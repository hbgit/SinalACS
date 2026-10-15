# Biometria amarrada ao Keystore (refresh token do ACS) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o refresh token do ACS só poder ser decifrado depois de uma autenticação biométrica/PIN **imposta pelo Keystore (TEE)**, e não apenas por um portão de interface.

**Architecture:** Criptografia de envelope. Par RSA-2048 (OAEP) no Android Keystore com `setUserAuthenticationRequired(true)`. A cada `seal` gera-se uma chave AES-256-GCM descartável: ela cifra o refresh token (sem limite de tamanho) e é ela própria cifrada com a **chave pública** RSA (sem prompt: a renovação a cada 15 min grava o token rotacionado em silêncio). O blob salvo é `Base64(IV).Base64(chaveAES_RSA).Base64(token_AES)`. A **decifra** exige `BiometricPrompt` com `CryptoObject` sobre a chave privada RSA (libera a AES, que decifra o token), uma vez por partida a frio. Depois do desbloqueio o token fica em RAM (como já fica a sessão). Um plugin Kotlin próprio (`MethodChannel`) faz isso; o lado Dart é uma `SessionTokenStore` nova (`AuthBoundSessionTokenStore`) que nunca abre prompt dentro de `read()`.

**Tech Stack:** Flutter/Dart (apps/acs), Kotlin + `androidx.biometric` 1.1.0, Android Keystore, `local_auth` 3.x (continua sendo o portão do `AppLockGate`), `flutter_test`.

**Spec:** `PROGRESS.md` §"Refresh token rotativo e desbloqueio biométrico do ACS" (Limite de desenho + Aberto (a)); `docs/superpowers/plans/2026-10-03-refresh-token-e-biometria-do-acs.md`; `spec/lgpd_design.md` §5.1; `spec/stack.md` (sem framework novo: é invólucro de API de plataforma).

## Global Constraints

- minSdk 24 (`apps/acs/android/app/build.gradle*`); `compileSdk` 36. A solução deve degradar, não quebrar, em API 24–29.
- Nunca registrar token, chave ou mensagem de exceção do Keystore em log (LGPD-RF09).
- Falha fechada: qualquer erro/cancelamento do prompt **não** devolve o token.
- `BackendClient._exclusive` e a semântica de `read()` dentro dele não mudam: `read()` jamais abre UI.
- Rodar a migração do token legado **antes** do primeiro `_tryResume` (Task 4); se ela falhar, manter o legado (não deslogar).
- Fila de visitas por dono, token de envio diferido (`acs_upload_token|<userId>`) e chave do SQLCipher **ficam fora do escopo** (ver "Fora do escopo").
- Textos de UI em português; commits sem atribuição de IA (regra do repositório).
- Rodar `graphify update .` depois de modificar código.

## Review Focus

1. **Nova digital cadastrada invalida a chave** (`KeyPermanentlyInvalidatedException`): esperado = token apagado, volta ao login completo com "Sua sessão expirou. Entre novamente.", nunca laço de prompt. (Task 1, Task 3)
2. **Cancelar o prompt não apaga o token**: tentar de novo funciona; só invalidação/recusa do servidor apaga. (Task 1)
3. **Aparelho sem bloqueio de tela/biometria (ou API < 30 sem biometria forte)**: o token não é persistido (só RAM) e a partida a frio exige login completo. (Task 1, Task 4)
4. **Token legado já gravado no `flutter_secure_storage`** (instalações atuais): migra para a chave vinculada sem perder a sessão e apaga o original. (Task 4)
5. **Blob corrompido, truncado ou com GCM adulterado** (falha de tag): tratado como `unavailable`, nunca crash nem token parcial; tokens de qualquer tamanho cabem (envelope). (Task 3)
6. **Logout explícito**: apaga o blob e o par RSA do Keystore, sem chave órfã. (Task 5)
7. **Migração interrompida no meio** (app morto entre selar e apagar o legado): na próxima partida o legado ainda existe e o cofre também; apagar o legado sem perder a sessão. (Task 4)

---

## Arquivos

| Arquivo | Responsabilidade |
|---|---|
| `apps/acs/lib/core/security/session_token_store.dart` (modificar) | acrescenta `SessionUnlock`, `contains()` e `unlock()` à interface; `Memory` os implementa |
| `apps/acs/lib/core/security/keystore_vault.dart` (criar) | porta `KeystoreVault`, `VaultException`, duplo `FakeKeystoreVault` e `MethodChannelKeystoreVault` |
| `apps/acs/lib/core/security/auth_bound_session_token_store.dart` (criar) | `SessionTokenStore` com cache em RAM + cofre; migração do legado |
| `apps/acs/lib/core/security/secure_session_token_store.dart` (modificar) | `contains`/`unlock` (`notRequired`) no store legado |
| `apps/acs/lib/core/network/backend_client.dart` (modificar) | `unlockStoredSession`; `hasStoredSession` usa `contains()` |
| `apps/acs/lib/app/app.dart` (modificar `_tryResume`) | usa o prompt do cofre em vez do `gate.authenticate` quando o store o fornece |
| `apps/acs/android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/KeystoreVault.kt` (criar) | Keystore + `BiometricPrompt`/`CryptoObject` |
| `apps/acs/android/app/src/main/kotlin/.../MainActivity.kt` (modificar) | registra o canal |
| `apps/acs/android/app/build.gradle(.kts)` (modificar) | `androidx.biometric:biometric:1.1.0` |
| `apps/acs/lib/main.dart` (modificar) | monta `AuthBoundSessionTokenStore` |
| `scripts/qa/acs_keystore_bound_e2e.sh` (criar) | prova no emulador |
| `PROGRESS.md`, `apps/CLAUDE.md`, `CLAUDE.md`, `spec/lgpd_design.md` (modificar) | documentação |

