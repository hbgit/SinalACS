import 'dart:async';

import 'package:sinalacs_server/src/application/admin/admin_scope.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_checkpoint_store.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// O que a verificação global precisa saber do mundo além da cadeia: a UBS do
/// coordenador ([AdminScopeStore]) e se uma linha de `audit_logs` pertence a
/// uma UBS — pelo **autor** da linha, a mesma regra de escopo de
/// `admin.auditLogs`.
abstract interface class AuditChainScopeStore implements AdminScopeStore {
  /// `true` se a linha de [sequence] existe e o autor dela tem microárea na
  /// UBS [ubsId]. Linha inexistente, autor sem microárea (staff) ou de outra
  /// UBS: `false`.
  Future<bool> auditRowInUbs(int sequence, String ubsId);
}

/// Uma verificação global concluída: o resultado do verificador e o instante
/// em que terminou. Interna; nunca serializa.
class AuditChainSnapshot {
  const AuditChainSnapshot({required this.verification, required this.at});

  final AuditChainVerification verification;
  final DateTime at;
}

/// Estado do **processo** da verificação global (#45, D9): o `Future` em
/// andamento (single-flight) e o último resultado (cache de
/// [AuditChainStatusService.cacheTtl]). Vive no `AlertRuntime`, porque os
/// endpoints são construídos por requisição; o backend é de instância única
/// (PRD), então um por processo basta.
class AuditChainStatusCache {
  Future<AuditChainSnapshot>? inFlight;
  AuditChainSnapshot? last;

  void reset() {
    inFlight = null;
    last = null;
  }
}

/// `admin.verifyAuditChain` (#45, Task 6; decisões D3 e D9).
///
/// 1. **Papel e escopo primeiro** ([AdminScopeResolver], recurso
///    `admin_audit_chain`): `acs`/`patient`/coordenador sem UBS são recusados
///    com `denied` auditado, sem ler a cadeia.
/// 2. **Auditoria antes de verificar:** `read`/`admin_audit_chain`/`success`
///    com `record` (fail-closed) — também quando a resposta sai do cache.
/// 3. **Single-flight e cache:** uma verificação em andamento é compartilhada
///    por todas as chamadas do processo; a concluída vale por [cacheTtl] no
///    [AuditChainStatusCache]. Relógio injetável; relógio que volta no tempo
///    invalida o cache. A verificação compartilhada usa o reader da requisição
///    que a iniciou (e que a espera, então a sessão dela segue aberta).
/// 4. **Nada além de cadeia íntegra e não vazia vira `verified`** ([stateOf]):
///    quebra ⇒ `broken`; banco, prazo de leitura, `Error` ou segredo ausente ⇒
///    `unavailable`; cadeia vazia ou orçamento esgotado ⇒ `inconclusive`.
///    Nenhuma falha vira 500 genérico: tudo que a leitura lança — `Exception`
///    **ou** `Error` — é `unavailable/databaseError`.
/// 5. **Projeção por papel (D9, Review Focus 7):** o administrador recebe o
///    status completo; o coordenador recebe o estado (um `broken` continua
///    `broken`: o painel não pode dizer íntegra), mas `firstBrokenSequence` e
///    `reasonCode` da quebra só se a linha quebrada for de um autor da UBS
///    dele, e nunca `checkedRows`/`headSequence` (volume do sistema).
///
/// O texto livre `reason` do verificador não sai daqui: o cliente recebe só
/// o `reasonCode` fechado. Segredo trocado aparece como `broken` já na
/// `sequence` 1 (Review Focus 3): "falha", não necessariamente adulteração.
///
/// 6. **Checkpoint de cauda (Task 7, D4):** o verificador sozinho não vê
///    linhas apagadas do **fim** da cadeia (a cadeia mais curta continua
///    contígua e encadeada). Depois de uma cadeia `ok`, [_ancorarCauda] lê os
///    [checkpointWindow] checkpoints mais recentes e confere a assinatura de
///    cada um com a MESMA [AuditChain] da escrita
///    ([AuditChain.checkpointMatches]). O mais recente **válido** é a âncora:
///    se a linha daquela `sequence` não existe mais, ou existe com outro
///    `entryHash` (cauda apagada e a aplicação regravou por cima), o
///    resultado é `broken/tailTruncated`. Checkpoint com assinatura inválida
///    é **ignorado** como âncora e **sinalizado**: sem truncamento provado
///    pela âncora válida, o resultado é `inconclusive/checkpointInvalid`,
///    nunca `verified` — e a linha não é apagada (é evidência). Falha ao ler
///    checkpoints é `unavailable/databaseError`: sem âncora conferida, não há
///    `verified`.
///
///    Só um resultado final `verified` grava checkpoint novo
///    (`headSequence`, `headEntryHash`), e só se avança: a âncora lida já em
///    `sequence >= head` não regrava, e o store recusa atomicamente qualquer
///    `sequence` menor ou igual à maior gravada (corrida de duas
///    verificações no mesmo `sequence` termina sem erro). Gravar é melhor
///    esforço: falha (Exception ou Error) **não** muda o `verified` — a
///    cadeia foi conferida — nem derruba a resposta, mas também não some:
///    vai para [onCheckpointWriteFailure] (log de servidor, sem hash).
///
///    **Limites conhecidos (registrados em Pendências do plano):** restaurar
///    o banco inteiro de um backup mais antigo — cadeia **e** checkpoints
///    juntos — passa como íntegro, porque os dois voltam coerentes entre si;
///    e quem tem escrita no banco e apaga a cauda também pode apagar os
///    checkpoints (sem forjar um novo, que exige o segredo). O checkpoint
///    reduz o risco do truncamento, não o elimina.
class AuditChainStatusService {
  AuditChainStatusService({
    required this.store,
    required this.audit,
    required AuditChainReader reader,
    required String secret,
    required AuditChainCheckpointStore checkpoints,
    required this.cache,
    this.onCheckpointWriteFailure,
    this.budget = defaultBudget,
    this.readTimeout = defaultReadTimeout,
    DateTime Function()? clock,
  }) : _reader = reader,
       _secret = secret,
       _checkpoints = checkpoints,
       _clock = clock ?? DateTime.now;

