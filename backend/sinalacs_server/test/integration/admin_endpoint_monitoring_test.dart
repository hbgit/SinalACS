import 'dart:convert';

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

/// `admin.alertsPulse` e `admin.endMonitoringSession` (#44, D5) pelo endpoint,
/// com tokens reais e Postgres real: o pulso não grava `read`, a sessão abre e
/// fecha uma vez, recusas auditadas, escopo por UBS, resposta sem identidade e
/// cadeia de auditoria íntegra. Dados sintéticos; ids próprios.
const _ubsA = '00000000-0000-4000-8000-0000000046b1';
const _ubsB = '00000000-0000-4000-8000-0000000046b2';
const _maA = '00000000-0000-4000-8000-0000000046b3';
const _maB = '00000000-0000-4000-8000-0000000046b4';
const _acs = '00000000-0000-4000-8000-0000000046b5';
const _admin = '00000000-0000-4000-8000-0000000046b6';
const _coordA = '00000000-0000-4000-8000-0000000046b7';
const _coordB = '00000000-0000-4000-8000-0000000046b8';
const _coordSemUbs = '00000000-0000-4000-8000-0000000046b9';
const _paciente = '00000000-0000-4000-8000-0000000046ba';
const _pacienteNome = 'Joana Sintética Pulso';
const _segredo = 'test-audit-chain-secret';

final _t = DateTime.utc(2026, 10, 11, 12);

AppConfig _config() => AppConfig(
  mqttBroker: 'localhost:1883',
  jwtSecret: 'test-secret',
  auditChainSecret: _segredo,
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

Future<void> _usuario(
  Session s,
  String id,
  UserRole role, {
  String? ma,
  String? nome,
}) => User.db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'admin-pulse-ep-$id',
        name: nome ?? 'Sintético $id',
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
  await _usuario(s, _paciente, UserRole.patient, ma: _maA, nome: _pacienteNome);
  await Patient.db.insertRow(
    s,
    await encryptedPatient(
      id: _paciente,
      emergencyContact: 'contato sintético',
      isChronic: false,
    ),
  );
  await _usuario(s, _acs, UserRole.acs, ma: _maA);
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acs),
      enrollmentId: 'ACS-PULSO-1',
      ubsId: UuidValue.fromString(_ubsA),
      active: true,
    ),
  );
  await _usuario(s, _admin, UserRole.admin);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_admin),
      enrollmentId: 'ADM-PULSO-1',
      active: true,
    ),
  );
  for (final (id, mat, ubs) in [
    (_coordA, 'COO-PULSO-A', _ubsA),
    (_coordB, 'COO-PULSO-B', _ubsB),
    (_coordSemUbs, 'COO-PULSO-X', null),
  ]) {
    await _usuario(s, id, UserRole.coordinator);
    await StaffAccount.db.insertRow(
      s,
      StaffAccount(
        id: UuidValue.fromString(id),
        enrollmentId: mat,
        active: true,
        ubsId: ubs == null ? null : UuidValue.fromString(ubs),
      ),
    );
  }
}

