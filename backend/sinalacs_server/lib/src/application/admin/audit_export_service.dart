import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/admin/admin_labels.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_csv.dart';
import 'package:sinalacs_server/src/application/audit/audit_row_sealer.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:uuid/uuid.dart';

/// O que a exportação precisa do mundo (#45, Task 10). Interface à parte do
/// ORM, como `AdminReadStore`: o serviço e seus testes não conhecem SQL.
///
/// Toda leitura é do **sistema inteiro** (só o administrador exporta, D5) e
/// limitada a `sequence <= headSequence`: o recorte é fixado antes de o
/// evento `export` existir.
abstract interface class AuditExportStore implements AdminScopeStore {
  /// Maior `sequence` de `audit_logs` agora (0 com a tabela vazia).
  Future<int> headSequence();

  /// Linhas do recorte ([filter], `sequence <= headSequence`), contadas até
  /// no máximo [cap]: devolve `min(total, cap)`.
  Future<int> countUpTo(
    AdminAuditFilter filter, {
    required int headSequence,
    required int cap,
  });

  /// As linhas do recorte em ordem **crescente** de `sequence`, no máximo
  /// [limit], cada uma com a entrada interna do selo (vizinho da cadeia lido
  /// do banco) e o papel/matrícula do autor.
  Future<List<AdminAuditRow>> readUpTo(
    AdminAuditFilter filter, {
    required int headSequence,
    required int limit,
  });

  /// **Uma** transação: insere [registro] em `audit_exports` e apensa
  /// [evento] à cadeia (`OrmAuditTrail.recordInTransaction`). Se qualquer um
  /// falhar, nenhum dos dois fica.
  Future<void> commitExport(AuditExport registro, AuditEvent evento);
}

/// Falha da exportação depois de autorizada e validada (leitura, geração ou
/// gravação). A mensagem é **fixa**: nunca carrega texto do banco, do CSV
/// nem do erro original.
class AuditExportFailedException implements Exception {
  const AuditExportFailedException();

  static const mensagem =
      'Não foi possível gerar a exportação da auditoria. Tente novamente.';

  String get message => mensagem;

  @override
  String toString() => 'AuditExportFailedException: $mensagem';
}

