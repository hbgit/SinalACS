import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_scope.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/retention/expurge_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_outbox.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_chain_reader.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_data_subject_case_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_retention_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Parte com Postgres do inventário de rotas de descarte de alerta vermelho
/// (#44, Task 3); a parte hermética está em
/// `test/unit/red_alert_discard_paths_test.dart`. Os buracos
/// que a Task 3 provou (ACK sem auditoria, expurgo de vermelho pending) foram
/// fechados na Task 4. Ids iguais aos do dev-login, para o RPC real rodar.
/// Dados sintéticos.
const _ubs = '00000000-0000-4000-8000-000000000004';
const _ma = '00000000-0000-4000-8000-000000000003';
const _pac = '00000000-0000-4000-8000-000000000001';
const _acs = '00000000-0000-4000-8000-000000000002';
const _adm = '00000000-0000-4000-8000-000000004405';
const _pedido = '00000000-0000-4000-8000-000000004406';

final _agora = DateTime.utc(2026, 10, 11, 12);

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

Future<void> _user(Session s, String id, UserRole role, {String? ma}) => User.db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'discard-$id',
        name: 'Sintético $id',
        birthDate: DateTime.utc(1985, 3, 4),
        role: role,
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        createdAt: _agora,
        updatedAt: _agora,
      ),
    )
    .then((_) {});

Future<void> _seed(Session s) async {
  await Ubs.db.insertRow(
    s,
    Ubs(
      id: UuidValue.fromString(_ubs),
      name: 'UBS descarte',
      address: 'Endereço sintético',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    s,
    MicroArea(
      id: UuidValue.fromString(_ma),
      name: 'Microárea descarte',
      ubsId: UuidValue.fromString(_ubs),
      geoJsonBoundary: '{}',
    ),
  );
  await _user(s, _pac, UserRole.patient, ma: _ma);
  await _user(s, _acs, UserRole.acs, ma: _ma);
  await _user(s, _adm, UserRole.admin);
  await Patient.db.insertRow(
    s,
    await encryptedPatient(
      id: _pac,
      emergencyContact: 'contato sintético',
      isChronic: false,
    ),
  );
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acs),
      enrollmentId: 'DESC-001',
      ubsId: UuidValue.fromString(_ubs),
      active: true,
    ),
  );
}

Future<Alert> _alertaVermelho(Session s, {required DateTime em}) =>
    Alert.db.insertRow(
      s,
      Alert(
        patientId: UuidValue.fromString(_pac),
        microAreaId: UuidValue.fromString(_ma),
        triggeredAt: em,
        riskLevel: RiskLevel.red,
        locationHash: 'hash-sintetico',
        status: AlertStatus.pending,
        mqttTopic: 'sinalacs/v1/microareas/$_ma/alerts',
        deviceId: 'device-sintetico',
        retryCount: 0,
        version: 0,
      ),
    );

Future<int> _auditoriaDoAlerta(Session s, UuidValue alertId) =>
    AuditLog.db.count(s, where: (t) => t.resourceId.equals(alertId));

