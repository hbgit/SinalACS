import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_checkpoint_store.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_chain_reader.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_checkpoint_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_export_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:test/test.dart';

import 'support/privileged_tamper.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Append-only da trilha no banco (#82, RF17/STRIDE-R): o trigger por comando
/// recusa `UPDATE`, `DELETE` e `TRUNCATE` em `audit_logs`, `audit_exports` e
/// `audit_chain_checkpoints`, e as escritas legítimas (só `INSERT`) seguem
/// passando. Cada tentativa proibida roda dentro de `session.db.transaction`
/// (um savepoint no harness), para a recusa não abortar o resto do caso.
/// Dados sintéticos.
const _segredo = 'segredo-sintetico-da-82';
const _ator = '00000000-0000-4000-8000-0000000082a1';
final _t = DateTime.utc(2026, 10, 25, 12);

const _tabelas = ['audit_logs', 'audit_exports', 'audit_chain_checkpoints'];

/// Uma coluna de texto qualquer de cada tabela, para o `UPDATE … SET`.
const _colunaDeTexto = {
  'audit_logs': '"result"',
  'audit_exports': '"format"',
  'audit_chain_checkpoints': '"signature"',
};

final _recusado = throwsA(
  isA<DatabaseQueryException>()
      .having((e) => e.code, 'code', '42501')
      .having((e) => e.message, 'message', contains('append-only')),
);

Future<void> _ator1(Session s) => User.db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(_ator),
        cpfHash: 'append-only-$_ator',
        name: 'Admin Sintético 82',
        birthDate: DateTime.utc(1980),
        role: UserRole.admin,
        createdAt: _t,
        updatedAt: _t,
      ),
    )
    .then((_) {});

AuditEvent _evento(String resultado) => AuditEvent(
  userId: _ator,
  actionType: 'read',
  resourceType: 'append_only',
  result: resultado,
);

AuditExport _exportacao() => AuditExport(
  requestedBy: UuidValue.fromString(_ator),
  requestedAt: _t,
  filtersJson: '{}',
  format: 'csv',
  rowCount: 0,
  contentSha256: 'c' * 64,
  chainState: 'verified',
);

AuditChainCheckpointRecord _checkpoint(int sequence) {
  final hash = sequence.toRadixString(16).padLeft(64, '0');
  return AuditChainCheckpointRecord(
    sequence: sequence,
    entryHash: hash,
    signature: AuditChain(
      secret: _segredo,
    ).computeCheckpointSignature(sequence, hash),
  );
}

void main() {
  withServerpod('Dado o trigger append-only da trilha (#82)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmAuditTrail trilha;

    /// Um comando proibido, isolado num savepoint.
    Future<void> tentar(String sql, {QueryParameters? parameters}) =>
        session.db.transaction(
          (t) => session.db.unsafeExecute(
            sql,
            parameters: parameters,
            transaction: t,
          ),
        );

    Future<AuditChainVerification> verificar() => AuditChainVerifier(
      reader: OrmAuditChainReader(session: () => session),
      secret: _segredo,
    ).verify();

    setUp(() async {
      session = sessionBuilder.build();
      await _ator1(session);
      trilha = OrmAuditTrail(session: () => session, chainSecret: _segredo);
      // Uma linha em cada tabela, para o UPDATE/DELETE ter alvo.
      await trilha.record(_evento('success'));
      await AuditExport.db.insertRow(session, _exportacao());
      await OrmAuditCheckpointStore(
        session: () => session,
      ).advanceTo(_checkpoint(900000000001));
    });

    for (final tabela in _tabelas) {
      test('$tabela: UPDATE é recusado', () async {
        await expectLater(
          tentar('UPDATE $tabela SET ${_colunaDeTexto[tabela]} = \'x\''),
          _recusado,
        );
      });

      test('$tabela: DELETE é recusado', () async {
        await expectLater(tentar('DELETE FROM $tabela'), _recusado);
      });

      test('$tabela: TRUNCATE é recusado', () async {
        await expectLater(tentar('TRUNCATE $tabela CASCADE'), _recusado);
      });
    }

    test('UPDATE e DELETE sem linha alvo também são recusados', () async {
      await expectLater(
        tentar("UPDATE audit_logs SET result = 'x' WHERE false"),
        _recusado,
      );
      await expectLater(
        tentar('DELETE FROM audit_logs WHERE false'),
        _recusado,
      );
    });

    test('depois da recusa, a trilha continua gravando', () async {
      final antes = (await AuditLog.db.findFirstRow(
        session,
        orderBy: (t) => t.sequence,
        orderDescending: true,
      ))!.sequence;
      await expectLater(
        tentar("UPDATE audit_logs SET result = 'x'"),
        _recusado,
      );

      await trilha.record(_evento('depois_da_recusa'));

      final cabeca = await AuditLog.db.findFirstRow(
        session,
        orderBy: (t) => t.sequence,
        orderDescending: true,
      );
      expect(cabeca!.sequence, antes + 1);
      expect(cabeca.result, 'depois_da_recusa');
      expect((await verificar()).ok, isTrue);
    });

    test('advanceTo e exportação seguem funcionando', () async {
      final checkpoints = OrmAuditCheckpointStore(session: () => session);
      // A segunda cai no ON CONFLICT DO NOTHING, que não é UPDATE.
      await checkpoints.advanceTo(_checkpoint(900000000002));
      await checkpoints.advanceTo(_checkpoint(900000000002));
      expect(
        await AuditChainCheckpoint.db.count(
          session,
          where: (t) => t.sequence.equals(900000000002),
        ),
        1,
      );

      final exportacoes = await AuditExport.db.count(session);
      await OrmAuditExportStore(
        session: () => session,
        appendAudit: trilha.recordInTransaction,
      ).commitExport(_exportacao(), _evento('exportado'));
      expect(await AuditExport.db.count(session), exportacoes + 1);
      expect((await verificar()).ok, isTrue);
    });

    test('o superusuário ainda contorna (limite documentado)', () async {
      final alvo = (await AuditLog.db.findFirstRow(
        session,
        orderBy: (t) => t.sequence,
        orderDescending: true,
      ))!.sequence;

      await adulterarComoSuperusuario(
        session,
        "UPDATE audit_logs SET result = 'x' WHERE sequence = @s",
        parameters: QueryParameters.named({'s': alvo}),
      );

      final quebrada = await verificar();
      expect(quebrada.ok, isFalse);
      expect(quebrada.reasonCode, AuditChainReason.hashMismatch);

      // O atalho não vaza: o resto do caso volta a ter o trigger.
      await expectLater(
        tentar("UPDATE audit_logs SET result = 'y' WHERE sequence = @s",
            parameters: QueryParameters.named({'s': alvo})),
        _recusado,
      );
    });

    test('PUBLIC não tem UPDATE, DELETE nem TRUNCATE na trilha', () async {
      final r = await session.db.unsafeQuery(
        'SELECT c.relname, p.privilege_type '
        'FROM pg_class c, aclexplode(coalesce(c.relacl, acldefault(\'r\', c.relowner))) p '
        'WHERE c.relname = ANY(@tabelas) AND p.grantee = 0 '
        "AND p.privilege_type IN ('UPDATE', 'DELETE', 'TRUNCATE')",
        parameters: QueryParameters.named({'tabelas': _tabelas}),
      );
      expect(r, isEmpty);
    });
  });
}
