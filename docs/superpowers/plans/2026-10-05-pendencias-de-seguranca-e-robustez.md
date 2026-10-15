# Pendências de segurança e robustez (TOTP, alertas sob a reautenticação, certificados de dev, scripts de QA) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Confirmar, com evidência, quais dos cinco pontos ainda estão abertos e corrigir os que estiverem: bloqueio progressivo contra adivinhação de TOTP, alertas visíveis sob a reautenticação, `sync_dev_ca.sh` que confere o par chave/certificado e não deixa `.tmp`, permissão das chaves privadas de dev e robustez dos scripts de `FLAG_SECURE` e de assinatura.

**Architecture:** Cinco assuntos independentes, uma task por assunto (mais uma de verificação e uma de documentação). A Task 1 só mede. Cada correção segue TDD no menor teste que prova o defeito (teste Dart, teste de shell com PATH-shim, cenário do script de assinatura). O bloqueio progressivo adiciona **uma coluna** (`lockStreak`) e mantém a política no serviço e a contagem atômica numa instrução SQL, como já é hoje.

**Tech Stack:** Dart/Serverpod (`backend/sinalacs_server`, `dart test`), Flutter (`apps/acs`, `flutter test`), bash + openssl (`scripts/dev`, `scripts/qa`), Gradle Kotlin DSL (`apps/acs/android/app/build.gradle.kts`).

**Spec:** `PROGRESS.md` ("Adivinhação de TOTP" e "Minors adiados" T1, T2, T3, T5, T7, linhas ~610–630), `spec/security_assessment.md` (achado F6), `spec/lgpd_design.md` (controle de acesso e monitoramento), `spec/ux_accessibility_assessment.md` (SC 4.1.3 e contraste de texto vermelho), `CLAUDE.md` (invariante: "Red alerts must never be silently dropped").

Levantamento com `graphify query` e leitura do código em 2026-10-05, **antes** de executar (a Task 1 repete cada medida):

| # | Ponto | Estado observado |
|---|-------|------------------|
| 1 | Bloqueio progressivo do TOTP | **Aberto.** `InstitutionalAuthService.maxFailedAttempts = 5`, `lockDuration = 15 min` fixos (`institutional_auth_service.dart:153-154`); `_registrarFalha` reinicia a contagem quando o bloqueio vence (`:402-415`); `user_credentials` só tem `failedAttempts` e `lockedUntil`. Senha errada e TOTP errado compartilham o mesmo contador. |
| 2 | Alerta sob a reautenticação | **A confirmar por teste.** `_openReauth` (`apps/acs/lib/app/app.dart:1188`) empilha um `LoginScreen` opaco; fila e feed seguem vivos por baixo (o comentário da linha ~1175 garante que nada é descartado), mas nada na rota de reautenticação mostra que há alerta novo. |
| 3 | `sync_dev_ca.sh` | **Aberto.** Confere CA→folha (`check_ca`) e CA→cert do cliente (`openssl verify`), mas **não** compara a chave privada com o certificado do cliente; não há `trap`, então uma falha ou Ctrl-C entre a fase 2 e a 3 deixa `*.tmp` nos assets. |
| 4 | Chaves em 644 | **Aberto.** `infra/docker/mosquitto/init.sh:128` e `infra/docker/traefik/init.sh:173` fazem `chmod 644` em `*.key` (inclui `acs-area-12.key`, `ca.key`, `server.key`). A cópia no asset já nasce 600. |
| 5a | `acs_secure_window.sh` | **Aberto.** `awk ... exit` consome o pipe do `dumpsys` com `set -o pipefail` (risco de SIGPIPE no `adb`) e `sleep 6` é fixo. |
| 5b | `acs_release_signing.sh` / Gradle | **Parcial.** Hermeticidade **já fechada** (`unset SINALACS_KEYSTORE_*` na linha 23). **Abertos:** `project.hasProperty("sinalacs.allowDebugSigning")` vale mesmo com `=false`; a mensagem não diz qual das quatro propriedades falta; `apksigner="$(ls .../build-tools/*/apksigner | tail -1)"` ordena por texto (`9.0.0` > `34.0.0`). |
| 5c | Comentários | **A confirmar.** `video/capture/capture-acs.sh` cita o rótulo antigo da UBS; `secure_window_test.dart` só confere string no fonte; falta documentar como regenerar capturas do ACS. |

## Global Constraints

- Triagem determinística e nunca alterável à mão; alerta vermelho **nunca** é descartado em silêncio (`CLAUDE.md`).
- Nunca dado real de paciente em teste, log, captura ou configuração de dev; credenciais de teste sintéticas.
- `registerFailedAttempt` continua sendo **uma instrução SQL**, sem leitura-antes-de-escrita; "bloqueio ativo não conta nem estende tentativa" continua valendo.
- Matrícula inexistente e senha errada continuam produzindo a mesma exceção e a mesma mensagem; o bloqueio só é revelado depois de a senha conferir (`institutional_auth_service.dart`, regra 1 e 3).
- Texto vermelho em UI usa `redOnSurface` medido contra a superfície onde renderiza (`apps/CLAUDE.md`, "WCAG contrast tokens"); mensagens dinâmicas usam `Semantics(liveRegion: true)`.
- Nunca editar `lib/src/generated/` nem `migrations/` à mão: `serverpod generate` e `serverpod create-migration` (`backend/CLAUDE.md`).
- Interface e documentação em português; commits sem atribuição de IA (regra do repositório).
- Rodar `graphify update .` depois de modificar código.

## Fora do escopo

- Limite por origem (IP) no `loginInstitutional`: é infraestrutura (middleware do Traefik), já listado no `PROGRESS.md`.
- Redefinição de MFA por coordenador e MFA trust-on-first-use.
- Qualquer mudança em produção: as chaves de dev e os scripts de QA só valem na stack local.

## Review Focus

