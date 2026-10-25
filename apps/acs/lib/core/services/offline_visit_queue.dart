import 'dart:math';

import 'package:sinalacs_acs/core/telemetry/telemetry_recorder.dart';

enum SyncOutcomeKind {
  synced,
  conflict,
  empty,
  error,

  /// O servidor recusou em definitivo — ver [OfflineVisitRecord.rejectionReason].
  /// Ao contrário de [error], que é retentável, nada muda tentando de novo.
  rejected,
}

class SyncOutcome {
  const SyncOutcome({
    required this.kind,
    required this.processed,
    this.message,
  });

  final SyncOutcomeKind kind;
  final int processed;

  /// Motivo, já em português, quando [kind] é [SyncOutcomeKind.error] ou
  /// [SyncOutcomeKind.rejected].
  ///
  /// Sem isto a tela só conseguia dizer "não deu certo": a mensagem real do
  /// servidor (identificador inválido, sessão expirada) ficava presa aqui.
  final String? message;
}

/// Cópia da visita no servidor, guardada junto à visita local em conflito (#79).
///
/// Sem identificação do paciente: só o que o ACS precisa para comparar.
class VisitConflictSnapshot {
  const VisitConflictSnapshot({
    required this.version,
    required this.status,
    required this.notes,
    this.completedAt,
  });

  final int version;
  final String status;
  final String notes;
  final DateTime? completedAt;

  Map<String, Object?> toJson() => {
        'version': version,
        'status': status,
        'notes': notes,
        'completedAt': completedAt?.toUtc().toIso8601String(),
      };

  factory VisitConflictSnapshot.fromJson(Map<String, Object?> json) {
    final completedAt = json['completedAt'] as String?;
    return VisitConflictSnapshot(
      version: json['version']! as int,
      status: json['status']! as String,
      notes: json['notes']! as String,
      completedAt: completedAt == null ? null : DateTime.parse(completedAt),
    );
  }
}

/// UUID v4 com `Random.secure`: ids de visita (`localId`) e de eventos de
/// telemetria saem do mesmo gerador.
String newRandomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class OfflineVisitRecord {
  OfflineVisitRecord({
    required this.patientId,
    required this.risk,
    required this.status,
    this.outcome = '',
    this.notes = '',
    this.rejectionReason,
    String? localId,
    DateTime? createdAt,
    this.version = 1,
    this.conflictServerVersion,
    this.conflictServer,
  })  : localId = localId ?? newRandomUuid(),
        createdAt = createdAt ?? DateTime.now();

  /// UUID do paciente, exatamente como veio no alerta.
  ///
  /// Guardar o identificador e montar o rótulo na tela é o que mantém o disco
  /// sem texto legível sobre a pessoa (minimização, LGPD-RF01). Antes gravava-se
  /// `'Paciente ' + 8 dos 32 dígitos hex`, o que era pior nos dois sentidos: um
  /// rótulo legível no aparelho e um UUID irrecuperável — `visits.sync` recusa
  /// qualquer coisa que não seja UUID, então a visita nunca poderia subir.
  final String patientId;

  final String risk;
  final String status;
  final String outcome;

  /// Observações de campo registradas na visita antes da sincronização.
  final String notes;

  /// Identificador gerado no dispositivo.
  ///
  /// É a chave de deduplicação da sincronização: a tabela `visits` do servidor
  /// tem índice único em `localId`, então reenviar a mesma visita depois de uma
  /// falha de rede atualiza a linha em vez de criar uma segunda.
  final String localId;

  final DateTime createdAt;

  /// Versão conhecida no servidor, para detecção de conflito.
  final int version;

  /// Não-nulo significa: o servidor recusou esta visita EM DEFINITIVO — o
  /// texto é o motivo, em português, vindo de `VisitSyncResult.message`.
  ///
  /// Nunca cita nome de paciente nem microárea alheia — a mesma mensagem que
  /// já chegava do servidor para o caso retentável (`error`), agora também
  /// para o terminal (`rejected`). Uma vez definido, nada nesta classe o
  /// desfaz: sair do estado de recusa é uma decisão explícita do ACS
  /// (`OfflineVisitQueue.discardRejected`), não um efeito colateral de
  /// `copyWith`.
  final String? rejectionReason;

  /// Versão que o servidor tinha quando respondeu `conflict` (#79). Não-nulo =
  /// a visita está em conflito e fica no aparelho até o ACS decidir.
  final int? conflictServerVersion;

  /// Cópia da visita no servidor, vista no conflito, para o ACS comparar.
  final VisitConflictSnapshot? conflictServer;

  bool get inConflict => conflictServerVersion != null;

  OfflineVisitRecord copyWith({
    String? patientId,
    String? risk,
    String? status,
    String? outcome,
    String? notes,
    String? rejectionReason,
    String? localId,
    DateTime? createdAt,
    int? version,
    int? conflictServerVersion,
    VisitConflictSnapshot? conflictServer,
  }) {
    return OfflineVisitRecord(
      patientId: patientId ?? this.patientId,
      risk: risk ?? this.risk,
      status: status ?? this.status,
      outcome: outcome ?? this.outcome,
      notes: notes ?? this.notes,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      localId: localId ?? this.localId,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
      conflictServerVersion: conflictServerVersion ?? this.conflictServerVersion,
      conflictServer: conflictServer ?? this.conflictServer,
    );
  }
}

