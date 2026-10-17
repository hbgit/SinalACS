import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Lado do aparelho da limpeza remota (#81) pelos endpoints, contra Postgres
/// real: renovação, login e envio diferido recusam o aparelho marcado, e
/// `devices.pendingWipe`/`confirmWipe` fecham o ciclo auditado. Dados
/// sintéticos; ids próprios (`...e0xx`).
const _ubsId = '00000000-0000-4000-8000-00000000e001';
const _microAreaId = '00000000-0000-4000-8000-00000000e002';
const _acsId = '00000000-0000-4000-8000-00000000e003';
const _adminId = '00000000-0000-4000-8000-00000000e004';

const _matricula = 'ACS-WIPE-EP-001';
const _senha = 'senha-sintetica-de-teste';
const _aparelhoD = 'aparelho-wipe-d';
const _aparelhoNovo = 'aparelho-wipe-novo';

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Wipe',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea Wipe',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  Future<void> user(String id, UserRole role, String cpf) => User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(id),
      cpfHash: cpf,
      name: 'Usuário sintético',
      birthDate: DateTime.utc(1980),
      role: role,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  );
  await user(_acsId, UserRole.acs, 'development-acs-wipe-ep');
  await user(_adminId, UserRole.admin, 'development-admin-wipe-ep');
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: _matricula,
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
}

String _tokenAdmin() => AlertRuntime.instance.auth.issueToken(
  AuthenticatedUser(
    id: _adminId,
    role: UserRole.admin,
    microAreaId: null,
    deviceId: 'sem-aparelho',
  ),
);

void main() {
  withServerpod('Dado o aparelho do ACS com pedido de limpeza remota (#81)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late String refreshToken;
    late String uploadToken;

    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      await AlertRuntimeHarness.store(session).saveCredential(
        _acsId,
        await AlertRuntimeHarness.hasher.derive(_senha),
        DateTime.now().toUtc(),
      );
      final login = await endpoints.auth.loginInstitutional(
        sessionBuilder,
        matricula: _matricula,
        password: _senha,
        deviceId: _aparelhoD,
      );
      refreshToken = login.refreshToken!;
      uploadToken = login.uploadToken!;
    });

    Future<String> pedir() async {
      final r = await endpoints.admin.orderDeviceWipe(
        sessionBuilder,
        accessToken: _tokenAdmin(),
        acsId: _acsId,
        deviceId: _aparelhoD,
        reason: DeviceWipeReason.lost,
      );
      return r.orderId;
    }

    test(
      'a renovação recebe DeviceWipeRequiredException, não SessionExpiredException',
      () async {
        final orderId = await pedir();
        await expectLater(
          endpoints.auth.refreshSession(
            sessionBuilder,
            refreshToken: refreshToken,
            deviceId: _aparelhoD,
          ),
          throwsA(
            isA<DeviceWipeRequiredException>().having(
              (e) => e.orderId,
              'orderId',
              orderId,
            ),
          ),
        );
      },
    );

    test(
      'o login recusa o aparelho marcado, mesmo com a senha certa',
      () async {
        final orderId = await pedir();
        await expectLater(
          endpoints.auth.loginInstitutional(
            sessionBuilder,
            matricula: _matricula,
            password: _senha,
            deviceId: _aparelhoD,
          ),
          throwsA(
            isA<DeviceWipeRequiredException>().having(
              (e) => e.orderId,
              'orderId',
              orderId,
            ),
          ),
        );
        final novo = await endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: _senha,
          deviceId: _aparelhoNovo,
        );
        expect(novo.accessToken, isNotEmpty);
      },
    );

    test('o envio diferido do aparelho marcado é recusado', () async {
      await pedir();
      await expectLater(
        endpoints.visits.syncDeferred(
          sessionBuilder,
          uploadToken: uploadToken,
          deviceId: _aparelhoD,
          visits: [],
        ),
        throwsA(isA<DeviceWipeRequiredException>()),
      );
    });

    test('entrega, confirmação e auditoria do ciclo inteiro', () async {
      expect(
        await endpoints.devices.pendingWipe(sessionBuilder, _aparelhoD),
        isNull,
      );
      final orderId = await pedir();

      expect(
        await endpoints.devices.pendingWipe(sessionBuilder, _aparelhoD),
        orderId,
      );
      expect(
        await endpoints.devices.pendingWipe(sessionBuilder, _aparelhoD),
        orderId,
      );

      // Par errado: no-op silencioso, o pedido segue pendente.
      await endpoints.devices.confirmWipe(
        sessionBuilder,
        _aparelhoD,
        '00000000-0000-4000-8000-00000000e0ff',
      );
      expect(
        await endpoints.devices.pendingWipe(sessionBuilder, _aparelhoD),
        orderId,
      );

      await endpoints.devices.confirmWipe(sessionBuilder, _aparelhoD, orderId);
      await endpoints.devices.confirmWipe(sessionBuilder, _aparelhoD, orderId);
      expect(
        await endpoints.devices.pendingWipe(sessionBuilder, _aparelhoD),
        isNull,
      );

      // O id antigo fica marcado para sempre (D1).
      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: _senha,
          deviceId: _aparelhoD,
        ),
        throwsA(isA<DeviceWipeRequiredException>()),
      );

      final linhas = await AuditLog.db.find(
        session,
        where: (t) => t.resourceId.equals(UuidValue.fromString(orderId)),
      );
      final resultados = linhas.map((l) => l.result).toList()..sort();
      expect(resultados, ['wipe_confirmed', 'wipe_delivered', 'wipe_ordered']);
      final doAparelho = linhas.where((l) => l.resourceType == 'acs_device');
      expect(doAparelho.map((l) => l.userId.toString()), everyElement(_acsId));
      expect(doAparelho.map((l) => l.actionType), everyElement('write'));
    });
  });
}
