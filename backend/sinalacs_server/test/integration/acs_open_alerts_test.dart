import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Reserva por HTTP dos alertas do ACS (#80, R2): `alerts.openForMicroArea`.
///
/// O caso que fecha o R2 no servidor é o primeiro: com o broker fora, o alerta
/// criado pelo paciente aparece para o ACS da microárea pelo RPC.
class _RecordingPublisher implements AlertPublisher {
  final List<AlertDelivery> published = [];
  bool offline = false;

  @override
  Future<void> publish(AlertDelivery alert) async {
    if (offline) throw Exception('broker indisponível');
    published.add(alert);
  }
}

/// Mesmos UUIDs sintéticos do seed de desenvolvimento, dos quais o dev-login
/// depende. Inseridos por caso porque o harness reverte o banco a cada teste.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _outraMicroAreaId = '00000000-0000-4000-8000-0000000000aa';

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
  for (final (id, nome) in [(_microAreaId, 'Microárea 12'), (_outraMicroAreaId, 'Microárea 13')]) {
    await MicroArea.db.insertRow(
      session,
      MicroArea(id: UuidValue.fromString(id), name: nome, ubsId: UuidValue.fromString(_ubsId), geoJsonBoundary: '{}'),
    );
  }
  final now = DateTime.now().toUtc();
  await User.db.insert(session, [
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'development-patient',
      name: 'Paciente de desenvolvimento',
      birthDate: DateTime.utc(1990),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
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
  ]);
  await Patient.db.insertRow(
    session,
    await encryptedPatient(id: _patientId, emergencyContact: 'Contato de desenvolvimento', isChronic: false),
  );
  await Acs.db.insertRow(
    session,
    Acs(id: UuidValue.fromString(_acsId), enrollmentId: 'ACS-001', ubsId: UuidValue.fromString(_ubsId), active: true),
  );
}

/// Alerta inserido direto pelo ORM, para controlar `triggeredAt`, status e
/// microárea sem passar pelo relógio do serviço.
Future<String> _alerta(
  Session session, {
  required DateTime triggeredAt,
  AlertStatus status = AlertStatus.pending,
  String microAreaId = _microAreaId,
  DateTime? escalatedAt,
}) async {
  final row = await Alert.db.insertRow(
    session,
    Alert(
      patientId: UuidValue.fromString(_patientId),
      acsId: UuidValue.fromString(_acsId),
      microAreaId: UuidValue.fromString(microAreaId),
      triggeredAt: triggeredAt,
      acknowledgedAt: status == AlertStatus.acknowledged ? triggeredAt.add(const Duration(minutes: 1)) : null,
      riskLevel: RiskLevel.red,
      locationHash: 'hash-sintetico',
      status: status,
      mqttTopic: 'sinalacs/v1/microareas/$microAreaId/alerts',
      deviceId: 'device-teste',
      retryCount: 0,
      version: 0,
      escalatedAt: escalatedAt,
    ),
  );
  return row.id!.uuid;
}

