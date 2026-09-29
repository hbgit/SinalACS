import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/application/patients/data_subject_rights_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

const _patientId = '00000000-0000-4000-8000-000000000001';
const _microAreaId = '00000000-0000-4000-8000-000000000003';

const _patient = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

const _acs = AuthenticatedUser(
  id: '00000000-0000-4000-8000-000000000002',
  role: UserRole.acs,
  microAreaId: _microAreaId,
  deviceId: 'acs-device-001',
);

final _now = DateTime.utc(2026, 9, 28, 12);

class FakeDataSubjectRightsStore implements DataSubjectRightsStore {
  final consents = <ConsentLogEntry>[];
  final requests = <({String userId, DataSubjectRequestSnapshot snapshot})>[];
  var _nextId = 1;

  @override
  Future<String> recordConsent(ConsentLogEntry entry) async {
    consents.add(entry);
    return 'consentimento-${consents.length}';
  }

  @override
  Future<ConsentRecordSnapshot?> latestConsent(String userId, ConsentPurpose purpose) async {
    ConsentLogEntry? latest;
    for (final e in consents) {
      if (e.userId != userId || e.purpose != purpose) continue;
      if (latest == null || e.timestamp.isAfter(latest.timestamp)) latest = e;
    }
    return latest == null
        ? null
        : ConsentRecordSnapshot(
            purpose: latest.purpose.name,
            action: latest.action,
            version: latest.version,
            timestamp: latest.timestamp,
          );
  }

  @override
  Future<({DataSubjectRequestSnapshot request, bool created})> createDeletionRequestIfNoneOpen({
    required String userId,
    required DateTime createdAt,
    required DateTime dueAt,
  }) async {
    for (final r in requests.reversed) {
      if (r.userId == userId &&
          r.snapshot.type == DataSubjectRequestType.deletion &&
          r.snapshot.status == DataSubjectRequestStatus.open) {
        return (request: r.snapshot, created: false);
      }
    }
    final created = await createRequest(
      userId: userId,
      type: DataSubjectRequestType.deletion,
      details: null,
      createdAt: createdAt,
      dueAt: dueAt,
    );
    return (request: created, created: true);
  }

  @override
  Future<DataSubjectRequestSnapshot> createRequest({
    required String userId,
    required DataSubjectRequestType type,
    required String? details,
    required DateTime createdAt,
    required DateTime dueAt,
  }) async {
    final snapshot = DataSubjectRequestSnapshot(
      id: 'pedido-${_nextId++}',
      type: type,
      status: DataSubjectRequestStatus.open,
      details: details,
      createdAt: createdAt,
      dueAt: dueAt,
    );
    requests.add((userId: userId, snapshot: snapshot));
    return snapshot;
  }
}

class FakeAuditTrail extends AuditTrail {
  FakeAuditTrail({this.failOnRecord = false});

  final bool failOnRecord;
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async {
    if (failOnRecord) throw StateError('trilha de auditoria fora do ar');
    events.add(event);
  }
}

