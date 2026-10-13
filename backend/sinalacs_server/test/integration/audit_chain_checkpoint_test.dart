import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_checkpoint_store.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_checkpoint_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Checkpoint de cauda da cadeia de `audit_logs` (#45, Task 7, D4) pelo
/// endpoint `admin.verifyAuditChain`, com Postgres real e tokens reais. As
/// adulterações (`DELETE`/`UPDATE` direto, restauração de "backup") só
/// existem no banco de teste do harness, desfeito a cada caso. Dados
/// sintéticos; ids próprios.
const _admin = '00000000-0000-4000-8000-0000000047a1';
const _ator = '00000000-0000-4000-8000-0000000047a2';
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

Future<void> _seed(Session s) async {
  for (final id in [_admin, _ator]) {
    await User.db.insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'checkpoint-$id',
        name: 'Sintético $id',
        birthDate: DateTime.utc(1980),
        role: UserRole.admin,
        createdAt: _t,
        updatedAt: _t,
      ),
    );
  }
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_admin),
      enrollmentId: 'ADM-CHECKPOINT-1',
      active: true,
    ),
  );
}

void main() {
  withServerpod('Dado o checkpoint de cauda da cadeia (#45, Task 7)', (
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

    Future<void> linhas(int n) async {
      final trilha = OrmAuditTrail(session: () => session, chainSecret: _segredo);
      for (var i = 0; i < n; i++) {
        await trilha.record(
          AuditEvent(
            userId: _ator,
            actionType: 'read',
            resourceType: 'checkpoint_$i',
            result: 'success',
          ),
        );
      }
    }

    Future<AdminAuditChainStatus> verificar() {
      // Cada chamada é uma verificação nova: o cache de 60 s é do processo.
      AlertRuntime.instance.resetAuditChainStatusCache();
      final token = AlertRuntime.instance.auth.issueToken(
        AuthenticatedUser(
          id: _admin,
          role: UserRole.admin,
          microAreaId: null,
          deviceId: 'sem-aparelho',
        ),
      );
      return endpoints.admin.verifyAuditChain(
        sessionBuilder,
        accessToken: token,
      );
    }

    Future<int> cabeca() async => (await AuditLog.db.findFirstRow(
      session,
      orderBy: (t) => t.sequence,
      orderDescending: true,
    ))!.sequence;

    Future<List<AuditChainCheckpoint>> checkpoints() =>
        AuditChainCheckpoint.db.find(session, orderBy: (t) => t.sequence);

    test(
      'verified grava o checkpoint assinado; apagar as 3 últimas linhas ⇒ '
      'broken/tailTruncated',
      () async {
        await linhas(5);
        final primeira = await verificar();
        expect(primeira.state, AuditIntegrityState.verified);
        final head = await cabeca();
        expect(primeira.headSequence, head);

        final gravados = await checkpoints();
        expect(gravados, hasLength(1));
        final c = gravados.single;
        final linhaHead = await AuditLog.db.findFirstRow(
          session,
          where: (t) => t.sequence.equals(head),
        );
        expect(c.sequence, head);
        expect(c.entryHash, linhaHead!.entryHash);
        expect(
          c.signature,
          AuditChain(secret: _segredo).computeCheckpointSignature(
            head,
            linhaHead.entryHash,
          ),
        );
        // O verificador sozinho não veria: o que sobra é contíguo.
        await session.db.unsafeExecute(
          'DELETE FROM audit_logs WHERE sequence > @s',
          parameters: QueryParameters.named({'s': head - 3}),
        );

        final segunda = await verificar();
        expect(segunda.state, AuditIntegrityState.broken);
        expect(segunda.reasonCode, AuditChainReason.tailTruncated);
        expect(segunda.firstBrokenSequence, head);
        expect(segunda.headSequence, isNull);
        // Cadeia quebrada não grava; o checkpoint segue lá.
        expect((await checkpoints()).map((c) => c.sequence), [head]);
        final texto = jsonEncode(segunda.toJson());
        expect(texto, isNot(contains(c.entryHash)));
        expect(texto, isNot(contains(c.signature)));
      },
    );

    test(
      'cauda apagada e a aplicação regrava por cima (HMAC válido) ⇒ '
      'entryHash diverge no checkpoint ⇒ tailTruncated',
      () async {
        await linhas(5);
        expect((await verificar()).state, AuditIntegrityState.verified);
        final head = await cabeca();
        await session.db.unsafeExecute(
          'DELETE FROM audit_logs WHERE sequence > @s',
          parameters: QueryParameters.named({'s': head - 3}),
        );
        // A trilha de produção volta a ocupar as sequences apagadas.
        await linhas(5);
        expect(await cabeca(), greaterThan(head));

        final s = await verificar();
        expect(s.state, AuditIntegrityState.broken);
        expect(s.reasonCode, AuditChainReason.tailTruncated);
        expect(s.firstBrokenSequence, head);
      },
    );

    test('sem apagar, linha nova por cima ⇒ verified e o checkpoint avança',
        () async {
      await linhas(3);
      expect((await verificar()).state, AuditIntegrityState.verified);
      final antes = (await checkpoints()).single.sequence;

      await linhas(2);
      final s = await verificar();
      expect(s.state, AuditIntegrityState.verified);
      final depois = await checkpoints();
      expect(depois.map((c) => c.sequence), [antes, await cabeca()]);
      expect(depois.last.sequence, greaterThan(antes));
    });

    test(
      'checkpoint com signature inválida ⇒ ignorado e sinalizado: '
      'inconclusive/checkpointInvalid, nada gravado, nada apagado',
      () async {
        await linhas(3);
        expect((await verificar()).state, AuditIntegrityState.verified);
        await session.db.unsafeExecute(
          'UPDATE audit_chain_checkpoints SET signature = @sig',
          parameters: QueryParameters.named({'sig': 'f' * 64}),
        );

        final s = await verificar();
        expect(s.state, AuditIntegrityState.inconclusive);
        expect(s.reasonCode, AuditChainReason.checkpointInvalid);
        expect(s.headSequence, isNull);
        final depois = await checkpoints();
        expect(depois, hasLength(1));
        expect(depois.single.signature, 'f' * 64);
      },
    );

    test(
      'LIMITE CONHECIDO: restaurar o banco inteiro de um backup antigo '
      '(cadeia e checkpoints) ⇒ verified',
      () async {
        await linhas(3);
        expect((await verificar()).state, AuditIntegrityState.verified);
        // "Backup": cópia das duas tabelas neste instante.
        await session.db.unsafeExecute(
          'CREATE TEMP TABLE bk_audit_logs AS SELECT * FROM audit_logs',
        );
        await session.db.unsafeExecute(
          'CREATE TEMP TABLE bk_checkpoints AS '
          'SELECT * FROM audit_chain_checkpoints',
        );
        await linhas(4);
        expect((await verificar()).state, AuditIntegrityState.verified);
        expect(await checkpoints(), hasLength(2));

        // "Restauração": as duas tabelas voltam juntas, coerentes entre si.
        for (final sql in [
          'DELETE FROM audit_chain_checkpoints',
          'DELETE FROM audit_logs',
          'INSERT INTO audit_logs SELECT * FROM bk_audit_logs',
          'INSERT INTO audit_chain_checkpoints SELECT * FROM bk_checkpoints',
        ]) {
          await session.db.unsafeExecute(sql);
        }

        // A cauda perdida não é detectável: documentado em Pendências.
        final s = await verificar();
        expect(s.state, AuditIntegrityState.verified);
        expect(s.reasonCode, isNull);
      },
    );

    group('OrmAuditCheckpointStore', () {
      AuditChainCheckpointRecord registro(int sequence) {
        final hash = sequence.toRadixString(16).padLeft(64, '0');
        return AuditChainCheckpointRecord(
          sequence: sequence,
          entryHash: hash,
          signature: AuditChain(
            secret: _segredo,
          ).computeCheckpointSignature(sequence, hash),
        );
      }

      test('só avança: menor ou igual ao último não grava, sem erro', () async {
        final store = OrmAuditCheckpointStore(session: () => session);
        await store.advanceTo(registro(10));
        await store.advanceTo(registro(7));
        await store.advanceTo(registro(10));
        await store.advanceTo(registro(12));
        expect((await checkpoints()).map((c) => c.sequence), [10, 12]);

        final ultimos = await store.latest(limit: 1);
        expect(ultimos.single.sequence, 12);
        expect(ultimos.single.entryHash, registro(12).entryHash);
        expect(ultimos.single.signature, registro(12).signature);
        expect(
          (await store.latest(limit: 5)).map((c) => c.sequence),
          [12, 10],
        );
      });

      test('a mesma sequence de novo não vira erro de índice único', () async {
        final store = OrmAuditCheckpointStore(session: () => session);
        await store.advanceTo(registro(30));
        await expectLater(store.advanceTo(registro(30)), completes);
        expect(await checkpoints(), hasLength(1));
      });
    });
  });

  // Corrida real entre transações: o harness com rollback não aceita
  // transações concorrentes, então este grupo grava de verdade, numa faixa
  // de `sequence` só dele, e apaga tudo no `finally` — um checkpoint
  // esquecido aqui faria toda verificação seguinte do banco de teste virar
  // tailTruncated.
  withServerpod(
    'Dado OrmAuditCheckpointStore sem rollback (corrida, #45 Task 7)',
    (sessionBuilder, endpoints) {
      const base = 8000000000000;

      AuditChainCheckpointRecord registro(int sequence) {
        final hash = sequence.toRadixString(16).padLeft(64, '0');
        return AuditChainCheckpointRecord(
          sequence: sequence,
          entryHash: hash,
          signature: AuditChain(
            secret: _segredo,
          ).computeCheckpointSignature(sequence, hash),
        );
      }

      Future<void> limpar(Session s) => AuditChainCheckpoint.db
          .deleteWhere(s, where: (t) => t.sequence >= base)
          .then((_) {});

      Future<List<int>> faixa(Session s) async => [
        for (final c in await AuditChainCheckpoint.db.find(
          s,
          where: (t) => t.sequence >= base,
          orderBy: (t) => t.sequence,
        ))
          c.sequence,
      ];

      test('duas verificações gravando a MESMA sequence ao mesmo tempo ⇒ uma '
          'linha, nenhuma exceção; sequences diferentes ⇒ nunca a menor '
          'depois da maior', () async {
        final s = sessionBuilder.build();
        await limpar(s);
        try {
          final a = OrmAuditCheckpointStore(
            session: () => sessionBuilder.build(),
          );
          final b = OrmAuditCheckpointStore(
            session: () => sessionBuilder.build(),
          );
          await Future.wait([
            a.advanceTo(registro(base + 1)),
            b.advanceTo(registro(base + 1)),
          ]);
          expect(await faixa(s), [base + 1]);

          await Future.wait([
            a.advanceTo(registro(base + 2)),
            b.advanceTo(registro(base + 3)),
          ]);
          final depois = await faixa(s);
          // Ordem de commit livre: ou as duas avançaram (2 antes de 3), ou a
          // 3 venceu e a 2 foi recusada. Nunca só a 2.
          expect(
            depois,
            anyOf(
              equals([base + 1, base + 2, base + 3]),
              equals([base + 1, base + 3]),
            ),
          );
        } finally {
          await limpar(s);
        }
      });
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}
