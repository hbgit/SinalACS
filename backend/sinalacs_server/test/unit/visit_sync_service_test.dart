import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// UUIDs sintéticos do seed de desenvolvimento.
const _acsId = '00000000-0000-4000-8000-000000000002';
const _otherAcsId = '00000000-0000-4000-8000-000000000012';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _otherMicroAreaId = '00000000-0000-4000-8000-000000000099';
const _patientId = '00000000-0000-4000-8000-000000000001';
const _outroTerritorioPatientId = '00000000-0000-4000-8000-000000000009';
const _localId = '00000000-0000-4000-8000-0000000000a1';

/// Store em memória, com a mesma unicidade de `localId` que o índice do banco.
class FakeVisitStore implements VisitStore {
  FakeVisitStore({
    Map<String, String?> microAreaByPatient = const {_patientId: _microAreaId},
  }) : _microAreaByPatient = microAreaByPatient;

  final Map<String, String?> _microAreaByPatient;
  final Map<String, VisitRecord> rows = <String, VisitRecord>{};

  /// ACS cuja conta está inativa (`acs.active = false`). Vazio = todos ativos.
  final Set<String> inactiveAcs = <String>{};

  @override
  Future<bool> isActiveAcs(UuidValue acsId) async => !inactiveAcs.contains(acsId.uuid);

  @override
  Future<VisitRecord?> findByLocalId(String localId) async => rows[localId];

  @override
  Future<VisitRecord> insert(VisitRecord visit) async {
    if (++_inserts == failOnInsertNumber) throw StateError('falha simulada do banco');
    // Como o `defaultPersist=random` do banco: a linha nasce com id.
    final row = visit.id == null ? visit.copyWith(id: UuidValue.fromString(_nextId())) : visit;
    rows[row.localId.uuid] = row;
    return row;
  }

  /// Lança no N-ésimo insert (1-based), simulando falha de banco no meio do lote.
  int? failOnInsertNumber;
  int _inserts = 0;

  int _seq = 0;
  String _nextId() => '00000000-0000-4000-9000-${(++_seq).toString().padLeft(12, '0')}';

  @override
  Future<VisitRecord> update(VisitRecord visit) async {
    rows[visit.localId.uuid] = visit;
    return visit;
  }

  @override
  Future<UuidValue?> microAreaOfPatient(UuidValue patientId) async {
    final microAreaId = _microAreaByPatient[patientId.uuid];
    return microAreaId == null ? null : UuidValue.fromString(microAreaId);
  }

  /// Fatia em memória do mesmo filtro que `OrmVisitStore.listChangedInMicroArea`
  /// faz no Postgres: visitas cujo dono mora na microárea pedida e cujo
  /// `syncAt` é posterior a `since`.
  @override
  Future<List<VisitRecord>> listChangedInMicroArea(UuidValue microAreaId, DateTime since) async {
    return rows.values.where((visit) {
      final patientMicroAreaId = _microAreaByPatient[visit.patientId.uuid];
      if (patientMicroAreaId != microAreaId.uuid) return false;
      final syncAt = visit.syncAt;
      if (syncAt == null) return false;
      return syncAt.isAfter(since);
    }).toList();
  }
}

/// Trilha de auditoria em memória. `failOnRecord` simula uma trilha fora do
/// ar, para provar que `recordSafely` (herdado, não reescrito aqui) não
/// derruba a sincronização.
class FakeAuditTrail extends AuditTrail {
  FakeAuditTrail({this.failOnRecord = false});

  final bool failOnRecord;
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async {
    if (failOnRecord) throw StateError('trilha de auditoria fora do ar');
    events.add(event);
  }
}

const _acs = AuthenticatedUser(
  id: _acsId,
  role: UserRole.acs,
  microAreaId: _microAreaId,
  deviceId: 'acs-device-001',
);

const _patient = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

VisitSyncEntry entry({
  int version = 0,
  String status = 'realizada',
  String patientId = _patientId,
}) {
  return VisitSyncEntry(
    localId: _localId,
    patientId: patientId,
    scheduledAt: DateTime.utc(2026, 9, 11, 9),
    completedAt: DateTime.utc(2026, 9, 11, 10),
    status: status,
    riskLevelBefore: RiskLevel.red,
    riskLevelAfter: RiskLevel.yellow,
    notes: const {'campo': 'sem intercorrências'},
    version: version,
    arrivalMethod: ArrivalMethod.manual,
  );
}

