import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_row_sealer.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_admin_read_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_chain_reader.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Leitura em lotes da cadeia e selo por linha (#45, Task 5) contra Postgres
/// real. Dados sintéticos; as adulterações (`UPDATE`/`DELETE` direto) só
/// existem no banco de teste do harness, que é desfeito a cada caso.
const _segredo = 'segredo-sintetico-da-task-5';
const _ator = '00000000-0000-4000-8000-0000000045a1';
final _t = DateTime.utc(2026, 10, 13, 12);

Future<void> _ator1(Session s) => User.db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(_ator),
        cpfHash: 'task5-$_ator',
        name: 'Admin Sintético Task 5',
        birthDate: DateTime.utc(1980),
        role: UserRole.admin,
        createdAt: _t,
        updatedAt: _t,
      ),
    )
    .then((_) {});

/// Seis linhas encadeadas pelo caminho de produção; as linhas 2 e 5 (relativas
/// a [base]) são as únicas com `resourceType` `seal_alvo`.
Future<int> _seisLinhas(Session s) async {
  final trilha = OrmAuditTrail(session: () => s, chainSecret: _segredo);
  for (var i = 1; i <= 6; i++) {
    await trilha.record(
      AuditEvent(
        userId: _ator,
        actionType: 'read',
        resourceType: i == 2 || i == 5 ? 'seal_alvo' : 'seal_outro',
        result: 'success',
      ),
    );
  }
  final primeira = await AuditLog.db.findFirstRow(
    s,
    where: (t) => t.resourceType.equals('seal_outro'),
    orderBy: (t) => t.sequence,
  );
  return primeira!.sequence; // sequence da linha 1
}

