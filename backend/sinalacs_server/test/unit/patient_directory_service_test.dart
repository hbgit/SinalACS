import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_directory_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// UUIDs sintéticos do seed de desenvolvimento.
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _otherMicroAreaId = '00000000-0000-4000-8000-000000000099';

const _acs = AuthenticatedUser(
  id: _acsId,
  role: UserRole.acs,
  microAreaId: _microAreaId,
  deviceId: 'acs-device-001',
);

const _patientId = '00000000-0000-4000-8000-000000000005';
const _patient = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

class FakePatientDirectoryStore implements PatientDirectoryStore {
  FakePatientDirectoryStore(this.byMicroArea);

  final Map<String, List<PatientDirectoryEntry>> byMicroArea;
  final List<String> queriedMicroAreas = <String>[];

  /// `patientId` → última lista gravada por [updateChronicConditions].
  final Map<String, List<String>> updatedConditions = <String, List<String>>{};

  @override
  Future<List<PatientDirectoryEntry>> listByMicroArea(String microAreaId) async {
    queriedMicroAreas.add(microAreaId);
    return byMicroArea[microAreaId] ?? const [];
  }

  @override
  Future<PatientDirectoryEntry?> findById(String patientId) async {
    for (final entries in byMicroArea.values) {
      for (final entry in entries) {
        if (entry.patientId == patientId) return entry;
      }
    }
    return null;
  }

  @override
  Future<void> updateChronicConditions({
    required String patientId,
    required List<String> conditions,
  }) async {
    updatedConditions[patientId] = conditions;
  }
}

