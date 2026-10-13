import 'package:sinalacs_server/src/application/admin/admin_scope.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

// `AdminScope` e `AdminScopeStore` nasceram aqui e mudaram de casa na #43; o
// `export` mantém o alcance de quem já importava este arquivo.
export 'package:sinalacs_server/src/application/admin/admin_scope.dart';

/// O que o pulso da monitoração (#44, D5) lê além dos indicadores: só uma
/// contagem e um instante, nunca um alerta.
typedef AlertsPulseCounts = ({int overdueRed, DateTime? maxChangedAt});

/// Leitura do backoffice. Interface à parte do ORM, no espírito de
/// `AlertStore`: o serviço e seus testes não conhecem SQL.
abstract interface class AdminReadStore implements AdminScopeStore {
  /// Contagens por risco e TMRAV no escopo. O TMRAV olha os 30 dias anteriores
  /// a [now]; sem alerta vermelho reconhecido na janela, `tmravSeconds` é nulo.
  Future<AdminIndicators> indicators(AdminScope scope, {required DateTime now});

  Future<List<AdminMicroArea>> microAreas(AdminScope scope);

  /// Pulso da monitoração (#44, D5), no escopo: `overdueRed` conta os alertas
  /// com a MESMA regra de `AdminAlert.overdue` (vermelho, pendente, sem
  /// escalonamento, estritamente além de [threshold] em [now]);
  /// `maxChangedAt` é o maior instante de mudança (disparo, ACK ou
  /// escalonamento) entre os alertas do escopo, nulo se não há alerta.
  Future<AlertsPulseCounts> pulse(
    AdminScope scope, {
    required DateTime now,
    required Duration threshold,
  });

  /// Vencidos primeiro, depois mais recentes (`overdue` desc, `triggeredAt`
  /// desc, `id` desc: ordem estável). Assim nenhum vermelho vencido fica além
  /// da primeira página (#44). `nextOffset` nulo = fim da lista.
  ///
  /// [now] é o relógio do **servidor**: `AdminAlert.overdue` é calculado com ele
  /// (#44), nunca com o do aparelho. Escalonar não tira o alerta da lista nem do
  /// filtro `pending` (D3).
  Future<AdminAlertPage> alerts(
    AdminScope scope, {
    String? microAreaId,
    AlertStatus? status,
    required int limit,
    required int offset,
    required DateTime now,
  });

  /// Mais recentes primeiro, por keyset (`sequence` menor que [beforeSequence]).
  ///
  /// O escopo não filtra só o recurso auditado: filtra o **autor** da linha — o
  /// coordenador só vê linhas de atores com microárea na UBS dele; linhas de
  /// staff (sem microárea) não aparecem para ele.
  ///
  /// [filter] (#45) já chega validado pelo serviço e só **restringe** o
  /// escopo, nunca o alarga: nulo = sem filtro.
  Future<AdminAuditPage> auditLogs(
    AdminScope scope, {
    AdminAuditFilter? filter,
    required int limit,
    int? beforeSequence,
  });
}

