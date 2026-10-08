import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Persistência do atendimento de pedidos do titular. Interface à parte do ORM,
/// no espírito de `AdminReadStore`: o serviço e seus testes não conhecem SQL.
abstract interface class DataSubjectCaseStore {
  /// UBS do coordenador (`staff_accounts.ubsId`), ou `null` se não houver.
  Future<String?> ubsOf(String staffId);

  /// Prazo mais próximo primeiro (`dueAt` crescente, `id` desempata): os
  /// vencidos sobem ao topo. `nextOffset` nulo = fim da lista. Nunca decifra
  /// `details` nem a nota.
  Future<AdminDataSubjectRequestPage> list(
    AdminScope scope, {
    DataSubjectRequestStatus? status,
    required int limit,
    required int offset,
    required DateTime now,
  });

  /// `null` = não existe OU fora do escopo (indistinguíveis de propósito).
  Future<AdminDataSubjectRequestDetail?> find(
    AdminScope scope,
    String id, {
    required DateTime now,
  });

  /// Transação: trava o pedido (`pg_advisory_xact_lock`), confere [from], grava
  /// status/nota/decidedBy, executa a anonimização se [anonymize] e grava a
  /// auditoria via [audit]. Devolve `false` se o estado atual não está em
  /// [from] (corrida perdida).
  Future<bool> decide(
    AdminScope scope,
    String id, {
    required Set<DataSubjectRequestStatus> from,
    required DataSubjectRequestStatus to,
    required String? resolution,
    required String decidedBy,
    required bool anonymize,
    required AuditEvent audit,
    required DateTime now,
  });
}

