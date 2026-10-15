# Teste completo do app do paciente contra um banco de teste — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rodar no `emulator-5554` uma jornada completa do app do paciente (login OTP real pela tela → triagem → alerta de urgência → status → "Meus Dados" → consentimento de avisos → push do ACS chegando pelo Gorush e FCM) contra uma stack Docker cujo banco é o **banco de teste** (`postgres-test`), com fixtures geradas por execução, sem nenhum UUID, CPF ou login de desenvolvimento fixos.

**Architecture:** Um override do Compose (`docker-compose.e2e.yml`) aponta `serverpod`, os seeds e o Gorush para o banco `sinalacs_e2e` dentro do serviço `postgres-test` (efêmero, sem volume) e desliga `ENABLE_DEV_LOGIN`. Um seeder Dart (`bin/seed_e2e_fixtures.dart`) cria UBS, microárea, ACS com credencial e pacientes com **UUIDs aleatórios e CPFs sintéticos de dígito verificador válido**, e grava um manifesto JSON gitignorado. Os testes de `integration_test/` leem o manifesto por `--dart-define-from-file`; o código OTP (que o gateway `log` só escreve no log do servidor) chega ao emulador por um relé HTTP local. O login de desenvolvimento continua existindo só como fallback da CI (`smoke_test.dart`).

**Tech Stack:** Docker Compose, Postgres 15, Serverpod 3.4.13 (Dart), Flutter 3 (`integration_test`), bash, `adb`, Gorush 1.22.0 + FCM.

**Spec:** `spec/PRD_system.md` (RF01, RF03–RF05, RF14), `spec/lgpd_design.md` (nada de dado real em seed/teste/log; consentimento por finalidade), `backend/CLAUDE.md` (seeds, `postgres-test`), `apps/CLAUDE.md` (validação no emulador).

## Inventário dos dados fixos que este plano substitui

| Onde | Dado fixo | Substituído por |
|---|---|---|
| `backend/.../seeds/development.sql` | UUIDs `…0001`–`…0009`, nomes "Fulano de Tal" etc., `cpfHash` literal | Fixtures geradas por execução (Task 2); `development.sql` segue existindo só para a stack de desenvolvimento |
| `backend/.../bin/seed_cpf_hashes.dart` | CPFs `12345678909`, `98765432100`… amarrados aos UUIDs acima | CPFs gerados com DV válido, únicos por execução |
| `lib/src/endpoints/auth_endpoint.dart:24-36` | `_patient`/`_acs` com UUIDs e `deviceId` fixos (`developmentLogin`) | Login real: OTP (paciente) e matrícula+senha (ACS), com `ENABLE_DEV_LOGIN=false` na stack de e2e |
| `apps/patient/integration_test/{smoke,backend_connection,push_register}_test.dart`, `tool/{live_check,push_consent}.dart` | `developmentLogin(role: 'patient')`; constante `seedMicroAreaId = '0000…0003'` | Helper `loginPatient()` (fixtures + OTP quando há manifesto; fallback ao login de desenvolvimento sem manifesto, para a CI) e microárea lida da sessão |
| `apps/acs/tool/send_notice.dart` | `developmentLogin(role: 'acs')` | `loginInstitutional` com matrícula/senha do manifesto |
| `scripts/qa/push_e2e.sh` | `docker exec sinalacs-postgres … sinalacs_db`, `delete from push_tokens` no banco de desenvolvimento | Mesmo script apontando para o banco de e2e (não apaga nada do banco de desenvolvimento) |
| `apps/patient/test/**` (widget tests) | `'Paciente de Teste'`, `'Fulano de Tal'`, CPF `123.456.789-09`, `FakePatientBackend` | **Não muda, de propósito**: são herméticos (sem rede nem banco) e é isso que os faz rápidos e estáveis; a cobertura com banco real vive na jornada nova |

## Estado verificado em 2026-09-30

- `emulator-5554` (AVD `Medium_Phone`) e a stack de desenvolvimento estão de pé (`docker compose ps`); `postgres-test` está no ar (`--profile test`, porta host 9090, banco `sinalacs_test`, **sem volume**).
- `adb` não está no `PATH`: `export PATH="$HOME/Android/Sdk/platform-tools:$PATH"`. `serverpod`: `export PATH="$HOME/.pub-cache/bin:$PATH"`.
- O gateway de SMS `log` escreve `[SMS-GATEWAY=log] código de acesso: NNNNNN` no log do container `sinalacs-serverpod`. Regras do OTP: 6 dígitos, TTL 5 min, teto de 5 verificações, **60 s entre pedidos por paciente**.
- Credenciais do FCM em `infra/docker/gorush/credentials/` (o `push_e2e.sh` valida) e `apps/patient/android/app/google-services.json`.
- Suítes atuais: paciente 233 (widget), backend 433.

## Global Constraints

- Nenhum dado real de paciente em seed, teste, log ou captura; CPFs só sintéticos com DV válido, nunca impressos em log nem em mensagem de erro.
- O seeder recusa rodar se `APP_ENV != development` **ou** se o banco de destino não for `sinalacs_e2e` (nunca toca o banco de desenvolvimento nem `sinalacs_test`, que é do `dart test`).
- Alerta vermelho nunca é descartado nem atrasado; triagem determinística vem só de `triage.evaluate`.
- Textos, comentários e commits em português; commits terminam com `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Sem push nem merge.
- `flutter analyze` sem problemas e `dart analyze` do backend no baseline de 51 infos antes de cada commit; o `ci_invariants.sh` continua verde (ele vigia `docker-compose.yml` e o workflow, não arquivos novos).
- O manifesto `.e2e/fixtures.json` contém segredos de teste (senha do ACS): gitignorado, `chmod 600`.

## Review Focus

- Paciente com OTP vencido ou digitado errado: a tela mostra o erro (`login_error`) e **não** entra; o teste de jornada cobre o código errado antes do certo.
- Segundo pedido de OTP dentro de 60 s: o relé devolve o código do **último** pedido, não o antigo; o teste pede, espera e compara.
- Paciente de outra microárea (fixture `outsider`): o ACS da microárea principal não o enxerga em `patients.listMicroArea` — prova de território com o banco real.
- Stack de e2e com `ENABLE_DEV_LOGIN=false`: `developmentLogin` falha como "não encontrado"; o teste garante que nada no fluxo depende dele.
- Rodar duas vezes seguidas: a segunda execução não colide (UUIDs/CPFs novos, banco recriado) e não deixa lixo no banco de desenvolvimento.

---

### Task 1: Banco de teste para a stack de e2e (Compose override)

**Files:**
- Create: `docker-compose.e2e.yml`
- Create: `scripts/qa/e2e_stack.sh`
- Modify: `.gitignore` (acrescentar `.e2e/`)

**Interfaces:**
- Produces: `./scripts/qa/e2e_stack.sh up|down|psql "<sql>"`. `up` cria o banco `sinalacs_e2e` no `postgres-test`, sobe `serverpod` + `gorush` + dependências apontando para ele, com `ENABLE_DEV_LOGIN=false` e `SMS_GATEWAY=log`, e espera saudável. `psql` roda SQL nele (usado pelos scripts e testes do host). Tasks 2–6 dependem disso.

- [ ] **Step 1: Ler as peças que o override toca**

Ler `docker-compose.yml` inteiro (serviços `serverpod`, `database-seed`, `health-data-seed`, `acs-credential-seed`, `cpf-hash-seed`, `gorush`, `traefik`) e anotar os nomes das variáveis `SERVERPOD_DATABASE_*`. O override **só** redefine essas variáveis e `ENABLE_DEV_LOGIN`; não copia o resto.

- [ ] **Step 2: Escrever o override**

`docker-compose.e2e.yml`:

```yaml
# Stack de e2e: o mesmo backend, mas com o banco de TESTE (postgres-test,
# efêmero, sem volume) e sem login de desenvolvimento. Uso:
#   ./scripts/qa/e2e_stack.sh up
# O banco `sinalacs_e2e` é separado de `sinalacs_test` (do `dart test`) para que
# a suíte do backend e a jornada no emulador não pisem uma na outra.
services:
  serverpod:
    depends_on:
      postgres-test:
        condition: service_healthy
    environment:
      SERVERPOD_DATABASE_HOST: postgres-test
      SERVERPOD_DATABASE_NAME: sinalacs_e2e
      SERVERPOD_DATABASE_USER: postgres
      SERVERPOD_DATABASE_PASSWORD: ${TEST_DATABASE_PASSWORD:?defina em .env — rode ./scripts/dev/bootstrap_env.sh}
      ENABLE_DEV_LOGIN: "false"
      SMS_GATEWAY: log
      GORUSH_URL: http://gorush:8088