/// Trilha de auditoria em memória, no mesmo molde de
/// `visit_sync_service_test.dart`.
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
  late FakePatientDirectoryStore store;
  late FakeAuditTrail audit;
  late PatientDirectoryService service;

  final pacientesDaArea = [
    const PatientDirectoryEntry(
      patientId: '00000000-0000-4000-8000-000000000005',
      name: 'Fulano de Tal',
      isChronic: true,
      chronicConditions: ['hipertensão'],
    ),
    const PatientDirectoryEntry(
      patientId: '00000000-0000-4000-8000-000000000006',
      name: 'Ciclana da Silva',
      isChronic: false,
      chronicConditions: [],
    ),
  ];

  setUp(() {
    store = FakePatientDirectoryStore({
      _microAreaId: pacientesDaArea,
      _otherMicroAreaId: const [
        PatientDirectoryEntry(
          patientId: '00000000-0000-4000-8000-000000000009',
          name: 'Paciente de Outra Área',
          isChronic: false,
          chronicConditions: [],
        ),
      ],
    });
    audit = FakeAuditTrail();
    service = PatientDirectoryService(store: store, audit: audit);
  });

  test('devolve só os pacientes da microárea do ACS', () async {
    final result = await service.listForAcs(_acs);

    expect(result, hasLength(2));
    expect(result.map((p) => p.patientId), containsAll([
      '00000000-0000-4000-8000-000000000005',
      '00000000-0000-4000-8000-000000000006',
    ]));
    expect(store.queriedMicroAreas, [_microAreaId]);
  });

  test('recusa quando o papel não é ACS', () async {
    const patient = AuthenticatedUser(
      id: '00000000-0000-4000-8000-000000000001',
      role: UserRole.patient,
      microAreaId: _microAreaId,
      deviceId: 'patient-device-001',
    );

    expect(
      () => service.listForAcs(patient),
      throwsA(isA<StateError>()),
    );
  });

  test('recusa quando o ACS não tem microárea', () async {
    const acsSemArea = AuthenticatedUser(
      id: _acsId,
      role: UserRole.acs,
      microAreaId: null,
      deviceId: 'acs-device-001',
    );

    expect(
      () => service.listForAcs(acsSemArea),
      throwsA(isA<StateError>()),
    );
  });

  test('o resultado não carrega dado além de nome e condições crônicas', () async {
    // Minimização (spec/lgpd_design.md:364): a visita de rotina só precisa de
    // nome e condições crônicas para escolher o paciente. `MicroAreaPatient`
    // não declara `emergencyContact` nem qualquer outro campo — a asserção é
    // no próprio construtor: se um campo a mais fosse adicionado ao modelo,
    // este teste continuaria passando sem avisar, então o que prova
    // minimização aqui é a ausência do campo no `.spy.yaml`, não este teste.
    final result = await service.listForAcs(_acs);

    expect(result.first.patientId, isNotEmpty);
    expect(result.first.name, isNotEmpty);
  });

  test('a leitura grava uma linha de auditoria sem enumerar os pacientes', () async {
    await service.listForAcs(_acs);

    expect(audit.events, hasLength(1));
    final event = audit.events.single;
    expect(event.actionType, 'read');
    expect(event.resourceType, 'patient_directory');
    expect(event.result, 'granted');
    expect(event.userId, _acsId);
    // Enumerar os pacientes lidos AQUI recriaria o prontuário dentro do
    // próprio log de auditoria — por isso o evento não carrega `resourceId`.
    expect(event.resourceId, isNull);
  });

  test('uma trilha de auditoria fora do ar não impede a listagem', () async {
    audit = FakeAuditTrail(failOnRecord: true);
    service = PatientDirectoryService(store: store, audit: audit);

    final result = await service.listForAcs(_acs);

    expect(result, hasLength(2));
  });

  group('myChronicConditions', () {
    test('devolve as condições do próprio paciente autenticado', () async {
      final result = await service.myChronicConditions(_patient);

      expect(result, ['hipertensão']);
    });

    test('devolve lista vazia quando não há linha para o id do token', () async {
      const semLinha = AuthenticatedUser(
        id: '00000000-0000-4000-8000-000000000123',
        role: UserRole.patient,
        microAreaId: _microAreaId,
        deviceId: 'patient-device-002',
      );

      expect(await service.myChronicConditions(semLinha), isEmpty);
    });

    test('recusa quando o papel não é paciente', () {
      expect(
        () => service.myChronicConditions(_acs),
        throwsA(isA<StateError>()),
      );
    });

    test('não exige microárea (INV-05 escopa pelo próprio id, não território)', () async {
      const semArea = AuthenticatedUser(
        id: _patientId,
        role: UserRole.patient,
        microAreaId: null,
        deviceId: 'patient-device-001',
      );

      expect(await service.myChronicConditions(semArea), ['hipertensão']);
    });

    test('a leitura grava uma linha de auditoria', () async {
      await service.myChronicConditions(_patient);

      expect(audit.events, hasLength(1));
      final event = audit.events.single;
      expect(event.actionType, 'read');
      expect(event.resourceType, 'patient_profile');
      expect(event.result, 'granted');
      expect(event.userId, _patientId);
    });
  });

  group('updateMyChronicConditions', () {
    test('grava a lista no store com o id do TOKEN, nunca de parâmetro', () async {
      await service.updateMyChronicConditions(_patient, conditions: ['asma', 'diabetes']);

      expect(store.updatedConditions[_patientId], ['asma', 'diabetes']);
    });

    test('recusa quando o papel não é paciente', () {
      expect(
        () => service.updateMyChronicConditions(_acs, conditions: ['asma']),
        throwsA(isA<StateError>()),
      );
      expect(store.updatedConditions, isEmpty);
    });

    test('a escrita grava uma linha de auditoria', () async {
      await service.updateMyChronicConditions(_patient, conditions: ['asma']);

      expect(audit.events, hasLength(1));
      final event = audit.events.single;
      expect(event.actionType, 'write');
      expect(event.resourceType, 'patient_profile');
      expect(event.result, 'granted');
      expect(event.userId, _patientId);
    });

    test('uma trilha de auditoria fora do ar não impede a gravação', () async {
      audit = FakeAuditTrail(failOnRecord: true);
      service = PatientDirectoryService(store: store, audit: audit);

      await service.updateMyChronicConditions(_patient, conditions: ['asma']);

      expect(store.updatedConditions[_patientId], ['asma']);
    });
  });
}