void main() {
  withServerpod('Rotas de descarte de alerta vermelho (#44)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;

    setUp(() async {
      session = sessionBuilder.build();
      AlertRuntime.instance.overrideConfig(_config());
      await _seed(session);
    });
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    test(
      'alerts.acknowledge (RPC): vai a acknowledged E deixa auditoria',
      () async {
        final alerta = await _alertaVermelho(session, em: _agora);
        final token = await endpoints.auth.developmentLogin(
          sessionBuilder,
          role: 'acs',
        );
        final r = await endpoints.alerts.acknowledge(
          sessionBuilder,
          accessToken: token.accessToken,
          alertId: alerta.id!.uuid,
        );
        expect(r.acknowledged, isTrue);
        final depois = await Alert.db.findById(session, alerta.id!);
        expect(depois!.status, AlertStatus.acknowledged);
        expect(
          await _auditoriaDoAlerta(session, alerta.id!),
          greaterThan(0),
          reason: 'ACK de alerta vermelho sem linha em audit_logs',
        );
        final verifier = AuditChainVerifier(
          reader: OrmAuditChainReader(session: () => session),
          secret: 'test-audit-chain-secret',
        );
        expect((await verifier.verify()).ok, isTrue);
      },
    );

    test('ACK com a trilha de auditoria falhando é desfeito por inteiro', () async {
      final alerta = await _alertaVermelho(session, em: _agora);
      final store = OrmAlertStore(
        session: () => session,
        appendAudit: (s, t, e) async => throw StateError('trilha fora do ar'),
      );

      await expectLater(
        store.acknowledge(
          alertId: alerta.id!.uuid,
          acsId: _acs,
          microAreaId: _ma,
          audit: const AuditEvent(
            userId: _acs,
            actionType: 'write',
            resourceType: 'alert',
            resourceId: _pac,
            result: 'acknowledged',
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final depois = (await Alert.db.findById(session, alerta.id!))!;
      expect(depois.status, AlertStatus.pending);
      expect(depois.acknowledgedAt, isNull);
      expect(depois.acsId, isNull);
      expect(await AlertDeliveryRecord.db.count(session), 0);
      expect(await AuditLog.db.count(session), 0);
    });

    test(
      'ACK por MQTT (mesmo caminho do callback de server.dart)',
      () async {
        // server.dart: runtime.serviceFor(session).acknowledge(user com
        // deviceId "mqtt"). O dispatcher só decodifica a mensagem e chama este
        // callback; o broker real não é necessário para provar a escrita.
        final alerta = await _alertaVermelho(session, em: _agora);
        final ok = await AlertRuntime.instance
            .serviceFor(session)
            .acknowledge(
              user: AuthenticatedUser(
                id: _acs,
                role: UserRole.acs,
                microAreaId: _ma,
                deviceId: 'mqtt',
              ),
              alertId: alerta.id!.uuid,
            );
        expect(ok, isTrue);
        expect(
          (await Alert.db.findById(session, alerta.id!))!.status,
          AlertStatus.acknowledged,
        );
        expect(
          await _auditoriaDoAlerta(session, alerta.id!),
          greaterThan(0),
          reason: 'ACK por MQTT sem linha em audit_logs',
        );
        final linha = await AuditLog.db.findFirstRow(
          session,
          where: (t) => t.resourceId.equals(alerta.id!),
        );
        expect(
          linha!.result,
          'acknowledged_mqtt',
          reason: 'o ACK por MQTT não é autenticado e não pode parecer o do RPC',
        );
      },
    );

    test(
      'outbox esgotando tentativas: alerta segue pending e a entrega, viva',
      () async {
        final alerta = await _alertaVermelho(session, em: _agora);
        final outbox = OrmAlertOutbox(
          session: () => session,
          clock: () => _agora,
        );
        await AlertOutboxEntry.db.insertRow(
          session,
          AlertOutboxEntry(
            alertId: alerta.id!,
            topic: 'sinalacs/v1/microareas/$_ma/alerts',
            payload: '{}',
            createdAt: _agora,
            attempts: 0,
            nextAttemptAt: _agora,
          ),
        );
        final entrada = (await AlertOutboxEntry.db.findFirstRow(session))!;
        for (var i = 0; i < 30; i++) {
          await outbox.markFailed(
            entrada.id!.uuid,
            'broker indisponível',
            _agora.add(const Duration(seconds: 60)),
          );
        }

        final depois = await Alert.db.findById(session, alerta.id!);
        expect(depois!.status, AlertStatus.pending);
        expect(depois.riskLevel, RiskLevel.red);
        final linha = (await AlertOutboxEntry.db.findFirstRow(session))!;
        expect(linha.publishedAt, isNull, reason: 'nunca marcado entregue');
        expect(linha.lastError, 'broker indisponível');
      },
    );

    test(
      'retenção LGPD: não apaga vermelho pending vencido (D7)',
      () async {
        final velho = await _alertaVermelho(
          session,
          em: _agora.subtract(const Duration(days: 800)),
        );
        final cortes = RetentionCutoffs(
          alerts: _agora.subtract(const Duration(days: 730)),
          visits: _agora.subtract(const Duration(days: 1825)),
          triageSessions: _agora.subtract(const Duration(days: 1825)),
        );

        await OrmRetentionStore(session: () => session).purgeDue(cortes);

        final restante = await Alert.db.findById(session, velho.id!);
        expect(
          restante,
          isNotNull,
          reason: 'expurgo apagou alerta vermelho ainda pending',
        );
        expect(restante!.status, AlertStatus.pending);
      },
    );

    test(
      'anonimização do titular: não apaga nem altera status de alerta',
      () async {
        final alerta = await _alertaVermelho(session, em: _agora);
        await DataSubjectRequest.db.insertRow(
          session,
          DataSubjectRequest(
            id: UuidValue.fromString(_pedido),
            userId: UuidValue.fromString(_pac),
            requestType: DataSubjectRequestType.deletion,
            detailsEncrypted: '',
            detailsKeyVersion: 1,
            status: DataSubjectRequestStatus.open,
            createdAt: _agora.subtract(const Duration(days: 15)),
            dueAt: _agora,
          ),
        );
        final store = OrmDataSubjectCaseStore(
          session,
          testHealthDataCipher(),
          chainSecret: 'segredo-sintetico',
          appendAudit: (s, t, e) async {},
        );

        final ok = await store.decide(
          const AdminScope.system(),
          _pedido,
          from: const {DataSubjectRequestStatus.open},
          to: DataSubjectRequestStatus.completed,
          resolution: null,
          decidedBy: _adm,
          anonymize: true,
          audit: const AuditEvent(
            userId: _adm,
            actionType: 'write',
            resourceType: 'data_subject_request',
            resourceId: _pedido,
            result: 'completed',
          ),
          now: _agora,
        );

        expect(ok, isTrue);
        final depois = await Alert.db.findById(session, alerta.id!);
        expect(depois, isNotNull);
        expect(depois!.status, AlertStatus.pending);
        expect(depois.riskLevel, RiskLevel.red);
        expect(depois.triggeredAt, alerta.triggeredAt);
      },
    );
  });
}
