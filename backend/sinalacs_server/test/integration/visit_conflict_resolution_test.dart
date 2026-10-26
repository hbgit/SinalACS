import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real e pelo endpoint, o que o grupo
/// `resolveConflict` de `visit_sync_service_test.dart` prova com fakes (#79):
/// o conflito devolve a cópia do servidor, `visits.resolveConflict` grava em
/// compare-and-set sobre a versão vista, as notas voltam decifradas, a versão
/// vencida não grava e a recusa territorial é a mesma do `sync`.
const _acsId = '00000000-0000-4000-8000-000000000002';
const _acsOutraAreaId = '00000000-0000-4000-8000-000000000022';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _otherMicroAreaId = '00000000-0000-4000-8000-000000000099';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _patientId = '00000000-0000-4000-8000-000000000005';
const _localId = '00000000-0000-4000-8000-0000000000d1';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      telemetryPseudonymKey: AppConfig.developmentTelemetryPseudonymKey,
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
      id: UuidValue.fromString(_acsOutraAreaId),
      cpfHash: 'development-acs-22',
      name: 'ACS da microárea vizinha',
      birthDate: DateTime.utc(1982),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_otherMicroAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'development-patient-05',
      name: 'Paciente Sintético',
      birthDate: DateTime.utc(1975, 3, 10),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
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
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
    ),
  );
}

VisitSyncEntry _entry({
  required int version,
  String status = 'realizada',
  Map<String, String> notes = const {'campo': 'nota sintética inicial'},
}) =>
    VisitSyncEntry(
      localId: _localId,
      patientId: _patientId,
      scheduledAt: DateTime.utc(2026, 10, 16, 9),
      completedAt: DateTime.utc(2026, 10, 16, 10),
      status: status,
      riskLevelBefore: RiskLevel.green,
      riskLevelAfter: RiskLevel.green,
      notes: notes,
      version: version,
      arrivalMethod: ArrivalMethod.manual,
    );

void main() {
  withServerpod('Dada uma visita em conflito, visits.resolveConflict',
      (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    test(
        'resolve com a versão vista, recusa versão vencida e outro território, '
        'e grava conflict_resolved_local na trilha', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final token = login.accessToken;

      Future<VisitSyncResult> sync(VisitSyncEntry e) async => (await endpoints.visits.sync(
            sessionBuilder,
            accessToken: token,
            visits: [e],
          ))
              .single;

      // Cria (v1) e leva a v3 pela regra do `sync` (versão = servidor - 1).
      expect((await sync(_entry(version: 0))).serverVersion, 1);
      expect((await sync(_entry(version: 0))).serverVersion, 2);
      expect((await sync(_entry(version: 1))).serverVersion, 3);

      // O aparelho partiu da v1: conflito com a cópia do servidor.
      final conflito = await sync(_entry(version: 1, status: 'paciente ausente'));
      expect(conflito.syncStatus, SyncStatus.conflict);
      expect(conflito.serverVersion, 3);
      expect(conflito.serverVisit!.version, 3);
      expect(conflito.serverVisit!.status, 'realizada');

      // "Manter a minha": compare-and-set sobre a versão vista.
      const notasDoAparelho = {'campo': 'nota sintética do aparelho'};
      final resolvido = await endpoints.visits.resolveConflict(
        sessionBuilder,
        accessToken: token,
        visit: _entry(version: 1, status: 'paciente ausente', notes: notasDoAparelho),
        expectedServerVersion: 3,
      );
      expect(resolvido.syncStatus, SyncStatus.synced);
      expect(resolvido.serverVersion, 4);

      // As notas relidas do banco (cifradas na coluna) voltam iguais.
      final relidas = await endpoints.visits.pull(
        sessionBuilder,
        accessToken: token,
        since: DateTime.utc(2000),
      );
      expect(relidas.single.version, 4);
      expect(relidas.single.status, 'paciente ausente');
      expect(relidas.single.notes, notasDoAparelho);

      // Segunda decisão sobre a mesma versão vista: vencida, nada gravado.
      final vencido = await endpoints.visits.resolveConflict(
        sessionBuilder,
        accessToken: token,
        visit: _entry(version: 1, status: 'recusou atendimento'),
        expectedServerVersion: 3,
      );
      expect(vencido.syncStatus, SyncStatus.conflict);
      expect(vencido.serverVersion, 4);
      expect(vencido.serverVisit!.version, 4);
      expect(vencido.serverVisit!.notes, notasDoAparelho);

      // ACS de outra microárea: a mesma recusa territorial do `sync`.
      final tokenOutraArea = AlertRuntime.instance.auth.issueToken(const AuthenticatedUser(
        id: _acsOutraAreaId,
        role: UserRole.acs,
        microAreaId: _otherMicroAreaId,
        deviceId: 'acs-device-outra-area',
      ));
      final recusado = await endpoints.visits.resolveConflict(
        sessionBuilder,
        accessToken: tokenOutraArea,
        visit: _entry(version: 4, status: 'recusou atendimento'),
        expectedServerVersion: 4,
      );
      expect(recusado.syncStatus, SyncStatus.rejected);
      expect(recusado.message, 'paciente fora da sua microárea');
      expect(recusado.serverVisit, isNull);

      final negadas = await AuditLog.db.find(
        session,
        where: (t) => t.result.equals('denied_territory'),
      );
      expect(negadas, hasLength(1));
      expect(negadas.single.resourceType, 'visit');
      expect(negadas.single.userId, UuidValue.fromString(_acsOutraAreaId));

      final linha = (await Visit.db.find(session)).single;
      expect(linha.version, 4);
      expect(linha.status, 'paciente ausente');

      final resolucoes = await AuditLog.db.find(
        session,
        where: (t) => t.result.equals('conflict_resolved_local'),
      );
      expect(resolucoes, hasLength(1));
      expect(resolucoes.single.actionType, 'write');
      expect(resolucoes.single.resourceType, 'visit');
      expect(resolucoes.single.resourceId, linha.id);
      expect(resolucoes.single.userId, UuidValue.fromString(_acsId));
    });

    test('versão esperada menor que 1 vira AlertValidationException', () async {
      await _seed(sessionBuilder.build());
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      await expectLater(
        endpoints.visits.resolveConflict(
          sessionBuilder,
          accessToken: login.accessToken,
          visit: _entry(version: 0),
          expectedServerVersion: 0,
        ),
        throwsA(isA<AlertValidationException>()),
      );
    });

    test('paciente recebe AlertPermissionException', () async {
      await _seed(sessionBuilder.build());
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      await expectLater(
        endpoints.visits.resolveConflict(
          sessionBuilder,
          accessToken: login.accessToken,
          visit: _entry(version: 0),
          expectedServerVersion: 1,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });
  });
}
