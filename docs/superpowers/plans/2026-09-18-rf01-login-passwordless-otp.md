# RF01 — Login Passwordless do Paciente (CPF + nascimento + OTP) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar o login por CPF + data de nascimento validados por código OTP — o último item do "Núcleo Duro que Prova a Hipótese" do MVP (`spec/PRD_system.md` §6.1) ainda sem código —, com o CPF hasheado por HMAC-SHA-256 e pepper como `spec/lgpd_data_audit.md` torna mandatório.

**Architecture:** Três peças. (1) `Cpf`, um value object que normaliza e valida dígitos verificadores — hoje o app tem dois `TextField` sem controller e nenhum código no repositório calcula CPF. (2) `CpfHasher` (HMAC-SHA-256 com `CPF_HASH_PEPPER`, campo de domínio explícito) que substitui os literais `'development-patient'` que o seed grava em `users.cpfHash`; sem pepper o seed de 10^9 CPFs é reversível por força bruta em segundos, que é o que `lgpd_data_audit.md:196` proíbe. (3) `PasswordlessAuthService` + `otp_challenges`, replicando o padrão de hash-só de `enrollment_tokens` (o único artefato análogo que já existe): pedido de código, verificação, limite de tentativas, expiração e auditoria. O SMS atrás de uma interface `SmsGateway`, porque **nenhum provedor está escolhido em spec nenhuma** — a implementação de desenvolvimento registra o código no log do processo, e fora de `development` o boot falha se nenhum gateway real estiver configurado, seguindo o estilo fail-closed de `AppConfig._resolveSecret`.

**Tech Stack:** Dart/Serverpod (`backend/sinalacs_server`), `package:crypto` (HMAC-SHA-256, já em uso por `DevelopmentAuthService`), `package:postgres` (seed Dart). Flutter (`apps/patient`).

**Spec:** `spec/PRD_system.md` linhas 134 (RF01 na matriz, dependência "SMS Gateway"), 1005 (critério de MVP: "10 pacientes conseguem logar em < 60s"), 548 (SLO de login < 1s); `spec/sys_flow.md:22`; `spec/stack.md:20` ("Login Fricção Zero … delegada à camada de aplicação"); `spec/lgpd_data_audit.md` linhas 185-197 — em especial **196** ("`users.cpfHash` … Migrar para **HMAC-SHA-256** utilizando segredo corporativo (*pepper*) injetado via variável de ambiente restrita ao backend (`CPF_HASH_PEPPER`). O cálculo deve ser feito exclusivamente pelo servidor.") e **187** ("torna-se **mandatória** para impedir que a credencial de login do paciente seja quebrada em caso de vazamento do banco") e **197** (`birthDate` como `date`, não `timestamp`); `spec/lgpd_design.md:309` ("registro de tentativas de acesso"). Diagnóstico: `spec/validation_report.md` linha 69 (RF01 "ausente").

## Global Constraints

- **Nenhum CPF, data de nascimento ou código OTP em claro entra em log, teste, seed versionado ou mensagem de erro.** O seed grava o HMAC de CPFs sintéticos; os testes usam CPFs de exemplo da própria documentação do algoritmo (ver Task 1) e nunca um CPF real.
- **A resposta é idêntica para CPF inexistente, data de nascimento errada e CPF válido.** `requestOtp` não pode revelar se aquele CPF está cadastrado — mesmo raciocínio já aplicado ao login institucional.
- **O código OTP é gravado apenas como HMAC.** `otp_challenges.codeHash` nunca contém o código; o valor em claro existe só no momento da geração e no envio. Mesmo padrão de `enrollment_tokens.tokenHash` (`models/enrollment_token.spy.yaml:10-13`).
- **Nenhum provedor de SMS é escolhido por este plano.** `SMS_GATEWAY` só aceita `log` quando `APP_ENV=development`; qualquer outro valor (ou ausência dele) fora de `development` falha no boot, exatamente como `JWT_SECRET` e `HEALTH_DATA_ENCRYPTION_KEY` já fazem. Escolher o provedor é decisão de produto/infra, como o projeto Firebase do RF14.
- **⚠️ Consequência de sessão que este plano expõe — leia antes de executar a Task 7.** O código OTP **não pode ser reapresentado**: ao contrário da senha do ACS, não existe credencial reutilizável para renovar a sessão em silêncio. Com o TTL de 15 minutos hoje vigente e sem refresh token, o paciente teria de receber um SMS novo a cada 15 minutos — o que torna o app inutilizável. A decisão genérica de "manter 15 min e registrar a lacuna" foi tomada em 2026-09-18 **antes** desta consequência ficar visível, e não se sustenta para o RF01. A Task 7 eleva o TTL do paciente a **1 hora**, que é o que `spec/lgpd_design.md` LGPD-RT06 **já exige** — não é uma decisão nova, é aplicar um requisito que já existe e que este plano não tem como evitar. O TTL do ACS permanece 15 minutos, como decidido.
- **MFA/TOTP e refresh token rotativo continuam fora de escopo** (LGPD-RT06 / F5), com a lacuna registrada na Task 8.
- Mensagens, comentários e nomes de domínio em português.
- Depois de qualquer `.spy.yaml` novo ou alterado: `cd backend/sinalacs_server && serverpod generate && serverpod create-migration`. O CLI do Serverpod pode não estar no PATH (`export PATH="$PATH:$HOME/.pub-cache/bin"`), e `create-migration` **aborta sem `--force`** quando a migração inclui índice único — esta task inclui um. Ver a Task 3.
- Antes de `dart test` de integração: `docker compose --profile test up -d postgres-test`.

---

## File Structure

- **Create** `backend/sinalacs_server/lib/src/application/auth/cpf.dart` — value object `Cpf`.
- **Create** `backend/sinalacs_server/lib/src/application/auth/cpf_hasher.dart` — interface.
- **Create** `backend/sinalacs_server/lib/src/infrastructure/crypto/hmac_cpf_hasher.dart` — implementação HMAC-SHA-256 + pepper.
- **Create** `backend/sinalacs_server/lib/src/models/otp_challenge.spy.yaml` + `models/exceptions/otp_request_exception.spy.yaml`.
- **Create** `backend/sinalacs_server/lib/src/application/auth/sms_gateway.dart` — interface + `LoggingSmsGateway` + `RecordingSmsGateway` (teste).
- **Create** `backend/sinalacs_server/lib/src/application/auth/passwordless_auth_service.dart` — `OtpChallengeStore` + `PasswordlessAuthService`.
- **Create** `backend/sinalacs_server/lib/src/infrastructure/database/orm_otp_challenge_store.dart`.
- **Create** `backend/sinalacs_server/bin/seed_cpf_hashes.dart`.
- **Create** testes: `test/unit/cpf_test.dart`, `test/unit/hmac_cpf_hasher_test.dart`, `test/unit/passwordless_auth_service_test.dart`, `test/integration/passwordless_login_test.dart`.
- **Modify** `backend/sinalacs_server/lib/src/models/user.spy.yaml` — índice único em `cpfHash`, `birthDate` para `date`.
- **Modify** `backend/sinalacs_server/lib/src/config/app_config.dart` — `CPF_HASH_PEPPER`, `SMS_GATEWAY`. **Os `AppConfig(...)` construídos direto em `test/integration/` também precisam dos dois parâmetros novos** (são mecânicos e sem eles o commit não compila), então a Task 2 inclui `test/integration/` no commit.
- **Modify** `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart`, `runtime/alert_runtime.dart`.
- **Modify** `docker-compose.yml`, `scripts/dev/bootstrap_env.sh`, `.env.example`.
- **Modify** `apps/patient/lib/core/network/backend_client.dart`, `apps/patient/lib/app/app.dart`, os fakes de teste, `tool/live_check.dart`, `integration_test/backend_connection_test.dart`.
- **Modify** docs na Task 8.

**Depende de:** nenhum símbolo de `docs/superpowers/plans/2026-09-18-rbac-camada-autorizacao.md` — `auth.requestOtp`/`verifyOtp` são públicos por definição (quem chama ainda não tem sessão), então não usam `Authorization` nem `AuthenticatedEndpoint`, e `AuthEndpoint` já está na allowlist de postura daquele plano. De `docs/superpowers/plans/2026-09-18-rf07-login-institucional-acs.md` este plano reusa **padrões**, não código: interface em `application/` com implementação em `infrastructure/`, serviço de seed Dart rodando depois do `database-seed`, e a tradução de exceção tipada de credencial no `_guard` do app. Nem `HmacCpfHasher` nem `PasswordHasher` compartilham arquivo; executar o RF07 antes é conveniente (o `docker-compose.yml` ganha os dois serviços de seed na mesma região do arquivo), mas não é obrigatório.

---

## Task 1: `Cpf` — normalização e dígitos verificadores

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/auth/cpf.dart`
- Test: `backend/sinalacs_server/test/unit/cpf_test.dart`

**Interfaces:**
- Produces: `class Cpf { static Cpf? tryParse(String input); String get digits; String get formatted; }` — `tryParse` devolve `null` para qualquer coisa que não seja um CPF válido de 11 dígitos.

Os CPFs usados nos testes são os exemplos clássicos da própria documentação do algoritmo de dígito verificador (`12345678909`, `98765432100`), não matrículas reais. O teste inclui um CPF com dígito verificador errado e um com todos os dígitos iguais (que passa na aritmética e é inválido por definição).

- [ ] **Step 1: Escrever o teste que falha**

Cria `backend/sinalacs_server/test/unit/cpf_test.dart`:

```dart
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:test/test.dart';

