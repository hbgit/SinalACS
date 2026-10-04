import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_chain_reader.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// `visits.syncLegacy` (D4 do plano 2026-10-03) contra Postgres real: prova o
/// que o store falso do teste unitário não alcança — `visits.acsId` nulo de
/// verdade na coluna (FK opcional para `acs`), o enum `authorship` persistido,
/// `originDeviceId`, a transação do endpoint e a linha real em `audit_logs`.
///
/// A sessão do ACS é só o TRANSPORTE: a visita legada foi gravada no aparelho
/// antes de existir dono por visita, e a autoria é desconhecida.
///
/// Dados sintéticos. O ACS é o do `developmentLogin` (ids fixos do seed).
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _otherMicroAreaId = '00000000-0000-4000-8000-000000000099';
const _ubsId = '00000000-0000-4000-8000-000000000004';

const _patientInAreaId = '00000000-0000-4000-8000-000000000005';
const _patientOutsideAreaId = '00000000-0000-4000-8000-000000000009';

const _deviceId = 'aparelho-legado-01';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      smsGateway: 'log',
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
      name: 'UBS Legado',
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
      cpfHash: 'development-patient-legado-05',
      name: 'Paciente Sintético',
      birthDate: DateTime.utc(1975, 3, 10),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(_patientOutsideAreaId),
      cpfHash: 'development-patient-legado-09',
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
      emergencyContact: 'Contato sintético',
      isChronic: false,
    ),
    await encryptedPatient(
      id: _patientOutsideAreaId,
      emergencyContact: 'Contato sintético',
      isChronic: false,
    ),
  ]);
}

VisitSyncEntry _entry({
  required String localId,
  String patientId = _patientInAreaId,
  int version = 0,
  String status = 'realizada',
}) =>
    VisitSyncEntry(
      localId: localId,
      patientId: patientId,
      scheduledAt: DateTime.utc(2026, 9, 12, 9),
      completedAt: DateTime.utc(2026, 9, 12, 10),
      status: status,
      riskLevelBefore: RiskLevel.green,
      notes: const {'campo': 'sem intercorrências'},
      version: version,
      arrivalMethod: ArrivalMethod.manual,
    );

Future<Visit?> _row(Session session, String localId) => Visit.db.findFirstRow(
      session,
      where: (t) => t.localId.equals(UuidValue.fromString(localId)),
    );

