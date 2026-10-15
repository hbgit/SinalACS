import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/e2e_config.dart';
import 'support/e2e_login_core.dart';
import 'support/fake_patient_backend.dart';

Map<String, Object?> _manifesto() => {
      'microAreaId': 'm',
      'acs': {'id': 'c', 'matricula': 'E2E-1', 'password': 'senha-secreta-xyz'},
      'patients': [
        {'role': 'main', 'cpf': '52998224725', 'birthDate': '1990-01-01', 'id': 'a', 'name': 'Nome Um', 'chronic': false, 'microAreaId': 'm'},
        {'role': 'outsider', 'cpf': '11144477735', 'birthDate': '1970-02-02', 'id': 'b', 'name': 'Nome Dois', 'chronic': false, 'microAreaId': 'n'},
      ],
    };

/// Relé de mentira: responde 404 nas `naoRespondidas` primeiras chamadas e
/// depois devolve [codigo]. Guarda o `since` recebido.
Future<(HttpServer, List<String>)> _rele({required String codigo, int naoRespondidas = 0}) async {
  const relogioDoHost = 1700000000000; // diferente do relógio deste processo, de propósito
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final desdes = <String>[];
  var chamadas = 0;
  server.listen((request) async {
    if (request.uri.path == '/count') {
      desdes.add('count:${request.uri.queryParameters['since']}');
      request.response.write('2');
      await request.response.close();
      return;
    }
    if (request.uri.path == '/now') {
      request.response.write('$relogioDoHost');
      await request.response.close();
      return;
    }
    desdes.add(request.uri.queryParameters['since'] ?? '');
    if (chamadas++ < naoRespondidas) {
      request.response.statusCode = 404;
    } else {
      request.response.write(codigo);
    }
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return (server, desdes);
}

void main() {
  test('sem manifesto, não há configuração e vale o fallback de desenvolvimento', () async {
    expect(E2eConfig.fromMap(const {}), isNull);

    final backend = FakePatientBackend();
    await loginPatientWith(backend, null, relayUrl: 'http://127.0.0.1:1/code');

    expect(backend.developmentLoginCount, 1);
    expect(backend.otpRequests, isEmpty);
  });

  test('o manifesto escolhe o paciente pelo papel', () {
    final config = E2eConfig.fromMap(_manifesto())!;

    expect(config.patient('outsider').birthDate, DateTime(1970, 2, 2));
    expect(config.microAreaId, 'm');
    expect(() => config.patient('inexistente'), throwsStateError);
  });

  test('o manifesto do aparelho não traz a senha do ACS e mesmo assim é lido', () {
    final semAcs = _manifesto()..remove('acs');

    final config = E2eConfig.fromMap(semAcs)!;

    expect(config.patient('main').birthDate, DateTime(1990, 1, 1));
    expect(config.acsPassword, isEmpty);
  });

  test('toString nunca mostra CPF nem senha do ACS', () {
    final config = E2eConfig.fromMap(_manifesto())!;
    final texto = '$config ${config.patient('main')}';

    expect(texto.contains('52998224725'), isFalse);
    expect(texto.contains(config.acsPassword), isFalse);
  });

  test('com manifesto: pede o OTP da fixture, lê o código no relé e verifica com ele', () async {
    final (server, desdes) = await _rele(codigo: '123456', naoRespondidas: 2);
    final backend = FakePatientBackend();

    final session = await loginPatientWith(
      backend,
      E2eConfig.fromMap(_manifesto()),
      relayUrl: 'http://127.0.0.1:${server.port}/code',
      role: 'outsider',
      retryDelay: Duration.zero,
    );

    expect(session.role, 'patient');
    expect(backend.developmentLoginCount, 0, reason: 'com manifesto nunca usa o login de desenvolvimento');
    expect(backend.otpRequests.single.cpf, '11144477735');
    expect(backend.otpRequests.single.birthDate, DateTime(1970, 2, 2));
    expect(backend.otpVerifications.single.code, '123456');
    // O corte vem do relógio do HOST (o do relé), nunca do aparelho: um emulador
    // adiantado ou atrasado não pode fazer o relé negar o código do pedido.
    expect(desdes, hasLength(3));
    expect(desdes.every((d) => d == '1700000000000'), isTrue);
  });

  test('relayCount devolve quantos códigos o relé viu depois do corte', () async {
    final (server, desdes) = await _rele(codigo: '123456');

    final n = await relayCount('http://127.0.0.1:${server.port}/code', 42);

    expect(n, 2);
    expect(desdes, ['count:42']);
  });

  test('relé mudo: falha com a dica de subir o relé, sem chamar o verifyOtp', () async {
    final (server, _) = await _rele(codigo: 'x', naoRespondidas: 1000);
    final backend = FakePatientBackend();

    await expectLater(
      loginPatientWith(backend, E2eConfig.fromMap(_manifesto()),
          relayUrl: 'http://127.0.0.1:${server.port}/code', retryDelay: Duration.zero, attempts: 3),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('otp_relay.py'))),
    );
    expect(backend.otpVerifications, isEmpty);
  });
}