/// Resultado da sincronização de uma visita, do ponto de vista do servidor.
class VisitSyncOutcome {
  const VisitSyncOutcome({
    required this.localId,
    required this.status,
    this.serverVersion,
    this.message,
    this.serverSnapshot,
  });

  final String localId;

  /// `synced`, `conflict`, `error` ou `rejected`, como devolvido por
  /// `visits.sync` (`SyncStatus.name`).
  final String status;

  final int? serverVersion;

  /// Motivo devolvido pelo servidor quando [status] é `error` ou `rejected`.
  ///
  /// Ele já vinha no contrato (`VisitSyncResult.message`) e era descartado no
  /// caminho até aqui, o que deixava um `patientId` inválido parecendo silêncio.
  final String? message;

  /// Cópia da visita no servidor quando [status] é `conflict` (#79). Pode
  /// faltar (caminho sem autor, servidor antigo): o conflito vale assim mesmo,
  /// a tela só não tem o que comparar.
  final VisitConflictSnapshot? serverSnapshot;
}

/// Quem leva as visitas pendentes ao servidor.
///
/// Abstração no mesmo espírito de `AlertPublisher`/`AlertStore` no backend:
/// mantém a fila testável sem rede.
abstract class VisitSynchronizer {
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits);
}

/// Quem leva ao servidor a decisão "manter a minha versão" de uma visita em
/// conflito (#79, `visits.resolveConflict`).
///
/// Separado de [VisitSynchronizer] de propósito: o envio diferido não resolve
/// conflito (não há dono presente para decidir, D6), então não implementa isto.
abstract interface class VisitConflictResolver {
  /// Envia [visit] (já com a edição do ACS) com compare-and-set sobre
  /// [expectedServerVersion], a versão do servidor que o ACS viu.
  Future<VisitSyncOutcome> resolve(OfflineVisitRecord visit, {required int expectedServerVersion});
}

/// D7: o servidor disse `conflict` sem dizer a versão. Sem versão de
/// referência não há como resolver depois, então é erro retentável.
const conflictWithoutVersionMessage = 'O servidor indicou conflito sem informar a versão.';

/// `resolveKeepLocal` numa fila sem [VisitConflictResolver].
const conflictResolverMissingMessage = 'A resolução de conflitos não está configurada neste aplicativo.';

/// Onde as visitas ficam enquanto não sincronizam.
///
/// Desde que existe [OfflineVisitRecord.rejectionReason], o que [save] recebe
/// não é mais só "a fila" — é a fila MAIS as visitas recusadas em definitivo
/// que o ACS ainda não descartou (ver `OfflineVisitQueue._persist`). Sem isso,
/// uma visita recusada sumiria do disco no instante em que saísse de
/// `_pending`, silenciosamente — o oposto do que a recusa terminal pede.
abstract class VisitStore {
  Future<List<OfflineVisitRecord>> load();

  Future<void> save(List<OfflineVisitRecord> visits);
}

/// Armazenamento em memória. Padrão quando nenhum é fornecido.
class InMemoryVisitStore implements VisitStore {
  List<OfflineVisitRecord> _visits = <OfflineVisitRecord>[];

  @override
  Future<List<OfflineVisitRecord>> load() async => List.of(_visits);

  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    _visits = List.of(visits);
  }
}

/// Fábrica de armazenamento por dono. [VisitStore] continua sendo load/save,
/// mas agora SEMPRE de um único dono (id do ACS).
abstract interface class VisitStorage {
  VisitStore forOwner(String ownerId);

  /// Quarentena (D2): as visitas legadas, sem dono.
  LegacyVisitStore get legacy;