void main() {
  late FakeDataSubjectRightsStore store;
  late FakeAuditTrail audit;
  late DataSubjectRightsService service;

  setUp(() {
    store = FakeDataSubjectRightsStore();
    audit = FakeAuditTrail();
    service = DataSubjectRightsService(store: store, audit: audit, clock: () => _now);
  });

  group('acceptTermsOfUse (LGPD-RF18)', () {
    test('grava "granted" para termsOfUse com a versão vigente e audita', () async {
      final record = await service.acceptTermsOfUse(_patient);

      final entry = store.consents.single;
      expect(entry.userId, _patientId);
      expect(entry.purpose, ConsentPurpose.termsOfUse);
      expect(entry.action, 'granted');
      expect(entry.version, consentPolicyVersion);
      expect(entry.timestamp, _now);
      expect(record.purpose, 'termsOfUse');
      expect(record.action, 'granted');
      expect(audit.events.single.resourceType, 'consent_log');
    });

    test('só paciente aceita: ACS é recusado sem gravar nada', () async {
      await expectLater(service.acceptTermsOfUse(_acs), throwsA(isA<StateError>()));
      expect(store.consents, isEmpty);
      expect(audit.events, isEmpty);
    });

    test('aceitar de novo com o aceite vigente não grava nada', () async {
      await service.acceptTermsOfUse(_patient);
      final again = await service.acceptTermsOfUse(_patient);

      expect(store.consents, hasLength(1));
      expect(audit.events, hasLength(1));
      expect(again.action, 'granted');
      expect(again.version, consentPolicyVersion);
    });

    test('aceite de versão anterior não conta: grava de novo', () async {
      store.consents.add(ConsentLogEntry(
        userId: _patientId,
        purpose: ConsentPurpose.termsOfUse,
        action: 'granted',
        version: '2025.9',
        timestamp: _now.subtract(const Duration(days: 30)),
      ));

      await service.acceptTermsOfUse(_patient);

      expect(store.consents, hasLength(2));
      expect(store.consents.last.version, consentPolicyVersion);
    });
  });

  group('hasAcceptedCurrentTerms (LGPD-RF18)', () {
    ConsentLogEntry linha(String action, String version, int minutos,
            {ConsentPurpose purpose = ConsentPurpose.termsOfUse}) =>
        ConsentLogEntry(
          userId: _patientId,
          purpose: purpose,
          action: action,
          version: version,
          timestamp: _now.add(Duration(minutes: minutos)),
        );

    test('sem nenhuma linha de termsOfUse, não aceitou', () async {
      expect(await service.hasAcceptedCurrentTerms(_patient), isFalse);
      store.consents.add(linha('granted', consentPolicyVersion, 0, purpose: ConsentPurpose.localReminders));
      expect(await service.hasAcceptedCurrentTerms(_patient), isFalse);
    });

    test('aceite da versão vigente conta', () async {
      store.consents.add(linha('granted', consentPolicyVersion, 0));
      expect(await service.hasAcceptedCurrentTerms(_patient), isTrue);
    });

    test('aceite de versão anterior não conta', () async {
      store.consents.add(linha('granted', '2025.9', 0));
      expect(await service.hasAcceptedCurrentTerms(_patient), isFalse);
    });

    test('vale a linha mais recente, seja qual for a ordem em que foram gravadas', () async {
      store.consents.add(linha('granted', consentPolicyVersion, 5));
      store.consents.add(linha('granted', '2025.9', 0));
      expect(await service.hasAcceptedCurrentTerms(_patient), isTrue);
    });

    test('linha mais recente que não é "granted" não conta', () async {
      store.consents.add(linha('granted', consentPolicyVersion, 0));
      store.consents.add(linha('denied', consentPolicyVersion, 5));
      expect(await service.hasAcceptedCurrentTerms(_patient), isFalse);
    });

    test('só paciente consulta: ACS é recusado', () async {
      await expectLater(service.hasAcceptedCurrentTerms(_acs), throwsA(isA<StateError>()));
    });
  });

  group('updateConsent (LGPD-RF05)', () {
    test('a linha de auditoria aponta para a linha de consentimento gravada', () async {
      await service.updateConsent(_patient, purpose: ConsentPurpose.localReminders, granted: false);

      expect(audit.events.single.resourceId, 'consentimento-1');
    });

    test('revogar grava uma linha nova "denied", com a versão vigente e o relógio do servidor', () async {
      final record = await service.updateConsent(
        _patient,
        purpose: ConsentPurpose.localReminders,
        granted: false,
      );

      final entry = store.consents.single;
      expect(entry.userId, _patientId);
      expect(entry.purpose, ConsentPurpose.localReminders);
      expect(entry.action, 'denied');
      expect(entry.version, consentPolicyVersion);
      expect(entry.timestamp, _now);

      expect(record.purpose, 'localReminders');
      expect(record.action, 'denied');
      expect(record.timestamp, _now);
    });

    test('conceder de novo grava "granted"', () async {
      await service.updateConsent(_patient, purpose: ConsentPurpose.segmentedPush, granted: true);

      expect(store.consents.single.action, 'granted');
    });

    test('recusa mexer no consentimento obrigatório, em qualquer direção, sem gravar nada', () async {
      for (final granted in [false, true]) {
        await expectLater(
          service.updateConsent(
            _patient,
            purpose: ConsentPurpose.healthDataProcessing,
            granted: granted,
          ),
          throwsA(isA<DataRightsException>()),
        );
      }
      expect(store.consents, isEmpty);
      expect(audit.events, isEmpty);
    });

    test('recusa mexer no aceite do Termo de Uso pelo painel', () async {
      await expectLater(
        service.updateConsent(_patient, purpose: ConsentPurpose.termsOfUse, granted: false),
        throwsA(isA<DataRightsException>()),
      );
      expect(store.consents, isEmpty);
      expect(audit.events, isEmpty);
    });

    test('um ACS não altera consentimento de ninguém', () async {
      await expectLater(
        service.updateConsent(_acs, purpose: ConsentPurpose.localReminders, granted: false),
        throwsA(isA<StateError>()),
      );
      expect(store.consents, isEmpty);
    });

    test('grava uma linha de escrita em audit_logs', () async {
      await service.updateConsent(_patient, purpose: ConsentPurpose.localReminders, granted: false);

      final event = audit.events.single;
      expect(event.userId, _patientId);
      expect(event.actionType, 'write');
      expect(event.resourceType, 'consent_log');
      expect(event.result, 'granted');
    });

    test('não exige microárea: o escopo é o próprio titular', () async {
      const semArea = AuthenticatedUser(
        id: _patientId,
        role: UserRole.patient,
        microAreaId: null,
        deviceId: 'patient-device-001',
      );

      await service.updateConsent(semArea, purpose: ConsentPurpose.localReminders, granted: true);
      expect(store.consents, hasLength(1));
    });
  });

  group('requestDeletion (LGPD-RF08)', () {
    test('abre um pedido em análise com prazo de 15 dias', () async {
      final request = await service.requestDeletion(_patient);

      expect(request.type, DataSubjectRequestType.deletion);
      expect(request.status, DataSubjectRequestStatus.open);
      expect(request.details, isNull);
      expect(request.createdAt, _now);
      expect(request.dueAt, _now.add(const Duration(days: 15)));
      expect(store.requests.single.userId, _patientId);
    });

    test('pedir de novo com um pedido aberto devolve o mesmo, sem duplicar', () async {
      final first = await service.requestDeletion(_patient);
      final second = await service.requestDeletion(_patient);

      expect(second.id, first.id);
      expect(store.requests, hasLength(1));
      // A repetição também é auditada, com o resultado `repeated`.
      expect(audit.events, hasLength(2));
      expect(audit.events.last.resourceId, first.id);
      expect(audit.events.last.result, 'repeated');
    });

    test('o pedido novo vai para audit_logs com o id do pedido', () async {
      final request = await service.requestDeletion(_patient);

      final event = audit.events.single;
      expect(event.actionType, 'write');
      expect(event.resourceType, 'data_subject_request');
      expect(event.resourceId, request.id);
      expect(event.result, 'granted');
    });

    test('um ACS não pede exclusão em nome de ninguém', () async {
      await expectLater(service.requestDeletion(_acs), throwsA(isA<StateError>()));
      expect(store.requests, isEmpty);
    });

    test('uma trilha de auditoria fora do ar não impede o pedido', () async {
      service = DataSubjectRightsService(
        store: store,
        audit: FakeAuditTrail(failOnRecord: true),
        clock: () => _now,
      );

      final request = await service.requestDeletion(_patient);
      expect(request.status, DataSubjectRequestStatus.open);
    });
  });

  group('requestCorrection (LGPD-RF08)', () {
    test('grava o texto sem os espaços das pontas', () async {
      final request = await service.requestCorrection(
        _patient,
        details: '  Meu contato de emergência mudou.  ',
      );

      expect(request.type, DataSubjectRequestType.correction);
      expect(request.details, 'Meu contato de emergência mudou.');
      expect(request.dueAt, _now.add(const Duration(days: 15)));
    });

    test('um segundo pedido com outro aberto é pedido NOVO — o texto novo não se perde', () async {
      await service.requestCorrection(_patient, details: 'Contato errado.');
      final second = await service.requestCorrection(_patient, details: 'Nome com grafia errada.');

      expect(store.requests, hasLength(2));
      expect(second.details, 'Nome com grafia errada.');
    });

    test('texto vazio ou só espaços é recusado', () async {
      for (final details in ['', '   ', '\n\t']) {
        await expectLater(
          service.requestCorrection(_patient, details: details),
          throwsA(isA<DataRightsException>()),
        );
      }
      expect(store.requests, isEmpty);
    });

    test('aceita 500 caracteres e recusa 501', () async {
      await service.requestCorrection(_patient, details: 'a' * 500);
      await expectLater(
        service.requestCorrection(_patient, details: 'a' * 501),
        throwsA(isA<DataRightsException>()),
      );
      expect(store.requests, hasLength(1));
    });

    test('o texto do pedido nunca vai para audit_logs', () async {
      await service.requestCorrection(_patient, details: 'Tenho hipertensão, não diabetes.');

      final event = audit.events.single;
      expect(event.resourceType, 'data_subject_request');
      expect(event.resourceId, isNot(contains('hipertensão')));
      expect(event.result, 'granted');
    });

    test('um ACS não pede correção em nome de ninguém', () async {
      await expectLater(
        service.requestCorrection(_acs, details: 'Qualquer coisa.'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
