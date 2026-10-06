import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/security/upload_token_store.dart';
import 'package:sinalacs_acs/core/services/deferred_flush_service.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fakes.dart';

/// Envio diferido (D4/D7 do plano 2026-10-03): o legado sobe pela sessão atual
/// só como transporte; a fila de cada ACS que saiu sobe com o token DELE. Nada
/// sai do aparelho antes do `synced`. Ids e pacientes sintéticos.
void main() {
  const acsA = 'acs-a';
  const acsB = 'acs-b';
  const acsC = 'acs-c';
  const aparelho = 'aparelho-sintetico-1';

  OfflineVisitRecord visita(String localId, {int n = 1}) =>
      OfflineVisitRecord(localId: localId, patientId: syntheticPatientId(n), risk: 'green', status: 'PENDENTE');

  AuthSession sessao(String userId) => AuthSession(
        accessToken: 'jwt-de-$userId',
        tokenType: 'Bearer',
        userId: userId,
        role: 'acs',
        microAreaId: seedMicroAreaId,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      );

  late FakeAcsBackend backend;
  late MemoryUploadTokenStore tokens;
  late InMemoryVisitStorage storage;

  DeferredFlushService servico({VisitStorage? sobre}) => DeferredFlushService(
        backend: backend,
        storage: sobre ?? storage,
        tokens: tokens,
        deviceIds: MemoryDeviceIdStore(aparelho),
      );

  List<String> ids(List<OfflineVisitRecord> visitas) => [for (final v in visitas) v.localId];

  setUp(() {
    backend = FakeAcsBackend();
    tokens = MemoryUploadTokenStore();
    storage = InMemoryVisitStorage();
  });

  group('legado (quarentena)', () {
    test('legado sobe pela sessão atual e SAI do aparelho só depois do synced', () async {
      storage = InMemoryVisitStorage(legacyVisits: [visita('leg-1'), visita('leg-2')]);
      backend.session = sessao(acsB);
      // Primeiro a rede cai: nada sai do aparelho.
      backend.legacyFailure = const BackendFailure('Sem conexão com o servidor.');

      final falhou = await servico().flushAll();
      expect(ids(await storage.legacy.load()), ['leg-1', 'leg-2']);
      expect(falhou.sent, 0);
      expect(falhou.remaining, 2);

      backend.legacyFailure = null;
      final report = await servico().flushAll();

      expect(backend.legacyBatches, hasLength(2));
      final lote = backend.legacyBatches.last;
      expect(lote.transportUserId, acsB, reason: 'a sessão atual só transporta');
      expect(lote.deviceId, aparelho);
      expect([for (final e in lote.visits) e.localId], ['leg-1', 'leg-2']);
      expect(await storage.legacy.load(), isEmpty);
      expect(report.sent, 2);
      expect(report.remaining, 0);
      expect(backend.deferredBatches, isEmpty, reason: 'legado nunca vai com token de envio');
    });

    test('sem sessão, o legado não sobe e continua contado', () async {
      storage = InMemoryVisitStorage(legacyVisits: [visita('leg-1')]);

      final report = await servico().flushAll();

      expect(backend.legacyBatches, isEmpty);
      expect(report.remaining, 1);
      expect(ids(await storage.legacy.load()), ['leg-1']);
    });

    test('legado de outra microárea: rejected → continua em quarentena', () async {
      storage = InMemoryVisitStorage(legacyVisits: [visita('leg-fora'), visita('leg-ok')]);
      backend.session = sessao(acsB);
      backend.legacyResultFor = (e) => e.localId == 'leg-fora'
          ? VisitSyncResult(localId: e.localId, syncStatus: SyncStatus.rejected, message: 'paciente fora da sua microárea')
          : VisitSyncResult(localId: e.localId, syncStatus: SyncStatus.synced, serverVersion: 1);

      final report = await servico().flushAll();

      expect(ids(await storage.legacy.load()), ['leg-fora']);
      expect(report.sent, 1);
      expect(report.remaining, 1);
      expect(report.needsReview, 0, reason: 'território alheio não é caso de revisão');
    });

    test("'versão diferente' fica em quarentena e é contada como revisão", () async {
      storage = InMemoryVisitStorage(legacyVisits: [visita('leg-versao')]);
      backend.session = sessao(acsB);
      backend.legacyResultFor = (e) => VisitSyncResult(
            localId: e.localId,
            syncStatus: SyncStatus.rejected,
            message: 'visita já registrada com autor — versão diferente',
          );

      final report = await servico().flushAll();

      expect(ids(await storage.legacy.load()), ['leg-versao']);
      expect(report.needsReview, 1);
      expect(report.remaining, 1);
    });

    test('error por visita: fica para a próxima', () async {
      storage = InMemoryVisitStorage(legacyVisits: [visita('leg-1')]);
      backend.session = sessao(acsB);
      backend.legacyResultFor =
          (e) => VisitSyncResult(localId: e.localId, syncStatus: SyncStatus.error, message: 'paciente desconhecido');

      final report = await servico().flushAll();

      expect(ids(await storage.legacy.load()), ['leg-1']);
      expect(report.remaining, 1);
    });

    test('lotes de no máximo 100 (o servidor recusa acima de 200)', () async {
      storage = InMemoryVisitStorage(legacyVisits: [for (var i = 0; i < 230; i++) visita('leg-$i', n: i + 1)]);
      backend.session = sessao(acsB);

      final report = await servico().flushAll();

      expect([for (final l in backend.legacyBatches) l.visits.length], [100, 100, 30]);
      expect(report.sent, 230);
      expect(await storage.legacy.load(), isEmpty);
    });

    test('app morto depois do 200 e antes de apagar: o reenvio volta synced e a linha é apagada', () async {
      final falha = _RemocaoLegadaFalhaUmaVez(InMemoryVisitStorage(legacyVisits: [visita('leg-1')]));
      backend.session = sessao(acsB);

      final primeiro = await servico(sobre: falha).flushAll();
      expect(ids(await falha.legacy.load()), ['leg-1'], reason: 'a remoção falhou: a linha continua');
      expect(primeiro.remaining, 1);

      final segundo = await servico(sobre: falha).flushAll();
      expect([for (final l in backend.legacyBatches) l.visits.single.localId], ['leg-1', 'leg-1']);
      expect(await falha.legacy.load(), isEmpty);
      expect(segundo.remaining, 0);
    });
  });

  group('fila de quem saiu (token de envio)', () {
    test('fila de A sobe com o token de A mesmo com B logado, e a autoria enviada é a de A', () async {
      await storage.forOwner(acsA).save([visita('a-1'), visita('a-2')]);
      await storage.forOwner(acsB).save([visita('b-1')]);
      await tokens.write(acsA, 'upload-a');
      await tokens.write(acsB, 'upload-b');
      backend.session = sessao(acsB);

      final report = await servico().flushAll();

      expect(backend.deferredBatches, hasLength(1));
      final lote = backend.deferredBatches.single;
      expect(lote.uploadToken, 'upload-a', reason: 'a autoria vem do token: o servidor grava A como autor');
      expect(lote.deviceId, aparelho);
      expect([for (final e in lote.visits) e.localId], ['a-1', 'a-2']);
      expect(backend.syncedVisitBatches, isEmpty, reason: 'nada de A sai pela sessão de B');
      expect(await storage.forOwner(acsA).load(), isEmpty);
      // A fila de B (dono da sessão) é do painel: o serviço não a envia.
      expect(ids(await storage.forOwner(acsB).load()), ['b-1']);
      expect(await tokens.read(acsB), 'upload-b', reason: 'o token do dono da sessão não é revogado');
      expect(report.sent, 2);
      expect(report.remaining, 1, reason: 'a visita de B continua no aparelho');
    });

    test('depois que a fila de A zera, o token de A é revogado no servidor e apagado do Keystore', () async {
      await storage.forOwner(acsA).save([visita('a-1')]);
      await tokens.write(acsA, 'upload-a');

      final report = await servico().flushAll();

      expect(backend.revokedUploadTokens, ['upload-a']);
      expect(await tokens.read(acsA), isNull);
      expect(await tokens.owners(), isEmpty);
      expect(report.remaining, 0);
    });

    test('dono sem visita nenhuma: token revogado na hora', () async {
      await tokens.write(acsA, 'upload-a');

      await servico().flushAll();

      expect(backend.deferredBatches, isEmpty);
      expect(backend.revokedUploadTokens, ['upload-a']);
      expect(await tokens.read(acsA), isNull);
    });

    test('recusada em definitivo fica visível a A e o token de A continua', () async {
      await storage.forOwner(acsA).save([visita('a-1'), visita('a-2')]);
      await tokens.write(acsA, 'upload-a');
      backend.deferredResultFor = (e) => e.localId == 'a-1'
          ? VisitSyncResult(localId: e.localId, syncStatus: SyncStatus.rejected, message: 'paciente fora da sua microárea')
          : VisitSyncResult(localId: e.localId, syncStatus: SyncStatus.synced, serverVersion: 1);

      final report = await servico().flushAll();

      final restantes = await storage.forOwner(acsA).load();
      expect(ids(restantes), ['a-1']);
      expect(restantes.single.rejectionReason, 'paciente fora da sua microárea');
      expect(backend.revokedUploadTokens, isEmpty);
      expect(await tokens.read(acsA), 'upload-a');
      expect(report.remaining, 1);
    });

    test('erro de rede no meio: nada é apagado; o próximo flushAll reenvia o mesmo localId (idempotente)', () async {
      await storage.forOwner(acsA).save([visita('a-1'), visita('a-2')]);
      await tokens.write(acsA, 'upload-a');
      backend.deferredFailure = const BackendFailure('Sem conexão com o servidor.');

      final falhou = await servico().flushAll();

      expect(ids(await storage.forOwner(acsA).load()), ['a-1', 'a-2']);
      expect(await tokens.read(acsA), 'upload-a');
      expect(backend.revokedUploadTokens, isEmpty);
      expect(falhou.remaining, 2);
      expect(falhou.blockedOwners, isEmpty, reason: 'rede não é bloqueio');

      backend.deferredFailure = null;
      final report = await servico().flushAll();

      expect([for (final l in backend.deferredBatches) [for (final e in l.visits) e.localId]], [
        ['a-1', 'a-2'],
        ['a-1', 'a-2'],
      ]);
      expect(await storage.forOwner(acsA).load(), isEmpty);
      expect(report.remaining, 0);
    });

    test('token de A recusado (vencido/revogado): a fila de A permanece, A entra em blockedOwners', () async {
      await storage.forOwner(acsA).save([visita('a-1')]);
      await tokens.write(acsA, 'upload-a');
      backend.refusedUploadTokens.add('upload-a');

      final report = await servico().flushAll();

      expect(ids(await storage.forOwner(acsA).load()), ['a-1']);
      expect(report.blockedOwners, [acsA]);
      expect(report.remaining, 1);
      expect(await tokens.read(acsA), isNull, reason: 'o servidor disse que o token morreu');
      expect(backend.revokedUploadTokens, isEmpty);
    });

    test('token presente mas fora do índice: o dono com visitas é achado pelo disco e sobe com o token dele',
        () async {
      await storage.forOwner(acsA).save([visita('a-1')]);
      await storage.forOwner(acsB).save([visita('b-1')]);
      final semIndice = _IndicePerdido({acsA: 'upload-a', acsB: 'upload-b'});
      backend.session = sessao(acsB);

      final report = await DeferredFlushService(
        backend: backend,
        storage: storage,
        tokens: semIndice,
        deviceIds: MemoryDeviceIdStore(aparelho),
      ).flushAll();

      expect(backend.deferredBatches, hasLength(1));
      expect(backend.deferredBatches.single.uploadToken, 'upload-a');
      expect(await storage.forOwner(acsA).load(), isEmpty);
      expect(report.blockedOwners, isEmpty);
      expect(semIndice.reparados, [acsA], reason: 'o índice é reparado; o dono da sessão não é lido');
      expect(semIndice.lidos, isNot(contains(acsB)));
    });

    test('dono com visitas e sem token: bloqueado, nada enviado', () async {
      await storage.forOwner(acsA).save([visita('a-1')]);

      final report = await servico().flushAll();

      expect(backend.deferredBatches, isEmpty);
      expect(report.blockedOwners, [acsA]);
      expect(report.remaining, 1);
    });

    test('app morto depois do 200 e antes de apagar: o reenvio do mesmo localId volta synced e a linha é apagada',
        () async {
      final falha = _GravacaoDoDonoFalhaUmaVez(storage);
      await storage.forOwner(acsA).save([visita('a-1')]);
      await tokens.write(acsA, 'upload-a');

      final primeiro = await servico(sobre: falha).flushAll();
      expect(ids(await storage.forOwner(acsA).load()), ['a-1'], reason: 'o 200 chegou, mas o disco não foi limpo');
      expect(primeiro.remaining, 1);
      expect(primeiro.sent, 0, reason: 'sent conta só o que saiu do aparelho');
      expect(await tokens.read(acsA), 'upload-a', reason: 'ainda há visita: o token fica');

      final segundo = await servico(sobre: falha).flushAll();
      expect([for (final l in backend.deferredBatches) l.visits.single.localId], ['a-1', 'a-1']);
      expect(await storage.forOwner(acsA).load(), isEmpty);
      expect(segundo.remaining, 0);
      expect(segundo.sent, 1);
      expect(await tokens.read(acsA), isNull);
    });

    test('token recusado durante novo login de A: o token NOVO de A não é apagado', () async {
      await storage.forOwner(acsA).save([visita('a-1')]);
      await tokens.write(acsA, 'upload-a');
      final gate = backend.deferredGate = Completer<void>();

      final voo = servico().flushAll();
      await pumpEventQueue();
      // A entra de novo neste aparelho: o login grava um token novo, e o
      // servidor revoga o anterior (mesmo usuário + aparelho).
      await tokens.write(acsA, 'upload-a-novo');
      backend.refusedUploadTokens.add('upload-a');
      gate.complete();
      final report = await voo;

      expect(report.blockedOwners, [acsA]);
      expect(await tokens.read(acsA), 'upload-a-novo');
      expect(ids(await storage.forOwner(acsA).load()), ['a-1']);
    });

    test('fila vazia revogada enquanto A entra de novo: o token NOVO de A não é apagado', () async {
      await tokens.write(acsA, 'upload-a');
      final gate = backend.revokeGate = Completer<void>();

      final voo = servico().flushAll();
      await pumpEventQueue();
      await tokens.write(acsA, 'upload-a-novo');
      gate.complete();
      await voo;

      expect(backend.revokedUploadTokens, ['upload-a']);
      expect(await tokens.read(acsA), 'upload-a-novo');
    });

    test('flushAll nunca envia visita de A com o token de B (verifica o token usado por lote)', () async {
      await storage.forOwner(acsA).save([for (var i = 0; i < 230; i++) visita('a-$i', n: i + 1)]);
      await storage.forOwner(acsC).save([visita('c-1'), visita('c-2')]);
      await tokens.write(acsA, 'upload-a');
      await tokens.write(acsC, 'upload-c');
      backend.session = sessao(acsB);

      final report = await servico().flushAll();

      final dono = {'upload-a': 'a-', 'upload-c': 'c-'};
      for (final lote in backend.deferredBatches) {
        final prefixo = dono[lote.uploadToken]!;
        expect(lote.visits.every((e) => e.localId.startsWith(prefixo)), isTrue,
            reason: 'lote com ${lote.uploadToken} levou visita de outro dono');
        expect(lote.visits.length, lessThanOrEqualTo(100));
      }
      expect([
        for (final l in backend.deferredBatches)
          if (l.uploadToken == 'upload-a') l.visits.length
      ], [100, 100, 30]);
      expect(report.sent, 232);
      expect(backend.revokedUploadTokens, unorderedEquals(['upload-a', 'upload-c']));
    });

    test('A volta a ser a sessão atual: o serviço não envia a fila dela (é do painel)', () async {
      await storage.forOwner(acsA).save([visita('a-1')]);
      await tokens.write(acsA, 'upload-a');
      backend.session = sessao(acsA);

      final report = await servico().flushAll();

      expect(backend.deferredBatches, isEmpty);
      expect(backend.revokedUploadTokens, isEmpty);
      expect(report.blockedOwners, isEmpty);
      expect(report.remaining, 1);
    });

    test('A entra enquanto o envio de A está em voo: a visita nova de A não se perde', () async {
      await storage.forOwner(acsA).save([visita('a-1')]);
      await tokens.write(acsA, 'upload-a');
      final gate = backend.deferredGate = Completer<void>();

      final voo = servico().flushAll();
      await pumpEventQueue();
      // O painel de A grava uma visita nova enquanto o lote está no servidor.
      await storage.forOwner(acsA).save([visita('a-1'), visita('a-novo')]);
      gate.complete();
      await voo;

      expect(ids(await storage.forOwner(acsA).load()), ['a-novo']);
      expect(await tokens.read(acsA), 'upload-a');
    });
  });

  test('flushAll simultâneos viram uma só execução (single-flight)', () async {
    await storage.forOwner(acsA).save([visita('a-1')]);
    await tokens.write(acsA, 'upload-a');
    final gate = backend.deferredGate = Completer<void>();
    final service = servico();

    final primeiro = service.flushAll();
    final segundo = service.flushAll();
    await pumpEventQueue();
    gate.complete();
    final relatorios = await Future.wait([primeiro, segundo]);

    expect(backend.deferredBatches, hasLength(1));
    expect(identical(relatorios[0], relatorios[1]), isTrue);

    // Terminada a execução, uma nova chamada roda de novo.
    backend.deferredGate = null;
    await storage.forOwner(acsA).save([visita('a-2')]);
    await tokens.write(acsA, 'upload-a2');
    await service.flushAll();
    expect(backend.deferredBatches, hasLength(2));
  });

  test('flushAll nunca lança: falha do Keystore vira relatório', () async {
    await storage.forOwner(acsA).save([visita('a-1')]);
    final service = DeferredFlushService(
      backend: backend,
      storage: storage,
      tokens: _TokensQueFalham(),
      deviceIds: MemoryDeviceIdStore(aparelho),
    );

    final report = await service.flushAll();

    expect(report.remaining, 1);
    expect(backend.deferredBatches, isEmpty);
  });

  test('pendingElsewhere conta outros donos + legado e não expõe conteúdo', () async {
    storage = InMemoryVisitStorage(legacyVisits: [visita('leg-1'), visita('leg-2')]);
    await storage.forOwner(acsA).save([visita('a-1'), visita('a-2'), visita('a-3')]);
    await storage.forOwner(acsB).save([visita('b-1')]);
    await storage.forOwner(acsC).save([visita('c-1')]);

    final int contagem = await servico().pendingElsewhere(acsB);

    expect(contagem, 3 + 1 + 2);
    expect(backend.legacyBatches, isEmpty);
    expect(backend.deferredBatches, isEmpty);
  });
}

