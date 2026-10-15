import 'dart:async';
import 'dart:io';

import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart';

/// Sonda de diagnóstico (#56, Tarefa 6b): dispatcher com TLS + mTLS contra o
/// broker real, dentro de `runZonedGuarded` com marcador de zona. Grava em
/// `PROBE_OUT` (fora do repositório) o tipo do erro, o errno, a pilha completa
/// e a zona em que o erro chegou. Segredos só vêm do ambiente; nada é impresso.
///
/// `PROBE_MODE=guarded` (padrão): o `connect` roda dentro da zona guardada.
/// `PROBE_MODE=root`: o `connect` roda na zona raiz e só `main` é guardado
/// (mostra se um erro nascido fora da zona escapa dela).
Future<void> main() async {
  final out = File(Platform.environment['PROBE_OUT'] ?? '/dev/stderr');
  void log(String s) =>
      out.writeAsStringSync('${DateTime.now().toIso8601String()} $s\n',
          mode: FileMode.append);
  final env = Platform.environment;
  final config = AppConfig(
    mqttBroker: env['MQTT_BROKER'] ?? 'localhost:8883',
    jwtSecret: 'test-secret',
    auditChainSecret: 'test-audit-chain-secret',
    healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
    cpfHashPepper: AppConfig.developmentCpfHashPepper,
    smsGateway: 'log',
    mqttUsername: env['MQTT_USERNAME'],
    mqttPassword: env['MQTT_PASSWORD'],
    mqttUseTls: true,
    mqttCaCertificatePath: env['MQTT_CA_CERT_PATH'],
    mqttClientCertificatePath: env['MQTT_CLIENT_CERT_PATH'],
    mqttClientKeyPath: env['MQTT_CLIENT_KEY_PATH'],
    appEnv: 'development',
    enableDevLogin: true,
  );
  final mode = env['PROBE_MODE'] ?? 'guarded';
  final done = Completer<void>();

  Future<void> body() async {
    final d = MqttAlertDispatcher(config: config);
    await d.connect();
    stdout.writeln('PRONTO');
    log('PRONTO zona=${Zone.current[#marker]}');
  }

  runZonedGuarded(() {
    if (mode == 'root') {
      Zone.root.run(() => body());
    } else {
      body();
    }
  }, (error, stack) {
    var errno = '';
    if (error is SocketException) errno = ' errno=${error.osError?.errorCode}';
    log('ERRO tipo=${error.runtimeType}$errno zonaDoHandler='
        '${Zone.current[#marker]} msg=${error.toString().split('\n').first}');
    log('PILHA(vazia=${stack == StackTrace.empty}):\n$stack');
  },
      zoneValues: {#marker: 'ZONA_PROBE'},
      zoneSpecification: ZoneSpecification(
        // Chamado quando um Future/Stream é completado com erro: a pilha SÍNCRONA
        // neste ponto mostra quem originou o erro (o erro em si chega sem pilha).
        errorCallback: (self, parent, zone, error, stackTrace) {
          if (error is SocketException) {
            log('ORIGEM errorCallback tipo=${error.runtimeType} '
                'errno=${error.osError?.errorCode} '
                'zonaCorrente=${Zone.current[#marker]} '
                'pilhaOriginal=${stackTrace == null ? "null" : "presente"}\n'
                '${StackTrace.current}');
          }
          return parent.errorCallback(zone, error, stackTrace);
        },
      ));
  await done.future;
}