  /// Quantas visitas (pendentes e recusadas) cada dono tem no aparelho. Só a
  /// contagem — nenhum conteúdo de visita sai daqui. Não inclui a quarentena.
  /// Usado pelo envio diferido para achar donos sem token e para dizer quanto
  /// ainda não subiu.
  Future<Map<String, int>> countsByOwner();

  /// "Limpar este aparelho" (D9): apaga os dados do app neste aparelho — as
  /// visitas (que, se existirem, não foram enviadas), o cursor do pull e o
  /// cache da microárea — numa transação. **Recusa** com [WipeBlocked], sem
  /// apagar nada, se houver QUALQUER visita no aparelho, de qualquer dono ou
  /// da quarentena: tudo o que está em `offline_visits` ainda não subiu.
  Future<void> wipeAllData();

  /// Troca de chave por evento (CRIPTO-APP-CACHE): apaga o banco inteiro e a
  /// chave que o cifrava; a próxima abertura recomeça com chave nova. É
  /// **incondicional** (não confere visitas): quem chama recusa antes, como
  /// [wipeAllData] faz com [WipeBlocked].
  Future<void> destroyAll();
}

/// "Limpar este aparelho" recusado: ainda há [unsent] visitas não enviadas.
/// Só a contagem — nenhum conteúdo de visita.
class WipeBlocked implements Exception {
  const WipeBlocked(this.unsent);

  final int unsent;

  @override
  String toString() => 'WipeBlocked: $unsent visita(s) ainda não enviada(s)';
}

/// Quarentena (D2): as linhas com `owner IS NULL`. Nenhum dono as enxerga.
abstract interface class LegacyVisitStore {
  Future<List<OfflineVisitRecord>> load();

  /// Remove só estes `localId`s legados (depois do 200 do servidor).
  Future<void> remove(Iterable<String> localIds);
}

/// Lançada quando um `localId` não pode ser gravado: ou ele já pertence a
/// outro dono (ou à quarentena), ou aparece repetido na própria lista. `local_id`
/// é chave primária global: a visita alheia NUNCA é sobrescrita nem apagada, e a
/// gravação inteira é desfeita (tudo ou nada).
class VisitLocalIdConflict implements Exception {
  VisitLocalIdConflict(this.localId, {this.repeatedInList = false});

  final String localId;

  /// true quando o `localId` se repete dentro do mesmo `save`.
  final bool repeatedInList;

  @override
  String toString() => repeatedInList
      ? 'VisitLocalIdConflict: localId $localId repetido na mesma gravação'
      : 'VisitLocalIdConflict: localId $localId já pertence a outro dono';
}

/// Valida o id de dono: vazio ou só espaços é erro de programação (sem dono, a
/// visita cairia na quarentena ou numa visão compartilhada).
String requireOwnerId(String ownerId) {
  if (ownerId.trim().isEmpty) {
    throw ArgumentError.value(ownerId, 'ownerId', 'não pode ser vazio');
  }
  return ownerId;
}

/// Falha com [VisitLocalIdConflict] se [visits] repete algum `localId`.
void ensureNoRepeatedLocalIds(List<OfflineVisitRecord> visits) {
  final seen = <String>{};
  for (final visit in visits) {
    if (!seen.add(visit.localId)) {
      throw VisitLocalIdConflict(visit.localId, repeatedInList: true);
    }
  }
}

/// [VisitStorage] em memória: uma visão por dono sobre um registro único, com a
/// mesma unicidade global de `localId` do SQLCipher.
class InMemoryVisitStorage implements VisitStorage {
  InMemoryVisitStorage({Iterable<OfflineVisitRecord> legacyVisits = const []})
      : _legacy = _InMemoryLegacyVisitStore(legacyVisits);

  final Map<String, List<OfflineVisitRecord>> _byOwner = {};
  final _InMemoryLegacyVisitStore _legacy;
  final Map<String, VisitStore> _views = {};

  @override
  VisitStore forOwner(String ownerId) => _views.putIfAbsent(
        requireOwnerId(ownerId),
        () => _InMemoryOwnerVisitStore(this, ownerId),
      );

  @override
  LegacyVisitStore get legacy => _legacy;