  final AuditChainScopeStore store;
  final AuditTrail audit;
  final AuditChainStatusCache cache;

  /// Orçamento da verificação (D9), conferido entre lotes pelo verificador.
  final Duration budget;

  /// Prazo de cada leitura de lote: uma consulta que não volta vira
  /// `unavailable/databaseError`, não uma requisição presa.
  final Duration readTimeout;

  /// Chamado quando gravar o checkpoint falha. Recebe o erro; nunca o
  /// hash. Se ele próprio lançar, é engolido: a resposta não cai por log.
  final void Function(Object error)? onCheckpointWriteFailure;

  final AuditChainReader _reader;
  final String _secret;
  final AuditChainCheckpointStore _checkpoints;
  final DateTime Function() _clock;

  /// Quantos checkpoints mais recentes são conferidos a cada verificação.
  /// Um inválido entre eles já basta para `inconclusive`; o válido mais novo
  /// entre eles é a âncora.
  static const checkpointWindow = 100;

  static const defaultBudget = Duration(seconds: 10);
  static const defaultReadTimeout = Duration(seconds: 10);
  static const cacheTtl = Duration(seconds: 60);
  static const recurso = 'admin_audit_chain';

  late final AdminScopeResolver _resolver = AdminScopeResolver(
    store: store,
    audit: audit,
  );

  Future<AdminAuditChainStatus> verify(AuthenticatedUser user) async {
    final escopo = await _resolver.resolve(user, recurso: recurso);
    await audit.record(
      AuditEvent(
        userId: user.id,
        actionType: 'read',
        resourceType: recurso,
        result: 'success',
      ),
    );
    final retrato = await _resultadoGlobal();
    return _projetar(retrato, escopo);
  }

  /// Só o estado global (mesmo single-flight e cache de 60 s de [verify]),
  /// **sem** papel, escopo nem linha de auditoria própria: para quem já
  /// autorizou e audita o ato maior — a exportação (#45, Task 10), que grava o
  /// estado em `audit_exports.chainState`. Nunca lança (ver
  /// [_verificarCadeia]).
  Future<AuditIntegrityState> currentState() async =>
      stateOf((await _resultadoGlobal()).verification);