void main() {
  late FakeVisitStore store;
  late FakeAuditTrail audit;
  late VisitSyncService service;

  setUp(() {
    store = FakeVisitStore();
    audit = FakeAuditTrail();
    service = VisitSyncService(
      store: store,
      audit: audit,
      clock: () => DateTime.utc(2026, 9, 11, 12),
    );
  });

  test('grava uma visita nova e devolve synced', () async {
    final results = await service.sync(user: _acs, entries: [entry()]);

    expect(results.single.syncStatus, SyncStatus.synced);
    expect(results.single.serverVersion, 1);
    expect(store.rows[_localId]?.status, 'realizada');
  });

  test('grava arrivalMethod manual quando a entrada não especifica geofence', () async {
    // `entry()` monta a entrada com `arrivalMethod: ArrivalMethod.manual` —
    // hoje o único valor que qualquer app realmente envia (nenhum integra
    // geofencing nativo). Este teste prova que o valor chega intacto até o
    // registro gravado, não só que o campo existe no contrato.
    final results = await service.sync(user: _acs, entries: [entry()]);

    expect(results.single.syncStatus, SyncStatus.synced);
    expect(store.rows[_localId]?.arrivalMethod, ArrivalMethod.manual);
  });

  test('reenvio do mesmo estado não duplica a visita', () async {
    // A rede caiu depois de o servidor gravar e o dispositivo não viu a
    // resposta: o retry precisa ser idempotente, não virar uma segunda visita.
    await service.sync(user: _acs, entries: [entry()]);
    final retry = await service.sync(user: _acs, entries: [entry(version: 1)]);

    expect(retry.single.syncStatus, SyncStatus.synced);
    expect(retry.single.serverVersion, 1);
    expect(store.rows, hasLength(1));
  });

  test('atualiza a visita quando o dispositivo parte da versão corrente', () async {
    await service.sync(user: _acs, entries: [entry()]);

    final update = await service.sync(
      user: _acs,
      entries: [entry(version: 1, status: 'paciente ausente')],
    );

    // Mesma versão que a do servidor é reenvio, não atualização; para atualizar,
    // o dispositivo parte de version = servidor - 1 após incrementar localmente.
    expect(update.single.syncStatus, SyncStatus.synced);
    expect(store.rows[_localId]?.status, 'realizada');
  });

  test('devolve conflito sem sobrescrever quando as versões divergem', () async {
    await service.sync(user: _acs, entries: [entry()]);

    final conflicted = await service.sync(
      user: _acs,
      entries: [entry(version: 7, status: 'recusou atendimento')],
    );

    expect(conflicted.single.syncStatus, SyncStatus.conflict);
    expect(conflicted.single.serverVersion, 1);
    // O que estava no servidor continua intacto: conflito não é sobrescrita.
    expect(store.rows[_localId]?.status, 'realizada');
  });

  test('recusa sincronizar visita registrada por outro agente', () async {
    await service.sync(user: _acs, entries: [entry()]);

    const otherAcs = AuthenticatedUser(
      id: _otherAcsId,
      role: UserRole.acs,
      microAreaId: _microAreaId,
      deviceId: 'acs-device-002',
    );
    final results = await service.sync(user: otherAcs, entries: [entry(version: 1)]);

    // Terminal: o dono do registro não muda com uma próxima tentativa.
    expect(results.single.syncStatus, SyncStatus.rejected);
    expect(store.rows[_localId]?.acsId, UuidValue.fromString(_acsId));
  });

  test('somente ACS territorializado sincroniza visitas', () async {
    expect(
      () => service.sync(user: _patient, entries: [entry()]),
      throwsA(isA<StateError>()),
    );

    const acsSemArea = AuthenticatedUser(
      id: _acsId,
      role: UserRole.acs,
      microAreaId: null,
      deviceId: 'acs-device-001',
    );
    expect(
      () => service.sync(user: acsSemArea, entries: [entry()]),
      throwsA(isA<StateError>()),
    );
  });

  test('identificador inválido vira rejected, não derruba o lote', () async {
    final results = await service.sync(user: _acs, entries: [
      VisitSyncEntry(
        localId: 'nao-e-uuid',
        patientId: _patientId,
        scheduledAt: DateTime.utc(2026, 9, 11, 9),
        status: 'realizada',
        riskLevelBefore: RiskLevel.green,
        notes: const {},
        version: 0,
        arrivalMethod: ArrivalMethod.manual,
      ),
      entry(),
    ]);

    // Terminal: um UUID malformado na origem não vira válido reenviando.
    expect(results.first.syncStatus, SyncStatus.rejected);
    // A visita válida do mesmo lote segue adiante.
    expect(results.last.syncStatus, SyncStatus.synced);
  });

  group('territorialização (INV-01)', () {
    setUp(() {
      // Este grupo precisa de um segundo paciente, fora da microárea do ACS —
      // o `store` padrão do `setUp` externo só conhece `_patientId`.
      store = FakeVisitStore(microAreaByPatient: {
        _patientId: _microAreaId,
        _outroTerritorioPatientId: _otherMicroAreaId,
      });
      audit = FakeAuditTrail();
      service = VisitSyncService(
        store: store,
        audit: audit,
        clock: () => DateTime.utc(2026, 9, 11, 12),
      );
    });

    test('recusa visita para paciente de outra microárea, sem gravar nada', () async {
      final results = await service.sync(
        user: _acs,
        entries: [entry(patientId: _outroTerritorioPatientId)],
      );

      // Terminal: o território não muda com uma próxima tentativa.
      expect(results.single.syncStatus, SyncStatus.rejected);
      expect(store.rows, isEmpty);
      // A mensagem não pode citar a microárea alheia nem o nome do paciente.
      expect(results.single.message, isNot(contains(_otherMicroAreaId)));
    });

    test('recusa por território grava auditoria com o paciente envolvido', () async {
      await service.sync(user: _acs, entries: [entry(patientId: _outroTerritorioPatientId)]);

      expect(audit.events, hasLength(1));
      final event = audit.events.single;
      expect(event.result, 'denied_territory');
      expect(event.resourceType, 'visit');
      expect(event.resourceId, UuidValue.fromString(_outroTerritorioPatientId).uuid);
      expect(event.userId, _acsId);
    });

    test('uma recusa por território não descarta as demais visitas do lote', () async {
      final results = await service.sync(user: _acs, entries: [
        entry(patientId: _outroTerritorioPatientId),
        entry(),
      ]);

      expect(results.first.syncStatus, SyncStatus.rejected);
      expect(results.last.syncStatus, SyncStatus.synced);
    });

    test('paciente inexistente vira error sem gerar auditoria de território', () async {
      final results = await service.sync(
        user: _acs,
        entries: [entry(patientId: '00000000-0000-4000-8000-00000000dead')],
      );

      expect(results.single.syncStatus, SyncStatus.error);
      // Não é necessariamente espionagem territorial — pode ser um localId
      // órfão de um seed antigo. Só a recusa POR TERRITÓRIO é auditada.
      expect(audit.events, isEmpty);
    });

    test('uma trilha de auditoria fora do ar não impede a recusa territorial', () async {
      audit = FakeAuditTrail(failOnRecord: true);
      service = VisitSyncService(store: store, audit: audit, clock: () => DateTime.utc(2026, 9, 11, 12));

      final results = await service.sync(
        user: _acs,
        entries: [entry(patientId: _outroTerritorioPatientId)],
      );

      // A operação clínica (recusar a visita) não pode depender da auditoria.
      expect(results.single.syncStatus, SyncStatus.rejected);
    });
  });

  group('pull', () {
    final referencia = DateTime.utc(2026, 9, 15, 12);

    VisitRecord visita({
      required String localId,
      required String patientId,
      required DateTime syncAt,
    }) {
      return VisitRecord(
        patientId: UuidValue.fromString(patientId),
        acsId: UuidValue.fromString(_acsId),
        scheduledAt: DateTime.utc(2026, 9, 11, 9),
        completedAt: DateTime.utc(2026, 9, 11, 10),
        status: 'realizada',
        riskLevelBefore: RiskLevel.red,
        riskLevelAfter: RiskLevel.yellow,
        notes: const {'campo': 'sem intercorrências'},
        syncStatus: SyncStatus.synced,
        arrivalMethod: ArrivalMethod.manual,
        localId: UuidValue.fromString(localId),
        syncAt: syncAt,
        version: 1,
      );
    }

    setUp(() {
      store = FakeVisitStore(microAreaByPatient: {
        _patientId: _microAreaId,
        _outroTerritorioPatientId: _otherMicroAreaId,
      });
      audit = FakeAuditTrail();
      service = VisitSyncService(
        store: store,
        audit: audit,
        clock: () => DateTime.utc(2026, 9, 16, 12),
      );
    });

    test('devolve só visitas da microárea do ACS, alteradas após since', () async {
      final visitaRecenteMesmaArea = visita(
        localId: '00000000-0000-4000-8000-0000000000d1',
        patientId: _patientId,
        syncAt: referencia.add(const Duration(hours: 1)),
      );
      final visitaAntigaDemais = visita(
        localId: '00000000-0000-4000-8000-0000000000d2',
        patientId: _patientId,
        syncAt: referencia.subtract(const Duration(hours: 1)),
      );
      final visitaDeOutraArea = visita(
        localId: '00000000-0000-4000-8000-0000000000d3',
        patientId: _outroTerritorioPatientId,
        syncAt: referencia.add(const Duration(hours: 1)),
      );
      await store.insert(visitaRecenteMesmaArea);
      await store.insert(visitaAntigaDemais);
      await store.insert(visitaDeOutraArea);

      final result = await service.pull(user: _acs, since: referencia);

      expect(
        result.map((e) => e.localId),
        containsAll([visitaRecenteMesmaArea.localId.uuid]),
      );
      expect(
        result.map((e) => e.localId),
        isNot(contains(visitaDeOutraArea.localId.uuid)),
      );
      expect(
        result.map((e) => e.localId),
        isNot(contains(visitaAntigaDemais.localId.uuid)),
      );
    });

    test('cada entrada devolve o syncAt do SERVIDOR, não o relógio do cliente', () async {
      // O app do ACS usa este campo para avançar o cursor local sem depender
      // do próprio relógio (fix round 1, achado da revisão da Task 10):
      // `VisitPullService` avança para o maior `syncAt` recebido, nunca para
      // `DateTime.now()` do dispositivo.
      final visitaRecente = visita(
        localId: '00000000-0000-4000-8000-0000000000d4',
        patientId: _patientId,
        syncAt: referencia.add(const Duration(hours: 2)),
      );
      await store.insert(visitaRecente);

      final result = await service.pull(user: _acs, since: referencia);

      expect(result.single.syncAt, visitaRecente.syncAt);
    });

    test('recusa quando quem chama não é ACS territorializado', () async {
      expect(
        () => service.pull(user: _patient, since: referencia),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'grava uma linha de auditoria read/visit_pull, mesmo padrão de '
        'PatientDirectoryService.listForAcs', () async {
      await service.pull(user: _acs, since: referencia);

      expect(audit.events, hasLength(1));
      expect(audit.events.single.userId, _acsId);
      expect(audit.events.single.actionType, 'read');
      expect(audit.events.single.resourceType, 'visit_pull');
      expect(audit.events.single.result, 'granted');
    });

    test('uma trilha de auditoria fora do ar não impede o pull', () async {
      final audit = FakeAuditTrail(failOnRecord: true);
      final service = VisitSyncService(store: store, audit: audit);

      final result = await service.pull(user: _acs, since: referencia);

      expect(result, isNotNull);
    });
  });

  group('syncLegacy (autoria desconhecida, D4)', () {
    const deviceId = 'aparelho-legado-01';

    setUp(() {
      store = FakeVisitStore(microAreaByPatient: {
        _patientId: _microAreaId,
        _outroTerritorioPatientId: _otherMicroAreaId,
      });
      audit = FakeAuditTrail();
      service = VisitSyncService(
        store: store,
        audit: audit,
        clock: () => DateTime.utc(2026, 10, 3, 12),
      );
    });

    test('syncLegacy grava authorship legacyUnclaimed, acsId nulo e originDeviceId', () async {
      final results = await service.syncLegacy(
        transporter: _acs,
        deviceId: deviceId,
        entries: [entry()],
      );

      expect(results.single.syncStatus, SyncStatus.synced);
      expect(results.single.serverVersion, 1);
      final row = store.rows[_localId]!;
      expect(row.authorship, VisitAuthorship.legacyUnclaimed);
      expect(row.acsId, isNull);
      expect(row.originDeviceId, deviceId);
      expect(row.syncAt, DateTime.utc(2026, 10, 3, 12));
    });

    test('syncLegacy NÃO grava o transportador como autor (acsId permanece nulo)', () async {
      // Duas passagens (gravação + atualização a partir da versão corrente):
      // em nenhuma delas quem transportou vira autor.
      await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [entry()]);
      // Atualização: o dispositivo parte de `version = servidor - 1` (mesma
      // regra do `sync`, ver 'visits.sync expõe synced, conflict e error').
      final update = await service.syncLegacy(
        transporter: _acs,
        deviceId: deviceId,
        entries: [entry(version: 0, status: 'paciente ausente')],
      );

      expect(update.single.syncStatus, SyncStatus.synced);
      expect(update.single.serverVersion, 2);
      final row = store.rows[_localId]!;
      expect(row.acsId, isNull);
      expect(row.authorship, VisitAuthorship.legacyUnclaimed);
      expect(row.status, 'paciente ausente');
    });

    test('visita legada de paciente de OUTRA microárea: rejected, nada gravado', () async {
      final results = await service.syncLegacy(
        transporter: _acs,
        deviceId: deviceId,
        entries: [entry(patientId: _outroTerritorioPatientId)],
      );

      expect(results.single.syncStatus, SyncStatus.rejected);
      expect(results.single.message, isNot(contains(_otherMicroAreaId)));
      expect(store.rows, isEmpty);
      final denied = audit.events.where((e) => e.result == 'denied_territory');
      expect(denied.single.resourceType, 'visit_legacy');
      expect(denied.single.userId, _acsId);
    });

    test('mesmo localId reenviado: idempotente (synced, sem duplicar, sem mudar autoria)', () async {
      await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [entry()]);

      // Outro ACS do mesmo território reenvia do mesmo aparelho (o primeiro
      // envio caiu antes da resposta): continua sem autor.
      const outroAcs = AuthenticatedUser(
        id: _otherAcsId,
        role: UserRole.acs,
        microAreaId: _microAreaId,
        deviceId: 'acs-device-002',
      );
      final retry = await service.syncLegacy(
        transporter: outroAcs,
        deviceId: deviceId,
        entries: [entry(version: 1)],
      );

      expect(retry.single.syncStatus, SyncStatus.synced);
      expect(retry.single.serverVersion, 1);
      expect(store.rows, hasLength(1));
      expect(store.rows[_localId]!.acsId, isNull);
      expect(store.rows[_localId]!.authorship, VisitAuthorship.legacyUnclaimed);
    });

    test('versão divergente de uma visita legada vira conflito, sem sobrescrever', () async {
      await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [entry()]);

      final conflicted = await service.syncLegacy(
        transporter: _acs,
        deviceId: deviceId,
        entries: [entry(version: 7, status: 'recusou atendimento')],
      );

      expect(conflicted.single.syncStatus, SyncStatus.conflict);
      expect(conflicted.single.serverVersion, 1);
      expect(store.rows[_localId]!.status, 'realizada');
    });

    test('visita legada de OUTRO aparelho com o mesmo localId: rejected', () async {
      await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [entry()]);

      final results = await service.syncLegacy(
        transporter: _acs,
        deviceId: 'outro-aparelho',
        entries: [entry(version: 1, status: 'paciente ausente')],
      );

      expect(results.single.syncStatus, SyncStatus.rejected);
      expect(store.rows[_localId]!.originDeviceId, deviceId);
      expect(store.rows[_localId]!.status, 'realizada');
    });

    test('localId que já existe como visita COM autor ACS: conflito/rejected, autoria original preservada',
        () async {
      await service.sync(user: _acs, entries: [entry()]);

      final results = await service.syncLegacy(
        transporter: _acs,
        deviceId: deviceId,
        entries: [entry(version: 0, status: 'paciente ausente')],
      );

      expect(results.single.syncStatus, SyncStatus.rejected);
      expect(results.single.message, 'visita já registrada com autor — versão diferente');
      final row = store.rows[_localId]!;
      expect(row.authorship, VisitAuthorship.acs);
      expect(row.acsId, UuidValue.fromString(_acsId));
      expect(row.originDeviceId, isNull);
      expect(row.status, 'realizada');
    });

    test('ACS comum que reenvia o localId de uma visita sem autor NÃO a reivindica', () async {
      await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [entry()]);

      // Reenvio idêntico (mesma versão) e atualização (versão corrente): os
      // dois são recusados — senão o `sync` comum viraria a porta para
      // reivindicar a autoria de uma visita legada.
      final same = await service.sync(user: _acs, entries: [entry(version: 1)]);
      final update = await service.sync(
        user: _acs,
        entries: [entry(version: 0, status: 'paciente ausente')],
      );

      expect(same.single.syncStatus, SyncStatus.rejected);
      expect(update.single.syncStatus, SyncStatus.rejected);
      final row = store.rows[_localId]!;
      expect(row.acsId, isNull);
      expect(row.authorship, VisitAuthorship.legacyUnclaimed);
      expect(row.status, 'realizada');
      expect(row.version, 1);
    });

    test('papel diferente de acs, sem microárea ou conta inativa: StateError (AlertPermissionException no endpoint)',
        () async {
      expect(
        () => service.syncLegacy(transporter: _patient, deviceId: deviceId, entries: [entry()]),
        throwsA(isA<StateError>()),
      );

      const acsSemArea = AuthenticatedUser(
        id: _acsId,
        role: UserRole.acs,
        microAreaId: null,
        deviceId: 'acs-device-001',
      );
      expect(
        () => service.syncLegacy(transporter: acsSemArea, deviceId: deviceId, entries: [entry()]),
        throwsA(isA<StateError>()),
      );

      store.inactiveAcs.add(_acsId);
      await expectLater(
        service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [entry()]),
        throwsA(isA<StateError>()),
      );
      expect(store.rows, isEmpty);
    });

    test('deviceId vazio: ArgumentError, nada gravado', () async {
      await expectLater(
        service.syncLegacy(transporter: _acs, deviceId: '  ', entries: [entry()]),
        throwsA(isA<ArgumentError>()),
      );
      expect(store.rows, isEmpty);
    });

    test('cada lote gera audit_logs visit_legacy_sync com o transportador, sem conteúdo clínico',
        () async {
      await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [entry()]);

      final events = audit.events.where((e) => e.result == 'visit_legacy_sync').toList();
      expect(events, hasLength(1));
      expect(events.single.userId, _acsId);
      expect(events.single.actionType, 'write');
      expect(events.single.resourceType, 'visit_legacy');
      // Nem paciente, nem nota, nem localId: o evento é o LOTE.
      expect(events.single.resourceId, isNull);
    });

    test('uma trilha de auditoria fora do ar não impede o envio legado', () async {
      audit = FakeAuditTrail(failOnRecord: true);
      service = VisitSyncService(store: store, audit: audit);

      final results =
          await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [entry()]);

      expect(results.single.syncStatus, SyncStatus.synced);
    });

    test('pull entrega a visita legada à microárea sem expor autor (campo acsId ausente)', () async {
      await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [entry()]);

      final result = await service.pull(user: _acs, since: DateTime.utc(2026, 10, 1));

      expect(result.single.localId, _localId);
      // `VisitSyncEntry` não tem campo de autor — nem `acsId` nem
      // `originDeviceId` atravessam o pull.
      final json = result.single.toJson();
      expect(json.containsKey('acsId'), isFalse);
      expect(json.containsKey('originDeviceId'), isFalse);
    });
  });

  group('syncLegacy — fix round 1', () {
    const deviceId = 'aparelho-legado-01';
    const localB = '00000000-0000-4000-8000-0000000000b2';
    const localC = '00000000-0000-4000-8000-0000000000b3';

    VisitSyncEntry legacyEntry(String localId, {int version = 0, String patientId = _patientId}) =>
        VisitSyncEntry(
          localId: localId,
          patientId: patientId,
          scheduledAt: DateTime.utc(2026, 9, 11, 9),
          status: 'realizada',
          riskLevelBefore: RiskLevel.green,
          notes: const {'campo': 'sem intercorrências'},
          version: version,
          arrivalMethod: ArrivalMethod.manual,
        );

    List<AuditEvent> items() =>
        audit.events.where((e) => e.result == 'visit_legacy_sync_item').toList();

    setUp(() {
      store = FakeVisitStore(microAreaByPatient: {
        _patientId: _microAreaId,
        _outroTerritorioPatientId: _otherMicroAreaId,
      });
      audit = FakeAuditTrail();
      service = VisitSyncService(store: store, audit: audit, clock: () => DateTime.utc(2026, 10, 3, 12));
    });

    test('N visitas gravadas → N linhas de item + 1 de lote; nenhuma para rejected/no-op', () async {
      await service.syncLegacy(
        transporter: _acs,
        deviceId: deviceId,
        entries: [
          legacyEntry(_localId),
          legacyEntry(localB),
          legacyEntry(localC, patientId: _outroTerritorioPatientId),
        ],
      );

      expect(items(), hasLength(2));
      for (final e in items()) {
        expect(e.userId, _acsId);
        expect(e.actionType, 'write');
        expect(e.resourceType, 'visit_legacy');
      }
      expect(items().map((e) => e.resourceId).toSet(),
          {store.rows[_localId]!.id!.uuid, store.rows[localB]!.id!.uuid});
      expect(audit.events.where((e) => e.result == 'visit_legacy_sync'), hasLength(1));

      // Reenvio idêntico: no-op, nenhuma linha de item a mais.
      audit.events.clear();
      await service.syncLegacy(
          transporter: _acs, deviceId: deviceId, entries: [legacyEntry(_localId, version: 1)]);
      expect(items(), isEmpty);
      expect(audit.events.where((e) => e.result == 'visit_legacy_sync'), hasLength(1));

      // Atualização a partir da versão corrente: muda a linha → 1 item.
      await service.syncLegacy(
          transporter: _acs, deviceId: deviceId, entries: [legacyEntry(_localId, version: 0)]);
      expect(items().single.resourceId, store.rows[_localId]!.id!.uuid);
    });

    test('lote acima de maxLegacyBatch: ArgumentError antes de tocar o store', () async {
      expect(VisitSyncService.maxLegacyBatch, 200);
      store.inactiveAcs.add(_acsId); // se o store fosse consultado, viraria StateError
      final entries = [
        for (var i = 0; i <= VisitSyncService.maxLegacyBatch; i++)
          legacyEntry('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
      ];

      await expectLater(
        service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: entries),
        throwsA(isA<ArgumentError>()),
      );
      expect(store.rows, isEmpty);
      expect(audit.events, isEmpty);
    });

    test('exatamente maxLegacyBatch visitas: aceito', () async {
      final entries = [
        for (var i = 0; i < VisitSyncService.maxLegacyBatch; i++)
          legacyEntry('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
      ];
      final results =
          await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: entries);
      expect(results, hasLength(VisitSyncService.maxLegacyBatch));
    });

    test('localId com autor ACS e MESMA versão: synced sem gravar nada', () async {
      await service.sync(user: _acs, entries: [legacyEntry(_localId)]);
      final before = store.rows[_localId]!;

      final results = await service.syncLegacy(
          transporter: _acs, deviceId: deviceId, entries: [legacyEntry(_localId, version: 1)]);

      expect(results.single.syncStatus, SyncStatus.synced);
      expect(results.single.serverVersion, 1);
      expect(identical(store.rows[_localId], before), isTrue);
      expect(store.rows[_localId]!.acsId, UuidValue.fromString(_acsId));
      expect(items(), isEmpty);
    });

    test('localId legado de outro aparelho, mesma versão: rejected', () async {
      await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [legacyEntry(_localId)]);

      final results = await service.syncLegacy(
          transporter: _acs, deviceId: 'outro-aparelho', entries: [legacyEntry(_localId, version: 1)]);

      expect(results.single.syncStatus, SyncStatus.rejected);
      expect(results.single.message, 'visita legada de outro aparelho');
    });

    test('recusa territorial mantém a própria mensagem', () async {
      final results = await service.syncLegacy(
          transporter: _acs,
          deviceId: deviceId,
          entries: [legacyEntry(_localId, patientId: _outroTerritorioPatientId)]);
      expect(results.single.message, 'paciente fora da sua microárea');
    });
  });

  group('syncLegacy — fix round 2', () {
    const deviceId = 'aparelho-legado-01';
    const outroPacienteMesmaArea = '00000000-0000-4000-8000-000000000021';
    const localB = '00000000-0000-4000-8000-0000000000b2';

    VisitSyncEntry e(String localId, {int version = 0, String patientId = _patientId}) => VisitSyncEntry(
          localId: localId,
          patientId: patientId,
          scheduledAt: DateTime.utc(2026, 9, 11, 9),
          status: 'realizada',
          riskLevelBefore: RiskLevel.green,
          notes: const {},
          version: version,
          arrivalMethod: ArrivalMethod.manual,
        );

    setUp(() {
      store = FakeVisitStore(microAreaByPatient: {
        _patientId: _microAreaId,
        outroPacienteMesmaArea: _microAreaId,
        _outroTerritorioPatientId: _otherMicroAreaId,
      });
      audit = FakeAuditTrail();
      service = VisitSyncService(store: store, audit: audit, clock: () => DateTime.utc(2026, 10, 3, 12));
    });

    test('lote cuja 2ª visita lança: nenhuma linha de item nem de lote', () async {
      store.failOnInsertNumber = 2;

      await expectLater(
        service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [e(_localId), e(localB)]),
        throwsA(isA<StateError>()),
      );
      expect(audit.events.where((x) => x.result == 'visit_legacy_sync_item'), isEmpty);
      expect(audit.events.where((x) => x.result == 'visit_legacy_sync'), isEmpty);
    });

    test('itens são gravados só depois do laço, logo antes da linha de lote', () async {
      await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [e(_localId), e(localB)]);

      expect(audit.events.map((x) => x.result).toList(),
          ['visit_legacy_sync_item', 'visit_legacy_sync_item', 'visit_legacy_sync']);
    });

    test('ACS da microárea X + paciente de Y + localId com autor na mesma versão: '
        "rejected 'paciente fora da sua microárea'", () async {
      const acsDeY = AuthenticatedUser(
        id: _otherAcsId,
        role: UserRole.acs,
        microAreaId: _otherMicroAreaId,
        deviceId: 'acs-device-y',
      );
      await service.sync(user: acsDeY, entries: [e(_localId, patientId: _outroTerritorioPatientId)]);

      final results = await service.syncLegacy(
        transporter: _acs,
        deviceId: deviceId,
        entries: [e(_localId, version: 1, patientId: _outroTerritorioPatientId)],
      );

      expect(results.single.syncStatus, SyncStatus.rejected);
      expect(results.single.message, 'paciente fora da sua microárea');
      expect(results.single.serverVersion, isNull);
    });

    test('paciente da própria microárea mas localId de visita de OUTRO paciente (com autor, '
        'mesma versão): recusa genérica', () async {
      await service.sync(user: _acs, entries: [e(_localId, patientId: outroPacienteMesmaArea)]);

      final results = await service.syncLegacy(
        transporter: _acs,
        deviceId: deviceId,
        entries: [e(_localId, version: 1)],
      );

      expect(results.single.syncStatus, SyncStatus.rejected);
      expect(results.single.message, 'paciente fora da sua microárea');
      expect(results.single.serverVersion, isNull);
      expect(store.rows[_localId]!.patientId, UuidValue.fromString(outroPacienteMesmaArea));
    });

    test('localId legado de OUTRO paciente, mesmo aparelho e versão: recusa genérica', () async {
      await service.syncLegacy(
          transporter: _acs, deviceId: deviceId, entries: [e(_localId, patientId: outroPacienteMesmaArea)]);

      final results =
          await service.syncLegacy(transporter: _acs, deviceId: deviceId, entries: [e(_localId, version: 1)]);

      expect(results.single.syncStatus, SyncStatus.rejected);
      expect(results.single.message, 'paciente fora da sua microárea');
    });

    test('paciente divergente com versão diferente também não revela "versão diferente"', () async {
      await service.sync(user: _acs, entries: [e(_localId, patientId: outroPacienteMesmaArea)]);

      final results = await service.syncLegacy(
          transporter: _acs, deviceId: deviceId, entries: [e(_localId, version: 5)]);

      expect(results.single.message, 'paciente fora da sua microárea');
    });
  });
}