/// Regras de leitura do backoffice (issue #40). Papel e escopo vêm do
/// [AdminScopeResolver] — a regra única do backoffice (issue #43): só
/// `coordinator` e `admin` leem; `acs` e `patient` são recusados mesmo com token
/// válido, e a recusa é auditada. O administrador vê o sistema; o coordenador, a
/// UBS de `staff_accounts.ubsId` — coordenador sem UBS é recusado (fail-closed),
/// em **todos** os métodos.
///
/// 1. **Auditoria antes do dado:** cada leitura grava uma linha `read` e só então
///    consulta o store. `record` (não `recordSafely`): se a linha não grava, a
///    exceção sobe e nenhum dado sai.
/// 2. **Paginação:** `limit` de 1 a 100, `offset` não negativo; fora disso,
///    [AdminInvalidRequestException] (não é erro de permissão).
///
/// A auditoria de logs segue o mesmo escopo, com a junção `users` ×
/// `micro_areas` que a #40 havia adiado: o coordenador lê as linhas dos atores
/// da UBS dele; as de staff (sem microárea) só o administrador lê.
class AdminReadService {
  AdminReadService({
    required this.store,
    required this.audit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AdminReadStore store;
  final AuditTrail audit;
  final DateTime Function() _clock;

  /// A regra única de papel/escopo, sobre o [store] (que também é a porta da
  /// UBS do coordenador).
  late final AdminScopeResolver _resolver = AdminScopeResolver(
    store: store,
    audit: audit,
  );

  static const maxLimit = 100;
  static const _paginacaoInvalida = 'Parâmetro de paginação inválido.';

  Future<AdminIndicators> indicators(AuthenticatedUser user) async {
    final escopo = await _resolver.resolve(user, recurso: 'admin_indicators');
    await _auditar(user, 'admin_indicators', 'success');
    return store.indicators(escopo, now: _clock().toUtc());
  }

  Future<List<AdminMicroArea>> microAreas(AuthenticatedUser user) async {
    final escopo = await _resolver.resolve(user, recurso: 'admin_micro_areas');
    await _auditar(user, 'admin_micro_areas', 'success');
    return store.microAreas(escopo);
  }

  Future<AdminAlertPage> alerts(
    AuthenticatedUser user, {
    String? microAreaId,
    AlertStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final escopo = await _resolver.resolve(user, recurso: 'admin_alerts');
    _validarPagina(limit, offset);
    await _auditar(user, 'admin_alerts', 'success');
    return store.alerts(
      escopo,
      microAreaId: microAreaId,
      status: status,
      limit: limit,
      offset: offset,
      now: _clock().toUtc(),
    );
  }

  /// Trilha de auditoria no escopo, com [filter] opcional (#45). Papel e
  /// escopo primeiro (a recusa é auditada `denied`); depois paginação e
  /// filtro — entrada inválida não é acesso, então não grava `success`.
  Future<AdminAuditPage> auditLogs(
    AuthenticatedUser user, {
    AdminAuditFilter? filter,
    int limit = 50,
    int? beforeSequence,
  }) async {
    const recurso = 'admin_audit_logs';
    final escopo = await _resolver.resolve(user, recurso: recurso);
    _validarPagina(limit, 0);
    validarFiltroDeAuditoria(filter);
    await _auditar(user, recurso, 'success');
    return store.auditLogs(
      escopo,
      filter: filter,
      limit: limit,
      beforeSequence: beforeSequence,
    );
  }

  /// Ações que existem em `audit_logs.actionType` (D1).
  static const acoesDeAuditoria = {'read', 'write', 'login', 'export'};

  /// Janela máxima entre `from` e `to` (D1).
  static const janelaMaximaDoFiltro = Duration(days: 366);

  static final _rotulo = RegExp(r'^[a-z_]{1,64}$');
  static const _filtroInvalido = 'Filtro de auditoria inválido.';

  /// Regras do [AdminAuditFilter] (D1/D2), puras e públicas para a exportação
  /// (Task 10) usar a mesma. Lança [AdminInvalidRequestException] com uma
  /// mensagem sobre a própria entrada; nunca ecoa o valor recebido.
  static void validarFiltroDeAuditoria(AdminAuditFilter? f) {
    if (f == null) return;
    void recusar(String detalhe) => throw AdminInvalidRequestException(
      message: '$_filtroInvalido $detalhe',
    );

    final matricula = f.actorEnrollmentId;
    if (matricula != null && (matricula.isEmpty || matricula.length > 32)) {
      recusar('A matrícula deve ter de 1 a 32 caracteres.');
    }
    final acao = f.actionType;
    if (acao != null && !acoesDeAuditoria.contains(acao)) {
      recusar('Ação desconhecida.');
    }
    final tipo = f.resourceType;
    if (tipo != null && !_rotulo.hasMatch(tipo)) {
      recusar('Tipo de recurso inválido.');
    }
    final resultado = f.result;
    if (resultado != null && !_rotulo.hasMatch(resultado)) {
      recusar('Resultado inválido.');
    }
    final de = f.from;
    final ate = f.to;
    if (de != null && ate != null) {
      if (!de.isBefore(ate)) {
        recusar('O início do período deve ser anterior ao fim.');
      }
      if (ate.difference(de) > janelaMaximaDoFiltro) {
        recusar('O período é de no máximo 366 dias.');
      }
    }
    final busca = f.search;
    if (busca != null && (busca.length < 2 || busca.length > 64)) {
      recusar('A busca deve ter de 2 a 64 caracteres.');
    }
  }

  void _validarPagina(int limit, int offset) {
    if (limit < 1 || limit > maxLimit || offset < 0) {
      throw AdminInvalidRequestException(message: _paginacaoInvalida);
    }
  }

  Future<void> _auditar(
    AuthenticatedUser user,
    String recurso,
    String result,
  ) => audit.record(
    AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: recurso,
      result: result,
    ),
  );
}
