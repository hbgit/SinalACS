import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
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
    this.authorship = VisitAuthorship.acs,
    this.originDeviceId,
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

  /// Autor da visita. Nulo **só** quando [authorship] é
  /// [VisitAuthorship.legacyUnclaimed]: a visita veio do aparelho sem dono
  /// conhecido (D4), e quem a transportou **não** é o autor.
  final UuidValue? acsId;

  final VisitAuthorship authorship;

  /// Instalação de onde veio uma visita legada; nulo nas visitas com autor.
  final String? originDeviceId;
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
    Object? acsId = _keep,
    VisitAuthorship? authorship,
    Object? originDeviceId = _keep,
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
        acsId: acsId == _keep ? this.acsId : acsId as UuidValue?,
        authorship: authorship ?? this.authorship,
        originDeviceId:
            originDeviceId == _keep ? this.originDeviceId : originDeviceId as String?,
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

/// A visita existe no banco, mas sem o risco cifrado: foi gravada antes da
/// migração da #75, que descartou as colunas em claro sem backfill. Não há
/// risco legível para devolver, e inventar um violaria a INV-02; quem chama
/// recusa só esta visita. Leva só o id sintético (VAZ-01).
class UnreadableVisitException implements Exception {
  const UnreadableVisitException(this.visitId);

  final UuidValue? visitId;

  @override
  String toString() => 'Visita $visitId sem riskLevelBefore cifrado (#75).';
}

/// Persistência das visitas sincronizadas.
///
/// Interface no mesmo padrão de `AlertStore`: mantém o serviço testável sem
/// Postgres real.
abstract interface class VisitStore {
  /// Visita já gravada com este `localId`, se houver. Lança
  /// [UnreadableVisitException] se ela existe mas não tem o risco cifrado.
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

  /// `true` se o ACS existe e a conta está ativa (`acs.active`).
  ///
  /// Só `syncLegacy` consulta: o token prova quem é o transportador, não que a
  /// conta continua ativa — e uma visita sem autor só entra pela mão de quem
  /// ainda responde pelo território.
  Future<bool> isActiveAcs(UuidValue acsId);
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

  /// Teto de visitas por chamada de envio desvinculado do autor (`syncLegacy`;
  /// a Task 6 reaproveita no `syncDeferred`). O `sync` comum NÃO tem teto.
  static const int maxLegacyBatch = 200;

  /// Recusa um lote acima de [maxLegacyBatch] com `ArgumentError` (o endpoint
  /// traduz para `AlertValidationException`). Pública para o endpoint poder
  /// checar ANTES de abrir a transação.
  static void checkLegacyBatchSize(int length) {
    if (length > maxLegacyBatch) {
      throw ArgumentError.value(length, 'visits',
          'lote acima do limite de $maxLegacyBatch visitas por envio');
    }
  }

