import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/backend_admin_data_source.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/fake_admin_auth.dart';

/// `BackendAdminDataSource` (#43) sobre o `EndpointAdmin` de gestão de contas,
/// com um chamador falso: o mapa token + payload por método, a tradução dos
/// enums por **nome** e a separação entre falha de validação (texto do
/// servidor, que fala da entrada do próprio operador) e recusa de acesso
/// (texto fixo). Dados sintéticos.
BackendAdminDataSource _fonte(
  FakeEndpointCaller caller, {
  String token = 'token-de-teste',
  DateTime? expiresAt,
  DateTime Function()? now,
}) => BackendAdminDataSource(
  api.EndpointAdmin(caller),
  accessToken: token,
  expiresAt: expiresAt,
  now: now,
);

api.AdminAcs _acs({
  String id = 'acs-1',
  String name = 'Carla Nogueira',
  String enrollmentId = 'ACS-001',
  String? microAreaId = 'ma-12',
  String? microAreaName = 'Microárea 12 — Zona Rural',
  bool active = true,
  bool mfaActive = false,
}) => api.AdminAcs(
  id: id,
  name: name,
  enrollmentId: enrollmentId,
  ubsId: 'ubs-1',
  ubsName: 'UBS Vila Nova',
  microAreaId: microAreaId,
  microAreaName: microAreaName,
  active: active,
  mfaActive: mfaActive,
);

