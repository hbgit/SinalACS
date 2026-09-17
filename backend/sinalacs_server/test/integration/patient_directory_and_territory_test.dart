import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_chain_reader.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
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
const _unknownPatientId = '00000000-0000-4000-8000-0000000000ee';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      // Hex de 64 caracteres: HealthDataCipher decodifica byte a byte
      // para montar a chave AES-256 (ver AppConfig).
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
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
    await encryptedPatient(
      id: _patientInAreaId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: true,
      chronicConditions: const ['hipertensão'],
    ),
    await encryptedPatient(
      id: _patientOutsideAreaId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
    ),
  ]);
}

VisitSyncEntry _visitEntry({
  required String localId,
  required String patientId,
  required int version,
}) =>
    VisitSyncEntry(
      localId: localId,
      patientId: patientId,
      scheduledAt: DateTime.utc(2026, 9, 12, 9),
      status: 'realizada',
      riskLevelBefore: RiskLevel.green,
      notes: const {},
      version: version,
    );

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

    test('patients.listMicroArea rejeita token inválido', () async {
      await _seed(sessionBuilder.build());

      await expectLater(
        endpoints.patients.listMicroArea(
          sessionBuilder,
          accessToken: 'token-invalido',
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('duas escritas reais na trilha ficam encadeadas e passam na verificação',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      // Primeira escrita: leitura do diretório (granted).
      await endpoints.patients.listMicroArea(sessionBuilder, accessToken: login.accessToken);
      // Segunda escrita: recusa territorial no sync.
      await endpoints.visits.sync(
        sessionBuilder,
        accessToken: login.accessToken,
        visits: [
          VisitSyncEntry(
            localId: '00000000-0000-4000-8000-0000000000b2',
            patientId: _patientOutsideAreaId,
            scheduledAt: DateTime.utc(2026, 9, 12, 9),
            status: 'realizada',
            riskLevelBefore: RiskLevel.green,
            notes: const {},
            version: 0,
          ),
        ],
      );

      final rows = await AuditLog.db.find(session, orderBy: (t) => t.sequence);
      expect(rows, hasLength(2));
      expect(rows[0].sequence, 1);
      expect(rows[1].sequence, 2);
      expect(rows[1].previousHash, rows[0].entryHash);

      final verifier = AuditChainVerifier(
        reader: OrmAuditChainReader(session: () => session),
        secret: 'test-audit-chain-secret',
      );
      final result = await verifier.verify();

      expect(result.ok, isTrue);
      expect(result.checked, 2);
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

      expect(results.single.syncStatus, SyncStatus.rejected);

      final rows = await Visit.db.find(session);
      expect(rows, isEmpty, reason: 'nada deveria ser gravado para paciente fora do território');

      final audited = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('visit') & t.result.equals('denied_territory'),
      );
      expect(audited, hasLength(1));
      expect(audited.single.resourceId, UuidValue.fromString(_patientOutsideAreaId));
    });

    test('visits.sync devolve lista vazia quando não há visitas', () async {
      await _seed(sessionBuilder.build());
      final login =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      final results = await endpoints.visits.sync(
        sessionBuilder,
        accessToken: login.accessToken,
        visits: const [],
      );

      expect(results, isEmpty);
    });

    test('visits.sync expõe synced, conflict e error pelo endpoint', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final login =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      final synced = await endpoints.visits.sync(
        sessionBuilder,
        accessToken: login.accessToken,
        visits: [
          _visitEntry(
            localId: '00000000-0000-4000-8000-0000000000c1',
            patientId: _patientInAreaId,
            version: 0,
          ),
        ],
      );
      expect(synced.single.syncStatus, SyncStatus.synced);
      expect(synced.single.serverVersion, 1);

      final update = await endpoints.visits.sync(
        sessionBuilder,
        accessToken: login.accessToken,
        visits: [
          _visitEntry(
            localId: '00000000-0000-4000-8000-0000000000c1',
            patientId: _patientInAreaId,
            version: 0,
          ),
        ],
      );
      expect(update.single.syncStatus, SyncStatus.synced);
      expect(update.single.serverVersion, 2);

      final conflict = await endpoints.visits.sync(
        sessionBuilder,
        accessToken: login.accessToken,
        visits: [
          _visitEntry(
            localId: '00000000-0000-4000-8000-0000000000c1',
            patientId: _patientInAreaId,
            version: 0,
          ),
        ],
      );
      expect(conflict.single.syncStatus, SyncStatus.conflict);
      expect(conflict.single.serverVersion, 2);

      final error = await endpoints.visits.sync(
        sessionBuilder,
        accessToken: login.accessToken,
        visits: [
          _visitEntry(
            localId: '00000000-0000-4000-8000-0000000000c2',
            patientId: _unknownPatientId,
            version: 0,
          ),
        ],
      );
      expect(error.single.syncStatus, SyncStatus.error);
      expect(error.single.message, contains('paciente não encontrado'));

      final rows = await Visit.db.find(session);
      expect(rows, hasLength(1), reason: 'somente a visita válida deve persistir');
    });

    test(
        'visits.pull devolve só visitas da própria microárea, alteradas após '
        'since, contra Postgres real', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final referencia = DateTime.utc(2026, 9, 16, 12);

      // As notas viajam cifradas na coluna (RNF03): o fixture monta o par
      // `notesEncrypted`/`notesKeyVersion` com a mesma chave de
      // desenvolvimento que o `AlertRuntime` usa aqui.
      final notasVazias = await encryptedVisitNotes(const {});

      Visit visita({
        required String localId,
        required String patientId,
        required DateTime syncAt,
      }) =>
          Visit(
            patientId: UuidValue.fromString(patientId),
            acsId: UuidValue.fromString(_acsId),
            scheduledAt: DateTime.utc(2026, 9, 12, 9),
            completedAt: DateTime.utc(2026, 9, 12, 10),
            status: 'realizada',
            riskLevelBefore: RiskLevel.green,
            riskLevelAfter: RiskLevel.green,
            notesEncrypted: notasVazias.ciphertextBase64,
            notesKeyVersion: notasVazias.keyVersion,
            syncStatus: SyncStatus.synced,
            localId: UuidValue.fromString(localId),
            syncAt: syncAt,
            version: 1,
          );

      // Grava direto no banco (via seed), não via `visits.sync` — o objetivo
      // aqui é provar o filtro de leitura, não o fluxo de gravação.
      final visitaRecenteMesmaArea = await Visit.db.insertRow(
        session,
        visita(
          localId: '00000000-0000-4000-8000-0000000000f1',
          patientId: _patientInAreaId,
          syncAt: referencia.add(const Duration(hours: 1)),
        ),
      );
      await Visit.db.insertRow(
        session,
        visita(
          localId: '00000000-0000-4000-8000-0000000000f2',
          patientId: _patientInAreaId,
          syncAt: referencia.subtract(const Duration(hours: 1)),
        ),
      );
      await Visit.db.insertRow(
        session,
        visita(
          localId: '00000000-0000-4000-8000-0000000000f3',
          patientId: _patientOutsideAreaId,
          syncAt: referencia.add(const Duration(hours: 1)),
        ),
      );

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final result = await endpoints.visits.pull(
        sessionBuilder,
        accessToken: login.accessToken,
        since: referencia,
      );

      expect(result.map((e) => e.localId), [visitaRecenteMesmaArea.localId.uuid]);
    });

    test('visits.pull rejeita quem não é ACS territorializado', () async {
      await _seed(sessionBuilder.build());
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      await expectLater(
        endpoints.visits.pull(
          sessionBuilder,
          accessToken: login.accessToken,
          since: DateTime.utc(2026, 9, 16, 12),
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });
  });
}
