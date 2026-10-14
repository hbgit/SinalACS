import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// `admin.verifyAuditChain` (#45, Task 6) pelo endpoint, com tokens reais e
/// Postgres real. As adulterações (`UPDATE`/`DELETE` direto em `audit_logs`)
/// só existem no banco de teste do harness, desfeito a cada caso. Dados
/// sintéticos; ids próprios.
const _ubsA = '00000000-0000-4000-8000-0000000046c1';
const _ubsB = '00000000-0000-4000-8000-0000000046c2';
const _maA = '00000000-0000-4000-8000-0000000046c3';
const _maB = '00000000-0000-4000-8000-0000000046c4';
const _acsA = '00000000-0000-4000-8000-0000000046c5';
const _acsB = '00000000-0000-4000-8000-0000000046c6';
const _admin = '00000000-0000-4000-8000-0000000046c7';
const _coordA = '00000000-0000-4000-8000-0000000046c8';
const _paciente = '00000000-0000-4000-8000-0000000046c9';

/// O segredo cuja ausência na resposta o teste afirma.
const _segredo = AppConfig.developmentAuditChainSecret;

final _t = DateTime.utc(2026, 10, 13, 12);

AppConfig _config() => AppConfig(
  mqttBroker: 'localhost:1883',
  jwtSecret: 'test-secret',
  auditChainSecret: _segredo,
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

Future<void> _usuario(Session s, String id, UserRole role, {String? ma}) =>
    User.db
        .insertRow(
          s,
          User(
            id: UuidValue.fromString(id),
            cpfHash: 'audit-chain-ep-$id',
            name: 'Sintético $id',
            birthDate: DateTime.utc(1980),
            role: role,
            microAreaId: ma == null ? null : UuidValue.fromString(ma),
            createdAt: _t,
            updatedAt: _t,
          ),
        )
        .then((_) {});

Future<void> _seed(Session s) async {
  for (final (id, nome) in [(_ubsA, 'UBS A'), (_ubsB, 'UBS B')]) {
    await Ubs.db.insertRow(
      s,
      Ubs(
        id: UuidValue.fromString(id),
        name: nome,
        address: 'Endereço sintético',
        city: 'São Paulo',
        state: 'SP',
      ),
    );
  }
  for (final (id, ubs) in [(_maA, _ubsA), (_maB, _ubsB)]) {
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(id),
        name: 'Microárea $id',
        ubsId: UuidValue.fromString(ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }
  for (final (id, ma, ubs, mat) in [
    (_acsA, _maA, _ubsA, 'ACS-CADEIA-A'),
    (_acsB, _maB, _ubsB, 'ACS-CADEIA-B'),
  ]) {
    await _usuario(s, id, UserRole.acs, ma: ma);
    await Acs.db.insertRow(
      s,
      Acs(
        id: UuidValue.fromString(id),
        enrollmentId: mat,
        ubsId: UuidValue.fromString(ubs),
        active: true,
      ),
    );
  }
  await _usuario(s, _paciente, UserRole.patient, ma: _maA);
  await _usuario(s, _admin, UserRole.admin);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_admin),
      enrollmentId: 'ADM-CADEIA-1',
      active: true,
    ),
  );
  await _usuario(s, _coordA, UserRole.coordinator);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coordA),
      enrollmentId: 'COO-CADEIA-A',
      active: true,
      ubsId: UuidValue.fromString(_ubsA),
    ),
  );
}

String _token(String id, UserRole role, {String? ma}) =>
    AlertRuntime.instance.auth.issueToken(
      AuthenticatedUser(
        id: id,
        role: role,
        microAreaId: ma,
        deviceId: 'sem-aparelho',
      ),
    );