- ACS legítimo que erra o código depois de um bloqueio vencido: o próximo bloqueio é mais longo, mas um login correto zera tudo (a escalada nunca pode virar bloqueio permanente).
- Duas requisições concorrentes que cruzam o limite: a contagem continua certa e a coluna `lockStreak` sobe **uma** vez só.
- Alerta que chega com a reautenticação aberta e o banner já visível: o banner some quando o ACS confirma o alerta ou entra, e nunca cobre o campo de matrícula/senha/código.
- `sync_dev_ca.sh` interrompido depois de promover o primeiro asset: nenhum `*.tmp` sobra e um novo `sync` funciona.
- Chave do cliente de outro par (regerada sem o certificado): `sync_dev_ca.sh` recusa **antes** de copiar qualquer asset, com a mensagem "nada foi copiado" verdadeira.

---

### Task 1: Verificar o estado de cada ponto (somente medir)

**Files:**
- Modify: nenhum. O resultado vira a tabela do commit da Task 8 e decide quais tasks 2–7 rodam.

**Interfaces:**
- Produces: para cada ponto, `ABERTO` ou `FECHADO` com o comando e a saída que provam.

- [ ] **Step 1: Orientar-se no grafo (obrigatório antes de abrir código)**

```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
graphify query "InstitutionalAuthService lockDuration maxFailedAttempts registerFailedAttempt" --budget 1200
graphify query "AcsHomeShell _openReauth LoginScreen reauthUserId alert queue" --budget 1200
graphify query "sync_dev_ca.sh acs_client key tmp" --budget 800
```
Expected: nós `InstitutionalAuthService`, `OrmAcsCredentialStore`, `AcsHomeShell`/`_AcsHomeShellState`, `sync_dev_ca.sh`.

- [ ] **Step 2: Pontos 1, 3, 4 e 5 — medir**

```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
# 1: política fixa e sem coluna de escalada
grep -n "maxFailedAttempts = \|lockDuration = " backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart
grep -n "lockStreak" -r backend/sinalacs_server/lib/src | grep -v generated || echo "1: sem lockStreak (ABERTO)"
# 3: par chave/certificado e trap
grep -n "pubkey\|pkey\|trap " scripts/dev/sync_dev_ca.sh || echo "3: sem conferência de par nem trap (ABERTO)"
# 4: modo das chaves (e dono: define se 600 é viável para o usuário do host)
grep -n "chmod 644" infra/docker/mosquitto/init.sh infra/docker/traefik/init.sh
ls -ln infra/docker/mosquitto/runtime/certs/*.key infra/docker/traefik/runtime/certs/*.key 2>/dev/null
# 5a/5b
grep -n "sleep 6\|awk -v pkg" scripts/qa/acs_secure_window.sh
grep -n "hasProperty" apps/acs/android/app/build.gradle.kts
grep -n "apksigner=" scripts/qa/acs_release_signing.sh
grep -n "UBS" video/capture/capture-acs.sh
```
Expected: cada linha confirma a tabela acima. Se algo mostrar `FECHADO` (por exemplo `lockStreak` já existir), registrar e **pular** a task correspondente.

- [ ] **Step 3: Ponto 2 — o teste da Task 4 é a medida**; registrar "a confirmar na Task 4".

- [ ] **Step 4: Registrar** a tabela com o resultado literal; nada a commitar.

---

### Task 2: Política de bloqueio progressivo no serviço (falha primeiro)

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart:40-66` (registro), `:152-154` (constantes), `:402-415` (`_registrarFalha`)
- Test: `backend/sinalacs_server/test/unit/institutional_auth_service_test.dart`

**Interfaces:**
- Produces:
  - `AcsCredentialRecord.lockStreak` (`final int`, parâmetro nomeado com default `0`, para não quebrar os construtores existentes).
  - `static Duration InstitutionalAuthService.lockDurationFor(int streak)` = `15 min * 2^streak`, teto de `maxLockDuration = Duration(hours: 24)`.
  - `_registrarFalha` passa a calcular `lockUntil: at.add(lockDurationFor(record.lockStreak))`.
- Decisões (ledger): a escalada reinicia **só** num login válido (`registerSuccessfulLogin`); senha e TOTP seguem no mesmo contador (um atacante que já tem a senha gasta o mesmo orçamento); o teto de 24 h evita bloqueio permanente de ACS legítimo; a leitura de `lockStreak` pelo serviço pode estar uma rodada atrasada sob concorrência (a mesma tolerância que o código já documenta para `lockedUntil`).

- [ ] **Step 1: Escrever os testes que falham**

No arquivo de teste, junto dos testes de política (use o `group`/helpers do primeiro teste do arquivo para montar serviço e store; o `_FakeStore` está em `institutional_auth_service_test.dart:13`). Primeiro a função pura:

```dart
  group('lockDurationFor (bloqueio progressivo)', () {
    test('dobra a cada rodada de bloqueio, a partir de 15 min', () {
      expect(InstitutionalAuthService.lockDurationFor(0), const Duration(minutes: 15));
      expect(InstitutionalAuthService.lockDurationFor(1), const Duration(minutes: 30));
      expect(InstitutionalAuthService.lockDurationFor(2), const Duration(hours: 1));
      expect(InstitutionalAuthService.lockDurationFor(3), const Duration(hours: 2));
    });

    test('nunca passa de 24 h, mesmo com sequência enorme', () {
      expect(InstitutionalAuthService.lockDurationFor(7), const Duration(hours: 24));
      expect(InstitutionalAuthService.lockDurationFor(500), const Duration(hours: 24));
    });

    test('sequência negativa (linha corrompida) vale como zero', () {
      expect(InstitutionalAuthService.lockDurationFor(-3), const Duration(minutes: 15));
    });
  });
