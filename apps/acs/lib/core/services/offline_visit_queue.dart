import 'dart:math';

enum SyncOutcomeKind {
  synced,
  conflict,
  empty,
  error,
}

class SyncOutcome {
  const SyncOutcome({
    required this.kind,
    required this.processed,
    this.message,
  });

  final SyncOutcomeKind kind;
  final int processed;

  /// Motivo, já em português, quando [kind] é [SyncOutcomeKind.error].
  ///
  /// Sem isto a tela só conseguia dizer "não deu certo": a mensagem real do
  /// servidor (identificador inválido, sessão expirada) ficava presa aqui.
  final String? message;
}

class OfflineVisitRecord {
  OfflineVisitRecord({
    required this.patientId,
    required this.risk,
    required this.status,
    this.outcome = '',
    String? localId,
    DateTime? createdAt,
    this.version = 1,
  })  : localId = localId ?? _newLocalId(),
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

  /// Identificador gerado no dispositivo.
  ///
  /// É a chave de deduplicação da sincronização: a tabela `visits` do servidor
  /// tem índice único em `localId`, então reenviar a mesma visita depois de uma
  /// falha de rede atualiza a linha em vez de criar uma segunda.
  final String localId;

  final DateTime createdAt;

  /// Versão conhecida no servidor, para detecção de conflito.
  final int version;

  OfflineVisitRecord copyWith({
    String? patientId,
    String? risk,
    String? status,
    String? outcome,
    String? localId,
    DateTime? createdAt,
    int? version,
  }) {
    return OfflineVisitRecord(
      patientId: patientId ?? this.patientId,
      risk: risk ?? this.risk,
      status: status ?? this.status,
      outcome: outcome ?? this.outcome,
      localId: localId ?? this.localId,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
    );
  }

  static String _newLocalId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// Resultado da sincronização de uma visita, do ponto de vista do servidor.
class VisitSyncOutcome {
  const VisitSyncOutcome({
    required this.localId,
    required this.status,
    this.serverVersion,
    this.message,
  });

  final String localId;

  /// `synced`, `conflict` ou `error`, como devolvido por `visits.sync`.
  final String status;

  final int? serverVersion;

  /// Motivo devolvido pelo servidor quando [status] é `error`.
  ///
  /// Ele já vinha no contrato (`VisitSyncResult.message`) e era descartado no
  /// caminho até aqui, o que deixava um `patientId` inválido parecendo silêncio.
  final String? message;
}

/// Quem leva as visitas pendentes ao servidor.
///
/// Abstração no mesmo espírito de `AlertPublisher`/`AlertStore` no backend:
/// mantém a fila testável sem rede.
abstract class VisitSynchronizer {
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits);
}

/// Onde as visitas ficam enquanto não sincronizam.
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

/// Fila offline-first de visitas domiciliares.
///
/// Preserva a semântica da `SyncFsm` do backend
/// (`idle → localWrite → queued → syncing → {synced|conflict|error}`): uma
/// visita em conflito **volta para a fila** em vez de ser descartada, e uma
/// falha de rede não perde o lote.
class OfflineVisitQueue {
  OfflineVisitQueue({VisitStore? store, this.synchronizer})
      : _store = store ?? InMemoryVisitStore();

  final VisitStore _store;

  /// `null` mantém o comportamento local: a fila enfileira, mas não envia.
  final VisitSynchronizer? synchronizer;

  final List<OfflineVisitRecord> _pending = <OfflineVisitRecord>[];
  final List<OfflineVisitRecord> _synced = <OfflineVisitRecord>[];
  final List<OfflineVisitRecord> _conflicts = <OfflineVisitRecord>[];

  bool _restored = false;
  bool _persistenceFailed = false;

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

  List<OfflineVisitRecord> get pendingVisits => List.unmodifiable(_pending);
  List<OfflineVisitRecord> get syncedVisits => List.unmodifiable(_synced);
  List<OfflineVisitRecord> get conflictVisits => List.unmodifiable(_conflicts);

  /// Recarrega o que ficou gravado de execuções anteriores.
  ///
  /// Sem isso, fechar o app perde a fila — o oposto de offline-first.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;

    try {
      final stored = await _store.load();
      _pending
        ..clear()
        ..addAll(stored);
      _persistenceFailed = false;
    } catch (_) {
      // Banco indisponível (chave perdida, plataforma sem SQLCipher). A fila
      // segue em memória e o sinalizador acende.
      _persistenceFailed = true;
    }
  }

  Future<void> add(OfflineVisitRecord record) async {
    _pending.add(record);
    await _persist();
  }

  /// Grava o estado corrente, sem deixar a falha derrubar quem chamou.
  Future<void> _persist() async {
    try {
      await _store.save(_pending);
      _persistenceFailed = false;
    } catch (_) {
      _persistenceFailed = true;
    }
  }

  Future<SyncOutcome> sync({bool forceConflict = false}) async {
    if (_pending.isEmpty) {
      return const SyncOutcome(kind: SyncOutcomeKind.empty, processed: 0);
    }

    final batch = List<OfflineVisitRecord>.from(_pending);

    // Gancho de teste preservado do comportamento anterior.
    if (forceConflict) {
      return _applyOutcomes(batch, [
        VisitSyncOutcome(localId: batch.first.localId, status: 'conflict'),
        for (final visit in batch.skip(1))
          VisitSyncOutcome(localId: visit.localId, status: 'synced'),
      ]);
    }

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

    final List<VisitSyncOutcome> outcomes;
    try {
      outcomes = await sender.push(batch);
    } catch (error) {
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

    return _applyOutcomes(batch, outcomes);
  }

  Future<SyncOutcome> _applyOutcomes(
    List<OfflineVisitRecord> batch,
    List<VisitSyncOutcome> outcomes,
  ) async {
    final byLocalId = {for (final outcome in outcomes) outcome.localId: outcome};

    var conflicts = 0;
    var synced = 0;
    var errors = 0;
    String? firstError;
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
          final conflicted = visit.copyWith(status: 'CONFLITO');
          _conflicts.add(conflicted);
          // Volta para a fila: conflito precisa de resolução, não de descarte.
          stillPending.add(conflicted);
          conflicts++;
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

    _pending
      ..clear()
      ..addAll(stillPending);
    await _persist();

    // Precedência: conflito > erro > sincronizado. O conflito é o que exige
    // decisão de quem registrou; o erro, no máximo, uma nova tentativa.
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