  /// Estado de integridade de um resultado do verificador (D3). Público e
  /// puro para o teste de propriedade: só `ok` com pelo menos uma linha é
  /// `verified`.
  static AuditIntegrityState stateOf(AuditChainVerification v) {
    if (v.ok) {
      return v.checked > 0
          ? AuditIntegrityState.verified
          : AuditIntegrityState.inconclusive;
    }
    return switch (v.reasonCode) {
      AuditChainReason.hashMismatch ||
      AuditChainReason.linkBroken ||
      AuditChainReason.sequenceGap ||
      AuditChainReason.tailTruncated => AuditIntegrityState.broken,
      AuditChainReason.timeBudget ||
      AuditChainReason.checkpointInvalid => AuditIntegrityState.inconclusive,
      AuditChainReason.databaseError ||
      AuditChainReason.secretUnavailable ||
      null => AuditIntegrityState.unavailable,
    };
  }

  Future<AuditChainSnapshot> _resultadoGlobal() {
    final agora = _clock().toUtc();
    final ultimo = cache.last;
    if (ultimo != null) {
      final idade = agora.difference(ultimo.at);
      if (!idade.isNegative && idade < cacheTtl) return Future.value(ultimo);
    }
    final andamento = cache.inFlight;
    if (andamento != null) return andamento;

    final novo = _verificarCadeia().then((retrato) {
      cache.last = retrato;
      return retrato;
    });
    cache.inFlight = novo;
    // Limpa só se ainda for o mesmo (um reset de teste pode ter trocado).
    novo.whenComplete(() {
      if (identical(cache.inFlight, novo)) cache.inFlight = null;
    });
    return novo;
  }

  /// Nunca lança: qualquer falha da leitura — `Exception` ou `Error` — é
  /// `databaseError`. A âncora de cauda (Task 7) entra depois do
  /// verificador; a gravação do checkpoint, depois do estado final.
  Future<AuditChainSnapshot> _verificarCadeia() async {
    final reader = _ReaderComPrazo(_reader, readTimeout);
    AuditChainVerification resultado;
    int? maiorCheckpoint;
    try {
      resultado = await AuditChainVerifier(
        reader: reader,
        secret: _secret,
      ).verify(budget: budget, clock: _clock);
      if (resultado.ok) {
        final ancorado = await _ancorarCauda(resultado, reader);
        resultado = ancorado.resultado;
        maiorCheckpoint = ancorado.maiorValido;
      }
    } catch (_) {
      resultado = const AuditChainVerification(
        ok: false,
        checked: 0,
        reasonCode: AuditChainReason.databaseError,
      );
    }
    if (stateOf(resultado) == AuditIntegrityState.verified) {
      await _gravarCheckpoint(resultado, maiorCheckpoint);
    }
    return AuditChainSnapshot(verification: resultado, at: _clock().toUtc());
  }

  /// Confere a cadeia `ok` [v] contra o checkpoint válido mais recente.
  /// Lança em falha de leitura (o chamador transforma em `databaseError`).
  Future<({AuditChainVerification resultado, int? maiorValido})>
  _ancorarCauda(AuditChainVerification v, AuditChainReader reader) async {
    final chain = AuditChain(secret: _secret);
    final lidos = await _checkpoints
        .latest(limit: checkpointWindow)
        .timeout(readTimeout);

    AuditChainCheckpointRecord? ancora;
    var invalido = false;
    for (final c in lidos) {
      if (chain.checkpointMatches(c.sequence, c.entryHash, c.signature)) {
        // Lidos em ordem decrescente: o primeiro válido é o mais recente.
        if (ancora == null || c.sequence > ancora.sequence) ancora = c;
      } else {
        invalido = true;
      }
    }

    if (ancora != null) {
      // `entryAt`, não `checked`: se a cadeia cresceu enquanto era lida, a
      // linha do checkpoint pode estar além do que o verificador viu — e
      // existir com o mesmo hash não é truncamento.
      final linha = await reader.entryAt(ancora.sequence);
      if (linha == null || linha.entryHash != ancora.entryHash) {
        return (
          resultado: AuditChainVerification(
            ok: false,
            checked: v.checked,
            brokenAtSequence: ancora.sequence,
            reason: linha == null
                ? 'a cadeia termina antes do último checkpoint '
                      '(cauda apagada)'
                : 'entryHash diverge do checkpoint '
                      '(cauda apagada e regravada)',
            reasonCode: AuditChainReason.tailTruncated,
          ),
          maiorValido: ancora.sequence,
        );
      }
    }

    if (invalido) {
      return (
        resultado: AuditChainVerification(
          ok: false,
          checked: v.checked,
          reason:
              'checkpoint com assinatura inválida ignorado '
              '(adulteração ou segredo trocado)',
          reasonCode: AuditChainReason.checkpointInvalid,
        ),
        maiorValido: ancora?.sequence,
      );
    }
    return (resultado: v, maiorValido: ancora?.sequence);
  }