```

Depois, no `_FakeStore`, espelhar o SQL do store real: onde o fake aplica `lockedUntil` ao atingir o limite, incrementar também `lockStreak`; `registerSuccessfulLogin` do fake zera `lockStreak`; o `AcsCredentialRecord` que o fake devolve passa `lockStreak: lockStreak`. E o teste de serviço (mesma forma dos testes de bloqueio existentes: cinco logins com a senha errada, depois repetir depois do vencimento):

```dart
    test('a segunda rodada de bloqueio dura o dobro; o login válido zera a escalada', () async {
      final t0 = DateTime.utc(2026, 10, 5, 12);
      for (var i = 0; i < InstitutionalAuthService.maxFailedAttempts; i++) {
        await expectLater(
          service.login(matricula: 'ACS-001', password: 'errada', now: t0),
          throwsA(isA<AuthenticationFailedException>()),
        );
      }
      expect(store.lockedUntil, t0.add(const Duration(minutes: 15)));

      // 16 min depois: o bloqueio venceu; mais cinco falhas bloqueiam por 30 min.
      final t1 = t0.add(const Duration(minutes: 16));
      for (var i = 0; i < InstitutionalAuthService.maxFailedAttempts; i++) {
        await expectLater(
          service.login(matricula: 'ACS-001', password: 'errada', now: t1),
          throwsA(isA<AuthenticationFailedException>()),
        );
      }
      expect(store.lockedUntil, t1.add(const Duration(minutes: 30)));
      expect(store.lockStreak, 2);

      // Vencido o segundo bloqueio, a senha certa entra e zera a escalada.
      final t2 = t1.add(const Duration(minutes: 31));
      await service.login(matricula: 'ACS-001', password: senhaCerta, now: t2);
      expect(store.lockStreak, 0);
      expect(store.lockedUntil, isNull);
    });
```
(`service`, `store` e `senhaCerta` são os nomes que o primeiro teste do arquivo usa; se forem outros, use os dele.)

- [ ] **Step 2: Ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/institutional_auth_service_test.dart`
Expected: erro de compilação `The method 'lockDurationFor' isn't defined` / `lockStreak`.

- [ ] **Step 3: Implementar**

`AcsCredentialRecord`: adicionar `this.lockStreak = 0,` ao construtor e `final int lockStreak;` com o comentário `/// Quantas vezes seguidas a conta bloqueou sem um login válido no meio.`

Constantes e função, ao lado de `lockDuration`:

```dart
  static const maxFailedAttempts = 5;
  static const lockDuration = Duration(minutes: 15);

  /// Teto do bloqueio progressivo: bloquear para sempre transformaria o limite
  /// num ataque ao acesso do próprio ACS.
  static const maxLockDuration = Duration(hours: 24);

  /// Bloqueio da [streak]-ésima rodada seguida (0 = a primeira): `15 min × 2^streak`,
  /// no máximo [maxLockDuration]. Sequência negativa vale como zero.
  static Duration lockDurationFor(int streak) {
    final n = streak < 0 ? 0 : streak;
    // 2^7 × 15 min já passa de 24 h; limitar o expoente evita estouro em `<<`.
    if (n >= 7) return maxLockDuration;
    final d = lockDuration * (1 << n);
    return d > maxLockDuration ? maxLockDuration : d;
  }
```

`_registrarFalha`: trocar `lockUntil: at.add(lockDuration),` por `lockUntil: at.add(lockDurationFor(record.lockStreak)),`. Atualizar o doc comment da classe (regra 2) para citar a escalada.

- [ ] **Step 4: Ver passar**

Run: `cd backend/sinalacs_server && dart test test/unit/institutional_auth_service_test.dart test/unit/institutional_auth_mfa_test.dart`
Expected: passam. Se o `_Store` de `institutional_auth_mfa_test.dart:28` não compilar, acrescentar `lockStreak` a ele da mesma forma (campo + incremento + zerar).

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart backend/sinalacs_server/test/unit
git commit -m "feat(auth): bloqueio progressivo (15 min x 2^rodada, teto 24 h) no login institucional"
```

---

### Task 3: Coluna `lockStreak` e a instrução SQL atômica

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/user_credential.spy.yaml`
- Create (gerados): nova pasta em `backend/sinalacs_server/migrations/` e `lib/src/generated/*` via `serverpod`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_acs_credential_store.dart` (`findByEnrollmentId`, `registerFailedAttempt`, `registerSuccessfulLogin`)
- Modify: `spec/lgpd_data_audit.md` (a linha de `user_credentials`)
- Test: o teste do `OrmAcsCredentialStore` contra o banco de teste (`grep -rln OrmAcsCredentialStore backend/sinalacs_server/test`)

**Interfaces:**
- Consumes: `AcsCredentialRecord.lockStreak` e `lockDurationFor` (Task 2).
- Produces: coluna `user_credentials."lockStreak" bigint NOT NULL DEFAULT 0`; o store lê a coluna para o registro, incrementa **no mesmo `UPDATE`** quando o bloqueio é aplicado e zera no login válido.

- [ ] **Step 1: Teste que falha (banco de teste)** — ao lado dos testes de `registerFailedAttempt` do store ORM, usando a mesma montagem de credencial sintética:

```dart
    test('lockStreak sobe uma vez por bloqueio aplicado e zera no login válido', () async {
      final at = DateTime.utc(2026, 10, 5, 12);
      for (var i = 0; i < 5; i++) {
        await store.registerFailedAttempt(acsId,
            restartCounter: false, maxFailedAttempts: 5, lockUntil: at.add(const Duration(minutes: 15)), at: at);
      }
      expect((await store.findByEnrollmentId(matricula))!.lockStreak, 1);

      // Rajada concorrente na linha já bloqueada: o WHERE recusa, a sequência não sobe de novo.
      await Future.wait([
        for (var i = 0; i < 5; i++)
          store.registerFailedAttempt(acsId,
              restartCounter: false, maxFailedAttempts: 5, lockUntil: at.add(const Duration(minutes: 15)), at: at),
      ]);
      expect((await store.findByEnrollmentId(matricula))!.lockStreak, 1);

      await store.registerSuccessfulLogin(acsId, at.add(const Duration(minutes: 20)));
      expect((await store.findByEnrollmentId(matricula))!.lockStreak, 0);
    });
```

- [ ] **Step 2: Ver falhar**

Run: `cd backend/sinalacs_server && dart test <arquivo do teste do store ORM> -N "lockStreak"`
Expected: erro de compilação (`lockStreak` não existe no registro devolvido) ou coluna inexistente.

- [ ] **Step 3: Implementar**

`user_credential.spy.yaml`, depois de `lockedUntil`:

```yaml
  ### Rodadas de bloqueio seguidas, sem um login válido no meio. Alimenta o
  ### bloqueio progressivo (15 min x 2^lockStreak, teto 24 h). Zera no login válido.
  lockStreak: int, default=0