void main() {
  withServerpod('Dada a cadeia de audit_logs (#45, Task 5)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmAuditChainReader reader;
    late OrmAdminReadStore store;
    final selador = AuditRowSealer(AuditChain(secret: _segredo));

    setUp(() async {
      session = sessionBuilder.build();
      await _ator1(session);
      reader = OrmAuditChainReader(session: () => session);
      store = OrmAdminReadStore(session: () => session);
    });

    Future<Map<int, AuditRowSeal>> selosDaPagina(AdminAuditRowPage p) async => {
      for (final r in p.items) r.entry.sequence: selador.sealInput(r.seal),
    };

    test(
      'readBatch: sequence > afterSequence, ordem crescente, no máximo limit',
      () async {
        final base = await _seisLinhas(session);

        final lote = await reader.readBatch(afterSequence: base, limit: 3);
        expect(lote.map((e) => e.fields.sequence), [
          base + 1,
          base + 2,
          base + 3,
        ]);

        final fim = await reader.readBatch(afterSequence: base + 3, limit: 100);
        expect(fim.map((e) => e.fields.sequence), [base + 4, base + 5]);

        expect(
          await reader.readBatch(afterSequence: base + 5, limit: 10),
          isEmpty,
        );
      },
    );

    test(
      'entryAt devolve a linha com os campos da cadeia e nulo se não existe',
      () async {
        final base = await _seisLinhas(session);
        final linha = await reader.entryAt(base + 2);
        final anterior = await reader.entryAt(base + 1);

        expect(linha!.fields.sequence, base + 2);
        expect(linha.fields.previousHash, anterior!.entryHash);
        expect(
          AuditChain(secret: _segredo).matches(linha.fields, linha.entryHash),
          isTrue,
          reason: 'o reader devolve exatamente o que o HMAC cobriu',
        );
        expect(await reader.entryAt(base + 99), isNull);
      },
    );

    test(
      'o verificador em lotes lê a cadeia do Postgres e acha a edição',
      () async {
        final base = await _seisLinhas(session);
        final verificador = AuditChainVerifier(
          reader: reader,
          secret: _segredo,
        );

        final integra = await verificador.verify();
        expect(integra.ok, isTrue);
        expect(integra.checked, base + 5);

        await session.db.unsafeExecute(
          'UPDATE audit_logs SET result = \'x\' WHERE sequence = @s',
          parameters: QueryParameters.named({'s': base + 4}),
        );
        final quebrada = await verificador.verify();
        expect(quebrada.ok, isFalse);
        expect(quebrada.reasonCode, AuditChainReason.hashMismatch);
        expect(quebrada.brokenAtSequence, base + 4);
      },
    );

    test(
      'Review Focus 1: linhas filtradas não adjacentes (2 e 5) são verified; '
      'editar a 5 deixa só ela invalid e a 6 continua verified pelo selo',
      () async {
        final base = await _seisLinhas(session);
        final s2 = base + 1;
        final s5 = base + 4;
        final s6 = base + 5;
        final filtro = AdminAuditFilter(resourceType: 'seal_alvo');

        final pagina = await store.auditLogs(
          const AdminScope.system(),
          filter: filtro,
          limit: 50,
        );
        expect(
          pagina.items.map((r) => r.entry.sequence),
          [s5, s2],
          reason: 'só as linhas 2 e 5, não contíguas',
        );
        expect(
          await selosDaPagina(pagina),
          {
            s5: AuditRowSeal.verified,
            s2: AuditRowSeal.verified,
          },
          reason: 'o vizinho vem do banco, não da linha ao lado na página',
        );

        await session.db.unsafeExecute(
          'UPDATE audit_logs SET result = \'x\' WHERE sequence = @s',
          parameters: QueryParameters.named({'s': s5}),
        );

        final depois = await store.auditLogs(
          const AdminScope.system(),
          filter: filtro,
          limit: 50,
        );
        expect(await selosDaPagina(depois), {
          s5: AuditRowSeal.invalid,
          s2: AuditRowSeal.verified,
        });

        // Limite documentado em AuditRowSealer: a 6 encadeia no entryHash
        // ORIGINAL da 5 (que não foi recalculado), então o selo dela confere.
        final tudo = await store.auditLogs(
          const AdminScope.system(),
          limit: 50,
        );
        final selos = await selosDaPagina(tudo);
        expect(selos[s6], AuditRowSeal.verified);
        expect(selos[s5], AuditRowSeal.invalid);
        expect(selos[s2], AuditRowSeal.verified);
      },
    );

    test(
      'vizinho apagado ⇒ a linha seguinte fica unverifiable, nunca verified',
      () async {
        final base = await _seisLinhas(session);
        await session.db.unsafeExecute(
          'DELETE FROM audit_logs WHERE sequence = @s',
          parameters: QueryParameters.named({'s': base + 3}),
        );

        final pagina = await store.auditLogs(
          const AdminScope.system(),
          filter: AdminAuditFilter(resourceType: 'seal_alvo'),
          limit: 50,
        );
        expect(await selosDaPagina(pagina), {
          base + 4: AuditRowSeal.unverifiable,
          base + 1: AuditRowSeal.verified,
        });
      },
    );

    test(
      'o serviço sela cada linha e a resposta não carrega hash nem segredo',
      () async {
        final base = await _seisLinhas(session);
        final servico = AdminReadService(
          store: store,
          audit: OrmAuditTrail(session: () => session, chainSecret: _segredo),
          auditChain: AuditChain(secret: _segredo),
        );
        final admin = AuthenticatedUser(
          id: _ator,
          role: UserRole.admin,
          microAreaId: null,
          deviceId: 'sem-aparelho',
        );

        final pagina = await servico.auditLogs(admin, limit: 50);
        final porSequence = {for (final e in pagina.items) e.sequence: e};
        for (var s = base; s <= base + 5; s++) {
          expect(
            porSequence[s]!.integrity,
            AuditRowSeal.verified,
            reason: 'linha $s íntegra',
          );
        }

        final json = jsonEncode(pagina.toJson());
        expect(json, contains('"integrity":"verified"'));
        expect(json, isNot(contains('Hash')));
        expect(json, isNot(contains('ipHash')));
        expect(json, isNot(contains(_segredo)));
        final linha = await AuditLog.db.findFirstRow(
          session,
          where: (t) => t.sequence.equals(base + 1),
        );
        expect(json, isNot(contains(linha!.entryHash)));
        expect(json, isNot(contains(linha.previousHash)));
        expect(json, isNot(contains(linha.ipHash)));
      },
    );

    test('segredo errado no serviço ⇒ nenhuma linha verified', () async {
      await _seisLinhas(session);
      final servico = AdminReadService(
        store: store,
        audit: OrmAuditTrail(session: () => session, chainSecret: _segredo),
        auditChain: AuditChain(secret: 'outro-segredo'),
      );
      final pagina = await servico.auditLogs(
        AuthenticatedUser(
          id: _ator,
          role: UserRole.admin,
          microAreaId: null,
          deviceId: 'sem-aparelho',
        ),
        limit: 50,
      );
      expect(pagina.items, isNotEmpty);
      expect(
        pagina.items.where((e) => e.integrity == AuditRowSeal.verified),
        isEmpty,
      );
    });
  });
}
