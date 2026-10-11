import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_bootstrap.dart';
import 'package:sinalacs_admin/core/data/backend_admin_data_source.dart';

void main() {
  test('host sem https sobe recusando toda chamada, com o motivo', () async {
    final auth = buildAdminAuth(host: 'http://10.0.2.2/');
    expect(auth, isA<MisconfiguredAdminAuth>());
    await expectLater(
      auth.login(matricula: 'ADM-001', senha: 'x'),
      throwsA(isA<AdminAuthFailure>().having((e) => e.message, 'message', contains('HTTPS'))),
    );
  });

  test('host https monta o backend real, com ou sem a CA', () {
    expect(buildAdminAuth(host: 'https://10.0.2.2/'), isA<BackendAdminAuth>());
    expect(buildAdminAuth(host: 'https://10.0.2.2/', caBytes: null), isA<BackendAdminAuth>());
  });

  test('CA corrompida não é aceita em silêncio', () {
    expect(() => buildAdminAuth(host: 'https://10.0.2.2/', caBytes: const [1, 2, 3]), throwsA(anything));
  });

  test('a fiação de produção liga o painel ao backend real, nunca ao mock', () {
    final fiacao = buildAdminWiring(host: 'https://10.0.2.2/');
    expect(fiacao.auth, isA<BackendAdminAuth>());
    final sessao = AdminSession(
      accessToken: 'token-de-teste',
      userId: 'u',
      role: 'admin',
      expiresAt: DateTime.utc(2100),
    );
    expect(fiacao.dataSourceFor(sessao), isA<BackendAdminDataSource>());
  });

  test('host sem https: a fiação recusa e o painel nunca é montado sobre o mock', () {
    final fiacao = buildAdminWiring(host: 'http://10.0.2.2/');
    expect(fiacao.auth, isA<MisconfiguredAdminAuth>());
  });
}
