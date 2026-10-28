import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/device_certificate_enroller.dart';
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
  /// Falta o certificado da CA nos assets (`scripts/dev/sync_dev_ca.sh`).
  missingCaAsset,

  /// Este aparelho ainda não tem certificado de cliente válido para o broker
  /// (#94) e não deu para pedir um ao servidor (sem rede). Transitória: o
  /// certificado é emitido na próxima tentativa com rede.
  certificateUnavailable,

  /// O broker respondeu e recusou (credencial, identificador, indisponível),
  /// ou o servidor recusou emitir o certificado deste aparelho.
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
/// alertas" —, então credencial recusada, certificado ausente e broker fora
/// do ar eram indistinguíveis, inclusive para quem depura.
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
  /// `missingCaAsset` exige recompilar; `refused` herda o veredito do CONNACK
  /// (ou é a recusa do servidor ao certificado); `certificateUnavailable` e
  /// `unreachable` são transitórias — falta de rede é o caso comum de um ACS
  /// em campo.
  final bool transient;

  @override
  String toString() => '${kind.name}: $title';
}

/// Feed sem certificado por aparelho montado (sem id da instalação para
/// pedi-lo): o app foi montado sem `deviceIds`, como os testes de widget que
/// não injetam um feed. Falha na hora, sem abrir socket, e não é retentada.
class UnconfiguredAlertFeed implements AlertFeed {
  UnconfiguredAlertFeed({this.onConnectionChanged});

  @override
  void Function(bool connected)? onConnectionChanged;

  @override
  bool get isConnected => false;

  @override
  Future<void> start({required String microAreaId, required String acsId}) async {
    throw const AlertFeedFailure(
      AlertFeedFailureKind.certificateUnavailable,
      title: 'Sem certificado deste aparelho para a central',
      detail: 'Este aplicativo foi montado sem o identificador do aparelho.',
    );
  }

  @override
  void stop() {}
}

class MqttAlertFeed implements AlertFeed {
  MqttAlertFeed({
    required this.queue,
    required DeviceCertificateEnroller enroller,
    required DeviceIdStore deviceIds,
    this.onConnectionChanged,
    void Function()? onDeviceWipeRequired,
    Future<List<int>> Function()? loadCaCertificate,
    MqttSecureClient Function(SecureMqttConfig config)? clientFactory,
  })  : _enroller = enroller,
        _deviceIds = deviceIds,
        _onDeviceWipeRequired = onDeviceWipeRequired,
        _loadCaCertificate = loadCaCertificate ?? _loadCaAsset,
        _clientFactory = clientFactory ?? ((config) => MqttSecureClient(config: config));

  final AlertQueue queue;
  final DeviceCertificateEnroller _enroller;
  final DeviceIdStore _deviceIds;

  /// O servidor recusou a emissão com pedido de limpeza (#81): o app passa o
  /// `RemoteWipeCoordinator.check` daqui, que pergunta pelo pedido e apaga.
  final void Function()? _onDeviceWipeRequired;
  final Future<List<int>> Function() _loadCaCertificate;
  final MqttSecureClient Function(SecureMqttConfig config) _clientFactory;

  /// A CA é asset gitignored, copiado por scripts/dev/sync_dev_ca.sh.
  static Future<List<int>> _loadCaAsset() async =>
      (await rootBundle.load(BackendConfig.mqttCaAsset)).buffer.asUint8List();

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

    final List<int> caCertificate;
    try {
      caCertificate = await _loadCaCertificate();
    } catch (error) {
      throw AlertFeedFailure(
        AlertFeedFailureKind.missingCaAsset,
        title: 'Falta o certificado da central neste aplicativo.',
        detail: 'Sem ele a conexão segura não pode ser verificada.',
        cause: error,
      );
    }

    // Certificado de CLIENTE por aparelho (#94): emitido pelo backend para o
    // par gerado aqui, guardado no Keystore. Nenhuma senha nem certificado
    // compartilhado viaja no binário.
    final String deviceId;
    final String certificatePem;
    final String privateKeyPem;
    try {
      deviceId = await _deviceIds.readOrCreate();
      final cert = await _enroller.ensure(acsId: acsId, deviceId: deviceId, microAreaId: microAreaId);
      certificatePem = cert.certificatePem;
      privateKeyPem = cert.privateKeyPem;
    } on DeviceCertificateUnavailable catch (error) {
      throw AlertFeedFailure(
        AlertFeedFailureKind.certificateUnavailable,
        title: 'Sem certificado deste aparelho para a central',
        detail: 'Será emitido quando houver rede.',
        cause: error,
        transient: true,
      );
    } on DeviceWipeRequiredFailure catch (error) {
      _onDeviceWipeRequired?.call();
      throw AlertFeedFailure(
        AlertFeedFailureKind.refused,
        title: error.message,
        detail: 'Nenhum alerta será recebido neste aparelho.',
        cause: error,
      );
    } on BackendFailure catch (error) {
      // Recusa do servidor (papel, território, CSR): insistir não muda nada.
      throw AlertFeedFailure(
        AlertFeedFailureKind.refused,
        title: 'A central recusou o certificado deste aparelho.',
        detail: error.message,
        cause: error,
      );
    } catch (error) {
      // Keystore indisponível ou falha local inesperada: tenta de novo.
      throw AlertFeedFailure(
        AlertFeedFailureKind.certificateUnavailable,
        title: 'Sem certificado deste aparelho para a central',
        detail: 'Será emitido quando houver rede.',
        cause: error,
        transient: true,
      );
    }

    final client = _clientFactory(
      SecureMqttConfig(
        brokerHost: BackendConfig.mqttHost,
        port: BackendConfig.mqttPort,
        // Estável por ACS e por aparelho: é o que permite ao broker restaurar
        // a sessão persistente e reentregar o que chegou enquanto o aparelho
        // estava offline, e ao servidor derrubar a sessão de um aparelho
        // revogado. Um id aleatório aqui descartaria esses alertas.
        clientId: deviceClientId(acsId: acsId, deviceId: deviceId),
        topic: alertTopicFor(microAreaId),
        caCertificate: caCertificate,
        clientCertificate: utf8.encode(certificatePem),
        clientPrivateKey: utf8.encode(privateKeyPem),
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