  @override
  Future<Map<String, int>> countsByOwner() async => {
        for (final entry in _byOwner.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.length,
      };

  /// Não há cursor nem cache em memória: só confere e esvazia as visitas.
  @override
  Future<void> wipeAllData() async {
    final unsent = _byOwner.values.fold<int>(0, (total, visits) => total + visits.length) +
        _legacy._visits.length;
    if (unsent > 0) throw WipeBlocked(unsent);
    _byOwner.clear();
  }

  /// Sem arquivo nem chave: esvazia a memória.
  @override
  Future<void> destroyAll() async {
    _byOwner.clear();
    _legacy._visits.clear();
  }
}

class _InMemoryOwnerVisitStore implements VisitStore {
  _InMemoryOwnerVisitStore(this._storage, this._owner);

  final InMemoryVisitStorage _storage;
  final String _owner;

  @override
  Future<List<OfflineVisitRecord>> load() async =>
      List.of(_storage._byOwner[_owner] ?? const <OfflineVisitRecord>[]);

  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    ensureNoRepeatedLocalIds(visits);
    final taken = <String>{
      for (final entry in _storage._byOwner.entries)
        if (entry.key != _owner) ...entry.value.map((v) => v.localId),
      ..._storage._legacy._visits.map((v) => v.localId),
    };
    for (final visit in visits) {
      if (taken.contains(visit.localId)) {
        throw VisitLocalIdConflict(visit.localId);
      }
    }
    _storage._byOwner[_owner] = List.of(visits);
  }
}

class _InMemoryLegacyVisitStore implements LegacyVisitStore {
  _InMemoryLegacyVisitStore(Iterable<OfflineVisitRecord> visits)
      : _visits = List.of(visits);

  final List<OfflineVisitRecord> _visits;

  @override
  Future<List<OfflineVisitRecord>> load() async => List.of(_visits);

  @override
  Future<void> remove(Iterable<String> localIds) async {
    final ids = localIds.toSet();
    _visits.removeWhere((visit) => ids.contains(visit.localId));
  }
}

/// Fila offline-first de visitas domiciliares.
///
/// Preserva a semântica da `SyncFsm` do backend
/// (`idle → localWrite → queued → syncing → {synced|conflict|error|rejected}`):
/// uma falha de rede não perde o lote; uma visita em conflito (#79, D3) SAI da
/// retentativa — reenviá-la só devolveria o mesmo conflito — e fica no
/// aparelho, gravada com a cópia do servidor, até o ACS decidir
/// ([resolveKeepLocal]/[resolveKeepServer]); uma recusa definitiva
/// (`rejected`) também sai da retentativa e fica visível até o ACS
/// descartá-la — diferente de `error`, que continua pendente e retenta.
/// Nenhum dos dois some do disco sozinho.
class OfflineVisitQueue {
  OfflineVisitQueue({VisitStore? store, this.synchronizer, this.conflictResolver, this.telemetry})
      : _store = store ?? InMemoryVisitStore();

  final VisitStore _store;

  /// `null` mantém o comportamento local: a fila enfileira, mas não envia.
  final VisitSynchronizer? synchronizer;

  /// `null`: os conflitos ficam guardados, mas "Manter a minha" devolve erro.
  final VisitConflictResolver? conflictResolver;

  /// Eventos do PRD §1.3 (#83): `visit_registered` no [add], `sync_attempt`
  /// e `sync_result` em volta do envio. `null` desliga, sem mudar mais nada.
  /// O gravador nunca lança; resolver conflito não emite (fora do §1.3).
  final TelemetryRecorder? telemetry;

  final List<OfflineVisitRecord> _pending = <OfflineVisitRecord>[];
  final List<OfflineVisitRecord> _synced = <OfflineVisitRecord>[];
  final List<OfflineVisitRecord> _conflicts = <OfflineVisitRecord>[];
  final List<OfflineVisitRecord> _rejected = <OfflineVisitRecord>[];

  bool _restored = false;
  bool _persistenceFailed = false;
  bool _sealed = false;

  /// Limpeza remota (#81): a partir daqui a fila nunca mais grava no disco —
  /// nem pelo fim de um envio que já estava em voo, que recriaria o banco
  /// apagado (com chave nova) com as visitas que a coordenação mandou apagar.
  /// Registrar lança; enviar e resolver não fazem nada. Irreversível: o app
  /// descarta a fila selada e monta outra depois do próximo login.
  void seal() => _sealed = true;

  bool get isSealed => _sealed;

  /// `true` quando o armazenamento do dispositivo não está aceitando gravação.
  ///
  /// A fila continua funcionando em memória — travar o registro de visita em
  /// campo seria pior —, mas quem consome precisa avisar a pessoa: uma fila que
  /// parou de persistir em silêncio perde o trabalho do dia ao fechar o app.
  /// Manter em RAM não viola o INV-04, que proíbe *persistir* em texto plano.
  bool get persistenceFailed => _persistenceFailed;