```

Gerar (nunca à mão):

```bash
cd backend/sinalacs_server
serverpod generate
serverpod create-migration
```
Expected: nova pasta em `migrations/` cujo `migration.sql` faz `ADD COLUMN "lockStreak" bigint NOT NULL DEFAULT 0` (aditiva, preserva as linhas de dev). Abrir o `migration.sql` e conferir isso antes de seguir.

`registerFailedAttempt` — acrescentar a coluna ao `SET`, só no ramo em que o bloqueio é aplicado:

```sql
             "lockStreak" = CASE
                 WHEN @restart THEN "lockStreak"
                 WHEN "failedAttempts" + 1 >= @maxFailedAttempts THEN "lockStreak" + 1
                 ELSE "lockStreak"
               END,
```
(`@restart` preserva a sequência: o bloqueio vencido recomeça a contagem de falhas, **não** a escalada.) `registerSuccessfulLogin`: `SET "failedAttempts" = 0, "lockedUntil" = NULL, "lockStreak" = 0, ...`. `findByEnrollmentId`: passar `lockStreak: row.lockStreak` ao `AcsCredentialRecord`.

- [ ] **Step 4: Ver passar e rodar a suíte do backend que toca no login**

Run: `cd backend/sinalacs_server && dart test test/unit/institutional_auth_service_test.dart test/unit/institutional_auth_mfa_test.dart <teste do store ORM>`
Expected: passam. Em seguida `docker compose` com `pg_data/` antigo: a migração é aditiva, então **não** exige `rm -rf pg_data/` (ao contrário da Track E, que o `CLAUDE.md` avisa).

- [ ] **Step 5: Documentar a coluna** em `spec/lgpd_data_audit.md` (linha de `user_credentials`: `lockStreak`, não sensível, contador de segurança) e atualizar a contagem de colunas/tabelas citada, se o texto trouxer uma.

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/lib backend/sinalacs_server/migrations backend/sinalacs_server/test spec/lgpd_data_audit.md
git commit -m "feat(auth): coluna lockStreak e escalada atômica do bloqueio do login institucional"
```

---

### Task 4: Alerta visível sob a tela de reautenticação

**Files:**
- Create: `apps/acs/lib/app/pending_alerts_banner.dart`
- Modify: `apps/acs/lib/app/app.dart:1188-1215` (`_openReauth`, o `page` da rota)
- Test: `apps/acs/test/pending_alerts_banner_test.dart` (novo); `apps/acs/test/session_reauth_test.dart` (montagem do shell já existente)

**Interfaces:**
- Produces: `PendingAlertsBanner({required Listenable listenable, required int Function() count})` — some com `count() == 0`; texto `"1 alerta vermelho aguardando. Entre para ver."` ou `"N alertas vermelhos aguardando. Entre para ver."`; `Key('reauth_pending_alerts')`; `Semantics(liveRegion: true)`; cor do texto `context.acsRisk.redOnSurface` sobre `Theme.of(context).cardColor`.

- [ ] **Step 1: Teste do widget isolado (falha)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/app/pending_alerts_banner.dart';

void main() {
  Widget host(ValueNotifier<int> n) => MaterialApp(
        theme: buildAcsDarkTheme(),
        home: Scaffold(
          body: PendingAlertsBanner(listenable: n, count: () => n.value),
        ),
      );

  testWidgets('sem alerta pendente não mostra nada', (t) async {
    await t.pumpWidget(host(ValueNotifier(0)));
    expect(find.byKey(const Key('reauth_pending_alerts')), findsNothing);
  });

  testWidgets('mostra a contagem e acompanha as mudanças', (t) async {
    final n = ValueNotifier(1);
    await t.pumpWidget(host(n));
    expect(find.text('1 alerta vermelho aguardando. Entre para ver.'), findsOneWidget);

    n.value = 3;
    await t.pump();
    expect(find.text('3 alertas vermelhos aguardando. Entre para ver.'), findsOneWidget);

    n.value = 0;
    await t.pump();
    expect(find.byKey(const Key('reauth_pending_alerts')), findsNothing);
  });

  testWidgets('é região viva (SC 4.1.3)', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(host(ValueNotifier(2)));
    expect(
      t.getSemantics(find.byKey(const Key('reauth_pending_alerts'))),
      matchesSemantics(isLiveRegion: true, label: '2 alertas vermelhos aguardando. Entre para ver.'),
    );
    h.dispose();
  });
}
```

- [ ] **Step 2: Ver falhar**

Run: `cd apps/acs && flutter test test/pending_alerts_banner_test.dart`
Expected: `Target of URI doesn't exist: '.../pending_alerts_banner.dart'`.

- [ ] **Step 3: Implementar** — `lib/app/pending_alerts_banner.dart`:

```dart
import 'package:flutter/material.dart';

import 'acs_theme.dart';

/// Aviso fixo no topo da reautenticação (sessão vencida ou bloqueio): o painel
/// com a fila de alertas fica por baixo da rota opaca, e um alerta vermelho que
/// chega ali não pode esperar o novo login para ser notado.
class PendingAlertsBanner extends StatelessWidget {
  const PendingAlertsBanner({super.key, required this.listenable, required this.count});

  final Listenable listenable;
  final int Function() count;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final n = count();
          if (n <= 0) return const SizedBox.shrink();
          final texto = n == 1
              ? '1 alerta vermelho aguardando. Entre para ver.'
              : '$n alertas vermelhos aguardando. Entre para ver.';
          return Material(
            key: const Key('reauth_pending_alerts'),
            color: Theme.of(context).cardColor,
            child: Semantics(
              liveRegion: true,
              label: texto,
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  texto,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.acsRisk.redOnSurface, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          );
        },
      );
}
```

Run: `cd apps/acs && flutter test test/pending_alerts_banner_test.dart` → Expected: passam.

