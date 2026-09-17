import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Uma visita EM CLARO, do jeito que o serviço a manipula.
///
/// Espelha o modelo persistido `Visit` campo a campo, com uma diferença: aqui
/// `notes` é `Map<String, String>` legível, enquanto na coluna é ciphertext
/// (`notesEncrypted`/`notesKeyVersion`). A tradução acontece só em
/// `OrmVisitStore` — `application/` não sabe que as notas são cifradas
/// (RNF03, INV-04). Mesma fronteira de [PatientDirectoryEntry] e
/// [TriageSessionRecord].
class VisitRecord {
  const VisitRecord({
    this.id,
    required this.patientId,
    required this.acsId,
    required this.scheduledAt,
    this.startedAt,
    this.completedAt,
    required this.status,
    required this.riskLevelBefore,
    this.riskLevelAfter,
    required this.notes,
    required this.syncStatus,
    required this.arrivalMethod,
    required this.localId,
    this.syncAt,
    required this.version,
  });

  final UuidValue? id;
  final UuidValue patientId;
  final UuidValue acsId;
  final DateTime scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String status;
  final RiskLevel riskLevelBefore;
  final RiskLevel? riskLevelAfter;
  final Map<String, String> notes;
  final SyncStatus syncStatus;

  /// Como o check-in desta visita foi registrado (RF12, decisão §4). Definido
  /// na criação da visita, como [scheduledAt]/[riskLevelBefore] — não muda na
  /// atualização feita ao concluir (ver `VisitSyncService._syncOne`).
  final ArrivalMethod arrivalMethod;
  final UuidValue localId;
  final DateTime? syncAt;
  final int version;

  /// Mesma semântica de sentinela do `copyWith` gerado pelo Serverpod: passar
  /// `null` explicitamente ZERA o campo, e omitir o argumento preserva o valor
  /// atual. Sem a sentinela, `completedAt: null` (uma visita reaberta) seria
  /// indistinguível de "não mexa neste campo".
  VisitRecord copyWith({
    Object? id = _keep,
    UuidValue? patientId,
    UuidValue? acsId,
    DateTime? scheduledAt,
    Object? startedAt = _keep,
    Object? completedAt = _keep,
    String? status,
    RiskLevel? riskLevelBefore,
    Object? riskLevelAfter = _keep,
    Map<String, String>? notes,
    SyncStatus? syncStatus,
    ArrivalMethod? arrivalMethod,
    UuidValue? localId,
    Object? syncAt = _keep,
    int? version,
  }) =>
      VisitRecord(
        id: id == _keep ? this.id : id as UuidValue?,
        patientId: patientId ?? this.patientId,
        acsId: acsId ?? this.acsId,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        startedAt: startedAt == _keep ? this.startedAt : startedAt as DateTime?,
        completedAt: completedAt == _keep ? this.completedAt : completedAt as DateTime?,
        status: status ?? this.status,
        riskLevelBefore: riskLevelBefore ?? this.riskLevelBefore,
        riskLevelAfter:
            riskLevelAfter == _keep ? this.riskLevelAfter : riskLevelAfter as RiskLevel?,
        notes: notes ?? this.notes,
        syncStatus: syncStatus ?? this.syncStatus,
        arrivalMethod: arrivalMethod ?? this.arrivalMethod,
        localId: localId ?? this.localId,
        syncAt: syncAt == _keep ? this.syncAt : syncAt as DateTime?,
        version: version ?? this.version,
      );
}

/// Sentinela de [VisitRecord.copyWith] — equivalente ao `_Undefined` que o
/// Serverpod gera para os seus próprios modelos.
const Object _keep = Object();

/// Persistência das visitas sincronizadas.
///
/// Interface no mesmo padrão de `AlertStore`: mantém o serviço testável sem
/// Postgres real.
abstract interface class VisitStore {
  /// Visita já gravada com este `localId`, se houver.
  Future<VisitRecord?> findByLocalId(String localId);

  /// Grava uma visita nova, já com `version` inicial.
  Future<VisitRecord> insert(VisitRecord visit);

