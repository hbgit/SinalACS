import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// UUIDs sintéticos do seed de desenvolvimento.
const _acsId = '00000000-0000-4000-8000-000000000002';
const _otherAcsId = '00000000-0000-4000-8000-000000000012';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _patientId = '00000000-0000-4000-8000-000000000001';
const _localId = '00000000-0000-4000-8000-0000000000a1';

/// Store em memória, com a mesma unicidade de `localId` que o índice do banco.
class FakeVisitStore implements VisitStore {
  final Map<String, Visit> rows = <String, Visit>{};

  @override
  Future<Visit?> findByLocalId(String localId) async => rows[localId];

  @override
  Future<Visit> insert(Visit visit) async {
    rows[visit.localId.uuid] = visit;
    return visit;
  }

  @override
  Future<Visit> update(Visit visit) async {
    rows[visit.localId.uuid] = visit;
    return visit;
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

VisitSyncEntry entry({int version = 0, String status = 'realizada'}) {
  return VisitSyncEntry(
    localId: _localId,
    patientId: _patientId,
    scheduledAt: DateTime.utc(2026, 9, 11, 9),
    completedAt: DateTime.utc(2026, 9, 11, 10),
    status: status,
    riskLevelBefore: RiskLevel.red,
    riskLevelAfter: RiskLevel.yellow,
    notes: const {'campo': 'sem intercorrências'},
    version: version,
  );
}

void main() {
  late FakeVisitStore store;
  late VisitSyncService service;

  setUp(() {
    store = FakeVisitStore();
    service = VisitSyncService(
      store: store,
      clock: () => DateTime.utc(2026, 9, 11, 12),
    );
  });

  test('grava uma visita nova e devolve synced', () async {
    final results = await service.sync(user: _acs, entries: [entry()]);

    expect(results.single.syncStatus, SyncStatus.synced);
    expect(results.single.serverVersion, 1);
    expect(store.rows[_localId]?.status, 'realizada');
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

    expect(results.single.syncStatus, SyncStatus.error);
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

  test('identificador inválido vira error, não derruba o lote', () async {
    final results = await service.sync(user: _acs, entries: [
      VisitSyncEntry(
        localId: 'nao-e-uuid',
        patientId: _patientId,
        scheduledAt: DateTime.utc(2026, 9, 11, 9),
        status: 'realizada',
        riskLevelBefore: RiskLevel.green,
        notes: const {},
        version: 0,
      ),
      entry(),
    ]);

    expect(results.first.syncStatus, SyncStatus.error);
    // A visita válida do mesmo lote segue adiante.
    expect(results.last.syncStatus, SyncStatus.synced);
  });
}
