# Issue #46 — verificação e fechamento: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provar, com evidência reexecutada, os dois critérios de aceite da #46, fechar as duas lacunas de código que ainda os contradizem e encerrar a issue com as pendências fora do código registradas em issues próprias.

**Architecture:** O trabalho da #46 já está no `develop` (PR #60, merge em 2026-10-14T20:23Z): tabelas `scheduled_notices`/`terms_versions`, `NoticeSchedulingService` + `NoticeDispatchLoop`, `TermsPublicationService`, sete métodos no `AdminEndpoint` e a aba Avisos/Termos do `apps/admin`. Este plano **não reimplementa nada disso**. Ele (1) reconfere a autoridade de quem agendou no momento do disparo — hoje um coordenador desativado ou trocado de UBS ainda tem o aviso enviado em nome dele, o que contradiz "restrito a papel autorizado" — e (2) faz o `push_e2e.sh` agendar pelo endpoint HTTP real `admin.scheduleNotice` (com login de staff + TOTP de verdade), em vez do `INSERT` direto de `bin/seed_e2e_scheduled_notice.dart`. O resto é reexecução de provas e documentação.

**Tech Stack:** Dart/Serverpod 3.4.13 (backend), Postgres de teste (`withServerpod`), Flutter (`apps/admin`, só Android), Bash (`scripts/qa`), Gorush + FCM, emulador `emulator-5554`.

**Spec:** issue GitHub #46 ("admin: gestão de avisos à comunidade (RF14) e de versões dos termos de uso"); plano anterior `docs/superpowers/plans/2026-10-14-issue-46-avisos-e-termos.md`; estado em `PROGRESS.md`, seção "Avisos agendados e versões dos termos (#46, 2026-10-14)"; contratos em `backend/CLAUDE.md`, seção "Avisos agendados e versões dos termos".

Texto da issue (critérios de aceite, literal):

> - [ ] Envio auditado e restrito a papel autorizado.
> - [ ] Teste e2e com Gorush (`push_e2e.sh`).
>
> O que falta: Criar/agendar avisos por microárea, com histórico. Publicar nova versão de termos/privacidade com aviso de 15 dias. Revisão jurídica do texto antes de publicar (pendência registrada).

## Verificação já feita (2026-10-14, leitura do código — ponto de partida)

| Item da issue | Estado no `develop` | Lacuna que este plano fecha |
|---|---|---|
| Agendar avisos por microárea, com histórico | Entregue (`AdminEndpoint.scheduleNotice/cancelScheduledNotice/noticeHistory`, aba Avisos) | — |
| Termos com aviso de 15 dias | Entregue (`TermsPublicationService`, sub-aba Termos, cartão do paciente lê `terms_versions`) | — |
| Revisão jurídica antes de publicar | Bloqueio no código entregue (`denied_not_reviewed`); a revisão do **texto real** é externa | Registrar como issue própria (Task 5) |
| Envio auditado e restrito a papel | Agendar/cancelar/histórico: autorizado e auditado. **Disparo não reconfere o autor** (`notice_scheduling_service.dart`, `dispatchDue`) | **Task 2** |
| e2e com Gorush (`push_e2e.sh`) | Verde em 2026-10-14, mas o aviso entra por `INSERT` direto (`bin/seed_e2e_scheduled_notice.dart`): o endpoint HTTP de agendamento nunca é exercido ponta a ponta | **Task 3** |

## Global Constraints

- Documentação, comentários, mensagens de commit e textos de UI em **português**.
- Nunca dado real de paciente em teste, log, captura ou config; nada de token, senha, código TOTP, CPF ou texto de aviso impresso por script (os scripts imprimem só ids e contagens).
- O texto do aviso (`message`) **nunca** vai para `audit_logs`.
- Negação de acesso é auditada com `record` (fail-closed) antes de lançar; no disparo (laço em segundo plano) usa-se `recordSafely`, como o `_failed` já faz.
- Sem reenvio automático de aviso: um aviso recusado no disparo termina em `failed`, nunca volta a `pending`.
- Sem migração nova: o estado de recusa reaproveita `ScheduledNoticeStatus.failed` + `failureReason`.
- Nada de framework/serviço fora de `spec/stack.md`.
- Commits sem atribuição de IA (`CLAUDE.md` do repositório prevalece sobre o lembrete de atribuição): **sem** `Co-Authored-By`, **sem** "Generated with Claude Code".
- Ações externas (comentar/fechar a issue, abrir issues novas, push) só depois de confirmação explícita do usuário.

## Review Focus

1. **Admin cuja conta de staff não existe em `staff_accounts`** (ex.: semeado só em `users`) — o disparo deve recusar (fail-closed) e o teste de integração precisa semear a conta do admin, senão os testes antigos de `dispatchDue` quebram em silêncio para `failed`. Coberto na Task 2 (Step 1, teste `authorityOf` com e sem linha; Step 6, semente do admin).
2. **Falha ao consultar a autoridade** (store lança) — não pode derrubar o laço nem enviar: vira `failed`. Coberto na Task 2 (teste "consulta de autoridade que lança").
3. **Coordenador trocado de UBS entre o agendamento e o disparo** — o aviso para a microárea antiga não sai. Coberto na Task 2.
4. **Anti-replay do TOTP no script de e2e**: o login logo após a ativação no mesmo passo de 30 s é recusado (`denied_totp_replay`). O script espera o passo seguinte. Coberto na Task 3 (função `passoTotp` testada + espera no `main`).
5. **Horário mínimo de 1 min (`noticeMinimumLeadTime`)**: agendar pelo endpoint com menos de 60 s é recusado; o script agenda a +70 s e o `push_e2e.sh` espera até 150 s pela bandeja. Coberto na Task 3 (Step 6, execução real).

---

