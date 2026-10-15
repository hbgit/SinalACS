# Minors adiados da issue #39 — verificação e fechamento — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar os cinco itens adiados na revisão da issue #39 (login real do backoffice), depois de confirmar no código que cada um ainda está aberto.

**Architecture:** Cada item é uma mudança pequena e independente, na ordem: teste de endpoint (só teste), auditoria com audiência (backend), cabeçalho do admin (app), política de bloqueio (decisão + teste + doc), captura de tela (emulador + doc). Cada tarefa começa por um passo de **verificação** que confirma o estado atual; se o item já estiver fechado, a tarefa termina ali.

**Tech Stack:** Dart/Serverpod 3.4 (backend), Flutter (apps/admin), Postgres de teste (`sinalacs-postgres-test`), emulador Android `emulator-5554`.

**Spec:** `docs/superpowers/plans/2026-10-06-admin-autenticacao-real.md` (plano da #39), `spec/lgpd_design.md` (trilha de auditoria), `spec/ux_accessibility_assessment.md`.

## Resultado da verificação inicial (2026-10-06, branch `fix/app_admin` @ `8b077be`)

Feita com `graphify query` para localizar os arquivos e leitura direta do código. **Os cinco pontos continuam abertos:**

| # | Ponto | Evidência |
|---|---|---|
| 1 | Auditoria sem audiência | `institutional_auth_service.dart:476-483`: `_recordAudit` grava `actionType: 'login'`, `resourceType: 'session'` para ACS e staff. |
| 2 | Bloqueio compartilhado | Mesma política para as duas audiências: `maxFailedAttempts = 5`, `lockDuration = 15 min`, dobra por rodada (`institutional_auth_service.dart:175-188`). **Achado:** o contador mora em `user_credentials`, uma linha por usuário (`orm_acs_credential_store.dart:236-248`), então **não é compartilhado entre contas** — só a política é a mesma. O item estava mal descrito. |
| 3 | Sem teste de endpoint | `beginStaffTotpEnrollment`/`confirmStaffTotpEnrollment` só aparecem em `endpoint_auth_posture_test.dart` e no `serverpod_test_tools.dart` gerado. |
| 4 | Cabeçalho fixo | `apps/admin/lib/app/app.dart:132`: `AdminHeader('Backoffice • admin.dev', ...)`; `session` já está disponível no `AdminHomeShell`. |
| 5 | Captura antiga | `docs/telas-admin.md:11` aponta `screenshots/admin/01-login.png` (de 2026-09-15) e a linha 13 admite que não foi recapturada. |

## Global Constraints

- Texto de UI, comentários e mensagens de erro em português.
- Nada de `serverpod`-gerado editado à mão; esta mudança não altera modelos, então não há migração nem `serverpod generate`.
- Dado de teste sintético; senha e segredo nunca versionados.
- Sem atribuições de IA em commits (regra do repositório).
- Alvos de toque ≥ 48×52 dp e contraste pelos tokens `*OnSurface` do admin (`apps/CLAUDE.md`).
- Não rodar `docker compose down`, nem tocar em `pg_data/`; o emulador `emulator-5554` pode ser usado, o E2E que recria os containers de dev **não** faz parte deste plano.

## Review Focus

1. Consumidores que filtram `audit_logs` por `resourceType == 'session'` (tela de Auditoria do admin, seed, testes): mudar o valor para o staff não pode esconder as linhas de ACS nem as de staff (Tarefa 2).
2. `session.role` com valor inesperado no cabeçalho: não pode lançar nem mostrar texto cru; cai num rótulo genérico (Tarefa 3).
3. Cabeçalho a 200% de fonte e 320 dp com o rótulo novo, mais longo que "admin.dev": não pode estourar (Tarefa 3).
4. `confirmStaffTotpEnrollment` com código errado: conta tentativa e não ativa a MFA; com a conta bloqueada, nenhuma resposta distingue "bloqueada" de "senha errada" antes de a senha conferir (Tarefa 1).
5. Captura nova do login não pode conter dado real nem segredo (só campos vazios) (Tarefa 5).

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `backend/sinalacs_server/test/integration/staff_login_test.dart` (mod.) | Testes de endpoint de ativação de MFA do staff (T1) |
| `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart` (mod.) | `_recordAudit` com recurso por audiência (T2) |
| `backend/sinalacs_server/test/unit/institutional_auth_staff_test.dart` (mod.), `RecordingAudit` em `test/support` (mod.) | Asserção do recurso gravado (T2) |
| `apps/admin/lib/app/app.dart` (mod.), `apps/admin/test/admin_header_test.dart` (mod.) | Cabeçalho com o papel da sessão (T3) |
| `backend/CLAUDE.md`, `spec/lgpd_design.md` (mod., só se a política mudar) | Política de bloqueio por audiência (T4) |
| `docs/screenshots/admin/01-login.png`, `docs/telas-admin.md` (mod.) | Captura e texto do login (T5) |

---

### Task 1: Teste de endpoint para `begin`/`confirmStaffTotpEnrollment`

**Files:**
- Modify: `backend/sinalacs_server/test/integration/staff_login_test.dart`

**Interfaces:**
- Consumes: `endpoints.auth.beginStaffTotpEnrollment(sessionBuilder, matricula:, password:)` → `TotpEnrollmentStart` (campos `secretBase32`, `otpauthUri`); `endpoints.auth.confirmStaffTotpEnrollment(sessionBuilder, matricula:, password:, code:)`; helpers e fixtures já definidos no arquivo (`_adminId`, `_adminMatricula`, `_senha`, e o helper que insere admin sem MFA — leia as linhas 30-120 do arquivo e use o mesmo `withServerpod`/`sessionBuilder` dos testes de `loginStaff`).

- [ ] **Step 0: Verificar que o item está aberto**

Run: `cd backend/sinalacs_server && grep -n "beginStaffTotpEnrollment\|confirmStaffTotpEnrollment" test/integration/staff_login_test.dart`
Expected: sem saída (aberto). Se houver saída, ler os testes: se já cobrem os casos abaixo, encerrar a tarefa.

- [ ] **Step 1: Escrever os testes que falham**

Dentro do grupo existente de `withServerpod`, acrescente (ajuste só os nomes dos helpers ao que o arquivo já usa; o corpo de cada teste é este):

```dart
group('ativação de MFA do staff pelo endpoint', () {
  test('begin devolve segredo e URI otpauth e não ativa a MFA', () async {
    await _inserirAdminSemMfa(session);

    final inicio = await endpoints.auth.beginStaffTotpEnrollment(
      sessionBuilder,
      matricula: _adminMatricula,
      password: _senha,
    );

    expect(inicio.secretBase32, isNotEmpty);
    expect(inicio.otpauthUri, startsWith('otpauth://totp/'));
    final cred = await UserCredential.db.findFirstRow(
      session,
      where: (t) => t.userId.equals(UuidValue.fromString(_adminId)),
    );
    expect(cred!.totpSecretEncrypted, isNotNull, reason: 'segredo pendente gravado');
    expect(cred.totpEnabledAt, isNull, reason: 'MFA só vale depois do confirm');
  });

  test('confirm com código certo ativa; depois disso loginStaff exige o código', () async {
    await _inserirAdminSemMfa(session);
    final inicio = await endpoints.auth.beginStaffTotpEnrollment(
      sessionBuilder, matricula: _adminMatricula, password: _senha);
    final agora = DateTime.now().toUtc();
    final codigo = Totp.codeAt(base32Decode(inicio.secretBase32), agora); // helper de TOTP usado em institutional_mfa_test.dart

    await endpoints.auth.confirmStaffTotpEnrollment(
      sessionBuilder, matricula: _adminMatricula, password: _senha, code: codigo);

    expect(
      () => endpoints.auth.loginStaff(sessionBuilder, matricula: _adminMatricula, password: _senha),
      throwsA(isA<MfaRequiredException>()),
    );
  });

  test('confirm com código errado não ativa a MFA e conta uma tentativa', () async {
    await _inserirAdminSemMfa(session);
    await endpoints.auth.beginStaffTotpEnrollment(
      sessionBuilder, matricula: _adminMatricula, password: _senha);

    await expectLater(
      endpoints.auth.confirmStaffTotpEnrollment(
        sessionBuilder, matricula: _adminMatricula, password: _senha, code: '000000'),
      throwsA(isA<AuthenticationFailedException>()),
    );

    final cred = await UserCredential.db.findFirstRow(
      session, where: (t) => t.userId.equals(UuidValue.fromString(_adminId)));
    expect(cred!.totpEnabledAt, isNull);
    expect(cred.failedAttempts, 1);
  });

  test('begin com senha errada é recusado com a mensagem genérica', () async {
    await _inserirAdminSemMfa(session);
    await expectLater(
      endpoints.auth.beginStaffTotpEnrollment(
        sessionBuilder, matricula: _adminMatricula, password: 'senha-errada'),
      throwsA(isA<AuthenticationFailedException>()
          .having((e) => e.message, 'message', 'Matrícula ou senha inválidos.')),
    );
  });

  test('begin com matrícula de ACS é recusado como matrícula inexistente', () async {
    await _inserirAcsComCredencial(session); // helper já usado pelos testes de cruzamento deste arquivo
    await expectLater(
      endpoints.auth.beginStaffTotpEnrollment(
        sessionBuilder, matricula: _acsMatricula, password: _senha),
      throwsA(isA<AuthenticationFailedException>()
          .having((e) => e.message, 'message', 'Matrícula ou senha inválidos.')),
    );
  });
});
```

`Totp.codeAt`/`base32Decode`/`_inserirAdminSemMfa`/`_inserirAcsComCredencial` são nomes de referência: use os que `institutional_mfa_test.dart` e este arquivo realmente definem (se o gerador de código TOTP tiver outro nome, use-o; se não houver helper para o admin sem MFA, extraia-o do setup dos testes de `loginStaff`, sem duplicar).

- [ ] **Step 2: Rodar e conferir**

Run: `cd backend/sinalacs_server && dart test test/integration/staff_login_test.dart`
Expected: os testes novos **passam de primeira** — o código já existe (Tarefa 3 da #39); o valor desta tarefa é a cobertura. Para provar que não são vácuos, faça uma mutação temporária em `auth_endpoint.dart` (`beginStaffTotpEnrollment` chamando `institutionalAuthServiceFor` em vez de `staffAuthServiceFor`): os testes 1, 4 e 5 devem falhar. Reverta a mutação (`git checkout -- lib`) e registre o resultado no commit.

- [ ] **Step 3: Commit**

```bash
git add backend/sinalacs_server/test/integration/staff_login_test.dart
git commit -m "test(backend): endpoint de ativação de MFA do staff (begin/confirm) contra Postgres (#39)"
```

---

### Task 2: Auditoria que distingue a audiência

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart:476-483`
- Modify: `backend/sinalacs_server/test/support/` (o `RecordingAudit` usado em `institutional_auth_staff_test.dart`; guarde também `resourceTypes`)
- Test: `backend/sinalacs_server/test/unit/institutional_auth_staff_test.dart`, `test/unit/institutional_auth_mfa_test.dart`

**Interfaces:**
- Produces: eventos de login gravam `resourceType: 'session'` para ACS (inalterado) e `'staff_session'` para staff. `actionType` continua `'login'`.

- [ ] **Step 0: Verificar que o item está aberto e achar consumidores do valor**

Run: `cd /home/rock/Documents/Dev/APPs/SinalACS && grep -rn "'session'" backend/sinalacs_server/lib backend/sinalacs_server/test apps/admin/lib apps/admin/test | grep -v generated`
Expected: `institutional_auth_service.dart` e testes. Anote **todo consumidor que filtre ou espere** `'session'` (tela de Auditoria do admin só exibe o texto; confirme). Se algum filtro existir, ele entra nesta tarefa.

- [ ] **Step 1: Escrever o teste que falha** (em `institutional_auth_staff_test.dart`)

```dart
test('eventos de login do staff gravam o recurso staff_session', () async {
  final m = await _montar(/* mesmos argumentos do teste 'granted' do staff */);
  await m.servico.login(matricula: 'ADM-001', password: _senha, totpCode: _codigoAtual());
  expect(m.audit.resourceTypes, everyElement('staff_session'));
  expect(m.audit.results, contains('granted'));
});

test('eventos de login do ACS continuam gravando o recurso session', () async {
  // mesmo cenário de login ACS bem-sucedido já existente em institutional_auth_mfa_test.dart
  expect(m.audit.resourceTypes, everyElement('session'));
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/institutional_auth_staff_test.dart`
Expected: FAIL (`resourceTypes` não existe / valor `session`).

- [ ] **Step 3: Implementar**

`RecordingAudit`: acrescente `List<String> get resourceTypes => events.map((e) => e.resourceType).toList();` (use o campo de eventos que a classe já guarda).

`institutional_auth_service.dart`:

```dart
  /// Distingue a audiência na trilha: revisar a atividade do backoffice não
  /// pode exigir juntar `userId` com `staff_accounts` à mão.
  String get _recursoDeAuditoria =>
      audience == CredentialAudience.staff ? 'staff_session' : 'session';

  Future<void> _recordAudit(String userId, String result) => audit.recordSafely(
    AuditEvent(
      userId: userId,
      actionType: 'login',
      resourceType: _recursoDeAuditoria,
      result: result,
    ),
  );
```

- [ ] **Step 4: Rodar tudo do backend**

Run: `dart test test/unit && dart test test/integration/staff_login_test.dart test/integration/institutional_login_test.dart test/integration/institutional_mfa_test.dart`
Expected: PASS. Qualquer teste existente que espere `'session'` para o staff é atualizado aqui (e só ele).

- [ ] **Step 5: Documentar e commitar**

`backend/CLAUDE.md`: troque a frase "audit rows do not yet distinguish audience" (seção do staff) por "o login do staff grava `resourceType: 'staff_session'`; o do ACS, `'session'`". Atualize `spec/lgpd_data_audit.md` só se ele enumerar valores de `resourceType`.

```bash
git add backend CLAUDE.md
git commit -m "feat(backend): auditoria de login distingue staff (staff_session) de ACS (session) (#39)"
```

---

### Task 3: Cabeçalho do admin mostra o papel da sessão

**Files:**
- Modify: `apps/admin/lib/app/app.dart:132` (e `AdminSession` só se faltar um getter)
- Test: `apps/admin/test/admin_header_test.dart`, `apps/admin/test/text_scale_test.dart`

**Interfaces:**
- Consumes: `AdminSession.role` (`'coordinator'` | `'admin'`), `widget.session` no `AdminHomeShell`.
- Produces: função de topo `String adminRoleLabel(String role)` em `app.dart` → `'Administrador'`, `'Coordenador'`, ou `'Equipe'` para qualquer outro valor.

- [ ] **Step 0: Verificar que o item está aberto**

Run: `cd /home/rock/Documents/Dev/APPs/SinalACS && grep -n "admin.dev" apps/admin/lib/app/app.dart`
Expected: linha 132. Sem saída = fechado; encerrar.

- [ ] **Step 1: Escrever os testes que falham** (em `admin_header_test.dart`, mesmo estilo dos testes existentes e `FakeAdminAuth`)

```dart
test('adminRoleLabel traduz os papéis e cai num rótulo genérico', () {
  expect(adminRoleLabel('admin'), 'Administrador');
  expect(adminRoleLabel('coordinator'), 'Coordenador');
  expect(adminRoleLabel('qualquer-coisa'), 'Equipe');
});

testWidgets('o cabeçalho mostra o papel da sessão e não "admin.dev"', (tester) async {
  await entrarComCredenciais(tester, /* FakeAdminAuth com papel admin */);
  expect(find.textContaining('Administrador'), findsWidgets);
  expect(find.textContaining('admin.dev'), findsNothing);
});

testWidgets('sessão de coordenador mostra "Coordenador"', (tester) async {
  await entrarComCredenciais(tester, /* FakeAdminAuth com papel coordinator */);
  expect(find.textContaining('Coordenador'), findsWidgets);
});
```

Se `FakeAdminAuth` não permite escolher o papel, acrescente o campo público `String role = 'admin'` nele (em `test/support/fake_admin_auth.dart`) e use-o no `AdminSession` que devolve.

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/admin && flutter test test/admin_header_test.dart`
Expected: FAIL (`adminRoleLabel` indefinido).

- [ ] **Step 3: Implementar**

Em `app.dart`:

```dart
/// Rótulo do papel para o cabeçalho. Valor desconhecido não quebra a tela nem
/// aparece cru: o token só chega aqui com papel de staff, mas o cabeçalho não
/// deve depender disso.
String adminRoleLabel(String role) => switch (role) {
      'admin' => 'Administrador',
      'coordinator' => 'Coordenador',
      _ => 'Equipe',
    };
```

e na linha 132: `AdminHeader('Backoffice • ${adminRoleLabel(widget.session.role)}', 'Painel administrativo', height: adminHeaderHeight(context))`. Não exibir `userId` (é um UUID sem valor para quem lê e vai parar em captura de tela).

- [ ] **Step 4: Rodar a suíte do admin, incluindo fonte grande**

Run: `cd apps/admin && flutter analyze && flutter test`
Expected: PASS. Confirme que `text_scale_test.dart` e `admin_header_test.dart` cobrem o painel a 200% e 320 dp com o rótulo novo (o de "Administrador" é mais longo que "admin.dev"); se não cobrirem, acrescente um caso no mesmo estilo dos existentes. Nenhum teste existente pode ter asserção afrouxada.

- [ ] **Step 5: Commit**

```bash
git add apps/admin
git commit -m "feat(admin): cabeçalho mostra o papel da sessão em vez de admin.dev fixo (#39)"
```

---

### Task 4: Política de bloqueio do staff — decidir, provar e documentar

**Files:**
- Test: `backend/sinalacs_server/test/integration/staff_login_test.dart`
- Modify: `backend/CLAUDE.md` (e `institutional_auth_service.dart` **somente** se o usuário escolher política diferente)

**Interfaces:**
- Consumes: `InstitutionalAuthService.maxFailedAttempts`, `lockDuration`, `lockDurationFor(streak)`.

- [ ] **Step 0: Confirmar o achado e pedir a decisão**

A verificação mostrou que o contador **não** é compartilhado: é por linha de `user_credentials`, e staff e ACS são usuários distintos. O que existe é a **mesma política**. Antes de codar, pergunte ao usuário (AskUserQuestion): manter a mesma política para as duas audiências (recomendado: já é o mais seguro razoável, 5 tentativas e 15 min dobrando até 24 h) **ou** endurecer o staff (por exemplo 3 tentativas). Sem resposta, siga com "manter".

- [ ] **Step 1: Teste que prova a independência dos contadores** (decisão "manter")

```dart
test('falhas de um ACS não bloqueiam o staff e vice-versa (contador por conta)', () async {
  await _inserirAdminComMfa(session);
  await _inserirAcsComCredencial(session);

  for (var i = 0; i < InstitutionalAuthService.maxFailedAttempts; i++) {
    await expectLater(
      endpoints.auth.loginInstitutional(sessionBuilder, matricula: _acsMatricula, password: 'errada'),
      throwsA(isA<AuthenticationFailedException>()),
    );
  }

  final admin = await UserCredential.db.findFirstRow(
    session, where: (t) => t.userId.equals(UuidValue.fromString(_adminId)));
  expect(admin!.failedAttempts, 0);
  expect(admin.lockedUntil, isNull);
});
```

- [ ] **Step 2: Rodar**

Run: `cd backend/sinalacs_server && dart test test/integration/staff_login_test.dart`
Expected: PASS de primeira (comportamento já existente; o teste fixa a propriedade). Mutação para provar que não é vácuo: faça temporariamente `registerFailedAttempt` atualizar todas as linhas (remova o `WHERE "userId"`) e confirme que o teste falha; reverta.

- [ ] **Step 3: Documentar**

`backend/CLAUDE.md`, seção do staff: "Staff e ACS seguem a **mesma política** de bloqueio (5 falhas, 15 min dobrando por rodada até 24 h), mas o contador é **por conta** (`user_credentials` por usuário): falhas de uma conta não afetam outra." Se o usuário escolheu endurecer o staff: implemente `maxFailedAttempts`/`lockDuration` por audiência no serviço com teste unitário próprio, em tarefa separada revisada.

- [ ] **Step 4: Commit**

```bash
git add backend
git commit -m "test(backend): contador de bloqueio é por conta; política do staff documentada (#39)"
```

---

### Task 5: Recapturar a tela de login do admin

**Files:**
- Modify: `docs/screenshots/admin/01-login.png`, `docs/telas-admin.md:11-13`

**Interfaces:** nenhuma (documentação).

- [ ] **Step 0: Verificar que o item está aberto**

Run: `cd /home/rock/Documents/Dev/APPs/SinalACS && git log -1 --format='%ad %s' --date=short -- docs/screenshots/admin/01-login.png; grep -n "não foi recapturada" docs/telas-admin.md`
Expected: data de 2026-09-15 e a frase presente (aberto).

- [ ] **Step 1: Subir o app no emulador**

Run: `export PATH="$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin:$PATH"; cd apps/admin && mkdir -p assets/certs && flutter run -d emulator-5554`
A tela de login não depende do backend; não digite credencial. Se o app não compilar por falta de `assets/certs/dev_rpc_ca.crt`, rode `./scripts/dev/sync_dev_ca.sh` (copia só a CA pública) ou deixe a pasta vazia (a conexão falha fechada, mas a tela abre).

- [ ] **Step 2: Capturar**

Run: `adb -s emulator-5554 exec-out screencap -p > docs/screenshots/admin/01-login.png`
Abra a imagem (Read) e confira: campos vazios, sem banner "ambiente de desenvolvimento", botão "Entrar", e **nenhum** dado real ou segredo. Compare o tamanho/orientação com `docs/screenshots/admin/06-android-retrato.png` para manter o padrão do documento.

- [ ] **Step 3: Atualizar o texto**

Em `docs/telas-admin.md`, remova a frase "A imagem acima é da versão anterior (formulário local) e não foi recapturada." e acrescente a data da captura. **Atenção:** as capturas `02` a `08` mostram o painel com o cabeçalho antigo "admin.dev"; depois da Tarefa 3 elas ficam desatualizadas e só podem ser refeitas com uma sessão real (depende da prova E2E pendente da #39). Registre isso numa nota curta no mesmo arquivo, sem afirmar que foram recapturadas.

- [ ] **Step 4: Verificar links e commitar**

Run: `./scripts/qa/check_documentation_links.sh; echo "exit=$?"`
Expected: `exit=0`.

```bash
git add docs/screenshots/admin/01-login.png docs/telas-admin.md
git commit -m "docs(admin): recaptura a tela de login do backoffice (#39)"
```

---

### Task 6: Fechamento

- [ ] **Step 1: Suítes completas**

Run: `cd backend/sinalacs_server && dart test; cd ../../apps/admin && flutter analyze && flutter test; cd ../.. && ./scripts/qa/ci_invariants.sh`
Expected: tudo verde.

- [ ] **Step 2: Atualizar `PROGRESS.md`** com o que foi fechado e o que segue aberto (prova E2E no emulador, capturas 02–08, ativação de TOTP por código de uso único antes da #40).

- [ ] **Step 3: `graphify update .` e commit**

```bash
graphify update .
git add PROGRESS.md
git commit -m "docs: fecha os minors adiados da #39 em PROGRESS.md"
```

---

## Auto-revisão

- **Cobertura:** os cinco pontos têm tarefa (T1 teste de endpoint, T2 auditoria, T3 cabeçalho, T4 bloqueio, T5 captura); T6 fecha. Cada tarefa abre com passo de verificação do estado atual.
- **Placeholders:** os nomes de helper marcados como "de referência" (`_inserirAdminSemMfa`, `Totp.codeAt`, `_codigoAtual`, `RecordingAudit.events`) existem sob outros nomes nos arquivos citados; o executor deve usar os reais, e o plano diz onde achá-los. Não verifiquei os nomes exatos.
- **Consistência:** `staff_session`, `adminRoleLabel`, `resourceTypes` usados igualmente nas tarefas.
- **Desvio do pedido:** o item 2 estava mal descrito (contador não é compartilhado); a T4 reflete o achado e pede decisão sobre a política em vez de "separar contadores".
- **Fora de escopo:** E2E no emulador da #39, recaptura das telas 02–08, ativação de TOTP por código de uso único (follow-up antes da #40).