/// `LegacyVisitStore.remove` falha uma vez, como o app morto depois do 200.
class _RemocaoLegadaFalhaUmaVez implements VisitStorage {
  _RemocaoLegadaFalhaUmaVez(this._inner) : legacy = _LegadoFalha(_inner.legacy);

  final VisitStorage _inner;

  @override
  final LegacyVisitStore legacy;

  @override
  VisitStore forOwner(String ownerId) => _inner.forOwner(ownerId);

  @override
  Future<Map<String, int>> countsByOwner() => _inner.countsByOwner();

  @override
  Future<void> wipeAllData() => _inner.wipeAllData();
}

class _LegadoFalha implements LegacyVisitStore {
  _LegadoFalha(this._inner);

  final LegacyVisitStore _inner;
  bool _falhou = false;

  @override
  Future<List<OfflineVisitRecord>> load() => _inner.load();

  @override
  Future<void> remove(Iterable<String> localIds) async {
    if (!_falhou) {
      _falhou = true;
      throw StateError('processo morto');
    }
    await _inner.remove(localIds);
  }
}

/// A primeira gravação da fila de um dono falha (o 200 chegou, o disco não
/// foi limpo).
class _GravacaoDoDonoFalhaUmaVez implements VisitStorage {
  _GravacaoDoDonoFalhaUmaVez(this._inner);

