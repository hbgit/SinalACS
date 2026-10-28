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

  /// O próximo cliente criado recusa o handshake TLS no primeiro connect.
  var recusarTls = false;

  setUp(() {
    backend = FakeAcsBackend();
    store = InMemoryDeviceCertificateStore();
    deviceIds = MemoryDeviceIdStore(deviceId);
    clientes = <_ClienteFalso>[];
    recusarTls = false;
  });

  MqttAlertFeed feed({void Function()? onDeviceWipeRequired}) => MqttAlertFeed(
        queue: AlertQueue(microAreaId: seedMicroAreaId),
        enroller: DeviceCertificateEnroller(store: store, backend: backend),
        deviceIds: deviceIds,
        onDeviceWipeRequired: onDeviceWipeRequired,
        loadCaCertificate: () async => utf8.encode('CA-SINTETICA'),
        clientFactory: (config) {
          final c = _ClienteFalso(config, recusarTls: recusarTls);
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

  test('servidor pede para tentar mais tarde: certificateUnavailable transitório com o motivo, sem falar de rede', () async {
    backend.issueCertificateFailure = const DeviceCertificateRetryLater(
        'a microárea da sessão mudou; a sessão precisa ser renovada antes de emitir o certificado deste aparelho');

    await expectLater(
      feed().start(microAreaId: seedMicroAreaId, acsId: seedAcsId),
      throwsA(isA<AlertFeedFailure>()
          .having((f) => f.kind, 'kind', AlertFeedFailureKind.certificateUnavailable)
          // Transitória: o painel mostra "Tentar agora" e retenta sozinho.
          .having((f) => f.transient, 'transient', isTrue)
          .having((f) => f.detail, 'detail', contains('renovada'))
          .having((f) => f.detail, 'detail', isNot(contains('rede')))),
    );
  });

  test('Keystore que falha na leitura: transitória com texto próprio, não "quando houver rede" (T5)', () async {
    final quebrado = _LeituraQuebrada();
    final f = MqttAlertFeed(
      queue: AlertQueue(microAreaId: seedMicroAreaId),
      enroller: DeviceCertificateEnroller(store: quebrado, backend: backend),
      deviceIds: deviceIds,
      loadCaCertificate: () async => utf8.encode('CA-SINTETICA'),
      clientFactory: (config) {
        final c = _ClienteFalso(config, recusarTls: false);
        clientes.add(c);
        return c;
      },
    );

    await expectLater(
      f.start(microAreaId: seedMicroAreaId, acsId: seedAcsId),
      throwsA(isA<AlertFeedFailure>()
          .having((f) => f.kind, 'kind', AlertFeedFailureKind.certificateUnavailable)
          .having((f) => f.transient, 'transient', isTrue)
          .having((f) => f.detail, 'detail', contains('armazenamento seguro'))
          .having((f) => f.detail, 'detail', isNot(contains('rede')))),
    );
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

  test('queda tlsRefused descarta o certificado, consulta o wipe e falha como certificateUnavailable transitório',
      () async {
    var consultouWipe = 0;
    final falhas = <AlertFeedFailure>[];
    final conexoes = <bool>[];
    final f = feed(onDeviceWipeRequired: () => consultouWipe++)
      ..onConnectionChanged = conexoes.add
      ..onFailure = falhas.add;
    await f.start(microAreaId: seedMicroAreaId, acsId: seedAcsId);
    expect(await store.read(acsId: seedAcsId, deviceId: deviceId), isNotNull);

    // O broker recusou o certificado na reconexão automática (revogado).
    clientes.single.cair(MqttDropReason.tlsRefused);
    await pumpEventQueue();

    expect(await store.read(acsId: seedAcsId, deviceId: deviceId), isNull, reason: 'o certificado recusado é descartado');
    expect(consultouWipe, 1, reason: 'a recusa pode ser a limpeza remota da #81');
    expect(falhas, hasLength(1));
    expect(falhas.single.kind, AlertFeedFailureKind.certificateUnavailable);
    expect(falhas.single.transient, isTrue, reason: 'o painel reinicia o feed, que reemite');
    expect(falhas.single.title, 'Sem certificado deste aparelho para a central');
    expect(f.isConnected, isFalse);
    expect(conexoes.last, isFalse);

    // O ReconnectSchedule do painel reinicia o feed: o enroller reemite.
    await f.start(microAreaId: seedMicroAreaId, acsId: seedAcsId);
    expect(backend.issueCertificateCount, 2);
    expect(utf8.decode(clientes.last.config.clientCertificate!),
        (await store.read(acsId: seedAcsId, deviceId: deviceId))!.certificatePem);
  });

  test('recusa TLS no primeiro connect descarta o certificado, consulta o wipe e falha como certificateUnavailable transitório',
      () async {
    var consultouWipe = 0;
    final falhas = <AlertFeedFailure>[];
    final f = feed(onDeviceWipeRequired: () => consultouWipe++)..onFailure = falhas.add;
    recusarTls = true;

    await expectLater(
      f.start(microAreaId: seedMicroAreaId, acsId: seedAcsId),
      throwsA(isA<AlertFeedFailure>()
          .having((e) => e.kind, 'kind', AlertFeedFailureKind.certificateUnavailable)
          .having((e) => e.transient, 'transient', isTrue)
          .having((e) => e.title, 'title', 'Sem certificado deste aparelho para a central')),
    );

    expect(await store.read(acsId: seedAcsId, deviceId: deviceId), isNull);
    expect(consultouWipe, 1);
    expect(falhas, isEmpty, reason: 'no primeiro connect a falha sobe pelo start(), não por onFailure');
    expect(f.isConnected, isFalse);
  });

  test('queda por outro erro da reconexão vira falha transitória sem descartar o certificado', () async {
    var consultouWipe = 0;
    final falhas = <AlertFeedFailure>[];
    final f = feed(onDeviceWipeRequired: () => consultouWipe++)..onFailure = falhas.add;
    await f.start(microAreaId: seedMicroAreaId, acsId: seedAcsId);

    clientes.single.cair(MqttDropReason.connectionError);
    await pumpEventQueue();

    expect(await store.read(acsId: seedAcsId, deviceId: deviceId), isNotNull);
    expect(consultouWipe, 0);
    expect(falhas.single.kind, AlertFeedFailureKind.unreachable);
    expect(falhas.single.transient, isTrue);
  });

  test('queda de um cliente já parado não chega ao painel', () async {
    final falhas = <AlertFeedFailure>[];
    final f = feed()..onFailure = falhas.add;
    await f.start(microAreaId: seedMicroAreaId, acsId: seedAcsId);
    f.stop();

    clientes.single.cair(MqttDropReason.tlsRefused);
    await pumpEventQueue();

    expect(falhas, isEmpty);
    expect(await store.read(acsId: seedAcsId, deviceId: deviceId), isNotNull);
  });
}

/// Cliente MQTT que não abre socket: registra a configuração e "conecta".
class _ClienteFalso implements MqttSecureClient {
  _ClienteFalso(this.config, {this.recusarTls = false});

  @override
  final SecureMqttConfig config;
  final bool recusarTls;

  bool connected = false;
  void Function(bool connected)? _onConnectionChanged;
  void Function(MqttDropReason reason)? _onDrop;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect({
    required void Function(ReceivedMqttAlert alert) onAlert,
    void Function(bool connected)? onConnectionChanged,
    void Function(MqttDropReason reason)? onDrop,
  }) async {
    if (recusarTls) throw const MqttTlsRefused(HandshakeException('CERTIFICATE_REVOKED'));
    _onConnectionChanged = onConnectionChanged;
    _onDrop = onDrop;
    connected = true;
    onConnectionChanged?.call(true);
  }

  /// O contrato de [MqttSecureClient.connect]: já desconectado, avisa
  /// `onConnectionChanged(false)` e depois `onDrop`.
  void cair(MqttDropReason reason) {
    connected = false;
    _onConnectionChanged?.call(false);
    _onDrop?.call(reason);
  }

  @override
  void disconnect() => connected = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Keystore cuja leitura falha (T5).
class _LeituraQuebrada extends InMemoryDeviceCertificateStore {
  @override
  Future<StoredDeviceCertificate?> read({required String acsId, required String deviceId}) async =>
      throw StateError('Keystore indisponível');
}
