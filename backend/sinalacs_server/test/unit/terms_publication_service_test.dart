import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show consentPolicyVersion;
import 'package:sinalacs_server/src/application/patients/terms_publication_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

const _placeholder = '[TEXTO PLACEHOLDER]';

AuthenticatedUser _user(UserRole role, {String id = 'u-1'}) =>
    AuthenticatedUser(id: id, role: role, microAreaId: null, deviceId: 'dev-1');

class _RecordingAudit extends AuditTrail {
  final events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);

  List<String> get dump => [
        for (final e in events)
          '${e.userId}|${e.actionType}|${e.resourceType}|${e.resourceId}|${e.result}',
      ];
}

class _ThrowingAudit extends AuditTrail {
  var calls = 0;

  @override
  Future<void> record(AuditEvent event) async {
    calls++;
    throw StateError('auditoria fora do ar');
  }
}

class _FakeStore implements TermsVersionStore {
  final rows = <String, TermsVersionSnapshot>{};
  var _seq = 0;

  @override
  Future<String> insertDraft({
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required String createdBy,
    required DateTime createdAt,
  }) async {
    final id = '00000000-0000-4000-8000-${(++_seq).toString().padLeft(12, '0')}';
    rows[id] = TermsVersionSnapshot(
      id: id,
      version: version,
      summary: summary,
      effectiveFrom: effectiveFrom,
      createdAt: createdAt,
    );
    return id;
  }

  @override
  Future<TermsVersionSnapshot?> findById(String id) async => rows[id];

  @override
  Future<bool> versionExists(String version) async =>
      rows.values.any((r) => r.version == version);

  @override
  Future<bool> markReviewed(String id, {required String reviewedBy, required DateTime at}) async {
    final r = rows[id];
    if (r == null || r.legallyReviewedAt != null || r.publishedAt != null) return false;
    rows[id] = _copy(r, reviewedAt: at, reviewedBy: reviewedBy);
    return true;
  }

  @override
  Future<bool> markPublished(String id, {required String publishedBy, required DateTime at}) async {
    final r = rows[id];
    if (r == null || r.legallyReviewedAt == null || r.publishedAt != null) return false;
    rows[id] = _copy(r, publishedAt: at, publishedBy: publishedBy);
    return true;
  }

  @override
  Future<List<TermsVersionSnapshot>> list() async => rows.values.toList();

  @override
  Future<TermsVersionSnapshot?> currentPublished(DateTime now) async {
    final c = rows.values
        .where((r) => r.publishedAt != null && r.effectiveFrom.isAfter(now))
        .toList()
      ..sort((a, b) => b.publishedAt!.compareTo(a.publishedAt!));
    return c.isEmpty ? null : c.first;
  }

  TermsVersionSnapshot _copy(
    TermsVersionSnapshot r, {
    DateTime? reviewedAt,
    String? reviewedBy,
    DateTime? publishedAt,
    String? publishedBy,
  }) =>
      TermsVersionSnapshot(
        id: r.id,
        version: r.version,
        summary: r.summary,
        effectiveFrom: r.effectiveFrom,
        createdAt: r.createdAt,
        legallyReviewedAt: reviewedAt ?? r.legallyReviewedAt,
        legallyReviewedBy: reviewedBy ?? r.legallyReviewedBy,
        publishedAt: publishedAt ?? r.publishedAt,
        publishedBy: publishedBy ?? r.publishedBy,
      );
}