/// `admin.exportAuditLogs` (#45, Task 10; D5–D8, Review Focus 6 e 8).
///
/// Ordem fixa (D8):
/// 1. **Só `admin`** ([AdminScopeResolver.requireAdmin], recurso
///    [recursoDaRecusa], `actionType: export`): coordenador, ACS e paciente
///    recebem `AlertPermissionException` com `denied` auditado, e **nenhuma**
///    linha é lida.
/// 2. **Filtro com período obrigatório** (`from` **e** `to`) e as regras de
///    `AdminReadService.validarFiltroDeAuditoria` (janela ≤ 366 dias, `from <
///    to`): recusa `AdminInvalidRequestException` **sem** auditar (entrada
///    inválida não é acesso).
/// 3. `headSequence` capturado **antes** de tudo; o recorte é
///    `sequence <= head`. O evento `export` entra depois, com `sequence`
///    maior: o arquivo nunca descreve a si mesmo e não há recursão (Review
///    Focus 6). Exportar de novo inclui o `export` anterior — esperado.
/// 4. `COUNT` limitado; acima de [maxRows] ⇒ `refused_limit` auditado
///    (`record`, fail-closed) e `AdminInvalidRequestException`.
/// 5. Lê as linhas e os selos, gera o CSV ([AuditCsv]) e o SHA-256 em memória
///    (sem arquivo em disco), e pega o estado da cadeia ([chainState], cache
///    de 60 s da verificação global).
/// 6. **Uma transação:** `audit_exports` + `export/admin_audit_logs/success`
///    com `resourceId` = id da exportação ([AuditExportStore.commitExport]).
///    Só depois do commit o CSV é devolvido.
///
/// Falha em 3–6 ⇒ `failed` gravado com `record` **fora** de transação (sem
/// conteúdo) e [AuditExportFailedException] de mensagem fixa. Se nem o
/// `failed` grava, a mesma exceção genérica sobe: nada sai.
///
/// **Resposta perdida depois do commit (Review Focus 8):** se a conexão cai
/// entre o commit e a entrega, fica um evento `export` sem arquivo entregue.
/// Aceito: erra para o lado de auditar a mais; não há o que desfazer.
///
/// Os campos da cadeia nunca saem daqui: o CSV é montado só a partir de
/// [AuditExportRow] (D6), e o selo vem do mesmo [AuditRowSealer] da tela.
class AuditExportService {
  AuditExportService({
    required this.store,
    required this.audit,
    required AuditChain auditChain,
    required Future<AuditIntegrityState> Function() chainState,
    this.onFailure,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _sealer = AuditRowSealer(auditChain),
       _chainState = chainState,
       _clock = clock ?? DateTime.now,
       _newId = newId ?? (() => const Uuid().v4());

  final AuditExportStore store;
  final AuditTrail audit;

  /// Recebe o erro original de uma falha (para log de servidor: só o tipo).
  /// Se ele próprio lançar, é engolido.
  final void Function(Object error)? onFailure;

  final AuditRowSealer _sealer;
  final Future<AuditIntegrityState> Function() _chainState;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Teto de linhas por arquivo (D5). Acima disso: estreitar os filtros.
  static const maxRows = 5000;

  /// Recurso das linhas de recusa e de falha (nenhuma exportação existe).
  static const recursoDaRecusa = 'admin_audit_export';

  /// Recurso da linha de sucesso (D7): o que foi exportado; o `resourceId` é
  /// o id em `audit_exports`.
  static const recursoExportado = 'admin_audit_logs';

  static const formato = 'csv';

  static const _periodoObrigatorio =
      'Filtro de auditoria inválido. A exportação exige início e fim do '
      'período.';
  static const _acimaDoTeto =
      'O recorte passa de $maxRows linhas. Estreite os filtros para exportar.';

  late final AdminScopeResolver _resolver = AdminScopeResolver(
    store: store,
    audit: audit,
  );

  Future<AdminAuditExport> export(
    AuthenticatedUser user,
    AdminAuditFilter? filter,
  ) async {
    await _resolver.requireAdmin(
      user,
      recurso: recursoDaRecusa,
      actionType: 'export',
    );
    final f = _validar(filter);

    final int head;
    final int total;
    try {
      head = await store.headSequence();
      total = await store.countUpTo(f, headSequence: head, cap: maxRows + 1);
    } catch (erro) {
      return _falhar(user, erro);
    }
    if (total > maxRows) {
      await _registrar(user, 'refused_limit');
      throw AdminInvalidRequestException(message: _acimaDoTeto);
    }

    final String csv;
    final String sha;
    final int? primeira;
    final int? ultima;
    final int quantidade;
    final AuditIntegrityState estado;
    try {
      final linhas = await store.readUpTo(
        f,
        headSequence: head,
        limit: maxRows,
      );
      final rows = [for (final l in linhas) _linhaDoCsv(l)];
      csv = AuditCsv.build(rows);
      sha = sha256.convert(utf8.encode(csv)).toString();
      quantidade = rows.length;
      primeira = rows.isEmpty ? null : rows.first.sequence;
      ultima = rows.isEmpty ? null : rows.last.sequence;
      estado = await _chainState();
    } catch (erro) {
      return _falhar(user, erro);
    }

    final agora = _clock().toUtc();
    final id = _newId();
    try {
      await store.commitExport(
        AuditExport(
          id: UuidValue.fromString(id),
          requestedBy: UuidValue.fromString(user.id),
          requestedAt: agora,
          filtersJson: _filtrosJson(f),
          format: formato,
          rowCount: quantidade,
          firstSequence: primeira,
          lastSequence: ultima,
          contentSha256: sha,
          chainState: estado.name,
        ),
        AuditEvent(
          userId: user.id,
          actionType: 'export',
          resourceType: recursoExportado,
          resourceId: id,
          result: 'success',
        ),
      );
    } catch (erro) {
      return _falhar(user, erro);
    }

    return AdminAuditExport(
      fileName: nomeDoArquivo(f.from!, f.to!),
      csv: csv,
      rowCount: quantidade,
      firstSequence: primeira,
      lastSequence: ultima,
      contentSha256: sha,
      chainState: estado,
      generatedAt: agora,
    );
  }

  /// `auditoria_<from>_<to>.csv`, UTC compacto (`20261001T000000Z`): só o
  /// período, nunca filtro de matrícula, busca ou outro dado pessoal.
  static String nomeDoArquivo(DateTime from, DateTime to) =>
      'auditoria_${_compacto(from)}_${_compacto(to)}.csv';

  static String _compacto(DateTime t) {
    final u = t.toUtc();
    String d2(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}${d2(u.month)}${d2(u.day)}'
        'T${d2(u.hour)}${d2(u.minute)}${d2(u.second)}Z';
  }

  AdminAuditFilter _validar(AdminAuditFilter? filter) {
    if (filter == null || filter.from == null || filter.to == null) {
      throw AdminInvalidRequestException(message: _periodoObrigatorio);
    }
    AdminReadService.validarFiltroDeAuditoria(filter);
    return filter;
  }

  /// Só os parâmetros do filtro (D7), sem o marcador de classe do protocolo;
  /// nunca linhas.
  static String _filtrosJson(AdminAuditFilter f) =>
      jsonEncode(f.toJson()..remove('__className__'));

  /// Linha do CSV (D6): `autor` é a matrícula (ACS/staff) ou o rótulo
  /// minimizado (`Paciente #A18F`); `rotulo_recurso` é `#` + 4 hex do
  /// `resourceId`, nunca o UUID; o selo é o do [AuditRowSealer].
  AuditExportRow _linhaDoCsv(AdminAuditRow l) {
    final campos = l.seal.row.fields;
    final papel = l.actorRole ?? 'desconhecido';
    final matricula = l.actorEnrollmentId;
    final autor = papel == 'patient' || matricula == null || matricula.isEmpty
        ? AdminLabels.user(role: papel, id: campos.userId)
        : matricula;
    final recurso = campos.resourceId;
    return AuditExportRow(
      sequence: campos.sequence,
      timestampUtc: l.entry.timestamp.toUtc(),
      autor: autor,
      papelAutor: papel,
      acao: l.entry.actionType,
      recurso: l.entry.resourceType,
      rotuloRecurso: recurso == null ? '' : AdminLabels.patient(recurso),
      resultado: l.entry.result,
      selo: _sealer.sealInput(l.seal).name,
    );
  }

  Future<void> _registrar(AuthenticatedUser user, String result) =>
      audit.record(
        AuditEvent(
          userId: user.id,
          actionType: 'export',
          resourceType: recursoDaRecusa,
          result: result,
        ),
      );

  /// `failed` com `record` (fail-closed, fora de transação) e a exceção
  /// genérica. Se a trilha também falhar, a exceção continua a genérica:
  /// nenhum texto do banco sobe, e nada é entregue.
  Future<Never> _falhar(AuthenticatedUser user, Object erro) async {
    try {
      onFailure?.call(erro);
    } catch (_) {
      // O log falhou; a recusa segue.
    }
    try {
      await _registrar(user, 'failed');
    } catch (_) {
      // Sem a linha `failed`, ainda assim nada sai.
    }
    throw const AuditExportFailedException();
  }
}