void main() {
  withServerpod('Dado o envio de visitas legadas (autoria desconhecida)',
      (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    Future<String> acsToken() async =>
        (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

    test('syncLegacy grava authorship legacyUnclaimed, acsId nulo e originDeviceId', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      const localId = '00000000-0000-4000-8000-0000000001a1';

      final results = await endpoints.visits.syncLegacy(
        sessionBuilder,
        accessToken: await acsToken(),
        deviceId: _deviceId,
        visits: [_entry(localId: localId)],
      );

      expect(results.single.syncStatus, SyncStatus.synced);
      expect(results.single.serverVersion, 1);
      final row = (await _row(session, localId))!;
      expect(row.authorship, VisitAuthorship.legacyUnclaimed);
      expect(row.originDeviceId, _deviceId);
      expect(row.syncAt, isNotNull);
    });

    test('syncLegacy NÃO grava o transportador como autor (acsId permanece nulo)', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      const localId = '00000000-0000-4000-8000-0000000001a2';
      final token = await acsToken();

      await endpoints.visits.syncLegacy(sessionBuilder,
          accessToken: token, deviceId: _deviceId, visits: [_entry(localId: localId)]);
      await endpoints.visits.syncLegacy(sessionBuilder,
          accessToken: token,
          deviceId: _deviceId,
          visits: [_entry(localId: localId, version: 0, status: 'paciente ausente')]);

      final row = (await _row(session, localId))!;
      expect(row.acsId, isNull);
      expect(row.authorship, VisitAuthorship.legacyUnclaimed);
      expect(row.status, 'paciente ausente');
      expect(row.version, 2);
    });

    test('visita legada de paciente de OUTRA microárea: rejected, nada gravado', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final results = await endpoints.visits.syncLegacy(
        sessionBuilder,
        accessToken: await acsToken(),
        deviceId: _deviceId,
        visits: [
          _entry(
            localId: '00000000-0000-4000-8000-0000000001a3',
            patientId: _patientOutsideAreaId,
          ),
        ],
      );

      expect(results.single.syncStatus, SyncStatus.rejected);
      expect(await Visit.db.find(session), isEmpty);
      final denied = await AuditLog.db.find(
        session,
        where: (t) =>
            t.resourceType.equals('visit_legacy') & t.result.equals('denied_territory'),
      );
      expect(denied, hasLength(1));
      expect(denied.single.userId, UuidValue.fromString(_acsId));
    });

    test('mesmo localId reenviado: idempotente (synced, sem duplicar, sem mudar autoria)',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);
      const localId = '00000000-0000-4000-8000-0000000001a4';
      final token = await acsToken();

      await endpoints.visits.syncLegacy(sessionBuilder,
          accessToken: token, deviceId: _deviceId, visits: [_entry(localId: localId)]);
      final retry = await endpoints.visits.syncLegacy(sessionBuilder,
          accessToken: token, deviceId: _deviceId, visits: [_entry(localId: localId, version: 1)]);

      expect(retry.single.syncStatus, SyncStatus.synced);
      expect(retry.single.serverVersion, 1);
      final rows = await Visit.db.find(session);
      expect(rows, hasLength(1));
      expect(rows.single.acsId, isNull);
      expect(rows.single.authorship, VisitAuthorship.legacyUnclaimed);
    });

    test(
        'localId que já existe como visita COM autor ACS: conflito/rejected, autoria original '
        'preservada', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      const localId = '00000000-0000-4000-8000-0000000001a5';
      final token = await acsToken();

      await endpoints.visits.sync(sessionBuilder,
          accessToken: token, visits: [_entry(localId: localId)]);
      final results = await endpoints.visits.syncLegacy(sessionBuilder,
          accessToken: token,
          deviceId: _deviceId,
          visits: [_entry(localId: localId, version: 1, status: 'paciente ausente')]);

      expect(results.single.syncStatus, SyncStatus.rejected);
      final row = (await _row(session, localId))!;
      expect(row.acsId, UuidValue.fromString(_acsId));
      expect(row.authorship, VisitAuthorship.acs);
      expect(row.originDeviceId, isNull);
      expect(row.status, 'realizada');
    });

    test('visits.sync comum NÃO reivindica uma visita legada (rejected)', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      const localId = '00000000-0000-4000-8000-0000000001a6';
      final token = await acsToken();

      await endpoints.visits.syncLegacy(sessionBuilder,
          accessToken: token, deviceId: _deviceId, visits: [_entry(localId: localId)]);
      final results = await endpoints.visits.sync(sessionBuilder,
          accessToken: token,
          visits: [_entry(localId: localId, version: 0, status: 'paciente ausente')]);

      expect(results.single.syncStatus, SyncStatus.rejected);
      final row = (await _row(session, localId))!;
      expect(row.acsId, isNull);
      expect(row.authorship, VisitAuthorship.legacyUnclaimed);
      expect(row.version, 1);
    });

    test(
        'papel diferente de acs, sem microárea ou conta inativa: StateError '
        '(AlertPermissionException no endpoint)', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final patient = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');
      await expectLater(
        endpoints.visits.syncLegacy(sessionBuilder,
            accessToken: patient.accessToken,
            deviceId: _deviceId,
            visits: [_entry(localId: '00000000-0000-4000-8000-0000000001a7')]),
        throwsA(isA<AlertPermissionException>()),
      );

      final semArea = AlertRuntime.instance.auth.issueToken(const AuthenticatedUser(
        id: _acsId,
        role: UserRole.acs,
        microAreaId: null,
        deviceId: 'acs-device-001',
      ));
      await expectLater(
        endpoints.visits.syncLegacy(sessionBuilder,
            accessToken: semArea,
            deviceId: _deviceId,
            visits: [_entry(localId: '00000000-0000-4000-8000-0000000001a8')]),
        throwsA(isA<AlertPermissionException>()),
      );

      final token = await acsToken();
      final acs = (await Acs.db.findById(session, UuidValue.fromString(_acsId)))!;
      await Acs.db.updateRow(session, acs.copyWith(active: false));
      await expectLater(
        endpoints.visits.syncLegacy(sessionBuilder,
            accessToken: token,
            deviceId: _deviceId,
            visits: [_entry(localId: '00000000-0000-4000-8000-0000000001a9')]),
        throwsA(isA<AlertPermissionException>()),
      );

      expect(await Visit.db.find(session), isEmpty);
    });

    test('cada lote gera audit_logs visit_legacy_sync com o transportador, sem conteúdo clínico',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);

      await endpoints.visits.syncLegacy(
        sessionBuilder,
        accessToken: await acsToken(),
        deviceId: _deviceId,
        visits: [
          _entry(localId: '00000000-0000-4000-8000-0000000001b1'),
          _entry(localId: '00000000-0000-4000-8000-0000000001b2'),
        ],
      );

      final rows = await AuditLog.db.find(
        session,
        where: (t) => t.result.equals('visit_legacy_sync'),
      );
      expect(rows, hasLength(1), reason: 'um evento por LOTE, não por visita');
      expect(rows.single.userId, UuidValue.fromString(_acsId));
      expect(rows.single.actionType, 'write');
      expect(rows.single.resourceType, 'visit_legacy');
      expect(rows.single.resourceId, isNull);

      final verifier = AuditChainVerifier(
        reader: OrmAuditChainReader(session: () => session),
        secret: 'test-audit-chain-secret',
      );
      expect((await verifier.verify()).ok, isTrue);
    });

    test('pull entrega a visita legada à microárea sem expor autor (campo acsId ausente)',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);
      const localId = '00000000-0000-4000-8000-0000000001c1';
      final token = await acsToken();

      await endpoints.visits.syncLegacy(sessionBuilder,
          accessToken: token, deviceId: _deviceId, visits: [_entry(localId: localId)]);
      final pulled = await endpoints.visits.pull(
        sessionBuilder,
        accessToken: token,
        since: DateTime.utc(2000),
      );

      expect(pulled.map((e) => e.localId), [localId]);
      expect(pulled.single.notes, {'campo': 'sem intercorrências'});
      final json = pulled.single.toJson();
      expect(json.containsKey('acsId'), isFalse);
      expect(json.containsKey('originDeviceId'), isFalse);
    });
  });
}