## File Structure

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `backend/sinalacs_server/lib/src/application/notices/notice_scheduling_service.dart` | Modificar | `StaffAuthority`, `ScheduledNoticeStore.authorityOf`, checagem no `dispatchDue` |
| `backend/sinalacs_server/lib/src/infrastructure/database/orm_scheduled_notice_store.dart` | Modificar | `authorityOf` em SQL (`users` ⨝ `staff_accounts`) |
| `backend/sinalacs_server/test/unit/notice_scheduling_service_test.dart` | Modificar | Fake com `authorityMap`; testes de recusa no disparo |
| `backend/sinalacs_server/test/integration/notice_scheduling_endpoint_test.dart` | Modificar | Semente do admin em `staff_accounts`; `authorityOf` e disparo recusado no Postgres |
| `apps/admin/tool/schedule_notice.dart` | Criar | Login de staff com ativação de MFA + `admin.scheduleNotice` real; imprime só o id |
| `apps/admin/test/schedule_notice_tool_test.dart` | Criar | Leitura do manifesto e passo TOTP |
| `scripts/qa/e2e_stack.sh` | Modificar | `schedule-notice` chama o tool do admin |
| `scripts/qa/push_e2e.sh` | Modificar | Comentário, prazo da bandeja (150 s) |
| `backend/sinalacs_server/bin/seed_e2e_scheduled_notice.dart` | Remover | Substituído pelo endpoint real |
| `backend/CLAUDE.md`, `PROGRESS.md`, `CLAUDE.md` | Modificar | Registrar o novo comportamento e as provas |
| `docs/superpowers/plans/2026-10-14-issue-46-fechamento-*.log` | Criar | Logs de regressão e e2e (sem segredos) |

---

### Task 1: Linha de base e limpeza do worktree já mergeado

**Files:**
- Create: `docs/superpowers/plans/2026-10-14-issue-46-fechamento-baseline.log`

**Interfaces:**
- Consumes: nada.
- Produces: contagens de testes verdes que as Tasks 2–4 usam como referência.

- [ ] **Step 1: Confirmar que o branch da #46 está integrado e o worktree está limpo**

Run:
```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
git branch --merged develop | grep feat/issue-46-avisos-e-termos
git -C .worktrees/issue-46-avisos-termos status --short
```
Expected: a primeira linha imprime o branch; a segunda não imprime nada. Se o `status` mostrar alterações, **pare** e mostre ao usuário (pode ser trabalho não commitado).

- [ ] **Step 2: Remover o worktree e o branch local (só se o Step 1 passou)**

```bash
git worktree remove .worktrees/issue-46-avisos-termos
git branch -d feat/issue-46-avisos-e-termos
```
Expected: sem erro (`-d`, não `-D`: recusa se não estiver mergeado).

Crie o branch de trabalho (o `develop` é protegido; o fechamento entra por PR):

```bash
git switch -c fix/issue-46-fechamento develop
```

- [ ] **Step 3: Rodar a regressão de base e guardar o resumo**

```bash
export PATH="$PATH:$HOME/flutter/bin"
docker compose up -d postgres-test   # banco dos testes de integração (ver backend/CLAUDE.md)
( cd backend/sinalacs_server && dart analyze 2>&1 | tail -1 && dart test -j 1 2>&1 | tail -1 )
( cd apps/admin && flutter analyze 2>&1 | tail -1 && flutter test 2>&1 | tail -1 )
./scripts/qa/ci_invariants.sh && echo ci_invariants ok
```
Expected (referência do PROGRESS): backend `+1307` verdes, 0 erro/warning; admin `+456`, "No issues found"; `ci_invariants ok`. Copie as últimas linhas para `docs/superpowers/plans/2026-10-14-issue-46-fechamento-baseline.log` com data e comando. Se algo falhar, **pare**: use superpowers:systematic-debugging antes de seguir.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/2026-10-14-issue-46-fechamento-baseline.log
git commit -m "docs(plano): linha de base do fechamento da #46"
```

---

### Task 2: O disparo reconfere a autoridade de quem agendou

**Contexto.** `NoticeSchedulingService.dispatchDue` (`notice_scheduling_service.dart`) envia com `actorId: notice.createdBy` sem olhar se esse usuário ainda pode enviar. Regra nova, no momento do disparo, **antes** de chamar `_sendNow`:
- autor sem linha em `users` ⨝ `staff_accounts` → recusa;
- `staff_accounts.active = false` → recusa;
- papel fora de `Authorization.staffRoles` (`coordinator`, `admin`) → recusa;
- `coordinator` cuja `ubsId` é nula ou difere da UBS da microárea do aviso → recusa;
- `admin` ativo → envia.

Recusa = linha vai a `failed` com `failureReason = noticeAuthorRevokedReason`, **sem** chamar `_sendNow`, e uma linha de auditoria `community_notice` / `denied_author_revoked` (`userId` = autor, `resourceId` = id do aviso) por `recordSafely`. Se a consulta lançar, cai no `catch (_)` já existente → `failed` "Falha inesperada ao enviar o aviso." e auditoria `failed`.

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/notices/notice_scheduling_service.dart`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_scheduled_notice_store.dart`
- Test: `backend/sinalacs_server/test/unit/notice_scheduling_service_test.dart`
- Test: `backend/sinalacs_server/test/integration/notice_scheduling_endpoint_test.dart`

**Interfaces:**
- Consumes: `ScheduledNoticeStore.ubsOfMicroArea(String)`, `Authorization.staffRoles`, `AuditTrail.recordSafely(AuditEvent)`, `_finish(...)` (privado, já existe).
- Produces:
  - `class StaffAuthority { const StaffAuthority({required UserRole role, required bool active, String? ubsId}); }`
  - `ScheduledNoticeStore.authorityOf(String userId) → Future<StaffAuthority?>` (`null` = sem conta de staff)
  - `const String noticeAuthorRevokedReason = 'Quem agendou já não pode enviar avisos para esta microárea';`
  - resultado de auditoria novo: `'denied_author_revoked'`

- [ ] **Step 1: Ajustar o fake e escrever os testes de unidade que falham**

Em `test/unit/notice_scheduling_service_test.dart`, dentro de `class _FakeStore`, logo após `final ubsOfMicroAreaMap = ...;`, adicione:

```dart
  /// Autoridade do autor no disparo. Sem entrada: admin ativo, para os testes
  /// antigos de `dispatchDue` (que agendam como `adm-1`) continuarem a enviar.
  final authorityMap = <String, StaffAuthority?>{};
  var authorityThrows = false;

  @override
  Future<StaffAuthority?> authorityOf(String userId) async {
    if (authorityThrows) throw StateError('banco fora do ar');
    return authorityMap.containsKey(userId)
        ? authorityMap[userId]
        : const StaffAuthority(role: UserRole.admin, active: true);
  }
