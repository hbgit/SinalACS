import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, o que `patient_directory_service_test.dart` e
/// `visit_sync_service_test.dart` só provam com fakes: o JOIN em duas etapas
/// de `OrmPatientDirectoryStore` (patients → users, sem relação declarada
/// entre as tabelas), o `inSet` da consulta, e a escrita de verdade em
/// `audit_logs` — tabela que, antes deste PR, não tinha nenhum escritor.
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _otherMicroAreaId = '00000000-0000-4000-8000-000000000099';
const _ubsId = '00000000-0000-4000-8000-000000000004';

const _patientInAreaId = '00000000-0000-4000-8000-000000000005';
const _patientOutsideAreaId = '00000000-0000-4000-8000-000000000009';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: true,
    );

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Desenvolvimento',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insert(session, [
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
    MicroArea(
      id: UuidValue.fromString(_otherMicroAreaId),
      name: 'Microárea vizinha',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  ]);

  final now = DateTime.now().toUtc();
  await User.db.insert(session, [
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-acs',
      name: 'ACS de desenvolvimento',
      birthDate: DateTime.utc(1980),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(_patientInAreaId),
      cpfHash: 'development-patient-05',
      name: 'Fulano de Tal',
      birthDate: DateTime.utc(1975, 3, 10),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(_patientOutsideAreaId),
      cpfHash: 'development-patient-09',
      name: 'Paciente de Outra Área',
      birthDate: DateTime.utc(1970),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_otherMicroAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  ]);

  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'ACS-001',
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
  await Patient.db.insert(session, [
    Patient(
      id: UuidValue.fromString(_patientInAreaId),
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: true,
      chronicConditions: ['hipertensão'],
    ),
    Patient(
      id: UuidValue.fromString(_patientOutsideAreaId),
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
      chronicConditions: [],
    ),
  ]);
}

void main() {
  withServerpod('Dado o diretório de pacientes e a territorialização do sync',
      (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    test('patients.listMicroArea devolve só o paciente da microárea do ACS, via JOIN real',
        () async {
      await _seed(sessionBuilder.build());

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final result = await endpoints.patients.listMicroArea(
        sessionBuilder,
        accessToken: login.accessToken,
      );

      expect(result.map((p) => p.patientId), [_patientInAreaId]);
      expect(result.single.name, 'Fulano de Tal');
      expect(result.single.isChronic, isTrue);
      expect(result.single.chronicConditions, ['hipertensão']);
    });

    test('a leitura da lista grava uma linha real em audit_logs', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      await endpoints.patients.listMicroArea(sessionBuilder, accessToken: login.accessToken);

      final rows = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('patient_directory'),
      );
      expect(rows, hasLength(1));
      expect(rows.single.result, 'granted');
      expect(rows.single.userId, UuidValue.fromString(_acsId));
      // A trilha não guarda IP em claro — nem que seja o do harness de teste.
      expect(rows.single.ipHash, isNotEmpty);
    });

    test('visits.sync recusa e audita visita para paciente de outra microárea, contra Postgres real',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final results = await endpoints.visits.sync(
        sessionBuilder,
        accessToken: login.accessToken,
        visits: [
          VisitSyncEntry(
            localId: '00000000-0000-4000-8000-0000000000b1',
            patientId: _patientOutsideAreaId,
            scheduledAt: DateTime.utc(2026, 9, 12, 9),
            status: 'realizada',
            riskLevelBefore: RiskLevel.green,
            notes: const {},
            version: 0,
          ),
        ],
      );

      expect(results.single.syncStatus, SyncStatus.error);

      final rows = await Visit.db.find(session);
      expect(rows, isEmpty, reason: 'nada deveria ser gravado para paciente fora do território');

      final audited = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('visit') & t.result.equals('denied_territory'),
      );
      expect(audited, hasLength(1));
      expect(audited.single.resourceId, UuidValue.fromString(_patientOutsideAreaId));
    });
  });
}
