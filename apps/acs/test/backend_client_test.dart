import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/telemetry/app_version.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fake_rpc_server.dart';

/// Testes do `BackendClient` de verdade, contra um servidor que fala o
/// protocolo do cliente gerado — ver `support/fake_rpc_server.dart`.
///
/// A sessão de 15 minutos é renovada pelo refresh token rotativo; a senha não é
/// retida. Nenhum teste daqui usa senha real: as credenciais são sintéticas e o
/// servidor é local.
void main() {
  late FakeRpcServer server;
  late BackendClient backend;

  setUp(() async {
    server = await FakeRpcServer.start();
    backend = BackendClient(host: server.host, tokenStore: MemorySessionTokenStore(), deviceIds: MemoryDeviceIdStore());
  });

  tearDown(() async {
    backend.close();
    await server.stop();
  });

  test('envia a matrícula e a senha ao backend e abre a sessão', () async {
    final session = await backend.login(
      matricula: 'ACS-001',
      senha: 'senha-sintetica',
    );

    expect(session.role, 'acs');
    expect(session.microAreaId, server.microAreaId);
    expect(session.userId, server.userId);
    expect(backend.isAuthenticated, isTrue);

    final request = server.requests.single;
    expect(request.endpoint, 'auth');
    expect(request.method, 'loginInstitutional');
    expect(request.args['matricula'], 'ACS-001');
    expect(request.args['password'], 'senha-sintetica');
    expect(request.args['deviceId'], isNotEmpty, reason: 'sem deviceId o servidor não emite refresh token');
  });

  test('credencial recusada vira falha não recuperável com a mensagem do servidor', () async {
    // A mensagem é a do servidor de propósito: é ela que distingue "senha
    // errada" de "bloqueado por tentativas", e é a mesma para matrícula
    // inexistente — o app não tenta adivinhar qual dos dois foi.
    server.rejectWith = 'Matrícula ou senha inválidos.';

    await expectLater(
      backend.login(matricula: 'ACS-001', senha: 'errada'),
      throwsA(
        isA<BackendFailure>()
            .having((f) => f.message, 'message', 'Matrícula ou senha inválidos.')
            .having((f) => f.isRecoverable, 'isRecoverable', isFalse),
      ),
    );
    expect(backend.isAuthenticated, isFalse);
  });

  test('token expirado renova a sessão pelo refresh token, sem reenviar a senha', () async {
    // Um turno de campo dura mais que o token de 15 minutos.
    server.tokenLifetime = const Duration(minutes: -1);

    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
    expect(backend.isAuthenticated, isFalse, reason: 'o token emitido já nasce vencido');
    expect(server.loginCount, 1);

    await backend.listPatients();

    expect(server.loginCount, 1, reason: 'a senha não é reenviada');
    expect(server.refreshCount, 1);
    expect(server.requests.last.method, 'listMicroArea');
    expect(server.requests.last.args['accessToken'], isNotEmpty);
    expect(server.requests.map((r) => r.method), isNot(contains('developmentLogin')));
  });

  test('sem refresh token a renovação falha de forma não recuperável', () async {
    // Uma instância que nunca autenticou: não há token de onde tirar.
    await expectLater(
      backend.listPatients(),
      throwsA(
        isA<BackendFailure>()
            .having((f) => f.message, 'message', 'Sua sessão expirou. Entre novamente.')
            .having((f) => f.isRecoverable, 'isRecoverable', isFalse),
      ),
    );
    // A prova de que o reauth silencioso acabou: o servidor não recebeu
    // chamada nenhuma. Antes, este caminho chamava `login()` sozinho.
    expect(server.requests, isEmpty);
  });

  test('developmentLogin continua disponível para as ferramentas', () async {
    // Não é o caminho do produto, mas `tool/live_check.dart` e o
    // `integration_test/` rodam com `ENABLE_DEV_LOGIN=true` e dependem dele.
    final session = await backend.developmentLogin(role: 'acs');

    expect(session.role, 'acs');
    expect(session.microAreaId, server.microAreaId);
    expect(server.requests.single.method, 'developmentLogin');
    expect(server.requests.single.args['role'], 'acs');
  });

  /// RNF04/L-08: o host do `--dart-define` não pode voltar para http. A Task 4
  /// mediu que o `network_security_config.xml` não bloqueia o cleartext do
  /// `dart:io`, então esta validação é a única barreira que sobrou — e é aqui
  /// que ela fica vermelha se alguém a apagar.
  test('generateInvite pede o convite do paciente com o token da sessão', () async {
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');

    final invite = await backend.generateInvite(
      patientId: '00000000-0000-4000-8000-000000000005',
    );

    expect(invite.token, 'convite-sintetico');
    expect(invite.expiresAt, DateTime.utc(2026, 9, 29, 10, 15));
    final request = server.requests.last;
    expect(request.endpoint, 'onboarding');
    expect(request.method, 'generateEnrollmentToken');
    expect(request.args['patientId'], '00000000-0000-4000-8000-000000000005');
    expect(request.args['accessToken'], isNotEmpty);
  });

  test('generateInvite recusado por território vira mensagem de paciente fora da microárea', () async {
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
    server.rejectInviteWithPermission = true;

    await expectLater(
      backend.generateInvite(patientId: '00000000-0000-4000-8000-000000000009'),
      throwsA(
        isA<BackendFailure>()
            .having((f) => f.message, 'message', 'Este paciente não pertence à sua microárea.')
            .having((f) => f.isRecoverable, 'isRecoverable', isFalse),
      ),
    );
  });

  group('resolução de conflito de visita (#79)', () {
    VisitSyncEntry entrada({Map<String, String> notes = const {'campo': 'obs editada'}}) => VisitSyncEntry(
          localId: '00000000-0000-4000-8000-0000000000c1',
          patientId: '00000000-0000-4000-8000-000000000001',
          scheduledAt: DateTime.utc(2026, 10, 16, 9),
          completedAt: DateTime.utc(2026, 10, 16, 9, 30),
          status: 'Paciente ausente',
          riskLevelBefore: RiskLevel.red,
          notes: notes,
          version: 1,
          arrivalMethod: ArrivalMethod.manual,
        );

    test('resolveVisitConflict recusa sessão de outro dono', () async {
      await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');

      await expectLater(
        backend.resolveVisitConflict(entrada(), expectedServerVersion: 3, expectedUserId: 'outro-acs'),
        throwsA(same(sessionOwnerMismatch)),
      );
      expect(server.requests.where((r) => r.method == 'resolveConflict'), isEmpty,
          reason: 'a decisão de um ACS nunca sai com o token de outro');
    });

    test('resolveVisitConflict envia a versão vista com a sessão do próprio dono', () async {
      final sessao = await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');

      final resultado = await backend.resolveVisitConflict(
        entrada(),
        expectedServerVersion: 3,
        expectedUserId: sessao.userId,
      );

      expect(resultado.syncStatus, SyncStatus.synced);
      expect(resultado.serverVersion, 4);
      final pedido = server.requests.singleWhere((r) => r.method == 'resolveConflict');
      expect(pedido.endpoint, 'visits');
      expect(pedido.args['expectedServerVersion'], 3);
      expect(pedido.args['accessToken'], isNotEmpty);
    });

    test('conflictSnapshotFor usa o campo das observações, ou une os valores sem ele', () {
      final comCampo = conflictSnapshotFor(entrada(notes: {'campo': 'obs do servidor', 'outro': 'x'}));
      expect(comCampo.notes, 'obs do servidor');
      expect(comCampo.version, 1);
      expect(comCampo.status, 'Paciente ausente');
      expect(comCampo.completedAt, DateTime.utc(2026, 10, 16, 9, 30));

      final semCampo = conflictSnapshotFor(entrada(notes: {'a': 'primeira', 'b': 'segunda'}));
      expect(semCampo.notes, 'primeira\nsegunda');

      expect(conflictSnapshotFor(entrada(notes: const {})).notes, '');
    });
  });

  group('telemetria (#83)', () {
    TelemetryEventRecord evento(String dono) => TelemetryEventRecord(
          eventId: '0000000a-0000-4000-8000-0000000000e1',
          owner: dono,
          name: 'sync_attempt',
          occurredAt: DateTime.utc(2026, 10, 25, 12),
          payload: const {'records_count': 3, 'network_type': 'wifi', 'channel': 'sync'},
        );

    test('uploader recusa sessão de outro dono', () async {
      await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');

      await expectLater(
        backend.ingestTelemetry([evento('outro-acs')], expectedUserId: 'outro-acs'),
        throwsA(isA<BackendFailure>()),
      );
      expect(server.requests.where((r) => r.method == 'ingest'), isEmpty,
          reason: 'eventos de A nunca sobem com o token de B');
    });

    test('ingestTelemetry envia o lote com deviceId, sentAt e versão do app', () async {
      final sessao = await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
      final deviceIdDoLogin = server.requests.single.args['deviceId'];
      final antes = DateTime.now().toUtc();

      final ack = await backend.ingestTelemetry([evento(sessao.userId)], expectedUserId: sessao.userId);

      expect(ack.accepted, {'0000000a-0000-4000-8000-0000000000e1'});
      expect(ack.rejected, isEmpty);
      final pedido = server.requests.singleWhere((r) => r.method == 'ingest');
      expect(pedido.endpoint, 'telemetry');
      expect(pedido.args['accessToken'], isNotEmpty);
      expect(pedido.args['deviceId'], deviceIdDoLogin, reason: 'o mesmo DeviceIdStore do login');
      final sentAt = DateTime.parse(pedido.args['sentAt'] as String);
      expect(sentAt.isUtc, isTrue);
      expect(sentAt.isBefore(antes.subtract(const Duration(seconds: 1))), isFalse);
      final enviado = (pedido.args['events'] as List).single as Map<String, dynamic>;
      expect(enviado['eventId'], '0000000a-0000-4000-8000-0000000000e1');
      expect(enviado['eventName'], 'sync_attempt');
      expect(enviado['appVersion'], acsAppVersion);
      expect(jsonDecode(enviado['payloadJson'] as String),
          {'records_count': 3, 'network_type': 'wifi', 'channel': 'sync'});
      expect(enviado.containsKey('owner'), isFalse, reason: 'o autor vem do token');
    });
  });

  group('certificado do aparelho (#94)', () {
    test('issueDeviceCertificate envia o CSR com o token e devolve a folha', () async {
      await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');

      final emitido = await backend.issueDeviceCertificate('CSR-SINTETICO');

      final pedido = server.requests.lastWhere((r) => r.method == 'issueCertificate');
      expect(pedido.endpoint, 'devices');
      expect(pedido.args['csrPem'], 'CSR-SINTETICO');
      expect(pedido.args['accessToken'], backend.session!.accessToken);
      expect(emitido.certificatePem, 'CERT-SINTETICO');
      expect(emitido.serial, '0a1b');
      expect(emitido.notAfter, DateTime.utc(2026, 11, 26, 12));
      expect(emitido.serverNow, DateTime.utc(2026, 10, 27, 12));
    });

    test('DeviceWipeRequiredException vira DeviceWipeRequiredFailure e avisa onDeviceWipeRequired', () async {
      await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
      final pedidos = <String>[];
      backend.onDeviceWipeRequired = pedidos.add;
      server.issueCertificateRefusal = {
        'className': 'DeviceWipeRequiredException',
        'data': {'orderId': 'ordem-1', 'message': 'Este aparelho precisa ser limpo.'},
      };

      await expectLater(
        backend.issueDeviceCertificate('CSR-SINTETICO'),
        throwsA(isA<DeviceWipeRequiredFailure>().having((f) => f.orderId, 'orderId', 'ordem-1')),
      );
      expect(pedidos, ['ordem-1']);
    });

    test('AlertValidationException vira BackendFailure não recuperável com o texto do servidor', () async {
      await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
      server.issueCertificateRefusal = {
        'className': 'AlertValidationException',
        'data': {'message': 'CSR inválido.'},
      };

      await expectLater(
        backend.issueDeviceCertificate('CSR-SINTETICO'),
        throwsA(isA<BackendFailure>()
            .having((f) => f, 'tipo', isNot(isA<DeviceWipeRequiredFailure>()))
            .having((f) => f.message, 'message', 'CSR inválido.')
            .having((f) => f.isRecoverable, 'isRecoverable', isFalse)),
      );
    });

    test('AlertPermissionException vira BackendFailure não recuperável sem falar de alerta', () async {
      await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
      server.issueCertificateRefusal = {
        'className': 'AlertPermissionException',
        'data': {'message': 'Recusado.'},
      };

      await expectLater(
        backend.issueDeviceCertificate('CSR-SINTETICO'),
        throwsA(isA<BackendFailure>()
            .having((f) => f.message, 'message', isNot(contains('alerta')))
            .having((f) => f.isRecoverable, 'isRecoverable', isFalse)),
      );
    });

    test('sem servidor a emissão é falha recuperável', () async {
      await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
      await server.stop();

      await expectLater(
        backend.issueDeviceCertificate('CSR-SINTETICO'),
        throwsA(isA<BackendFailure>().having((f) => f.isRecoverable, 'isRecoverable', isTrue)),
      );
    });
  });

  group('host do RPC', () {
    test('recusa http — a porta em texto claro não existe mais', () {
      expect(
        () => requireSecureHost('http://10.0.2.2:8080/'),
        throwsA(
          isA<BackendFailure>()
              .having((f) => f.isRecoverable, 'isRecoverable', isFalse)
              .having((f) => f.message, 'message', contains('https')),
        ),
      );
      // Sem host nenhum também é recusa, e não um cliente sem endereço.
      expect(() => requireSecureHost(''), throwsA(isA<BackendFailure>()));
      expect(() => requireSecureHost('10.0.2.2'), throwsA(isA<BackendFailure>()));
    });

    test('aceita https e devolve o mesmo endereço', () {
      expect(requireSecureHost('https://10.0.2.2/'), 'https://10.0.2.2/');
    });

    test('o default de compilação é https', () {
      // O valor que o APK carrega sem nenhum --dart-define.
      expect(BackendConfig.host, startsWith('https://'));
      expect(BackendClient.resolveHost(null), BackendConfig.host);
    });

    test('valida quando o cliente cai no default, não quando o host é explícito', () {
      // O caminho do `--dart-define`: validado (é o defeito que este teste
      // prende). `defaultHost` existe porque o valor real é resolvido em tempo
      // de compilação e não muda dentro de um `flutter test`.
      expect(
        () => BackendClient.resolveHost(null, defaultHost: 'http://10.0.2.2:8080/'),
        throwsA(isA<BackendFailure>()),
      );

      // O caminho dos testes herméticos, que apontam para servidores fake em
      // `http://127.0.0.1:<porta efêmera>/`: passa como veio.
      expect(
        BackendClient.resolveHost('http://127.0.0.1:4444/'),
        'http://127.0.0.1:4444/',
      );
    });
  });
}
