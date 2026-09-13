import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Persistência das visitas sincronizadas.
///
/// Interface no mesmo padrão de `AlertStore`: mantém o serviço testável sem
/// Postgres real.
abstract interface class VisitStore {
  /// Visita já gravada com este `localId`, se houver.
  Future<Visit?> findByLocalId(String localId);

  /// Grava uma visita nova, já com `version` inicial.
  Future<Visit> insert(Visit visit);

  /// Atualiza uma visita existente, incrementando a versão.
  Future<Visit> update(Visit visit);

  /// Microárea do paciente, ou `null` se ele não existir.
  ///
  /// Sem isto, o serviço validava que o ACS é territorializado mas nunca que o
  /// PACIENTE pertence ao mesmo território — qualquer UUID de paciente
  /// existente era aceito, de qualquer microárea (furo do INV-01).
  Future<UuidValue?> microAreaOfPatient(UuidValue patientId);
}

/// Sincronização das visitas registradas offline pelo ACS.
///
/// Espelha a `SyncFsm` do lado do dispositivo: cada visita termina em
/// `synced`, `conflict` ou `error`, e conflito **nunca** sobrescreve o que está
/// no servidor — devolve a versão atual para o dispositivo reconciliar.
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
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.error,
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
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.error,
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
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.error,
        message: 'paciente fora da sua microárea',
      );
    }

    final acsId = UuidValue.fromString(user.id);
    final existing = await _store.findByLocalId(entry.localId);

    if (existing == null) {
      final inserted = await _store.insert(Visit(
        patientId: patientId,
        acsId: acsId,
        scheduledAt: entry.scheduledAt,
        completedAt: entry.completedAt,
        status: entry.status,
        riskLevelBefore: entry.riskLevelBefore,
        riskLevelAfter: entry.riskLevelAfter,
        notes: entry.notes,
        syncStatus: SyncStatus.synced,
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
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.error,
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