  /// Sincronização central→dispositivo: visitas da microárea do ACS
  /// alteradas desde `since`, para reconciliar um device que ficou offline ou
  /// foi reinstalado. Território vem sempre do token (INV-01), nunca de
  /// parâmetro — mesma regra de `PatientDirectoryService.listForAcs`.
  Future<List<VisitSyncEntry>> pull({
    required AuthenticatedUser user,
    required DateTime since,
  }) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem sincronizar visitas.'),
    );

    final microAreaId = UuidValue.fromString(user.microAreaId!);
    final visits = await _store.listChangedInMicroArea(microAreaId, since);

    // Best-effort, mesmo padrão de `PatientDirectoryService.listForAcs`: uma
    // trilha de auditoria que falha não pode impedir o ACS de sincronizar. A
    // leitura audita o EVENTO — `notes` é texto clínico decifrado na volta —,
    // não as visitas retornadas, para não recriar o prontuário dentro do
    // próprio log de auditoria.
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: 'visit_pull',
      result: 'granted',
    ));

    return [for (final visit in visits) _entryFor(visit)];
  }

  /// A visita como o ACS a recebe (`pull` e cópia do servidor no conflito).
  VisitSyncEntry _entryFor(VisitRecord visit) => VisitSyncEntry(
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
      );

  Future<List<VisitSyncResult>> sync({
    required AuthenticatedUser user,
    required List<VisitSyncEntry> entries,
  }) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem sincronizar visitas.'),
    );

    final results = <VisitSyncResult>[];
    for (final entry in entries) {
      results.add(await _syncOne(user: user, entry: entry));
    }
    return results;
  }

  /// Envio das visitas LEGADAS do aparelho — gravadas antes de existir dono
  /// por visita (migração v7 do app), de autoria desconhecida (D4).
  ///
  /// A sessão de [transporter] é só o **transporte**: precisa ser de um ACS
  /// territorializado e ativo, e cada visita passa pela mesma barreira de
  /// território do `sync` (microárea do paciente × microárea de quem
  /// transporta, INV-01), mas o transportador **nunca** vira autor —
  /// `acsId` fica nulo, `authorship` é `legacyUnclaimed` e `originDeviceId`
  /// guarda [deviceId]. Reenvio do mesmo `localId` é idempotente; um `localId`
  /// que já existe com autor ACS é recusado (`rejected`) e a autoria original
  /// fica intacta.
  ///
  /// Um evento `visit_legacy_sync` por LOTE vai para `audit_logs`, com o
  /// transportador e sem paciente, `localId` ou nota; e um
  /// `visit_legacy_sync_item` por visita efetivamente criada ou alterada, com
  /// o id da visita (`resourceId`) — nenhum para recusa ou reenvio sem efeito.
  /// No máximo [maxLegacyBatch] visitas por chamada.
  Future<List<VisitSyncResult>> syncLegacy({
    required AuthenticatedUser transporter,
    required String deviceId,
    required List<VisitSyncEntry> entries,
  }) async {
    Authorization.require(
      transporter,
      roles: {UserRole.acs},
      onDenied: () => StateError(
          'Somente ACS territorializados podem enviar visitas legadas.'),
    );
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'deviceId é obrigatório');
    }
    // Antes de qualquer consulta ao store.
    checkLegacyBatchSize(entries.length);
    if (!await _store.isActiveAcs(UuidValue.fromString(transporter.id))) {
      throw StateError('Somente ACS ativos podem enviar visitas legadas.');
    }

    final results = <VisitSyncResult>[];
    final written = <VisitRecord>[];
    for (final entry in entries) {
      results.add(await _syncOne(
        user: transporter,
        entry: entry,
        legacyDeviceId: deviceId,
        legacyWritten: written,
      ));
    }

    // A trilha usa outra conexão, FORA da transação do lote: gravar os itens
    // dentro do laço deixaria linhas apontando para visitas que nunca
    // persistiram quando uma entrada posterior lança e o lote é desfeito. Por
    // isso os itens só saem aqui, depois do laço inteiro, logo antes do lote.
    for (final visit in written) {
      await _auditLegacyItem(transporter, visit);
    }

    // Best-effort, como o `pull`: a trilha fora do ar não pode impedir que o
    // trabalho de campo suba. O evento é o LOTE — nada clínico, nenhum
    // identificador de paciente.
    await _audit.recordSafely(AuditEvent(
      userId: transporter.id,
      actionType: 'write',
      resourceType: 'visit_legacy',
      result: 'visit_legacy_sync',
    ));
    return results;
  }

  /// Resolução explícita de um conflito pelo AUTOR ("manter a minha" ou
  /// "editar e enviar", #79): compare-and-set sobre a versão do servidor que o
  /// aparelho viu.
  ///
  /// `entry.version` é IGNORADO — a única referência é
  /// [expectedServerVersion]. Igual à versão corrente: grava o conteúdo da
  /// entrada em `existing.version + 1` e devolve `synced`. Diferente (alguém
  /// mudou a visita de novo depois do conflito): devolve um `conflict` novo
  /// com a cópia atual, sem gravar nada. Visita inexistente no servidor é
  /// criada como no `sync`. Recusas de identidade, território e autoria são
  /// as mesmas do `sync` (`_checkTarget`).
  ///
  /// A decisão vai para a trilha como `write`/`visit`/`conflict_resolved_local`
  /// com o id da visita e nada clínico — best-effort (`recordSafely`), como o
  /// resto do domínio de visitas: o trabalho de campo não para por queda da
  /// trilha.
  Future<VisitSyncResult> resolveConflict({
    required AuthenticatedUser user,
    required VisitSyncEntry entry,
    required int expectedServerVersion,
  }) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem sincronizar visitas.'),
    );
    if (expectedServerVersion < 1) {
      throw ArgumentError.value(expectedServerVersion, 'expectedServerVersion',
          'versão esperada do servidor deve ser ao menos 1');
    }

    final gate = await _checkTarget(user: user, entry: entry, legacy: false);
    if (gate is _Refused) return gate.result;
    final (:localId, :patientId, :existing) = (gate as _Cleared).target;

    if (existing != null && existing.version != expectedServerVersion) {
      return _conflictFor(user, entry, existing);
    }

    final written = existing == null
        ? await _store.insert(_newVisit(
            entry: entry,
            localId: localId,
            patientId: patientId,
            acsId: UuidValue.fromString(user.id),
          ))
        : await _store.update(_updatedVisit(existing, entry));

    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'visit',
      resourceId: written.id?.uuid,
      result: 'conflict_resolved_local',
    ));
    return VisitSyncResult(
      localId: entry.localId,
      syncStatus: SyncStatus.synced,
      serverVersion: written.version,
    );
  }

  /// Uma visita do lote. Com [legacyDeviceId] nulo é o `sync` comum (o autor
  /// é [user]); preenchido, é o envio legado (sem autor, [user] só transporta).
  Future<VisitSyncResult> _syncOne({
    required AuthenticatedUser user,
    required VisitSyncEntry entry,
    String? legacyDeviceId,
    List<VisitRecord>? legacyWritten,
  }) async {
    final legacy = legacyDeviceId != null;
    final gate = await _checkTarget(user: user, entry: entry, legacy: legacy);
    if (gate is _Refused) return gate.result;
    final (:localId, :patientId, :existing) = (gate as _Cleared).target;

    if (existing == null) {
      final inserted = await _store.insert(_newVisit(
        entry: entry,
        localId: localId,
        patientId: patientId,
        // Legado: autoria desconhecida. NUNCA gravar quem transportou.
        acsId: legacy ? null : UuidValue.fromString(user.id),
        legacyDeviceId: legacyDeviceId,
      ));
      legacyWritten?.add(inserted);
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.synced,
        serverVersion: inserted.version,
      );
    }

    if (legacy) {
      // Antes de QUALQUER resposta que dependa da linha existente: o `localId`
      // tem de ser de uma visita do MESMO paciente da entrada (cujo território
      // já foi conferido acima — logo, a linha também é do território de quem
      // transporta). Sem isto, `synced`/'versão diferente' viraria um oráculo:
      // quem chuta um `localId` descobriria que a visita existe, e em que
      // versão, mesmo sendo de outro paciente ou de outra microárea. A
      // resposta é a mesma da recusa territorial, para não distinguir os casos.
      if (existing.patientId != patientId) {
        await _audit.recordSafely(AuditEvent(
          userId: user.id,
          actionType: 'write',
          resourceType: 'visit_legacy',
          resourceId: patientId.uuid,
          result: 'denied_patient_mismatch',
        ));
        return _outsideTerritory(entry);
      }

      // O envio legado só ALTERA visitas SEM autor que vieram do mesmo
      // aparelho. Uma visita com autor ACS não vira "desconhecida" por um
      // reenvio: na mesma versão o reenvio é só a idempotência (a visita já
      // subiu, possivelmente pelo próprio autor antes da migração v7) e
      // devolve `synced` sem gravar nada; em outra versão, `rejected`.
      if (existing.authorship != VisitAuthorship.legacyUnclaimed ||
          existing.acsId != null) {
        if (entry.version == existing.version) {
          return VisitSyncResult(
            localId: entry.localId,
            syncStatus: SyncStatus.synced,
            serverVersion: existing.version,
          );
        }
        return VisitSyncResult(
          localId: entry.localId,
          syncStatus: SyncStatus.rejected,
          message: 'visita já registrada com autor — versão diferente',
        );
      }
      // Proteção contra palpite errado (um localId colidindo entre aparelhos,
      // um cliente com bug), NÃO controle de segurança: `deviceId` é declarado
      // pelo próprio cliente e qualquer portador de sessão pode repeti-lo.
      if (existing.originDeviceId != legacyDeviceId) {
        return VisitSyncResult(
          localId: entry.localId,
          syncStatus: SyncStatus.rejected,
          message: 'visita legada de outro aparelho',
        );
      }
    }
    // Fora do legado, a autoria (sem autor / outro agente) já foi conferida
    // em `_checkTarget`.

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
      // Só o autor recebe a cópia (aqui `legacy` já exclui o transportador).
      // Audita o EVENTO, sem conteúdo clínico, como o `visit_pull`.
      if (legacy) {
        return VisitSyncResult(
          localId: entry.localId,
          syncStatus: SyncStatus.conflict,
          serverVersion: existing.version,
        );
      }
      return _conflictFor(user, entry, existing);
    }

    // Ver `_updatedVisit` sobre os campos que a atualização preserva.
    final updated = await _store.update(_updatedVisit(existing, entry));

    legacyWritten?.add(updated);
    return VisitSyncResult(
      localId: entry.localId,
      syncStatus: SyncStatus.synced,
      serverVersion: updated.version,
    );
  }

  /// Checagens de identidade, território e autoria comuns a `sync`,
  /// `syncLegacy` e `resolveConflict` — um só lugar, para as recusas serem as
  /// MESMAS (mesmo `SyncStatus`, mesma `message`, mesma auditoria
  /// `denied_territory`).
  ///
  /// Com [legacy], a autoria NÃO é conferida aqui: o envio legado tem regras
  /// próprias (paciente divergente, visita com autor, outro aparelho), que
  /// seguem em `_syncOne`.
  Future<_Gate> _checkTarget({
    required AuthenticatedUser user,
    required VisitSyncEntry entry,
    required bool legacy,
  }) async {
    if (entry.localId.trim().isEmpty) {
      // Terminal: um localId vazio não vira válido reenviando o mesmo lote.
      return _Refused(VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.rejected,
        message: 'localId é obrigatório',
      ));
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
      return _Refused(VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.rejected,
        message: 'identificadores devem ser UUID',
      ));
    }

    // Território ANTES de tocar em `existing`: um reenvio para o mesmo
    // `localId` também precisa ser barrado, não só a primeira gravação.
    final patientMicroAreaId = await _store.microAreaOfPatient(patientId);
    if (patientMicroAreaId == null) {
      return _Refused(VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.error,
        message: 'paciente não encontrado',
      ));
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
        resourceType: legacy ? 'visit_legacy' : 'visit',
        resourceId: patientId.uuid,
        result: 'denied_territory',
      ));
      // Terminal: o território não muda por retentar.
      return _Refused(_outsideTerritory(entry));
    }

    final VisitRecord? existing;
    try {
      existing = await _store.findByLocalId(entry.localId);
    } on UnreadableVisitException {
      // Terminal e só desta visita: o resto do lote segue, e o aparelho a
      // mantém na fila para revisão em vez de achar que a sessão caiu.
      return _Refused(VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.rejected,
        message: 'visita anterior à cifra do risco (#75)',
      ));
    }

    if (!legacy && existing != null) {
      // O território acima foi conferido contra o paciente DECLARADO. Sem
      // isto, um ACS movido de microárea (`admin.setAcsMicroArea`) mandaria o
      // `localId` de uma visita sua antiga com um paciente da área nova e
      // receberia a cópia da área de origem no `conflict` (ou a sobrescreveria
      // pelo `resolveConflict`). Antes da autoria, para nenhuma resposta
      // revelar que o `localId` existe; a resposta é a mesma da recusa
      // territorial, como no ramo legado.
      if (existing.patientId != patientId) {
        await _audit.recordSafely(AuditEvent(
          userId: user.id,
          actionType: 'write',
          resourceType: 'visit',
          resourceId: patientId.uuid,
          result: 'denied_patient_mismatch',
        ));
        return _Refused(_outsideTerritory(entry));
      }
      final acsId = UuidValue.fromString(user.id);
      if (existing.acsId == null) {
        // Visita sem autor (legado, D4): o `sync` comum NÃO a reivindica — se
        // reivindicasse, qualquer ACS do território viraria autor de um
        // trabalho de campo que ninguém sabe de quem é. Terminal: não muda por
        // retentar.
        return _Refused(VisitSyncResult(
          localId: entry.localId,
          syncStatus: SyncStatus.rejected,
          message: 'visita sem autor registrado',
        ));
      }
      if (existing.acsId != acsId) {
        // A visita pertence ao ACS que a registrou. Um ACS não sincroniza a
        // visita de outro, mesmo conhecendo o localId. Terminal: o dono do
        // registro não muda por retentar.
        return _Refused(VisitSyncResult(
          localId: entry.localId,
          syncStatus: SyncStatus.rejected,
          message: 'visita registrada por outro agente',
        ));
      }
    }

    return _Cleared((localId: localId, patientId: patientId, existing: existing));
  }

  /// Visita nova a partir da entrada do aparelho, já `synced` na versão 1.
  /// Sem [acsId] é a visita legada, de autoria desconhecida (D4).
  VisitRecord _newVisit({
    required VisitSyncEntry entry,
    required UuidValue localId,
    required UuidValue patientId,
    required UuidValue? acsId,
    String? legacyDeviceId,
  }) =>
      VisitRecord(
        patientId: patientId,
        acsId: acsId,
        authorship: acsId == null ? VisitAuthorship.legacyUnclaimed : VisitAuthorship.acs,
        originDeviceId: legacyDeviceId,
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
      );

  /// [existing] com o conteúdo de conclusão da entrada, em
  /// `existing.version + 1`.
  ///
  /// `acsId`, `authorship` e `originDeviceId` ficam de fora: a autoria é
  /// decidida na criação e nenhuma atualização a muda (nem o envio legado
  /// preenche um autor, nem o `sync` comum chega aqui com visita sem autor).
  /// `arrivalMethod` fica de fora deliberadamente: é definido na criação da
  /// visita (como `scheduledAt`/`riskLevelBefore`), não numa atualização de
  /// conclusão — `copyWith` sem o argumento preserva o valor gravado no
  /// insert.
  VisitRecord _updatedVisit(VisitRecord existing, VisitSyncEntry entry) => existing.copyWith(
        completedAt: entry.completedAt,
        status: entry.status,
        riskLevelAfter: entry.riskLevelAfter,
        notes: entry.notes,
        syncStatus: SyncStatus.synced,
        syncAt: _clock().toUtc(),
        version: existing.version + 1,
      );

  /// Conflito com a cópia do servidor para o AUTOR (nunca no legado, cujo
  /// transportador não é autor). Audita o EVENTO, sem conteúdo clínico, como
  /// o `visit_pull`.
  Future<VisitSyncResult> _conflictFor(
    AuthenticatedUser user,
    VisitSyncEntry entry,
    VisitRecord existing,
  ) async {
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: 'visit_conflict',
      resourceId: existing.id?.uuid,
      result: 'granted',
    ));
    return VisitSyncResult(
      localId: entry.localId,
      syncStatus: SyncStatus.conflict,
      serverVersion: existing.version,
      serverVisit: _entryFor(existing),
    );
  }

  /// A recusa territorial, única para fora do território e para `localId` de
  /// outro paciente: não cita a microárea alheia nem o paciente. Terminal.
  static VisitSyncResult _outsideTerritory(VisitSyncEntry entry) => VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.rejected,
        message: 'paciente fora da sua microárea',
      );

  /// Uma linha por visita legada criada ou alterada: quem transportou e QUAL
  /// visita — só o id, nada clínico. Best-effort como o resto da trilha.
  Future<void> _auditLegacyItem(AuthenticatedUser transporter, VisitRecord visit) =>
      _audit.recordSafely(AuditEvent(
        userId: transporter.id,
        actionType: 'write',
        resourceType: 'visit_legacy',
        resourceId: visit.id?.uuid,
        result: 'visit_legacy_sync_item',
      ));
}

/// Desfecho de `VisitSyncService._checkTarget`.
sealed class _Gate {
  const _Gate();
}

/// Recusa pronta para devolver ao aparelho.
final class _Refused extends _Gate {
  const _Refused(this.result);

  final VisitSyncResult result;
}

/// Identificadores válidos, território conferido e (fora do legado) autoria
/// conferida; [target] traz a linha existente, se houver.
final class _Cleared extends _Gate {
  const _Cleared(this.target);

  final ({UuidValue localId, UuidValue patientId, VisitRecord? existing}) target;
}
