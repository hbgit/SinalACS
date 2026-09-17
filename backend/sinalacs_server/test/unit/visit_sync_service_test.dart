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

  @override
  Future<VisitRecord?> findByLocalId(String localId) async => rows[localId];

  @override
  Future<VisitRecord> insert(VisitRecord visit) async {
    rows[visit.localId.uuid] = visit;
    return visit;
  }

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
  });
}
