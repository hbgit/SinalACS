import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_scheduled_notice_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// `admin.scheduleNotice` / `cancelScheduledNotice` / `noticeHistory` (#46)
/// pelo endpoint, com tokens reais e Postgres real. Dados sintéticos.
const _ubsA = '00000000-0000-4000-8000-0000000046a1';
const _ubsB = '00000000-0000-4000-8000-0000000046b1';
const _maA = '00000000-0000-4000-8000-0000000046a2';
const _maB = '00000000-0000-4000-8000-0000000046b2';
const _admin = '00000000-0000-4000-8000-0000000046c1';
const _coordA = '00000000-0000-4000-8000-0000000046c2';
const _acs = '00000000-0000-4000-8000-0000000046c3';
const _paciente = '00000000-0000-4000-8000-0000000046c4';
final _t = DateTime.utc(2026, 1, 1);

AppConfig _config() => AppConfig(
  mqttBroker: 'localhost:1883',
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

String _token(String id, UserRole role) => AlertRuntime.instance.auth.issueToken(
  AuthenticatedUser(id: id, role: role, microAreaId: null, deviceId: 'dev'),
);

Future<void> _seed(Session s) async {
  for (final (ubs, ma, nome) in [
    (_ubsA, _maA, 'Microárea A'),
    (_ubsB, _maB, 'Microárea B'),
  ]) {
    await Ubs.db.insertRow(
      s,
      Ubs(
        id: UuidValue.fromString(ubs),
        name: 'UBS $nome',
        address: 'Endereço sintético',
        city: 'Cidade',
        state: 'SP',
      ),
    );
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(ma),
        name: nome,
        ubsId: UuidValue.fromString(ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }
  await User.db.insert(s, [
    for (final (id, role) in [
      (_admin, UserRole.admin),
      (_coordA, UserRole.coordinator),
      (_acs, UserRole.acs),
      (_paciente, UserRole.patient),
    ])
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'sintetico-$id',
        name: 'Sintético $id',
        birthDate: DateTime.utc(1980),
        role: role,
        createdAt: _t,
        updatedAt: _t,
      ),
  ]);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_admin),
      enrollmentId: 'ADM-AVISO-1',
      active: true,
    ),
  );
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coordA),
      enrollmentId: 'COO-AVISO-1',
      active: true,
      ubsId: UuidValue.fromString(_ubsA),
    ),
  );
}