/// Regras do atendimento de pedidos do titular no backoffice (issue #42).
///
/// 1. **Papel e escopo:** como em [AdminReadService] — só `coordinator` e
///    `admin`; o coordenador enxerga a UBS de `staff_accounts.ubsId` e, sem UBS,
///    é recusado (fail-closed) em todos os métodos. Recusas são auditadas.
/// 2. **Não encontrado:** pedido inexistente e pedido fora do escopo geram a
///    mesma exceção, com a mesma mensagem.
/// 3. **Auditoria antes do dado:** a leitura grava `read` com `record` (não
///    `recordSafely`) antes de consultar o store. A auditoria das decisões viaja
///    dentro de [DataSubjectCaseStore.decide], na mesma transação.
/// 4. **Transições:** `open → inReview → completed|rejected` e
///    `open → completed|rejected`; `completed` e `rejected` são finais.
/// 5. **Nota/motivo:** de 3 a 500 caracteres após `trim`; nunca vai para
///    mensagem de exceção nem para evento de auditoria.
/// 6. **Anonimização:** só ao atender (`completed`) um pedido de exclusão.
class DataSubjectCaseService {
  DataSubjectCaseService({
    required this.store,
    required this.audit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DataSubjectCaseStore store;
  final AuditTrail audit;
  final DateTime Function() _clock;

  static const maxLimit = 100;
  static const notaMin = 3;
  static const notaMax = 500;
  static const _recurso = 'admin_data_subject_requests';
  static const _recursoDecisao = 'data_subject_request';
  static const _negado = 'acesso restrito ao backoffice';
  static const _paginacaoInvalida = 'Parâmetro de paginação inválido.';
  static const _naoEncontrado = 'Pedido não encontrado.';
  static const _transicaoInvalida =
      'O pedido não está num estado que permita esta ação.';
  static const _notaInvalida =
      'O texto deve ter de $notaMin a $notaMax caracteres.';
  static const _notaObrigatoria =
      'Pedido de correção exige uma nota de resposta.';

  Future<AdminDataSubjectRequestPage> list(
    AuthenticatedUser user, {
    DataSubjectRequestStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final escopo = await _escopo(user);
    if (limit < 1 || limit > maxLimit || offset < 0) {
      throw AdminInvalidRequestException(message: _paginacaoInvalida);
    }
    await _auditarLeitura(user, null);
    final agora = _clock().toUtc();
    final pagina = await store.list(
      escopo,
      status: status,
      limit: limit,
      offset: offset,
      now: agora,
    );
    return AdminDataSubjectRequestPage(
      items: [
        for (final i in pagina.items)
          AdminDataSubjectRequest(
            id: i.id,
            type: i.type,
            status: i.status,
            createdAt: i.createdAt,
            dueAt: i.dueAt,
            overdue: _vencido(i.status, i.dueAt, agora),
            patientLabel: i.patientLabel,
          ),
      ],
      nextOffset: pagina.nextOffset,
    );
  }

  Future<AdminDataSubjectRequestDetail> get(
    AuthenticatedUser user,
    String id,
  ) async {
    final escopo = await _escopo(user);
    await _auditarLeitura(user, id);
    return _achar(escopo, id, _clock().toUtc());
  }

  Future<void> startReview(AuthenticatedUser user, String id) async {
    final escopo = await _escopo(user);
    final agora = _clock().toUtc();
    final pedido = await _achar(escopo, id, agora);
    _exigirEstado(pedido, const {DataSubjectRequestStatus.open});
    await _decidir(
      user,
      escopo,
      pedido,
      from: const {DataSubjectRequestStatus.open},
      to: DataSubjectRequestStatus.inReview,
      resolution: null,
      anonymize: false,
      agora: agora,
    );
  }

  /// [note] é obrigatória no pedido de correção; na exclusão é opcional, mas
  /// quando vem precisa passar na mesma validação.
  Future<void> complete(
    AuthenticatedUser user,
    String id, {
    String? note,
  }) async {
    final escopo = await _escopo(user);
    final agora = _clock().toUtc();
    final pedido = await _achar(escopo, id, agora);
    _exigirEstado(pedido, _abertos);
    final correcao = pedido.type == DataSubjectRequestType.correction;
    if (correcao && note == null) {
      throw AdminInvalidRequestException(message: _notaObrigatoria);
    }
    final texto = note == null ? null : _validarNota(note);
    await _decidir(
      user,
      escopo,
      pedido,
      from: _abertos,
      to: DataSubjectRequestStatus.completed,
      resolution: texto,
      anonymize: pedido.type == DataSubjectRequestType.deletion,
      agora: agora,
    );
  }

  Future<void> reject(
    AuthenticatedUser user,
    String id, {
    required String reason,
  }) async {
    final escopo = await _escopo(user);
    final agora = _clock().toUtc();
    final pedido = await _achar(escopo, id, agora);
    _exigirEstado(pedido, _abertos);
    final motivo = _validarNota(reason);
    await _decidir(
      user,
      escopo,
      pedido,
      from: _abertos,
      to: DataSubjectRequestStatus.rejected,
      resolution: motivo,
      anonymize: false,
      agora: agora,
    );
  }

  static const _abertos = {
    DataSubjectRequestStatus.open,
    DataSubjectRequestStatus.inReview,
  };

  static bool _vencido(
    DataSubjectRequestStatus status,
    DateTime dueAt,
    DateTime agora,
  ) => _abertos.contains(status) && agora.isAfter(dueAt);

  Future<AdminDataSubjectRequestDetail> _achar(
    AdminScope escopo,
    String id,
    DateTime agora,
  ) async {
    final d = await store.find(escopo, id, now: agora);
    if (d == null) throw AdminInvalidRequestException(message: _naoEncontrado);
    return AdminDataSubjectRequestDetail(
      id: d.id,
      type: d.type,
      status: d.status,
      createdAt: d.createdAt,
      dueAt: d.dueAt,
      overdue: _vencido(d.status, d.dueAt, agora),
      patientLabel: d.patientLabel,
      details: d.details,
      resolution: d.resolution,
      decidedAt: d.decidedAt,
    );
  }

  void _exigirEstado(
    AdminDataSubjectRequestDetail pedido,
    Set<DataSubjectRequestStatus> permitidos,
  ) {
    if (!permitidos.contains(pedido.status)) {
      throw AdminInvalidRequestException(message: _transicaoInvalida);
    }
  }

  Future<void> _decidir(
    AuthenticatedUser user,
    AdminScope escopo,
    AdminDataSubjectRequestDetail pedido, {
    required Set<DataSubjectRequestStatus> from,
    required DataSubjectRequestStatus to,
    required String? resolution,
    required bool anonymize,
    required DateTime agora,
  }) async {
    final ok = await store.decide(
      escopo,
      pedido.id,
      from: from,
      to: to,
      resolution: resolution,
      decidedBy: user.id,
      anonymize: anonymize,
      audit: AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: _recursoDecisao,
        resourceId: pedido.id,
        result: switch (to) {
          DataSubjectRequestStatus.inReview => 'in_review',
          DataSubjectRequestStatus.completed => 'completed',
          DataSubjectRequestStatus.rejected => 'rejected',
          DataSubjectRequestStatus.open => 'open',
        },
      ),
      now: agora,
    );
    // Corrida perdida: outro analista decidiu entre a leitura e o lock.
    if (!ok) throw AdminInvalidRequestException(message: _transicaoInvalida);
  }

  String _validarNota(String texto) {
    final t = texto.trim();
    if (t.length < notaMin || t.length > notaMax) {
      throw AdminInvalidRequestException(message: _notaInvalida);
    }
    return t;
  }

  Future<AdminScope> _escopo(AuthenticatedUser user) async {
    if (!Authorization.staffRoles.contains(user.role)) {
      await _auditarNegado(user);
      throw AlertPermissionException(message: _negado);
    }
    if (user.role == UserRole.admin) return const AdminScope.system();
    final ubs = await store.ubsOf(user.id);
    if (ubs == null) {
      await _auditarNegado(user);
      throw AlertPermissionException(message: _negado);
    }
    return AdminScope.ubs(ubs);
  }

  Future<void> _auditarNegado(AuthenticatedUser user) => audit.record(
    AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: _recurso,
      result: 'denied',
    ),
  );

  Future<void> _auditarLeitura(AuthenticatedUser user, String? id) =>
      audit.record(
        AuditEvent(
          userId: user.id,
          actionType: 'read',
          resourceType: _recurso,
          resourceId: id,
          result: 'success',
        ),
      );
}