void main() {
  group('leituras', () {
    test('acs: manda só o token e mapeia território, estado e MFA', () async {
      final caller = FakeEndpointCaller(
        result: [
          _acs(),
          _acs(
            id: 'acs-2',
            name: 'Sem Território',
            enrollmentId: 'ACS-002',
            microAreaId: null,
            microAreaName: null,
            active: false,
            mfaActive: true,
          ),
        ],
      );

      final r = await _fonte(caller).fetchAcs();

      expect(caller.lastArgs, {'accessToken': 'token-de-teste'});
      expect(r, hasLength(2));
      expect(r.first.id, 'acs-1');
      expect(r.first.name, 'Carla Nogueira');
      expect(r.first.enrollmentId, 'ACS-001');
      expect(r.first.ubsName, 'UBS Vila Nova');
      expect(r.first.microAreaId, 'ma-12');
      expect(r.first.microAreaName, 'Microárea 12 — Zona Rural');
      expect(r.first.active, isTrue);
      expect(r.first.mfaActive, isFalse);
      expect(r.last.microAreaId, isNull, reason: 'quem não tem território aparece na lista para poder ser vinculado');
      expect(r.last.mfaActive, isTrue);
    });

    test('staff: manda só o token e traduz o papel por nome, nunca por índice', () async {
      final caller = FakeEndpointCaller(
        result: [
          api.AdminStaff(
            id: 'staff-1',
            name: 'Coordenadora',
            enrollmentId: 'COO-001',
            role: api.UserRole.coordinator,
            ubsName: 'UBS Vila Nova',
            active: true,
            mfaActive: true,
          ),
          api.AdminStaff(
            id: 'staff-2',
            name: 'Administrador',
            enrollmentId: 'ADM-002',
            role: api.UserRole.admin,
            ubsName: null,
            active: true,
            mfaActive: false,
          ),
        ],
      );

      final r = await _fonte(caller).fetchStaff();

      expect(caller.lastArgs, {'accessToken': 'token-de-teste'});
      // `UserRole` do cliente tem os mesmos nomes do servidor; a tradução é por
      // nome. O índice de `coordinator` é 2 e o de `admin` é 3 — se alguém
      // traduzisse por índice, '2'/'3' apareceriam aqui.
      expect(r.first.role, 'coordinator');
      expect(r.last.role, 'admin');
      expect(r.first.ubsName, 'UBS Vila Nova');
      expect(r.last.ubsName, isNull, reason: 'o administrador vê o sistema inteiro e não tem UBS');
      expect(r.last.mfaActive, isFalse);
    });

    test('a leitura segue com o texto de paginação: o _guard de leitura não mudou', () async {
      await expectLater(
        _fonte(FakeEndpointCaller(error: api.AdminInvalidRequestException(message: 'limit fora do intervalo'))).fetchAcs(),
        throwsA(
          isA<AdminDataFailure>().having((e) => e.message, 'message', 'Parâmetro de paginação inválido.'),
        ),
        reason: 'mensagem do servidor sobre outro assunto continua sem ir à tela nas leituras',
      );
    });
  });

  group('escritas', () {
    test('createAcs manda token e payload, e devolve a senha inicial uma vez', () async {
      final caller = FakeEndpointCaller(
        result: api.AdminAcsCreationResult(
          acs: _acs(id: 'acs-9', name: 'Nova', enrollmentId: 'ACS-9'),
          initialPassword: 'SENHA-INICIAL-DE-TESTE',
        ),
      );

      final r = await _fonte(caller).createAcs(name: 'Nova', enrollmentId: 'ACS-9', microAreaId: 'ma-1');

      expect(caller.lastArgs, {
        'accessToken': 'token-de-teste',
        'name': 'Nova',
        'enrollmentId': 'ACS-9',
        'microAreaId': 'ma-1',
      });
      expect(r.initialPassword, 'SENHA-INICIAL-DE-TESTE');
      expect(r.acs.id, 'acs-9');
      expect(r.acs.enrollmentId, 'ACS-9');
    });

    test('setAcsMicroArea manda o alvo e devolve a linha já no território novo', () async {
      final caller = FakeEndpointCaller(
        result: _acs(microAreaId: 'ma-07', microAreaName: 'Microárea 07 — Centro'),
      );

      final r = await _fonte(caller).setAcsMicroArea(acsId: 'acs-1', microAreaId: 'ma-07');

      expect(caller.lastArgs, {
        'accessToken': 'token-de-teste',
        'acsId': 'acs-1',
        'microAreaId': 'ma-07',
      });
      expect(r.microAreaId, 'ma-07');
      expect(r.microAreaName, 'Microárea 07 — Centro');
    });

    test('setAcsActive manda a flag e devolve a linha como o servidor a deixou', () async {
      final caller = FakeEndpointCaller(result: _acs(active: false));

      final r = await _fonte(caller).setAcsActive(acsId: 'acs-1', active: false);

      expect(caller.lastArgs, {
        'accessToken': 'token-de-teste',
        'acsId': 'acs-1',
        'active': false,
      });
      expect(r.active, isFalse);
    });

    test('resetAcsPassword devolve a senha nova do servidor', () async {
      final caller = FakeEndpointCaller(result: api.AdminPasswordResetResult(newPassword: 'SENHA-SORTEADA'));

      final senha = await _fonte(caller).resetAcsPassword(acsId: 'acs-1');

      expect(caller.lastArgs, {'accessToken': 'token-de-teste', 'acsId': 'acs-1'});
      expect(senha, 'SENHA-SORTEADA');
    });

    test('resetAcsMfa manda o alvo e não devolve credencial nenhuma', () async {
      final caller = FakeEndpointCaller();

      await _fonte(caller).resetAcsMfa(acsId: 'acs-1');

      expect(caller.lastArgs, {'accessToken': 'token-de-teste', 'acsId': 'acs-1'});
    });

    test('resetStaffMfa devolve o código de ativação e a validade, uma única vez', () async {
      final expira = DateTime.utc(2026, 10, 9, 12);
      final caller = FakeEndpointCaller(
        result: api.AdminStaffMfaResetResult(
          activationCode: 'ABCD-EFGH-JKLM-NPQR-STUV',
          activationCodeExpiresAt: expira,
        ),
      );

      final r = await _fonte(caller).resetStaffMfa(staffId: 'staff-1');

      expect(caller.lastArgs, {'accessToken': 'token-de-teste', 'staffId': 'staff-1'});
      expect(r.code, 'ABCD-EFGH-JKLM-NPQR-STUV');
      expect(r.expiresAt, expira);
    });
  });

  group('falhas das escritas', () {
    test('AdminInvalidRequestException vira AdminValidationFailure com a mensagem do servidor', () async {
      final caller = FakeEndpointCaller(
        error: api.AdminInvalidRequestException(message: 'Já existe um ACS com esta matrícula.'),
      );

      await expectLater(
        _fonte(caller).createAcs(name: 'Nova', enrollmentId: 'ACS-9', microAreaId: 'ma-1'),
        throwsA(
          isA<AdminValidationFailure>().having(
            (e) => e.message,
            'message',
            'Já existe um ACS com esta matrícula.',
          ),
        ),
        reason: 'a mensagem fala da entrada do próprio operador e pode ir à tela',
      );
    });

    test('a validação vale para toda escrita, não só para o cadastro', () async {
      for (final chamada in <Future<void> Function(BackendAdminDataSource)>[
        (f) => f.setAcsActive(acsId: 'acs-1', active: false),
        (f) => f.setAcsMicroArea(acsId: 'acs-1', microAreaId: 'ma-07'),
        (f) => f.resetAcsPassword(acsId: 'acs-1'),
        (f) => f.resetAcsMfa(acsId: 'acs-1'),
        (f) => f.resetStaffMfa(staffId: 'staff-1'),
      ]) {
        await expectLater(
          chamada(
            _fonte(FakeEndpointCaller(error: api.AdminInvalidRequestException(message: 'ACS inexistente.'))),
          ),
          throwsA(isA<AdminValidationFailure>().having((e) => e.message, 'message', 'ACS inexistente.')),
        );
      }
    });

    test('AlertPermissionException continua AdminDataFailure (texto fixo) nas escritas', () async {
      await expectLater(
        _fonte(
          FakeEndpointCaller(error: api.AlertPermissionException(message: 'detalhe interno do servidor')),
        ).setAcsActive(acsId: 'acs-1', active: false),
        throwsA(
          isA<AdminDataFailure>().having((e) => e.message, 'message', 'Acesso restrito ao backoffice.'),
        ),
        reason: 'o motivo da recusa de permissão nunca vai à tela',
      );
    });

    test('recusa depois do vencimento da sessão vira AdminSessionExpired, também nas escritas', () async {
      final fonte = _fonte(
        FakeEndpointCaller(error: api.AlertPermissionException(message: 'token inválido ou expirado')),
        expiresAt: DateTime.utc(2026, 1, 1, 12),
        now: () => DateTime.utc(2026, 1, 1, 12, 0, 1),
      );

      await expectLater(fonte.resetAcsMfa(acsId: 'acs-1'), throwsA(isA<AdminSessionExpired>()));
    });

    test('401 do servidor vira AdminSessionExpired', () async {
      await expectLater(
        _fonte(FakeEndpointCaller(error: api.ServerpodClientUnauthorized())).resetAcsPassword(acsId: 'acs-1'),
        throwsA(isA<AdminSessionExpired>()),
      );
    });

    test('falha de rede vira o texto de conexão, nunca uma falha de validação', () async {
      for (final erro in <Object>[
        const SocketException('sem rede'),
        TimeoutException('x'),
        const HandshakeException('x'),
        const api.ServerpodClientException('Connection refused', -1),
      ]) {
        await expectLater(
          _fonte(FakeEndpointCaller(error: erro)).setAcsActive(acsId: 'acs-1', active: true),
          throwsA(
            isA<AdminDataFailure>().having((e) => e.message, 'message', 'Não foi possível conectar ao servidor.'),
          ),
        );
      }
    });
  });
}