  int get pendingCount => _pending.length;
  int get syncedCount => _synced.length;
  int get conflictCount => _conflicts.length;
  int get rejectedCount => _rejected.length;

  List<OfflineVisitRecord> get pendingVisits => List.unmodifiable(_pending);
  List<OfflineVisitRecord> get syncedVisits => List.unmodifiable(_synced);
  List<OfflineVisitRecord> get conflictVisits => List.unmodifiable(_conflicts);
  List<OfflineVisitRecord> get rejectedVisits => List.unmodifiable(_rejected);

  /// Recarrega o que ficou gravado de execuções anteriores.
  ///
  /// Sem isso, fechar o app perde a fila — o oposto de offline-first. O que
  /// veio do disco é separado entre pendente, em conflito e recusado pelos
  /// próprios campos do registro ([OfflineVisitRecord.inConflict] primeiro,
  /// depois [OfflineVisitRecord.rejectionReason]) — não há uma segunda tabela.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;

    try {
      final stored = await _store.load();
      _pending.clear();
      _conflicts.clear();
      _rejected.clear();
      for (final visit in stored) {
        if (visit.inConflict) {
          _conflicts.add(visit);
        } else if (visit.rejectionReason != null) {
          _rejected.add(visit);
        } else {
          _pending.add(visit);
        }
      }
      _persistenceFailed = false;
    } catch (_) {
      // Banco indisponível (chave perdida, plataforma sem SQLCipher). A fila
      // segue em memória e o sinalizador acende.
      _persistenceFailed = true;
    }
  }

  /// [alertId]: a visita nasceu de um alerta; só vai para a telemetria.
  Future<void> add(OfflineVisitRecord record, {String? alertId}) async {
    if (_sealed) throw StateError('Fila de visitas encerrada pela limpeza do aparelho.');
    _pending.add(record);
    await _persist();
    // Depois da gravação: o evento nunca chega antes da visita estar no disco.
    // Sem gravador, nem o `await`: o fluxo fica idêntico ao de antes.
    final recorder = telemetry;
    if (recorder != null) await recorder.visitRegistered(visit: record, alertId: alertId);
  }

  /// Descarta as visitas recusadas em definitivo.
  ///
  /// Ação explícita do ACS, nunca automática: a recusa terminal já tirou a
  /// visita da retentativa, mas apagar o registro do trabalho de campo sem
  /// confirmação apagaria evidência de uma visita feita que nunca chegou ao
  /// servidor.
  Future<void> discardRejected() async {
    if (_sealed || _rejected.isEmpty) return;
    _rejected.clear();
    await _persist();
  }

  /// "Manter a do servidor" (#79, D4): apaga a cópia deste aparelho da visita
  /// em conflito. Só local — o servidor não é chamado, nada muda lá. A tela
  /// pede confirmação antes. `localId` desconhecido não faz nada.
  Future<void> resolveKeepServer(String localId) async {
    if (_sealed) return;
    final before = _conflicts.length;
    _conflicts.removeWhere((visit) => visit.localId == localId);
    if (_conflicts.length == before) return;
    await _persist();
  }

  Future<SyncOutcome>? _resolving;

  /// "Manter a minha versão" / "Editar e enviar" (#79, D5): aplica [outcome] e
  /// [notes] editados (nulos = mantém os do aparelho) e envia a visita por
  /// `visits.resolveConflict`, com a versão do servidor que o ACS viu.
  ///
  /// `synced` → sai do aparelho; `conflict` → fica, com a cópia nova do
  /// servidor e a edição preservada; `rejected` → vai para as recusadas; erro
  /// de rede → fica em conflito como estava, mas com a edição gravada.
  ///
  /// Espera um [sync] em voo antes de ler o registro, e as resoluções correm
  /// uma de cada vez.
  Future<SyncOutcome> resolveKeepLocal(String localId, {String? outcome, String? notes}) {
    if (_sealed) return Future.value(_sealedOutcome);
    final previous = _resolving;
    late final Future<SyncOutcome> run;
    run = () async {
      if (previous != null) await previous.then((_) {}, onError: (_) {});
      final syncing = _syncing;
      if (syncing != null) await syncing.then((_) {}, onError: (_) {});
      if (_sealed) return _sealedOutcome;
      return _resolveKeepLocalNow(localId, outcome: outcome, notes: notes);
    }()
        .whenComplete(() {
      if (identical(_resolving, run)) _resolving = null;
    });
    return _resolving = run;
  }

  Future<SyncOutcome> _resolveKeepLocalNow(String localId, {String? outcome, String? notes}) async {
    final index = _conflicts.indexWhere((visit) => visit.localId == localId);
    if (index < 0) {
      return const SyncOutcome(
        kind: SyncOutcomeKind.error,
        processed: 0,
        message: 'Esta visita não está mais em conflito neste aparelho.',
      );
    }
    final edited = _conflicts[index].copyWith(outcome: outcome, notes: notes);
    // A edição é gravada ANTES da rede: se a chamada falhar, o que o ACS
    // digitou continua no aparelho.
    _conflicts[index] = edited;
    await _persist();

    final resolver = conflictResolver;
    if (resolver == null) {
      return const SyncOutcome(
        kind: SyncOutcomeKind.error,
        processed: 1,
        message: conflictResolverMissingMessage,
      );
    }

    final VisitSyncOutcome result;
    try {
      result = await resolver.resolve(edited, expectedServerVersion: edited.conflictServerVersion!);
    } catch (error) {
      // Mesmo contrato do `sync`: em produção é uma `BackendFailure`, cujo
      // `toString()` já é a frase em português.
      return SyncOutcome(kind: SyncOutcomeKind.error, processed: 1, message: '$error');
    }

    // O registro pode ter saído durante a chamada (ex.: "Manter a do
    // servidor" em outra tela): nada a recolocar.
    final current = _conflicts.indexWhere((visit) => visit.localId == localId);
    switch (result.status) {
      case 'synced':
        // Descartada durante a chamada: o servidor gravou, mas o ACS já tirou
        // a cópia do aparelho — contá-la como enviada daqui a ressuscitaria,
        // como no ramo `rejected`.
        if (current < 0) {
          return const SyncOutcome(kind: SyncOutcomeKind.synced, processed: 1);
        }
        _conflicts.removeAt(current);
        _synced.add(edited.copyWith(
          status: 'SINCRONIZADO',
          version: result.serverVersion ?? edited.version,
        ));
        await _persist();
        return const SyncOutcome(kind: SyncOutcomeKind.synced, processed: 1);
      case 'conflict':
        final serverVersion = result.serverVersion;
        if (serverVersion == null) {
          return const SyncOutcome(
            kind: SyncOutcomeKind.error,
            processed: 1,
            message: conflictWithoutVersionMessage,
          );
        }
        // copyWith não zera, mas sobrescreve: versão e cópia novas, conteúdo
        // editado preservado. Sem cópia nova, a anterior não vale mais.
        final replaced = OfflineVisitRecord(
          patientId: edited.patientId,
          risk: edited.risk,
          status: edited.status,
          outcome: edited.outcome,
          notes: edited.notes,
          rejectionReason: edited.rejectionReason,
          localId: edited.localId,
          createdAt: edited.createdAt,
          version: edited.version,
          conflictServerVersion: serverVersion,
          conflictServer: result.serverSnapshot,
        );
        if (current >= 0) {
          _conflicts[current] = replaced;
          await _persist();
        }
        return const SyncOutcome(kind: SyncOutcomeKind.conflict, processed: 1);
      case 'rejected':
        final reason = result.message ?? 'O servidor recusou esta visita em definitivo.';
        // Descartada durante a chamada ("Manter a do servidor"): o ACS já
        // decidiu apagar a cópia do aparelho; recolocá-la nas recusadas a
        // ressuscitaria.
        if (current < 0) {
          return SyncOutcome(kind: SyncOutcomeKind.rejected, processed: 1, message: reason);
        }
        _conflicts.removeAt(current);
        // Sai do conflito para as recusadas: o registro novo não carrega a
        // versão de conflito, senão `restore` o poria de volta em conflito.
        _rejected.add(OfflineVisitRecord(
          patientId: edited.patientId,
          risk: edited.risk,
          status: edited.status,
          outcome: edited.outcome,
          notes: edited.notes,
          rejectionReason: reason,
          localId: edited.localId,
          createdAt: edited.createdAt,
          version: edited.version,
        ));
        await _persist();
        return SyncOutcome(kind: SyncOutcomeKind.rejected, processed: 1, message: reason);
      default:
        return SyncOutcome(
          kind: SyncOutcomeKind.error,
          processed: 1,
          message: result.message ?? 'O servidor não confirmou a visita.',
        );
    }
  }

  /// Grava o estado corrente, sem deixar a falha derrubar quem chamou.
  ///
  /// Persiste pendentes, em conflito E recusadas: as duas últimas já saíram
  /// da retentativa, e sair do disco junto as faria desaparecer do aparelho,
  /// silenciosamente — antes mesmo de o ACS decidir o que fazer com elas.
  static const _sealedOutcome = SyncOutcome(
    kind: SyncOutcomeKind.error,
    processed: 0,
    message: 'Fila de visitas encerrada pela limpeza do aparelho.',
  );

  Future<void> _persist() async {
    if (_sealed) return;
    try {
      await _store.save([..._pending, ..._conflicts, ..._rejected]);
      _persistenceFailed = false;
    } catch (_) {
      _persistenceFailed = true;
    }
  }

  Future<SyncOutcome>? _syncing;

  /// `true` enquanto um [sync] ou um [resolveKeepLocal] está em voo (a
  /// visita pode estar no servidor). Quem descarta filas (o app, ao trocar de
  /// dono) não pode descartar esta: uma segunda fila sobre o mesmo dono seria
  /// regravada às cegas por esta quando o envio terminasse.
  bool get isSyncing => _syncing != null || _resolving != null;

  /// Envia o que está pendente. **Single-flight**: chamar de novo com um envio
  /// em voo devolve o resultado DESSE envio (o lote nunca sai duas vezes, nem
  /// é contado duas vezes); o que foi registrado depois da captura do lote
  /// fica para o próximo `sync()`. Visitas em conflito não fazem parte do
  /// lote (D3): reenviá-las só devolveria o mesmo conflito.
  Future<SyncOutcome> sync() {
    final inFlight = _syncing;
    if (inFlight != null) return inFlight;
    if (_sealed) return Future.value(_sealedOutcome);
    late final Future<SyncOutcome> run;
    run = _syncOnce().whenComplete(() {
      if (identical(_syncing, run)) _syncing = null;
    });
    return _syncing = run;
  }

  Future<SyncOutcome> _syncOnce() async {
    if (_pending.isEmpty) {
      return const SyncOutcome(kind: SyncOutcomeKind.empty, processed: 0);
    }

    final batch = List<OfflineVisitRecord>.from(_pending);

    final sender = synchronizer;
    if (sender == null) {
      // Sem sincronizador configurado a fila permanece local; nada é
      // declarado sincronizado, porque nada saiu do dispositivo. Em produção
      // este ramo não é alcançável: `buildVisitQueue` sempre liga um.
      return SyncOutcome(
        kind: SyncOutcomeKind.error,
        processed: batch.length,
        message: 'A sincronização não está configurada neste aplicativo.',
      );
    }

    // Com `await`: o `sync_attempt` fica no disco antes do envio, e um app
    // morto no meio deixa a tentativa órfã (contada como interrompida).
    final recorder = telemetry;
    final attemptId =
        recorder == null ? null : await recorder.syncAttempt(recordsCount: batch.length);
    final stopwatch = Stopwatch()..start();

    final List<VisitSyncOutcome> outcomes;
    try {
      outcomes = await sender.push(batch);
    } catch (error) {
      if (recorder != null) {
        await recorder.syncResult(
          attemptEventId: attemptId,
          successCount: 0,
          failureCount: batch.length,
          conflictCount: 0,
          rejectedCount: 0,
          outcome: SyncOutcomeKind.error.name,
          transportError: true,
          duration: stopwatch.elapsed,
        );
      }
      // O lote continua pendente: perder a visita por falha de rede seria
      // exatamente o que a fila existe para evitar.
      //
      // `'$error'` é a mensagem que a tela mostra. Em produção isto é sempre
      // uma `BackendFailure`, cujo `toString()` já é a frase em português — o
      // `BackendClient` não deixa escapar outro tipo. A fila não importa
      // `backend_client.dart` de propósito: ela não deve conhecer a rede.
      return SyncOutcome(
        kind: SyncOutcomeKind.error,
        processed: batch.length,
        message: '$error',
      );
    }

    if (recorder == null) return _applyOutcomes(batch, outcomes);

    late final ({int synced, int errors, int conflicts, int rejected}) counts;
    final result = await _applyOutcomes(batch, outcomes, onCounts: (c) => counts = c);
    // Com a fila selada no meio do voo isto ainda grava: é telemetria, não
    // visita, e `_persist` já não tocou no disco das visitas.
    await recorder.syncResult(
      attemptEventId: attemptId,
      successCount: counts.synced,
      failureCount: counts.errors,
      conflictCount: counts.conflicts,
      rejectedCount: counts.rejected,
      outcome: result.kind.name,
      transportError: false,
      duration: stopwatch.elapsed,
    );
    return result;
  }

  /// [onCounts] recebe as contagens apuradas do lote (telemetria, #83), antes
  /// da precedência reduzi-las a um só [SyncOutcome].
  Future<SyncOutcome> _applyOutcomes(
    List<OfflineVisitRecord> batch,
    List<VisitSyncOutcome> outcomes, {
    void Function(({int synced, int errors, int conflicts, int rejected}) counts)? onCounts,
  }) async {
    final byLocalId = {for (final outcome in outcomes) outcome.localId: outcome};

    var conflicts = 0;
    var synced = 0;
    var errors = 0;
    var rejected = 0;
    String? firstError;
    String? firstRejection;
    final stillPending = <OfflineVisitRecord>[];

    for (final visit in batch) {
      final outcome = byLocalId[visit.localId];
      switch (outcome?.status) {
        case 'synced':
          _synced.add(visit.copyWith(
            status: 'SINCRONIZADO',
            version: outcome?.serverVersion ?? visit.version,
          ));
          synced++;
        case 'conflict':
          final serverVersion = outcome?.serverVersion;
          if (serverVersion == null) {
            // D7: sem a versão do servidor não há referência para resolver
            // depois. Fica pendente e retenta, como um `error`.
            stillPending.add(visit);
            errors++;
            firstError ??= conflictWithoutVersionMessage;
            break;
          }
          // D3: sai da retentativa e espera a decisão do ACS, gravada com a
          // cópia do servidor. Substitui um conflito anterior da mesma visita
          // em vez de duplicar.
          _conflicts
            ..removeWhere((c) => c.localId == visit.localId)
            ..add(visit.copyWith(
              conflictServerVersion: serverVersion,
              conflictServer: outcome?.serverSnapshot,
            ));
          conflicts++;
        case 'rejected':
          // Terminal: SAI da retentativa, mas fica visível até o ACS
          // descartar — não some, e não volta para `stillPending`.
          final reason = outcome?.message ??
              'O servidor recusou esta visita em definitivo.';
          _rejected.add(visit.copyWith(rejectionReason: reason));
          rejected++;
          firstRejection ??= reason;
        case 'error':
          // O servidor recusou ESTA visita. Continua pendente — descartar
          // perderia o registro feito em campo —, mas precisa ser contada:
          // antes caía no `default` e a chamada devolvia `synced`, então uma
          // visita recusada ficava presa na fila para sempre, em silêncio.
          stillPending.add(visit);
          errors++;
          firstError ??= outcome?.message;
        default:
          // Sem resposta para esta visita — o lote pode ter voltado incompleto.
          stillPending.add(visit);
          errors++;
      }
    }

    // `add()` pode ter entrado com o lote no servidor: quem não estava no lote
    // capturado continua pendente, depois dos que voltaram para a fila. Refazer
    // `_pending` só com o lote apagava essa visita da memória e, no `_persist`
    // abaixo, do disco.
    final inBatch = {for (final visit in batch) visit.localId};
    final arrived = [for (final visit in _pending) if (!inBatch.contains(visit.localId)) visit];
    _pending
      ..clear()
      ..addAll(stillPending)
      ..addAll(arrived);
    await _persist();
    onCounts?.call((synced: synced, errors: errors, conflicts: conflicts, rejected: rejected));

    // Precedência: recusado > conflito > erro > sincronizado. Recusado é
    // trabalho de campo que NUNCA vai ao servidor — o que mais precisa
    // chegar aos olhos do ACS. Conflito exige decisão de quem registrou; erro,
    // no máximo, uma nova tentativa.
    if (rejected > 0) {
      return SyncOutcome(
        kind: SyncOutcomeKind.rejected,
        processed: rejected,
        message: firstRejection,
      );
    }
    if (conflicts > 0) {
      return SyncOutcome(kind: SyncOutcomeKind.conflict, processed: conflicts);
    }
    if (errors > 0) {
      return SyncOutcome(
        kind: SyncOutcomeKind.error,
        processed: errors,
        message: firstError ?? 'O servidor não confirmou $errors visita(s).',
      );
    }
    return SyncOutcome(kind: SyncOutcomeKind.synced, processed: synced);
  }
}
