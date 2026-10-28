import 'dart:async';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:sinalacs_server/src/application/devices/device_certificate_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_connection_settings.dart';

/// Derruba a sessão MQTT aberta de um aparelho (#94).
///
/// A CRL só vale no próximo handshake (I2): a sessão de um aparelho revogado
/// seguiria viva — e, na troca de microárea, lendo o território antigo — até
/// cair sozinha. O backend conecta ao broker com o MESMO client id do aparelho
/// (clean session) e o broker encerra a sessão anterior (takeover do MQTT
/// 3.1.1, §3.1.4-2); o backend então desconecta. Na reconexão, o aparelho
/// revogado é recusado pela CRL.
///
/// Mesmo `SecurityContext` do despachante de alertas ([mqttSecurityContext]):
/// aos olhos do broker é o `backend`. Melhor esforço: a falha vira uma linha de
/// log só com o tipo do erro (nunca o client id, que carrega o id do ACS) e
/// [kick] nunca lança — o corte duro é a CRL.
class MqttSessionKicker implements SessionKicker {
  MqttSessionKicker({required AppConfig config, void Function(String line)? log})
    : _config = config,
      _log = log ?? stderr.writeln;

  final AppConfig _config;
  final void Function(String line) _log;

  /// O client id do aparelho. **O app usa a mesma string**
  /// (`deviceClientId` em `apps/acs/lib/.../mqtt_secure_client.dart`).
  static String clientIdFor({required String acsId, required String deviceId}) =>
      deviceMqttClientId(acsId: acsId, deviceId: deviceId);

  @override
  Future<void> kick(
    String clientId, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final fim = Completer<void>();
    MqttServerClient? client;
    // Uma linha por chamada: um erro tardio do socket já desconectado não
    // repete o registro.
    void registrar(Object error) {
      if (fim.isCompleted) return;
      _log('Falha ao derrubar a sessão MQTT de um aparelho (${error.runtimeType}).');
      fim.complete();
    }

    // Zona própria derivada da raiz, como a do despachante (#56): um erro
    // assíncrono do socket não sobe para a zona da requisição.
    unawaited(Zone.root
        .fork(
          specification: ZoneSpecification(
            handleUncaughtError: (self, parent, zone, error, stack) =>
                registrar(error),
          ),
        )
        .run(() async {
          try {
            final broker = parseMqttBroker(_config.mqttBroker);
            final c = client =
                MqttServerClient.withPort(broker.host, clientId, broker.port)
                  ..keepAlivePeriod = 0
                  ..secure = _config.mqttUseTls
                  ..autoReconnect = false
                  ..logging(on: false)
                  ..connectionMessage = MqttConnectMessage()
                      .withClientIdentifier(clientId)
                      .startClean();
            final contexto = mqttSecurityContext(_config);
            if (contexto != null) c.securityContext = contexto;
            await c
                .connect(_config.mqttUsername ?? 'backend', _config.mqttPassword)
                .timeout(timeout);
            if (c.connectionStatus?.state != MqttConnectionState.connected) {
              throw const SocketException('CONNACK não recebido');
            }
            if (!fim.isCompleted) fim.complete();
          } catch (error) {
            registrar(error);
          } finally {
            try {
              client?.disconnect();
            } catch (_) {
              // Já registrado; desconectar é só limpeza.
            }
          }
        }));
    await fim.future;
  }
}