  /// Melhor esforço: nunca lança e nunca muda o resultado.
  Future<void> _gravarCheckpoint(
    AuditChainVerification v,
    int? maiorExistente,
  ) async {
    final hash = v.headEntryHash;
    if (hash == null || v.checked < 1) return;
    if (maiorExistente != null && maiorExistente >= v.checked) return;
    try {
      await _checkpoints
          .advanceTo(
            AuditChainCheckpointRecord(
              sequence: v.checked,
              entryHash: hash,
              signature: AuditChain(
                secret: _secret,
              ).computeCheckpointSignature(v.checked, hash),
            ),
          )
          .timeout(readTimeout);
    } catch (erro) {
      try {
        onCheckpointWriteFailure?.call(erro);
      } catch (_) {
        // O log também falhou; a resposta segue.
      }
    }
  }

  Future<AdminAuditChainStatus> _projetar(
    AuditChainSnapshot retrato,
    AdminScope escopo,
  ) async {
    final v = retrato.verification;
    final estado = stateOf(v);
    final quebrada = estado == AuditIntegrityState.broken;
    final ubs = escopo.ubsId;

    if (ubs == null) {
      return AdminAuditChainStatus(
        state: estado,
        checkedRows: v.checked,
        headSequence: estado == AuditIntegrityState.verified ? v.checked : null,
        firstBrokenSequence: quebrada ? v.brokenAtSequence : null,
        brokenInScope: quebrada ? true : null,
        reasonCode: v.ok ? null : v.reasonCode,
        verifiedAt: retrato.at,
      );
    }

    if (!quebrada) {
      return AdminAuditChainStatus(
        state: estado,
        reasonCode: v.ok ? null : v.reasonCode,
        verifiedAt: retrato.at,
      );
    }

    bool? noEscopo;
    final seq = v.brokenAtSequence;
    if (seq == null) {
      noEscopo = false;
    } else {
      try {
        noEscopo = await store.auditRowInUbs(seq, ubs);
      } catch (_) {
        // Pertencimento desconhecido: continua `broken`, sem sequence.
        noEscopo = null;
      }
    }
    return AdminAuditChainStatus(
      state: estado,
      firstBrokenSequence: noEscopo == true ? seq : null,
      brokenInScope: noEscopo,
      reasonCode: noEscopo == true ? v.reasonCode : null,
      verifiedAt: retrato.at,
    );
  }
}

/// Aplica [_prazo] a cada leitura de lote: estourar lança
/// `TimeoutException`, que o verificador já trata como `databaseError`.
class _ReaderComPrazo implements AuditChainReader {
  _ReaderComPrazo(this._interno, this._prazo);

  final AuditChainReader _interno;
  final Duration _prazo;

  @override
  Future<List<AuditChainEntry>> readBatch({
    required int afterSequence,
    required int limit,
  }) => _interno
      .readBatch(afterSequence: afterSequence, limit: limit)
      .timeout(_prazo);

  @override
  Future<AuditChainEntry?> entryAt(int sequence) =>
      _interno.entryAt(sequence).timeout(_prazo);
}
