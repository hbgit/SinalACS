import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/opaque_token.dart';
import 'package:sinalacs_server/src/application/auth/upload_token_service.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_upload_token_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Token de envio diferido do ACS (D7 do plano 2026-10-03) contra Postgres
/// real: emissão no `auth.loginInstitutional`, `visits.syncDeferred` com a
/// autoria do DONO do token e `visits.revokeUploadToken`.
///
/// O que se prova aqui, adversarialmente: o token de A nunca grava com a
/// autoria de B, nunca fora da microárea ATUAL de A, nunca toma um `localId`
/// de B, e sobrevive ao fim da sessão de A (logout/refresh revogado) — mas não
/// a revogação, vencimento, outro aparelho, conta inativa ou sem microárea.
///
/// Dados sintéticos; ids próprios (`...0d?`).
const _ubsId = '00000000-0000-4000-8000-0000000000d1';
const _areaId = '00000000-0000-4000-8000-0000000000d2';
const _outraAreaId = '00000000-0000-4000-8000-0000000000d3';
const _acsA = '00000000-0000-4000-8000-0000000000d4';
const _acsB = '00000000-0000-4000-8000-0000000000d5';
const _pacienteNaArea = '00000000-0000-4000-8000-0000000000d6';
const _pacienteFora = '00000000-0000-4000-8000-0000000000d7';

