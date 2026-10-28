import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/device_certificate_store.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/device_certificate_enroller.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';
import 'package:sinalacs_acs/core/services/remote_wipe.dart';

import 'support/fakes.dart';

/// O feed MQTT do ACS com o certificado POR APARELHO (#94): nada de senha nem
/// de certificado compartilhado no binário. O broker é substituído por um
/// cliente falso que só registra a configuração; a CA vem de um carregador
/// injetado (o asset real é gitignorado). Ids sintéticos.
void main() {
  const deviceId = '00000000-0000-4000-8000-0000000000d1';

  late FakeAcsBackend backend;
  late InMemoryDeviceCertificateStore store;
  late MemoryDeviceIdStore deviceIds;
  late List<_ClienteFalso> clientes;

  setUp(() {
    backend = FakeAcsBackend();
    store = InMemoryDeviceCertificateStore();
    deviceIds = MemoryDeviceIdStore(deviceId);
    clientes = <_ClienteFalso>[];
  });

  MqttAlertFeed feed({void Function()? onDeviceWipeRequired}) => MqttAlertFeed(
        queue: AlertQueue(microAreaId: seedMicroAreaId),
        enroller: DeviceCertificateEnroller(store: store, backend: backend),
        deviceIds: deviceIds,
        onDeviceWipeRequired: onDeviceWipeRequired,
        loadCaCertificate: () async => utf8.encode('CA-SINTETICA'),
        clientFactory: (config) {
          final c = _ClienteFalso(config);
          clientes.add(c);
          return c;
        },
      );

  test('o feed pede o certificado ao enroller e monta o SecurityContext com ele (sem username/senha)', () async {
    await feed().start(microAreaId: seedMicroAreaId, acsId: seedAcsId);

    expect(backend.issueCertificateCount, 1);
    final guardado = (await store.read(acsId: seedAcsId, deviceId: deviceId))!;
    final config = clientes.single.config;
    expect(config.username, isNull);
    expect(config.password, isNull);
    expect(utf8.decode(config.clientCertificate!), guardado.certificatePem);
    expect(utf8.decode(config.clientPrivateKey!), guardado.privateKeyPem);
    expect(config.topic, alertTopicFor(seedMicroAreaId));
    expect(clientes.single.connected, isTrue);

    // O par é real: o `SecurityContext` só aceita a chave privada se ela casar
    // com a chave pública da folha (o BoringSSL confere). Sem CA aqui, de
    // propósito: a CA de teste não é PEM de verdade.
    final contexto = buildMqttSecurityContext(SecureMqttConfig(
      brokerHost: config.brokerHost,
      port: config.port,
      clientId: config.clientId,
      topic: config.topic,
      clientCertificate: config.clientCertificate,
      clientPrivateKey: config.clientPrivateKey,
    ));
    expect(contexto, isA<SecurityContext>());
  });

  test('client id é sinalacs-acs-<acsId>-<deviceId>', () async {
    // Cópia literal de `deviceMqttClientId` em
    // backend/sinalacs_server/lib/src/application/devices/device_certificate_service.dart
    // (usada por `MqttSessionKicker.clientIdFor` em
    // backend/sinalacs_server/lib/src/infrastructure/mqtt/mqtt_session_kicker.dart):
    //   'sinalacs-acs-$acsId-$deviceId'
    // O app não importa o servidor; se um dos dois mudar, a derrubada da
    // sessão do aparelho revogado deixa de achar o cliente.
    const esperado = 'sinalacs-acs-$seedAcsId-$deviceId';
    expect(deviceClientId(acsId: seedAcsId, deviceId: deviceId), esperado);

    await feed().start(microAreaId: seedMicroAreaId, acsId: seedAcsId);

    expect(clientes.single.config.clientId, esperado);
  });

  test('DeviceCertificateUnavailable vira AlertFeedFailureKind.certificateUnavailable transitório', () async {
    backend.issueCertificateFailure = const BackendFailure('Sem conexão com o servidor.');

    await expectLater(
      feed().start(microAreaId: seedMicroAreaId, acsId: seedAcsId),
      throwsA(isA<AlertFeedFailure>()
          .having((f) => f.kind, 'kind', AlertFeedFailureKind.certificateUnavailable)
          .having((f) => f.transient, 'transient', isTrue)
          .having((f) => f.title, 'title', 'Sem certificado deste aparelho para a central')
          .having((f) => f.detail, 'detail', 'Será emitido quando houver rede.')),
    );
    expect(clientes, isEmpty, reason: 'sem certificado, nenhum socket é aberto');
  });

  test('DeviceWipeRequiredFailure vira o fluxo da #81 (RemoteWipeCoordinator.check)', () async {
    backend.issueCertificateFailure = const DeviceWipeRequiredFailure('ordem-1');
    backend.pendingWipeOrderId = 'ordem-1';
    var apagou = 0;
    final coordenador = RemoteWipeCoordinator(
      backend: backend,
      deviceIds: deviceIds,
      journal: MemoryWipeJournal(),
      erase: () async {
        apagou++;
        await deviceIds.delete();
      },
    );
    Future<bool>? verificacao;

    await expectLater(
      feed(onDeviceWipeRequired: () => verificacao = coordenador.check())
          .start(microAreaId: seedMicroAreaId, acsId: seedAcsId),
      throwsA(isA<AlertFeedFailure>().having((f) => f.transient, 'transient', isFalse)),
    );

    expect(verificacao, isNotNull);
    expect(await verificacao, isTrue);
    expect(apagou, 1);
    expect(backend.pendingWipeQueries, [deviceId]);
    expect(backend.confirmedWipes, [(deviceId: deviceId, orderId: 'ordem-1')]);
    expect(clientes, isEmpty);
  });
}

/// Cliente MQTT que não abre socket: registra a configuração e "conecta".
class _ClienteFalso implements MqttSecureClient {
  _ClienteFalso(this.config);

  @override
  final SecureMqttConfig config;

  bool connected = false;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect({
    required void Function(ReceivedMqttAlert alert) onAlert,
    void Function(bool connected)? onConnectionChanged,
  }) async {
    connected = true;
    onConnectionChanged?.call(true);
  }

  @override
  void disconnect() => connected = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
