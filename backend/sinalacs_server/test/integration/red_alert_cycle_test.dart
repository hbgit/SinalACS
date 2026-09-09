import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Substitui o teste que subia o servidor `dart:io` com
/// `Process.start('dart run bin/server.dart')` numa porta fixa e falava com ele
/// por `HttpClient` cru.
///
/// O harness do Serverpod sobe o servidor em processo e expõe os endpoints
/// tipados, o que elimina a porta fixa, a espera por `/health` e o risco de
/// reusar por engano um servidor já em execução.
class _RecordingPublisher implements AlertPublisher {
  final List<AlertDelivery> published = [];

  @override
  void publish(AlertDelivery alert) => published.add(alert);
}

/// Mesmos UUIDs sintéticos do seed de desenvolvimento, dos quais o dev-login
/// depende. Inseridos por caso porque o harness reverte o banco a cada teste.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';

AppConfig _config({required bool enableDevLogin}) => AppConfig(
      databaseUrl: 'postgresql://localhost/sinalacs_test',
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: enableDevLogin,
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
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
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
  // O id de patients e acs É o UUID do usuário: foi assim que as foreign keys
  // foram recuperadas sob o ORM do Serverpod.
  await Patient.db.insertRow(
    session,
    Patient(
      id: UuidValue.fromString(_patientId),
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
      chronicConditions: [],
    ),
  );
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'ACS-001',
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
}

void main() {
  withServerpod('Dado o ciclo de alerta vermelho', (sessionBuilder, endpoints) {
    late _RecordingPublisher publisher;

    setUp(() {
      publisher = _RecordingPublisher();
      AlertRuntime.instance
        ..overridePublisher(publisher)
        // Dev-login habilitado explicitamente, para o teste não depender de
        // variáveis de ambiente do processo. O caso desligado é coberto à parte.
        ..overrideConfig(_config(enableDevLogin: true));
    });

    tearDown(() {
      AlertRuntime.instance
        ..overridePublisher(null)
        ..overrideConfig(null);
    });

    test('a sonda de saúde preserva os três campos do antigo GET /health',
        () async {
      final health = await endpoints.health.check(sessionBuilder);

      expect(health.status, 'ok');
      expect(health.dbConnected, isTrue);
      // Sem broker no harness, e é justamente por isso que o healthcheck não
      // pode depender do MQTT: hosts free-tier precisam responder mesmo assim.
      expect(health.mqttConnected, isFalse);
    });

    test('a triagem classifica de forma determinística', () async {
      final vermelho = await endpoints.triage.evaluate(
        sessionBuilder,
        chestPain: true,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );
      final verde = await endpoints.triage.evaluate(
        sessionBuilder,
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      expect(vermelho.risk, RiskLevel.red);
      expect(verde.risk, RiskLevel.green);
    });

    test('o dev-login emite token para paciente e para ACS', () async {
      final paciente = await endpoints.auth
          .developmentLogin(sessionBuilder, role: 'patient');
      final acs =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      expect(paciente.tokenType, 'Bearer');
      expect(paciente.accessToken, isNotEmpty);
      expect(acs.accessToken, isNot(paciente.accessToken));
    });

    test('o dev-login rejeita papel desconhecido', () async {
      await expectLater(
        endpoints.auth.developmentLogin(sessionBuilder, role: 'medico'),
        throwsA(isA<AlertValidationException>()),
      );
    });

    test('paciente cria alerta, a chave deduplica e o ACS confirma', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final token = await endpoints.auth
          .developmentLogin(sessionBuilder, role: 'patient');

      final criado = await endpoints.alerts.createRedAlert(
        sessionBuilder,
        accessToken: token.accessToken,
        idempotencyKey: 'ciclo-1',
        locationHash: 'hash-sintetico',
      );

      expect(criado.status, AlertStatus.pending);
      expect(publisher.published, hasLength(1));
      expect(
        publisher.published.single.topic,
        'sinalacs/v1/microareas/$_microAreaId/alerts',
      );

      // Mesma chave: devolve o mesmo alerta, sem gravar nem publicar de novo.
      final repetido = await endpoints.alerts.createRedAlert(
        sessionBuilder,
        accessToken: token.accessToken,
        idempotencyKey: 'ciclo-1',
        locationHash: 'hash-sintetico',
      );

      expect(repetido.alertId, criado.alertId);
      expect(publisher.published, hasLength(1));
      expect(await Alert.db.find(session), hasLength(1));

      final tokenAcs =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final confirmado = await endpoints.alerts.acknowledge(
        sessionBuilder,
        accessToken: tokenAcs.accessToken,
        alertId: criado.alertId,
      );

      expect(confirmado.acknowledged, isTrue);
      expect(confirmado.status, AlertStatus.acknowledged);
      expect(await AlertDeliveryRecord.db.find(session), hasLength(1));
    });

    test('a mesma chave com outra localização é rejeitada', () async {
      await _seed(sessionBuilder.build());
      final token = await endpoints.auth
          .developmentLogin(sessionBuilder, role: 'patient');

      await endpoints.alerts.createRedAlert(
        sessionBuilder,
        accessToken: token.accessToken,
        idempotencyKey: 'ciclo-2',
        locationHash: 'hash-original',
      );

      await expectLater(
        endpoints.alerts.createRedAlert(
          sessionBuilder,
          accessToken: token.accessToken,
          idempotencyKey: 'ciclo-2',
          locationHash: 'hash-diferente',
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('um ACS não pode criar alerta', () async {
      await _seed(sessionBuilder.build());
      final tokenAcs =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      await expectLater(
        endpoints.alerts.createRedAlert(
          sessionBuilder,
          accessToken: tokenAcs.accessToken,
          idempotencyKey: 'ciclo-3',
          locationHash: 'hash',
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('o dev-login desligado responde como rota inexistente', () async {
      // O servidor dart:io respondia 404, e não 403, para não revelar a
      // existência da rota. A exceção tipada preserva essa semântica.
      AlertRuntime.instance.overrideConfig(_config(enableDevLogin: false));

      await expectLater(
        endpoints.auth.developmentLogin(sessionBuilder, role: 'patient'),
        throwsA(isA<EndpointDisabledException>()),
      );
    });

    test('token inválido é recusado', () async {
      await expectLater(
        endpoints.alerts.createRedAlert(
          sessionBuilder,
          accessToken: 'lixo',
          idempotencyKey: 'ciclo-4',
          locationHash: 'hash',
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });
  });
}
