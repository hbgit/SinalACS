import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/alert_outbox_dispatcher.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/endpoints/health_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/fake_mqtt_broker.dart';
import '../support/health_data_fixtures.dart';
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

  /// Quando verdadeiro, simula o broker fora do ar.
  bool offline = false;

  @override
  void publish(AlertDelivery alert) {
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

AppConfig _config({required bool enableDevLogin}) => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      // Hex de 64 caracteres: HealthDataCipher decodifica byte a byte
      // para montar a chave AES-256 (ver AppConfig).
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      smsGateway: 'log',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: enableDevLogin,
    );

/// Dispatcher MQTT real apontado ao [FakeMqttBroker] (TCP plano em
/// 127.0.0.1). O canal de produção é TLS/mTLS: a queda por RST/EPIPE real do
/// socket TLS foi provada no Docker (Tarefa 7v da #56); aqui o que se prova é o
/// caminho outbox → dispatcher → reconexão, que não depende da camada TLS.
AppConfig _mqttConfig(int port) => AppConfig(
      mqttBroker: '127.0.0.1:$port',
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

/// Polling a cada 25 ms até [cond] valer; falha depois de [timeout].
Future<void> _until(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final limite = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(limite)) fail('timeout');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// Publisher que executa [antes] e só então delega ao dispatcher real.
///
/// Usado no experimento H5 para derrubar o socket no instante exato entre a
/// checagem de estado e a escrita: o dispatcher ainda vê `connected` porque o
/// evento de fim de conexão só é processado num turno seguinte do event loop.
class _PublisherComGancho implements AlertPublisher {
  _PublisherComGancho(this._real, this.antes);

  final AlertPublisher _real;
  void Function() antes;

  @override
  void publish(AlertDelivery alert) {
    antes();
    _real.publish(alert);
  }
}

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
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
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

    test('a sonda de saúde segue respondendo ok quando a verificação do banco falha',
        () async {
      final endpoint = HealthEndpoint(
        databaseProbe: (_) async => throw Exception('db indisponível'),
      );

      final health = await endpoint.check(sessionBuilder.build());

      expect(health.status, 'ok');
      expect(health.dbConnected, isFalse);
    });

    test('a triagem classifica de forma determinística', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      final vermelho = await endpoints.triage.evaluate(
        sessionBuilder,
        accessToken: login.accessToken,
        chestPain: true,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );
      expect(vermelho.risk, RiskLevel.red);

      final verde = await endpoints.triage.evaluate(
        sessionBuilder,
        accessToken: login.accessToken,
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );
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
      // A publicação acontece depois do commit, ainda dentro da chamada.
      expect(criado.published, isTrue);
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

    test('confirmar um alerta inexistente devolve acknowledged false, sem erro',
        () async {
      await _seed(sessionBuilder.build());
      final tokenAcs =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      final ack = await endpoints.alerts.acknowledge(
        sessionBuilder,
        accessToken: tokenAcs.accessToken,
        alertId: '00000000-0000-4000-8000-0000000000ff',
      );

      expect(ack.alertId, '00000000-0000-4000-8000-0000000000ff');
      expect(ack.acknowledged, isFalse);
      expect(ack.status, isNull);
    });

    test('paciente consulta o status do próprio alerta mais recente', () async {
      await _seed(sessionBuilder.build());
      final token =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      final semAlerta =
          await endpoints.alerts.statusFor(sessionBuilder, accessToken: token.accessToken);
      expect(semAlerta.found, isFalse);
      expect(semAlerta.alertId, isNull);

      final criado = await endpoints.alerts.createRedAlert(
        sessionBuilder,
        accessToken: token.accessToken,
        idempotencyKey: 'status-1',
        locationHash: 'hash-sintetico',
      );

      final status =
          await endpoints.alerts.statusFor(sessionBuilder, accessToken: token.accessToken);
      expect(status.found, isTrue);
      expect(status.alertId, criado.alertId);
      expect(status.status, AlertStatus.pending);
      expect(status.acknowledgedAt, isNull);

      final tokenAcs =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      await endpoints.alerts.acknowledge(
        sessionBuilder,
        accessToken: tokenAcs.accessToken,
        alertId: criado.alertId,
      );

      final statusDepoisDoAck =
          await endpoints.alerts.statusFor(sessionBuilder, accessToken: token.accessToken);
      expect(statusDepoisDoAck.status, AlertStatus.acknowledged);
      expect(statusDepoisDoAck.acknowledgedAt, isNotNull);
    });

    test('um ACS não pode consultar alerts.statusFor', () async {
      await _seed(sessionBuilder.build());
      final tokenAcs =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      expect(
        () => endpoints.alerts.statusFor(sessionBuilder, accessToken: tokenAcs.accessToken),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('confirmar com alertId vazio é rejeitado pelo endpoint', () async {
      await _seed(sessionBuilder.build());
      final tokenAcs =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      await expectLater(
        endpoints.alerts.acknowledge(
          sessionBuilder,
          accessToken: tokenAcs.accessToken,
          alertId: '   ',
        ),
        throwsA(isA<AlertValidationException>()),
      );
    });

    test('com o broker fora, o alerta é gravado e a entrega fica pendente',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);
      publisher.offline = true;

      final token = await endpoints.auth
          .developmentLogin(sessionBuilder, role: 'patient');

      final criado = await endpoints.alerts.createRedAlert(
        sessionBuilder,
        accessToken: token.accessToken,
        idempotencyKey: 'outbox-1',
        locationHash: 'hash-outbox',
      );

      // O contrato mudou: o alerta é aceito e enfileirado em vez de recusado.
      expect(criado.published, isFalse);
      expect(publisher.published, isEmpty);

      // Mas está gravado — é isso que o risco invertido quebrava.
      expect(await Alert.db.find(session), hasLength(1));
      final pendentes = await AlertOutboxEntry.db.find(session);
      expect(pendentes, hasLength(1));
      expect(pendentes.single.publishedAt, isNull);

      // A tentativa imediata falhou e adiou a entrada pelo backoff, então a
      // varredura só a reclama depois da janela — daí o relógio adiantado.
      publisher.offline = false;
      final publicadas = await AlertRuntime.instance
          .dispatcherFor(session,
              clock: () => DateTime.now().toUtc().add(const Duration(minutes: 5)))
          .drainOnce();

      expect(publicadas, 1);
      expect(publisher.published, hasLength(1));
      expect(publisher.published.single.alertId, criado.alertId);

      final depois = await AlertOutboxEntry.db.find(session);
      expect(depois.single.publishedAt, isNotNull);

      // E o ACK encontra a linha, que era o que se perdia antes.
      final tokenAcs =
          await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final confirmado = await endpoints.alerts.acknowledge(
        sessionBuilder,
        accessToken: tokenAcs.accessToken,
        alertId: criado.alertId,
      );
      expect(confirmado.acknowledged, isTrue);
    });

    group('com o MqttAlertDispatcher real e o broker falso', () {
      late FakeMqttBroker broker;
      late MqttAlertDispatcher dispatcher;
      late List<Object> fatais;

      setUp(() async {
        broker = await FakeMqttBroker.start();
        fatais = <Object>[];
        dispatcher = MqttAlertDispatcher(
          config: _mqttConfig(broker.port),
          initialBackoff: const Duration(milliseconds: 100),
          maxBackoff: const Duration(milliseconds: 400),
          onFatal: fatais.add,
          log: (_) {},
        );
        AlertRuntime.instance.overridePublisher(dispatcher);
      });

      tearDown(() async {
        await dispatcher.close();
        await broker.close();
        expect(fatais, isEmpty, reason: 'onFatal não devia ser chamado');
      });

      Future<RedAlertResult> criarAlerta(String chave) async {
        final token = await endpoints.auth
            .developmentLogin(sessionBuilder, role: 'patient');
        return endpoints.alerts.createRedAlert(
          sessionBuilder,
          accessToken: token.accessToken,
          idempotencyKey: chave,
          locationHash: 'hash-$chave',
        );
      }

      Future<bool> confirmar(String alertId) async {
        final tokenAcs =
            await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
        final ack = await endpoints.alerts.acknowledge(
          sessionBuilder,
          accessToken: tokenAcs.accessToken,
          alertId: alertId,
        );
        return ack.acknowledged;
      }

      AlertOutboxDispatcher drenador(Session session) =>
          AlertRuntime.instance.dispatcherFor(
            session,
            clock: () =>
                DateTime.now().toUtc().add(const Duration(minutes: 5)),
          );

      test(
          'alerta criado com o broker fora é entregue depois da reconexão, '
          'uma vez só (#56)', () async {
        final session = sessionBuilder.build();
        await _seed(session);

        await dispatcher.connect();
        expect(dispatcher.isConnected, isTrue);

        // Interrupção: o broker some (conexões e porta).
        final porta = broker.port;
        await broker.close();
        await _until(() => !dispatcher.isConnected);

        final criado = await criarAlerta('queda-1');
        final alertId = criado.alertId;
        // Aceito e enfileirado, não recusado (INV-03).
        expect(criado.published, isFalse);
        expect(await Alert.db.find(session), hasLength(1));
        final pendentes = await AlertOutboxEntry.db.find(session);
        expect(pendentes, hasLength(1));
        expect(pendentes.single.publishedAt, isNull);

        // O broker volta na MESMA porta; o dispatcher reconecta sozinho.
        broker = await FakeMqttBroker.start(port: porta);
        await _until(() => dispatcher.isConnected && broker.connectCount >= 1);

        // A tentativa imediata adiou a entrada pelo backoff do outbox: o
        // relógio adiantado faz a varredura reclamá-la.
        final publicadas = await drenador(session).drainOnce();
        expect(publicadas, 1);
        await _until(() => broker.publishCount == 1);
        final depois = await AlertOutboxEntry.db.find(session);
        expect(depois.single.publishedAt, isNotNull);

        // Segunda varredura: nada a publicar, sem duplicidade.
        expect(await drenador(session).drainOnce(), 0);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(broker.publishCount, 1);

        expect(await confirmar(alertId), isTrue);
      });

      // H5 (#56) — LACUNA DOCUMENTADA, NÃO CORRIGIDA NESTA TAREFA.
      //
      // Estes dois testes afirmam o comportamento ATUAL, que viola INV-03:
      // `publish()` é síncrono e devolve assim que a mensagem vai para o
      // buffer do socket, sem esperar PUBACK, e o outbox marca `publishedAt`
      // logo depois. Uma reconexão cria um cliente MQTT NOVO (sessão limpa),
      // então a mensagem QoS 1 em voo do cliente antigo nunca é retransmitida.
      // Quando a correção (publicação confirmada por PUBACK) entrar, estes
      // testes devem falhar e ser invertidos.
      test(
          'H5 (lacuna, comportamento atual): socket morto antes de o '
          'dispatcher perceber — outbox marca publicado e o broker nunca '
          'recebe', () async {
        final session = sessionBuilder.build();
        await _seed(session);
        await dispatcher.connect();
        expect(dispatcher.isConnected, isTrue);

        // O broker derruba as conexões no mesmo turno em que o dispatcher
        // vai escrever: o estado da biblioteca ainda diz `connected`.
        final gancho = _PublisherComGancho(dispatcher, broker.dropClients);
        AlertRuntime.instance.overridePublisher(gancho);

        final criado = await criarAlerta('h5-socket-morto');
        gancho.antes = () {};

        // publish() devolveu sem erro: o endpoint relata entrega.
        expect(criado.published, isTrue);
        final entrada = (await AlertOutboxEntry.db.find(session)).single;
        expect(entrada.publishedAt, isNotNull,
            reason: 'H5: marcado publicado sem PUBACK');

        // O dispatcher percebe a queda e reconecta com um cliente novo.
        await _until(() => broker.connectCount >= 2 && dispatcher.isConnected);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(broker.publishCount, 0,
            reason: 'H5: nem o cliente antigo entregou, nem o novo retransmite');

        // E o outbox não tem mais o que entregar: a mensagem está perdida
        // para o canal MQTT (o alerta segue gravado e pendente no banco).
        expect(await drenador(session).drainOnce(), 0);
        expect(broker.publishCount, 0);
        final alerta = (await Alert.db.find(session)).single;
        expect(alerta.id.toString(), criado.alertId);
        expect(alerta.status, AlertStatus.pending);
      });

      test(
          'H5 (lacuna, comportamento atual): broker recebe o PUBLISH, não '
          'responde PUBACK e cai — outbox já marcou publicado e não há '
          'retransmissão', () async {
        final session = sessionBuilder.build();
        await _seed(session);
        await dispatcher.connect();
        expect(dispatcher.isConnected, isTrue);
        broker.dropOnPublish = true;

        final criado = await criarAlerta('h5-sem-puback');

        expect(criado.published, isTrue);
        final entrada = (await AlertOutboxEntry.db.find(session)).single;
        expect(entrada.publishedAt, isNotNull,
            reason: 'H5: marcado publicado antes de qualquer PUBACK');

        await _until(() => broker.publishCount == 1);
        broker.dropOnPublish = false;
        await _until(() => broker.connectCount >= 2 && dispatcher.isConnected);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        // Sem PUBACK, o QoS 1 pediria retransmissão; o cliente novo não a faz.
        expect(broker.publishCount, 1);
        expect(await drenador(session).drainOnce(), 0);
        expect(broker.publishCount, 1);
      });
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
