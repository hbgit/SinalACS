import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Contas do backoffice sobre Postgres (issue #43).
///
/// SQL direto (`unsafeQuery` com parâmetros nomeados), como `OrmAdminReadStore`:
/// o ORM do Serverpod não expressa a junção `users`/`acs`/`ubs`/`micro_areas`/
/// `user_credentials` que as listagens precisam. Nada aqui concatena **valor**
/// no texto da consulta; só a presença do filtro de escopo e do filtro por id
/// muda a forma.
///
/// O escopo do coordenador é `acs."ubsId"` — o mesmo campo que o login usa —, e
/// a listagem inclui quem não tem microárea (`LEFT JOIN`): um ACS recém-cadastrado,
/// ainda sem território, precisa aparecer para poder ser vinculado.
///
/// `mfaActive` vem da própria consulta (`totpEnabledAt IS NOT NULL`), nunca de
/// coluna calculada: MFA iniciada e não confirmada não é MFA ativa.
class OrmAdminAccountStore implements AdminAccountStore {
  OrmAdminAccountStore({required Session Function() session})
    : _session = session;

  final Session Function() _session;

  /// `@ubs` nulo = sistema inteiro (administrador).
  static const _escopoAcs = '(@ubs::uuid IS NULL OR acs."ubsId" = @ubs::uuid)';

  /// Colunas e junções das duas listagens; o `WHERE`/`ORDER BY` de cada método
  /// é o que varia.
  static const _selecaoAcs = '''
      SELECT u.id, u.name, acs."enrollmentId", acs."ubsId", ub.name,
             m.id, m.name, acs.active, (uc."totpEnabledAt" IS NOT NULL)
      FROM acs
      JOIN users u ON u.id = acs.id
      JOIN ubs ub ON ub.id = acs."ubsId"
      LEFT JOIN micro_areas m ON m.id = u."microAreaId"
      LEFT JOIN user_credentials uc ON uc."userId" = acs.id''';

  static const _selecaoStaff = '''
      SELECT u.id, u.name, s."enrollmentId", u.role, ub.name, s.active,
             (uc."totpEnabledAt" IS NOT NULL)
      FROM staff_accounts s
      JOIN users u ON u.id = s.id
      LEFT JOIN ubs ub ON ub.id = s."ubsId"
      LEFT JOIN user_credentials uc ON uc."userId" = s.id''';

  @override
  Future<List<AdminAcs>> acsList(AdminScope scope) async {
    final rows = await _session().db.unsafeQuery(
      '$_selecaoAcs WHERE $_escopoAcs ORDER BY u.name, u.id',
      parameters: QueryParameters.named({'ubs': scope.ubsId}),
    );
    return [for (final r in rows) _acs(r)];
  }

  @override
  Future<AdminAcs?> acsById(AdminScope scope, String acsId) async {
    // Um id que não é UUID nem chega ao banco: o Postgres lançaria erro de
    // sintaxe no `::uuid`, e um erro de servidor diria ao chamador que o id é
    // inválido — em vez da mesma resposta de "não existe ou não é seu".
    if (!_uuidValido(acsId)) return null;
    final rows = await _session().db.unsafeQuery(
      '$_selecaoAcs WHERE u.id = @id::uuid AND $_escopoAcs',
      parameters: QueryParameters.named({'id': acsId, 'ubs': scope.ubsId}),
    );
    return rows.isEmpty ? null : _acs(rows.single);
  }

  @override
  Future<List<AdminStaff>> staffList() async {
    final rows = await _session().db.unsafeQuery(
      '$_selecaoStaff ORDER BY u.name, u.id',
    );
    return [for (final r in rows) _staff(r)];
  }

  @override
  Future<AdminStaff?> staffById(String staffId) async {
    if (!_uuidValido(staffId)) return null;
    final rows = await _session().db.unsafeQuery(
      '$_selecaoStaff WHERE s.id = @id::uuid',
      parameters: QueryParameters.named({'id': staffId}),
    );
    return rows.isEmpty ? null : _staff(rows.single);
  }

  /// Mesma leitura de `OrmAdminReadStore.ubsOf`: `staff_accounts.ubsId` é a
  /// única fonte do escopo do coordenador.
  @override
  Future<String?> ubsOf(String staffId) async {
    if (!_uuidValido(staffId)) return null;
    final conta = await StaffAccount.db.findById(
      _session(),
      UuidValue.fromString(staffId),
    );
    return conta?.ubsId?.toString();
  }

  /// `UuidValue.fromString` **não** valida nada (só embrulha a string); quem
  /// valida o formato é `withFormatValidation`. Sem esta guarda, um id fora do
  /// formato chega ao `::uuid` e vira erro de sintaxe do Postgres — um 500 no
  /// lugar da resposta de "não existe".
  static bool _uuidValido(String id) {
    try {
      UuidValue.withFormatValidation(id);
      return true;
    } on FormatException {
      return false;
    }
  }

  static AdminAcs _acs(List<dynamic> r) => AdminAcs(
    id: r[0].toString(),
    name: r[1] as String,
    enrollmentId: r[2] as String,
    ubsId: r[3].toString(),
    ubsName: r[4] as String,
    // Nulos enquanto o ACS não tem território (`users.microAreaId`).
    microAreaId: r[5]?.toString(),
    microAreaName: r[6] as String?,
    active: r[7] as bool,
    mfaActive: r[8] as bool,
  );

  static AdminStaff _staff(List<dynamic> r) => AdminStaff(
    id: r[0].toString(),
    name: r[1] as String,
    enrollmentId: r[2] as String,
    role: UserRole.fromJson(r[3] as String),
    // Nulo para o administrador (sistema inteiro) e para o coordenador sem UBS.
    ubsName: r[4] as String?,
    active: r[5] as bool,
    mfaActive: r[6] as bool,
  );
}