- [ ] **Step 4: Ligar na rota de reautenticação e provar com o shell**

Em `_openReauth`, o `page` passa a ser:

```dart
    Widget page(BuildContext _) => Column(
          children: [
            SafeArea(
              bottom: false,
              child: PendingAlertsBanner(listenable: _queue, count: () => _queue.unacknowledgedCount),
            ),
            Expanded(
              child: LoginScreen(
                visitScopeFor: widget.visitScopeFor,
                themeController: widget.themeController,
                directory: widget.directory,
                feedBuilder: widget.feedBuilder,
                initialAlert: widget.initialAlert,
                initialPosition: widget.initialPosition,
                syncInterval: widget.syncInterval,
                aviso: aviso,
                reauthUserId: widget.acsId,
              ),
            ),
          ],
        );
```
(importar `pending_alerts_banner.dart`). Em `test/session_reauth_test.dart`, acrescentar um teste com a **mesma montagem** do primeiro teste desse arquivo que abre a reautenticação: depois de a rota abrir, entregar um alerta à fila (pelo `feedBuilder`/fila que o teste já injeta) e afirmar `find.byKey(const Key('reauth_pending_alerts'))` `findsOneWidget`, e que o campo de matrícula continua tocável. Rodar `flutter test test/session_reauth_test.dart test/login_flow_test.dart`.
Expected: verde. **Se o teste do shell passar sem a mudança do `_openReauth`** (ex.: o painel já aparece por outro caminho), registrar no ledger que o ponto 2 estava fechado e **reverter** o passo 4, mantendo só a prova.

- [ ] **Step 5: Contraste** — conferir se `test/contrast_tokens_test.dart` já mede `redOnSurface` contra `cardColor`; se não medir, acrescentar o par à matriz do teste (padrão do arquivo) e rodar `flutter test test/contrast_tokens_test.dart`.

- [ ] **Step 6: Commit**

```bash
git add apps/acs/lib/app apps/acs/test
git commit -m "feat(acs): aviso de alertas pendentes sobre a reautenticação"
```

---

### Task 5: `sync_dev_ca.sh` confere o par chave/certificado e não deixa `.tmp`

**Files:**
- Modify: `scripts/dev/sync_dev_ca.sh`
- Create: `scripts/dev/sync_dev_ca_test.sh`
- Modify: `.github/workflows/ci.yml` (job `workflow-lint`, junto dos outros `*_test.sh`) **somente se** esse job já roda scripts de teste de shell; o job list guardado por `ci_invariants.sh` não muda.

**Interfaces:**
- Produces: variável opcional `SYNC_DEV_CA_ROOT` (padrão: a raiz do repositório, como hoje) para o teste apontar a uma árvore temporária; `trap` que remove os seis `*.tmp`; conferência `chave pública do certificado == chave pública da chave` antes da fase 2.

- [ ] **Step 1: Escrever o teste de shell (falha)** — `scripts/dev/sync_dev_ca_test.sh`:

```bash
#!/usr/bin/env bash
#
# Prova o sync_dev_ca.sh numa árvore temporária (nunca toca nos assets reais).
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$aqui/sync_dev_ca.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

falha() { echo "FALHOU: $*" >&2; exit 1; }

# CA + folha de servidor + certificado e chave do cliente, tudo descartável.
gera_runtime() {
  local dir="$1" ; mkdir -p "$dir"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$dir/ca.key" -out "$dir/ca.crt" -days 2 -subj "/CN=ca-teste" 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -keyout "$dir/server.key" -out "$dir/server.csr" -subj "/CN=localhost" 2>/dev/null
  openssl x509 -req -in "$dir/server.csr" -CA "$dir/ca.crt" -CAkey "$dir/ca.key" -CAcreateserial -out "$dir/server.crt" -days 2 2>/dev/null
}
monta() {
  local raiz="$1" ; rm -rf "$raiz"
  gera_runtime "$raiz/infra/docker/mosquitto/runtime/certs"
  gera_runtime "$raiz/infra/docker/traefik/runtime/certs"
  local m="$raiz/infra/docker/mosquitto/runtime/certs"
  openssl req -newkey rsa:2048 -nodes -keyout "$m/acs-area-12.key" -out "$m/c.csr" -subj "/CN=acs-area-12" 2>/dev/null
  openssl x509 -req -in "$m/c.csr" -CA "$m/ca.crt" -CAkey "$m/ca.key" -CAcreateserial -out "$m/acs-area-12.crt" -days 2 2>/dev/null
  mkdir -p "$raiz/apps/acs/assets/certs" "$raiz/apps/patient/assets/certs"
}
sem_tmp() { [[ -z "$(find "$1/apps" -name '*.tmp' 2>/dev/null)" ]]; }

echo "== caso 1: tudo certo copia os assets"
monta "$tmp/ok"
SYNC_DEV_CA_ROOT="$tmp/ok" "$script" >/dev/null || falha "o sync falhou numa árvore válida"
[[ -f "$tmp/ok/apps/acs/assets/certs/acs_client.key" ]] || falha "a chave do cliente não foi copiada"
[[ "$(stat -c %a "$tmp/ok/apps/acs/assets/certs/acs_client.key")" == 600 ]] || falha "a chave do cliente não está em 600"
sem_tmp "$tmp/ok" || falha "sobrou .tmp no caminho feliz"

echo "== caso 2: chave que não é o par do certificado é recusada antes de copiar"
monta "$tmp/par"
m="$tmp/par/infra/docker/mosquitto/runtime/certs"
openssl genrsa -out "$m/acs-area-12.key" 2048 2>/dev/null   # outra chave, mesmo certificado
if SYNC_DEV_CA_ROOT="$tmp/par" "$script" >"$tmp/saida" 2>&1; then falha "aceitou chave de outro par"; fi
grep -q "não é o par" "$tmp/saida" || falha "a mensagem não explicou o motivo: $(cat "$tmp/saida")"
grep -q "nada foi copiado" "$tmp/saida" || falha "a mensagem não diz que nada foi copiado"
[[ -z "$(find "$tmp/par/apps" -type f 2>/dev/null)" ]] || falha "algum asset foi copiado apesar do erro"

echo "== caso 3: falha no meio da publicação não deixa .tmp"
monta "$tmp/meio"
mkdir -p "$tmp/shim"
real="$(command -v openssl)"
# O `openssl x509 -subject` roda DEPOIS do primeiro `mv` (promote_ca): é a falha no meio.
cat >"$tmp/shim/openssl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == "-subject" ]] && exit 1; done
exec "$real" "\$@"
EOF
chmod +x "$tmp/shim/openssl"
if PATH="$tmp/shim:$PATH" SYNC_DEV_CA_ROOT="$tmp/meio" "$script" >/dev/null 2>&1; then falha "o sync não falhou com o shim"; fi
sem_tmp "$tmp/meio" || falha "sobrou .tmp depois da falha no meio: $(find "$tmp/meio/apps" -name '*.tmp')"

echo "OK — sync_dev_ca.sh: par conferido, nada copiado no erro, sem .tmp"
```