```

O `postgres-test` não tem `container_name` no plano de rede do serviço `serverpod`? Ele tem (`sinalacs-postgres-test`) e está na rede default do projeto: o host `postgres-test` resolve. Conferir com `docker compose --profile test --profile push -f docker-compose.yml -f docker-compose.e2e.yml config | grep -A12 "serverpod:"`.

- [ ] **Step 3: Escrever o script de stack**

`scripts/qa/e2e_stack.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
# Sobe/derruba a stack de e2e contra o banco de teste. Ver docker-compose.e2e.yml.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ -f .env ]] || { echo 'erro: rode ./scripts/dev/bootstrap_env.sh'; exit 1; }
set -a; source .env; set +a
unset GORUSH_CREDENTIALS_DIR   # o Compose o prioriza sobre o .env (ver PROGRESS.md)
export GORUSH_CREDENTIALS_DIR="$PWD/infra/docker/gorush/credentials"
dc() { docker compose --profile test --profile push -f docker-compose.yml -f docker-compose.e2e.yml "$@"; }
db=sinalacs_e2e
pg() { docker exec -e PGPASSWORD="$TEST_DATABASE_PASSWORD" sinalacs-postgres-test psql -U postgres -d "${2:-$db}" -Atc "$1"; }

case "${1:-}" in
  up)
    dc up -d postgres-test >/dev/null
    until docker exec sinalacs-postgres-test pg_isready -U postgres -d sinalacs_test >/dev/null 2>&1; do sleep 1; done
    # Recria o banco: cada execução parte de um banco vazio.
    pg "drop database if exists $db with (force)" postgres >/dev/null
    pg "create database $db" postgres >/dev/null
    # Só o backend e o relé; os seeds de desenvolvimento NÃO sobem (as fixtures vêm da Task 2).
    dc up -d --build --no-deps serverpod gorush traefik mosquitto
    for _ in $(seq 1 90); do
      [[ "$(docker inspect -f '{{.State.Health.Status}}' sinalacs-serverpod 2>/dev/null)" == healthy ]] && exit 0
      sleep 2
    done
    echo 'erro: serverpod não ficou saudável'; dc logs --tail 40 serverpod; exit 1 ;;
  down) dc stop serverpod gorush >/dev/null; pg "drop database if exists $db with (force)" postgres >/dev/null ;;
  psql) pg "$2" ;;
  *) echo 'uso: e2e_stack.sh up|down|psql "<sql>"'; exit 2 ;;
esac
```

- [ ] **Step 4: Verificar**

Run: `./scripts/qa/e2e_stack.sh up && ./scripts/qa/e2e_stack.sh psql "select count(*) from users" && curl -sk https://localhost/ -o /dev/null -w '%{http_code}\n'`
Expected: `up` sai com 0; `count` = `0` (migrações aplicadas pelo Serverpod, nenhum seed); HTTP 200/404 do Traefik (não erro de conexão). Conferir também que o banco de desenvolvimento não mudou: `docker exec sinalacs-postgres psql -U sinalacs_user -d sinalacs_db -Atc "select count(*) from push_tokens"` igual ao de antes.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.e2e.yml scripts/qa/e2e_stack.sh .gitignore
git commit -m "test(e2e): stack de e2e com o banco de teste e sem login de desenvolvimento

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Fixtures geradas por execução (seeder Dart + manifesto)

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/testing/e2e_fixtures.dart` (geração pura: CPF válido, UUID v4, manifesto)
- Create: `backend/sinalacs_server/bin/seed_e2e_fixtures.dart` (grava no banco e escreve `.e2e/fixtures.json`)
- Test: `backend/sinalacs_server/test/unit/e2e_fixtures_test.dart`
- Modify: `scripts/qa/e2e_stack.sh` (comando `seed`)

**Interfaces:**
- Consumes: `Cpf` (`lib/src/application/auth/cpf.dart`, valida DV), `HmacCpfHasher(pepper:)`, `Argon2PasswordHasher` (ver `bin/seed_acs_credentials.dart` para a chamada e as colunas de `user_credentials`), `HealthDataCipher` (ver `bin/seed_health_data.dart` para cifrar `chronicConditions`).
- Produces: `E2eFixtures generateE2eFixtures(Random random)` com os campos `ubsId`, `microAreaId`, `otherMicroAreaId`, `acs` (`id`, `matricula`, `password`), `patients` (lista de `E2ePatient{id, name, cpf, birthDate, chronic, microAreaId}`; nomes: `main`, `chronic`, `outsider` em `role` de fixture). `toJson()`/`fromJson()`. Arquivo `.e2e/fixtures.json` (modo 600).

- [ ] **Step 1: Escrever os testes que falham**

`test/unit/e2e_fixtures_test.dart`:

```dart
import 'dart:math';

