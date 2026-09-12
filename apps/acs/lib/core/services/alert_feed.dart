import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';

/// Liga o broker à [AlertQueue].
///
/// É a única peça que sabe montar a configuração MQTT a partir da sessão: o
/// tópico depende da microárea do ACS autenticado, então não dá para fixá-lo em
/// tempo de compilação.
abstract class AlertFeed {
  Future<void> start({required String microAreaId, required String acsId});

  void stop();

  bool get isConnected;

  /// Notificado a cada mudança de estado da conexão, inclusive depois de
  /// [start] já ter retornado — é o que mantém o chip do cabeçalho honesto
  /// quando a conexão cai e volta sozinha (`autoReconnect`).
  ///
  /// Campo mutável, não parâmetro de construtor: quem monta o [AlertFeed]
  /// (os `feedBuilder` de teste) não precisa mudar para o dono do widget
  /// poder assinar depois.
  abstract void Function(bool connected)? onConnectionChanged;
}

/// Por que o ACS não está recebendo alertas.
enum AlertFeedFailureKind {
  /// O binário foi compilado sem `SINALACS_MQTT_PASSWORD`.
  missingPassword,

  /// Falta o certificado da CA nos assets (`scripts/dev/sync_dev_ca.sh`).
  missingCaAsset,

  /// O broker respondeu e recusou (credencial, identificador, indisponível).
  refused,

  /// Não foi possível chegar ao broker.
  unreachable,
}

/// Falha ao assinar o tópico de alertas, já classificada.
///
/// [title] e [detail] vão direto para o banner do painel; [cause] existe só
/// para o log e **nunca** chega à tela. Nenhum dos três carrega credencial.
///
/// Antes tudo isto virava a mesma frase — "Sem conexão com a central de
/// alertas" —, então senha errada, certificado ausente e broker fora do ar
/// eram indistinguíveis, inclusive para quem depura.
class AlertFeedFailure implements Exception {
  const AlertFeedFailure(
    this.kind, {
    required this.title,
    required this.detail,
    this.cause,
    this.transient = false,
  });

  final AlertFeedFailureKind kind;
  final String title;
  final String detail;
  final Object? cause;

  /// Se vale a pena tentar de novo sozinho, sem intervenção humana.
  ///
  /// `missingPassword`/`missingCaAsset` exigem recompilar; `refused` herda o
  /// veredito do CONNACK; `unreachable` é sempre transitória — falta de rede
  /// é o caso comum de um ACS em campo.
  final bool transient;

  @override
  String toString() => '${kind.name}: $title';
}

class MqttAlertFeed implements AlertFeed {
  MqttAlertFeed({
    required this.queue,
    this.onConnectionChanged,
  });

  final AlertQueue queue;

  @override
  void Function(bool connected)? onConnectionChanged;

  MqttSecureClient? _client;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> start({
    required String microAreaId,
    required String acsId,
  }) async {
    // Desliga qualquer conexão anterior antes de abrir outra. Sem isto, uma
    // segunda chamada a start() (a nova retentativa) sobrescreveria _client e
    // deixaria o cliente antigo órfão, fora do alcance de stop()/dispose().
    stop();

    // Antes de abrir qualquer socket: este binário tem senha? Sem isto, um app
    // compilado sem `--dart-define` gastava o timeout do broker para depois
    // dizer "sem conexão", escondendo que o problema estava na compilação.
    if (BackendConfig.mqttPasswordMissing) {
      throw const AlertFeedFailure(
        AlertFeedFailureKind.missingPassword,
        title: 'Este aplicativo foi compilado sem a senha do broker de alertas.',
        detail: 'Nenhum alerta será recebido até o aplicativo ser recompilado.',
      );
    }

    // A CA é asset gitignored, copiado por scripts/dev/sync_dev_ca.sh.
    final ByteData caCertificate;
    try {
      caCertificate = await rootBundle.load(BackendConfig.mqttCaAsset);
    } catch (error) {
      throw AlertFeedFailure(
        AlertFeedFailureKind.missingCaAsset,
        title: 'Falta o certificado da central neste aplicativo.',
        detail: 'Sem ele a conexão segura não pode ser verificada.',
        cause: error,
      );
    }

    final client = MqttSecureClient(
      config: SecureMqttConfig(
        brokerHost: BackendConfig.mqttHost,
        port: BackendConfig.mqttPort,
        // Estável por ACS: é o que permite ao broker restaurar a sessão
        // persistente e reentregar o que chegou enquanto o aparelho estava
        // offline. Um id aleatório aqui descartaria esses alertas.
        clientId: 'sinalacs-acs-$acsId',
        topic: alertTopicFor(microAreaId),
        username: BackendConfig.mqttUsername,
        password: BackendConfig.mqttPassword,
        caCertificate: caCertificate.buffer.asUint8List(),
      ),
    );

    try {
      await client.connect(
        onAlert: (alert) => queue.upsert(PrioritizedAlert.fromMqtt(alert)),
        onConnectionChanged: (connected) {
          _connected = connected;
          onConnectionChanged?.call(connected);
        },
      );
    } on MqttConnectionRefused catch (error) {
      throw AlertFeedFailure(
        AlertFeedFailureKind.refused,
        title: error.message,
        detail: 'Novos alertas não estão chegando.',
        cause: error,
        transient: error.transient,
      );
    } catch (error) {
      throw AlertFeedFailure(
        AlertFeedFailureKind.unreachable,
        title: 'Sem conexão com a central de alertas.',
        detail: 'Novos alertas podem não estar chegando.',
        cause: error,
        transient: true,
      );
    }

    _client = client;
    _connected = client.isConnected;
    onConnectionChanged?.call(_connected);
  }

  @override
  void stop() {
    _client?.disconnect();
    _client = null;
    _connected = false;
  }
}