- [ ] **Step 2: Ver falhar**

Run: `chmod +x scripts/dev/sync_dev_ca_test.sh && ./scripts/dev/sync_dev_ca_test.sh`
Expected: `FALHOU:` no caso 1 (o script ignora `SYNC_DEV_CA_ROOT` e procura a árvore real) — ou, depois do passo 3 parcial, no caso 2 ("aceitou chave de outro par") e no caso 3 ("sobrou .tmp").

- [ ] **Step 3: Implementar** — em `sync_dev_ca.sh`:

(a) a raiz passa a ser sobrescrevível (o `repo_root=` existente fica como padrão):

```bash
repo_root="${SYNC_DEV_CA_ROOT:-$repo_root}"
```
(logo depois da linha que define `repo_root`; se o script a define antes de `set -euo pipefail`, colocar a nova linha depois dessa definição).

(b) `trap` no início das fases, cobrindo os seis temporários:

```bash
limpar_tmp() {
  rm -f "$repo_root"/apps/{acs,patient}/assets/certs/{dev_ca.crt,dev_rpc_ca.crt}.tmp \
        "$repo_root"/apps/acs/assets/certs/acs_client.{crt,key}.tmp
}
trap limpar_tmp EXIT
```
O `mv` bem-sucedido já consumiu o `.tmp` correspondente, então o `rm -f` do trap só apaga o que sobrou. Um `trap ... EXIT` roda também em Ctrl-C porque o `bash` sai pelo `EXIT`.

(c) a conferência do par, logo depois do `openssl verify` do certificado do cliente:

```bash
pub_crt="$(openssl x509 -in "$mqtt_certs/acs-area-12.crt" -noout -pubkey)"
pub_key="$(openssl pkey -in "$mqtt_certs/acs-area-12.key" -pubout 2>/dev/null || true)"
if [[ -z "$pub_key" || "$pub_crt" != "$pub_key" ]]; then
  echo "erro: $mqtt_certs/acs-area-12.key não é o par do certificado acs-area-12.crt — nada foi copiado." >&2
  echo "Apague infra/docker/mosquitto/runtime e suba a stack de novo para regerar o par." >&2
  exit 1
fi
```

- [ ] **Step 4: Ver passar**

Run: `./scripts/dev/sync_dev_ca_test.sh && bash -n scripts/dev/sync_dev_ca.sh`
Expected: os três casos `OK` e a linha final `OK — sync_dev_ca.sh: ...`. Conferir também que o script **real** ainda funciona com a stack no ar: `./scripts/dev/sync_dev_ca.sh` imprime as quatro cópias e `ls apps/acs/assets/certs/*.tmp` não lista nada.

- [ ] **Step 5: CI** — se `workflow-lint` já executa `scripts/qa/*_test.sh`, acrescentar `scripts/dev/sync_dev_ca_test.sh` na mesma lista de passos (um passo por teste, como `lib_rele_test.sh`); rodar `./scripts/qa/ci_invariants.sh` e `actionlint` (o job continua o mesmo, só ganha um passo).

- [ ] **Step 6: Commit**

```bash
git add scripts/dev/sync_dev_ca.sh scripts/dev/sync_dev_ca_test.sh .github/workflows/ci.yml
git commit -m "fix(dev): sync_dev_ca.sh confere o par da chave do cliente e limpa os .tmp"
```

---

### Task 6: Permissão das chaves privadas de desenvolvimento (medir e decidir)

**Files:**
- Modify: `infra/docker/mosquitto/init.sh:127-128`, `infra/docker/traefik/init.sh:172-173` (**somente** se a medida permitir) e `spec/lgpd_design.md`/`PROGRESS.md` (a decisão)

**Interfaces:**
- Consumes: `sync_dev_ca.sh` (Task 5), que copia `acs-area-12.key` com o usuário do host.
- Produces: uma decisão registrada: quais chaves ficam 600/640 e quais precisam de 644, e por quê.

O 644 existe porque o `init.sh` roda **dentro de um contêiner como root** e os arquivos ficam num bind mount lido por outro usuário (o `mosquitto`, o Traefik e o usuário do host que roda o `sync_dev_ca.sh`). Apertar sem medir quebra a stack em silêncio.

- [ ] **Step 1: Medir quem lê o quê**

```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
ls -ln infra/docker/mosquitto/runtime/certs infra/docker/traefik/runtime/certs
id -u
docker compose exec -T mosquitto id 2>/dev/null; docker compose exec -T traefik id 2>/dev/null
grep -n "user:\|USER " docker-compose.yml infra/docker/mosquitto/Dockerfile infra/docker/traefik/Dockerfile 2>/dev/null
```
Expected: dono (`uid`) das `.key`, o usuário de cada contêiner e o `uid` do host. Quadro de decisão:

