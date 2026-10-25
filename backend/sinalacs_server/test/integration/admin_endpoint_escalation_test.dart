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

/// `admin.escalateAlert` (#44) pelo endpoint, com tokens reais e Postgres real:
/// papel, escopo por UBS, auditoria, cadeia de hash e resposta sem identidade.
/// Dados sintéticos; ids próprios.
const _ubsA = '00000000-0000-4000-8000-0000000044d1';
const _ubsB = '00000000-0000-4000-8000-0000000044d2';
const _maA = '00000000-0000-4000-8000-0000000044d3';
const _maB = '00000000-0000-4000-8000-0000000044d4';
const _acs = '00000000-0000-4000-8000-0000000044d5';
const _admin = '00000000-0000-4000-8000-0000000044d6';
const _coordA = '00000000-0000-4000-8000-0000000044d7';
const _coordB = '00000000-0000-4000-8000-0000000044d8';
const _paciente = '00000000-0000-4000-8000-0000000044d9';
const _segredo = 'test-audit-chain-secret';

final _t = DateTime.utc(2026, 10, 11, 12);

AppConfig _config() => AppConfig(
  mqttBroker: 'localhost:1883',
  jwtSecret: 'test-secret',
  auditChainSecret: _segredo,
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

Future<void> _usuario(Session s, String id, UserRole role, {String? ma}) => User
    .db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'admin-esc-$id',
        name: 'Sintético $id',
        birthDate: DateTime.utc(1980),
        role: role,
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        createdAt: _t,
        updatedAt: _t,
      ),
    )
    .then((_) {});

Future<void> _seed(Session s) async {
  for (final (id, nome) in [(_ubsA, 'UBS A'), (_ubsB, 'UBS B')]) {
    await Ubs.db.insertRow(
      s,
      Ubs(
        id: UuidValue.fromString(id),
        name: nome,
        address: 'Endereço sintético',
        city: 'São Paulo',
        state: 'SP',
      ),
    );
  }
  for (final (id, ubs) in [(_maA, _ubsA), (_maB, _ubsB)]) {
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(id),
        name: 'Microárea $id',
        ubsId: UuidValue.fromString(ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }
  await _usuario(s, _paciente, UserRole.patient, ma: _maA);
  await Patient.db.insertRow(
    s,
    await encryptedPatient(
      id: _paciente,
      emergencyContact: 'contato sintético',
      isChronic: false,
    ),
  );
  await _usuario(s, _acs, UserRole.acs, ma: _maA);
  await _usuario(s, _admin, UserRole.admin);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_admin),
      enrollmentId: 'ADM-ESC-1',
      active: true,
    ),
  );
  for (final (id, mat, ubs) in [
    (_coordA, 'COO-ESC-A', _ubsA),
    (_coordB, 'COO-ESC-B', _ubsB),
  ]) {
    await _usuario(s, id, UserRole.coordinator);
    await StaffAccount.db.insertRow(
      s,
      StaffAccount(
        id: UuidValue.fromString(id),
        enrollmentId: mat,
        active: true,
        ubsId: UuidValue.fromString(ubs),
      ),
    );
  }
}

/// Alerta vermelho pendente, disparado bem antes do prazo padrão.
Future<Alert> _alerta(Session s, String ma) => Alert.db.insertRow(
  s,
  Alert(
    patientId: UuidValue.fromString(_paciente),
    microAreaId: UuidValue.fromString(ma),
    triggeredAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    riskLevel: RiskLevel.red,
    locationHash: 'hash-sintetico',
    status: AlertStatus.pending,
    mqttTopic: 'sinalacs/v1/microareas/$ma/alerts',
    deviceId: 'device-sintetico',
    retryCount: 0,
    version: 1,
  ),
);

String _token(String id, UserRole role, {String? ma}) =>
    AlertRuntime.instance.auth.issueToken(
      AuthenticatedUser(
        id: id,
        role: role,
        microAreaId: ma,
        deviceId: 'sem-aparelho',
      ),
    );

Future<List<AuditLog>> _linhas(Session s, String resourceType) =>
    AuditLog.db.find(
      s,
      where: (t) => t.resourceType.equals(resourceType),
      orderBy: (t) => t.sequence,
    );

