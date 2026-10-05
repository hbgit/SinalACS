// apps/acs/test/auth_bound_session_token_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/security/auth_bound_session_token_store.dart';
import 'package:sinalacs_acs/core/security/keystore_vault.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'support/counting_session_token_store.dart';

void main() {
  late FakeKeystoreVault vault;
  late MemorySessionTokenStore legacy;
  late AuthBoundSessionTokenStore store;

  setUp(() {
    vault = FakeKeystoreVault();
    legacy = MemorySessionTokenStore();
    store = AuthBoundSessionTokenStore(vault: vault, legacy: legacy);
  });

  test('write sela no cofre e mantém em RAM; read nunca abre prompt', () async {
    await store.write('tok-1');
    expect(vault.sealed[AuthBoundSessionTokenStore.alias], 'tok-1');
    expect(await store.read(), 'tok-1');
    expect(vault.unsealCalls, 0);
  });

  test('partida a frio: contains é true, read é null até unlock', () async {
    vault.sealed[AuthBoundSessionTokenStore.alias] = 'tok-1';
    final cold = AuthBoundSessionTokenStore(vault: vault, legacy: legacy);
    expect(await cold.contains(), isTrue);
    expect(await cold.read(), isNull);
    expect(await cold.unlock(reason: 'x'), SessionUnlock.unlocked);
    expect(await cold.read(), 'tok-1');
    expect(vault.unsealCalls, 1);
  });

  test(
    'cancelar o prompt NÃO apaga o token e permite tentar de novo',
    () async {
      vault.sealed[AuthBoundSessionTokenStore.alias] = 'tok-1';
      final cold = AuthBoundSessionTokenStore(vault: vault, legacy: legacy);
      vault.nextUnsealFailure = VaultFailure.cancelled;
      expect(await cold.unlock(reason: 'x'), SessionUnlock.cancelled);
      expect(await cold.contains(), isTrue);
      expect(await cold.unlock(reason: 'x'), SessionUnlock.unlocked);
    },
  );

  test('lockedOut e unavailable não devolvem token', () async {
    vault.sealed[AuthBoundSessionTokenStore.alias] = 'tok-1';
    final cold = AuthBoundSessionTokenStore(vault: vault, legacy: legacy);
    vault.nextUnsealFailure = VaultFailure.lockedOut;
    expect(await cold.unlock(reason: 'x'), SessionUnlock.lockedOut);
    vault.nextUnsealFailure = VaultFailure.unavailable;
    expect(await cold.unlock(reason: 'x'), SessionUnlock.unavailable);
    expect(await cold.read(), isNull);
  });

  test('chave invalidada (nova digital) apaga token e cofre', () async {
    vault.sealed[AuthBoundSessionTokenStore.alias] = 'tok-1';
    final cold = AuthBoundSessionTokenStore(vault: vault, legacy: legacy);
    vault.nextUnsealFailure = VaultFailure.invalidated;
    expect(await cold.unlock(reason: 'x'), SessionUnlock.unavailable);
    expect(await cold.contains(), isFalse);
    expect(vault.sealed, isEmpty);
  });

  test('aparelho sem suporte: token só em RAM, nada persistido', () async {
    vault.supported = false;
    await store.write('tok-1');
    expect(await store.read(), 'tok-1');
    expect(vault.sealed, isEmpty);
    final cold = AuthBoundSessionTokenStore(vault: vault, legacy: legacy);
    expect(await cold.contains(), isFalse);
  });

  test('falha ao selar degrada para RAM e não lança', () async {
    vault.failSeal = true;
    await store.write('tok-1');
    expect(await store.read(), 'tok-1');
    expect(vault.sealed, isEmpty);
  });

  test('clear apaga RAM, cofre e legado', () async {
    await store.write('tok-1');
    await legacy.write('velho');
    await store.clear();
    expect(await store.read(), isNull);
    expect(await store.contains(), isFalse);
    expect(await legacy.read(), isNull);
  });

  test('desbloqueios concorrentes abrem um único prompt', () async {
    vault.sealed[AuthBoundSessionTokenStore.alias] = 'tok-1';
    final cold = AuthBoundSessionTokenStore(vault: vault, legacy: legacy);
    final r = await Future.wait([
      cold.unlock(reason: 'x'),
      cold.unlock(reason: 'x'),
    ]);
    expect(r, [SessionUnlock.unlocked, SessionUnlock.unlocked]);
    expect(vault.unsealCalls, 1);
  });

  test('MemorySessionTokenStore: notRequired e contains', () async {
    final m = MemorySessionTokenStore('a');
    expect(await m.contains(), isTrue);
    expect(await m.unlock(reason: 'x'), SessionUnlock.notRequired);
  });

  test('token legado é selado sem prompt e o original é apagado', () async {
    await legacy.write('velho');
    expect(await store.contains(), isTrue);
    expect(vault.sealed[AuthBoundSessionTokenStore.alias], 'velho');
    expect(await legacy.read(), isNull);
    expect(vault.unsealCalls, 0);
    expect(await store.read(), isNull);
    expect(await store.unlock(reason: 'x'), SessionUnlock.unlocked);
    expect(await store.read(), 'velho');
  });

  test(
    'migração que falha preserva o legado (a sessão não se perde)',
    () async {
      vault.failSeal = true;
      await legacy.write('velho');
      expect(await store.contains(), isFalse);
      expect(await legacy.read(), 'velho');
    },
  );

  test(
    'migração roda antes do 1º unlock: contains() já sela o legado',
    () async {
      await legacy.write('velho');
      await store.contains();
      expect(vault.sealed[AuthBoundSessionTokenStore.alias], 'velho');
      expect(await legacy.read(), isNull);
    },
  );

  test(
    'app morto entre selar e apagar o legado: o legado é descartado',
    () async {
      vault.sealed[AuthBoundSessionTokenStore.alias] = 'velho';
      await legacy.write('velho');
      expect(await store.contains(), isTrue);
      expect(await legacy.read(), isNull);
    },
  );

  test('contains() é leve após a migração: não relê o legado', () async {
    final counting = CountingSessionTokenStore();
    final s = AuthBoundSessionTokenStore(vault: vault, legacy: counting);
    await s.contains();
    final reads = counting.reads;
    await s.contains();
    await s.contains();
    expect(counting.reads, reads);
  });

  test(
    'migração que falhou não liga o flag: a próxima contains() tenta de novo',
    () async {
      vault.failSeal = true;
      await legacy.write('velho');
      expect(await store.contains(), isFalse);
      vault.failSeal = false;
      expect(await store.contains(), isTrue);
      expect(vault.sealed[AuthBoundSessionTokenStore.alias], 'velho');
    },
  );
}
