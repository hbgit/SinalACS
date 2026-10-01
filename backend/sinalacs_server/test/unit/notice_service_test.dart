import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/notices/notice_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/push/gorush_client.dart';
import 'package:test/test.dart';

const _microAreaId = '00000000-0000-4000-8000-000000000003';

const _acs = AuthenticatedUser(
  id: '00000000-0000-4000-8000-000000000002',
  role: UserRole.acs,
  microAreaId: _microAreaId,
  deviceId: 'acs-device-001',
);

const _patient = AuthenticatedUser(
  id: '00000000-0000-4000-8000-000000000001',
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

class _FakeRecipientStore implements NoticeRecipientStore {
  List<PushTarget> targets = const [
    PushTarget(token: 'tok-a', platform: 'android'),
    PushTarget(token: 'tok-b', platform: 'ios'),
  ];
  String? lastMicroAreaId;
  bool? lastChronicOnly;
  final deleted = <String>[];
  Object? deleteFailure;

  @override
  Future<List<PushTarget>> consentedTargets({
    required String microAreaId,
    required bool chronicOnly,
  }) async {
    lastMicroAreaId = microAreaId;
    lastChronicOnly = chronicOnly;
    return targets;
  }

  @override
  Future<int> deleteTokens(List<String> tokens) async {
    final failure = deleteFailure;
    if (failure != null) throw failure;
    deleted.addAll(tokens);
    return tokens.length;
  }
}

class _FakeSender implements PushSender {
  int calls = 0;
  PushMessage? lastMessage;
  List<PushTarget>? lastTargets;
  PushSendReport report = const PushSendReport(accepted: 2, invalidTokens: []);
  PushGatewayException? failure;

  @override
  Future<PushSendReport> send(PushMessage message, List<PushTarget> targets) async {
    calls++;
    lastMessage = message;
    lastTargets = targets;
    final f = failure;
    if (f != null) throw f;
    return report;
  }
}

class _FakeAudit extends AuditTrail {
  final events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

void main() {
  late _FakeRecipientStore store;
  late _FakeSender sender;
  late _FakeAudit audit;
  late NoticeService service;

  setUp(() {
    store = _FakeRecipientStore();
    sender = _FakeSender();
    audit = _FakeAudit();
    service = NoticeService(store: store, sender: sender, audit: audit);
  });

  test('só ACS envia; paciente é recusado sem chamar o provedor', () async {
    await expectLater(
      service.sendSegmented(_patient, title: 't', message: 'm', audience: 'everyone'),
      throwsA(isA<StateError>()),
    );
    expect(sender.calls, 0);
  });

  test('a consulta usa a microárea do token e o filtro de crônicos', () async {
    await service.sendSegmented(_acs, title: 'Vacina', message: 'Amanhã.', audience: 'chronic');
    expect(store.lastMicroAreaId, _microAreaId);
    expect(store.lastChronicOnly, isTrue);

    await service.sendSegmented(_acs, title: 'Vacina', message: 'Amanhã.', audience: 'everyone');
    expect(store.lastChronicOnly, isFalse);
  });

  test('sem destinatário consentido: 0 enviados, sem chamar o provedor', () async {
    store.targets = const [];
    final r = await service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone');
    expect((r.recipients, r.accepted), (0, 0));
    expect(sender.calls, 0);
  });

  test('o payload não leva dado do paciente, só título, mensagem e tela', () async {
    await service.sendSegmented(_acs, title: ' Vacina ', message: ' Amanhã. ', audience: 'everyone');
    expect(sender.lastMessage!.title, 'Vacina');
    expect(sender.lastMessage!.body, 'Amanhã.');
    expect(sender.lastMessage!.data, {'screen': 'notices'});
    expect(sender.lastTargets, hasLength(2));
  });

  test('devolve destinatários e aceitos', () async {
    final r = await service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone');
    expect((r.recipients, r.accepted), (2, 2));
  });

  test('tokens inválidos devolvidos pelo provedor são apagados', () async {
    sender.report = const PushSendReport(accepted: 1, invalidTokens: ['tok-b']);
    await service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone');
    expect(store.deleted, ['tok-b']);
  });

  test('falha do Gorush vira erro tipado e não audita "enviado"', () async {
    sender.failure = const PushGatewayException('fora do ar');
    await expectLater(
      service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone'),
      throwsA(isA<NoticeDeliveryException>()),
    );
    expect(audit.events.where((e) => e.result == 'granted'), isEmpty);
  });

  test('timeout: o resultado é desconhecido, a mensagem manda conferir antes de reenviar', () async {
    sender.failure = const PushGatewayException('demorou', outcomeUnknown: true);
    await expectLater(
      service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone'),
      throwsA(isA<NoticeDeliveryException>()
          .having((e) => e.message, 'message', contains('Confira antes de reenviar'))),
    );
    expect(audit.events.single.result, 'unknown');
  });

  test('falha ao apagar tokens inválidos não vira erro: o envio já aconteceu', () async {
    sender.report = const PushSendReport(accepted: 1, invalidTokens: ['tok-b']);
    store.deleteFailure = StateError('banco fora do ar');
    final r = await service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone');
    expect((r.recipients, r.accepted), (2, 1));
    expect(audit.events.single.result, 'granted');
  });

  test('nenhum aceito: não audita "granted"', () async {
    sender.report = const PushSendReport(accepted: 0, invalidTokens: []);
    final r = await service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone');
    expect(r.accepted, 0);
    expect(audit.events.single.result, 'not_delivered');
  });

  test('sem Gorush configurado o envio é recusado com mensagem clara', () async {
    final off = NoticeService(store: store, sender: null, audit: audit);
    await expectLater(
      off.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone'),
      throwsA(isA<NoticeDeliveryException>()),
    );
  });

  test('título e mensagem vazios, longos demais ou público desconhecido são recusados', () async {
    for (final a in [
      ('', 'm', 'everyone'),
      ('t', '  ', 'everyone'),
      ('x' * (noticeTitleMaxLength + 1), 'm', 'everyone'),
      ('t', 'x' * (noticeMessageMaxLength + 1), 'everyone'),
      ('t', 'm', 'todos'),
    ]) {
      await expectLater(
        service.sendSegmented(_acs, title: a.$1, message: a.$2, audience: a.$3),
        throwsA(isA<DataRightsException>()),
        reason: '$a',
      );
    }
    expect(sender.calls, 0);
  });

  test('o texto da mensagem nunca vai para a trilha de auditoria', () async {
    await service.sendSegmented(_acs, title: 'Vacina', message: 'texto sigiloso', audience: 'everyone');
    expect(audit.events, isNotEmpty);
    for (final e in audit.events) {
      expect('${e.resourceType} ${e.resourceId} ${e.result}'.contains('sigiloso'), isFalse);
      expect(e.resourceType, 'community_notice');
    }
  });
}
