import 'dart:io';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Esquema da trilha de auditoria (#45): as colunas da cadeia de `audit_logs`
/// não mudam, e `audit_exports`/`audit_chain_checkpoints` existem e se
/// comportam como o desenho manda (checkpoint único por `sequence`).
String _definitionDoUltimoEsquema() {
  final versoes = Directory('migrations')
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.split(Platform.pathSeparator).last)
      .toList()
    ..sort();
  return File('migrations/${versoes.last}/definition.sql').readAsStringSync();
}

String _tabela(String sql, String nome) {
  final inicio = sql.indexOf('CREATE TABLE "$nome" (');
  expect(inicio, greaterThanOrEqualTo(0), reason: 'tabela $nome ausente');
  return sql.substring(inicio, sql.indexOf(');', inicio));
}

void main() {
  group('Dado o definition.sql mais recente', () {
    final sql = _definitionDoUltimoEsquema();

    test('as colunas da cadeia de audit_logs não mudaram', () {
      final t = _tabela(sql, 'audit_logs');
      expect(t, contains('"sequence" bigint NOT NULL'));
      expect(t, contains('"previousHash" text NOT NULL'));
      expect(t, contains('"entryHash" text NOT NULL'));
      expect(t, contains('"timestamp" timestamp without time zone NOT NULL'));
      expect(sql, contains('CREATE UNIQUE INDEX "audit_logs_sequence_idx"'));
    });

    test('audit_logs ganhou os índices de consulta', () {
      expect(sql, contains('"audit_logs_timestamp_idx" ON "audit_logs"'));
      expect(sql, contains('"audit_logs_user_sequence_idx" ON "audit_logs"'));
    });
  });

  group('Dado o append-only da trilha (#82)', () {
    final bloco = File('database/audit_append_only.sql').readAsStringSync();
    // O cabeçalho do registry começa com `###`.
    final versoes = File('migrations/migration_registry.txt')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();

    test('o definition.sql mais recente instala o append-only', () {
      expect(
        _definitionDoUltimoEsquema(),
        contains(bloco),
        reason: 'a última migração perdeu o bloco: rode '
            'scripts/dev/append_audit_append_only.sh (ver backend/CLAUDE.md)',
      );
    });

    test('a migração de origem aplica o append-only num banco existente', () {
      final origem = versoes.where(
        (v) => File('migrations/$v/migration.sql')
            .readAsStringSync()
            .contains(bloco),
      );
      expect(origem, isNotEmpty);
    });
  });

  withServerpod('Dado o esquema de auditoria em Postgres real',
      (sessionBuilder, endpoints) {
    test('audit_chain_checkpoints rejeita duas linhas com a mesma sequence',
        () async {
      final session = sessionBuilder.build();
      AuditChainCheckpoint cp() => AuditChainCheckpoint(
            sequence: 10,
            entryHash: 'a' * 64,
            signature: 'b' * 64,
            createdAt: DateTime.now().toUtc(),
          );
      await AuditChainCheckpoint.db.insertRow(session, cp());
      await expectLater(
        AuditChainCheckpoint.db.insertRow(session, cp()),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('audit_exports grava e relê uma exportação (sequências opcionais)',
        () async {
      final session = sessionBuilder.build();
      final agora = DateTime.now().toUtc();
      final user = await User.db.insertRow(
        session,
        User(
          cpfHash: 'audit-export-1',
          name: 'Admin sintético',
          birthDate: DateTime.utc(1980),
          role: UserRole.admin,
          createdAt: agora,
          updatedAt: agora,
        ),
      );
      final gravada = await AuditExport.db.insertRow(
        session,
        AuditExport(
          requestedBy: user.id!,
          requestedAt: agora,
          filtersJson: '{}',
          format: 'csv',
          rowCount: 0,
          contentSha256: 'c' * 64,
          chainState: 'ok',
        ),
      );
      final lida = await AuditExport.db.findById(session, gravada.id!);
      expect(lida!.firstSequence, isNull);
      expect(lida.lastSequence, isNull);
      expect(lida.rowCount, 0);
    });

    test('os três triggers append-only existem e estão ativos (#82)', () async {
      final session = sessionBuilder.build();
      final r = await session.db.unsafeQuery(
        "SELECT tgname FROM pg_trigger WHERE tgname LIKE '%_append_only' "
        "AND tgenabled = 'O' ORDER BY tgname",
      );
      expect(r.map((row) => row.first), [
        'audit_chain_checkpoints_append_only',
        'audit_exports_append_only',
        'audit_logs_append_only',
      ]);
    });
  });
}