void main() {
  withServerpod('Dado admin.escalateAlert (#44)', (sessionBuilder, endpoints) {
    late Session session;

    setUp(() async {
      session = sessionBuilder.build();
      AlertRuntime.instance.overrideConfig(_config());
      await _seed(session);
    });
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    test(
      'coordenador da UBS A escalona: linha escalated:no_ack_timeout, cadeia válida, resposta sem identidade',
      () async {
        final a = await _alerta(session, _maA);
        final r = await endpoints.admin.escalateAlert(
          sessionBuilder,
          accessToken: _token(_coordA, UserRole.coordinator),
          alertId: a.id!.uuid,
          reason: EscalationReason.noAckTimeout,
        );
        expect(r.alertId, a.id!.uuid);
        expect(r.alreadyEscalated, isFalse);
        final json = r.toJson()..remove('__className__');
        expect(json.keys.toSet(), {
          'alertId',
          'escalatedAt',
          'alreadyEscalated',
        });
        expect(json.toString(), isNot(contains(_paciente)));

        final lido = (await Alert.db.findById(session, a.id!))!;
        expect(lido.escalatedAt, r.escalatedAt);
        expect(lido.escalatedBy, UuidValue.fromString(_coordA));
        expect(lido.status, AlertStatus.pending);
        expect(
          await AlertOutboxEntry.db.count(
            session,
            where: (t) => t.alertId.equals(a.id!),
          ),
          1,
        );

        final linhas = await _linhas(session, 'admin_alert');
        expect(linhas, hasLength(1));
        expect(linhas.single.result, 'escalated:no_ack_timeout');
        expect(linhas.single.actionType, 'write');
        expect(linhas.single.resourceId, a.id);
        expect(linhas.single.userId, UuidValue.fromString(_coordA));

        // Repetir: idempotente, mesmo carimbo, segunda linha de auditoria.
        final deNovo = await endpoints.admin.escalateAlert(
          sessionBuilder,
          accessToken: _token(_coordA, UserRole.coordinator),
          alertId: a.id!.uuid,
          reason: EscalationReason.patientRecontact,
        );
        expect(deNovo.alreadyEscalated, isTrue);
        expect(deNovo.escalatedAt, r.escalatedAt);
        expect(
          (await _linhas(session, 'admin_alert')).map((l) => l.result),
          ['escalated:no_ack_timeout', 'already_escalated:patient_recontact'],
        );

        final verifier = AuditChainVerifier(
          reader: OrmAuditChainReader(session: () => session),
          secret: _segredo,
        );
        expect((await verifier.verify()).ok, isTrue);
      },
    );

    test(
      'coordenador da UBS B: "Alerta não encontrado." e nenhuma linha de sucesso',
      () async {
        final a = await _alerta(session, _maA);
        await expectLater(
          endpoints.admin.escalateAlert(
            sessionBuilder,
            accessToken: _token(_coordB, UserRole.coordinator),
            alertId: a.id!.uuid,
            reason: EscalationReason.noAckTimeout,
          ),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Alerta não encontrado.',
            ),
          ),
        );
        final linhas = await _linhas(session, 'admin_alert');
        expect(linhas.map((l) => l.result), ['denied_not_found']);
        expect((await Alert.db.findById(session, a.id!))!.escalatedAt, isNull);
        expect(
          await AlertOutboxEntry.db.count(
            session,
            where: (t) => t.alertId.equals(a.id!),
          ),
          0,
        );
      },
    );

    test('ACS e paciente: acesso restrito e recusa auditada', () async {
      final a = await _alerta(session, _maA);
      for (final (id, role) in [
        (_acs, UserRole.acs),
        (_paciente, UserRole.patient),
      ]) {
        await expectLater(
          endpoints.admin.escalateAlert(
            sessionBuilder,
            accessToken: _token(id, role, ma: _maA),
            alertId: a.id!.uuid,
            reason: EscalationReason.noAckTimeout,
          ),
          throwsA(
            isA<AlertPermissionException>().having(
              (e) => e.message,
              'message',
              'acesso restrito ao backoffice',
            ),
          ),
        );
      }
      final linhas = await _linhas(session, 'admin_alert');
      expect(linhas.map((l) => l.result), ['denied', 'denied']);
      expect(linhas.map((l) => l.actionType), ['write', 'write']);
      expect((await Alert.db.findById(session, a.id!))!.escalatedAt, isNull);
    });

    test('administrador escalona alerta de qualquer UBS', () async {
      final b = await _alerta(session, _maB);
      final r = await endpoints.admin.escalateAlert(
        sessionBuilder,
        accessToken: _token(_admin, UserRole.admin),
        alertId: b.id!.uuid,
        reason: EscalationReason.acsUnreachable,
      );
      expect(r.alreadyEscalated, isFalse);
      expect(
        (await _linhas(session, 'admin_alert')).single.result,
        'escalated:acs_unreachable',
      );
    });
  });
}
