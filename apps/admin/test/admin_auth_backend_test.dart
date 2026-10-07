import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';
import 'package:sinalacs_admin/core/auth/backend_config.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fake_admin_auth.dart';

String _jwt(Map<String, Object?> payload) {
  String b64(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64(payload)}.sig';
}

DevelopmentLoginResult _result(String token) =>
    DevelopmentLoginResult(accessToken: token, tokenType: 'Bearer');

BackendAdminAuth _backend(FakeEndpointCaller caller) =>
    BackendAdminAuth(EndpointAuth(caller));

void main() {
  group('AdminSession.fromToken', () {
    test('papel admin vira sessão e expiresAt vem de exp', () {
      final s = AdminSession.fromToken(
        _jwt({'sub': 'u1', 'role': 'admin', 'exp': 4102444800}),
      );
      expect(s.role, 'admin');
      expect(s.userId, 'u1');
      expect(s.expiresAt, DateTime.utc(2100, 1, 1));
    });

    test('coordinator é aceito', () {
      expect(
        AdminSession.fromToken(
          _jwt({'sub': 'u', 'role': 'coordinator', 'exp': 4102444800}),
        ).role,
        'coordinator',
      );
    });

    for (final role in ['acs', 'patient']) {
      test('papel $role é recusado pelo app', () {
        final token = _jwt({'sub': 'u', 'role': role, 'exp': 4102444800});
        expect(
          () => AdminSession.fromToken(token),
          throwsA(isA<AdminAuthFailure>()),
        );
      });
    }

    for (final token in [
      'lixo',
      'a.b.c',
      'a.${base64Url.encode(utf8.encode('[]'))}.c',
    ]) {
      test('token malformado "$token" é recusado', () {
        expect(
          () => AdminSession.fromToken(token),
          throwsA(isA<AdminAuthFailure>()),
        );
      });
    }

    test('payload sem exp é recusado', () {
      expect(
        () => AdminSession.fromToken(_jwt({'sub': 'u', 'role': 'admin'})),
        throwsA(isA<AdminAuthFailure>()),
      );
    });
  });

  group('BackendAdminAuth.login', () {
    test('sucesso devolve a sessão e repassa os argumentos', () async {
      final caller = FakeEndpointCaller(
        result: _result(_jwt({'sub': 'u', 'role': 'admin', 'exp': 4102444800})),
      );
      final s = await _backend(
        caller,
      ).login(matricula: 'ADM-001', senha: 'x', totpCode: '123456');
      expect(s.role, 'admin');
      expect(caller.lastArgs, {
        'matricula': 'ADM-001',
        'password': 'x',
        'totpCode': '123456',
      });
    });

    test('token de ACS emitido pelo servidor é recusado', () {
      final caller = FakeEndpointCaller(
        result: _result(_jwt({'sub': 'u', 'role': 'acs', 'exp': 4102444800})),
      );
      expect(
        _backend(caller).login(matricula: 'a', senha: 'b'),
        throwsA(isA<AdminAuthFailure>()),
      );
    });

    Future<Object?> falha(Object error) async {
      try {
        await _backend(
          FakeEndpointCaller(error: error),
        ).login(matricula: 'a', senha: 'b');
      } catch (e) {
        return e;
      }
      return null;
    }

    test('MfaRequiredException -> AdminMfaCodeRequired', () async {
      expect(
        await falha(MfaRequiredException(message: 'm')),
        isA<AdminMfaCodeRequired>(),
      );
    });

    test(
      'MfaEnrollmentRequiredException -> AdminMfaEnrollmentRequired',
      () async {
        expect(
          await falha(MfaEnrollmentRequiredException(message: 'm')),
          isA<AdminMfaEnrollmentRequired>(),
        );
      },
    );

    test(
      'AuthenticationFailedException mantém a mensagem do servidor',
      () async {
        final e = await falha(
          AuthenticationFailedException(message: 'Bloqueado'),
        );
        expect(e, isA<AdminAuthFailure>());
        expect((e as AdminAuthFailure).message, 'Bloqueado');
      },
    );

    test('SocketException -> sem conexão', () async {
      final e = await falha(const SocketException('x')) as AdminAuthFailure;
      expect(e.message, 'Não foi possível conectar ao servidor.');
    });

    test('ServerpodClientException -> sem conexão', () async {
      final e =
          await falha(const ServerpodClientException('boom', 503))
              as AdminAuthFailure;
      expect(e.message, 'Não foi possível conectar ao servidor.');
    });
  });

  group('MFA', () {
    test('beginMfaEnrollment mapeia os campos do servidor', () async {
      final caller = FakeEndpointCaller(
        result: TotpEnrollmentStart(
          secretBase32: 'SEG',
          otpauthUri: 'otpauth://x',
        ),
      );
      final r = await _backend(
        caller,
      ).beginMfaEnrollment(matricula: 'a', senha: 'b');
      expect(r.secret, 'SEG');
      expect(r.otpauthUri, 'otpauth://x');
    });

    test('confirmMfaEnrollment traduz recusa', () {
      final caller = FakeEndpointCaller(
        error: AuthenticationFailedException(message: 'Código inválido'),
      );
      expect(
        _backend(
          caller,
        ).confirmMfaEnrollment(matricula: 'a', senha: 'b', code: '1'),
        throwsA(isA<AdminAuthFailure>()),
      );
    });
  });

  group('host', () {
    test('http:// é recusado', () {
      expect(
        () => AdminBackendConfig.requireSecureHost('http://10.0.2.2:8080/'),
        throwsFormatException,
      );
    });
    test('https:// passa', () {
      expect(AdminBackendConfig.requireSecureHost('https://x/'), 'https://x/');
    });
    test('forHost usa a fábrica injetada', () {
      var chamado = false;
      expect(
        () => BackendAdminAuth.forHost(
          host: 'https://x/',
          clientFactory: (h) {
            chamado = true;
            return Client(h);
          },
        ),
        returnsNormally,
      );
      expect(chamado, isTrue);
    });
  });
}