/// Alerta vermelho pendente, disparado bem antes do prazo padrão (vencido).
Future<Alert> _alerta(
  Session s,
  String ma, {
  Duration atras = const Duration(hours: 1),
}) => Alert.db.insertRow(
  s,
  Alert(
    patientId: UuidValue.fromString(_paciente),
    microAreaId: UuidValue.fromString(ma),
    triggeredAt: DateTime.now().toUtc().subtract(atras),
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

Future<int> _linhasRead(Session s) =>
    AuditLog.db.count(s, where: (t) => t.actionType.equals('read'));

void main() {
  withServerpod('Dado admin.alertsPulse e a sessão de monitoramento (#44, D5)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;

    setUp(() async {
      session = sessionBuilder.build();
      AlertRuntime.instance.overrideConfig(_config());
      AlertRuntime.instance.resetMonitoringSessions();
      await _seed(session);
    });
    tearDown(() {
      AlertRuntime.instance.overrideConfig(null);
      AlertRuntime.instance.resetMonitoringSessions();
    });

    Future<AdminAlertsPulse> pulso(String id, UserRole role) =>
        endpoints.admin.alertsPulse(
          sessionBuilder,
          accessToken: _token(id, role),
        );

    test(
      'N pulsos: um START, nenhuma linha read, indicadores iguais a admin.indicators, resposta sem identidade',
      () async {
        await _alerta(session, _maA);
        final readsAntes = await _linhasRead(session);

        late AdminAlertsPulse p;
        for (var i = 0; i < 5; i++) {
          p = await pulso(_coordA, UserRole.coordinator);
        }
        expect(
          await _linhasRead(session),
          readsAntes,
          reason: 'pulso não grava read',
        );
        final sessoes = await _linhas(session, 'admin_monitoring');
        expect(sessoes.map((l) => l.actionType), ['monitoring_session_start']);
        expect(sessoes.single.result, 'success');
        expect(sessoes.single.resourceId, isNull);
        expect(sessoes.single.userId, UuidValue.fromString(_coordA));

        expect(p.overdueRed, 1);
        expect(p.maxChangedAt, isNotNull);
        expect(
          p.serverNow.difference(DateTime.now().toUtc()).abs(),
          lessThan(const Duration(minutes: 1)),
        );

        // Mesmo estado, mesma régua: o pulso embute o que admin.indicators dá.
        final ind = await endpoints.admin.indicators(
          sessionBuilder,
          accessToken: _token(_coordA, UserRole.coordinator),
        );
        expect(p.indicators.toJson(), ind.toJson());

        // Nenhuma identidade: nem id, nem nome, nem rótulo de paciente.
        final json = p.toJson()..remove('__className__');
        expect(json.keys.toSet(), {
          'indicators',
          'overdueRed',
          'maxChangedAt',
          'serverNow',
        });
        final texto = jsonEncode(p.toJson());
        for (final proibido in [
          _paciente,
          _pacienteNome,
          _acs,
          _maA,
          _ubsA,
          'patient',
          'Label',
          'microArea',
          'cpf',
          '#',
        ]) {
          expect(texto, isNot(contains(proibido)), reason: proibido);
        }
      },
    );

    test(
      'endMonitoringSession: com sessão grava um END; repetir e chamar sem sessão não grava',
      () async {
        await pulso(_coordA, UserRole.coordinator);
        for (var i = 0; i < 2; i++) {
          await endpoints.admin.endMonitoringSession(
            sessionBuilder,
            accessToken: _token(_coordA, UserRole.coordinator),
          );
        }
        // Sem sessão nenhuma: nada.
        await endpoints.admin.endMonitoringSession(
          sessionBuilder,
          accessToken: _token(_admin, UserRole.admin),
        );
        final linhas = await _linhas(session, 'admin_monitoring');
        expect(linhas.map((l) => l.actionType), [
          'monitoring_session_start',
          'monitoring_session_end',
        ]);
        expect(linhas.last.result, 'success');
        expect(linhas.last.userId, UuidValue.fromString(_coordA));

        // Depois do END, o próximo pulso abre outra sessão.
        await pulso(_coordA, UserRole.coordinator);
        expect(
          (await _linhas(session, 'admin_monitoring')).map((l) => l.actionType),
          [
            'monitoring_session_start',
            'monitoring_session_end',
            'monitoring_session_start',
          ],
        );
      },
    );

    test(
      'ACS, paciente e coordenador sem UBS: recusados no pulso e no END, com linha denied',
      () async {
        for (final (id, role, ma) in [
          (_acs, UserRole.acs, _maA),
          (_paciente, UserRole.patient, _maA),
          (_coordSemUbs, UserRole.coordinator, null),
        ]) {
          await expectLater(
            endpoints.admin.alertsPulse(
              sessionBuilder,
              accessToken: _token(id, role, ma: ma),
            ),
            throwsA(
              isA<AlertPermissionException>().having(
                (e) => e.message,
                'message',
                'acesso restrito ao backoffice',
              ),
            ),
          );
          await expectLater(
            endpoints.admin.endMonitoringSession(
              sessionBuilder,
              accessToken: _token(id, role, ma: ma),
            ),
            throwsA(isA<AlertPermissionException>()),
          );
        }
        final pulsos = await _linhas(session, 'admin_pulse');
        expect(pulsos.map((l) => l.result), ['denied', 'denied', 'denied']);
        expect(pulsos.map((l) => l.actionType).toSet(), {'read'});
        final fins = await _linhas(session, 'admin_monitoring');
        expect(fins.map((l) => l.result), ['denied', 'denied', 'denied']);
        expect(fins.map((l) => l.actionType).toSet(), {
          'monitoring_session_end',
        });
      },
    );

    test(
      'coordenador da UBS B não vê os alertas da UBS A',
      () async {
        await _alerta(session, _maA);
        await _alerta(session, _maA, atras: const Duration(minutes: 30));
        final b = await _alerta(session, _maB, atras: const Duration(hours: 2));

        final pB = await pulso(_coordB, UserRole.coordinator);
        expect(pB.overdueRed, 1);
        expect(pB.maxChangedAt, b.triggeredAt);
        expect(pB.indicators.red, 1);

        final pA = await pulso(_coordA, UserRole.coordinator);
        expect(pA.overdueRed, 2);
        expect(pA.indicators.red, 2);

        final pAdmin = await pulso(_admin, UserRole.admin);
        expect(pAdmin.overdueRed, 3);
      },
    );

    test(
      'maxChangedAt muda após o ACK e após o escalonamento; a cadeia de auditoria segue íntegra',
      () async {
        final ack = await _alerta(
          session,
          _maA,
          atras: const Duration(hours: 2),
        );
        final esc = await _alerta(
          session,
          _maA,
          atras: const Duration(hours: 3),
        );

        final p0 = await pulso(_coordA, UserRole.coordinator);
        expect(p0.maxChangedAt, ack.triggeredAt);
        expect(p0.overdueRed, 2);

        final r = await endpoints.alerts.acknowledge(
          sessionBuilder,
          accessToken: _token(_acs, UserRole.acs, ma: _maA),
          alertId: ack.id!.uuid,
        );
        expect(r.acknowledged, isTrue);
        final p1 = await pulso(_coordA, UserRole.coordinator);
        expect(p1.maxChangedAt!.isAfter(p0.maxChangedAt!), isTrue);
        expect(
          p1.maxChangedAt,
          (await Alert.db.findById(session, ack.id!))!.acknowledgedAt,
        );
        expect(p1.overdueRed, 1);

        final e = await endpoints.admin.escalateAlert(
          sessionBuilder,
          accessToken: _token(_coordA, UserRole.coordinator),
          alertId: esc.id!.uuid,
          reason: EscalationReason.noAckTimeout,
        );
        final p2 = await pulso(_coordA, UserRole.coordinator);
        expect(p2.maxChangedAt, e.escalatedAt);
        expect(p2.maxChangedAt!.isAfter(p1.maxChangedAt!), isTrue);
        expect(p2.overdueRed, 0);

        await endpoints.admin.endMonitoringSession(
          sessionBuilder,
          accessToken: _token(_coordA, UserRole.coordinator),
        );

        final verifier = AuditChainVerifier(
          reader: OrmAuditChainReader(session: () => session),
          secret: _segredo,
        );
        expect((await verifier.verify()).ok, isTrue);
      },
    );
  });
}