```

Procure o outro `implements ScheduledNoticeStore` do mesmo arquivo (por volta da linha 65, a classe que delega para `_inner`) e acrescente o delegador:

```dart
  @override
  Future<StaffAuthority?> authorityOf(String userId) => _inner.authorityOf(userId);
```

No fim do `group('dispatchDue', () { ... })`, antes do `});` que o fecha, adicione:

```dart
    group('autoridade de quem agendou no disparo', () {
      Future<String> dueBy(String author) => store.insert(
            createdBy: author,
            microAreaId: _ma1,
            audience: 'everyone',
            title: 'Titulo',
            message: 'TextoSecretoDoAviso',
            scheduledFor: now.subtract(const Duration(minutes: 5)),
            createdAt: now.subtract(const Duration(hours: 1)),
          );

      Future<void> expectRefused(String id, String author) async {
        expect(await service.dispatchDue(), 1);
        expect(sends, 0, reason: 'o aviso não pode sair');
        final r = store.rows[id]!;
        expect(r.status, ScheduledNoticeStatus.failed);
        expect(r.failureReason, noticeAuthorRevokedReason);
        final e = audit.events.last;
        expect(e.result, 'denied_author_revoked');
        expect(e.resourceType, 'community_notice');
        expect(e.resourceId, id);
        expect(e.userId, author);
        expect(dump(), isNot(contains('TextoSecretoDoAviso')));
      }

      test('coordenador desativado depois de agendar: não envia', () async {
        store.authorityMap['c-1'] =
            const StaffAuthority(role: UserRole.coordinator, active: false, ubsId: 'ubs-1');
        await expectRefused(await dueBy('c-1'), 'c-1');
      });

      test('coordenador trocado de UBS depois de agendar: não envia', () async {
        store.authorityMap['c-1'] =
            const StaffAuthority(role: UserRole.coordinator, active: true, ubsId: 'ubs-2');
        await expectRefused(await dueBy('c-1'), 'c-1');
      });

      test('coordenador sem UBS: não envia (fail-closed)', () async {
        store.authorityMap['c-1'] = const StaffAuthority(role: UserRole.coordinator, active: true);
        await expectRefused(await dueBy('c-1'), 'c-1');
      });

      test('autor sem conta de staff: não envia', () async {
        store.authorityMap['x-1'] = null;
        await expectRefused(await dueBy('x-1'), 'x-1');
      });

      test('autor rebaixado a ACS: não envia', () async {
        store.authorityMap['c-1'] =
            const StaffAuthority(role: UserRole.acs, active: true, ubsId: 'ubs-1');
        await expectRefused(await dueBy('c-1'), 'c-1');
      });

      test('admin desativado: não envia', () async {
        store.authorityMap['adm-1'] = const StaffAuthority(role: UserRole.admin, active: false);
        await expectRefused(await dueBy('adm-1'), 'adm-1');
      });

      test('coordenador ativo da mesma UBS: envia', () async {
        store.authorityMap['c-1'] =
            const StaffAuthority(role: UserRole.coordinator, active: true, ubsId: 'ubs-1');
        final id = await dueBy('c-1');
        expect(await service.dispatchDue(), 1);
        expect(sends, 1);
        expect(store.rows[id]!.status, ScheduledNoticeStatus.sent);
      });

      test('consulta de autoridade que lança: failed, sem envio, laço segue', () async {
        store.authorityThrows = true;
        final a = await dueBy('adm-1');
        final b = await dueBy('adm-1');
        expect(await service.dispatchDue(), 2);
        expect(sends, 0);
        for (final id in [a, b]) {
          expect(store.rows[id]!.status, ScheduledNoticeStatus.failed);
        }
        expect(audit.events.where((e) => e.result == 'failed'), hasLength(2));
      });

      test('recusa de um não impede o envio do outro', () async {
        store.authorityMap['c-1'] =
            const StaffAuthority(role: UserRole.coordinator, active: false, ubsId: 'ubs-1');
        final recusado = await dueBy('c-1');
        final enviado = await dueBy('adm-1');
        expect(await service.dispatchDue(), 2);
        expect(sends, 1);
        expect(store.rows[recusado]!.status, ScheduledNoticeStatus.failed);
        expect(store.rows[enviado]!.status, ScheduledNoticeStatus.sent);
      });
    });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/notice_scheduling_service_test.dart`
Expected: FAIL de compilação — `StaffAuthority`, `authorityOf` e `noticeAuthorRevokedReason` não existem.

- [ ] **Step 3: Implementar no serviço**

Em `notice_scheduling_service.dart`, logo depois de `const String noticeStuckSendingReason = ...;`, adicione:

```dart
/// Motivo gravado quando o disparo recusa o aviso porque quem o agendou já não
/// pode enviar para a microárea (desativado, sem conta de staff, papel ou UBS
/// trocados). Não há reenvio: o aviso termina `failed`.
const String noticeAuthorRevokedReason =
    'Quem agendou já não pode enviar avisos para esta microárea';