| Chave | Quem lê | Se lê como outro uid que o dono | Resultado |
|-------|---------|---------------------------------|-----------|
| `acs-area-12.key` | só `sync_dev_ca.sh` e `tool/live_check.dart` (host) | dono = root, host ≠ root | 600 quebra a cópia → manter 644 **e documentar**; ou `chown` para o uid do host no `init.sh` (variável `HOST_UID`) |
| `server.key` (broker/Traefik) | o próprio serviço | contêiner não-root ≠ dono | 640 com grupo, ou manter 644 |
| `ca.key` | ninguém depois de assinar as folhas | — | 600 |

- [ ] **Step 2: Teste que falha para o que for apertável** — `scripts/qa/dev_key_permissions_test.sh` (só roda com a stack gerada; sem `runtime/`, sai 0 com aviso, como os outros scripts de QA que dependem da stack):

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dirs=(infra/docker/mosquitto/runtime/certs infra/docker/traefik/runtime/certs)
[[ -d "${dirs[0]}" ]] || { echo "sem runtime/ (suba a stack antes); nada a conferir"; exit 0; }
ruim=0
for k in "${dirs[0]}/ca.key" "${dirs[1]}/ca.key"; do
  [[ -f "$k" ]] || continue
  m="$(stat -c %a "$k")"
  [[ "$m" == 600 ]] || { echo "ca.key em $m (esperado 600): $k" >&2; ruim=1; }