const _matriculaA = 'ACS-UPLOAD-A';
const _matriculaB = 'ACS-UPLOAD-B';
const _senha = 'senha-sintetica-de-teste';
const _aparelhoA = 'aparelho-upload-A';
const _aparelhoB = 'aparelho-upload-B';

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

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Envio Diferido',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insert(session, [
    MicroArea(
      id: UuidValue.fromString(_areaId),
      name: 'Microárea do envio',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
    MicroArea(
      id: UuidValue.fromString(_outraAreaId),
      name: 'Microárea vizinha',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  ]);
  final now = DateTime.now().toUtc();
  User user(String id, UserRole role, String cpf, String area) => User(
        id: UuidValue.fromString(id),
        cpfHash: cpf,
        name: 'Usuário sintético',
        birthDate: DateTime.utc(1980),
        role: role,
        microAreaId: UuidValue.fromString(area),
        createdAt: now,
        updatedAt: now,
      );
  await User.db.insert(session, [
    user(_acsA, UserRole.acs, 'development-acs-upload-a', _areaId),
    user(_acsB, UserRole.acs, 'development-acs-upload-b', _areaId),
    user(_pacienteNaArea, UserRole.patient, 'development-patient-upload-6', _areaId),
    user(_pacienteFora, UserRole.patient, 'development-patient-upload-7', _outraAreaId),
  ]);
  await Acs.db.insert(session, [
    Acs(
      id: UuidValue.fromString(_acsA),
      enrollmentId: _matriculaA,
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
    Acs(
      id: UuidValue.fromString(_acsB),
      enrollmentId: _matriculaB,
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  ]);
  await Patient.db.insert(session, [
    await encryptedPatient(
        id: _pacienteNaArea, emergencyContact: 'Contato sintético', isChronic: false),
    await encryptedPatient(
        id: _pacienteFora, emergencyContact: 'Contato sintético', isChronic: false),
  ]);
  final digest = await AlertRuntimeHarness.hasher.derive(_senha);
  for (final id in [_acsA, _acsB]) {
    await AlertRuntimeHarness.store(session).saveCredential(id, digest, now);
  }
}

VisitSyncEntry _entry(String localId,
        {String patientId = _pacienteNaArea, int version = 0, String status = 'realizada'}) =>
    VisitSyncEntry(
      localId: localId,
      patientId: patientId,
      scheduledAt: DateTime.utc(2026, 10, 2, 9),
      completedAt: DateTime.utc(2026, 10, 2, 10),
      status: status,
      riskLevelBefore: RiskLevel.green,
      notes: const {'campo': 'sem intercorrências'},
      version: version,
      arrivalMethod: ArrivalMethod.manual,
    );

Future<Visit?> _row(Session session, String localId) => Visit.db.findFirstRow(
      session,
      where: (t) => t.localId.equals(UuidValue.fromString(localId)),
    );

String _local(int n) => '00000000-0000-4000-8000-${(0xe00 + n).toRadixString(16).padLeft(12, '0')}';

void main() {
  withServerpod('Dado o token de envio diferido do ACS', (sessionBuilder, endpoints) {
    late Session session;

    setUp(() async {
      AlertRuntime.instance.overrideConfig(_config());
      session = sessionBuilder.build();
      await _seed(session);
    });
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    Future<DevelopmentLoginResult> entrar(
            {String matricula = _matriculaA, String? deviceId = _aparelhoA}) =>
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: matricula,
          password: _senha,
          deviceId: deviceId,
        );

    Future<List<VisitSyncResult>> enviar(String token, List<VisitSyncEntry> visits,
            {String deviceId = _aparelhoA}) =>
        endpoints.visits.syncDeferred(
          sessionBuilder,
          uploadToken: token,
          deviceId: deviceId,
          visits: visits,
        );

    Future<void> recusado(Future<Object?> call) => expectLater(
          call,
          throwsA(isA<SessionExpiredException>().having(
              (e) => e.message, 'message', UploadTokenService.deniedMessage)),
        );

    Future<List<AuditLog>> trilha(String result) => AuditLog.db.find(
          session,
          where: (t) => t.result.equals(result),
        );

    test('o login com deviceId devolve uploadToken; a tabela guarda só o hash',
        () async {
      final login = await entrar();
      final token = login.uploadToken;
      expect(token, isNotNull);
      expect(token!.length, greaterThanOrEqualTo(43));
      expect(token, isNot(login.refreshToken));

      final linhas = await AcsUploadToken.db.find(session);
      expect(linhas, hasLength(1));
      expect(linhas.single.tokenHash, OpaqueToken.hash(token));
      expect(linhas.single.userId.uuid, _acsA);
      expect(linhas.single.deviceId, _aparelhoA);
      expect(linhas.single.revokedAt, isNull);
      expect(
        linhas.single.expiresAt.difference(linhas.single.issuedAt),
        UploadTokenService.lifetime,
      );
      final emitidos = await trilha('upload_token_issued');
      expect(emitidos.single.userId.uuid, _acsA);
    });

    test('login sem deviceId (ausente ou em branco) devolve uploadToken nulo',
        () async {
      for (final id in <String?>[null, '', '   ']) {
        final login = await entrar(deviceId: id);
        expect(login.accessToken, isNotEmpty, reason: 'deviceId=$id');
        expect(login.uploadToken, isNull, reason: 'deviceId=$id');
      }
      expect(await AcsUploadToken.db.find(session), isEmpty);
    });

    test('developmentLogin (paciente e ACS) nunca devolve uploadToken', () async {
      for (final role in ['patient', 'acs']) {
        final login = await endpoints.auth.developmentLogin(sessionBuilder, role: role);
        expect(login.uploadToken, isNull, reason: role);
      }
    });

    test('syncDeferred grava a visita com a autoria do DONO do token', () async {
      final login = await entrar();
      final resultados = await enviar(login.uploadToken!, [_entry(_local(1))]);
      expect(resultados.single.syncStatus, SyncStatus.synced);
      final row = (await _row(session, _local(1)))!;
      expect(row.acsId?.uuid, _acsA);
      expect(row.authorship, VisitAuthorship.acs);
      expect(row.originDeviceId, isNull);

      final lote = await trilha('visit_deferred_sync');
      expect(lote, hasLength(1));
      expect(lote.single.userId.uuid, _acsA);
      expect(lote.single.resourceId, isNull);
    });

    test('token de A com paciente de outra microárea → rejected, nada gravado',
        () async {
      final login = await entrar();
      final r = await enviar(
          login.uploadToken!, [_entry(_local(2), patientId: _pacienteFora)]);
      expect(r.single.syncStatus, SyncStatus.rejected);
      expect(await _row(session, _local(2)), isNull);
    });

    test('token de A não toma um localId que já pertence a B', () async {
      final tokenB = AlertRuntime.instance.auth.issueToken(const AuthenticatedUser(
          id: _acsB, role: UserRole.acs, microAreaId: _areaId, deviceId: _aparelhoB));
      await endpoints.visits.sync(sessionBuilder,
          accessToken: tokenB, visits: [_entry(_local(3))]);

      final login = await entrar();
      final r = await enviar(login.uploadToken!,
          [_entry(_local(3), version: 1, status: 'sobrescrita por A')]);
      expect(r.single.syncStatus, SyncStatus.rejected);
      final row = (await _row(session, _local(3)))!;
      expect(row.acsId?.uuid, _acsB);
      expect(row.status, 'realizada');
      expect(row.version, 1);
    });

    test('token de B apresentado do aparelho de A é recusado; nunca há autoria de B',
        () async {
      final loginB = await entrar(matricula: _matriculaB, deviceId: _aparelhoB);
      await recusado(enviar(loginB.uploadToken!, [_entry(_local(4))]));
      expect(await _row(session, _local(4)), isNull);
      // E o token de A, mesmo no envio da visita "de B", grava como A.
      final loginA = await entrar();
      await enviar(loginA.uploadToken!, [_entry(_local(5))]);
      expect((await _row(session, _local(5)))!.acsId?.uuid, _acsA);
    });

    test('a microárea é RELIDA: depois da troca, o território é o atual', () async {
      final login = await entrar();
      final a = (await User.db.findById(session, UuidValue.fromString(_acsA)))!;
      a.microAreaId = UuidValue.fromString(_outraAreaId);
      await User.db.updateRow(session, a);

      final r = await enviar(login.uploadToken!, [
        _entry(_local(6)), // área antiga
        _entry(_local(7), patientId: _pacienteFora), // área atual
      ]);
      expect(r[0].syncStatus, SyncStatus.rejected);
      expect(r[1].syncStatus, SyncStatus.synced);
      expect((await _row(session, _local(7)))!.acsId?.uuid, _acsA);
    });

    test('D7: syncDeferred continua valendo depois do logout (refresh revogado)',
        () async {
      final login = await entrar();
      await endpoints.auth.logout(sessionBuilder, refreshToken: login.refreshToken!);
      await expectLater(
        endpoints.auth.refreshSession(sessionBuilder,
            refreshToken: login.refreshToken!, deviceId: _aparelhoA),
        throwsA(isA<SessionExpiredException>()),
      );
      final r = await enviar(login.uploadToken!, [_entry(_local(8))]);
      expect(r.single.syncStatus, SyncStatus.synced);
      expect((await _row(session, _local(8)))!.acsId?.uuid, _acsA);
    });

    test('revokeUploadToken: recusa depois, idempotente, ignora desconhecido',
        () async {
      final login = await entrar();
      await endpoints.visits.revokeUploadToken(sessionBuilder,
          uploadToken: login.uploadToken!);
      await recusado(enviar(login.uploadToken!, [_entry(_local(9))]));
      await endpoints.visits.revokeUploadToken(sessionBuilder,
          uploadToken: login.uploadToken!);
      await endpoints.visits.revokeUploadToken(sessionBuilder,
          uploadToken: 'token-que-nao-existe');
      expect(await _row(session, _local(9)), isNull);
    });

    test('segundo login do mesmo (usuário, aparelho) revoga o primeiro token',
        () async {
      final primeiro = await entrar();
      final segundo = await entrar();
      await recusado(enviar(primeiro.uploadToken!, [_entry(_local(10))]));
      final r = await enviar(segundo.uploadToken!, [_entry(_local(10))]);
      expect(r.single.syncStatus, SyncStatus.synced);
      // Outro aparelho do mesmo ACS não é afetado.
      final outro = await entrar(deviceId: 'aparelho-upload-A2');
      await entrar();
      final r2 = await enviar(outro.uploadToken!, [_entry(_local(11))],
          deviceId: 'aparelho-upload-A2');
      expect(r2.single.syncStatus, SyncStatus.synced);
    });

    test('vencido, outro aparelho, conta inativa e sem microárea → a MESMA recusa',
        () async {
      // Vencido: o relógio do endpoint não é injetável; envelhece a linha.
      final vencido = await entrar();
      final linha = (await AcsUploadToken.db.findFirstRow(session,
          where: (t) => t.tokenHash.equals(OpaqueToken.hash(vencido.uploadToken!))))!;
      linha.expiresAt = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      await AcsUploadToken.db.updateRow(session, linha);
      await recusado(enviar(vencido.uploadToken!, [_entry(_local(12))]));

      // Outro aparelho (e o token cai: nem o aparelho certo usa depois).
      final roubado = await entrar();
      await recusado(enviar(roubado.uploadToken!, [_entry(_local(12))],
          deviceId: 'aparelho-do-ladrao'));
      await recusado(enviar(roubado.uploadToken!, [_entry(_local(12))]));

      // Conta inativa.
      final inativo = await entrar();
      final acs = (await Acs.db.findById(session, UuidValue.fromString(_acsA)))!;
      acs.active = false;
      await Acs.db.updateRow(session, acs);
      await recusado(enviar(inativo.uploadToken!, [_entry(_local(12))]));
      acs.active = true;
      await Acs.db.updateRow(session, acs);

      // Microárea removida.
      final semArea = await entrar();
      final u = (await User.db.findById(session, UuidValue.fromString(_acsA)))!;
      u.microAreaId = null;
      await User.db.updateRow(session, u);
      await recusado(enviar(semArea.uploadToken!, [_entry(_local(12))]));

      // Desconhecido.
      await recusado(enviar('token-inventado', [_entry(_local(12))]));

      expect(await _row(session, _local(12)), isNull);
      for (final motivo in ['expired', 'device', 'inactive']) {
        expect(await trilha('upload_token_denied_$motivo'), isNotEmpty,
            reason: motivo);
      }
    });

    test('lote acima de maxLegacyBatch → AlertValidationException antes de tudo',
        () async {
      final login = await entrar();
      final antes = (await AuditLog.db.find(session)).length;
      await expectLater(
        enviar(login.uploadToken!, [
          for (var i = 0; i <= VisitSyncService.maxLegacyBatch; i++) _entry(_local(100 + i)),
        ]),
        throwsA(isA<AlertValidationException>()),
      );
      expect(await Visit.db.find(session), isEmpty);
      expect((await AuditLog.db.find(session)).length, antes);
    });

    test('o token nunca aparece na trilha de auditoria', () async {
      final login = await entrar();
      final token = login.uploadToken!;
      await enviar(token, [_entry(_local(13))]);
      await recusado(enviar(token, [_entry(_local(14))], deviceId: 'outro'));
      await endpoints.visits.revokeUploadToken(sessionBuilder, uploadToken: token);
      for (final row in await AuditLog.db.find(session)) {
        final texto = row.toJson().toString();
        expect(texto, isNot(contains(token)));
        expect(texto, isNot(contains(OpaqueToken.hash(token))));
      }
    });
    test('login com o sentinela público de deviceId: sem refresh nem upload, e não falha',
        () async {
      final login = await entrar(deviceId: InstitutionalAuthService.deviceIdAbsent);
      expect(login.accessToken, isNotEmpty);
      expect(login.refreshToken, isNull);
      expect(login.uploadToken, isNull);
      expect(await AcsUploadToken.db.find(session), isEmpty);
      expect(await AcsRefreshToken.db.find(session), isEmpty);
    });

    test('ordem: token inválido com 201 visitas → AlertValidationException (teto antes do token)',
        () async {
      await expectLater(
        enviar('token-inventado', [
          for (var i = 0; i <= VisitSyncService.maxLegacyBatch; i++) _entry(_local(400 + i)),
        ]),
        throwsA(isA<AlertValidationException>()),
      );
    });

    test('escopo: token de envio não serve como JWT nem como refresh; JWT não serve como token de envio',
        () async {
      final login = await entrar();
      final upload = login.uploadToken!;

      // Token de envio no lugar do JWT.
      await expectLater(
        endpoints.visits.sync(sessionBuilder, accessToken: upload, visits: [_entry(_local(20))]),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.visits.pull(sessionBuilder,
            accessToken: upload, since: DateTime.utc(2026)),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.patients.listMicroArea(sessionBuilder, accessToken: upload),
        throwsA(isA<AlertPermissionException>()),
      );
      // Token de envio no lugar do refresh token.
      await expectLater(
        endpoints.auth.refreshSession(sessionBuilder,
            refreshToken: upload, deviceId: _aparelhoA),
        throwsA(isA<SessionExpiredException>()),
      );

      // JWT no lugar do token de envio.
      await recusado(enviar(login.accessToken, [_entry(_local(21))]));
      await endpoints.visits.revokeUploadToken(sessionBuilder,
          uploadToken: login.accessToken); // sem efeito, sem lançar

      // Nada disso gravou visita nem derrubou o token de envio verdadeiro.
      expect(await _row(session, _local(20)), isNull);
      expect(await _row(session, _local(21)), isNull);
      final r = await enviar(upload, [_entry(_local(22))]);
      expect(r.single.syncStatus, SyncStatus.synced);
    });
  });

  // Corridas precisam de conexões independentes: sem rollback automático cada
  // `Session` usa a sua. Só o store (sem trilha de auditoria, que prenderia o
  // usuário por FK); a limpeza apaga só as linhas deste grupo.
  withServerpod(
    'Dado o token de envio diferido, sem rollback (corridas)',
    (sessionBuilder, endpoints) {
      const ubs = '00000000-0000-4000-8000-0000000000f1';
      const area = '00000000-0000-4000-8000-0000000000f2';
      const acs = '00000000-0000-4000-8000-0000000000f3';
      const aparelho = 'aparelho-corrida';

      Future<void> limpar() async {
        final s = sessionBuilder.build();
        await AcsUploadToken.db.deleteWhere(s,
            where: (t) => t.userId.equals(UuidValue.fromString(acs)));
        await User.db.deleteWhere(s, where: (t) => t.id.equals(UuidValue.fromString(acs)));
        await MicroArea.db
            .deleteWhere(s, where: (t) => t.id.equals(UuidValue.fromString(area)));
        await Ubs.db.deleteWhere(s, where: (t) => t.id.equals(UuidValue.fromString(ubs)));
      }

      Future<void> semear() async {
        final s = sessionBuilder.build();
        await Ubs.db.insertRow(
            s,
            Ubs(
                id: UuidValue.fromString(ubs),
                name: 'UBS Corrida',
                address: 'Endereço local',
                city: 'São Paulo',
                state: 'SP'));
        await MicroArea.db.insertRow(
            s,
            MicroArea(
                id: UuidValue.fromString(area),
                name: 'Microárea Corrida',
                ubsId: UuidValue.fromString(ubs),
                geoJsonBoundary: '{}'));
        final now = DateTime.now().toUtc();
        await User.db.insertRow(
            s,
            User(
                id: UuidValue.fromString(acs),
                cpfHash: 'development-acs-upload-corrida',
                name: 'Usuário sintético',
                birthDate: DateTime.utc(1980),
                role: UserRole.acs,
                microAreaId: UuidValue.fromString(area),
                createdAt: now,
                updatedAt: now));
      }

      test('emissões paralelas do mesmo (usuário, aparelho) deixam exatamente UM vigente',
          () async {
        await limpar();
        try {
          await semear();
          var n = 0;
          for (var rodada = 0; rodada < 8; rodada++) {
            final at = DateTime.utc(2026, 10, 3, 12, rodada);
            await Future.wait([
              for (var k = 0; k < 6; k++)
                OrmUploadTokenStore(session: sessionBuilder.build).replace(
                  UploadTokenRecord(
                    id: '00000000-0000-4000-8000-${(0xf00 + n++).toRadixString(16).padLeft(12, '0')}',
                    userId: acs,
                    deviceId: aparelho,
                    issuedAt: at,
                    expiresAt: at.add(UploadTokenService.lifetime),
                  ),
                  OpaqueToken.hash('corrida-$rodada-$k'),
                ),
            ]);
            final vigentes = await AcsUploadToken.db.find(
              sessionBuilder.build(),
              where: (t) =>
                  t.userId.equals(UuidValue.fromString(acs)) &
                  t.deviceId.equals(aparelho) &
                  t.revokedAt.equals(null),
            );
            expect(vigentes, hasLength(1), reason: 'rodada $rodada');
          }
        } finally {
          await limpar();
        }
      });
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}
