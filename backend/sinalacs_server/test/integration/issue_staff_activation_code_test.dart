import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:sinalacs_server/src/application/auth/staff_activation_code.dart';
import 'package:sinalacs_server/src/ops/staff_activation_issuer.dart';
import 'package:test/test.dart';

/// Emissão do código de ativação pela CLI do operador (#48), contra o Postgres
/// de teste (porta 9090, `sinalacs_test`). Tudo roda numa transação que o teste
/// desfaz: nada fica no banco. Dados sintéticos.
const _ativo = '00000000-0000-4000-8000-0000000000c1';
const _inativo = '00000000-0000-4000-8000-0000000000c2';

class _Desfazer implements Exception {}

String _senhaDoBancoDeTeste() {
  final texto = File('config/passwords.yaml').readAsStringSync();
  final m = RegExp(r'^test:\s*\n(?:[ \t]+.*\n)*?[ \t]+database:\s*[\x27"]?([^\x27"\n]+)', multiLine: true)
      .firstMatch(texto);
  if (m == null) fail('config/passwords.yaml sem test.database (rode scripts/dev/bootstrap_env.sh)');
  return m.group(1)!.trim();
}

Future<void> _comTransacao(Future<void> Function(pg.Session tx) corpo) async {
  final conexao = await pg.Connection.open(
    pg.Endpoint(host: 'localhost', port: 9090, database: 'sinalacs_test', username: 'postgres', password: _senhaDoBancoDeTeste()),
    settings: const pg.ConnectionSettings(sslMode: pg.SslMode.disable),
  );
  try {
    await conexao.runTx((tx) async {
      await _semear(tx);
      await corpo(tx);
      throw _Desfazer();
    });
  } on _Desfazer {
    // rollback esperado
  } finally {
    await conexao.close();
  }
}

Future<void> _semear(pg.Session tx) async {
  for (final (id, matricula, ativo) in [(_ativo, 'ADM-CLI-001', true), (_inativo, 'ADM-CLI-002', false)]) {
    await tx.execute(
      pg.Sql.named('INSERT INTO "users" ("id","cpfHash","name","birthDate","role","microAreaId","createdAt","updatedAt") '
          "VALUES (@id,@hash,'Admin CLI','1985-01-01','admin',NULL,NOW(),NOW())"),
      parameters: {'id': id, 'hash': 'cli-test-$id'},
    );
    await tx.execute(
      pg.Sql.named('INSERT INTO "staff_accounts" ("id","enrollmentId","active") VALUES (@id,@m,@a)'),
      parameters: {'id': id, 'm': matricula, 'a': ativo},
    );
  }
}

void main() {
  final t0 = DateTime.utc(2026, 10, 7, 12);

  test('matrícula inexistente: notFound e nada é gravado', () => _comTransacao((tx) async {
        final r = await issueStaffActivationCode(tx,
            matricula: 'NAO-EXISTE', issuedBy: 'operador', validity: const Duration(hours: 24), now: t0);
        expect(r.code, isNull);
        expect(r.status, IssueStatus.notFound);
      }));

  test('conta inativa: notFound (a mensagem não distingue inexistente de inativa)', () => _comTransacao((tx) async {
        final r = await issueStaffActivationCode(tx,
            matricula: 'ADM-CLI-002', issuedBy: 'operador', validity: const Duration(hours: 24), now: t0);
        expect(r.status, IssueStatus.notFound);
        final linha = await tx.execute(pg.Sql.named('SELECT "activationCodeHash" FROM "staff_accounts" WHERE "id"=@id'),
            parameters: {'id': _inativo});
        expect(linha.single[0], isNull);
      }));

  test('conta ativa: grava só o hash, a validade e quem emitiu', () => _comTransacao((tx) async {
        final r = await issueStaffActivationCode(tx,
            matricula: 'ADM-CLI-001', issuedBy: 'operador', validity: const Duration(hours: 24), now: t0);
        expect(r.status, IssueStatus.issued);
        final codigo = r.code!;
        final linha = (await tx.execute(
          pg.Sql.named('SELECT "activationCodeHash","activationCodeExpiresAt","activationCodeIssuedBy","activationCodeIssuedAt" '
              'FROM "staff_accounts" WHERE "id"=@id'),
          parameters: {'id': _ativo},
        ))
            .single;
        expect(linha[0], StaffActivationCode.hash(codigo));
        expect(linha[0], isNot(contains(StaffActivationCode.normalize(codigo))));
        expect(linha[1], t0.add(const Duration(hours: 24)));
        expect(linha[2], 'operador');
        expect(linha[3], t0);
      }));

  test('emitir de novo troca o código', () => _comTransacao((tx) async {
        final a = await issueStaffActivationCode(tx,
            matricula: 'ADM-CLI-001', issuedBy: 'op-1', validity: const Duration(hours: 1), now: t0);
        final b = await issueStaffActivationCode(tx,
            matricula: 'ADM-CLI-001', issuedBy: 'op-2', validity: const Duration(hours: 1), now: t0);
        expect(a.code, isNot(b.code));
        final h = (await tx.execute(pg.Sql.named('SELECT "activationCodeHash" FROM "staff_accounts" WHERE "id"=@id'),
                parameters: {'id': _ativo}))
            .single[0];
        expect(h, StaffActivationCode.hash(b.code!));
      }));

  test('quem emitiu é obrigatório', () => _comTransacao((tx) async {
        await expectLater(
          issueStaffActivationCode(tx, matricula: 'ADM-CLI-001', issuedBy: '  ', validity: const Duration(hours: 1), now: t0),
          throwsArgumentError,
        );
      }));
}