void main() {
  late _FakeStore store;
  late _RecordingAudit audit;
  late DateTime now;
  late TermsPublicationService service;
  final admin = _user(UserRole.admin, id: 'adm-1');

  setUp(() {
    store = _FakeStore();
    audit = _RecordingAudit();
    now = DateTime.utc(2099, 1, 1, 12);
    service = TermsPublicationService(store: store, audit: audit, clock: () => now);
  });

  Future<TermsVersionSnapshot> draft({String version = '2099.1', int days = 20}) =>
      service.draft(admin,
          version: version,
          summary: _placeholder,
          effectiveFrom: now.add(Duration(days: days)));

  test('publicar sem revisão jurídica: recusa e audita denied_not_reviewed', () async {
    final d = await draft();
    await expectLater(service.publish(admin, d.id), throwsA(isA<AdminInvalidRequestException>()));
    expect(audit.events.last.result, 'denied_not_reviewed');
    expect(audit.events.last.resourceType, 'terms_version');
    expect(audit.events.last.resourceId, d.id);
    expect(store.rows[d.id]!.publishedAt, isNull);
  });

  test('vigência a menos de 15 dias da publicação: recusa', () async {
    final d = await draft();
    await service.markReviewed(admin, d.id);
    now = d.effectiveFrom.subtract(const Duration(days: 15)).add(const Duration(seconds: 1));
    await expectLater(service.publish(admin, d.id), throwsA(isA<AdminInvalidRequestException>()));
    expect(audit.events.last.result, 'denied_notice_period');
    expect(store.rows[d.id]!.publishedAt, isNull);
  });

  test('vigência exatamente 15 dias após a publicação: aceita e audita published', () async {
    final d = await draft();
    await service.markReviewed(admin, d.id);
    now = d.effectiveFrom.subtract(const Duration(days: 15));
    final p = await service.publish(admin, d.id);
    expect(p.publishedAt, now);
    expect(p.publishedBy, 'adm-1');
    expect(audit.events.last.result, 'published');
    expect(audit.events.last.resourceId, d.id);
  });

  for (final role in [UserRole.coordinator, UserRole.acs, UserRole.patient]) {
    test('papel $role: rascunhar, revisar, publicar e listar dão denied_role', () async {
      final d = await draft();
      final u = _user(role, id: 'x-1');
      final before = audit.events.length;
      await expectLater(
          service.draft(u, version: '2099.2', summary: _placeholder, effectiveFrom: now.add(const Duration(days: 20))),
          throwsA(isA<StateError>()));
      await expectLater(service.markReviewed(u, d.id), throwsA(isA<StateError>()));
      await expectLater(service.publish(u, d.id), throwsA(isA<StateError>()));
      await expectLater(service.list(u), throwsA(isA<StateError>()));
      final denied = audit.events.skip(before).toList();
      expect(denied, hasLength(4));
      expect(denied.map((e) => e.result).toSet(), {'denied_role'});
      expect(denied.every((e) => e.resourceType == 'terms_version'), isTrue);
      expect(store.rows, hasLength(1));
      expect(store.rows[d.id]!.legallyReviewedAt, isNull);
    });
  }

  test('negação com id que não é UUID grava resourceId nulo', () async {
    await expectLater(service.publish(_user(UserRole.acs), 'não-uuid'), throwsA(isA<StateError>()));
    expect(audit.events.last.resourceId, isNull);
  });

  test('versão igual à vigente (consentPolicyVersion) é recusada no rascunho', () async {
    await expectLater(
      service.draft(admin,
          version: consentPolicyVersion,
          summary: _placeholder,
          effectiveFrom: now.add(const Duration(days: 20))),
      throwsA(isA<AdminInvalidRequestException>()),
    );
    expect(store.rows, isEmpty);
  });

  test('versão duplicada é recusada com mensagem própria', () async {
    await draft();
    await expectLater(
      draft(),
      throwsA(isA<AdminInvalidRequestException>()
          .having((e) => e.message, 'message', 'Já existe uma versão com este número.')),
    );
  });

  test('versão vazia e resumo vazio ou acima de 280 são recusados', () async {
    final eff = now.add(const Duration(days: 20));
    await expectLater(service.draft(admin, version: '  ', summary: _placeholder, effectiveFrom: eff),
        throwsA(isA<AdminInvalidRequestException>()));
    await expectLater(service.draft(admin, version: 'v', summary: '  ', effectiveFrom: eff),
        throwsA(isA<AdminInvalidRequestException>()));
    await expectLater(
        service.draft(admin, version: 'v', summary: 'x' * 281, effectiveFrom: eff),
        throwsA(isA<AdminInvalidRequestException>()));
    final ok = await service.draft(admin, version: 'v', summary: 'x' * 280, effectiveFrom: eff);
    expect(ok.summary.length, 280);
  });

  test('rascunho com vigência no passado é recusado; com 14 dias é aceito', () async {
    await expectLater(
      service.draft(admin,
          version: '2099.1', summary: _placeholder, effectiveFrom: now.subtract(const Duration(seconds: 1))),
      throwsA(isA<AdminInvalidRequestException>()),
    );
    final d = await draft(days: 14);
    await service.markReviewed(admin, d.id);
    await expectLater(service.publish(admin, d.id), throwsA(isA<AdminInvalidRequestException>()));
    expect(audit.events.last.result, 'denied_notice_period');
  });

  test('revisar de novo ou revisar versão publicada: recusa e não sobrescreve', () async {
    final d = await draft();
    final r = await service.markReviewed(admin, d.id);
    now = now.add(const Duration(hours: 1));
    await expectLater(service.markReviewed(_user(UserRole.admin, id: 'adm-2'), d.id),
        throwsA(isA<AdminInvalidRequestException>()));
    expect(store.rows[d.id]!.legallyReviewedAt, r.legallyReviewedAt);
    expect(store.rows[d.id]!.legallyReviewedBy, 'adm-1');
    await service.publish(admin, d.id);
    await expectLater(service.markReviewed(admin, d.id), throwsA(isA<AdminInvalidRequestException>()));
  });

  test('publicar de novo uma versão já publicada é recusado', () async {
    final d = await draft();
    await service.markReviewed(admin, d.id);
    final p = await service.publish(admin, d.id);
    now = now.add(const Duration(hours: 1));
    await expectLater(service.publish(admin, d.id), throwsA(isA<AdminInvalidRequestException>()));
    expect(store.rows[d.id]!.publishedAt, p.publishedAt);
  });

  test('versão inexistente: Versão não encontrada', () async {
    await expectLater(
      service.publish(admin, '00000000-0000-4000-8000-0000000000ff'),
      throwsA(isA<AdminInvalidRequestException>()
          .having((e) => e.message, 'message', 'Versão não encontrada.')),
    );
  });

  test('nova publicação enquanto outra ainda não vigente substitui a anterior (uma só agenda)', () async {
    final a = await draft(version: '2099.1', days: 20);
    await service.markReviewed(admin, a.id);
    await service.publish(admin, a.id);
    expect((await store.currentPublished(now))!.id, a.id);

    now = now.add(const Duration(hours: 1));
    final b = await draft(version: '2099.2', days: 30);
    await service.markReviewed(admin, b.id);
    await service.publish(admin, b.id);
    expect((await store.currentPublished(now))!.id, b.id);
  });

  test('auditoria: dump completo e sem resumo/texto', () async {
    final d = await draft();
    await service.markReviewed(admin, d.id);
    await service.publish(admin, d.id);
    await service.list(admin);
    expect(audit.dump, [
      'adm-1|write|terms_version|${d.id}|drafted',
      'adm-1|write|terms_version|${d.id}|reviewed',
      'adm-1|write|terms_version|${d.id}|published',
      'adm-1|read|terms_version|null|granted',
    ]);
    expect(audit.dump.join().contains('PLACEHOLDER'), isFalse);
  });

  group('auditoria fail-closed (record, nunca recordSafely)', () {
    late _ThrowingAudit broken;
    late TermsPublicationService svc;
    final falha = throwsA(
      isA<StateError>().having(
        (e) => e.message,
        'message',
        'auditoria fora do ar',
      ),
    );

    setUp(() {
      broken = _ThrowingAudit();
      svc = TermsPublicationService(
        store: store,
        audit: broken,
        clock: () => now,
      );
    });

    Future<TermsVersionSnapshot> seeded({bool reviewed = false}) async {
      final d = await draft();
      if (reviewed) await service.markReviewed(admin, d.id);
      return d;
    }

    test('draft: auditoria falha propaga o erro', () async {
      await expectLater(
        svc.draft(
          admin,
          version: '2099.9',
          summary: _placeholder,
          effectiveFrom: now.add(const Duration(days: 20)),
        ),
        falha,
      );
    });

    test('markReviewed: auditoria falha propaga o erro', () async {
      final d = await seeded();
      await expectLater(svc.markReviewed(admin, d.id), falha);
    });

    test(
      'publish: auditoria falha propaga o erro (sucesso e denied_not_reviewed)',
      () async {
        final d = await seeded();
        await expectLater(
          svc.publish(admin, d.id),
          falha,
        ); // denied_not_reviewed
        await service.markReviewed(admin, d.id);
        await expectLater(svc.publish(admin, d.id), falha); // published
      },
    );

    test(
      'negação por papel continua negando: erro da trilha sobe, nada é gravado',
      () async {
        final d = await seeded();
        await expectLater(
          svc.publish(_user(UserRole.coordinator), d.id),
          falha,
        );
        expect(store.rows[d.id]!.publishedAt, isNull);
        expect(broken.calls, 1);
      },
    );

    test('list: se a leitura não grava, o store NÃO é listado', () async {
      await seeded();
      final listados = <int>[];
      final spy = _ListSpy(store, () => listados.add(1));
      final s = TermsPublicationService(
        store: spy,
        audit: broken,
        clock: () => now,
      );
      await expectLater(s.list(admin), falha);
      expect(listados, isEmpty);
    });
  });
}

class _ListSpy implements TermsVersionStore {
  _ListSpy(this._i, this._onList);
  final _FakeStore _i;
  final void Function() _onList;

  @override
  Future<List<TermsVersionSnapshot>> list() {
    _onList();
    return _i.list();
  }

  @override
  Future<String> insertDraft({
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required String createdBy,
    required DateTime createdAt,
  }) => _i.insertDraft(
    version: version,
    summary: summary,
    effectiveFrom: effectiveFrom,
    createdBy: createdBy,
    createdAt: createdAt,
  );
  @override
  Future<TermsVersionSnapshot?> findById(String id) => _i.findById(id);
  @override
  Future<bool> versionExists(String v) => _i.versionExists(v);
  @override
  Future<bool> markReviewed(
    String id, {
    required String reviewedBy,
    required DateTime at,
  }) => _i.markReviewed(id, reviewedBy: reviewedBy, at: at);
  @override
  Future<bool> markPublished(
    String id, {
    required String publishedBy,
    required DateTime at,
  }) => _i.markPublished(id, publishedBy: publishedBy, at: at);
  @override
  Future<TermsVersionSnapshot?> currentPublished(DateTime n) =>
      _i.currentPublished(n);
}