## Fora do escopo (decisão, com motivo)

- **Chave do SQLCipher**: o banco abre antes do login e a fila grava com o app bloqueado (alerta chegando); exigir prompt por uso quebraria o offline-first. Segue no Keystore sem vínculo de usuário.
- **Token de envio diferido**: existe exatamente para subir visitas **sem** sessão (depois do "Sair"). Vinculá-lo a biometria o inutiliza.
- **iOS**: não existe.

---

### Task 1: Contrato Dart — porta do cofre e store vinculado

**Files:**
- Modify: `apps/acs/lib/core/security/session_token_store.dart`
- Create: `apps/acs/lib/core/security/keystore_vault.dart`
- Create: `apps/acs/lib/core/security/auth_bound_session_token_store.dart`
- Modify: `apps/acs/test/support/gated_session_token_store.dart`
- Test: `apps/acs/test/auth_bound_session_token_store_test.dart`

**Interfaces:**
- Produces: `enum SessionUnlock { unlocked, notRequired, cancelled, lockedOut, unavailable }`; em `SessionTokenStore`: `Future<bool> contains()` e `Future<SessionUnlock> unlock({required String reason})`; `abstract interface class KeystoreVault { Future<bool> get isSupported; Future<bool> contains(String alias); Future<void> seal(String alias, String plaintext); Future<String?> unseal(String alias, {required String reason}); Future<void> delete(String alias); }`; `enum VaultFailure { cancelled, lockedOut, invalidated, unavailable }`; `class VaultException implements Exception { const VaultException(this.failure); final VaultFailure failure; }`; `class FakeKeystoreVault implements KeystoreVault` (campos de teste: `supported`, `failSeal`, `nextUnsealFailure`, `unsealCalls` (prompts abertos), `readCalls` (consultas a `contains`, nunca abrem prompt), `sealed`); `class AuthBoundSessionTokenStore implements SessionTokenStore { AuthBoundSessionTokenStore({required KeystoreVault vault, required SessionTokenStore legacy}); static const alias = 'acs_refresh_token'; }`.

- [ ] **Step 1: Escrever os testes que falham**

```dart
// apps/acs/test/auth_bound_session_token_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/security/auth_bound_session_token_store.dart';
import 'package:sinalacs_acs/core/security/keystore_vault.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';

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

  test('cancelar o prompt NÃO apaga o token e permite tentar de novo', () async {
    vault.sealed[AuthBoundSessionTokenStore.alias] = 'tok-1';
    final cold = AuthBoundSessionTokenStore(vault: vault, legacy: legacy);
    vault.nextUnsealFailure = VaultFailure.cancelled;
    expect(await cold.unlock(reason: 'x'), SessionUnlock.cancelled);
    expect(await cold.contains(), isTrue);
    expect(await cold.unlock(reason: 'x'), SessionUnlock.unlocked);
  });

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
    final r = await Future.wait([cold.unlock(reason: 'x'), cold.unlock(reason: 'x')]);
    expect(r, [SessionUnlock.unlocked, SessionUnlock.unlocked]);
    expect(vault.unsealCalls, 1);
  });

  test('MemorySessionTokenStore: notRequired e contains', () async {
    final m = MemorySessionTokenStore('a');
    expect(await m.contains(), isTrue);
    expect(await m.unlock(reason: 'x'), SessionUnlock.notRequired);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/acs && flutter test test/auth_bound_session_token_store_test.dart`
Expected: FAIL — arquivos/tipos inexistentes.

- [ ] **Step 3: Implementar**

`session_token_store.dart` — acrescentar acima de `SessionTokenStore` e na interface:

```dart
/// Resultado do desbloqueio do token guardado. `notRequired`: este store não
/// tem prompt próprio (o chamador usa o portão de interface).
enum SessionUnlock { unlocked, notRequired, cancelled, lockedOut, unavailable }
```

Na interface acrescentar:

```dart
  /// `true` se há token guardado, **sem** decifrá-lo (nunca abre prompt).
  Future<bool> contains();

  /// Decifra o token guardado para a memória, abrindo o prompt do sistema se o
  /// store o exige. `read()` só enxerga o token depois disto.
  Future<SessionUnlock> unlock({required String reason});
```

Em `MemorySessionTokenStore`:

```dart
  @override
  Future<bool> contains() async => _token != null;

  @override
  Future<SessionUnlock> unlock({required String reason}) async => SessionUnlock.notRequired;
```

`gated_session_token_store.dart`: delegar `contains` e `unlock` a `_inner`.

`keystore_vault.dart`:

```dart
import 'package:flutter/services.dart';

enum VaultFailure { cancelled, lockedOut, invalidated, unavailable }

class VaultException implements Exception {
  const VaultException(this.failure);
  final VaultFailure failure;
  // Sem mensagem de propósito: nunca carregar detalhe do Keystore para logs.
  @override
  String toString() => 'VaultException($failure)';
}

/// Cofre cuja decifra exige autenticação do usuário imposta pelo Keystore.
abstract interface class KeystoreVault {
  Future<bool> get isSupported;
  Future<bool> contains(String alias);

  /// Cifra com a chave pública: NÃO abre prompt.
  Future<void> seal(String alias, String plaintext);

  /// Abre o prompt biométrico/PIN e decifra. `null` se não há blob.
  /// Lança [VaultException].
  Future<String?> unseal(String alias, {required String reason});

  Future<void> delete(String alias);
}

class MethodChannelKeystoreVault implements KeystoreVault {
  MethodChannelKeystoreVault([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('br.com.prismrr.sinalacs.acs/keystore_vault');

  final MethodChannel _channel;

  @override
  Future<bool> get isSupported async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> contains(String alias) async {
    try {
      return await _channel.invokeMethod<bool>('contains', {'alias': alias}) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> seal(String alias, String plaintext) async {
    try {
      await _channel.invokeMethod<void>('seal', {'alias': alias, 'plaintext': plaintext});
    } on PlatformException {
      throw const VaultException(VaultFailure.unavailable);
    }
  }

  @override
  Future<String?> unseal(String alias, {required String reason}) async {
    try {
      return await _channel.invokeMethod<String>('unseal', {'alias': alias, 'reason': reason});
    } on PlatformException catch (e) {
      throw VaultException(switch (e.code) {
        'cancelled' => VaultFailure.cancelled,
        'lockedOut' => VaultFailure.lockedOut,
        'invalidated' => VaultFailure.invalidated,
        _ => VaultFailure.unavailable,
      });
    } on MissingPluginException {
      throw const VaultException(VaultFailure.unavailable);
    }
  }

  @override
  Future<void> delete(String alias) async {
    try {
      await _channel.invokeMethod<void>('delete', {'alias': alias});
    } catch (_) {}
  }
}

/// Duplo de teste (RAM).
class FakeKeystoreVault implements KeystoreVault {
  bool supported = true;
  bool failSeal = false;
  VaultFailure? nextUnsealFailure;
  int unsealCalls = 0; // = unlockCalls: quantos prompts foram abertos
  int readCalls = 0; // quantas vezes `contains` foi consultado (nunca abre prompt)
  final Map<String, String> sealed = {};

  @override
  Future<bool> get isSupported async => supported;

  @override
  Future<bool> contains(String alias) async {
    readCalls++;
    return sealed.containsKey(alias);
  }

  @override
  Future<void> seal(String alias, String plaintext) async {
    if (failSeal) throw const VaultException(VaultFailure.unavailable);
    sealed[alias] = plaintext;
  }

  @override
  Future<String?> unseal(String alias, {required String reason}) async {
    unsealCalls++;
    final failure = nextUnsealFailure;
    if (failure != null) {
      nextUnsealFailure = null;
      if (failure == VaultFailure.invalidated) sealed.remove(alias);
      throw VaultException(failure);
    }
    return sealed[alias];
  }

  @override
  Future<void> delete(String alias) async => sealed.remove(alias);
}
```

`auth_bound_session_token_store.dart`:

```dart
import 'dart:async';

import 'keystore_vault.dart';
import 'session_token_store.dart';

/// Refresh token do ACS cuja decifra só acontece depois de uma autenticação
/// biométrica/PIN imposta pelo Keystore (TEE), não por um portão de interface.
///
/// - `write` cifra com a chave pública (sem prompt: a rotação de 15 min segue
///   silenciosa) e mantém o valor em RAM.
/// - `read` devolve só a RAM e **nunca** abre prompt (é chamado dentro de
///   `BackendClient._exclusive`).
/// - `unlock` é o único lugar que decifra, uma vez por partida a frio.
///
/// Sem suporte (sem bloqueio de tela, API < 30 sem biometria forte) ou com
/// falha ao selar, o token fica só em RAM: a próxima partida a frio exige login
/// completo. Nunca registre o valor em log.
class AuthBoundSessionTokenStore implements SessionTokenStore {
  AuthBoundSessionTokenStore({required KeystoreVault vault, required SessionTokenStore legacy})
      : _vault = vault,
        _legacy = legacy;

  static const alias = 'acs_refresh_token';

  final KeystoreVault _vault;
  final SessionTokenStore _legacy;
  String? _cache;
  Future<SessionUnlock>? _unlocking;
  // Ligado quando a migração do legado terminou (ou não havia legado): daí em
  // diante `contains()` só consulta o cofre, sem tocar no armazenamento legado.
  bool _migrated = false;

  @override
  Future<String?> read() async => _cache;

  @override
  Future<bool> contains() async {
    if (_cache != null) return true;
    if (!await _vault.isSupported) return false;
    if (!_migrated) await _migrateLegacy();
    return _vault.contains(alias);
  }

  @override
  Future<SessionUnlock> unlock({required String reason}) {
    if (_cache != null) return Future.value(SessionUnlock.unlocked);
    return _unlocking ??= _unlock(reason).whenComplete(() => _unlocking = null);
  }

  Future<SessionUnlock> _unlock(String reason) async {
    try {
      await _migrateLegacy();
      final token = await _vault.unseal(alias, reason: reason);
      if (token == null || token.isEmpty) return SessionUnlock.unavailable;
      _cache = token;
      return SessionUnlock.unlocked;
    } on VaultException catch (e) {
      switch (e.failure) {
        case VaultFailure.cancelled:
          return SessionUnlock.cancelled;
        case VaultFailure.lockedOut:
          return SessionUnlock.lockedOut;
        case VaultFailure.invalidated:
          // Nova digital cadastrada: a chave morreu, o token é irrecuperável.
          await _vault.delete(alias);
          return SessionUnlock.unavailable;
        case VaultFailure.unavailable:
          return SessionUnlock.unavailable;
      }
    }
  }

  @override
  Future<void> write(String token) async {
    _cache = token;
    _migrated = true; // o legado é apagado abaixo; nada mais a migrar
    try {
      if (await _vault.isSupported) {
        await _vault.seal(alias, token);
        await _legacy.clear();
        return;
      }
    } on VaultException {
      // Degrada para RAM.
    }
    // Sem cofre: não deixa um blob antigo ressuscitar um token já rotacionado.
    await _vault.delete(alias);
    await _legacy.clear();
  }

  @override
  Future<void> clear() async {
    _cache = null;
    await _vault.delete(alias);
    await _legacy.clear();
  }

  /// Instalações antigas guardam o token no `flutter_secure_storage`. Sela-o
  /// (sem prompt) e apaga o original; o `unseal` seguinte já pede biometria.
  Future<void> _migrateLegacy() async {
    if (_migrated) return;
    final old = await _legacy.read();
    if (old == null || old.isEmpty) {
      _migrated = true;
      return;
    }
    if (await _vault.contains(alias)) {
      await _legacy.clear();
      _migrated = true;
      return;
    }
    try {
      await _vault.seal(alias, old);
      await _legacy.clear();
      _migrated = true;
    } on VaultException {
      // Mantém o legado e NÃO liga o flag: a próxima chamada tenta de novo.
      // Melhor um token no Keystore comum que perder a sessão.
    }
  }
}
```

