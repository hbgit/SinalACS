import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
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

class FakePatientDataOverviewStore implements PatientDataOverviewStore {
  FakePatientDataOverviewStore(this.byId);

  final Map<String, PatientDataSnapshot?> byId;
  final List<String> queriedIds = <String>[];

  @override
  Future<PatientDataSnapshot?> loadFor(String patientId) async {
    queriedIds.add(patientId);
    return byId[patientId];
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
  late FakePatientDataOverviewStore store;
  late FakeAuditTrail audit;
  late PatientDataOverviewService service;

  final snapshot = PatientDataSnapshot(
    name: 'Paciente de Teste',
    birthDate: DateTime.utc(1990, 1, 1),
    emergencyContact: 'Contato de teste',
    isChronic: true,
    chronicConditions: const ['hipertensão'],
    consents: [
      ConsentRecordSnapshot(
        purpose: 'healthDataProcessing',
        action: 'granted',
        version: '2026.1',
        timestamp: DateTime.utc(2026, 1, 1),
      ),
    ],
    riskHistory: [
      RiskEventSnapshot(
        source: 'triage',
        riskLevel: RiskLevel.yellow,
        recordedAt: DateTime.utc(2026, 2, 1),
      ),
    ],
  );

  setUp(() {
    store = FakePatientDataOverviewStore({_patientId: snapshot});
    audit = FakeAuditTrail();
    service = PatientDataOverviewService(store: store, audit: audit);
  });

  test('devolve o snapshot do próprio paciente autenticado', () async {
    final result = await service.myData(_patient);

    expect(result.name, 'Paciente de Teste');
    expect(result.chronicConditions, ['hipertensão']);
    expect(result.consents, hasLength(1));
    expect(result.riskHistory, hasLength(1));
    expect(store.queriedIds, [_patientId]);
  });

  test('recusa quando o papel não é paciente', () {
    expect(() => service.myData(_acs), throwsA(isA<StateError>()));
  });

  test('não exige microárea (INV-05 escopa pelo próprio id, não território)', () async {
    const semArea = AuthenticatedUser(
      id: _patientId,
      role: UserRole.patient,
      microAreaId: null,
      deviceId: 'patient-device-001',
    );

    final result = await service.myData(semArea);
    expect(result.name, 'Paciente de Teste');
  });

  test('lança quando o token carrega um id sem linha em patients', () async {
    store = FakePatientDataOverviewStore({_patientId: null});
    service = PatientDataOverviewService(store: store, audit: audit);

    expect(() => service.myData(_patient), throwsA(isA<StateError>()));
  });

  test('a leitura grava uma linha de auditoria', () async {
    await service.myData(_patient);

    expect(audit.events, hasLength(1));
    final event = audit.events.single;
    expect(event.actionType, 'read');
    expect(event.resourceType, 'patient_data_overview');
    expect(event.result, 'granted');
    expect(event.userId, _patientId);
  });

  test('uma trilha de auditoria fora do ar não impede a leitura', () async {
    audit = FakeAuditTrail(failOnRecord: true);
    service = PatientDataOverviewService(store: store, audit: audit);

    final result = await service.myData(_patient);
    expect(result.name, 'Paciente de Teste');
  });
}
