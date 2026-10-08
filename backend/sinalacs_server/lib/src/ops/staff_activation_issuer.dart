import 'package:postgres/postgres.dart' as pg;
import 'package:sinalacs_server/src/application/auth/staff_activation_code.dart';

enum IssueStatus { issued, notFound }

class IssueResult {
  const IssueResult._(this.status, this.code, this.expiresAt);

  const IssueResult.notFound() : this._(IssueStatus.notFound, null, null);

  const IssueResult.issued(String code, DateTime expiresAt) : this._(IssueStatus.issued, code, expiresAt);

  final IssueStatus status;

  /// O código em claro. Só existe aqui, na saída da CLI: o banco guarda o hash.
  final String? code;
  final DateTime? expiresAt;
}

/// Emite o código de ativação da MFA de uma conta de staff (#48).
///
/// Matrícula inexistente e conta inativa dão o mesmo `notFound`: a CLI não
/// serve para sondar quais matrículas existem. Um código novo substitui o
/// anterior. A emissão fica registrada em `activationCodeIssuedBy`/`IssuedAt`
/// (a trilha `audit_logs` exige a cadeia de auditoria do servidor, que a CLI
/// não carrega).
Future<IssueResult> issueStaffActivationCode(
  pg.Session db, {
  required String matricula,
  required String issuedBy,
  required Duration validity,
  DateTime? now,
}) async {
  final quem = issuedBy.trim();
  if (quem.isEmpty) throw ArgumentError('informe quem está emitindo o código (--issued-by)');
  final agora = (now ?? DateTime.now()).toUtc();

  final conta = await db.execute(
    pg.Sql.named('SELECT "id","active" FROM "staff_accounts" WHERE "enrollmentId" = @m'),
    parameters: {'m': matricula.trim()},
  );
  if (conta.isEmpty || conta.single[1] != true) return const IssueResult.notFound();

  final codigo = StaffActivationCode.generate();
  final expira = agora.add(validity);
  await db.execute(
    pg.Sql.named(
      'UPDATE "staff_accounts" SET "activationCodeHash" = @h, "activationCodeExpiresAt" = @e, '
      '"activationCodeIssuedBy" = @by, "activationCodeIssuedAt" = @at WHERE "id" = @id',
    ),
    parameters: {'h': StaffActivationCode.hash(codigo), 'e': expira, 'by': quem, 'at': agora, 'id': conta.single[0]},
  );
  return IssueResult.issued(codigo, expira);
}