> Nota: no ramo de falha de `seal`, o `catch` cai no fim e executa `_vault.delete` + `_legacy.clear()`. Isto é intencional (token rotacionado novo não pode conviver com um blob velho); `write` de um login novo substitui o blob.

`secure_session_token_store.dart` — em `SecureStorageSessionTokenStore` acrescentar:

```dart
  @override
  Future<bool> contains() async => await read() != null;

  @override
  Future<SessionUnlock> unlock({required String reason}) async => SessionUnlock.notRequired;
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd apps/acs && flutter test test/auth_bound_session_token_store_test.dart && flutter analyze`
Expected: PASS; `analyze` pode apontar outros implementadores de `SessionTokenStore` (corrija com `contains`/`unlock` delegando, comportamento `notRequired`).

- [ ] **Step 5: Commit**

```bash
git add apps/acs/lib/core/security apps/acs/test
git commit -m "feat(acs): store do refresh token vinculado a um cofre do Keystore (contrato Dart)"
```

---

### Task 2: BackendClient e retomada a frio usam o prompt do cofre

**Files:**
- Modify: `apps/acs/lib/core/network/backend_client.dart` (interface `AcsBackend` ~l.80-100, stub ~l.216, `hasStoredSession` ~l.616, `resumeSession` ~l.625)
- Modify: `apps/acs/lib/app/app.dart` (`_tryResume`, ~l.722-770)
- Modify: `apps/acs/test/support/fakes.dart` (implementadores de `AcsBackend`)
- Test: `apps/acs/test/session_resume_test.dart`

**Interfaces:**
- Consumes: `SessionTokenStore.contains()/unlock()`, `SessionUnlock` (Task 1).
- Produces: `Future<SessionUnlock> AcsBackend.unlockStoredSession({required String reason})`.

- [ ] **Step 1: Testes que falham** (adicionar em `session_resume_test.dart`, usando os helpers já existentes do arquivo para montar o app com `biometricGate` falso e `BackendClient`)

```dart
testWidgets('store com prompt próprio: o cofre desbloqueia e o gate de UI NÃO é chamado',
    (tester) async {
  final vault = FakeKeystoreVault()..sealed[AuthBoundSessionTokenStore.alias] = 'tok-1';
  final store = AuthBoundSessionTokenStore(vault: vault, legacy: MemorySessionTokenStore());
  final gate = FakeBiometricGate(); // já existe em test/support/fakes.dart
  // monta app como nos testes vizinhos, passando tokenStore: store, biometricGate: gate
  // ...
  await tester.pumpAndSettle();
  expect(vault.unsealCalls, 1);
  expect(gate.authenticateCalls, 0);
  // e o painel abriu (mesma asserção dos testes vizinhos de retomada)
});

testWidgets('prompt do cofre cancelado: fica no login, token continua guardado', (tester) async {
  final vault = FakeKeystoreVault()
    ..sealed[AuthBoundSessionTokenStore.alias] = 'tok-1'
    ..nextUnsealFailure = VaultFailure.cancelled;
  // monta como acima
  await tester.pumpAndSettle();
  expect(find.text('Entrar'), findsOneWidget);
  expect(await store.contains(), isTrue);
});

testWidgets('chave invalidada: aviso de sessão expirada e login completo', (tester) async {
  final vault = FakeKeystoreVault()
    ..sealed[AuthBoundSessionTokenStore.alias] = 'tok-1'
    ..nextUnsealFailure = VaultFailure.invalidated;
  // monta como acima
  await tester.pumpAndSettle();
  expect(find.text('Sua sessão expirou. Entre novamente.'), findsOneWidget);
});
```

> Antes de escrever: abrir `test/session_resume_test.dart` e copiar o *setup* exato (nome do fake do gate, como o app é montado). O `BiometricGate` antigo mockava "pedir a digital"; com o cofre, essa responsabilidade passa ao `FakeKeystoreVault` (`unsealCalls`). Os nomes acima (`FakeBiometricGate`, `authenticateCalls`) devem ser conferidos nesse arquivo e em `test/support/fakes.dart`; ajuste para os nomes reais — a asserção é a mesma.

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/acs && flutter test test/session_resume_test.dart`
Expected: FAIL (`unlockStoredSession` inexistente).

- [ ] **Step 3: Implementar**

`AcsBackend`:

```dart
  /// Desbloqueia o refresh token guardado (prompt do Keystore, se o store o
  /// exige). `notRequired`: o chamador usa o portão de interface.
  Future<SessionUnlock> unlockStoredSession({required String reason});