void main() {
  withServerpod('Dado admin.verifyAuditChain (#45, Task 6)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;

    setUp(() async {
      session = sessionBuilder.build();
      AlertRuntime.instance.overrideConfig(_config());
      AlertRuntime.instance.resetAuditChainStatusCache();
      await _seed(session);
    });
    tearDown(() {
      AlertRuntime.instance.overrideConfig(null);
      AlertRuntime.instance.resetAuditChainStatusCache();
    });

    /// Grava uma linha pela trilha de produção e devolve a `sequence` dela.
    Future<int> linha(String autor, String resourceType) async {
      await OrmAuditTrail(session: () => session, chainSecret: _segredo).record(
        AuditEvent(
          userId: autor,
          actionType: 'read',
          resourceType: resourceType,
          result: 'success',
        ),
      );
      final l = await AuditLog.db.findFirstRow(
        session,
        where: (t) => t.resourceType.equals(resourceType),
        orderBy: (t) => t.sequence,
        orderDescending: true,
      );
      return l!.sequence;
    }

    Future<AdminAuditChainStatus> verificar(String id, UserRole role) {
      // Cada chamada é uma verificação nova: o cache de 60 s é do processo.
      AlertRuntime.instance.resetAuditChainStatusCache();
      return endpoints.admin.verifyAuditChain(
        sessionBuilder,
        accessToken: _token(id, role),
      );
    }

    Future<int> ultimaSequence() async => (await AuditLog.db.findFirstRow(
      session,
      orderBy: (t) => t.sequence,
      orderDescending: true,
    ))!.sequence;

    test(
      'admin ⇒ verified sobre a cadeia gravada por OrmAuditTrail; '
      'auditado antes; resposta sem segredo nem hash',
      () async {
        for (var i = 0; i < 4; i++) {
          await linha(_acsA, 'cadeia_$i');
        }
        final s = await verificar(_admin, UserRole.admin);
        final ultima = await ultimaSequence();

        expect(s.state, AuditIntegrityState.verified);
        // A linha `read` do próprio pedido entra antes de verificar.
        expect(s.checkedRows, ultima);
        expect(s.headSequence, ultima);
        expect(s.firstBrokenSequence, isNull);
        expect(s.reasonCode, isNull);
        final auditada = await AuditLog.db.findFirstRow(
          session,
          where: (t) => t.resourceType.equals('admin_audit_chain'),
        );
        expect(auditada!.actionType, 'read');
        expect(auditada.result, 'success');
        expect(auditada.sequence, ultima);

        final texto = jsonEncode(s.toJson());
        expect(texto, isNot(contains(_segredo)));
        expect(texto, isNot(contains('entryHash')));
        expect(texto, isNot(contains('Hash')));
        final hashes = await AuditLog.db.find(session);
        for (final h in hashes) {
          expect(texto, isNot(contains(h.entryHash)));
        }
      },
    );

    test(
      'UPDATE direto do result ⇒ broken/hashMismatch na linha alterada',
      () async {
        await linha(_acsA, 'cadeia_0');
        final alvo = await linha(_acsA, 'cadeia_1');
        await linha(_acsA, 'cadeia_2');
        await session.db.unsafeExecute(
          'UPDATE audit_logs SET result = \'x\' WHERE sequence = @s',
          parameters: QueryParameters.named({'s': alvo}),
        );

        final s = await verificar(_admin, UserRole.admin);
        expect(s.state, AuditIntegrityState.broken);
        expect(s.reasonCode, AuditChainReason.hashMismatch);
        expect(s.firstBrokenSequence, alvo);
        expect(s.brokenInScope, isTrue);
        expect(s.headSequence, isNull);
        expect(jsonEncode(s.toJson()), isNot(contains(_segredo)));
      },
    );

    test('DELETE de uma linha do meio ⇒ broken/sequenceGap', () async {
      await linha(_acsA, 'cadeia_0');
      final meio = await linha(_acsA, 'cadeia_1');
      await linha(_acsA, 'cadeia_2');
      await session.db.unsafeExecute(
        'DELETE FROM audit_logs WHERE sequence = @s',
        parameters: QueryParameters.named({'s': meio}),
      );

      final s = await verificar(_admin, UserRole.admin);
      expect(s.state, AuditIntegrityState.broken);
      expect(s.reasonCode, AuditChainReason.sequenceGap);
      expect(s.firstBrokenSequence, meio + 1);
    });

    test(
      'coordenador com linha quebrada de outra UBS ⇒ broken, '
      'brokenInScope=false, sem sequence; na própria UBS ⇒ com sequence',
      () async {
        final daB = await linha(_acsB, 'cadeia_b');
        await linha(_acsA, 'cadeia_a');
        await session.db.unsafeExecute(
          'UPDATE audit_logs SET result = \'x\' WHERE sequence = @s',
          parameters: QueryParameters.named({'s': daB}),
        );

        final s = await verificar(_coordA, UserRole.coordinator);
        expect(s.state, AuditIntegrityState.broken);
        expect(s.brokenInScope, isFalse);
        expect(s.firstBrokenSequence, isNull);
        expect(s.reasonCode, isNull);
        expect(s.checkedRows, isNull);
        expect(s.headSequence, isNull);
        final texto = jsonEncode(s.toJson());
        expect(texto, isNot(contains('"$daB"')));
        expect(texto, isNot(contains(_segredo)));

        // A mesma quebra, agora numa linha de autor da UBS A.
        await session.db.unsafeExecute(
          'UPDATE audit_logs SET result = \'success\' WHERE sequence = @s',
          parameters: QueryParameters.named({'s': daB}),
        );
        final daA = await linha(_acsA, 'cadeia_a2');
        await session.db.unsafeExecute(
          'UPDATE audit_logs SET result = \'x\' WHERE sequence = @s',
          parameters: QueryParameters.named({'s': daA}),
        );
        final noEscopo = await verificar(_coordA, UserRole.coordinator);
        expect(noEscopo.state, AuditIntegrityState.broken);
        expect(noEscopo.brokenInScope, isTrue);
        expect(noEscopo.firstBrokenSequence, daA);
        expect(noEscopo.reasonCode, AuditChainReason.hashMismatch);
      },
    );

    test('ACS e paciente ⇒ AlertPermissionException e denied', () async {
      for (final (id, role, ma) in [
        (_acsA, UserRole.acs, _maA),
        (_paciente, UserRole.patient, _maA),
      ]) {
        await expectLater(
          endpoints.admin.verifyAuditChain(
            sessionBuilder,
            accessToken: _token(id, role, ma: ma),
          ),
          throwsA(
            isA<AlertPermissionException>().having(
              (e) => e.message,
              'message',
              'acesso restrito ao backoffice',
            ),
          ),
        );
      }
      final linhas = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('admin_audit_chain'),
        orderBy: (t) => t.sequence,
      );
      expect(linhas.map((l) => l.result), ['denied', 'denied']);
      expect(linhas.map((l) => l.userId.uuid), [_acsA, _paciente]);
    });

    test('sem token válido ⇒ falha, sem linha nenhuma', () async {
      final antes = await AuditLog.db.count(session);
      for (final token in ['', 'nao-e-um-token']) {
        await expectLater(
          endpoints.admin.verifyAuditChain(sessionBuilder, accessToken: token),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(await AuditLog.db.count(session), antes);
    });
  });
}