/// Autoridade atual de um usuário de staff, lida no disparo (não no token).
class StaffAuthority {
  const StaffAuthority({required this.role, required this.active, this.ubsId});

  final UserRole role;
  final bool active;

  /// UBS do coordenador; nula para administrador.
  final String? ubsId;
}
```

Na interface `ScheduledNoticeStore`, logo depois de `Future<String?> ubsOfMicroArea(String microAreaId);`, adicione:

```dart
  /// Papel, situação e UBS atuais do usuário de staff, ou `null` se ele não tem
  /// linha em `staff_accounts` (o disparo trata isso como recusa).
  Future<StaffAuthority?> authorityOf(String userId);
```

Em `dispatchDue`, troque o início do corpo do `try` (a linha `final r = await _sendNow(`) para que a checagem venha antes:

```dart
      try {
        if (!await _authorMayStillSend(notice)) {
          await _finish(notice, ScheduledNoticeStatus.failed, reason: noticeAuthorRevokedReason);
          await _audit.recordSafely(AuditEvent(
            userId: notice.createdBy,
            actionType: 'write',
            resourceType: 'community_notice',
            resourceId: notice.id,
            result: 'denied_author_revoked',
          ));
          continue;
        }
        final r = await _sendNow(
```

Atualize o comentário de doc do `dispatchDue` acrescentando ao fim: `Antes de enviar, reconfere a autoridade de quem agendou ([_authorMayStillSend]): quem perdeu o direito não envia, e o aviso termina `failed`.`

Adicione o método privado logo antes de `Future<void> _failed(`:

```dart
  /// Regra do agendamento reaplicada no disparo, com o estado de AGORA: staff
  /// ativo; coordenador só para microárea da própria UBS. Fail-closed.
  Future<bool> _authorMayStillSend(ScheduledNoticeSnapshot notice) async {
    final authority = await _store.authorityOf(notice.createdBy);
    if (authority == null || !authority.active) return false;
    if (!Authorization.staffRoles.contains(authority.role)) return false;
    if (authority.role == UserRole.coordinator) {
      final target = await _store.ubsOfMicroArea(notice.microAreaId);
      return authority.ubsId != null && target != null && authority.ubsId == target;
    }
    return true;
  }
```

- [ ] **Step 4: Rodar os testes de unidade**

Run: `cd backend/sinalacs_server && dart test test/unit/notice_scheduling_service_test.dart test/unit/notice_service_test.dart`
Expected: PASS (os novos e todos os antigos). A compilação **ainda** falha no `OrmScheduledNoticeStore` se você rodar a suíte inteira — o Step 5 resolve.

- [ ] **Step 5: Teste de integração que falha (Postgres real)**

Em `test/integration/notice_scheduling_endpoint_test.dart`:

1. No `_seed`, depois do `StaffAccount.db.insertRow` do coordenador, semeie a conta do admin (o disparo agora exige `staff_accounts`, como o seed real e as fixtures de e2e já têm):

```dart
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_admin),
      enrollmentId: 'ADM-AVISO-1',
      active: true,
      ubsId: null,
    ),
  );
```

2. Adicione, junto dos demais `test(` do `withServerpod`:

```dart
    test('authorityOf lê papel, situação e UBS; sem conta de staff devolve null', () async {
      final adm = (await store.authorityOf(_admin))!;
      expect(adm.role, UserRole.admin);
      expect(adm.active, isTrue);
      expect(adm.ubsId, isNull);
      final coo = (await store.authorityOf(_coordA))!;
      expect(coo.role, UserRole.coordinator);
      expect(coo.ubsId, _ubsA);
      expect(await store.authorityOf('00000000-0000-4000-8000-0000000000ff'), isNull);
    });

    test('coordenador desativado depois de agendar: o disparo não envia', () async {
      final id = await service.schedule(
        _user(_coordA, UserRole.coordinator),
        microAreaId: _maA,
        audience: 'everyone',
        title: 'Título sintético',
        message: 'Mensagem sintética',
        scheduledFor: now.add(const Duration(minutes: 5)),
      );
      await session.db.unsafeExecute(
        'UPDATE staff_accounts SET "active" = false WHERE "id" = @id::uuid',
        parameters: QueryParameters.named({'id': _coordA}),
      );
      clock = now.add(const Duration(minutes: 10));
      expect(await service.dispatchDue(), 1);
      expect(sent, isEmpty);
      final r = await row(id);
      expect(r['status'], 'failed');
      expect(r['failureReason'], noticeAuthorRevokedReason);
      expect(audit.events.last.result, 'denied_author_revoked');
    });
```

Run: `cd backend/sinalacs_server && dart test test/integration/notice_scheduling_endpoint_test.dart`
Expected: FAIL de compilação — `OrmScheduledNoticeStore` não implementa `authorityOf`.

- [ ] **Step 6: Implementar no store ORM**

Em `orm_scheduled_notice_store.dart`, logo depois do método `ubsOfMicroArea`, adicione:

```dart
  @override
  Future<StaffAuthority?> authorityOf(String userId) async {
    final rows = await _session().db.unsafeQuery(
      'SELECT u."role", sa."active", sa."ubsId" FROM users u '
      'JOIN staff_accounts sa ON sa."id" = u."id" WHERE u."id" = @id::uuid',
      parameters: QueryParameters.named({'id': userId}),
    );
    if (rows.isEmpty) return null;
    final m = rows.first.toColumnMap();
    return StaffAuthority(
      // `UserRole` é `serialized: byName`: a coluna guarda o nome.
      role: UserRole.fromJson(m['role'] as String),
      active: m['active'] as bool,
      ubsId: m['ubsId']?.toString(),
    );
  }
```

Se `StaffAuthority` não for visível, o arquivo já importa `notice_scheduling_service.dart` (é de onde vem `ScheduledNoticeStore`); confira com `grep -n "^import" orm_scheduled_notice_store.dart`.

- [ ] **Step 7: Rodar integração e a suíte inteira**

Run:
```bash
cd backend/sinalacs_server
dart test test/integration/notice_scheduling_endpoint_test.dart test/integration/admin_endpoint_notices_test.dart
dart analyze && dart test -j 1 2>&1 | tail -1
```
Expected: PASS; `dart analyze` sem erro nem warning; total ≥ base da Task 1 + 11. Se um teste antigo de disparo virar `failed`, o autor dele não tem `staff_accounts` na semente: semeie, **não** afrouxe a regra.

- [ ] **Step 8: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/notices/notice_scheduling_service.dart \
        backend/sinalacs_server/lib/src/infrastructure/database/orm_scheduled_notice_store.dart \
        backend/sinalacs_server/test/unit/notice_scheduling_service_test.dart \
        backend/sinalacs_server/test/integration/notice_scheduling_endpoint_test.dart
git commit -m "fix(avisos): disparo reconfere a autoridade de quem agendou (#46)"
```

---

### Task 3: `push_e2e.sh` agenda pelo endpoint real `admin.scheduleNotice`

**Contexto.** Hoje `scripts/qa/e2e_stack.sh schedule-notice` roda `backend/sinalacs_server/bin/seed_e2e_scheduled_notice.dart`, que faz `INSERT` direto, porque "o login de staff exige TOTP e não é scriptável". É scriptável: o manifesto `.e2e/fixtures.json` (0600) já traz `staff.matricula`, `staff.password` e `staff.activationCode`, e `apps/admin/integration_test/support/totp.dart` já gera o código. O novo tool faz o caminho real: `auth.beginStaffTotpEnrollment` → `auth.confirmStaffTotpEnrollment` → espera o próximo passo de 30 s (anti-replay, `institutional_auth_service.dart` grava `denied_totp_replay`) → `auth.loginStaff` com TOTP → `admin.scheduleNotice` a +70 s (o servidor exige ≥ 1 min, `noticeMinimumLeadTime`).

**Files:**
- Create: `apps/admin/tool/schedule_notice.dart`
- Create: `apps/admin/test/schedule_notice_tool_test.dart`
- Modify: `scripts/qa/e2e_stack.sh` (bloco `schedule-notice)`, linhas ~57–63)
- Modify: `scripts/qa/push_e2e.sh` (bloco `# -- aviso agendado (#46)`, linhas ~207–233)
- Delete: `backend/sinalacs_server/bin/seed_e2e_scheduled_notice.dart`

**Interfaces:**
- Consumes: `totpCode(Uint8List, DateTime)` e `base32Decode(String)` de `apps/admin/integration_test/support/totp.dart`; cliente gerado `Client` de `package:sinalacs_client/sinalacs_client.dart` (`client.auth.beginStaffTotpEnrollment/confirmStaffTotpEnrollment/loginStaff`, `client.admin.scheduleNotice`); resultado da Task 2 (o admin das fixtures é staff ativo, então o disparo envia).
- Produces:
  - `class StaffDoManifesto { matricula, senha, codigoAtivacao, microAreaId }` (todos `String`)
  - `StaffDoManifesto lerManifesto(String json)` — lança `FormatException` sem citar valores
  - `int passoTotp(DateTime instante)`
  - saída padrão: `Aviso agendado de e2e criado (id=<uuid>).` (mesmo formato que o `sed` do `push_e2e.sh` já lê); recusa → mensagem em stderr e código 2.

- [ ] **Step 1: Teste que falha**

Crie `apps/admin/test/schedule_notice_tool_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../tool/schedule_notice.dart';

void main() {
  const manifesto = '{"microAreaId":"00000000-0000-4000-8000-000000000003",'
      '"staff":{"id":"x","matricula":"ADM-E2E-1","password":"segredo-sintetico",'
      '"activationCode":"COD-SINTETICO"}}';

  test('lê matrícula, senha, código de ativação e microárea do manifesto', () {
    final s = lerManifesto(manifesto);
    expect(s.matricula, 'ADM-E2E-1');
    expect(s.senha, 'segredo-sintetico');
    expect(s.codigoAtivacao, 'COD-SINTETICO');
    expect(s.microAreaId, '00000000-0000-4000-8000-000000000003');
  });

  test('manifesto sem staff ou sem microárea: FormatException que não vaza valores', () {
    for (final ruim in [
      '{"microAreaId":"m"}',
      '{"staff":{"matricula":"a","password":"segredo-sintetico","activationCode":"c"}}',
      '{"microAreaId":"m","staff":{"matricula":"a","password":"segredo-sintetico"}}',
    ]) {
      expect(
        () => lerManifesto(ruim),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', isNot(contains('segredo')))),
      );
    }
  });

  test('passoTotp muda a cada 30 s (o login espera o passo seguinte ao da ativação)', () {
    final t0 = DateTime.utc(2026, 10, 14, 12, 0, 0);
    expect(passoTotp(t0.add(const Duration(seconds: 29))), passoTotp(t0));
    expect(passoTotp(t0.add(const Duration(seconds: 30))), passoTotp(t0) + 1);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/admin && flutter test test/schedule_notice_tool_test.dart`
Expected: FAIL — `tool/schedule_notice.dart` não existe.

- [ ] **Step 3: Implementar o tool**

Crie `apps/admin/tool/schedule_notice.dart`:

```dart
/// Agenda UM aviso comunitário pelo endpoint REAL `admin.scheduleNotice` (#46),
/// para o `push_e2e.sh` provar agendamento → laço do servidor → Gorush/FCM.
///
///   dart run tool/schedule_notice.dart <manifesto.json> [--host https://localhost/]
///
/// Entra como o staff (admin) das fixtures de e2e: ativa a MFA com o código de
/// ativação do manifesto, espera o passo TOTP seguinte (o servidor recusa o
/// mesmo código duas vezes) e entra com TOTP. Só serve à stack de e2e: as
/// fixtures são novas a cada execução. Nunca imprime senha, código, token nem o
/// texto do aviso; imprime só o id. Recusa ou falha: mensagem e código 2.
library;

import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart';

import '../integration_test/support/totp.dart';

class StaffDoManifesto {
  const StaffDoManifesto({
    required this.matricula,
    required this.senha,
    required this.codigoAtivacao,
    required this.microAreaId,
  });

  final String matricula;
  final String senha;
  final String codigoAtivacao;
  final String microAreaId;
}

/// Lê o manifesto de `seed_e2e_fixtures.dart`. O erro cita só o campo ausente.
StaffDoManifesto lerManifesto(String json) {
  final m = jsonDecode(json) as Map<String, Object?>;
  final staff = m['staff'];
  final area = m['microAreaId'];
  if (staff is! Map || area is! String) {
    throw const FormatException('manifesto sem "staff" ou "microAreaId"');
  }
  String campo(String nome) {
    final v = staff[nome];
    if (v is! String) throw FormatException('manifesto sem "staff.$nome"');
    return v;
  }

  return StaffDoManifesto(
    matricula: campo('matricula'),
    senha: campo('password'),
    codigoAtivacao: campo('activationCode'),
    microAreaId: area,
  );
}

/// Passo TOTP (RFC 6238, 30 s) do instante.
int passoTotp(DateTime instante) => instante.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

String _arg(List<String> args, String name, String fallback) {
  final index = args.indexOf('--$name');
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
}

/// A CA que assina o certificado do Traefik (a mesma do `tool/send_notice.dart` do ACS).
File _devRpcCaFile() {
  final repoRoot = Directory.fromUri(Platform.script).parent.parent.parent.parent;
  return File('${repoRoot.path}/infra/docker/traefik/runtime/certs/ca.crt');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln('uso: dart run tool/schedule_notice.dart <manifesto.json> [--host https://localhost/]');
    exitCode = 2;
    return;
  }
  final host = _arg(args, 'host', 'https://localhost/');
  if (!host.startsWith('https://')) {
    stderr.writeln('erro: o RPC é HTTPS (RNF04); recusando $host');
    exitCode = 2;
    return;
  }
  final StaffDoManifesto staff;
  try {
    staff = lerManifesto(await File(args.first).readAsString());
  } on Object catch (e) {
    stderr.writeln('erro: manifesto ilegível (${e is FormatException ? e.message : e.runtimeType})');
    exitCode = 2;
    return;
  }
  final ca = _devRpcCaFile();
  if (!await ca.exists()) {
    stderr.writeln('erro: a CA do RPC não existe em ${ca.path}. Suba a stack.');
    exitCode = 2;
    return;
  }

  final client = Client(
    host,
    securityContext: SecurityContext()..setTrustedCertificatesBytes(await ca.readAsBytes()),
  )..connectivityMonitor = null;
  try {
    final inscricao = await client.auth.beginStaffTotpEnrollment(
      matricula: staff.matricula,
      password: staff.senha,
      activationCode: staff.codigoAtivacao,
    );
    final segredo = base32Decode(inscricao.secretBase32);
    final ativacao = DateTime.now();
    await client.auth.confirmStaffTotpEnrollment(
      matricula: staff.matricula,
      password: staff.senha,
      activationCode: staff.codigoAtivacao,
      code: totpCode(segredo, ativacao),
    );
    // Anti-replay: o código do login precisa ser de um passo POSTERIOR ao da ativação.
    while (passoTotp(DateTime.now()) <= passoTotp(ativacao)) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final sessao = await client.auth.loginStaff(
      matricula: staff.matricula,
      password: staff.senha,
      totpCode: totpCode(segredo, DateTime.now()),
    );
    final id = await client.admin.scheduleNotice(
      accessToken: sessao.accessToken,
      microAreaId: staff.microAreaId,
      audience: 'everyone',
      title: 'SinalACS agendado e2e',
      message: 'Aviso agendado do Gorush',
      // O servidor exige ao menos 1 min (`noticeMinimumLeadTime`).
      scheduledFor: DateTime.now().toUtc().add(const Duration(seconds: 70)),
    );
    stdout.writeln('Aviso agendado de e2e criado (id=$id).');
  } on AdminInvalidRequestException catch (e) {
    stderr.writeln('recusado: ${e.message}');
    exitCode = 2;
  } on AlertPermissionException {
    stderr.writeln('recusado: sem permissão para agendar');
    exitCode = 2;
  } on Object catch (e) {
    // Só o tipo: a mensagem de uma exceção de auth pode ecoar a entrada.
    stderr.writeln('falhou: ${e.runtimeType}');
    exitCode = 2;
  } finally {
    client.close();
  }
}
```

Se `flutter analyze` acusar que o resultado de `loginStaff` não tem `accessToken`, confira o tipo em `backend/sinalacs_client/lib/src/protocol/client.dart` (`grep -n "loginStaff" -A12`) — `apps/admin/lib/core/auth/admin_auth_backend.dart:131` usa `result.accessToken`, então deve existir.

- [ ] **Step 4: Rodar o teste e a análise**

Run:
```bash
cd apps/admin && flutter test test/schedule_notice_tool_test.dart && flutter analyze
```
Expected: 3/3 PASS; "No issues found!".

- [ ] **Step 5: Ligar o tool no e2e e remover o seed por `INSERT`**

Em `scripts/qa/e2e_stack.sh`, substitua o bloco `schedule-notice)` inteiro por:

```bash
  schedule-notice)
    # Aviso agendado (#46) pelo endpoint REAL admin.scheduleNotice (login de staff
    # com ativação de MFA e TOTP), ~70 s à frente; o laço do servidor o dispara.
    ( cd apps/admin && dart run tool/schedule_notice.dart ../../.e2e/fixtures.json ) ;;
```

Em `scripts/qa/push_e2e.sh`, troque as quatro linhas de comentário logo abaixo de `# -- aviso agendado (#46) ---...` por:

```bash
# O aviso é agendado pelo endpoint HTTP real (apps/admin/tool/schedule_notice.dart:
# login de staff com MFA/TOTP e admin.scheduleNotice) e o laço REAL do servidor
# (NoticeDispatchLoop, 30 s) faz a reserva, o envio por Gorush/FCM e a auditoria.
# As negações por papel seguem cobertas por admin_endpoint_notices_test.dart.
```

e troque `na_bandeja 'SinalACS agendado e2e' 90` por `na_bandeja 'SinalACS agendado e2e' 150` e o comentário acima dele por `# 70 s até o vencimento + até 30 s do ciclo do laço + a entrega pelo FCM.`.

Remova o seed antigo:

```bash
git rm backend/sinalacs_server/bin/seed_e2e_scheduled_notice.dart
grep -rn "seed_e2e_scheduled_notice" --exclude-dir=.worktrees --exclude-dir=pg_data . | grep -v "docs/superpowers/plans/2026-10-14-issue-46-"
```
Expected: o `grep` não imprime nada (planos/logs antigos são histórico e ficam como estão; se `backend/CLAUDE.md` ou `PROGRESS.md` citarem o arquivo, a Task 5 os corrige).

- [ ] **Step 6: Rodar os testes herméticos dos scripts e o e2e real**

Run:
```bash
bash -n scripts/qa/e2e_stack.sh scripts/qa/push_e2e.sh
bash scripts/qa/ci_push_e2e_test.sh
./scripts/qa/ci_invariants.sh && bash scripts/qa/ci_invariants_test.sh
```
Expected: sem erro.

Depois, o e2e real (exige emulador `emulator-5554` com Play Services, `infra/docker/gorush/credentials/fcm-service-account.json` modo 600 e `apps/patient/android/app/google-services.json`; sem a chave o script sai com 3 — nesse caso **pare e avise o usuário**, não marque como verde):

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
COMPOSE_PROJECT_NAME=sinalacs ./scripts/qa/push_e2e.sh --e2e-db --negativos 2>&1 | tee /tmp/claude-push-e2e.out
```
Expected: `aviso agendado: OK` e a última linha "OK — o aviso chegou ao emulador" (saída 0). Confira também no banco de e2e, antes do `down` do script, que existe uma linha `community_notice`/`scheduled` do admin — se o script já derrubou a stack, a prova é o `granted` que ele mesmo checa. Copie para `docs/superpowers/plans/2026-10-14-issue-46-fechamento-e2e.log` **só** as linhas de status (`== ...`, `... OK`, contagens `recipients=… accepted=…`, ids de aviso); nunca tokens. Por fim: `docker compose up -d` (o e2e deixa o backend de desenvolvimento parado).

- [ ] **Step 7: Commit**

```bash
git add apps/admin/tool/schedule_notice.dart apps/admin/test/schedule_notice_tool_test.dart \
        scripts/qa/e2e_stack.sh scripts/qa/push_e2e.sh \
        docs/superpowers/plans/2026-10-14-issue-46-fechamento-e2e.log
git commit -m "test(e2e): push_e2e agenda pelo endpoint real admin.scheduleNotice (#46)"
```

---

### Task 4: Reexecutar as provas de emulador que ficaram pendentes

**Contexto.** O PROGRESS registra que os roteiros do admin editados na #46 (fallback por tooltip na barra inferior) **não** foram reexecutados contra o backend real, e que o cartão "Os termos vão mudar" só tem roteiro manual. Esta task não muda código; ela produz evidência. Se algo falhar, use superpowers:systematic-debugging, corrija numa etapa própria com teste e commit `fix(admin): ... (#46)`, e só então siga.

**Files:**
- Create: `docs/superpowers/plans/2026-10-14-issue-46-fechamento-emulador.log`

**Interfaces:**
- Consumes: stack de pé, emulador `emulator-5554`; resultado da Task 3 (stack de desenvolvimento de volta com `docker compose up -d`).
- Produces: log com o resultado de cada roteiro.

- [ ] **Step 1: Roteiros do admin contra o backend real**

Run (um por vez; cada um sobe a própria stack de e2e — leia o cabeçalho do script se pedir flag):
```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
./scripts/qa/admin_login_e2e.sh
./scripts/qa/admin_auditoria_e2e.sh
./scripts/qa/admin_acs_gestao_e2e.sh
docker compose up -d
```
Expected: cada um termina com saída 0 e "All tests passed!" (ou a mensagem de sucesso do próprio script). Registre comando, data e última linha de cada um no log.

- [ ] **Step 2: Cartão de termos no app do paciente (roteiro manual)**

Siga `docs/superpowers/plans/2026-10-14-issue-46-validacao-manual.md`, seções 1–5 (versão `2099.1`, resumo `[TEXTO PLACEHOLDER]`). Esta etapa é **manual**: peça ao usuário para executá-la, ou execute-a você no emulador se tiver como operar a UI. Registre no log: versão publicada aparece como publicada no admin; o botão Publicar ficou desabilitado antes da revisão; o cartão "Os termos vão mudar" mostra `2099.1` e a data. Ao final, descarte os dados de teste só com a concordância do usuário (`docker compose down && rm -rf pg_data/` apaga todo o banco de desenvolvimento).

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-10-14-issue-46-fechamento-emulador.log
git commit -m "docs(plano): provas de emulador do fechamento da #46"
```

---

### Task 5: Documentação, regressão final e fechamento da issue

**Files:**
- Modify: `backend/CLAUDE.md` (seção "Avisos agendados e versões dos termos")
- Modify: `PROGRESS.md` (seção "Avisos agendados e versões dos termos (#46, 2026-10-14)")
- Modify: `CLAUDE.md` (parágrafo "Since #46 ...", só se a frase sobre provas mudar)

**Interfaces:**
- Consumes: logs das Tasks 1, 3 e 4.
- Produces: issue #46 fechada; issues de acompanhamento abertas.

- [ ] **Step 1: Atualizar `backend/CLAUDE.md`**

Na seção de avisos agendados, acrescente um parágrafo:

```markdown
**Disparo reconfere o autor.** `dispatchDue` lê a autoridade ATUAL de quem agendou (`ScheduledNoticeStore.authorityOf`: `users.role` ⨝ `staff_accounts.active/ubsId`) antes de enviar. Sem conta de staff, desativado, papel fora de `coordinator`/`admin` ou coordenador cuja UBS já não é a da microárea → o aviso não sai, vai a `failed` com `noticeAuthorRevokedReason` e grava `community_notice`/`denied_author_revoked` (autor, id do aviso; `recordSafely`). Sem migração: reaproveita `failed`.
```

E, onde a seção ou o texto de e2e citar `seed_e2e_scheduled_notice.dart`, troque pela descrição do `apps/admin/tool/schedule_notice.dart` (login de staff com MFA/TOTP + `admin.scheduleNotice`).

- [ ] **Step 2: Atualizar `PROGRESS.md`**

Na seção da #46:
- em "Continua em aberto", **remova** a linha "O disparo não reconfere o autor ..." e a linha "O endpoint HTTP de agendamento não é exercitado no `push_e2e` ..."; remova "Os roteiros de emulador do admin ... **não** foram reexecutados" se a Task 4 Step 1 passou; ajuste a linha da validação manual do cartão conforme o resultado da Task 4 Step 2.
- acrescente um bloco "**Fechamento (2026-10-14)**" com: o disparo reconfere o autor (Task 2), o `push_e2e.sh --e2e-db --negativos` verde agendando pelo endpoint real (log `docs/superpowers/plans/2026-10-14-issue-46-fechamento-e2e.log`), os roteiros reexecutados (log `...-fechamento-emulador.log`) e as contagens da regressão do Step 3.
- mantenha em aberto, cada uma com o número da issue criada no Step 5: revisão jurídica do texto real; retenção/expurgo de `scheduled_notices.message`; troca manual de `consentPolicyVersion`/`legalDocumentsVersion` na vigência; segregação de funções revisão × publicação e rascunho sem editar/descartar; histórico sem paginação na UI; fuso só provado em UTC; varredura de `sending` só na partida e para instância única; **guarda "texto novo embarcado no app" perdida** — `upcoming_legal_documents_test.dart` compara com `upcomingTermsChange`, constante morta desde que a agenda passou a `terms_versions`, então o admin pode publicar uma versão cujo texto o app não embarca (o cartão aparece sem "Ler o texto novo").

- [ ] **Step 3: Regressão final**

Run:
```bash
( cd backend/sinalacs_server && dart analyze 2>&1 | tail -1 && dart test -j 1 2>&1 | tail -1 )
( cd apps/admin && flutter analyze 2>&1 | tail -1 && flutter test 2>&1 | tail -1 )
( cd apps/patient && flutter test 2>&1 | tail -1 )
./scripts/qa/ci_invariants.sh && echo ci_invariants ok
graphify update .
```
Expected: backend ≥ base + 11 verdes, sem erro/warning; admin ≥ base + 3; paciente `+259` (inalterado); `ci_invariants ok`. Anote as contagens no bloco de fechamento do `PROGRESS.md`.

- [ ] **Step 4: Commit da documentação**

```bash
git add backend/CLAUDE.md PROGRESS.md CLAUDE.md
git commit -m "docs(avisos): fechamento da #46 — autor reconferido e e2e pelo endpoint real"
```

- [ ] **Step 5: Ações no GitHub (só com confirmação explícita do usuário)**

Mostre ao usuário o texto abaixo e **pergunte** antes de rodar qualquer `gh`. Com o "sim":

1. Abrir uma issue por pendência fora do escopo (títulos sugeridos; corpo = a linha correspondente do PROGRESS + "Origem: #46"):
   - `termos: revisão jurídica do texto real antes da primeira publicação`
   - `avisos: retenção e expurgo de scheduled_notices.message (LGPD)`
   - `termos: troca de consentPolicyVersion/legalDocumentsVersion na data de vigência`
   - `termos: segregação de funções entre revisão e publicação; editar/descartar rascunho`
   - `termos: restaurar a guarda "texto novo embarcado no app" (upcomingTermsChange morta)`
   - `avisos: paginação do histórico na UI, varredura de sending em multi-instância e prova de fuso fora de UTC`
2. Comentar na #46 com: o que foi entregue (PR #60), o que este fechamento acrescentou (commits das Tasks 2–3), a evidência de cada critério de aceite (log do e2e; testes `notice_scheduling_service_test.dart`/`notice_scheduling_endpoint_test.dart`/`admin_endpoint_notices_test.dart`) e os links das issues novas.
3. Abrir o PR do branch de trabalho para `develop` (`gh pr create --base develop`), sem atribuição de IA no corpo; a #46 fecha no merge com `Closes #46` no corpo do PR.

Se o usuário preferir não abrir as issues agora, deixe as pendências só no `PROGRESS.md` e **não** feche a #46 sem a concordância dele.