import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/infrastructure/testing/e2e_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('todo CPF gerado tem dígito verificador válido (mil amostras)', () {
    final random = Random(1);
    for (var i = 0; i < 1000; i++) {
      expect(() => Cpf.parse(generateValidCpfDigits(random)), returnsNormally);
    }
  });

  test('duas execuções não compartilham UUID nem CPF', () {
    final a = generateE2eFixtures(Random(1));
    final b = generateE2eFixtures(Random(2));
    final idsA = {a.microAreaId, a.acs.id, ...a.patients.map((p) => p.id)};
    final idsB = {b.microAreaId, b.acs.id, ...b.patients.map((p) => p.id)};
    expect(idsA.intersection(idsB), isEmpty);
    expect(a.patients.map((p) => p.cpf).toSet().intersection(b.patients.map((p) => p.cpf).toSet()), isEmpty);
  });

  test('dentro de uma execução tudo é único e o forasteiro está em outra microárea', () {
    final f = generateE2eFixtures(Random(7));
    expect(f.patients.map((p) => p.cpf).toSet(), hasLength(f.patients.length));
    expect(f.patients.map((p) => p.id).toSet(), hasLength(f.patients.length));
    final outsider = f.patients.singleWhere((p) => p.role == 'outsider');
    expect(outsider.microAreaId, f.otherMicroAreaId);
    expect(f.patients.where((p) => p.role != 'outsider').every((p) => p.microAreaId == f.microAreaId), isTrue);
  });

  test('nenhum UUID é do formato fixo do seed de desenvolvimento', () {
    final f = generateE2eFixtures(Random(3));
    for (final id in [f.microAreaId, f.acs.id, ...f.patients.map((p) => p.id)]) {
      expect(id.startsWith('00000000-0000-4000-8000'), isFalse);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
    }
  });

  test('o manifesto ida e volta é idêntico', () {
    final f = generateE2eFixtures(Random(9));
    expect(E2eFixtures.fromJson(f.toJson()).toJson(), f.toJson());
  });

  test('toString e mensagens de erro não vazam CPF nem senha', () {
    final f = generateE2eFixtures(Random(4));
    final texto = f.toString();
    for (final p in f.patients) {
      expect(texto.contains(p.cpf), isFalse);
    }
    expect(texto.contains(f.acs.password), isFalse);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/e2e_fixtures_test.dart`
Expected: FAIL (arquivo/símbolos inexistentes).

- [ ] **Step 3: Implementar a geração pura**

`lib/src/infrastructure/testing/e2e_fixtures.dart`:

```dart
import 'dart:math';

/// Dados SINTÉTICOS de uma execução de e2e. Nada aqui é estável entre
/// execuções: UUIDs e CPFs mudam a cada chamada (quem precisa deles lê o
/// manifesto). Nunca um dado real (LGPD).
class E2ePatient {
  const E2ePatient({
    required this.id,
    required this.role,
    required this.name,
    required this.cpf,
    required this.birthDate,
    required this.chronic,
    required this.microAreaId,
  });

  final String id;
  final String role; // main | chronic | outsider
  final String name;
  final String cpf; // só dígitos; nunca em log
  final String birthDate; // AAAA-MM-DD
  final bool chronic;
  final String microAreaId;

  Map<String, Object?> toJson() => {
        'id': id, 'role': role, 'name': name, 'cpf': cpf,
        'birthDate': birthDate, 'chronic': chronic, 'microAreaId': microAreaId,
      };

  factory E2ePatient.fromJson(Map<String, Object?> j) => E2ePatient(
        id: j['id']! as String, role: j['role']! as String, name: j['name']! as String,
        cpf: j['cpf']! as String, birthDate: j['birthDate']! as String,
        chronic: j['chronic']! as bool, microAreaId: j['microAreaId']! as String,
      );
}

class E2eAcs {
  const E2eAcs({required this.id, required this.matricula, required this.password});

  final String id;
  final String matricula;
  final String password;

  Map<String, Object?> toJson() => {'id': id, 'matricula': matricula, 'password': password};

  factory E2eAcs.fromJson(Map<String, Object?> j) =>
      E2eAcs(id: j['id']! as String, matricula: j['matricula']! as String, password: j['password']! as String);
}

class E2eFixtures {
  const E2eFixtures({
    required this.ubsId,
    required this.microAreaId,
    required this.otherMicroAreaId,
    required this.acs,
    required this.patients,
  });

  final String ubsId;
  final String microAreaId;
  final String otherMicroAreaId;
  final E2eAcs acs;
  final List<E2ePatient> patients;

  E2ePatient byRole(String role) => patients.singleWhere((p) => p.role == role);

  Map<String, Object?> toJson() => {
        'ubsId': ubsId, 'microAreaId': microAreaId, 'otherMicroAreaId': otherMicroAreaId,
        'acs': acs.toJson(), 'patients': [for (final p in patients) p.toJson()],
      };

  factory E2eFixtures.fromJson(Map<String, Object?> j) => E2eFixtures(
        ubsId: j['ubsId']! as String, microAreaId: j['microAreaId']! as String,
        otherMicroAreaId: j['otherMicroAreaId']! as String,
        acs: E2eAcs.fromJson((j['acs']! as Map).cast<String, Object?>()),
        patients: [for (final p in (j['patients']! as List)) E2ePatient.fromJson((p as Map).cast<String, Object?>())],
      );

  @override
  String toString() => 'E2eFixtures(${patients.length} pacientes, acs ${acs.id.substring(0, 8)}…)';
}

String generateUuidV4(Random random) {
  String hex(int n) => List.generate(n, (_) => random.nextInt(16).toRadixString(16)).join();
  final variant = '89ab'[random.nextInt(4)];
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
}

/// 11 dígitos com os dois dígitos verificadores corretos e sem todos iguais.
String generateValidCpfDigits(Random random) {
  while (true) {
    final d = List<int>.generate(9, (_) => random.nextInt(10));
    if (d.toSet().length == 1) continue;
    int dv(List<int> base) {
      var sum = 0;
      for (var i = 0; i < base.length; i++) {
        sum += base[i] * (base.length + 1 - i);
      }
      final r = (sum * 10) % 11;
      return r == 10 ? 0 : r;
    }
    final d1 = dv(d);
    final d2 = dv([...d, d1]);
    return [...d, d1, d2].join();
  }
}

String _birthDate(Random random) {
  final year = 1950 + random.nextInt(50);
  return '$year-${(1 + random.nextInt(12)).toString().padLeft(2, '0')}-${(1 + random.nextInt(28)).toString().padLeft(2, '0')}';
}

String _password(Random random) {
  const alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(20, (_) => alphabet[random.nextInt(alphabet.length)]).join();
}

E2eFixtures generateE2eFixtures(Random random) {
  final microAreaId = generateUuidV4(random);
  final otherMicroAreaId = generateUuidV4(random);
  final usedCpfs = <String>{};
  E2ePatient patient(String role, String name, {required bool chronic, required String microAreaId}) {
    String cpf;
    do {
      cpf = generateValidCpfDigits(random);
    } while (!usedCpfs.add(cpf));
    return E2ePatient(
      id: generateUuidV4(random), role: role, name: name, cpf: cpf,
      birthDate: _birthDate(random), chronic: chronic, microAreaId: microAreaId,
    );
  }

  return E2eFixtures(
    ubsId: generateUuidV4(random),
    microAreaId: microAreaId,
    otherMicroAreaId: otherMicroAreaId,
    acs: E2eAcs(id: generateUuidV4(random), matricula: 'E2E-${1000 + random.nextInt(9000)}', password: _password(random)),
    patients: [
      patient('main', 'Paciente E2E Principal', chronic: false, microAreaId: microAreaId),
      patient('chronic', 'Paciente E2E Crônico', chronic: true, microAreaId: microAreaId),
      patient('outsider', 'Paciente E2E Outra Área', chronic: false, microAreaId: otherMicroAreaId),
    ],
  );
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd backend/sinalacs_server && dart test test/unit/e2e_fixtures_test.dart`
Expected: 6/6 PASS. (Se `Cpf.parse` tiver outro nome, ler `lib/src/application/auth/cpf.dart` e ajustar só o teste.)

- [ ] **Step 5: O seeder que grava no banco**

`bin/seed_e2e_fixtures.dart`. Estrutura (seguir `bin/seed_acs_credentials.dart` para a conexão `Connection.open(Endpoint(...))`, o hasher Argon2 e o `INSERT INTO "user_credentials"`; `bin/seed_cpf_hashes.dart` para `HmacCpfHasher(pepper: env['CPF_HASH_PEPPER'])`; `bin/seed_health_data.dart` para cifrar condições crônicas):

```dart
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  if ((env['APP_ENV'] ?? 'development') != 'development') { stderr.writeln('recusando: APP_ENV != development'); exit(2); }
  if (env['SERVERPOD_DATABASE_NAME'] != 'sinalacs_e2e') {
    stderr.writeln('recusando: este seeder só escreve em sinalacs_e2e'); exit(2);
  }
  final out = File(args.isNotEmpty ? args.first : '.e2e/fixtures.json');
  final f = generateE2eFixtures(Random.secure());
  // conexão como em seed_acs_credentials.dart, depois, numa transação:
  //   ubs(f.ubsId), micro_areas(f.microAreaId e f.otherMicroAreaId, ambas com ubsId),
  //   users (paciente: cpfHash = HmacCpfHasher.hash(Cpf.parse(cpf)), name, birthDate, role 'patient', microAreaId),
  //   users (acs: role 'acs', cpfHash NULL ou literal 'e2e-acs-<uuid>' — ver o NOT NULL em development.sql; nunca um CPF, pelo aviso de seed_cpf_hashes.dart),
  //   patients (id, emergencyContact 'Contato E2E', isChronic, chronicConditionsEncrypted via HealthDataCipher, keyVersion),
  //   acs (id, enrollmentId = f.acs.matricula, ubsId, active true),
  //   user_credentials (Argon2 de f.acs.password, mesmas colunas de seed_acs_credentials.dart).
  // Por fim: out.parent.createSync(recursive: true); out.writeAsStringSync(jsonEncode(f.toJson())); chmod 600.
}
```

Escrever o corpo completo copiando os `INSERT` de `seeds/development.sql` (mesmas colunas) com parâmetros nomeados no lugar dos literais. Não deixar nenhum UUID/CPF literal no arquivo.

- [ ] **Step 6: Comando `seed` no script de stack**

Acrescentar ao `case` de `e2e_stack.sh`:

```bash
  seed)
    ( cd backend/sinalacs_server && \
      SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 \
      SERVERPOD_DATABASE_NAME=$db SERVERPOD_DATABASE_USER=postgres \
      SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
      dart run bin/seed_e2e_fixtures.dart ../../.e2e/fixtures.json ) ;;
```
(`CPF_HASH_PEPPER` e `HEALTH_DATA_ENCRYPTION_KEY` vêm do `.env` já carregado: precisam ser os mesmos do servidor.)

- [ ] **Step 7: Verificar no banco**

Run: `./scripts/qa/e2e_stack.sh seed && ./scripts/qa/e2e_stack.sh psql "select role, count(*) from users group by role order by role" && ls -l .e2e/fixtures.json`
Expected: `acs|1`, `patient|3`; arquivo `-rw-------`. `grep -c 00000000-0000-4000 .e2e/fixtures.json` = `0`.

- [ ] **Step 8: Commit**

```bash
git add backend/sinalacs_server/lib/src/infrastructure/testing backend/sinalacs_server/bin/seed_e2e_fixtures.dart backend/sinalacs_server/test/unit/e2e_fixtures_test.dart scripts/qa/e2e_stack.sh
git commit -m "test(e2e): fixtures sintéticas geradas por execução e seeder do banco de teste

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Relé do código OTP para o emulador

**Files:**
- Create: `scripts/qa/otp_relay.py`
- Test: `scripts/qa/otp_relay_test.py`

**Interfaces:**
- Produces: servidor HTTP em `127.0.0.1:8765` com `GET /code?since=<epoch_ms>` → `200` com o código mais recente do log do servidor gerado **depois** de `since`, ou `404` se não houver; o emulador o alcança por `adb reverse tcp:8765 tcp:8765` como `http://localhost:8765/code`. Função pura `parse_latest_code(log_text) -> str | None`.

- [ ] **Step 1: Teste que falha**

`scripts/qa/otp_relay_test.py`:

```python
import unittest
from otp_relay import parse_latest_code

class T(unittest.TestCase):
    def test_sem_linha(self):
        self.assertIsNone(parse_latest_code("nada aqui\n"))
    def test_pega_a_mais_recente(self):
        log = ("[SMS-GATEWAY=log] código de acesso: 111111 (gateway de desenvolvimento — nenhum SMS foi enviado)\n"
               "ruído\n"
               "[SMS-GATEWAY=log] código de acesso: 222222 (gateway de desenvolvimento — nenhum SMS foi enviado)\n")
        self.assertEqual(parse_latest_code(log), "222222")
    def test_ignora_seis_digitos_fora_da_linha_do_gateway(self):
        self.assertIsNone(parse_latest_code("pedido 123456 recebido\n"))

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd scripts/qa && python3 otp_relay_test.py`
Expected: FAIL (`ModuleNotFoundError: otp_relay`).

- [ ] **Step 3: Implementar**

`scripts/qa/otp_relay.py`:

```python
#!/usr/bin/env python3
"""Relé do código OTP do gateway `log` para o emulador (só desenvolvimento/e2e).

O gateway de log escreve o código no stdout do servidor; o emulador não lê
`docker logs`. Este servidor expõe só o código mais recente, sem destino nem CPF
(o log não os tem). Escuta em 127.0.0.1; o emulador chega por `adb reverse`.
"""
import re, subprocess, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

PADRAO = re.compile(r"\[SMS-GATEWAY=log\] código de acesso: (\d{6}) ")

def parse_latest_code(log_text):
    achados = PADRAO.findall(log_text)
    return achados[-1] if achados else None

class Handler(BaseHTTPRequestHandler):
    container = "sinalacs-serverpod"

    def do_GET(self):
        url = urlparse(self.path)
        if url.path != "/code":
            self.send_error(404); return
        since_ms = int(parse_qs(url.query).get("since", ["0"])[0])
        desde = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(since_ms / 1000))
        log = subprocess.run(["docker", "logs", "--since", desde, self.container],
                             capture_output=True, text=True).stdout
        code = parse_latest_code(log)
        if code is None:
            self.send_error(404); return
        self.send_response(200); self.send_header("Content-Type", "text/plain"); self.end_headers()
        self.wfile.write(code.encode())

    def log_message(self, *a):  # silencioso: o código não vai para o terminal
        pass

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8765), Handler).serve_forever()
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd scripts/qa && python3 otp_relay_test.py`
Expected: 3 testes OK.

- [ ] **Step 5: Verificação com a stack real**

```bash
python3 scripts/qa/otp_relay.py & RELAY=$!
# peça um OTP de uma fixture (ver Task 4 para o helper); aqui, com o manifesto:
CPF=$(python3 -c "import json;p=json.load(open('.e2e/fixtures.json'))['patients'][0];print(p['cpf'])")
echo "(o pedido real é feito pelo teste da Task 4; este passo só confirma 404 sem pedido)"
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:8765/code?since=$(( $(date +%s) * 1000 ))"; kill $RELAY
```
Expected: `404` (nenhum código depois de agora).

- [ ] **Step 6: Commit**

```bash
git add scripts/qa/otp_relay.py scripts/qa/otp_relay_test.py
git commit -m "test(e2e): relé do código OTP do gateway de log para o emulador

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Login do paciente pelas fixtures nos testes de integração (sem login de desenvolvimento)

**Files:**
- Create: `apps/patient/integration_test/support/e2e_login.dart`
- Test: `apps/patient/test/e2e_login_test.dart` (parte pura: leitura do manifesto e fallback)
- Modify: `apps/patient/integration_test/{smoke_test,backend_connection_test,push_register_test}.dart` (trocar `developmentLogin` e a constante `seedMicroAreaId`)
- Modify: `apps/patient/tool/{live_check,push_consent}.dart`
- Modify: `scripts/qa/e2e.sh` (nenhuma mudança de comportamento: sem manifesto continua no fallback)

**Interfaces:**
- Produces: `class E2eLogin { static E2eConfig? fromDefines(); }`, `Future<AuthSession> loginPatient(BackendClient backend, {String role = 'main'})`. Regras: com `--dart-define-from-file=.e2e/fixtures.json` **e** `--dart-define=OTP_RELAY=http://localhost:8765/code`, faz `requestOtp` + relé + `verifyOtp` do paciente da fixture `role`; sem manifesto, cai em `developmentLogin(role: 'patient')` (CI). `String microAreaOf(AuthSession s)` devolve `s.microAreaId` (sem constante).
- Consumes: `BackendClient.requestOtp({cpf, birthDate})`/`verifyOtp({cpf, code})` (`lib/core/network/backend_client.dart:63-74`); manifesto da Task 2; relé da Task 3.

- [ ] **Step 1: Teste puro que falha**

`apps/patient/test/e2e_login_test.dart` (o helper expõe `E2eConfig.fromMap`, testável sem emulador; `integration_test/support/` não é importável de `test/`, então o trecho puro mora em `lib/core/testing/e2e_config.dart` — **fora de `lib/` de produção não**: manter em `test/support/e2e_config.dart` e importar das duas suítes por caminho relativo `../../test/support/e2e_config.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e_config.dart';

void main() {
  test('sem manifesto, não há configuração e vale o fallback', () {
    expect(E2eConfig.fromMap(const {}), isNull);
  });

  test('o manifesto escolhe o paciente pelo papel', () {
    final config = E2eConfig.fromMap({
      'patients': [
        {'role': 'main', 'cpf': '52998224725', 'birthDate': '1990-01-01', 'id': 'a', 'name': 'x', 'chronic': false, 'microAreaId': 'm'},
        {'role': 'outsider', 'cpf': '11144477735', 'birthDate': '1970-02-02', 'id': 'b', 'name': 'y', 'chronic': false, 'microAreaId': 'n'},
      ],
      'acs': {'id': 'c', 'matricula': 'E2E-1', 'password': 'p'},
      'microAreaId': 'm',
    })!;
    expect(config.patient('outsider').birthDate, DateTime(1970, 2, 2));
    expect(() => config.patient('inexistente'), throwsStateError);
  });

  test('toString nunca mostra o CPF', () {
    final config = E2eConfig.fromMap({
      'patients': [{'role': 'main', 'cpf': '52998224725', 'birthDate': '1990-01-01', 'id': 'a', 'name': 'x', 'chronic': false, 'microAreaId': 'm'}],
      'acs': {'id': 'c', 'matricula': 'E2E-1', 'password': 'p'},
      'microAreaId': 'm',
    })!;
    expect(config.toString().contains('52998224725'), isFalse);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/e2e_login_test.dart`
Expected: FAIL (`e2e_config.dart` não existe).

- [ ] **Step 3: Implementar `test/support/e2e_config.dart` e `integration_test/support/e2e_login.dart`**

`test/support/e2e_config.dart`:

```dart
/// Manifesto das fixtures de e2e (gerado por `bin/seed_e2e_fixtures.dart`).
/// Chega como `--dart-define-from-file=.e2e/fixtures.json`: cada chave do JSON
/// vira um define. Não importar em código de produção.
class E2ePatientFixture {
  const E2ePatientFixture({required this.role, required this.cpf, required this.birthDate, required this.microAreaId});
  final String role;
  final String cpf;
  final DateTime birthDate;
  final String microAreaId;
  @override
  String toString() => 'E2ePatientFixture($role)'; // sem CPF
}

class E2eConfig {
  const E2eConfig({required this.patients, required this.microAreaId, required this.acsMatricula, required this.acsPassword});
  final List<E2ePatientFixture> patients;
  final String microAreaId;
  final String acsMatricula;
  final String acsPassword;

  E2ePatientFixture patient(String role) =>
      patients.firstWhere((p) => p.role == role, orElse: () => throw StateError('sem paciente "$role" no manifesto'));

  static E2eConfig? fromMap(Map<String, Object?> map) {
    final list = map['patients'];
    if (list is! List) return null;
    final acs = (map['acs']! as Map).cast<String, Object?>();
    return E2eConfig(
      patients: [
        for (final raw in list.cast<Map>())
          E2ePatientFixture(
            role: raw['role'] as String, cpf: raw['cpf'] as String,
            birthDate: DateTime.parse(raw['birthDate'] as String), microAreaId: raw['microAreaId'] as String,
          ),
      ],
      microAreaId: map['microAreaId']! as String,
      acsMatricula: acs['matricula']! as String,
      acsPassword: acs['password']! as String,
    );
  }

  @override
  String toString() => 'E2eConfig(${patients.length} pacientes)';
}
```

`integration_test/support/e2e_login.dart`: `const _patients = String.fromEnvironment('patients')` **não** funciona (define de lista vira texto). Por isso o manifesto entra como **um** define JSON: o script passa `--dart-define=E2E_FIXTURES="$(cat .e2e/fixtures.json)"` e o helper faz `jsonDecode(const String.fromEnvironment('E2E_FIXTURES'))`. Corrigir o texto do docstring de `e2e_config.dart` para isso.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_patient/core/network/auth_session.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import '../../test/support/e2e_config.dart';

const _fixtures = String.fromEnvironment('E2E_FIXTURES');
const _otpRelay = String.fromEnvironment('OTP_RELAY', defaultValue: 'http://localhost:8765/code');

E2eConfig? e2eConfig() =>
    _fixtures.isEmpty ? null : E2eConfig.fromMap((jsonDecode(_fixtures) as Map).cast<String, Object?>());

/// Entra como o paciente [role] da fixture, pelo OTP real; sem manifesto (CI),
/// usa o login de desenvolvimento, como antes.
Future<AuthSession> loginPatient(BackendClient backend, {String role = 'main'}) async {
  final config = e2eConfig();
  if (config == null) return backend.developmentLogin(role: 'patient');
  final fixture = config.patient(role);
  final pedidoEm = DateTime.now().toUtc().millisecondsSinceEpoch;
  await backend.requestOtp(cpf: fixture.cpf, birthDate: fixture.birthDate);
  final code = await _codeFromRelay(pedidoEm);
  return backend.verifyOtp(cpf: fixture.cpf, code: code);
}

Future<String> _codeFromRelay(int since) async {
  final client = HttpClient();
  try {
    for (var i = 0; i < 20; i++) {
      final request = await client.getUrl(Uri.parse('$_otpRelay?since=$since'));
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode == 200) return body.trim();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('o relé não devolveu o código do OTP (rode otp_relay.py e adb reverse tcp:8765)');
  } finally {
    client.close(force: true);
  }
}
```

Ajustar `requestOtp`/`verifyOtp` aos tipos reais de `BackendClient` (o CPF chega com ou sem máscara conforme a assinatura: ler `backend_client.dart:63-80` e `passwordless_login_test.dart`).

- [ ] **Step 4: Rodar o teste puro**

Run: `cd apps/patient && flutter test test/e2e_login_test.dart`
Expected: 3/3 PASS.

- [ ] **Step 5: Trocar os usos fixos**

- `smoke_test.dart`, `backend_connection_test.dart`, `push_register_test.dart`: `await backend.developmentLogin(role: 'patient')` → `await loginPatient(backend)`; remover `const seedMicroAreaId` e trocar `expect(session.microAreaId, seedMicroAreaId)` por `expect(session.microAreaId, e2eConfig()?.microAreaId ?? seedMicroAreaIdDeDesenvolvimento)` **ou**, melhor, `expect(session.microAreaId, isNotEmpty)` quando há manifesto (a igualdade com a fixture é a prova). Manter a constante de desenvolvimento num único lugar (`e2e_login.dart`, `const developmentMicroAreaId`) só para o fallback da CI.
- `tool/live_check.dart` e `tool/push_consent.dart` (rodam no host com `dart run`): ler o manifesto de `.e2e/fixtures.json` se existir (`File`), senão `developmentLogin`. Reusar `E2eConfig.fromMap`.

- [ ] **Step 6: Provar o teste falhando sem o relé e passando com ele**

```bash
export PATH="$HOME/Android/Sdk/platform-tools:$PATH"
./scripts/qa/e2e_stack.sh up && ./scripts/qa/e2e_stack.sh seed
adb reverse tcp:8443 tcp:443 && adb reverse tcp:8765 tcp:8765
cd apps/patient
# 1) sem o relé: falha com a mensagem do helper
flutter test integration_test/smoke_test.dart -d emulator-5554 --dart-define=SINALACS_HOST=https://localhost:8443/ --dart-define=E2E_FIXTURES="$(cat ../../.e2e/fixtures.json)" 2>&1 | tail -5
# 2) com o relé
python3 ../../scripts/qa/otp_relay.py & R=$!
flutter test integration_test/smoke_test.dart -d emulator-5554 --dart-define=SINALACS_HOST=https://localhost:8443/ --dart-define=E2E_FIXTURES="$(cat ../../.e2e/fixtures.json)" 2>&1 | tail -5; kill $R
```
Expected: (1) FAIL com "o relé não devolveu o código do OTP"; (2) `All tests passed!`. Em (2) o login foi o OTP real com a stack sem login de desenvolvimento.

- [ ] **Step 7: Sem manifesto continua verde (CI)**

Run: `./scripts/qa/e2e.sh --emulator` (stack de desenvolvimento, sem `E2E_FIXTURES`)
Expected: verde, como antes (usa o fallback).

- [ ] **Step 8: Commit**

```bash
git add apps/patient
git commit -m "test(paciente): integração entra pelo OTP real com fixtures; login de desenvolvimento só como fallback da CI

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Jornada completa pela tela (integration_test com o app real)

**Files:**
- Create: `apps/patient/integration_test/full_journey_test.dart`
- Modify: `apps/patient/lib/app/app.dart` **somente se** faltar uma `Key` estável nos botões de urgência/triagem (ler antes; preferir achar por `Key` que já existe: `panic_button`, `submit_triage`, `refresh_status`, `cpf_field`, `birth_date_field`, `enter_button`, `otp_code_field`, `verify_code_button`, `login_error`, `terms_gate_accept_button`, `consent_switch_segmentedPush`).

**Interfaces:**
- Consumes: `loginPatient`/`e2eConfig()` (Task 4), `BackendClient` real, `SinalAcsApp(backend:, pushTokens:)`, fixtures `main`, `chronic`, `outsider`.
- Produces: o teste `jornada` (um arquivo, vários `testWidgets` em sequência com `group`), usado por `patient_full_e2e.sh` (Task 7).

- [ ] **Step 1: Ler as telas para os gestos exatos**

Ler em `apps/patient/test/patient_app_mvp_test.dart` os testes que usam `panic_button`, `submit_triage` (triagem: como marcar "dor no peito"), `refresh_status` e `openMyData` (helpers nas linhas 172-211) e copiar os mesmos `find`/`tap` — eles já são a verdade dos gestos.

- [ ] **Step 2: Escrever o teste (vai falhar até a stack de e2e estar de pé)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';

import 'support/e2e_login.dart';
import '../test/support/e2e_config.dart';
import 'support/otp_relay_client.dart'; // extrair de e2e_login.dart: Future<String> codeFromRelay(int since)

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final config = e2eConfig();

  Future<BackendClient> backendReal() async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    return BackendClient(trustedCaBytes: ca);
  }

  Future<void> digitarEEntrar(WidgetTester tester, E2ePatientFixture p, {String? codigo}) async {
    await tester.enterText(find.byKey(const Key('cpf_field')), p.cpf);
    final d = p.birthDate;
    final data = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    await tester.enterText(find.byKey(const Key('birth_date_field')), data);
    final pedidoEm = DateTime.now().toUtc().millisecondsSinceEpoch;
    await tester.tap(find.byKey(const Key('enter_button')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await tester.enterText(find.byKey(const Key('otp_code_field')), codigo ?? await codeFromRelay(pedidoEm));
    await tester.tap(find.byKey(const Key('verify_code_button')));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  group('jornada do paciente contra o banco de teste', skip: config == null ? 'defina E2E_FIXTURES (scripts/qa/patient_full_e2e.sh)' : false, () {
    testWidgets('código errado não entra; o certo entra', (tester) async {
      final backend = await backendReal();
      addTearDown(backend.close);
      await tester.pumpWidget(SinalAcsApp(backend: backend));
      final p = config!.patient('main');
      await digitarEEntrar(tester, p, codigo: '000000');
      expect(find.byKey(const Key('login_error')), findsOneWidget);
      expect(find.byKey(const Key('panic_button')), findsNothing);
    });

    testWidgets('login, termos, triagem vermelha, alerta e status', (tester) async {
      final backend = await backendReal();
      addTearDown(backend.close);
      await tester.pumpWidget(SinalAcsApp(backend: backend));
      final p = config!.patient('chronic');   // paciente diferente: respeita os 60 s do OTP
      await digitarEEntrar(tester, p);
      // Termos: o paciente da fixture não aceitou; é um convite, não uma trava.
      if (find.byKey(const Key('terms_gate_accept_button')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('terms_gate_accept_button')));
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      // Triagem: dor no peito -> vermelho (copiar os gestos de patient_app_mvp_test.dart).
      // ... marcar sintoma e tocar submit_triage; esperar 'vermelho' na tela.
      // Alerta: tocar panic_button; esperar a confirmação; abrir o status e tocar refresh_status.
      // Esperar o texto de status real ("pendente") — não o vazio 'status_empty'.
      expect(find.byKey(const Key('status_empty')), findsNothing);
    });

    testWidgets('Meus dados mostra o cadastro da fixture, e só o dela', (tester) async {
      // login do 'main'; abrir Mais > Meus dados (openMyData);
      // expect(find.text(nome da fixture), findsOneWidget) — o manifesto tem o nome;
      // expect(find.textContaining('Outra Área'), findsNothing).
    });
  });
}
```

Os comentários `// ...` acima marcam **onde colar os gestos lidos no Step 1**; eles não ficam no arquivo final — cada um vira as linhas `tester.tap/enterText/expect` correspondentes. O teste só está completo quando nenhum comentário-lacuna resta. Acrescentar `nome` ao `E2ePatientFixture` (campo `name`) para a asserção de "Meus dados".

- [ ] **Step 3: Rodar sem a stack e ver falhar pelo motivo certo**

Run: `cd apps/patient && flutter test integration_test/full_journey_test.dart -d emulator-5554 --dart-define=SINALACS_HOST=https://localhost:8443/`
Expected: grupo **pulado** (sem `E2E_FIXTURES`), sem falha falsa.

- [ ] **Step 4: Rodar com a stack, o seed, o relé e o `adb reverse`**

```bash
cd apps/patient && flutter test integration_test/full_journey_test.dart -d emulator-5554 \
  --dart-define=SINALACS_HOST=https://localhost:8443/ --dart-define=E2E_FIXTURES="$(cat ../../.e2e/fixtures.json)"
```
Expected: 3/3 PASS. Se uma tela mudar, corrigir o **teste** (gesto), nunca o app para agradar o teste; se o app estiver errado, parar e usar `superpowers:systematic-debugging`.

- [ ] **Step 5: Prova de território (Review Focus)**

Acrescentar um `testWidgets` que entra como `main`, abre "Meus dados" e confirma que o nome do `outsider` não aparece; e um teste de backend real, no mesmo arquivo, que faz `loginInstitutional` do ACS (helper `acsBackend` com `config.acsMatricula`/`acsPassword`) e confirma que `patients.listMicroArea` lista `main` e `chronic` e **não** `outsider`. Rodar de novo; Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/patient/integration_test apps/patient/test/support
git commit -m "test(paciente): jornada completa pela tela contra o banco de teste (OTP, triagem, alerta, status, Meus dados, território)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Push de ponta a ponta com o ACS institucional e o banco de e2e

**Files:**
- Modify: `apps/acs/tool/send_notice.dart` (aceitar `--matricula` e `--password`; sem eles, `developmentLogin` como hoje)
- Modify: `apps/acs/test/` (teste do parser de argumentos, se a leitura for extraída)
- Modify: `scripts/qa/push_e2e.sh` (modo `--e2e-db`: `psql_q` via `e2e_stack.sh psql`, login do paciente/ACS do manifesto; sem a flag, comportamento atual intacto)
- Modify: `apps/patient/integration_test/push_register_test.dart` (já usa `loginPatient` da Task 4)

**Interfaces:**
- Consumes: Task 1 (`e2e_stack.sh psql`), Task 2 (manifesto), Task 4 (`loginPatient`), `AcsBackend.loginInstitutional` (ver `apps/acs/lib/core/network/backend_client.dart`).
- Produces: `push_e2e.sh --e2e-db --negativos` sai com 0 provando entrega e negativos **sem tocar** o banco de desenvolvimento.

- [ ] **Step 1: Teste que falha (argumentos do `send_notice`)**

Extrair a leitura de argumentos para uma função pura `NoticeArgs parseNoticeArgs(List<String>)` em `apps/acs/tool/send_notice_args.dart` e testar em `apps/acs/test/send_notice_args_test.dart`: `--matricula M --password P` preenche os campos; sem eles ficam `null`; `--title` vazio é erro. Rodar `cd apps/acs && flutter test test/send_notice_args_test.dart` → FAIL; implementar; → PASS.

- [ ] **Step 2: `send_notice` com login institucional**

No `main`, trocar `await backend.developmentLogin(role: 'acs')` por: se `args.matricula != null`, `await backend.loginInstitutional(matricula:, password:)`; senão o login de desenvolvimento. A senha nunca é impressa.

- [ ] **Step 3: `push_e2e.sh --e2e-db`**

Dentro do script: quando `--e2e-db`, (a) `psql_q() { ./scripts/qa/e2e_stack.sh psql "$1"; }`; (b) não subir a stack de desenvolvimento (`docker compose --profile push up` do topo vira `./scripts/qa/e2e_stack.sh up && seed`); (c) `send()` passa `--matricula/--password` lidos de `.e2e/fixtures.json` com `python3 -c`; (d) o teste de registro recebe `--dart-define=E2E_FIXTURES=...` e `adb reverse tcp:8765`, e o relé sobe e é encerrado em `trap`; (e) `tool/push_consent.dart` usa o manifesto (Task 4). Ler o script inteiro antes (150 linhas) e alterar só esses pontos.

- [ ] **Step 4: Rodar**

Run: `export PATH="$HOME/Android/Sdk/platform-tools:$PATH"; ./scripts/qa/push_e2e.sh --e2e-db --negativos`
Expected: termina com `OK — o aviso chegou ao emulador` e exit 0. Conferir depois que o banco de desenvolvimento não foi tocado: `docker exec sinalacs-postgres psql -U sinalacs_user -d sinalacs_db -Atc "select count(*) from push_tokens"` inalterado e nenhuma linha `community_notice` nova em `audit_logs` de desenvolvimento.

- [ ] **Step 5: Commit**

```bash
git add apps/acs/tool apps/acs/test scripts/qa/push_e2e.sh apps/patient/integration_test
git commit -m "test(e2e): push do ACS institucional até o emulador contra o banco de teste, sem tocar o de desenvolvimento

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Runner único, documentação e execução final no emulador 5554

**Files:**
- Create: `scripts/qa/patient_full_e2e.sh`
- Modify: `apps/CLAUDE.md`, `backend/CLAUDE.md` (seção de seeds), `PROGRESS.md`, `.env.example` (nada novo esperado), memória do projeto

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: `./scripts/qa/patient_full_e2e.sh [--sem-push]`: um comando que faz tudo e sai 0/≠0.

- [ ] **Step 1: Escrever o runner**

```bash
#!/usr/bin/env bash
# Teste completo do app do paciente no emulador-5554 contra o banco de teste.
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/Android/Sdk/platform-tools:$PATH"
dev=emulator-5554
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado"; exit 4; }

./scripts/qa/e2e_stack.sh up
./scripts/qa/e2e_stack.sh seed
adb -s "$dev" reverse tcp:8443 tcp:443 >/dev/null
adb -s "$dev" reverse tcp:8765 tcp:8765 >/dev/null
python3 scripts/qa/otp_relay.py & relay=$!
trap 'kill $relay 2>/dev/null || true; ./scripts/qa/e2e_stack.sh down' EXIT

fixtures="$(cat .e2e/fixtures.json)"
( cd apps/patient
  flutter test integration_test/full_journey_test.dart integration_test/backend_connection_test.dart \
    -d "$dev" --dart-define=SINALACS_HOST=https://localhost:8443/ --dart-define=E2E_FIXTURES="$fixtures" )
if [[ "${1:-}" != --sem-push ]]; then
  trap - EXIT; kill $relay 2>/dev/null || true
  ./scripts/qa/push_e2e.sh --e2e-db --negativos
  ./scripts/qa/e2e_stack.sh down
fi
echo 'OK — jornada completa do paciente contra o banco de teste'
```

`chmod +x`. O `trap` derruba o banco de e2e mesmo em falha.

- [ ] **Step 2: Rodar duas vezes seguidas (Review Focus)**

Run: `./scripts/qa/patient_full_e2e.sh; echo "1ª exit=$?"; ./scripts/qa/patient_full_e2e.sh; echo "2ª exit=$?"`
Expected: as duas com exit 0, UUIDs/CPFs diferentes (`diff` entre cópias do manifesto mostra tudo distinto) e o banco de desenvolvimento intacto.

- [ ] **Step 3: Suítes de regressão**

Run: `cd apps/patient && flutter analyze && flutter test; cd ../../backend/sinalacs_server && dart test; cd ../.. && ./scripts/qa/ci_invariants.sh`
Expected: analyze limpo; paciente 236+ (233 + 3 do `e2e_login_test`); backend 439 (433 + 6 de fixtures); invariantes ok. `./scripts/qa/e2e.sh --emulator` segue verde (fallback da CI).

- [ ] **Step 4: Documentar**

- `apps/CLAUDE.md`: parágrafo "Teste completo do paciente" (comando, o que prova, pré-requisitos: emulador, credenciais FCM, Play Services, relé).
- `backend/CLAUDE.md`: `seed_e2e_fixtures.dart` e a regra de que só escreve em `sinalacs_e2e`.
- `PROGRESS.md`: seção "Teste completo do paciente (2026-09-30)" com o que foi provado, contagens e o que **não** foi (iOS, aparelho físico, Gorush hospedado; `development.sql` e `developmentLogin` continuam existindo para a stack de desenvolvimento e a CI).
- Memória do projeto: um arquivo novo `patient-full-e2e-2026-09-30.md` e a linha em `MEMORY.md`.

- [ ] **Step 5: Commit**

```bash
git add scripts/qa/patient_full_e2e.sh apps/CLAUDE.md backend/CLAUDE.md PROGRESS.md
git commit -m "test(e2e): runner único do teste completo do paciente e documentação

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fora do escopo

- Trocar os widget tests (`FakePatientBackend`, "Fulano de Tal", CPF `123.456.789-09`): são herméticos por desenho.
- Remover `developmentLogin`, `development.sql` ou os seeds de desenvolvimento: a stack de desenvolvimento e o job `android-e2e` da CI ainda dependem deles. Migrar a CI para a stack de e2e é um plano próprio (mexe em `ci.yml` e no `ci_invariants.sh`).
- iOS/APNs, aparelho físico, Gorush hospedado, backoffice de atendimento dos pedidos do titular.

## Self-review

- **Cobertura do pedido:** backend no Docker com Gorush (Task 1, 6), dados fixos identificados (tabela) e substituídos por fixtures no banco de teste (Tasks 1–4, 6), teste completo no emulador (Tasks 5–7).
- **Placeholders:** os trechos marcados "colar os gestos lidos no Step 1" da Task 5 e o corpo do seeder da Task 2, Step 5, dependem de arquivos existentes citados com caminho e linha; o plano os declara como a fonte a copiar e proíbe deixar comentário-lacuna no arquivo final. Se o executor preferir, deve ler `seed_acs_credentials.dart`/`seed_health_data.dart` antes de começar a Task 2.
- **Consistência de nomes:** `E2eConfig.fromMap`/`patient(role)`, `loginPatient`, `e2eConfig()`, `codeFromRelay`, `generateE2eFixtures`, `E2eFixtures.byRole`, `e2e_stack.sh up|down|seed|psql` usados igual em todas as tasks. Correção feita: o manifesto entra por **um** define `E2E_FIXTURES` (JSON), não por `--dart-define-from-file` (que quebraria listas).
- **Rulings:** banco `sinalacs_e2e` dentro do `postgres-test` (e não `sinalacs_test`) para não colidir com `dart test`; fallback ao login de desenvolvimento quando não há manifesto, para não quebrar o `android-e2e` da CI.
