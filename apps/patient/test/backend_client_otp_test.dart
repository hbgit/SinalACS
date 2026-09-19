import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_rpc_server.dart';

/// O caminho do OTP (RF01) pelo [BackendClient] **real**, contra um servidor
/// RPC falso no protocolo do Serverpod.
///
/// É o único lugar onde duas coisas ficam presas: a tradução
/// `OtpRequestException → BackendFailure(mensagem do servidor, não
/// recuperável)` e a leitura do TTL do token. Nenhum teste durável passava por
/// `requestOtp`/`verifyOtp` antes deste arquivo — a suíte de widgets usa o
/// `FakePatientBackend`, que não tem `_guard` nenhum, e apagar o
/// `on OtpRequestException` de lá não deixava nada vermelho.
///
/// CPF sintético (o exemplo da documentação do dígito verificador), o mesmo que
/// o backend usa nos testes dele. Nenhum dado real.
void main() {
  const cpf = '123.456.789-09';
  final nascimento = DateTime.utc(1990, 1, 1);

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

  group('requestOtp', () {
    test('a recusa do servidor vira BackendFailure com a mensagem dele', () async {
      // A mensagem que só o servidor conhece (o app não tem cópia dela): é ela
      // que diz "confira os dados" para o dígito verificador inválido, e é ela
      // que precisa chegar à tela.
      server.rejectOtpWith = 'Confira os dados informados.';

      await expectLater(
        backend.requestOtp(cpf: cpf, birthDate: nascimento),
        throwsA(
          isA<BackendFailure>()
              .having((falha) => falha.message, 'mensagem',
                  'Confira os dados informados.')
              .having((falha) => falha.isRecoverable, 'isRecoverable', isFalse),
        ),
      );

      final pedido = server.requests.single;
      expect(pedido.endpoint, 'auth');
      expect(pedido.method, 'requestOtp');
      expect(pedido.args['cpf'], cpf);
      expect(pedido.args['birthDate'], '1990-01-01T00:00:00.000Z');
    });

    test('o 200 do pedido repetido não vira erro: a resposta é silenciosa',
        () async {
      // O caso do intervalo mínimo (`resendCooldown`): o servidor responde 200
      // sem enviar SMS novo, e **não** recusa.
      //
      // O valor deste teste é pequeno e é só DESTE lado: prender que dois
      // pedidos seguidos são tratados como sucesso, sem virar BackendFailure.
      // Ele **não** protege contra regressão do servidor, e a versão anterior
      // deste comentário dizia que sim ("se alguém reintroduzir uma exceção lá,
      // ela chega aqui como BackendFailure e este teste cai"): não cai — este
      // fake não tem cooldown nenhum, então nenhuma mudança no backend alcança
      // este arquivo. Quem pega a volta daquela exceção são os testes de
      // backend (unitário e de endpoint), medido.
      await backend.requestOtp(cpf: cpf, birthDate: nascimento);
      await backend.requestOtp(cpf: cpf, birthDate: nascimento);

      expect(server.otpRequests, 2);
    });
  });

  group('verifyOtp', () {
    test('a recusa vira BackendFailure com a mensagem do servidor', () async {
      server.rejectVerifyWith = 'Código inválido ou expirado. Peça um novo.';

      await expectLater(
        backend.verifyOtp(cpf: cpf, code: '000000'),
        throwsA(
          isA<BackendFailure>()
              .having((falha) => falha.message, 'mensagem',
                  'Código inválido ou expirado. Peça um novo.')
              .having((falha) => falha.isRecoverable, 'isRecoverable', isFalse),
        ),
      );
      expect(backend.isAuthenticated, isFalse);
    });

    test('a sessão sai com o TTL que está no token, e não com um suposto',
        () async {
      // Dois valores diferentes: o app lê o `exp` do token (é o servidor que
      // decide, e o RF01 decide 1 hora — `AuthEndpoint.patientSessionLifetime`).
      // Um teste só com 1 hora passaria também se o app cravasse a hora, e é
      // essa suposição que o segundo valor mata.
      server.tokenLifetime = const Duration(hours: 1);
      final umaHora = await backend.verifyOtp(cpf: cpf, code: '123456');
      expect(
        umaHora.expiresAt.difference(DateTime.now().toUtc()),
        greaterThan(const Duration(minutes: 59)),
      );

      server.tokenLifetime = const Duration(minutes: 15);
      final quinzeMinutos = await backend.verifyOtp(cpf: cpf, code: '123456');
      expect(
        quinzeMinutos.expiresAt.difference(DateTime.now().toUtc()),
        lessThan(const Duration(minutes: 16)),
      );

      expect(umaHora.role, 'patient');
      expect(umaHora.microAreaId, server.microAreaId);
      expect(backend.isAuthenticated, isTrue);
    });

    test('token já vencido deixa o app sem sessão utilizável', () async {
      // O caminho que a sessão de 1 hora produz no fim da vida: o app não
      // renova (não há o que renovar — o código OTP é de uso único), então a
      // chamada autenticada seguinte tem de falhar alto, e não sair com um
      // token vencido.
      server.tokenLifetime = const Duration(minutes: -1);
      final vencida = await backend.verifyOtp(cpf: cpf, code: '123456');

      expect(vencida.isExpired(), isTrue);
      expect(backend.isAuthenticated, isFalse);
    });
  });
}