void main() {
  withServerpod('Dada a reserva por HTTP dos alertas do ACS (#80)', (sessionBuilder, endpoints) {
    late _RecordingPublisher publisher;

    setUp(() {
      publisher = _RecordingPublisher();
      AlertRuntime.instance
        ..overridePublisher(publisher)
        ..overrideConfig(_config());
    });

    tearDown(() {
      AlertRuntime.instance
        ..overridePublisher(null)
        ..overrideConfig(null);
    });

    Future<String> tokenDoAcs() async =>
        (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

    test('com o broker fora, o alerta criado aparece para o ACS da microárea', () async {
      await _seed(sessionBuilder.build());
      publisher.offline = true;
      final paciente = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');
      final criado = await endpoints.alerts.createRedAlert(
        sessionBuilder,
        accessToken: paciente.accessToken,
        idempotencyKey: 'reserva-http-1',
        locationHash: 'hash-sintetico',
      );
      expect(criado.published, isFalse);

      final abertos = await endpoints.alerts.openForMicroArea(sessionBuilder, accessToken: await tokenDoAcs());

      expect(abertos, hasLength(1));
      final a = abertos.single;
      expect(a.alertId, criado.alertId);
      expect(a.status, AlertStatus.pending);
      expect(a.riskLevel, RiskLevel.red);
      expect(a.escalated, isFalse);
      expect(a.microAreaId, _microAreaId);
      expect(a.patientId, _patientId);
      expect(a.locationHash, 'hash-sintetico');
      expect(a.acknowledgedAt, isNull);
    });

    test('confirmado continua listado; concluído sai', () async {
      await _seed(sessionBuilder.build());
      final paciente = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');
      final criado = await endpoints.alerts.createRedAlert(
        sessionBuilder,
        accessToken: paciente.accessToken,
        idempotencyKey: 'reserva-http-2',
        locationHash: 'hash-sintetico',
      );
      final acs = await tokenDoAcs();

      await endpoints.alerts.acknowledge(sessionBuilder, accessToken: acs, alertId: criado.alertId);
      final depoisDoAck = await endpoints.alerts.openForMicroArea(sessionBuilder, accessToken: acs);
      expect(depoisDoAck.single.status, AlertStatus.acknowledged);
      expect(depoisDoAck.single.acknowledgedAt, isNotNull);

      await endpoints.alerts.resolve(sessionBuilder, accessToken: acs, alertId: criado.alertId);
      expect(await endpoints.alerts.openForMicroArea(sessionBuilder, accessToken: acs), isEmpty);
    });

    test('não confirmados vêm antes dos confirmados, cada grupo do mais antigo ao mais novo', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final t0 = DateTime.utc(2026, 10, 17, 10);
      final confirmado = await _alerta(session, triggeredAt: t0, status: AlertStatus.acknowledged);
      final maisNovo = await _alerta(session, triggeredAt: t0.add(const Duration(minutes: 2)));
      final maisAntigo = await _alerta(session, triggeredAt: t0.add(const Duration(minutes: 1)));

      final abertos = await endpoints.alerts.openForMicroArea(sessionBuilder, accessToken: await tokenDoAcs());

      expect(abertos.map((a) => a.alertId), [maisAntigo, maisNovo, confirmado]);
    });

    test('escalonado aparece com escalated: true', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final t0 = DateTime.utc(2026, 10, 17, 10);
      await _alerta(session, triggeredAt: t0, escalatedAt: t0.add(const Duration(minutes: 5)));
      await _alerta(session, triggeredAt: t0.add(const Duration(minutes: 1)), status: AlertStatus.escalated);

      final abertos = await endpoints.alerts.openForMicroArea(sessionBuilder, accessToken: await tokenDoAcs());

      expect(abertos, hasLength(2));
      expect(abertos.every((a) => a.escalated), isTrue);
    });

    test('ACS de outra microárea não vê', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      await _alerta(session, triggeredAt: DateTime.utc(2026, 10, 17, 10), microAreaId: _outraMicroAreaId);

      expect(await endpoints.alerts.openForMicroArea(sessionBuilder, accessToken: await tokenDoAcs()), isEmpty);
    });

    test('paciente é recusado', () async {
      await _seed(sessionBuilder.build());
      final paciente = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      await expectLater(
        endpoints.alerts.openForMicroArea(sessionBuilder, accessToken: paciente.accessToken),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('não grava linha de auditoria de leitura', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      await _alerta(session, triggeredAt: DateTime.utc(2026, 10, 17, 10));
      final acs = await tokenDoAcs();
      final antes = await AuditLog.db.count(session);

      await endpoints.alerts.openForMicroArea(sessionBuilder, accessToken: acs);

      expect(await AuditLog.db.count(session), antes);
    });

    test('corta em 200 sem nunca deixar de fora o pendente mais novo', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final t0 = DateTime.utc(2026, 10, 17, 10);
      final ids = <String>[];
      for (var i = 0; i <= RedAlertService.openAlertsLimit; i++) {
        ids.add(await _alerta(session, triggeredAt: t0.add(Duration(seconds: i))));
      }

      final abertos = await endpoints.alerts.openForMicroArea(sessionBuilder, accessToken: await tokenDoAcs());

      expect(abertos, hasLength(200));
      // O corte cai nos mais ANTIGOS: um vermelho novo numa microárea com
      // pendentes acumulados é justamente o que a reserva existe para entregar.
      expect(abertos.map((a) => a.alertId), contains(ids.last));
      expect(abertos.map((a) => a.alertId), isNot(contains(ids.first)));
      // E a resposta segue do mais antigo ao mais novo.
      expect(abertos.first.alertId, ids[1]);
      expect(abertos.last.alertId, ids.last);
    });
  });
}
