import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';

import 'support/fake_rpc_server.dart';

/// Testes do `BackendClient` de verdade, contra um servidor que fala o
/// protocolo do cliente gerado — ver `support/fake_rpc_server.dart`.
///
/// É o único lugar onde a decisão de projeto desta task é observável: a
/// credencial do ACS vive **apenas em memória** e é ela que renova a sessão de
/// 15 minutos. Nenhum teste daqui usa senha real: as credenciais são sintéticas
/// e o servidor é local.
void main() {
  late FakeRpcServer server;
  late BackendClient backend;

  setUp(() async {
    server = await FakeRpcServer.start();
    backend = BackendClient(host: server.host);
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

  test('token expirado renova a sessão reenviando a credencial em memória', () async {
    // O comportamento que o app já tinha e que esta task preserva: um turno de
    // campo dura mais que o token de 15 minutos, e sem renovação o ACS passa a
    // ver erro de permissão no meio do trabalho.
    server.tokenLifetime = const Duration(minutes: -1);

    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
    expect(
      backend.isAuthenticated,
      isFalse,
      reason: 'o token emitido pelo servidor de teste já nasce vencido',
    );
    expect(server.loginCount, 1);

    // Qualquer chamada autenticada passa por `_requireToken` antes de sair.
    await backend.listPatients();

    expect(server.loginCount, 2, reason: 'a sessão tinha de ser renovada');
    final renewals =
        server.requests.where((request) => request.method == 'loginInstitutional');
    final renewal = renewals.last;
    expect(renewal.args['matricula'], 'ACS-001');
    expect(renewal.args['password'], 'senha-sintetica');
    // A chamada que disparou a renovação ainda saiu, depois dela.
    expect(server.requests.last.method, 'listMicroArea');
    expect(server.requests.last.args['accessToken'], isNotEmpty);
    // E a renovação é a credencial da pessoa, nunca o atalho de
    // desenvolvimento: era esse o reauth silencioso que a task aposentou.
    expect(
      server.requests.map((request) => request.method),
      isNot(contains('developmentLogin')),
    );
  });

  test('sem credencial em memória a renovação falha de forma não recuperável', () async {
    // Uma instância que nunca autenticou: não há credencial de onde tirar.
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
