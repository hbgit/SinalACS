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

  /// Uma visita do lote. Com [legacyDeviceId] nulo é o `sync` comum (o autor
  /// é [user]); preenchido, é o envio legado (sem autor, [user] só transporta).
  Future<VisitSyncResult> _syncOne({
    required AuthenticatedUser user,
    required VisitSyncEntry entry,
    String? legacyDeviceId,
    List<VisitRecord>? legacyWritten,
  }) async {
    final legacy = legacyDeviceId != null;
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
        resourceType: legacy ? 'visit_legacy' : 'visit',
        resourceId: patientId.uuid,
        result: 'denied_territory',
      ));
      // Terminal: o território não muda por retentar.
      return _outsideTerritory(entry);
    }

    final acsId = UuidValue.fromString(user.id);
    final existing = await _store.findByLocalId(entry.localId);

    if (existing == null) {
      final inserted = await _store.insert(VisitRecord(
        patientId: patientId,
        // Legado: autoria desconhecida. NUNCA gravar quem transportou.
        acsId: legacy ? null : acsId,
        authorship: legacy ? VisitAuthorship.legacyUnclaimed : VisitAuthorship.acs,
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
    } else if (existing.acsId == null) {
      // Visita sem autor (legado, D4): o `sync` comum NÃO a reivindica — se
      // reivindicasse, qualquer ACS do território viraria autor de um trabalho
      // de campo que ninguém sabe de quem é. Terminal: não muda por retentar.
      return VisitSyncResult(
        localId: entry.localId,
        syncStatus: SyncStatus.rejected,
        message: 'visita sem autor registrado',
      );
    } else if (existing.acsId != acsId) {
      // A visita pertence ao ACS que a registrou. Um ACS não sincroniza a
      // visita de outro, mesmo conhecendo o localId. Terminal: o dono do
      // registro não muda por retentar.
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

    // `acsId`, `authorship` e `originDeviceId` também ficam de fora: a autoria
    // é decidida na criação e nenhuma atualização a muda (nem o envio legado
    // preenche um autor, nem o `sync` comum chega aqui com visita sem autor).
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

    legacyWritten?.add(updated);
    return VisitSyncResult(
      localId: entry.localId,
      syncStatus: SyncStatus.synced,
      serverVersion: updated.version,
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