  /// Atualiza uma visita existente, incrementando a versão.
  Future<VisitRecord> update(VisitRecord visit);

  /// Microárea do paciente, ou `null` se ele não existir.
  ///
  /// Sem isto, o serviço validava que o ACS é territorializado mas nunca que o
  /// PACIENTE pertence ao mesmo território — qualquer UUID de paciente
  /// existente era aceito, de qualquer microárea (furo do INV-01).
  Future<UuidValue?> microAreaOfPatient(UuidValue patientId);

  /// Visitas da microárea cujo `syncAt` é posterior a `since` — o cursor
  /// incremental de `visits.pull` (RF15, decisão §5).
  Future<List<VisitRecord>> listChangedInMicroArea(UuidValue microAreaId, DateTime since);
}

/// Sincronização das visitas registradas offline pelo ACS.
///
/// Espelha a `SyncFsm` do lado do dispositivo: cada visita termina em
/// `synced`, `conflict`, `error` ou `rejected`, e conflito **nunca**
/// sobrescreve o que está no servidor — devolve a versão atual para o
/// dispositivo reconciliar.
///
/// `error` é retentável (rede, paciente ainda não cadastrado); `rejected` é
/// terminal — o motivo não muda com uma próxima tentativa (identificador
/// malformado, território, dono do registro) — e o dispositivo não deve
/// reenviar.
class VisitSyncService {
  VisitSyncService({
    required VisitStore store,
    required AuditTrail audit,
    DateTime Function()? clock,
  })  : _store = store,
        _audit = audit,
        _clock = clock ?? DateTime.now;

  final VisitStore _store;
  final AuditTrail _audit;
  final DateTime Function() _clock;

  /// Sincronização central→dispositivo: visitas da microárea do ACS
  /// alteradas desde `since`, para reconciliar um device que ficou offline ou
  /// foi reinstalado. Território vem sempre do token (INV-01), nunca de
  /// parâmetro — mesma regra de `PatientDirectoryService.listForAcs`.
  Future<List<VisitSyncEntry>> pull({
    required AuthenticatedUser user,
    required DateTime since,
  }) async {
    if (user.role != UserRole.acs || user.microAreaId == null) {
      throw StateError('Somente ACS territorializados podem sincronizar visitas.');
    }

    final microAreaId = UuidValue.fromString(user.microAreaId!);
    final visits = await _store.listChangedInMicroArea(microAreaId, since);

    return [
      for (final visit in visits)
        VisitSyncEntry(
          localId: visit.localId.uuid,
          patientId: visit.patientId.uuid,
          scheduledAt: visit.scheduledAt,
          completedAt: visit.completedAt,
          status: visit.status,
          riskLevelBefore: visit.riskLevelBefore,
          riskLevelAfter: visit.riskLevelAfter,
          notes: visit.notes,
          version: visit.version,
          arrivalMethod: visit.arrivalMethod,
          // Relógio do SERVIDOR (gravado em `_syncOne` via `_clock()`), nunca
          // o do dispositivo. É o que o cursor do app usa para avançar sem
          // depender do relógio do aparelho — ver `VisitPullService` no ACS.
          syncAt: visit.syncAt,
        ),
    ];
  }

  Future<List<VisitSyncResult>> sync({
    required AuthenticatedUser user,
    required List<VisitSyncEntry> entries,
  }) async {
    if (user.role != UserRole.acs || user.microAreaId == null) {
      throw StateError('Somente ACS territorializados podem sincronizar visitas.');
    }

    final results = <VisitSyncResult>[];
    for (final entry in entries) {
      results.add(await _syncOne(user: user, entry: entry));
    }
    return results;
  }

  Future<VisitSyncResult> _syncOne({
    required AuthenticatedUser user,
    required VisitSyncEntry entry,
  }) async {
    if (entry.localId.trim().isEmpty) {
      // Terminal: um localId vazio não vira válido reenviando o mesmo lote.
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.rejected,
        message: 'localId é obrigatório',
      );
    }