void main() {
  withServerpod('Dado os endpoints de avisos do admin (#46)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmScheduledNoticeStore store;

    setUp(() async {
      session = sessionBuilder.build();
      AlertRuntime.instance.overrideConfig(_config());
      await _seed(session);
      store = OrmScheduledNoticeStore(session: () => session);
    });
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    DateTime future() => DateTime.now().toUtc().add(const Duration(hours: 2));

    Future<String> agenda(String token, String ma) =>
        endpoints.admin.scheduleNotice(
          sessionBuilder,
          accessToken: token,
          microAreaId: ma,
          audience: 'everyone',
          title: 'Vacinação',
          message: 'TEXTO-SECRETO-DO-AVISO',
          scheduledFor: future(),
        );

    Future<List<AuditLog>> audit(String result) => AuditLog.db.find(
      session,
      where: (t) =>
          t.resourceType.equals('community_notice') & t.result.equals(result),
    );

    test('token inválido: falha de autenticação nos três métodos', () async {
      await expectLater(
        agenda('lixo', _maA),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.admin.cancelScheduledNotice(
          sessionBuilder,
          accessToken: 'lixo',
          id: _maA,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.admin.noticeHistory(
          sessionBuilder,
          accessToken: 'lixo',
          limit: 50,
          offset: 0,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('paciente e ACS: AlertPermissionException e denied_role auditado', () async {
      for (final (id, role) in [(_paciente, UserRole.patient), (_acs, UserRole.acs)]) {
        await expectLater(
          agenda(_token(id, role), _maA),
          throwsA(isA<AlertPermissionException>()),
        );
        await expectLater(
          endpoints.admin.noticeHistory(
            sessionBuilder,
            accessToken: _token(id, role),
            limit: 50,
            offset: 0,
          ),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      final negadas = await audit('denied_role');
      expect(negadas, hasLength(4));
      expect(
        negadas.map((l) => l.userId).toSet(),
        {UuidValue.fromString(_paciente), UuidValue.fromString(_acs)},
      );
    });

    test('admin agenda: devolve o id e grava a linha pending', () async {
      final id = await agenda(_token(_admin, UserRole.admin), _maB);
      final r = await session.db.unsafeQuery(
        'SELECT "status" FROM scheduled_notices WHERE "id" = @id::uuid',
        parameters: QueryParameters.named({'id': id}),
      );
      expect(r.single.toColumnMap()['status'], 'pending');
      expect(await audit('scheduled'), hasLength(1));
    });

    test('coordenador em microárea de outra UBS: negado e denied_territory', () async {
      await expectLater(
        agenda(_token(_coordA, UserRole.coordinator), _maB),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(await audit('denied_territory'), hasLength(1));
      expect(
        await session.db.unsafeQuery('SELECT 1 FROM scheduled_notices'),
        isEmpty,
      );
    });

    test('cancelar pending funciona; cancelar enviado é AdminInvalidRequestException', () async {
      final token = _token(_admin, UserRole.admin);
      final pendente = await agenda(token, _maA);
      await endpoints.admin.cancelScheduledNotice(
        sessionBuilder,
        accessToken: token,
        id: pendente,
      );
      final r = await session.db.unsafeQuery(
        'SELECT "status" FROM scheduled_notices WHERE "id" = @id::uuid',
        parameters: QueryParameters.named({'id': pendente}),
      );
      expect(r.single.toColumnMap()['status'], 'cancelled');

      final enviado = await agenda(token, _maA);
      await store.claimDue(DateTime.now().toUtc().add(const Duration(days: 1)));
      await store.finish(
        enviado,
        status: ScheduledNoticeStatus.sent,
        recipients: 3,
        accepted: 2,
        at: DateTime.now().toUtc(),
      );
      await expectLater(
        endpoints.admin.cancelScheduledNotice(
          sessionBuilder,
          accessToken: token,
          id: enviado,
        ),
        throwsA(isA<AdminInvalidRequestException>()),
      );
    });

    test('histórico traz nome da microárea e matrícula, nunca a mensagem; coordenador só vê a UBS', () async {
      final admin = _token(_admin, UserRole.admin);
      final a = await agenda(admin, _maA);
      final b = await agenda(admin, _maB);
      await agenda(_token(_coordA, UserRole.coordinator), _maA);

      final page = await endpoints.admin.noticeHistory(
        sessionBuilder,
        accessToken: admin,
        limit: 50,
        offset: 0,
      );
      expect(page.entries.map((e) => e.id), containsAll([a, b]));
      final ea = page.entries.firstWhere((e) => e.id == a);
      expect(ea.microAreaName, 'Microárea A');
      expect(ea.createdByLabel, 'ADM-AVISO-1');
      expect(ea.title, 'Vacinação');
      expect(ea.status, ScheduledNoticeStatus.pending);
      expect(
        page.entries.any((e) => e.createdByLabel == 'COO-AVISO-1'),
        isTrue,
      );
      final json = page.toJson().toString();
      expect(json, isNot(contains('TEXTO-SECRETO-DO-AVISO')));
      for (final e in page.entries) {
        expect(e.toJson().keys, isNot(contains('message')));
      }

      final coord = await endpoints.admin.noticeHistory(
        sessionBuilder,
        accessToken: _token(_coordA, UserRole.coordinator),
        limit: 50,
        offset: 0,
      );
      expect(coord.entries, hasLength(2));
      expect(coord.entries.map((e) => e.microAreaId).toSet(), {_maA});
      expect(coord.entries.map((e) => e.id), isNot(contains(b)));
    });
  });
}