```

Stub (`~l.216`): `Future<SessionUnlock> unlockStoredSession({required String reason}) async => SessionUnlock.notRequired;`. Implementar o mesmo nos fakes de `test/support/fakes.dart`.

`BackendClient`:

```dart
  @override
  Future<bool> get hasStoredSession async {
    try {
      return await _tokenStore.contains();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SessionUnlock> unlockStoredSession({required String reason}) async {
    try {
      return await _tokenStore.unlock(reason: reason);
    } catch (_) {
      return SessionUnlock.unavailable; // falha fechada
    }
  }
```

(Manter o `catch` original de `hasStoredSession` — ler o corpo atual antes de editar.) Em `resumeSession`, manter `if (await _tokenStore.read() == null) return null;` (agora só é não-nulo depois do `unlock`).

`app.dart` `_tryResume`: substituir o bloco `UnlockResult unlock; try { unlock = await gate.authenticate(...) ... }` por:

```dart
      var unlocked = false;
      final stored = await backend.unlockStoredSession(reason: 'Entrar no SinalACS');
      switch (stored) {
        case SessionUnlock.unlocked:
          unlocked = true;
        case SessionUnlock.notRequired:
          UnlockResult ui;
          try {
            ui = await gate.authenticate(reason: 'Entrar no SinalACS');
          } catch (_) {
            ui = UnlockResult.unavailable; // falha fechada
          }
          unlocked = ui == UnlockResult.unlocked;
        case SessionUnlock.cancelled || SessionUnlock.lockedOut || SessionUnlock.unavailable:
          unlocked = false;
      }
      if (!unlocked || !mounted) return;
```

Depois do bloco `resumeSession`, o ramo `kept = await backend.hasStoredSession` já mostra "Sua sessão expirou." quando o token sumiu (caso `invalidated`). Conferir que `_resumePrompting` é desligado no `finally` (já é).

- [ ] **Step 4: Rodar tudo do app**

Run: `cd apps/acs && flutter test && flutter analyze`
Expected: PASS (a suíte inteira; os testes antigos usam `MemorySessionTokenStore` → `notRequired` → caminho antigo do gate).

- [ ] **Step 5: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): retomada a frio desbloqueia o token pelo cofre quando o store o exige"
```

---

### Task 3: Plugin Kotlin — Keystore + BiometricPrompt/CryptoObject

**Files:**
- Create: `apps/acs/android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/KeystoreVault.kt`
- Modify: `apps/acs/android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/MainActivity.kt`
- Modify: `apps/acs/android/app/build.gradle` (ou `.kts`)
- Test: `apps/acs/test/keystore_vault_channel_test.dart`, `apps/acs/test/android_manifest_test.dart` (já existe; estender)

**Interfaces:**
- Produces: canal `br.com.prismrr.sinalacs.acs/keystore_vault` com métodos `isSupported`, `contains`, `seal`, `unseal`, `delete`; códigos de erro `cancelled`, `lockedOut`, `invalidated`, `unavailable` (os mesmos de `MethodChannelKeystoreVault`).

- [ ] **Step 1: Teste do canal (Dart) que falha**

```dart
// apps/acs/test/keystore_vault_channel_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/security/keystore_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('br.com.prismrr.sinalacs.acs/keystore_vault');
  final vault = MethodChannelKeystoreVault();

  void mock(Future<Object?> Function(MethodCall) h) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, h);

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  for (final entry in {
    'cancelled': VaultFailure.cancelled,
    'lockedOut': VaultFailure.lockedOut,
    'invalidated': VaultFailure.invalidated,
    'qualquer-outro': VaultFailure.unavailable,
  }.entries) {
    test('unseal traduz o código ${entry.key}', () async {
      mock((_) async => throw PlatformException(code: entry.key));
      expect(
        () => vault.unseal('a', reason: 'x'),
        throwsA(isA<VaultException>().having((e) => e.failure, 'failure', entry.value)),
      );
    });
  }

  test('plugin ausente vira unavailable e isSupported false', () async {
    expect(() => vault.unseal('a', reason: 'x'), throwsA(isA<VaultException>()));
    expect(await vault.isSupported, isFalse);
  });

  test('seal que falha vira VaultException(unavailable)', () async {
    mock((_) async => throw PlatformException(code: 'seal_failed'));
    expect(() => vault.seal('a', 't'), throwsA(isA<VaultException>()));
  });
}
```

- [ ] **Step 2: Rodar** — Run: `cd apps/acs && flutter test test/keystore_vault_channel_test.dart` — Expected: PASS (a classe já existe da Task 1; este teste fixa o contrato que o Kotlin deve cumprir).

- [ ] **Step 3: Gradle**

Descobrir qual existe: `ls apps/acs/android/app/build.gradle*`. Fixar a **1.1.0** (estável; a 1.2.0-alpha é pré-lançamento e desnecessária). No bloco `dependencies` (criá-lo se não houver):

Groovy (`build.gradle`):
```groovy
dependencies {
    implementation "androidx.biometric:biometric:1.1.0"
}
```

Kotlin DSL (`build.gradle.kts`):
```kotlin
dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
}
```

- [ ] **Step 4: Kotlin**

```kotlin
// KeystoreVault.kt
package br.com.prismrr.sinalacs.acs

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource

/**
 * Cofre do refresh token (envelope): RSA-2048/OAEP no Android Keystore com
 * autenticação do usuário exigida a CADA decifra (CryptoObject) protege uma
 * chave AES-256-GCM descartável que cifra o token. Cifrar usa a chave pública e
 * não pede prompt. Só o texto cifrado fica em SharedPreferences privado: sem a
 * chave do TEE ele não vale nada. Nunca registre token, chave ou exceção.
 */
class KeystoreVault(private val activity: FragmentActivity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "br.com.prismrr.sinalacs.acs/keystore_vault"
        private const val PROVIDER = "AndroidKeyStore"
        private const val PREFS = "sinalacs_keystore_vault"
        private const val TRANSFORMATION = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding"
        // O provedor do Keystore usa MGF1 com SHA-1 mesmo pedindo SHA-256.
        private val OAEP = OAEPParameterSpec(
            "SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT,
        )
    }

    private val authenticators: Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else {
            // Antes da API 30 o CryptoObject só aceita biometria forte.
            BiometricManager.Authenticators.BIOMETRIC_STRONG
        }

    private val prefs get() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun keyAlias(alias: String) = "sinalacs.vault.$alias"
    private fun keyStore() = KeyStore.getInstance(PROVIDER).apply { load(null) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val alias = call.argument<String>("alias")
        try {
            when (call.method) {
                "isSupported" -> result.success(
                    BiometricManager.from(activity).canAuthenticate(authenticators) ==
                        BiometricManager.BIOMETRIC_SUCCESS,
                )
                "contains" -> result.success(alias != null && prefs.contains(alias))
                "seal" -> {
                    seal(alias!!, call.argument<String>("plaintext")!!)
                    result.success(null)
                }
                "unseal" -> unseal(alias!!, call.argument<String>("reason") ?: "", result)
                "delete" -> {
                    delete(alias!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // Sem getMessage: o texto do Keystore não vai para o canal nem para log.
            result.error("unavailable", null, null)
        }
    }

    private fun generateKey(alias: String) {
        val builder = KeyGenParameterSpec.Builder(
            keyAlias(alias),
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(2048)
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0, // a cada uso
                KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
            )
        }
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, PROVIDER).run {
            initialize(builder.build())
            generateKeyPair()
        }
    }

    private fun publicKey(alias: String): PublicKey {
        val ks = keyStore()
        if (!ks.containsAlias(keyAlias(alias))) generateKey(alias)
        val pub = ks.getCertificate(keyAlias(alias)).publicKey
        // Recria a chave fora do Keystore: a original herda as restrições de
        // autenticação e falharia ao cifrar sem prompt em alguns aparelhos.
        return KeyFactory.getInstance(pub.algorithm).generatePublic(X509EncodedKeySpec(pub.encoded))
    }

    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)
    private fun unb64(s: String) = Base64.decode(s, Base64.NO_WRAP)

    /**
     * Envelope: AES-256-GCM descartável cifra o token; a chave AES (32 bytes)
     * é cifrada com a pública RSA. Blob: IV.chaveAES_RSA.token_AES (Base64).
     */
    private fun seal(alias: String, plaintext: String) {
        val aesKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val aes = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, aesKey) }
        val body = aes.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val rsa = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, publicKey(alias), OAEP) }
        val wrapped = rsa.doFinal(aesKey.encoded)
        // `commit` (síncrono): o blob novo tem de estar em disco antes do legado ser apagado.
        prefs.edit().putString(alias, b64(aes.iv) + "." + b64(wrapped) + "." + b64(body)).commit()
    }

    private fun delete(alias: String) {
        prefs.edit().remove(alias).apply()
        val ks = keyStore()
        if (ks.containsAlias(keyAlias(alias))) ks.deleteEntry(keyAlias(alias))
    }

    private fun unseal(alias: String, reason: String, result: MethodChannel.Result) {
        val blob = prefs.getString(alias, null)
        if (blob == null) {
            result.success(null)
            return
        }
        val cipher: Cipher
        try {
            val key = keyStore().getKey(keyAlias(alias), null) as? PrivateKey
            if (key == null) {
                delete(alias)
                result.error("invalidated", null, null)
                return
            }
            cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, OAEP)
        } catch (e: KeyPermanentlyInvalidatedException) {
            delete(alias)
            result.error("invalidated", null, null)
            return
        } catch (e: Exception) {
            result.error("unavailable", null, null)
            return
        }

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("SinalACS")
            .setSubtitle(reason)
            .setAllowedAuthenticators(authenticators)
            .apply {
                // Com DEVICE_CREDENTIAL o botão negativo é proibido.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) setNegativeButtonText("Cancelar")
            }
            .build()

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                try {
                    // O CryptoObject é o RSA privado: libera a chave AES, que decifra o token.
                    val parts = blob.split(".")
                    require(parts.size == 3)
                    val aesBytes = r.cryptoObject!!.cipher!!.doFinal(unb64(parts[1]))
                    val aes = Cipher.getInstance("AES/GCM/NoPadding").apply {
                        init(Cipher.DECRYPT_MODE, SecretKeySpec(aesBytes, "AES"), GCMParameterSpec(128, unb64(parts[0])))
                    }
                    result.success(String(aes.doFinal(unb64(parts[2])), Charsets.UTF_8))
                } catch (e: Exception) {
                    result.error("unavailable", null, null)
                }
            }

            override fun onAuthenticationError(code: Int, msg: CharSequence) {
                val mapped = when (code) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED -> "cancelled"
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockedOut"
                    else -> "unavailable"
                }
                result.error(mapped, null, null)
            }
            // onAuthenticationFailed (digital errada) não encerra: o prompt segue.
        }

        activity.runOnUiThread {
            BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
                .authenticate(info, BiometricPrompt.CryptoObject(cipher))
        }
    }
}
```

`MainActivity.kt` — acrescentar imports `io.flutter.embedding.engine.FlutterEngine` e `io.flutter.plugin.common.MethodChannel` e o método:

```kotlin
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KeystoreVault.CHANNEL)
            .setMethodCallHandler(KeystoreVault(this))
    }
```

- [ ] **Step 5: Compilar**

Run: `cd apps/acs && flutter build apk --debug` — Expected: sucesso (compila o Kotlin). O envelope dispensa checar o tamanho do token.

- [ ] **Step 6: Commit**

```bash
git add apps/acs/android apps/acs/test
git commit -m "feat(acs): cofre Kotlin com envelope AES-GCM + RSA do Keystore e BiometricPrompt/CryptoObject"
```

---

### Task 4: Ligar no `main.dart` e migrar o token legado (antes da 1ª retomada)

**Files:**
- Create: `apps/acs/test/support/counting_session_token_store.dart`
- Modify: `apps/acs/lib/main.dart` (~l.48)
- Test: `apps/acs/test/auth_bound_session_token_store_test.dart` (acrescentar), `apps/acs/test/session_store_wiring_test.dart` (estender)

**Interfaces:**
- Consumes: `AuthBoundSessionTokenStore`, `MethodChannelKeystoreVault`, `SecureStorageSessionTokenStore`.

- [ ] **Step 1: Testes de migração que falham**

```dart
test('token legado é selado sem prompt e o original é apagado', () async {
  await legacy.write('velho');
  expect(await store.contains(), isTrue);
  expect(vault.sealed[AuthBoundSessionTokenStore.alias], 'velho');
  expect(await legacy.read(), isNull);
  expect(vault.unsealCalls, 0);
  // a leitura segue exigindo o prompt
  expect(await store.read(), isNull);
  expect(await store.unlock(reason: 'x'), SessionUnlock.unlocked);
  expect(await store.read(), 'velho');
});

test('migração que falha preserva o legado (a sessão não se perde)', () async {
  vault.failSeal = true;
  await legacy.write('velho');
  expect(await store.contains(), isFalse);
  expect(await legacy.read(), 'velho');
});
```

- [ ] **Step 2:** `flutter test test/auth_bound_session_token_store_test.dart` — Expected: PASS (a lógica está na Task 1; se falhar, corrija `_migrateLegacy`). O segundo teste exige que `contains()` devolva `false` quando o legado ficou: confirme que não devolve `true` por engano.

- [ ] **Step 2b: Teste de ordem e de interrupção** (acrescentar no mesmo arquivo)

```dart
test('migração roda antes do 1º unlock: contains() já sela o legado', () async {
  await legacy.write('velho');
  await store.contains(); // o que hasStoredSession chama, antes de _tryResume
  expect(vault.sealed[AuthBoundSessionTokenStore.alias], 'velho');
  expect(await legacy.read(), isNull);
});

test('app morto entre selar e apagar o legado: legado e cofre coexistem, o legado é descartado', () async {
  vault.sealed[AuthBoundSessionTokenStore.alias] = 'velho';
  await legacy.write('velho');
  expect(await store.contains(), isTrue);
  expect(await legacy.read(), isNull);
});
```

```dart
test('contains() é leve após a migração: não relê o legado', () async {
  final counting = CountingSessionTokenStore(); // duplo: MemorySessionTokenStore que conta `read`
  final s = AuthBoundSessionTokenStore(vault: vault, legacy: counting);
  await s.contains();
  final reads = counting.reads;
  await s.contains();
  await s.contains();
  expect(counting.reads, reads);
});

test('migração que falhou não liga o flag: a próxima contains() tenta de novo', () async {
  vault.failSeal = true;
  await legacy.write('velho');
  expect(await store.contains(), isFalse);
  vault.failSeal = false;
  expect(await store.contains(), isTrue);
  expect(vault.sealed[AuthBoundSessionTokenStore.alias], 'velho');
});
```

`CountingSessionTokenStore` é um duplo de 10 linhas em `test/support/` (estende o comportamento de `MemorySessionTokenStore` e incrementa `reads` em `read()`); criá-lo junto.

Esses testes passam com `_migrateLegacy` da Task 1, que é chamado dentro de `contains()` e de `unlock()`; `hasStoredSession` (chamado antes do prompt em `_tryResume`) garante a ordem. Se algum falhar, ajuste o store, não o teste.

- [ ] **Step 3: Montar no `main.dart`**

Trocar `tokenStore: SecureStorageSessionTokenStore(),` por:

```dart
      tokenStore: AuthBoundSessionTokenStore(
        vault: MethodChannelKeystoreVault(),
        legacy: SecureStorageSessionTokenStore(),
      ),
```

(importar `core/security/auth_bound_session_token_store.dart` e `keystore_vault.dart`). Estender `session_store_wiring_test.dart` com um teste que confirme que o `main` (ou a função de montagem que o teste já usa) monta o store vinculado — seguir o padrão do arquivo.

- [ ] **Step 4:** `cd apps/acs && flutter test && flutter analyze` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): refresh token passa a viver no cofre vinculado à biometria; migra o legado"
```

---

### Task 5: Logout apaga o par RSA (sem chave órfã)

**Files:**
- Test: `apps/acs/test/auth_bound_session_token_store_test.dart`, `apps/acs/test/refresh_session_test.dart`
- Conferir: `apps/acs/android/.../KeystoreVault.kt` (`delete`, já remove o blob e `deleteEntry`)

**Interfaces:**
- Consumes: `BackendClient.logout()` chama `_tokenStore.clear()` (já existe), que no store vinculado chama `KeystoreVault.delete(alias)`.

- [ ] **Step 1: Testes que falham/fixam**

```dart
test('clear (logout) apaga o blob e a chave: contains é false e o cofre fica vazio', () async {
  await store.write('tok-1');
  await store.clear();
  expect(vault.sealed, isEmpty);
  expect(await store.contains(), isFalse);
  expect(await store.read(), isNull);
});

test('após clear, novo write recria o ciclo normalmente', () async {
  await store.write('a');
  await store.clear();
  await store.write('b');
  expect(vault.sealed[AuthBoundSessionTokenStore.alias], 'b');
});
```

Em `refresh_session_test.dart`, acrescentar um teste de `BackendClient.logout()` com `tokenStore: AuthBoundSessionTokenStore(vault: vault, legacy: MemorySessionTokenStore())` e `expect(vault.sealed, isEmpty)` (copiar o setup dos testes de logout vizinhos).

- [ ] **Step 2:** `cd apps/acs && flutter test test/auth_bound_session_token_store_test.dart test/refresh_session_test.dart` — Expected: PASS. Se o de logout falhar, o `BackendClient` não está chamando `clear()` do store: corrigir lá.

- [ ] **Step 3: Fallback documentado no código.** No doc-comment de `AuthBoundSessionTokenStore` (já descreve), acrescentar: "API 24–29 sem biometria forte: o token fica só em RAM e morre com o processo; a partida a frio exige login completo. É recurso de segurança para aparelhos antigos, não falha." E em `app.dart`, no ramo `_aviso`/login, nada de texto novo; a comunicação ao ACS vai em `PROGRESS.md` (Task 6).

- [ ] **Step 4: Commit**

```bash
git add apps/acs
git commit -m "test(acs): logout apaga o blob e o par RSA; documenta o fallback em RAM para APIs antigas"
```

---

### Task 6: Prova no emulador e documentação

**Files:**
- Create: `scripts/qa/acs_keystore_bound_e2e.sh`
- Modify: `PROGRESS.md` (linhas "Limite de desenho" e "Aberto (a)" da seção do refresh token), `apps/CLAUDE.md` (parágrafo de `database_key_store`/token), `CLAUDE.md` (lista "Still missing": remover "biometric bound to the Keystore"; ajustar a frase "an interface gate, not a key binding"), `spec/lgpd_design.md` §5.1
- Conferir: `scripts/qa/contagem_validation_report.py` (contagem de testes do ACS na documentação)

**Interfaces:** nenhuma de código.

- [ ] **Step 1: Escrever o script** `acs_keystore_bound_e2e.sh` seguindo o padrão de `scripts/qa/acs_secure_window.sh` e `acs_release_signing.sh` (ler um deles antes e reaproveitar `lib_*.sh`). Passos que o script automatiza com `adb`: instalar o debug, entrar com o ACS de dev, forçar `adb shell am force-stop`, abrir de novo e verificar com `uiautomator dump` que **o diálogo do BiometricPrompt aparece** antes do painel; `adb -e emu finger touch 1` (digital cadastrada) abre o painel; `finger touch 2` (digital errada) não abre. O passo de nova digital (invalidação) é manual, descrito abaixo.

- [ ] **Step 2: Rodar no emulador** (`emulator-5554`, API 36, com PIN + digital cadastrados)

Run: `./scripts/qa/acs_keystore_bound_e2e.sh`
Expected: 3 casos verdes — (1) partida a frio pede prompt; (2) digital certa entra; (3) digital errada/cancelar não entra e o token continua guardado (segunda tentativa entra).

- [ ] **Step 3: Prova manual de invalidação** — no emulador, cadastrar uma segunda digital (Configurações → Segurança), abrir o app a frio. Expected: sem laço de prompt; tela de login com "Sua sessão expirou. Entre novamente."; login completo recria a chave e o ciclo volta ao normal. Anotar o resultado em `PROGRESS.md`.

- [ ] **Step 4: Prova de não-regressão** — `./scripts/qa/e2e.sh --emulator` e `acs_full_e2e.sh` (o e2e usa `BiometricGate` de teste na retomada; confirmar que continua verde e, se o app do e2e usar `MemorySessionTokenStore`, que o caminho `notRequired` segue funcionando). `acs_secure_window.sh` continua verde.

- [ ] **Step 5: Documentar**
  - `PROGRESS.md`: reescrever "Limite de desenho" (o token agora é decifrado por chave do Keystore com `setUserAuthenticationRequired`; o AppLockGate continua sendo portão de UI para os 30 s em segundo plano — o token fica em RAM durante o processo), marcar (a) como fechado com data e a prova, e **registrar o que segue aberto**: chave do SQLCipher e token de envio diferido sem vínculo (por desenho), API 24–29 sem prova (item (f) já aberto), aparelho sem biometria/PIN = login completo a cada partida a frio.
  - `CLAUDE.md` e `apps/CLAUDE.md`: mesma correção; atualizar a contagem de testes do ACS (rodar `flutter test` e usar o número real; conferir com `scripts/qa/contagem_validation_report.py`).
  - `spec/lgpd_design.md` §5.1: acrescentar a decisão (RSA/OAEP, decifra por uso, invalidação por nova biometria, envelope AES-256-GCM + RSA-OAEP).

- [ ] **Step 6: Atualizar o grafo e commitar**

```bash
graphify update .
git add scripts/qa/acs_keystore_bound_e2e.sh PROGRESS.md CLAUDE.md apps/CLAUDE.md spec/lgpd_design.md
git commit -m "docs(acs): biometria amarrada ao Keystore (refresh token); prova no emulador"
```

---

## Auto-revisão

- **Cobertura:** vínculo ao Keystore (Tasks 1+3), retomada a frio sem prompt duplo (Task 2), instalações existentes (Task 4), prova real e docs (Task 5). Review Focus 1→T1/T3/T6, 2→T1, 3→T1/T4, 4→T4, 5→T3, 6→T5, 7→T4.
- **Consistência de tipos:** `SessionUnlock`, `contains()`, `unlock({required String reason})`, `KeystoreVault`, `VaultFailure`, `AuthBoundSessionTokenStore.alias` usados com os mesmos nomes em todas as tasks.
- **Riscos que o plano não resolve por si:** (1) o comportamento de `CryptoObject` + `DEVICE_CREDENTIAL` varia por fabricante antes da API 30 — por isso API < 30 aceita só biometria forte e cai em login completo; só a Task 5 em emulador API 36 está provada, e os testes em API 24–29 continuam no item (f) aberto. (2) O OAEP do Keystore (MGF1-SHA1) é fonte conhecida de erro: o `OAEP` fixo no Kotlin cobre, mas só o emulador prova; o envelope AES-GCM só é provado no aparelho também. (3) Com o token em RAM depois do desbloqueio, um atacante com root e o app já aberto desbloqueado não é barrado — o ganho é contra a leitura **em repouso** e contra a partida a frio.