  final VisitStorage _inner;
  bool _falhou = false;

  @override
  LegacyVisitStore get legacy => _inner.legacy;

  @override
  Future<Map<String, int>> countsByOwner() => _inner.countsByOwner();

  @override
  VisitStore forOwner(String ownerId) => _DonoFalha(this, _inner.forOwner(ownerId));

  @override
  Future<void> wipeAllData() => _inner.wipeAllData();
}

class _DonoFalha implements VisitStore {
  _DonoFalha(this._dono, this._inner);

  final _GravacaoDoDonoFalhaUmaVez _dono;
  final VisitStore _inner;

  @override
  Future<List<OfflineVisitRecord>> load() => _inner.load();

  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    if (!_dono._falhou) {
      _dono._falhou = true;
      throw StateError('processo morto');
    }
    await _inner.save(visits);
  }
}

class _TokensQueFalham implements UploadTokenStore {
  @override
  Future<void> clear(String ownerId) => Future.error(StateError('Keystore'));

  @override
  Future<List<String>> owners() => Future.error(StateError('Keystore'));

  @override
  Future<String?> read(String ownerId) => Future.error(StateError('Keystore'));

  @override
  Future<void> write(String ownerId, String token) => Future.error(StateError('Keystore'));

  @override
  Future<void> repairIndex(String ownerId) => Future.error(StateError('Keystore'));