void main() {
  group('Cpf.tryParse', () {
    test('aceita CPF sintético com dígitos verificadores corretos', () {
      // Exemplos da documentação do próprio algoritmo de DV — nunca um CPF real.
      expect(Cpf.tryParse('12345678909')?.digits, '12345678909');
      expect(Cpf.tryParse('98765432100')?.digits, '98765432100');
    });

    test('normaliza a máscara que a pessoa digita', () {
      expect(Cpf.tryParse('123.456.789-09')?.digits, '12345678909');
      expect(Cpf.tryParse('  12345678909  ')?.digits, '12345678909');
    });

    test('recusa dígito verificador errado', () {
      expect(Cpf.tryParse('12345678900'), isNull);
      expect(Cpf.tryParse('98765432101'), isNull);
    });

    // Passa na aritmética do DV e é inválido por definição: a Receita nunca
    // emite CPF com todos os dígitos iguais.
    test('recusa repetição de dígito', () {
      for (final digito in ['0', '1', '9']) {
        expect(Cpf.tryParse(List.filled(11, digito).join()), isNull);
      }
    });

    test('recusa comprimento errado e lixo', () {
      expect(Cpf.tryParse('1234567890'), isNull);
      expect(Cpf.tryParse('123456789012'), isNull);
      expect(Cpf.tryParse(''), isNull);
      expect(Cpf.tryParse('abcdefghijk'), isNull);
    });

    test('formata para exibição', () {
      expect(Cpf.tryParse('12345678909')?.formatted, '123.456.789-09');
    });
  });
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/unit/cpf_test.dart`
Expected: FAIL — URI de `cpf.dart` não existe.

- [ ] **Step 3: Escrever o value object**

Cria `backend/sinalacs_server/lib/src/application/auth/cpf.dart`:

```dart
/// CPF validado — o identificador de login do paciente (RF01).
///
/// Existe porque a validação de dígito verificador precisa acontecer **antes**
/// de o CPF virar hash: um CPF com DV errado não pode nem ser procurado no
/// banco, senão um erro de digitação vira "paciente não encontrado" em vez de
/// "confira o número".
class Cpf {
  const Cpf._(this.digits);

  /// Apenas os 11 dígitos, sem máscara.
  final String digits;

  /// `123.456.789-09` — só para exibição.
  String get formatted =>
      '${digits.substring(0, 3)}.${digits.substring(3, 6)}.'
      '${digits.substring(6, 9)}-${digits.substring(9)}';

  /// Normaliza e valida. Devolve `null` para qualquer entrada inválida — quem
  /// chama decide a mensagem, e `null` não diz *por que* é inválido, o que
  /// evita distinguir "DV errado" de "não existe" na resposta ao cliente.
  static Cpf? tryParse(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 11) return null;

    // Repetição de dígito passa na aritmética abaixo e não é CPF válido:
    // a Receita não emite 111.111.111-11 nem nenhum outro múltiplo assim.
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return null;

    if (!_checkDigitMatches(digits, 9) || !_checkDigitMatches(digits, 10)) {
      return null;
    }
    return Cpf._(digits);
  }

  /// Confere o dígito verificador na posição [position] (9 = primeiro DV,
  /// 10 = segundo), pelos pesos decrescentes do algoritmo.
  static bool _checkDigitMatches(String digits, int position) {
    var sum = 0;
    for (var index = 0; index < position; index++) {
      sum += int.parse(digits[index]) * (position + 1 - index);
    }
    final remainder = sum % 11;
    final expected = remainder < 2 ? 0 : 11 - remainder;
    return expected == int.parse(digits[position]);
  }

  @override
  String toString() => formatted;
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd backend/sinalacs_server && dart test test/unit/cpf_test.dart`
Expected: PASS — 6 testes.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/auth/cpf.dart \
        backend/sinalacs_server/test/unit/cpf_test.dart
git commit -m "feat(backend): Cpf com normalizacao e digitos verificadores (RF01)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 2: `CpfHasher` — HMAC-SHA-256 com pepper

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/auth/cpf_hasher.dart`
- Create: `backend/sinalacs_server/lib/src/infrastructure/crypto/hmac_cpf_hasher.dart`
- Modify: `backend/sinalacs_server/lib/src/config/app_config.dart`
- Test: `backend/sinalacs_server/test/unit/hmac_cpf_hasher_test.dart`

**Interfaces:**
- Consumes: `Cpf` (Task 1).
- Produces: `abstract interface class CpfHasher { String hash(Cpf cpf); String hashOtpCode(String code); }` e `class HmacCpfHasher implements CpfHasher { HmacCpfHasher({required String pepper}); }`

O `hashOtpCode` mora aqui, e não num hasher próprio, por um motivo deliberado que precisa ficar escrito no código: **os dois valores compartilham o mesmo segredo e o mesmo modelo de ameaça** (força bruta offline depois de um vazamento do banco — 10^9 para o CPF, 10^6 para o código OTP), e a independência de segredos que o repositório exige vale para dados de vida longa (rotacionar `JWT_SECRET` não pode invalidar a trilha de auditoria). Um código OTP vive 5 minutos: rotacionar o pepper invalidá-lo é inofensivo. O que separa os dois usos é o **campo de domínio** no prefixo da mensagem, que impede que um hash de CPF seja reapresentado como hash de código.

- [ ] **Step 1: Escrever o teste que falha**

Cria `backend/sinalacs_server/test/unit/hmac_cpf_hasher_test.dart`:

```dart
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';
import 'package:test/test.dart';

void main() {
  final cpf = Cpf.tryParse('12345678909')!;

  test('é determinístico: o mesmo CPF e o mesmo pepper dão o mesmo hash', () {
    final a = HmacCpfHasher(pepper: 'pepper-de-teste');
    final b = HmacCpfHasher(pepper: 'pepper-de-teste');

    expect(a.hash(cpf), b.hash(cpf));
  });

  test('pepper diferente produz hash diferente', () {
    final a = HmacCpfHasher(pepper: 'pepper-de-teste');
    final b = HmacCpfHasher(pepper: 'outro-pepper');

    expect(a.hash(cpf), isNot(b.hash(cpf)));
  });

  test('o hash não contém o CPF', () {
    final hash = HmacCpfHasher(pepper: 'pepper-de-teste').hash(cpf);

    expect(hash.contains(cpf.digits), isFalse);
    expect(hash.length, 64, reason: 'hex de 32 bytes');
  });

  // Campo de domínio: sem ele, `hashOtpCode('12345678909')` seria idêntico a
  // `hash(cpf)` do mesmo valor, e um hash de uma finalidade valeria na outra.
  test('o domínio separa CPF de código OTP', () {
    final hasher = HmacCpfHasher(pepper: 'pepper-de-teste');

    expect(hasher.hashOtpCode(cpf.digits), isNot(hasher.hash(cpf)));
  });

  test('recusa pepper vazio', () {
    expect(() => HmacCpfHasher(pepper: ''), throwsA(isA<ArgumentError>()));
    expect(() => HmacCpfHasher(pepper: '   '), throwsA(isA<ArgumentError>()));
  });
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/unit/hmac_cpf_hasher_test.dart`
Expected: FAIL — URI de `hmac_cpf_hasher.dart` não existe.

- [ ] **Step 3: Escrever interface e implementação**

Cria `backend/sinalacs_server/lib/src/application/auth/cpf_hasher.dart`:

```dart
import 'package:sinalacs_server/src/application/auth/cpf.dart';

/// Hash do CPF e do código OTP, para que a busca de login nunca compare o
/// identificador em claro (LGPD, `spec/lgpd_data_audit.md:196`).
///
/// Interface em `application/`, implementação em `infrastructure/` — mesmo
/// arranjo de `PasswordHasher`/`AlertStore`.
abstract interface class CpfHasher {
  /// Índice de busca em `users.cpfHash`. Determinístico por necessidade: é
  /// coluna indexada, e um hash com salt por linha não permitiria procurar.
  /// O pepper é o que substitui o salt aqui — sem ele, o espaço de 10^9 CPFs
  /// é reversível por força bruta em segundos.
  String hash(Cpf cpf);

  /// Hash do código OTP de 6 dígitos, com campo de domínio próprio.
  String hashOtpCode(String code);
}
```

Cria `backend/sinalacs_server/lib/src/infrastructure/crypto/hmac_cpf_hasher.dart`:

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/cpf_hasher.dart';

/// HMAC-SHA-256 com pepper de servidor.
///
/// `package:crypto` em vez de `package:cryptography` porque aqui a operação é
/// síncrona e sem salt — é a mesma primitiva que `DevelopmentAuthService` já
/// usa para assinar o token.
///
/// Os prefixos `sinalacs:cpf:v1:` e `sinalacs:otp:v1:` são separação de
/// domínio: sem eles, um hash de código OTP (`'12345678909'` é um código de 11
/// dígitos válido como string) seria idêntico ao hash de um CPF de mesmo
/// valor, e um valor vazado numa finalidade valeria na outra. O `:v1:` é o
/// mesmo espaço para versionar o esquema sem ambiguidade — trocar o prefixo
/// invalida deliberadamente os hashes antigos, e é assim que se percebe.
class HmacCpfHasher implements CpfHasher {
  HmacCpfHasher({required String pepper}) : _key = _requirePepper(pepper);

  final List<int> _key;

  static const _cpfDomain = 'sinalacs:cpf:v1:';
  static const _otpDomain = 'sinalacs:otp:v1:';

  @override
  String hash(Cpf cpf) => _hmac('$_cpfDomain${cpf.digits}');

  @override
  String hashOtpCode(String code) => _hmac('$_otpDomain$code');

  String _hmac(String message) =>
      Hmac(sha256, _key).convert(utf8.encode(message)).toString();

  /// Pepper vazio é pior que pepper ausente: `Hmac(sha256, [])` produz um hash
  /// perfeitamente válido e sem segredo nenhum — o banco pareceria protegido e
  /// não estaria. `AppConfig` já recusa o valor vazio no boot; esta é a rede
  /// de baixo, para quem construir o hasher fora da config (o seed, os testes).
  static List<int> _requirePepper(String pepper) {
    if (pepper.trim().isEmpty) {
      throw ArgumentError.value(
        pepper.length,
        'pepper',
        'o pepper do CPF não pode ser vazio: sem ele o hash é reversível por '
            'força bruta',
      );
    }
    return utf8.encode(pepper);
  }
}
```

- [ ] **Step 4: Ligar o pepper na configuração**

Em `backend/sinalacs_server/lib/src/config/app_config.dart`, acrescente o campo, o parâmetro do construtor e a leitura:

```dart
  /// Pepper do HMAC de `users.cpfHash` e do hash do código OTP (RF01).
  ///
  /// `spec/lgpd_data_audit.md:196` nomeia esta variável e a torna obrigatória:
  /// o CPF tem 10^9 valores possíveis, então um hash sem segredo é revertido
  /// por força bruta em segundos a partir de um dump do banco. Segredo PRÓPRIO,
  /// não derivado de `jwtSecret`/`auditChainSecret`/`healthDataEncryptionKey`:
  /// rotacionar o pepper invalida os hashes de CPF gravados (é uma migração de
  /// dados, não uma operação silenciosa) e não pode arrastar a trilha de
  /// auditoria nem os tokens junto.
  ///
  /// O hash do código OTP usa o MESMO pepper, com campo de domínio próprio. A
  /// independência de segredos que o resto deste arquivo prega existe para
  /// dado de vida longa; um OTP vive 5 minutos, e rotacionar o pepper
  /// simplesmente o invalida — que é o efeito desejado. Ver `HmacCpfHasher`.
  final String cpfHashPepper;

  /// Gateway de SMS do login passwordless (RF01).
  ///
  /// `log` só é aceito em `development`: ele **não envia SMS**, escreve o
  /// código no log do processo para o desenvolvedor conseguir entrar. Fora de
  /// desenvolvimento, ausência ou valor desconhecido falha no boot — um
  /// servidor que sobe sem conseguir enviar código deixa todo paciente sem
  /// login, e falhar cedo é melhor que falhar no primeiro cadastro real.
  final String smsGateway;
```

No construtor e em `fromMap`:

```dart
      cpfHashPepper: _resolveSecret(
        value: environment['CPF_HASH_PEPPER'],
        appEnv: appEnv,
        envVarName: 'CPF_HASH_PEPPER',
        developmentFallback: developmentCpfHashPepper,
      ),
      smsGateway: _resolveSmsGateway(
        value: environment['SMS_GATEWAY'],
        appEnv: appEnv,
      ),
```

E as duas constantes/métodos novos:

```dart
  /// Pepper de desenvolvimento. Público, como os outros fallbacks — e por isso
  /// restrito a `development` por [_resolveSecret].
  static const developmentCpfHashPepper = 'development-cpf-hash-pepper';

  static const _knownSmsGateways = {'log'};

  /// Aceita apenas os gateways implementados, e `log` apenas em `development`.
  static String _resolveSmsGateway({
    required String? value,
    required String appEnv,
  }) {
    final gateway = value?.trim().toLowerCase();
    final isDevelopment = appEnv == 'development';

    if (gateway == null || gateway.isEmpty) {
      if (isDevelopment) return 'log';
      throw StateError(
        'SMS_GATEWAY é obrigatório quando APP_ENV=$appEnv: sem um gateway '
        'configurado, nenhum paciente consegue receber o código de acesso.',
      );
    }

    if (!_knownSmsGateways.contains(gateway)) {
      throw StateError(
        'SMS_GATEWAY="$gateway" não corresponde a nenhum gateway implementado '
        '(${_knownSmsGateways.join(', ')}).',
      );
    }

    if (gateway == 'log' && !isDevelopment) {
      throw StateError(
        'SMS_GATEWAY=log não envia SMS nenhum e por isso só vale em '
        'development; APP_ENV=$appEnv. Configure um gateway real.',
      );
    }

    return gateway;
  }
```

Acrescente os dois campos ao construtor `const AppConfig({...})` na ordem declarada, e cubra-os em `test/unit/app_config_test.dart` (que já testa as regras de `_resolveSecret`) com dois casos: `SMS_GATEWAY=log` com `APP_ENV=production` → `StateError`; ausência com `APP_ENV=production` → `StateError`.

- [ ] **Step 5: Somar ao bootstrap e ao exemplo de ambiente**

Em `scripts/dev/bootstrap_env.sh`, acrescente `CPF_HASH_PEPPER="$(secret)" \` à lista gerada e `CPF_HASH_PEPPER` ao `echo` de confirmação. Em `.env.example`:

```dotenv
# Pepper do HMAC de users.cpfHash e do hash do código OTP (RF01). Obrigatório
# fora de development. NÃO rotacione sem migrar os hashes existentes: trocar o
# valor torna todo CPF já gravado não encontrável no login.
CPF_HASH_PEPPER=

# Gateway de SMS do login passwordless. `log` (padrão em development) escreve o
# código no log do processo em vez de enviar SMS. Em produção é obrigatório
# apontar para um gateway real — nenhum provedor está escolhido ainda.
SMS_GATEWAY=
```

- [ ] **Step 6: Rodar os testes**

Run: `cd backend/sinalacs_server && dart test test/unit/hmac_cpf_hasher_test.dart test/unit/app_config_test.dart`
Expected: PASS — 5 do hasher + os de config (incluindo os 2 novos).

- [ ] **Step 7: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/auth/cpf_hasher.dart \
        backend/sinalacs_server/lib/src/infrastructure/crypto/hmac_cpf_hasher.dart \
        backend/sinalacs_server/lib/src/config/app_config.dart \
        backend/sinalacs_server/test/unit/ \
        scripts/dev/bootstrap_env.sh .env.example
git commit -m "feat(backend): HMAC-SHA-256 com pepper para CPF e codigo OTP (RF01, LGPD 196)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 3: Modelos — `otp_challenges`, CPF único e `birthDate` como data

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/otp_challenge.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/exceptions/otp_request_exception.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/user.spy.yaml`

**Interfaces:**
- Produces: `OtpChallenge`, `OtpRequestException` e o índice único `users_cpf_hash_key`.

- [ ] **Step 1: Criar o modelo do desafio**

Cria `backend/sinalacs_server/lib/src/models/otp_challenge.spy.yaml`:

```yaml
### Desafio de código OTP do login passwordless (RF01).
###
### Mesmo padrão de hash-só de `enrollment_tokens`: o código em claro existe
### apenas no momento da geração (enviado por SMS) e nunca é persistido. A
### tabela guarda o HMAC, para que um dump do banco não entregue códigos
### válidos de pacientes que estão tentando entrar agora.
class: OtpChallenge
table: otp_challenges
fields:
  id: UuidValue?, defaultPersist=random
  userId: UuidValue, relation(parent=users)
  ### HMAC-SHA-256 do código, com campo de domínio próprio (ver HmacCpfHasher).
  codeHash: String
  ### Tentativas de verificação já gastas. O código morre ao atingir o limite,
  ### mesmo antes de expirar — 6 dígitos são 10^6 combinações, e sem contador
  ### um atacante com um código enviado teria tentativas ilimitadas.
  attempts: int
  createdAt: DateTime
  expiresAt: DateTime
  ### Marca o consumo. `null` = ainda válido; nunca consumido = o desafio mais
  ### recente do paciente é o que vale.
  consumedAt: DateTime?
indexes:
  otp_challenges_user_id_created_at_idx:
    fields: userId, createdAt
```

- [ ] **Step 2: Criar a exceção**

Cria `backend/sinalacs_server/lib/src/models/exceptions/otp_request_exception.spy.yaml`:

```yaml
### Recusa do fluxo OTP (RF01): entrada inválida, limite de tentativas, código
### expirado ou nenhum código pendente. Uma exceção só, pelo mesmo motivo de
### `AuthenticationFailedException` — a resposta não pode revelar se aquele CPF
### está cadastrado.
exception: OtpRequestException
fields:
  message: String
```

- [ ] **Step 3: Tornar o CPF único e a data de nascimento uma data**

Substitua o bloco `indexes` de `backend/sinalacs_server/lib/src/models/user.spy.yaml` e o campo `birthDate`:

```yaml
  ### A data de nascimento é credencial do login passwordless (RF01) e por isso
  ### NÃO pode ser truncada para mês/ano (spec/lgpd_data_audit.md:185-186). O
  ### tipo muda de `timestamp without time zone` para `date`: guardar hora e
  ### fuso numa data de nascimento é precisão que não existe na entrada e que
  ### faz duas datas iguais divergirem na comparação.
  ### `birthDate` PERMANECE `timestamp`. O `type=date` que uma versão anterior
  ### deste plano mandava escrever **não existe**: `type=` é o tipo *Dart* do
  ### campo, e `DateTime` é fixado em `timestamp without time zone` pelo gerador
  ### (`serverpod_cli` 3.4.13 e 4.0.0 — `ColumnType` não tem `date`). Escrever
  ### isso faz `serverpod generate` recusar o modelo com "invalid datatype".
  ### Ver a nota de decisão no fim deste Step.
  birthDate: DateTime
```

```yaml
indexes:
  users_cpf_hash_key:
    fields: cpfHash
    unique: true
  users_micro_area_idx:
    fields: microAreaId
```

**Atenção:** o índice deixa de ser não-único (`users_cpf_hash_idx` vira `users_cpf_hash_key`). Confira que não há duplicata antes de migrar:

```bash
psql -h localhost -U sinalacs_user -d sinalacs_db -c \
  'SELECT "cpfHash", count(*) FROM "users" GROUP BY 1 HAVING count(*) > 1;'
```

Expected: zero linhas.

- [ ] **Step 4: Gerar e migrar**

```bash
cd backend/sinalacs_server
serverpod generate
serverpod create-migration
```

Expected: `otp_challenge.dart` e `otp_request_exception.dart` gerados; migração nova com o
`DROP INDEX "users_cpf_hash_idx"` / `CREATE UNIQUE INDEX "users_cpf_hash_key"` e o
`CREATE TABLE "otp_challenges"`. **Nenhum `ALTER` em `birthDate`** — ver a decisão abaixo.

**DECISÃO (2026-09-18, tomada na execução): a recomendação de `spec/lgpd_data_audit.md:197`
— `birthDate` como `date`, não `timestamp` — NÃO é atendida, e não tem como ser por este
caminho.** O motivo é do framework, não do plano: o Serverpod não expõe tipo de coluna `date`
(`ColumnType` não tem a variante, e `DateTime` mapeia fixo para `timestamp without time
zone`). As alternativas foram pesadas e rejeitadas:

- escrever o `ALTER ... USING "birthDate"::date` à mão na migração: o `definition.sql`
  gerado continuaria dizendo `timestamp` enquanto o banco diria `date` — o schema-de-registro
  passaria a mentir, e um `serverpod create-repair-migration` reverteria a coluna;
- guardar a data como `String`: perde a tipagem em toda a cadeia por uma otimização de
  higiene de dado.

Consequência prática: a coluna carrega um componente de hora (sempre meia-noite UTC, porque é
o que o app envia) e o **serviço compara por dia** (`_sameDay`, ano/mês/dia em UTC), então a
funcionalidade do RF01 não depende do tipo. A recomendação fica registrada como **não
atendida** na Task 8, com este motivo — para o documento de LGPD não ler como satisfeita.

**Confira a migração gerada antes de commitá-la** — a conversão de `timestamp` para `date` é destrutiva para a parte de hora, e é isso mesmo que se quer, mas o SQL precisa ser `USING "birthDate"::date` para o Postgres não recusar a conversão implícita. Se o gerador não emitir o `USING`, corrija **à mão** nesse arquivo de migração (é a única exceção à regra "nunca editar migrations": o gerador não conhece `USING`, e o projeto aceita essa correção pontual desde que o SQL final esteja certo).

**O gerador vai ABORTAR por causa do índice único** e precisa de `--force`. Reportado por quem executou a Task 2 do RF07, que criou o índice único de `acs.enrollmentId`: `serverpod create-migration` recusa quando a migração inclui um índice único e pede `--force`. Esta task esbarra no mesmo aviso (`users_cpf_hash_key`, `unique: true`). Confirme que o `--force` não gera nada parcial — no RF07 a tentativa abortada não deixou resíduo:

```bash
cd backend/sinalacs_server
serverpod create-migration --force
```

**E o CLI pode não estar no PATH** — se `serverpod` não for encontrado:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

- [ ] **Step 5: Analisar**

Run: `cd backend && dart analyze`
Expected: nenhum problema.

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/lib/src/models/ \
        backend/sinalacs_server/lib/src/generated/ \
        backend/sinalacs_server/migrations/ \
        backend/sinalacs_client/
git commit -m "feat(backend): modelo otp_challenges e CPF unico em users (RF01)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 4: `PasswordlessAuthService` — pedido e verificação do código

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/auth/sms_gateway.dart`
- Create: `backend/sinalacs_server/lib/src/application/auth/passwordless_auth_service.dart`
- Test: `backend/sinalacs_server/test/unit/passwordless_auth_service_test.dart`

**Interfaces:**
- Consumes: `Cpf` (Task 1), `CpfHasher` (Task 2), `OtpRequestException` (Task 3), `AuditTrail`, `AuthenticatedUser`.
- Produces:
  - `abstract interface class SmsGateway { Future<void> sendOtp({required String phone, required String code}); }`
  - `class LoggingSmsGateway implements SmsGateway` e `class RecordingSmsGateway implements SmsGateway` (teste, expõe `sent`).
  - `class PatientCredentialRecord { final String userId; final DateTime birthDate; }`
  - `abstract interface class OtpChallengeStore { Future<PatientCredentialRecord?> findByCpfHash(String cpfHash); Future<void> save(OtpChallengeRecord challenge); Future<OtpChallengeRecord?> latestOpen(String userId, DateTime at); Future<void> registerAttempt(String challengeId, int attempts); Future<void> consume(String challengeId, DateTime at); }`
  - `class PasswordlessAuthService { Future<void> requestOtp({required Cpf cpf, required DateTime birthDate, DateTime? now}); Future<AuthenticatedUser> verifyOtp({required Cpf cpf, required String code, String? deviceId, DateTime? now}); }`

**Sobre o telefone:** não existe coluna de telefone em `Patient` nem no ER do PRD, e inventar um número seria fabricar dado. O `SmsGateway` recebe um `phone` que, hoje, é o **próprio CPF formatado** — um identificador que o gateway real vai traduzir para o número na integração, e que o gateway de log simplesmente imprime ao lado do código. A ausência de telefone é uma lacuna de produto registrada na Task 8, não algo que este plano resolva inventando uma coluna.

- [ ] **Step 1: Escrever o teste que falha**

Cria `backend/sinalacs_server/test/unit/passwordless_auth_service_test.dart`:

```dart
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/passwordless_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/sms_gateway.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';
import 'package:test/test.dart';

const _patientId = '00000000-0000-4000-8000-000000000001';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
final _cpf = Cpf.tryParse('12345678909')!;
final _nascimento = DateTime.utc(1990, 1, 1);

/// Fake que finge o store **tendo esquecido os filtros** de `latestOpen`.
///
/// Uso único e validade são duas propriedades de SEGURANÇA. O `_FakeStore`
/// aplica `consumedAt == null` e `expiresAt.isAfter(at)`, então nunca devolve
/// linha consumida nem expirada — e um teste escrito sobre ele não consegue
/// medir o dia em que o store real esquecer um dos dois. Este fake é esse dia,
/// simulado: devolve a linha mais recente do usuário, sem filtro nenhum.
class _FakeStoreSemFiltro extends _FakeStore {
  _FakeStoreSemFiltro({super.record});

  @override
  Future<OtpChallengeRecord?> latestOpen(String userId, DateTime at) async {
    final doUsuario = challenges.where(
      (challenge) => challenge.userId == userId,
    );
    return doUsuario.isEmpty ? null : doUsuario.last;
  }
}

class _FakeStore implements OtpChallengeStore {
  _FakeStore({this.record});

  PatientCredentialRecord? record;
  final challenges = <OtpChallengeRecord>[];

  @override
  Future<PatientCredentialRecord?> findByCpfHash(String cpfHash) async =>
      cpfHash == _hasher.hash(_cpf) ? record : null;

  /// O id é do store, não de quem chama.
  ///
  /// `save` **ignora** o `id` recebido: o serviço manda `id: ''` porque quem
  /// insere é o banco. Se o fake guardasse esse `''` verbatim, `consume('')`
  /// casaria por acidente, uma troca de id passaria despercebida e o teste de
  /// uso único provaria menos do que aparenta. Atribuir um id próprio é o que
  /// torna o fake fiel ao store que a Task 5 escreve.
  var _lastId = 0;

  @override
  Future<void> save(OtpChallengeRecord challenge) async {
    _lastId++;
    challenges.add(
      OtpChallengeRecord(
        id: 'desafio-$_lastId',
        userId: challenge.userId,
        codeHash: challenge.codeHash,
        attempts: challenge.attempts,
        createdAt: challenge.createdAt,
        expiresAt: challenge.expiresAt,
      ),
    );
  }

  @override
  Future<OtpChallengeRecord?> latestOpen(String userId, DateTime at) async {
    final open = challenges.where(
      (challenge) =>
          challenge.userId == userId &&
          challenge.consumedAt == null &&
          challenge.expiresAt.isAfter(at),
    );
    return open.isEmpty ? null : open.last;
  }

  /// Espelha o store real: a tentativa é REGISTRADA e o consumo é GRAVADO.
  ///
  /// Não podem ser no-op: com `consume` vazio o desafio continua aberto em
  /// `latestOpen`, e o teste "não deixa o código ser usado duas vezes" fica
  /// impossível de passar — foi o defeito que uma versão anterior deste plano
  /// tinha. Mesmo precedente de `_FakeStore.registerFailedAttempt` em
  /// `institutional_auth_service_test.dart`: o fake guarda o que o serviço
  /// mandou guardar, senão o que ele prova não é o serviço.
  @override
  Future<void> registerAttempt(String challengeId, int attempts) async {
    final index = challenges.indexWhere((c) => c.id == challengeId);
    if (index < 0) return;
    challenges[index] = OtpChallengeRecord(
      id: challenges[index].id,
      userId: challenges[index].userId,
      codeHash: challenges[index].codeHash,
      attempts: attempts,
      createdAt: challenges[index].createdAt,
      expiresAt: challenges[index].expiresAt,
      consumedAt: challenges[index].consumedAt,
    );
  }

  @override
  Future<void> consume(String challengeId, DateTime at) async {
    final index = challenges.indexWhere((c) => c.id == challengeId);
    if (index < 0) return;
    challenges[index] = OtpChallengeRecord(
      id: challenges[index].id,
      userId: challenges[index].userId,
      codeHash: challenges[index].codeHash,
      attempts: challenges[index].attempts,
      createdAt: challenges[index].createdAt,
      expiresAt: challenges[index].expiresAt,
      consumedAt: at,
    );
  }
}

// `extends`, não `implements`: `AuditTrail` é uma `abstract class` com
// `recordSafely` concreto, herdado de propósito por todo implementador.
class _RecordingAudit extends AuditTrail {
  final events = <AuditEvent>[];
  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

final _hasher = HmacCpfHasher(pepper: 'pepper-de-teste');

PasswordlessAuthService _build({
  PatientCredentialRecord? record,
  SmsGateway? gateway,
  _FakeStore? store,
  _RecordingAudit? audit,
}) =>
    PasswordlessAuthService(
      store: store ?? _FakeStore(record: record),
      hasher: _hasher,
      sms: gateway ?? RecordingSmsGateway(),
      audit: audit ?? _RecordingAudit(),
      codeGenerator: () => '123456',
    );

void main() {
  final encontrado = PatientCredentialRecord(
    userId: _patientId,
    birthDate: _nascimento,
    microAreaId: _microAreaId,
  );

  group('requestOtp', () {
    test('grava desafio e envia o código quando CPF e nascimento conferem', () async {
      final store = _FakeStore(record: encontrado);
      final gateway = RecordingSmsGateway();
      final service = _build(store: store, gateway: gateway);

      await service.requestOtp(cpf: _cpf, birthDate: _nascimento);

      expect(store.challenges, hasLength(1));
      expect(gateway.sent.single.code, '123456');
      // O código nunca é persistido: só o HMAC dele.
      expect(store.challenges.single.codeHash, isNot(contains('123456')));
      expect(store.challenges.single.codeHash, _hasher.hashOtpCode('123456'));
    });

    test('não revela CPF inexistente nem nascimento errado', () async {
      final inexistente = _build(store: _FakeStore());
      final nascimentoErrado = _build(
        store: _FakeStore(record: encontrado),
      );

      // Nenhum dos dois lança: a resposta é a mesma de um pedido bem-sucedido,
      // senão o formulário vira um oráculo de "este CPF está cadastrado".
      await expectLater(
        inexistente.requestOtp(cpf: _cpf, birthDate: _nascimento),
        completes,
      );
      await expectLater(
        nascimentoErrado.requestOtp(
          cpf: _cpf,
          birthDate: DateTime.utc(1991, 2, 2),
        ),
        completes,
      );
    });

    test('não envia SMS quando o CPF não existe', () async {
      final gateway = RecordingSmsGateway();
      await _build(store: _FakeStore(), gateway: gateway)
          .requestOtp(cpf: _cpf, birthDate: _nascimento);

      expect(gateway.sent, isEmpty);
    });

    test('expira em 5 minutos', () async {
      final store = _FakeStore(record: encontrado);
      final agora = DateTime.utc(2026, 9, 18, 12);
      await _build(store: store).requestOtp(
        cpf: _cpf,
        birthDate: _nascimento,
        now: agora,
      );

      expect(
        store.challenges.single.expiresAt,
        agora.add(PasswordlessAuthService.codeTtl),
      );
    });

    test('respeita o intervalo mínimo entre pedidos', () async {
      final store = _FakeStore(record: encontrado);
      final agora = DateTime.utc(2026, 9, 18, 12);
      final service = _build(store: store);

      await service.requestOtp(cpf: _cpf, birthDate: _nascimento, now: agora);

      // Um segundo pedido imediato lança para quem chamou, mas sem dizer nada
      // sobre o CPF — a mensagem é de fluxo, não de cadastro.
      await expectLater(
        service.requestOtp(cpf: _cpf, birthDate: _nascimento, now: agora),
        throwsA(isA<OtpRequestException>()),
      );
      expect(store.challenges, hasLength(1));
    });
  });

  group('verifyOtp', () {
    Future<PasswordlessAuthService> comCodigoPendente({
      _FakeStore? store,
      DateTime? agora,
    }) async {
      final target = store ?? _FakeStore(record: encontrado);
      final service = _build(store: target);
      await service.requestOtp(
        cpf: _cpf,
        birthDate: _nascimento,
        now: agora,
      );
      return service;
    }

    test('aceita o código correto e devolve paciente territorializado', () async {
      final service = await comCodigoPendente();

      final user = await service.verifyOtp(cpf: _cpf, code: '123456');

      expect(user.id, _patientId);
      expect(user.role, UserRole.patient);
      expect(user.microAreaId, _microAreaId);
    });

    test('recusa código errado', () async {
      final service = await comCodigoPendente();

      await expectLater(
        service.verifyOtp(cpf: _cpf, code: '000000'),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('recusa quando não há código pendente', () async {
      final service = _build(store: _FakeStore(record: encontrado));

      await expectLater(
        service.verifyOtp(cpf: _cpf, code: '123456'),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('recusa código expirado', () async {
      final agora = DateTime.utc(2026, 9, 18, 12);
      final service = await comCodigoPendente(agora: agora);

      await expectLater(
        service.verifyOtp(
          cpf: _cpf,
          code: '123456',
          now: agora.add(
            PasswordlessAuthService.codeTtl + const Duration(minutes: 1),
          ),
        ),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('não deixa o código ser usado duas vezes', () async {
      final service = await comCodigoPendente();

      await service.verifyOtp(cpf: _cpf, code: '123456');

      await expectLater(
        service.verifyOtp(cpf: _cpf, code: '123456'),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('audita cada desfecho', () async {
      final audit = _RecordingAudit();
      final service = await comCodigoPendente();
      // Reusa o mesmo audit nos dois caminhos.
      final instrumented = PasswordlessAuthService(
        store: service.store,
        hasher: _hasher,
        sms: RecordingSmsGateway(),
        audit: audit,
        codeGenerator: () => '123456',
      );

      await instrumented.verifyOtp(cpf: _cpf, code: '000000').then(
            (_) {},
            onError: (Object _) {},
          );
      await instrumented.verifyOtp(cpf: _cpf, code: '123456');

      expect(
        audit.events.map((event) => event.result).toList(),
        ['denied_code', 'granted'],
      );
      expect(
        audit.events.every((event) => event.resourceType == 'session'),
        isTrue,
      );
    });
  });
}
```

> **Três armadilhas de teste desta task, todas medidas na rodada de correção.**
>
> 1. **O teste do teto de tentativas era auto-referente.** Ele itera
>    `PasswordlessAuthService.maxAttempts` vezes e depois exige a recusa — o laço acompanha o
>    valor mutado, o contador chega exatamente nele e **qualquer** valor passa. A mutação
>    `maxAttempts = 500` deixava a suíte inteira verde; nenhum dos três mutantes de parâmetro
>    morria. Acrescente as asserções literais de `codeTtl`, `maxAttempts` e `resendCooldown`
>    num teste próprio, senão os três valores são decorativos.
> 2. **Prenda a MENSAGEM, não só a classe da exceção.** As recusas de `verifyOtp` usam a mesma
>    constante `_invalidCode` de propósito; um teste que só assevera
>    `throwsA(isA<OtpRequestException>())` fica verde no dia em que "CPF desconhecido" ganhar
>    mensagem própria — que é o oráculo que a task existe para impedir. Compare as duas
>    mensagens **entre si** (a igualdade é a propriedade; o literal pode mudar de redação).
>    Idem para as recusas de `requestOtp`: assevere que `store.challenges` e `audit.events`
>    ficaram **vazios**, não só que nenhum SMS saiu.
> 3. **O guard de fonte precisa de auto-asserção.** O teste que lê o corpo de
>    `LoggingSmsGateway.sendOtp` e recusa `\bphone\b` absolve tudo se a extração do corpo
>    quebrar e ele passar a ler o vazio. Exija `contains('code')` no mesmo corpo: sem isso, um
>    guard que não olha para lugar nenhum é indistinguível de um guard que aprova.

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/unit/passwordless_auth_service_test.dart`
Expected: FAIL — URIs de `sms_gateway.dart` e `passwordless_auth_service.dart` não existem.

- [ ] **Step 3: Escrever o gateway de SMS**

Cria `backend/sinalacs_server/lib/src/application/auth/sms_gateway.dart`:

```dart
import 'dart:io';

/// Envio do código OTP por SMS (RF01).
///
/// **Nenhum provedor está escolhido** — nem `spec/PRD_system.md` (que só cita
/// "SMS Gateway" como dependência), nem `spec/stack.md`, nem o documento de
/// decisões pós-validação. Escolher provedor é decisão de produto/infra, e
/// depende de conta, custo por mensagem e contrato, como o projeto Firebase do
/// RF14. Por isso a interface existe: o serviço de login não sabe quem envia, e
/// trocar o gateway é implementar esta interface.
abstract interface class SmsGateway {
  /// [phone] é o identificador de destino. Hoje é o CPF formatado, porque não
  /// existe coluna de telefone em `Patient` nem no ER do PRD — ver a lacuna
  /// registrada no plano. O gateway real traduz para o número na integração.
  Future<void> sendOtp({required String phone, required String code});
}

/// Gateway de desenvolvimento: **não envia SMS**, escreve o código no log do
/// processo para o desenvolvedor conseguir entrar.
///
/// Só é construído quando `SMS_GATEWAY=log`, que `AppConfig` recusa fora de
/// `APP_ENV=development`. O código é dado de curta duração e de uso único, mas
/// ainda assim vai para o log de propósito — é o único jeito de exercitar o
/// fluxo sem provedor — e o texto deixa isso explícito.
///
/// O **destino não entra no texto**. O único chamador preenche `phone` com
/// `cpf.formatted`, então imprimi-lo põe CPF em claro no log do processo, que a
/// constraint global proíbe sem cláusula de ambiente — e log de desenvolvimento
/// é justamente o que acaba colado numa issue. Um gateway real mascara um
/// telefone (`+55 ** ****-1234`), mas o destino deste é um CPF: máscara de CPF
/// ainda diz de quem é o dado. Quem lê este log acabou de digitar o CPF no
/// formulário e sabe de quem é a requisição; o que ele não tem é o código.
///
/// `phone` continua na assinatura mesmo sem uso: um `override` de parâmetro
/// nomeado casa **por nome**, então tirá-lo quebraria o contrato da interface —
/// e o gateway real precisa dele para endereçar a mensagem. O que dá para tornar
/// impossível é **usar** o valor, e é isso que o teste de fonte em
/// `passwordless_auth_service_test.dart` prende, com uma auto-asserção
/// (`contains('code')`) para não absolver tudo caso a extração do corpo quebre.
class LoggingSmsGateway implements SmsGateway {
  const LoggingSmsGateway();

  @override
  Future<void> sendOtp({required String phone, required String code}) async {
    // O texto sai só do código; o destino é deliberadamente ignorado.
    stdout.writeln(
      '[SMS-GATEWAY=log] código de acesso: $code '
      '(gateway de desenvolvimento — nenhum SMS foi enviado)',
    );
  }
}

/// Gateway de teste: guarda o que "enviaria" para o teste asseverar.
class RecordingSmsGateway implements SmsGateway {
  final sent = <({String phone, String code})>[];

  @override
  Future<void> sendOtp({required String phone, required String code}) async {
    sent.add((phone: phone, code: code));
  }
}
```

- [ ] **Step 4: Escrever o serviço**

Cria `backend/sinalacs_server/lib/src/application/auth/passwordless_auth_service.dart`:

```dart
import 'dart:math';

import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/cpf_hasher.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/sms_gateway.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// O que o login precisa saber sobre o paciente, sem `application/` conhecer o
/// ORM.
class PatientCredentialRecord {
  const PatientCredentialRecord({
    required this.userId,
    required this.birthDate,
    required this.microAreaId,
  });

  final String userId;

  /// Data sem hora: a comparação é de dia, não de instante.
  final DateTime birthDate;

  final String? microAreaId;
}

/// O desafio como o ORM o entrega, já traduzido.
class OtpChallengeRecord {
  const OtpChallengeRecord({
    required this.id,
    required this.userId,
    required this.codeHash,
    required this.attempts,
    required this.createdAt,
    required this.expiresAt,
    this.consumedAt,
  });

  final String id;
  final String userId;
  final String codeHash;
  final int attempts;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? consumedAt;
}

/// Acesso a `users` (por hash de CPF) e a `otp_challenges`.
abstract interface class OtpChallengeStore {
  Future<PatientCredentialRecord?> findByCpfHash(String cpfHash);

  Future<void> save(OtpChallengeRecord challenge);

  /// Desafio mais recente, não consumido e ainda dentro da validade.
  Future<OtpChallengeRecord?> latestOpen(String userId, DateTime at);

  Future<void> registerAttempt(String challengeId, int attempts);

  Future<void> consume(String challengeId, DateTime at);
}

/// Login passwordless do paciente (RF01): CPF + data de nascimento + código.
class PasswordlessAuthService {
  PasswordlessAuthService({
    required this.store,
    required this.hasher,
    required this.sms,
    required this.audit,
    String Function()? codeGenerator,
  }) : _generateCode = codeGenerator ?? _randomCode;

  final OtpChallengeStore store;
  final CpfHasher hasher;
  final SmsGateway sms;
  final AuditTrail audit;
  final String Function() _generateCode;

  /// Cinco minutos: tempo de o SMS chegar e a pessoa digitar, sem deixar um
  /// código válido circulando por muito tempo.
  static const codeTtl = Duration(minutes: 5);

  /// Teto de verificações por desafio. 6 dígitos são 10^6 combinações; sem
  /// contador, um código enviado seria uma porta aberta a força bruta.
  static const maxAttempts = 5;

  /// Intervalo mínimo entre dois pedidos, para um CPF conhecido não virar
  /// gerador de SMS pago.
  static const resendCooldown = Duration(seconds: 60);

  static const _invalidInput = 'Confira os dados informados.';
  static const _resendTooSoon = 'Um código já foi enviado. Aguarde um minuto '
      'antes de pedir outro.';
  static const _invalidCode = 'Código inválido ou expirado. Peça um novo.';

  /// `requestOtp` devolve `void` e **não** distingue "enviado" de "CPF não
  /// encontrado": qualquer diferença de resposta transformaria este endpoint num
  /// verificador de quem é paciente da unidade.
  ///
  /// A igualdade é de **payload, status e efeitos**: as duas recusas não
  /// lançam, não gravam desafio, não enviam SMS e não escrevem auditoria.
  ///
  /// O **tempo não está equalizado**, e a versão anterior deste comentário
  /// dizia o contrário: o caminho válido faz um `latestOpen`, um `save` e o
  /// envio, que a recusa não faz. Um cronômetro distingue os dois. Não dá para
  /// equalizar aqui sem mentir sobre o envio; quando houver gateway de verdade
  /// o termo dominante é a ida ao provedor, e tirar o envio do caminho de
  /// resposta é a correção. Lacuna registrada na Task 8 — não resolvida.
  Future<void> requestOtp({
    required Cpf cpf,
    required DateTime birthDate,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByCpfHash(hasher.hash(cpf));

    if (record == null || !_sameDay(record.birthDate, birthDate)) {
      // Sem envio, sem lançamento: o formulário segue para a tela do código.
      return;
    }

    final open = await store.latestOpen(record.userId, at);
    if (open != null && at.difference(open.createdAt) < resendCooldown) {
      // Aqui lançar é seguro: chegar neste ponto exige CPF **e** nascimento
      // corretos, então a exceção não revela nada a quem sonda.
      throw OtpRequestException(message: _resendTooSoon);
    }

    final code = _generateCode();
    await store.save(
      OtpChallengeRecord(
        id: '',
        userId: record.userId,
        codeHash: hasher.hashOtpCode(code),
        attempts: 0,
        createdAt: at,
        expiresAt: at.add(codeTtl),
      ),
    );
    await sms.sendOtp(phone: cpf.formatted, code: code);
    await _recordAudit(record.userId, 'otp_requested');
  }

  Future<AuthenticatedUser> verifyOtp({
    required Cpf cpf,
    required String code,
    String? deviceId,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    if (code.trim().length != 6) {
      throw OtpRequestException(message: _invalidInput);
    }

    final record = await store.findByCpfHash(hasher.hash(cpf));
    if (record == null) {
      throw OtpRequestException(message: _invalidCode);
    }

    final challenge = await store.latestOpen(record.userId, at);
    // Consumo e validade são checados AQUI também, e não só no filtro de
    // `latestOpen`. O store da Task 5 filtra os dois, então contra ele este
    // trecho é inalcançável — é defesa em profundidade de propósito: sem ele,
    // uso único e TTL são duas propriedades de SEGURANÇA apoiadas só numa
    // consulta de um arquivo, e o dia em que essa consulta esquecer um filtro
    // não tem quem avise. Com o defeito, o serviço CONCEDIA ACESSO a um desafio
    // já consumido e a um expirado (medido no RED da rodada de correção).
    if (challenge == null ||
        challenge.consumedAt != null ||
        !challenge.expiresAt.isAfter(at) ||
        challenge.attempts >= maxAttempts) {
      await _recordAudit(record.userId, 'denied_code');
      throw OtpRequestException(message: _invalidCode);
    }

    if (challenge.codeHash != hasher.hashOtpCode(code.trim())) {
      await store.registerAttempt(challenge.id, challenge.attempts + 1);
      await _recordAudit(record.userId, 'denied_code');
      throw OtpRequestException(message: _invalidCode);
    }

    final microAreaId = record.microAreaId;
    if (microAreaId == null) {
      await _recordAudit(record.userId, 'denied_no_territory');
      throw OtpRequestException(
        message: 'Este acesso não está vinculado a uma microárea.',
      );
    }

    await store.consume(challenge.id, at);
    await _recordAudit(record.userId, 'granted');

    return AuthenticatedUser(
      id: record.userId,
      role: UserRole.patient,
      microAreaId: microAreaId,
      deviceId: deviceId ?? 'nao-aplicavel-login-passwordless',
    );
  }

  /// Compara ano/mês/dia em UTC, **não instantes**: `birthDate` é
  /// `timestamp without time zone` (o Serverpod não expõe tipo de coluna
  /// `date`) carregando sempre meia-noite UTC, e a data digitada pelo app
  /// também. Comparar instantes recusaria um nascimento correto por causa de
  /// fuso, e comparar só o dia é o que a credencial do RF01 significa.
  bool _sameDay(DateTime a, DateTime b) =>
      a.toUtc().year == b.toUtc().year &&
      a.toUtc().month == b.toUtc().month &&
      a.toUtc().day == b.toUtc().day;

  Future<void> _recordAudit(String userId, String result) =>
      audit.recordSafely(
        AuditEvent(
          userId: userId,
          actionType: 'login',
          resourceType: 'session',
          result: result,
        ),
      );

  /// `Random.secure()`, zero à esquerda preservado: um código de 6 dígitos
  /// precisa ter 10^6 possibilidades, e não 9×10^5.
  static String _randomCode() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < 6; index++) {
      buffer.write(random.nextInt(10));
    }
    return buffer.toString();
  }
}
```

- [ ] **Step 5: Rodar o teste e confirmar que passa**

Run: `cd backend/sinalacs_server && dart test test/unit/passwordless_auth_service_test.dart`
Expected: PASS — 11 testes.

- [ ] **Step 6: Rodar a suíte inteira**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS — contagem anterior + 6 (Task 1) + 5 (Task 2) + 2 (config) + 11.

- [ ] **Step 7: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/auth/sms_gateway.dart \
        backend/sinalacs_server/lib/src/application/auth/passwordless_auth_service.dart \
        backend/sinalacs_server/test/unit/passwordless_auth_service_test.dart
git commit -m "feat(backend): PasswordlessAuthService com OTP, limite de tentativas e auditoria (RF01)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 5: Store ORM, runtime e os endpoints `auth.requestOtp` / `auth.verifyOtp`

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_otp_challenge_store.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart`
- Test: `backend/sinalacs_server/test/integration/passwordless_login_test.dart`

**Interfaces:**
- Consumes: tudo da Task 4.
- Produces: `auth.requestOtp(cpf, birthDate)` e `auth.verifyOtp(cpf, code, deviceId?) → DevelopmentLoginResult`; `AlertRuntime.instance.passwordlessAuthServiceFor(session)`.

> **Duas obrigações de fidelidade que o teste unitário da Task 4 não alcança.**
>
> O store que a Task 4 pressupõe — e que o fake do teste dela espelha — tem
> quatro semânticas que a interface sozinha não declara: `save` **ignora o `id`
> recebido e atribui o seu** (o serviço manda `id: ''`, porque o id é do banco)
> e o devolve em `latestOpen`; `latestOpen` filtra `consumedAt IS NULL AND
> expiresAt > at`, do mais recente; `registerAttempt` grava a contagem
> **absoluta**; `consume` não desfaz consumo. Um store que honre o `id: ''` faz
> `consume('')` casar por acidente e a garantia de uso único evapora **com a
> suíte verde**. Prove cada uma com asserção contra o Postgres — não só contra o
> retorno do endpoint, que passaria mesmo com o filtro errado.
>
> **Lacuna de tempo, registrada e não resolvida.** O caminho válido de
> `requestOtp` faz um `latestOpen`, um `save` e o envio de SMS; as duas recusas
> (CPF inexistente, nascimento errado) fazem um `latestOpen` e retornam. Payload,
> status e efeitos são idênticos — isso está provado por teste —, mas o **tempo
> não é**: um cronômetro distingue "este CPF com este nascimento é de um paciente
> da unidade". Não é corrigível dentro do serviço sem mentir sobre o envio, e com
> gateway de verdade o termo dominante passa a ser a ida ao provedor. Decisão
> desta etapa: manter o envio no caminho de resposta, tratar a diferença como
> limitação conhecida e registrá-la na Task 8 — não fingir que a igualdade é
> total. Tirar o envio do caminho de resposta é a correção quando o provedor
> chegar.

- [ ] **Step 1: Escrever o teste de integração que falha**

Cria `backend/sinalacs_server/test/integration/passwordless_login_test.dart`:

```dart
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Login passwordless contra Postgres real: prova o JOIN por `cpfHash` e a
/// passagem por `otp_challenges` que o teste unitário (store falso) não alcança.
void main() {
  withServerpod('Dado o login passwordless do paciente (RF01)', (
    sessionBuilder,
    endpoints,
  ) {
    const patientId = '00000000-0000-4000-8000-000000000001';
    final cpf = Cpf.tryParse('12345678909')!;
    final nascimento = DateTime.utc(1990, 1, 1);

    setUp(() async {
      final session = sessionBuilder.build();

      // O harness `withServerpod` aplica as MIGRAÇÕES, nunca o
      // `development.sql`: o paciente do seed NÃO existe no banco de teste, e
      // um `findById` seguido de `user!` estoura null-check antes de qualquer
      // asserção. (Foi o defeito que quem executou a Task 4 do RF07 encontrou no
      // teste irmão de lá.) Insere o mínimo que o caminho exige — UBS, microárea
      // e o usuário paciente — com UUIDs sintéticos próprios para não colidir
      // com os de outros arquivos de integração que rodam sob o mesmo banco.
      await _seedPatient(session, patientId);

      final user = await User.db.findById(
        session,
        UuidValue.fromString(patientId),
      );
      user!
        ..cpfHash = AlertRuntime.instance.cpfHasherForTests.hash(cpf)
        ..birthDate = nascimento;
      await User.db.updateRow(session, user);
    });

    test('o código pedido permite entrar e devolver token de paciente', () async {
      final session = sessionBuilder.build();
      final gateway = RecordingSmsGateway();
      AlertRuntime.instance.overrideSmsGateway(gateway);

      // Endpoint recebe o próprio `sessionBuilder`; `sessionBuilder.build()` é
      // para acesso direto ao banco (ver `onboarding_endpoint_test.dart:236`).
      await endpoints.auth.requestOtp(
        sessionBuilder,
        cpf: cpf.digits,
        birthDate: nascimento,
      );

      // O gateway de teste guarda o código que "enviaria" — é o único lugar
      // onde o código em claro existe, por desenho.
      expect(gateway.sent, hasLength(1));

      final result = await endpoints.auth.verifyOtp(
        sessionBuilder,
        cpf: cpf.digits,
        code: gateway.sent.single.code,
      );

      expect(result.accessToken, isNotEmpty);
      expect(
        AlertRuntime.instance.auth.verifyToken(result.accessToken)?.role,
        UserRole.patient,
      );

      // Prova que o código em claro NÃO está no banco.
      final challenge = await OtpChallenge.db.findFirstRow(
        session,
        where: (table) => table.userId.equals(UuidValue.fromString(patientId)),
        orderBy: (table) => table.createdAt,
        orderDescending: true,
      );
      expect(challenge!.codeHash.length, 64);
      expect(challenge.codeHash.contains(gateway.sent.single.code), isFalse);
      expect(challenge.consumedAt, isNotNull);
    });

    test('CPF não cadastrado não grava desafio', () async {
      final session = sessionBuilder.build();
      final outro = Cpf.tryParse('98765432100')!;

      await endpoints.auth.requestOtp(
        sessionBuilder,
        cpf: outro.digits,
        birthDate: nascimento,
      );

      final challenges = await OtpChallenge.db.find(session);
      expect(challenges, isEmpty);
    });

    test('código inválido é recusado pelo endpoint com a exceção tipada', () async {
      await expectLater(
        endpoints.auth.verifyOtp(
          sessionBuilder,
          cpf: cpf.digits,
          code: '000000',
        ),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('data de nascimento errada não gera desafio', () async {
      final session = sessionBuilder.build();

      await endpoints.auth.requestOtp(
        sessionBuilder,
        cpf: cpf.digits,
        birthDate: DateTime.utc(1991, 2, 2),
      );

      expect(await OtpChallenge.db.find(session), isEmpty);
    });
  });
}

/// Semeia o mínimo que o login passwordless exige: UBS, microárea e o usuário
/// paciente (o `users` é quem carrega `cpfHash`/`birthDate`/`microAreaId`).
///
/// UUIDs sintéticos e **próprios deste arquivo**: vários testes de integração
/// rodam sob o mesmo banco e reusam `…0002`/`…0003`/`…0004`, o que funciona
/// porque o harness reverte cada caso (`rollbackDatabase` = `afterEach`), mas
/// usar um espaço próprio evita depender disso.
Future<void> _seedPatient(Session session, String patientId) async {
  const ubsId = '00000000-0000-4000-9000-000000000001';
  const microAreaId = '00000000-0000-4000-9000-000000000002';

  await Ubs.db.insertRow(
    session,
    Ubs(id: UuidValue.fromString(ubsId), name: 'UBS Teste RF01', address: 'Endereço sintético', city: 'São Paulo', state: 'SP'),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(id: UuidValue.fromString(microAreaId), name: 'Microárea Teste RF01', ubsId: UuidValue.fromString(ubsId), geoJsonBoundary: '{}'),
  );
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(patientId),
      // Placeholder: o `setUp` sobrescreve com o HMAC real do CPF sintético.
      cpfHash: 'a-definir-no-setup',
      name: 'Paciente Sintético RF01',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      microAreaId: microAreaId,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
  );
  await Patient.db.insertRow(
    session,
    Patient(id: UuidValue.fromString(patientId), emergencyContact: 'Contato sintético', isChronic: false, chronicConditionsEncrypted: '', chronicConditionsKeyVersion: 1),
  );
}
```

Não esqueça o `tearDown` restaurando o gateway (`AlertRuntime.instance.overrideSmsGateway(null)`), no mesmo estilo do `overrideConfig` que os testes de integração já usam.

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/integration/passwordless_login_test.dart`
Expected: FAIL — `orm_otp_challenge_store.dart` não existe.

- [ ] **Step 3: Escrever o store ORM e ligar no runtime**

Cria `backend/sinalacs_server/lib/src/infrastructure/database/orm_otp_challenge_store.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/passwordless_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

class OrmOtpChallengeStore implements OtpChallengeStore {
  OrmOtpChallengeStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<PatientCredentialRecord?> findByCpfHash(String cpfHash) async {
    final session = _session();
    final user = await User.db.findFirstRow(
      session,
      where: (table) => table.cpfHash.equals(cpfHash),
    );
    if (user == null) return null;

    return PatientCredentialRecord(
      userId: user.id!,
      birthDate: user.birthDate,
      microAreaId: user.microAreaId,
    );
  }

  @override
  Future<void> save(OtpChallengeRecord challenge) async {
    final session = _session();
    await OtpChallenge.db.insertRow(
      session,
      OtpChallenge(
        userId: UuidValue.fromString(challenge.userId),
        codeHash: challenge.codeHash,
        attempts: challenge.attempts,
        createdAt: challenge.createdAt,
        expiresAt: challenge.expiresAt,
        consumedAt: null,
      ),
    );
  }

  @override
  Future<OtpChallengeRecord?> latestOpen(String userId, DateTime at) async {
    final session = _session();
    final row = await OtpChallenge.db.findFirstRow(
      session,
      where: (table) =>
          table.userId.equals(UuidValue.fromString(userId)) &
          table.consumedAt.equals(null) &
          table.expiresAt.greaterThan(at),
      orderBy: (table) => table.createdAt,
      orderDescending: true,
    );
    return row == null ? null : _toRecord(row);
  }

  @override
  Future<void> registerAttempt(String challengeId, int attempts) async {
    final session = _session();
    final row = await OtpChallenge.db.findById(
      session,
      UuidValue.fromString(challengeId),
    );
    if (row == null) return;
    row.attempts = attempts;
    await OtpChallenge.db.updateRow(session, row);
  }

  @override
  Future<void> consume(String challengeId, DateTime at) async {
    final session = _session();
    final row = await OtpChallenge.db.findById(
      session,
      UuidValue.fromString(challengeId),
    );
    if (row == null) return;
    row.consumedAt = at;
    await OtpChallenge.db.updateRow(session, row);
  }

  OtpChallengeRecord _toRecord(OtpChallenge row) => OtpChallengeRecord(
        id: row.id!,
        userId: row.userId,
        codeHash: row.codeHash,
        attempts: row.attempts,
        createdAt: row.createdAt,
        expiresAt: row.expiresAt,
        consumedAt: row.consumedAt,
      );
}
```

Em `alert_runtime.dart`, acrescente:

```dart
  /// Gateway de SMS. Sem override, é o de `SMS_GATEWAY` — e `log` só existe
  /// em development (ver AppConfig).
  SmsGateway? _smsGatewayOverride;
  SmsGateway? _smsGateway;

  @visibleForTesting
  void overrideSmsGateway(SmsGateway? gateway) => _smsGatewayOverride = gateway;

  SmsGateway get smsGateway => _smsGatewayOverride ??
      (_smsGateway ??= config.smsGateway == 'log'
          ? const LoggingSmsGateway()
          : throw StateError(
              'SMS_GATEWAY=${config.smsGateway} não tem implementação: só '
              '"log" existe hoje. Implemente SmsGateway antes de configurá-lo.',
            ));

  /// Hash de CPF/código OTP (RF01).
  CpfHasher get cpfHasher => _cpfHasher ??= HmacCpfHasher(pepper: config.cpfHashPepper);
  CpfHasher? _cpfHasher;

  /// Exposto para os testes de integração que precisam gravar o hash de um CPF
  /// sintético sem passar pelo fluxo de login.
  @visibleForTesting
  CpfHasher get cpfHasherForTests => cpfHasher;

  /// Serviço de login passwordless para uma requisição.
  PasswordlessAuthService passwordlessAuthServiceFor(Session session) =>
      PasswordlessAuthService(
        store: OrmOtpChallengeStore(session: () => session),
        hasher: cpfHasher,
        sms: smsGateway,
        audit: auditTrailFor(session),
      );
```

Lembre de zerar `_cpfHasher`/`_smsGateway` em `overrideConfig` (o método já zera `_auth`/`_healthDataCipher` pelo mesmo motivo).

**E acrescente os dois métodos à allowlist do guard de postura.** O plano de RBAC (Task 4)
entregou `test/unit/endpoint_auth_posture_test.dart`, que agora exige que **todo método
público que recebe `Session session`** chame `authenticate(...)`/`authenticateToken(...)`
ou conste de `_publicMethodsByDesign` com o motivo. `requestOtp` e `verifyOtp` são públicos
por desenho — é o login de quem ainda não tem sessão —, então sem estas entradas a suíte
fica vermelha no primeiro `dart test` depois deles:

```dart
  'AuthEndpoint.requestOtp':
      'login por desenho: quem pede o código ainda não tem sessão',
  'AuthEndpoint.verifyOtp':
      'login por desenho: é esta chamada que emite a sessão do paciente',
```

Rode `cd backend/sinalacs_server && dart test test/unit/endpoint_auth_posture_test.dart` e
confirme que volta a passar.

- [ ] **Step 4: Adicionar os endpoints e registrar a postura pública deles**

Em `auth_endpoint.dart`:

```dart
  /// Pedido do código de acesso (RF01). Público por definição: quem chama
  /// ainda não tem sessão. A resposta é sempre a mesma — não revela se o CPF
  /// está cadastrado (ver `PasswordlessAuthService.requestOtp`).
  Future<void> requestOtp(
    Session session, {
    required String cpf,
    required DateTime birthDate,
  }) async {
    final parsed = Cpf.tryParse(cpf);
    if (parsed == null) {
      throw OtpRequestException(message: 'Confira os dados informados.');
    }

    await AlertRuntime.instance
        .passwordlessAuthServiceFor(session)
        .requestOtp(cpf: parsed, birthDate: birthDate);
  }

  /// Verificação do código, que emite a sessão do paciente (RF01).
  Future<DevelopmentLoginResult> verifyOtp(
    Session session, {
    required String cpf,
    required String code,
    String? deviceId,
  }) async {
    final parsed = Cpf.tryParse(cpf);
    if (parsed == null) {
      throw OtpRequestException(message: 'Código inválido ou expirado. Peça um novo.');
    }

    final runtime = AlertRuntime.instance;
    final user = await runtime
        .passwordlessAuthServiceFor(session)
        .verifyOtp(cpf: parsed, code: code, deviceId: deviceId);

    return DevelopmentLoginResult(
      // O TTL do paciente é definido aqui e vale 1 hora — ver as Global
      // Constraints e a Task 7. Nesta task a constante ainda não existe, então
      // use `runtime.auth.issueToken(user)` (o padrão de 15 min) e deixe a
      // Task 7 trocar esta chamada por:
      //   runtime.auth.issueToken(user, lifetime: patientSessionLifetime)
      accessToken: runtime.auth.issueToken(user),
      tokenType: 'Bearer',
    );
  }
```

Se ao final da Task 5 o `dart analyze` reclamar de `patientSessionLifetime` indefinido, é sinal de que a Task 7 ainda não rodou — mantenha o `issueToken(user)` sem a constante até lá.

- [ ] **Step 5: Regenerar o cliente**

Adicionar métodos a um endpoint **não** basta para o app enxergá-los: o cliente
tipado carrega um stub por método (`backend/sinalacs_client/lib/src/protocol/client.dart:100`
é a classe `EndpointAuth`), e o stub só passa a existir depois do gerador rodar. Sem
este passo a Task 7 falha ao compilar em `_client.auth.requestOtp(...)`, com um erro
que aponta para o app e não para a causa.

```bash
cd backend/sinalacs_server
serverpod generate
```

Expected: `client.dart` ganha `requestOtp` e `verifyOtp` na classe `EndpointAuth`.
Confirme com:

```bash
grep -n "requestOtp\|verifyOtp" ../sinalacs_client/lib/src/protocol/client.dart
```

Expected: duas ocorrências, dentro de `EndpointAuth`.

- [ ] **Step 6: Rodar os testes de integração**

Run: `cd backend/sinalacs_server && dart test test/integration/passwordless_login_test.dart`
Expected: PASS — os 4 testes do esqueleto mais o do caminho feliz.

- [ ] **Step 7: Rodar a suíte inteira e commitar**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS.

```bash
git add backend/sinalacs_server/lib/src/infrastructure/database/orm_otp_challenge_store.dart \
        backend/sinalacs_server/lib/src/runtime/alert_runtime.dart \
        backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart \
        backend/sinalacs_server/lib/src/generated/ \
        backend/sinalacs_client/ \
        backend/sinalacs_server/test/integration/passwordless_login_test.dart
git commit -m "feat(backend): endpoints auth.requestOtp/verifyOtp com store ORM (RF01)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 6: Seed dos hashes de CPF

**Files:**
- Create: `backend/sinalacs_server/bin/seed_cpf_hashes.dart`
- Modify: `docker-compose.yml`

**Interfaces:**
- Consumes: `HmacCpfHasher` (Task 2), `Cpf` (Task 1).
- Produces: CPFs sintéticos conhecidos no banco de desenvolvimento, sem os quais `requestOtp` nunca encontra paciente nenhum.

Sem isto a stack sobe com `users.cpfHash` contendo os literais `'development-patient'`, que **nenhum HMAC produz** — o login passwordless seria impossível de exercitar.

- [ ] **Step 1: Escrever o script**

Cria `backend/sinalacs_server/bin/seed_cpf_hashes.dart`:

```dart
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';

/// Quarta metade do seed de desenvolvimento: os hashes de CPF do RF01.
///
/// `seeds/development.sql` gravava literais (`'development-patient'`) porque
/// nenhum código calculava CPF. Agora que o login procura por
/// `users.cpfHash = HMAC(cpf)`, um literal nunca casa — e o paciente de
/// desenvolvimento não conseguiria entrar.
///
/// CPFs SINTÉTICOS, os exemplos da documentação do algoritmo de dígito
/// verificador. **Nunca** um CPF real (regra do repositório: nada de dado real
/// em seed, teste ou log).
const _cpfByUser = <String, String>{
  '00000000-0000-4000-8000-000000000001': '12345678909',
  '00000000-0000-4000-8000-000000000005': '98765432100',
  '00000000-0000-4000-8000-000000000006': '11144477735',
  '00000000-0000-4000-8000-000000000007': '52998224725',
  '00000000-0000-4000-8000-000000000008': '16899535009',
};

/// Datas de nascimento correspondentes (as mesmas do `development.sql`).
const _birthDateByUser = <String, String>{
  '00000000-0000-4000-8000-000000000001': '1990-01-01',
  '00000000-0000-4000-8000-000000000005': '1975-03-10',
  '00000000-0000-4000-8000-000000000006': '1988-07-22',
  '00000000-0000-4000-8000-000000000007': '1962-11-30',
  '00000000-0000-4000-8000-000000000008': '1999-05-14',
};

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final config = AppConfig.fromEnvironment();

  if (config.appEnv != 'development') {
    stderr.writeln(
      'Recusando rodar: este script grava CPFs SINTÉTICOS de desenvolvimento e '
      'APP_ENV=${config.appEnv}.',
    );
    exit(2);
  }

  // A MESMA instância que o servidor usa, pelo mesmo pepper: se divergirem,
  // nenhum CPF do seed é encontrado no login.
  final hasher = HmacCpfHasher(pepper: config.cpfHashPepper);

  final connection = await Connection.open(
    Endpoint(
      host: env['SERVERPOD_DATABASE_HOST'] ?? 'localhost',
      port: int.parse(env['SERVERPOD_DATABASE_PORT'] ?? '5432'),
      database: env['SERVERPOD_DATABASE_NAME'] ?? 'sinalacs_db',
      username: env['SERVERPOD_DATABASE_USER'] ?? 'sinalacs_user',
      password: env['SERVERPOD_DATABASE_PASSWORD'],
    ),
    settings: ConnectionSettings(
      sslMode: env['SERVERPOD_DATABASE_REQUIRE_SSL'] == 'true'
          ? SslMode.require
          : SslMode.disable,
    ),
  );

  try {
    var atualizados = 0;
    for (final entry in _cpfByUser.entries) {
      final cpf = Cpf.tryParse(entry.value);
      if (cpf == null) {
        // Falha alto em vez de gravar um hash de CPF inválido: um DV errado no
        // mapa acima produziria um paciente que existe e não consegue entrar.
        throw StateError('CPF sintético inválido para ${entry.key}: ${entry.value}');
      }
      final result = await connection.execute(
        Sql.named(
          'UPDATE "users" '
          '   SET "cpfHash" = @cpfHash, "birthDate" = @birthDate::date, '
          '       "updatedAt" = NOW() '
          ' WHERE "id" = @id',
        ),
        parameters: {
          'cpfHash': hasher.hash(cpf),
          'birthDate': _birthDateByUser[entry.key],
          'id': entry.key,
        },
      );
      atualizados += result.affectedRows;
    }
    stdout.writeln('Seed de CPF (RF01): $atualizados linha(s) de users atualizada(s).');
  } finally {
    await connection.close();
  }
}
```

**Verifique os dígitos verificadores dos três CPFs novos** (`11144477735`, `52998224725`, `16899535009`) rodando o script — ele mesmo valida. Se algum falhar, o `StateError` diz qual. Se preferir gerar outros, calcule com o algoritmo e ajuste.

- [ ] **Step 2: Acrescentar o serviço ao compose**

Em `docker-compose.yml`, depois do `acs-credential-seed`:

```yaml
  # Quarta metade do seed: os hashes de CPF do login passwordless (RF01), que
  # dependem do pepper e por isso só existem em Dart.
  cpf-hash-seed:
    image: sinalacs/server:local
    depends_on:
      database-seed:
        condition: service_completed_successfully
    environment:
      SERVERPOD_DATABASE_HOST: postgres
      SERVERPOD_DATABASE_PORT: "5432"
      SERVERPOD_DATABASE_NAME: ${POSTGRES_DB:-sinalacs_db}
      SERVERPOD_DATABASE_USER: ${POSTGRES_USER:-sinalacs_user}
      SERVERPOD_DATABASE_PASSWORD: ${POSTGRES_PASSWORD:?defina em .env — rode ./scripts/dev/bootstrap_env.sh}
      SERVERPOD_DATABASE_REQUIRE_SSL: "false"
      # O MESMO pepper do servidor — e por isso o serviço `serverpod` TAMBÉM
      # precisa recebê-lo (ver o Step 2b). Sem isso o seed grava HMACs com o
      # pepper real do `.env` enquanto o servidor procura com o fallback
      # público, e **nenhum CPF semeado é encontrado no login**.
      #
      # `:-` e não `:?` de propósito, seguindo o `HEALTH_DATA_ENCRYPTION_KEY`
      # logo acima: o Compose interpola o arquivo INTEIRO, então um `:?` aqui
      # derruba toda invocação de `docker compose` numa máquina cujo `.env` é
      # anterior à variável — não só este serviço. O guarda não se perde: fora
      # de development o `AppConfig` recusa subir, que é onde a regra pertence.
      CPF_HASH_PEPPER: ${CPF_HASH_PEPPER:-}
      APP_ENV: ${APP_ENV:-development}
    entrypoint: ["./seed_cpf_hashes"]
```

Confirme que o `Dockerfile` compila este entrypoint (ver a nota da Task 5 do plano de RF07).

- [ ] **Step 2b: Dar o pepper TAMBÉM ao serviço `serverpod`**

Achado do review da Task 2, e é determinístico, não hipotético: o bloco
`environment:` do serviço `serverpod` (docker-compose.yml:96-128) recebe
`JWT_SECRET` e `HEALTH_DATA_ENCRYPTION_KEY`, mas **não** `CPF_HASH_PEPPER`, e o
arquivo não tem `env_file:` em lugar nenhum. Sem esta linha o servidor cai no
fallback público `development-cpf-hash-pepper` enquanto o seed grava com o pepper
real do `.env` — e o login não encontra nenhum paciente semeado.

É a mesma razão pela qual `HEALTH_DATA_ENCRYPTION_KEY` aparece **duas** vezes no
arquivo (`:126` no servidor, `:168` no `health-data-seed`): as duas pontas
precisam derivar a mesma chave.

Acrescente ao bloco `environment:` do serviço `serverpod`, ao lado do
`HEALTH_DATA_ENCRYPTION_KEY`:

```yaml
      # Pepper do HMAC de `users.cpfHash` (RF01). PRECISA ser o mesmo valor que o
      # `cpf-hash-seed` recebe, pela mesma razão do
      # HEALTH_DATA_ENCRYPTION_KEY acima: o seed deriva o hash e o servidor o
      # procura — com peppers diferentes, nenhum CPF semeado é encontrado.
      CPF_HASH_PEPPER: ${CPF_HASH_PEPPER:-}
```

Depois disso, `docker compose config` precisa continuar passando, e a
**Verificação final** do plano tem de provar a concordância de verdade: com a
stack de pé e o seed aplicado, um `requestOtp` para um dos CPFs semeados tem de
encontrar o paciente (o log do `SMS_GATEWAY=log` mostra o código pedido). Se não
encontrar, os dois peppers divergiram.

- [ ] **Step 3: Verificar na stack**

```bash
docker compose up --build -d
docker compose logs cpf-hash-seed
```

Expected: `Seed de CPF (RF01): 5 linha(s) de users atualizada(s).`

Confirme que o hash gravado **não** é o CPF e que o login encontra a linha:

```bash
psql -h localhost -U sinalacs_user -d sinalacs_db -c \
  'SELECT "cpfHash", "birthDate" FROM "users" WHERE "id" = '"'"'00000000-0000-4000-8000-000000000001'"'"';'
```

Expected: um hex de 64 caracteres e a data `1990-01-01`.

- [ ] **Step 4: Commit**

```bash
git add backend/sinalacs_server/bin/seed_cpf_hashes.dart docker-compose.yml
git commit -m "feat(dev): seed dos hashes de CPF do login passwordless (RF01)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 7: App do paciente — formulário com CPF, nascimento e código

**Files:**
- Modify: `apps/patient/lib/core/network/backend_client.dart`
- Modify: `apps/patient/lib/app/app.dart`
- Modify: `apps/patient/lib/core/network/auth_session.dart` (comentário do TTL)
- Modify: `apps/patient/test/support/fake_patient_backend.dart`, testes de widget
- Modify: `apps/patient/tool/live_check.dart`, `apps/patient/integration_test/backend_connection_test.dart`

**Interfaces:**
- Consumes: `auth.requestOtp`, `auth.verifyOtp` (Task 5).
- Produces: `PatientBackend.requestOtp({required String cpf, required DateTime birthDate})` e `PatientBackend.verifyOtp({required String cpf, required String code}) → Future<AuthSession>`; `PatientBackend.developmentLogin({required String role})` para as ferramentas.

**⚠️ Esta task aplica a mudança de TTL descrita nas Global Constraints.** Leia aquela seção antes de começar.

- [ ] **Step 1: Subir o TTL do paciente para 1 hora no backend**

Em `auth_endpoint.dart`, no `verifyOtp` da Task 5, troque a linha do `issueToken` por:

```dart
    return DevelopmentLoginResult(
      // 1 hora é o que `spec/lgpd_design.md` LGPD-RT06 exige para o paciente.
      // Com o padrão de 15 minutos, e sem refresh token, o paciente teria de
      // receber um SMS novo a cada 15 minutos: o código OTP não pode ser
      // reapresentado como a senha do ACS pode, então não existe renovação
      // silenciosa para o paciente. Ver as Global Constraints do plano.
      accessToken: runtime.auth.issueToken(
        user,
        lifetime: const Duration(hours: 1),
      ),
      tokenType: 'Bearer',
    );
```

Acrescente uma constante nomeada no topo de `AuthEndpoint` para que o número tenha um lugar só:

```dart
  /// TTL da sessão do paciente (LGPD-RT06). O ACS continua nos 15 minutos
  /// padrão — a renovação dele é silenciosa, por credencial em memória.
  static const patientSessionLifetime = Duration(hours: 1);
```

e use-a no `issueToken`.

Atualize o comentário de `AuthSession.isExpired` em `apps/patient/lib/core/network/auth_session.dart` e o doc de `_requireToken` do app: a sessão do paciente vive 1 hora e **não** se renova sozinha.

- [ ] **Step 2: Trocar a interface do backend**

Em `apps/patient/lib/core/network/backend_client.dart`, na interface `PatientBackend`:

```dart
  /// Pede o código de acesso (RF01). A resposta não diz se o CPF existe.
  Future<void> requestOtp({
    required String cpf,
    required DateTime birthDate,
  });

  /// Verifica o código e abre a sessão do paciente (RF01).
  ///
  /// Diferente do ACS, **não há renovação silenciosa**: o código OTP é de uso
  /// único e não existe credencial reutilizável. Quando a sessão de 1 hora
  /// expira, o app manda a pessoa autenticar de novo — é a consequência
  /// registrada de adiar o refresh token de LGPD-RT06.
  Future<AuthSession> verifyOtp({
    required String cpf,
    required String code,
  });

  /// Login de DESENVOLVIMENTO, para `tool/` e `integration_test/` contra a
  /// stack local. Exige `ENABLE_DEV_LOGIN=true`. **Não** é o caminho do
  /// produto — RF01 é [requestOtp]/[verifyOtp].
  Future<AuthSession> developmentLogin({required String role});
```

Na implementação, `requestOtp`/`verifyOtp` seguem o padrão de `_guard` já existente, traduzindo `OtpRequestException` para `BackendFailure(error.message, isRecoverable: false)`. O antigo `login()` vira `developmentLogin({required String role})` com o corpo inalterado, e `_requireToken` passa a **lançar** em vez de renovar:

```dart
  /// Token válido para as chamadas autenticadas.
  ///
  /// Sem renovação automática (ver [verifyOtp]): se a sessão expirou, quem
  /// chama recebe uma falha não recuperável e a tela precisa mandar a pessoa
  /// entrar de novo. Inventar uma renovação aqui exigiria ou guardar a
  /// credencial — que para o paciente não existe — ou um refresh token, que
  /// LGPD-RT06 exige e este plano deliberadamente não implementa.
  Future<String> _requireToken() async {
    final current = _session;
    if (current != null && !current.isExpired()) return current.accessToken;

    throw const BackendFailure(
      'Sua sessão expirou. Entre novamente com o código de acesso.',
      isRecoverable: false,
    );
  }
```

- [ ] **Step 3: Construir o fluxo no app**

Em `apps/patient/lib/app/app.dart`, a tela de login (linhas ~217-231, hoje com dois `TextField` sem controller) passa a ter estados. Estrutura mínima, respeitando o tema e os tokens de contraste já existentes:

```dart
enum _LoginStep { credenciais, codigo }

class _LoginScreenState extends State<LoginScreen> {
  final _cpf = TextEditingController();
  final _nascimento = TextEditingController();
  final _codigo = TextEditingController();
  _LoginStep _step = _LoginStep.credenciais;
  bool _busy = false;
  String? _error;
  String? _cpfDigitado;
```

`_pedirCodigo()`:

```dart
  /// Converte o que a pessoa digitou em data e pede o código (RF01).
  ///
  /// A data vem como `DD/MM/AAAA` da máscara do campo. Um valor que não
  /// converte é erro de digitação — e a tela diz isso, em vez de mandar um
  /// pedido que o servidor vai ignorar em silêncio (a resposta dele é a mesma
  /// para "não existe" e "data errada", de propósito).
  DateTime? _parseNascimento(String input) {
    final partes = input.trim().split(RegExp(r'[/-]'));
    if (partes.length != 3) return null;
    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);
    if (dia == null || mes == null || ano == null) return null;
    if (dia < 1 || dia > 31 || mes < 1 || mes > 12 || ano < 1900 || ano > 2100) {
      return null;
    }
    return DateTime.utc(ano, mes, dia);
  }
```

`_entrar()` chama `verifyOtp`, e ao final navega para o shell como o `_enter()` de hoje já faz. Todo texto novo em português, com `Semantics(liveRegion: true)` nas mensagens de erro (padrão WCAG 4.1.3 já usado no app), e a tela do código com um botão "Pedir outro código" que volta ao passo anterior.

Onde a pessoa chega sem sessão e a sessão expira em uso: as telas que hoje capturam `BackendFailure` já mostram a mensagem do servidor; com `isRecoverable: false` e o texto "Sua sessão expirou…", acrescente no `PatientHomeShell` um botão "Entrar novamente" que faz `Navigator.pushReplacement` para a tela de login quando a falha não é recuperável e a sessão está expirada. Onde hoje o paciente era silenciosamente reautenticado, ele passa a poder voltar ao login em um toque.

- [ ] **Step 4: Atualizar os chamadores e os testes**

`test/support/fake_patient_backend.dart` — implemente `requestOtp`/`verifyOtp` (o fake guarda o código e o devolve) e renomeie `login()` para `developmentLogin({required String role})`.

`tool/live_check.dart:32` e `integration_test/backend_connection_test.dart` (5 sítios) — troque `backend.login()` por `backend.developmentLogin(role: 'patient')`.

Testes de widget novos, em `apps/patient/test/`:

```dart
  testWidgets('pede o código e avança para o passo do código', (tester) async {
    // digita CPF e nascimento, toca em "Entrar sem Senha"
    expect(backend.lastOtpRequest?.cpf, '123.456.789-09');
    expect(find.byKey(const Key('otp_code_field')), findsOneWidget);
  });

  testWidgets('data de nascimento inválida não chama o backend', (tester) async {
    // digita '99/99/9999'
    expect(backend.lastOtpRequest, isNull);
    expect(find.textContaining('Confira a data'), findsOneWidget);
  });

  testWidgets('código correto abre o painel', (tester) async {
    // ... e assevera que a navegação aconteceu
  });
```

Adapte os nomes ao fake existente. Asseverar a **máscara** do CPF enviado importa: o backend normaliza de qualquer forma, mas o app não deve mandar o que a pessoa digitou sem passar pelo seu próprio formato de exibição.

- [ ] **Step 5: Rodar a suíte do app**

```bash
cd apps/patient && flutter analyze && flutter test
```

Expected: analisador limpo, suíte verde.

- [ ] **Step 6: Verificar o fluxo real no emulador (opcional, mas é a prova que importa)**

Com a stack de pé e `SMS_GATEWAY=log`:

```bash
set -a; source .env; set +a
cd apps/patient && flutter test integration_test -d emulator-5554 \
  --dart-define=SINALACS_HOST=http://10.0.2.2:8080/
docker compose logs serverpod | grep 'SMS-GATEWAY=log'
```

Expected: a linha do gateway de desenvolvimento aparece com o código — o que prova que o pedido chegou ao serviço e o SMS (simulado) saiu. Registre o resultado; se não houver emulador disponível, diga isso no relatório final em vez de afirmar que foi verificado.

- [ ] **Step 7: Commit**

```bash
git add apps/patient/
git commit -m "feat(patient): login passwordless com CPF, nascimento e codigo OTP (RF01)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 8: Documentação e lacunas

**Files:**
- Modify: `spec/validation_report.md` (linha 69 — RF01; linha 548 não; linha 99 não)
- Modify: `spec/lgpd_design.md` (o bloco "Estado atual" do login)
- Modify: `spec/lgpd_data_audit.md` — **tabela nova não classificada** (Step 5)
- Modify: `spec/lgpd_data_audit.md` (linhas 185-197 — o que já foi feito do que era recomendação)
- Modify: `apps/CLAUDE.md`, `backend/CLAUDE.md`, `PROGRESS.md`

- [ ] **Step 1: RF01 no relatório de validação**

```markdown
| RF01 | Autenticação passwordless (CPF + nasc. + OTP) | **backend + app** | `auth.requestOtp`/`verifyOtp` com CPF validado por dígito verificador, hasheado em HMAC-SHA-256 com `CPF_HASH_PEPPER` (LGPD §196), código de 6 dígitos com TTL de 5 min, teto de 5 verificações, intervalo de 60 s e auditoria por desfecho (`otp_challenges`). **O provedor de SMS não está escolhido**: `SMS_GATEWAY=log` escreve o código no log e só é aceito em `development`. |
```

- [ ] **Step 2: Marcar o que saiu das recomendações de `lgpd_data_audit.md`**

Nas linhas 185-197, marque cada recomendação conforme o que este plano de fato fez, e
preserve o texto original — ele é o diagnóstico:

- `cpfHash` → HMAC-SHA-256 com pepper: "**atendido** (2026-09-18,
  `docs/superpowers/plans/2026-09-18-rf01-login-passwordless-otp.md`)".
- `birthDate` → `date`: "**não atendido** (2026-09-18): o Serverpod não expõe tipo de coluna
  `date` (`ColumnType` não tem a variante, e `DateTime` mapeia fixo para `timestamp without
  time zone`). A coluna carrega hora — sempre meia-noite UTC — e o serviço compara por dia,
  então a funcionalidade não depende do tipo; a recomendação segue em aberto."
- `users.cpfHash` (linha 10) e as demais já cobertas: deixe como estão.

Não escreva "atendido" para o `birthDate`: um documento de conformidade que se declara
satisfeito onde não está é pior que um que registra a lacuna.

- [ ] **Step 3: Registrar as lacunas em `PROGRESS.md`**

Seção datada com o que **não** foi feito, cada item com o motivo e o ponteiro:

- **Provedor de SMS não escolhido** — é `SMS_GATEWAY=log` em desenvolvimento; fora dele o boot exige um gateway real, que não existe. Falta a decisão de produto/infra (conta, custo por mensagem, contrato).
- **Não existe coluna de telefone** em `Patient` nem no ER do PRD. O gateway recebe o CPF formatado como identificador de destino; um gateway real precisa do número, o que é decisão de produto (e dado pessoal a coletar com finalidade e retenção próprias).
- **`patientSessionLifetime` passou a 1 hora** para o paciente, aplicando LGPD-RT06, porque o OTP não se renova em silêncio. O ACS continua com 15 minutos e renovação por credencial em memória.
- **Refresh token rotativo continua ausente** (LGPD-RT06) — é o que permitiria voltar o TTL do paciente ao de 15 min sem quebrar a experiência.
- **MFA/TOTP ausente** (F5).
- **Sem limite de tentativas por origem** — o contador é por desafio e por CPF; não há IP.

- [ ] **Step 4: Um ponteiro em `user.spy.yaml` para o beco sem saída do `birthDate`**

Achado do review da Task 3. Quando o `type=date` foi revertido, o campo ficou sem
comentário nenhum — e o próximo leitor que consultar `spec/lgpd_data_audit.md:197`
vai tentar escrever `type=date` de novo, porque nada no arquivo diz que ele não
existe. Uma linha evita repetir o beco sem saída:

```yaml
  ### `spec/lgpd_data_audit.md` recomenda o tipo SQL `date` aqui. Não é
  ### expressável no DSL do Serverpod (3.4.13): `type=` é o tipo Dart do campo e
  ### `DateTime` mapeia fixo para `timestamp without time zone` — `ColumnType` não
  ### tem a variante `date`, e `serverpod generate` recusa o modelo. A coluna
  ### carrega sempre meia-noite UTC e `PasswordlessAuthService` compara por dia.
  birthDate: DateTime,
```

- [ ] **Step 5: Atualizar `apps/CLAUDE.md` e `backend/CLAUDE.md`**

No primeiro, a seção do paciente: login por CPF+nascimento+OTP, sessão de 1 hora **sem renovação silenciosa** (e por quê). No segundo, a lista de endpoints (`auth.requestOtp`, `auth.verifyOtp`) e as tabelas novas (`otp_challenges`), mais `CPF_HASH_PEPPER`/`SMS_GATEWAY` entre as variáveis de `AppConfig`.

- [ ] **Step 6: Classificar `otp_challenges` no inventário de LGPD**

`spec/lgpd_data_audit.md` §1 se declara um inventário campo a campo de **toda** tabela
persistida, e `otp_challenges` guarda credencial de uso único — mas nenhuma task deste
plano a classificava (é o mesmo gap que o review da Task 2 do RF07 achou em
`user_credentials`, já corrigido lá). Acrescente à tabela do §1:

```markdown
| **otp_challenges** | `id` | `uuid` | Pseudonimizado | UUID da linha | — |
| | `userId` | `uuid` | Pseudonimizado | Chave estrangeira (`users.id`) | — |
| | `codeHash` | `text` | Crítico — credencial | HMAC-SHA-256 do código, campo de domínio próprio | O código em claro nunca é persistido; existe só entre a geração e o envio. |
| | `attempts` | `bigint` | Metadado de Segurança | Verificações gastas neste desafio | Teto de 5: 6 dígitos são 10^6 combinações. |
| | `createdAt` / `expiresAt` / `consumedAt` | `timestamp without time zone` | Metadado Técnico | Janela de validade e consumo | TTL de 5 minutos; `consumedAt` marca uso único. |
```

Nota: `codeHash` usa o mesmo `CPF_HASH_PEPPER` do `users.cpfHash`, com separação de
domínio (`sinalacs:otp:v1:`), e o §2.1 do documento — que critica o SHA-256 sem salt de
`cpfHash` — **não** se aplica a ele pelo mesmo motivo que não se aplica ao CPF migrado:
há segredo de servidor na chave. Vale dizer isso na nota, para o leitor não ler a seção
como se ela contradissesse a tabela.

- [ ] **Step 7: Commit**

```bash
graphify update .
git add spec/ apps/CLAUDE.md backend/CLAUDE.md PROGRESS.md
git commit -m "docs: registrar RF01 implementado e as lacunas de SMS, telefone e refresh token

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Verificação final

- [ ] **Backend verde:** `cd backend/sinalacs_server && dart test` → `All tests passed!`.
- [ ] **Analisadores limpos:** `cd backend && dart analyze` e `cd apps/patient && flutter analyze`.
- [ ] **App paciente verde:** `cd apps/patient && flutter test`.
- [ ] **Nenhum CPF em claro persistido:** `psql -h localhost -U sinalacs_user -d sinalacs_db -c 'SELECT "cpfHash" FROM "users";'` → todos os valores com 64 caracteres hexadecimais, nenhum literal legível.
- [ ] **Nenhum código OTP persistido:** `psql ... -c 'SELECT "codeHash" FROM "otp_challenges";'` → 64 caracteres hexadecimais; nenhuma coluna com 6 dígitos.
- [ ] **Anti-enumeração observado:** `requestOtp` com um CPF não cadastrado devolve a mesma resposta que com um cadastrado, e **não** gera linha em `otp_challenges`.
- [ ] **Fluxo real exercitado:** com `SMS_GATEWAY=log` e a stack de pé, o log do servidor mostra o código e o login pelo app conclui. Se o emulador não estiver disponível, registre como **não verificado** em vez de assumir que funcionou.
- [ ] **Boot fail-closed:** `APP_ENV=production SMS_GATEWAY=log` e `APP_ENV=production` sem `CPF_HASH_PEPPER` fazem o servidor **não subir**, com mensagem nomeando a variável.

## Fora de escopo (registrado, não implementado)

- **Escolha do provedor de SMS** e a coluna de telefone — decisão de produto/infra, como o projeto Firebase do RF14.
- **Refresh token rotativo** (LGPD-RT06) e o retorno do TTL do paciente a 15 min.
- **MFA/TOTP** (F5).
- **Limite de tentativas por IP** (F6).
- **Reenvio por outro canal** (voz, e-mail) e **biometria**, que `spec/sys_flow.md:22` menciona como alternativas do RF01.