done
exit "$ruim"
```
Expected antes da correção: falha (`ca.key em 644`).

- [ ] **Step 3: Implementar o que a medida permitir** — em cada `init.sh`, separar o `chmod`:

```sh
chmod 644 "$certs_dir"/*.crt
chmod 644 "$certs_dir/server.key"   # lida pelo serviço, que roda como outro uid (medido na Task 6)
chmod 600 "$certs_dir/ca.key"        # só assina folhas; ninguém precisa lê-la depois
```
(no Mosquitto, `acs-area-12.key` e demais `*.key` seguem o resultado do quadro: 644 documentado, ou `chown` ao uid do host.) Subir a stack do zero e provar que nada quebrou:

```bash
docker compose down && rm -rf infra/docker/mosquitto/runtime infra/docker/traefik/runtime
docker compose up -d --build && ./scripts/dev/sync_dev_ca.sh && ./scripts/qa/dev_key_permissions_test.sh && ./scripts/qa/mtls_invariants.sh && ./scripts/qa/tls_invariants.sh
```
Expected: stack saudável; os dois invariantes de TLS/mTLS passam; o teste de permissão passa. **Se qualquer um quebrar, desfazer a mudança correspondente** e registrar a razão: o plano aceita "manter 644 e documentar" como desfecho válido para as chaves lidas por outro uid.

- [ ] **Step 4: Registrar a decisão** em `PROGRESS.md` (substituindo o minor T7 "chaves privadas de cliente em 644") e em `spec/lgpd_design.md` (nota de dev: gitignored, máquina de um usuário, nunca em produção).

- [ ] **Step 5: Commit**

```bash
git add infra/docker scripts/qa/dev_key_permissions_test.sh PROGRESS.md spec/lgpd_design.md
git commit -m "fix(dev): ca.key em 600; decisão registrada para as demais chaves de dev"
```

---

### Task 7: Robustez dos scripts de `FLAG_SECURE` e de assinatura, e comentários

**Files:**
- Modify: `scripts/qa/acs_secure_window.sh:54-66`
- Modify: `scripts/qa/acs_release_signing.sh:30`, mais um cenário 5
- Modify: `apps/acs/android/app/build.gradle.kts:170,188,133` (`hasProperty`) e `:172-182` (mensagem)
- Modify: `apps/acs/test/secure_window_test.dart`
- Modify: `video/capture/capture-acs.sh:9` (rótulo) e a documentação de captura

**Interfaces:**
- Produces: `acs_secure_window.sh` sem pipe com `exit` e sem `sleep` fixo; guard do Gradle que só libera com `=true`; `apksigner` escolhido por versão.

- [ ] **Step 1: `acs_secure_window.sh` — espera ativa e awk sem SIGPIPE**

Trocar `sleep 6` e o pipe por:

```bash
# Espera a janela do app aparecer (até 40 s), em vez de dormir um tempo fixo.
dump=""
for _ in $(seq 1 40); do
  dump="$(adb -s "$dev" shell dumpsys window windows 2>/dev/null || true)"
  grep -q "^  Window #.*$pkg/" <<<"$dump" && break
  sleep 1
done
# O dumpsys já está numa variável: o awk lê tudo, sem `exit` sobre um pipe
# (com pipefail isso podia matar o adb por SIGPIPE e abortar o script).
flags="$(awk -v pkg="$pkg" '
  /^  Window #/ { dentro = index($0, pkg "/") > 0 }
  dentro && /^ +fl=/ && !achou { print; achou = 1 }' <<<"$dump")"
```
Run: `bash -n scripts/qa/acs_secure_window.sh` (o teste de ponta a ponta exige o emulador: `./scripts/qa/acs_secure_window.sh --reinstalar` no `emulator-5554`).
Expected: `OK — janela do ACS com FLAG_SECURE`.

- [ ] **Step 2: Guard do Gradle só com `=true` (cenário que falha primeiro)**

Em `scripts/qa/acs_release_signing.sh`, depois do cenário 4, acrescentar:

```bash
echo "== cenário 5: -Psinalacs.allowDebugSigning=false NÃO libera a assinatura de debug =="
if saida="$(construir -Psinalacs.allowDebugSigning=false -Psinalacs.allowDevClientKey=true 2>&1)"; then
  echo "erro: allowDebugSigning=false liberou a build de release sem chave." >&2
  exit 1
fi
grep -q "assinatura de release" <<<"$saida" || { echo "erro: a falha não explicou o motivo:" >&2; tail -n 15 <<<"$saida" >&2; exit 1; }
```
Run (precisa do SDK e da stack para as senhas do `.env`): `./scripts/qa/acs_release_signing.sh`
Expected antes da correção: o cenário 5 falha com "allowDebugSigning=false liberou a build" (porque `hasProperty` ignora o valor).

Em `build.gradle.kts`, uma função só para as três licenças e a mensagem que lista o que falta:

```kotlin
// `-Pfoo=false` não pode liberar nada: só o texto "true" vale.
fun licenca(nome: String): Boolean = project.findProperty(nome)?.toString() == "true"
```
e trocar `project.hasProperty("sinalacs.allowDebugSigning")` por `licenca("sinalacs.allowDebugSigning")`, o mesmo para `sinalacs.allowDevClientKey` (`:188`) e `sinalacs.allowMissingMqttPassword` (`:133`). Na mensagem do guard (`:172-182`), acrescentar antes do "Informe a chave…":

```kotlin
val faltam = listOf(
    "storeFile (SINALACS_KEYSTORE_PATH)" to releaseStoreFile,
    "storePassword (SINALACS_KEYSTORE_PASSWORD)" to releaseStorePassword,
    "keyAlias (SINALACS_KEY_ALIAS)" to releaseKeyAlias,
    "keyPassword (SINALACS_KEY_PASSWORD)" to releaseKeyPassword,
).filter { it.second == null }.joinToString(", ") { it.first }
```
com a linha `|Faltando: $faltam` na mensagem (o texto "assinatura de release" que os cenários 1 e 5 procuram permanece).

- [ ] **Step 3: `apksigner` pela maior versão**

Em `acs_release_signing.sh:30`:

```bash
apksigner="$(ls -d "$HOME"/Android/Sdk/build-tools/*/ | sort -V | tail -1)apksigner"
[[ -x "$apksigner" ]] || { echo "erro: apksigner não encontrado em $HOME/Android/Sdk/build-tools" >&2; exit 4; }
```

- [ ] **Step 4: Rodar a prova completa do release**

Run: `./scripts/qa/acs_release_signing.sh`
Expected: cenários 1–5 passam e a linha final `OK — release exige chave própria; ...`. Se o ambiente não tiver SDK/emulador, registrar que a prova **não** foi executada e rodar só `bash -n` nos dois scripts e `cd apps/acs && flutter test test/android_manifest_test.dart`.

- [ ] **Step 5: Comentários e teste que só olha string**

- `video/capture/capture-acs.sh:9`: comparar a lista de rótulos do comentário com o texto real do botão no app (`grep -rn "Encaminhar para" apps/acs/lib`) e corrigir o comentário para o rótulo atual.
- `apps/acs/test/secure_window_test.dart`: além da string no fonte, acrescentar a asserção de que `MainActivity.kt` chama `window.setFlags(` com `FLAG_SECURE` **dentro de `onCreate`** (regex sobre o corpo de `onCreate`, não só a presença da palavra), seguindo o estilo do arquivo; rodar `cd apps/acs && flutter test test/secure_window_test.dart`.
- Documentar como regenerar capturas do ACS (que saem pretas com `FLAG_SECURE`): um parágrafo em `docs/telas-acs.md` apontando para a seção "FLAG_SECURE escurece captura e gravação" do `PROGRESS.md` e dizendo que a captura exige a janela desprotegida (remover a flag temporariamente) ou foto do aparelho.

- [ ] **Step 6: Commit**

```bash
git add scripts/qa apps/acs/android/app/build.gradle.kts apps/acs/test/secure_window_test.dart video/capture/capture-acs.sh docs/telas-acs.md
git commit -m "fix(qa): scripts de FLAG_SECURE e de assinatura mais robustos; guard só com =true"
```

---

### Task 8: Fechar a documentação e o grafo

**Files:**
- Modify: `PROGRESS.md` (bullet "Adivinhação de TOTP", "Minors adiados" T1/T2/T5/T7, bloco de pendências)
- Modify: `CLAUDE.md`/`backend/CLAUDE.md`/`apps/CLAUDE.md` (a frase de "5 tentativas por 15 min", a contagem de tabelas/colunas, se citadas)
- Modify: `spec/security_assessment.md` (F6: bloqueio progressivo)

- [ ] **Step 1: Atualizar o texto com o resultado medido** — para cada um dos cinco pontos, "fechado em 2026-10-05" com a prova (comando e saída) **ou** "continua aberto: <motivo medido>". O orçamento de adivinhação do TOTP passa a ser calculado na nova política (primeira rodada 5 tentativas; depois 5 a cada 30 min, 1 h, 2 h… até 24 h) e a conta do "0,14% ao dia" é refeita com a mesma fórmula do texto original, mostrando o valor novo.
- [ ] **Step 2: Verificações finais**

```bash
cd backend/sinalacs_server && dart analyze && dart test test/unit
cd ../../apps/acs && flutter analyze && flutter test
cd ../.. && ./scripts/dev/sync_dev_ca_test.sh && ./scripts/qa/check_documentation_links.sh && python3 scripts/qa/contagem_validation_report.py && graphify update .
```
Expected: tudo verde; se `contagem_validation_report.py` apontar divergência de contagem de testes, atualizar o número citado.
- [ ] **Step 3: Commit**

```bash
git add PROGRESS.md CLAUDE.md backend/CLAUDE.md apps/CLAUDE.md spec/security_assessment.md
git commit -m "docs: fecha pendências de TOTP, reautenticação, certificados de dev e scripts de QA"
```

## Self-Review

- **Cobertura:** (1) Tasks 2–3; (2) Task 4; (3) Task 5; (4) Task 6; (5) Task 7; verificação Task 1 e fechamento Task 8. O que o levantamento já mostrou fechado (hermeticidade do `acs_release_signing.sh`) está na tabela, não em task.
- **Placeholders:** os pontos que dependem de nomes não lidos estão explícitos como instrução de leitura com o arquivo e a linha (`_FakeStore` em `institutional_auth_service_test.dart:13`, `_Store` em `institutional_auth_mfa_test.dart:28`, o teste do store ORM por `grep`, a montagem de `session_reauth_test.dart`). O formato de `dumpsys` e o uid dos contêineres são medidos antes de qualquer mudança (Tasks 1 e 6).
- **Consistência de tipos:** `lockStreak`, `lockDurationFor`, `maxLockDuration`, `PendingAlertsBanner(listenable:, count:)`, `SYNC_DEV_CA_ROOT` e `licenca()` aparecem com os mesmos nomes em todas as tasks.