  @override
  Future<void> clearAll({Iterable<String> alsoOwners = const <String>[]}) => Future.error(StateError('Keystore'));

  @override
  Future<bool> compareAndClear(String ownerId, String expected) => Future.error(StateError('Keystore'));
}

/// Tokens guardados cujo ÍNDICE se perdeu: `owners()` não lista ninguém, mas
/// a leitura por chave funciona.
class _IndicePerdido implements UploadTokenStore {
  _IndicePerdido(this._tokens);

  final Map<String, String> _tokens;
  final List<String> lidos = <String>[];
  final List<String> reparados = <String>[];

  @override
  Future<List<String>> owners() async => const <String>[];

  @override
  Future<String?> read(String ownerId) async {
    lidos.add(ownerId);
    return _tokens[ownerId];
  }

  @override
  Future<void> write(String ownerId, String token) async => _tokens[ownerId] = token;

  @override
  Future<void> clear(String ownerId) async => _tokens.remove(ownerId);

  @override
  Future<void> repairIndex(String ownerId) async => reparados.add(ownerId);

  @override
  Future<void> clearAll({Iterable<String> alsoOwners = const <String>[]}) async => _tokens.clear();

  @override
  Future<bool> compareAndClear(String ownerId, String expected) async {
    if (_tokens[ownerId] != expected) return false;
    _tokens.remove(ownerId);
    return true;
  }
}