    final UuidValue localId;
    final UuidValue patientId;
    try {
      // `UuidValue.fromString` NÃO valida — só normaliza para minúsculas. Sem
      // `withValidation`, um `localId` malformado entraria no banco e quebraria
      // a deduplicação do reenvio, que é justamente o que o índice único
      // protege.
      localId = UuidValue.withValidation(entry.localId);
      patientId = UuidValue.withValidation(entry.patientId);
    } on FormatException {
      // Terminal: um identificador malformado na origem não vira válido
      // reenviando.
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.rejected,
        message: 'identificadores devem ser UUID',
      );
    }

    // Território ANTES de tocar em `existing`: um reenvio para o mesmo
    // `localId` também precisa ser barrado, não só a primeira gravação.
    final patientMicroAreaId = await _store.microAreaOfPatient(patientId);
    if (patientMicroAreaId == null) {
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.error,
        message: 'paciente não encontrado',
      );
    }

    final acsMicroAreaId = UuidValue.fromString(user.microAreaId!);
    if (patientMicroAreaId != acsMicroAreaId) {
      // A mensagem não cita a microárea alheia nem o nome do paciente — só que
      // o vínculo não existe. §404 de spec/lgpd_design.md: "o sistema monitora
      // se um ACS consulta dados de um paciente fora de sua microárea sem
      // justificativa, gerando alerta para auditoria".
      await _audit.recordSafely(AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: 'visit',
        resourceId: patientId.uuid,
        result: 'denied_territory',
      ));
      // Terminal: o território não muda por retentar.
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.rejected,
        message: 'paciente fora da sua microárea',
      );
    }

    final acsId = UuidValue.fromString(user.id);
    final existing = await _store.findByLocalId(entry.localId);

    if (existing == null) {
      final inserted = await _store.insert(VisitRecord(
        patientId: patientId,
        acsId: acsId,
        scheduledAt: entry.scheduledAt,
        completedAt: entry.completedAt,
        status: entry.status,
        riskLevelBefore: entry.riskLevelBefore,
        riskLevelAfter: entry.riskLevelAfter,
        notes: entry.notes,
        syncStatus: SyncStatus.synced,
        arrivalMethod: entry.arrivalMethod,
        localId: localId,
        syncAt: _clock().toUtc(),
        version: 1,
      ));
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.synced,
        serverVersion: inserted.version,
      );
    }

    // A visita pertence ao ACS que a registrou. Um ACS não sincroniza a visita
    // de outro, mesmo conhecendo o localId.
    if (existing.acsId != acsId) {
      // Terminal: o dono do registro não muda por retentar.
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.rejected,
        message: 'visita registrada por outro agente',
      );
    }

    // Reenvio do MESMO estado: a rede caiu depois de o servidor gravar, e o
    // dispositivo não viu a resposta. Não é conflito — é a idempotência
    // funcionando.
    if (entry.version == existing.version) {
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.synced,
        serverVersion: existing.version,
      );
    }

    // O dispositivo partiu de uma versão que não é mais a atual: alguém alterou
    // a visita no meio. Devolve conflito com a versão do servidor, sem
    // sobrescrever nada.
    if (entry.version != existing.version - 1) {
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.conflict,
        serverVersion: existing.version,
      );
    }

    // `arrivalMethod` fica de fora deliberadamente: é definido na criação da
    // visita (como `scheduledAt`/`riskLevelBefore`), não numa atualização de
    // conclusão — `copyWith` sem o argumento preserva o valor gravado no
    // insert.
    final updated = await _store.update(existing.copyWith(
      completedAt: entry.completedAt,
      status: entry.status,
      riskLevelAfter: entry.riskLevelAfter,
      notes: entry.notes,
      syncStatus: SyncStatus.synced,
      syncAt: _clock().toUtc(),
      version: existing.version + 1,
    ));

    return VisitSyncResult(
      localId: entry.localId,
      syncStatus: SyncStatus.synced,
      serverVersion: updated.version,
    );
  }
}
