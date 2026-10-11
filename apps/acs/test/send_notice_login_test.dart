import 'package:flutter_test/flutter_test.dart';

import '../tool/send_notice_login.dart';

void main() {
  test('sem variáveis, não há credencial e vale o login de desenvolvimento', () {
    expect(acsCredentialsFromEnv(const {}), isNull);
    expect(acsCredentialsFromEnv(const {'ACS_MATRICULA': '', 'ACS_PASSWORD': ''}), isNull);
  });

  test('com as duas variáveis, devolve matrícula e senha', () {
    final credentials = acsCredentialsFromEnv(const {'ACS_MATRICULA': 'E2E-1', 'ACS_PASSWORD': 'segredo'})!;

    expect(credentials.matricula, 'E2E-1');
    expect(credentials.password, 'segredo');
  });

  test('só uma das duas é um erro que nomeia a que falta, sem mostrar valores', () {
    expect(
      () => acsCredentialsFromEnv(const {'ACS_MATRICULA': 'E2E-1'}),
      throwsA(isA<ArgumentError>().having((e) => e.message, 'message', allOf(contains('ACS_PASSWORD'), isNot(contains('E2E-1'))))),
    );
    expect(
      () => acsCredentialsFromEnv(const {'ACS_PASSWORD': 'segredo'}),
      throwsA(isA<ArgumentError>().having((e) => e.message, 'message', allOf(contains('ACS_MATRICULA'), isNot(contains('segredo'))))),
    );
  });

  test('toString da credencial nunca mostra a senha', () {
    final credentials = acsCredentialsFromEnv(const {'ACS_MATRICULA': 'E2E-1', 'ACS_PASSWORD': 'segredo-xyz'})!;

    expect('$credentials'.contains('segredo-xyz'), isFalse);
  });
}
