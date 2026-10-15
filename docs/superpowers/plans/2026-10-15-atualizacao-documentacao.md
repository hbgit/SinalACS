# Atualização do README e da documentação de entrada — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alinhar o `README.md` e os documentos de entrada (CONTRIBUTING, READMEs dos apps e do servidor, telas do paciente, política de segurança) com o que o código entrega em 2026-10-15.

**Architecture:** Só documentação. Cada tarefa abre com uma *verificação que falha* (um `grep` que encontra a afirmação desatualizada, ou um comando que prova o fato novo), reescreve o trecho e fecha com a mesma verificação passando mais o conferidor de links. Nenhum código de produção muda. Toda afirmação nova é conferida no código antes de entrar no texto — não copiar de `spec/validation_report.md`, que está desatualizado nos dois sentidos.

**Tech Stack:** Markdown; `rg`/`grep`; `scripts/qa/check_documentation_links.sh`; `graphify update .`.

**Spec:** não há spec de design — a fonte da verdade é o próprio repositório: `CLAUDE.md` (raiz, estado atual e o que falta), `PROGRESS.md`, `backend/CLAUDE.md`, `apps/CLAUDE.md`, `.github/workflows/ci.yml`, `scripts/dev/bootstrap_env.sh`. Quando o README e o `CLAUDE.md` divergirem, vale o `CLAUDE.md`, **depois** de conferido no código.

## Global Constraints

- Todo texto em português (regra do projeto); identificadores, comandos e caminhos ficam como estão no código.
- Nenhum dado real de paciente, credencial ou valor de `.env` em exemplo. Senhas aparecem só como nome de variável.
- Não gravar contagens de testes no README nem no CONTRIBUTING — elas apodrecem (o README diz "25 testes"; o backend hoje tem mais de mil casos). Dar o comando que mede.
- Não prometer o que não existe: deploy de produção, iOS, provisionamento de certificado de cliente por aparelho, refresh token do paciente e os demais itens da lista "Still missing" do `CLAUDE.md` continuam como pendências.
- Assinatura de release: **só o app ACS** recusa a chave de debug (`apps/acs/android/app/build.gradle.kts:181-205`, `-Psinalacs.allowDebugSigning=true`); paciente e admin ainda assinam release com a chave de debug (`apps/patient/android/app/build.gradle.kts:38`, `apps/admin/android/app/build.gradle.kts:34`).
- Fora do escopo deste plano (cada um merece o seu): `spec/validation_report.md` (tem conferidor próprio, `scripts/qa/contagem_validation_report.py`), `spec/test_plan.md`, `spec/sys_flow.md`, `spec/security_assessment.md`, `docs/showcase/`, `video/`, `backend/sinalacs_client/doc/endpoint.md` (gerado pelo Serverpod) e os `CHANGELOG.md` dos pacotes.
- Mensagens de commit em português, no estilo `docs(<área>): ...`, sem atribuição de IA.

## Review Focus

- **Leitor que segue o README num clone limpo:** a ordem dos passos precisa ser `bootstrap_env.sh` → `docker compose up --build` → `sync_dev_ca.sh` → app. Hoje "Configuração" aparece depois de "Execução local", e quem lê de cima para baixo sobe a stack sem `.env` e recebe o erro de interpolação. Coberto pela Task 2, Step 4.
- **Primeiro login no admin:** o seed cria `ADM-001` **sem código de ativação**; sem emitir um com `bin/issue_staff_activation_code.dart` o login nunca passa da MFA. O README do admin diz que "a conta ativa a verificação pela própria tela", o que omite esse passo. Coberto pela Task 4, Step 3.
- **Contagem que volta a apodrecer:** qualquer número de testes, de jobs ou de variáveis escrito à mão. Jobs e variáveis entram por nome (há guarda para os jobs em `ci_invariants.sh`); testes, só pelo comando. Coberto pelas Tasks 2 e 3 (grep final por `[0-9]+ testes`).
- **Link relativo quebrado depois da reescrita:** READMEs em `apps/*/` e `backend/*/` usam `../../`. Coberto pelo conferidor de links ao fim de toda tarefa.
- **Afirmação de segurança mais forte que a realidade:** "mTLS entregue" só vale para a stack local; "TLS no broker" é com senha + ACL + certificado de cliente na stack local; o vínculo ao Keystore foi provado só no emulador API 36. Coberto pela Task 1, Step 3 (texto conferido contra o `CLAUDE.md`).

---

## Preparação (uma vez, antes da Task 1)

- [ ] Criar o branch a partir da base das PRs (`develop`, salvo indicação do mantenedor):

```bash
git fetch origin
git switch -c docs/atualiza-readme-e-docs origin/develop
```

- [ ] Registrar a linha de base do conferidor de links (ignorando worktrees locais em `.worktrees/`, que não são versionados):

```bash
bash scripts/qa/check_documentation_links.sh 2>&1 | grep -v '\.worktrees/' ; echo "fim"
```

Esperado: nenhuma linha `link local ausente` fora de `.worktrees/`. Se aparecer alguma, anote — ela não é causada por este plano, mas deve ser corrigida na tarefa que mexe naquele arquivo.

Nas tarefas abaixo, "conferidor de links" significa exatamente esse comando.

---

### Task 1: README — estado atual, funcionalidades, estrutura e segurança

**Files:**
- Modify: `README.md:8-40` (bloco "Estado atual", "Funcionalidades atuais", "Estrutura")
- Modify: `README.md:265-271` ("Segurança e escopo")

**Interfaces:**
- Consumes: lista "Already delivered"/"Still missing" de `CLAUDE.md` (raiz).
- Produces: as seções `## Funcionalidades atuais` e `## Estrutura` com estes títulos exatos (a Task 2 insere seções entre elas e "Pré-requisitos").

- [ ] **Step 1: Verificação que falha**

```bash
rg -n 'dart:io, sem framework|login institucional demonstrativo|sincronização simulada|preparada para SQLCipher|permanecem pendentes de integração real|Integrações de produção com MQTT autenticado, identidade|^\s+tests/ ' README.md
```

Esperado: 7 ou mais linhas encontradas (todas desatualizadas: o backend é Serverpod; o login do ACS é real com TOTP; a fila sincroniza com `visits.sync`; o SQLCipher está ativo; MQTT autenticado e RBAC existem; não há diretório `tests/`).

- [ ] **Step 2: Conferir os fatos no código antes de escrever**

```bash
ls tests 2>&1 | head -1                                   # esperado: No such file or directory
ls apps backend scripts docs infra spec video
ls backend/sinalacs_server/lib/src/endpoints/
rg -n 'sqlcipher' apps/acs/pubspec.yaml apps/patient/pubspec.yaml
rg -ln 'BiometricPrompt|CryptoObject' apps/acs/android apps/acs/lib | head -3
```

Esperado: `tests/` não existe; `video/` e `scripts/` existem; os endpoints listados batem com os do `CLAUDE.md`. Se algo divergir, o texto do Step 3 segue o código, não o plano.

- [ ] **Step 3: Reescrever o bloco de estado, funcionalidades e estrutura**

Substituir `README.md` da linha `> **Estado atual:**` até o fim do bloco ```` ```text ... ``` ```` de "Estrutura" por:

````markdown
> **Estado atual:** protótipo funcional, validado localmente em stack Docker
> (PostgreSQL, Mosquitto, backend Serverpod e Traefik) e em emulador Android.
> **Não está pronto para produção:** não há deploy de produção, iOS, nem
> integração com um provedor de identidade real. A lista completa do que falta,
> com responsáveis, está em [PROGRESS.md](PROGRESS.md).

## Funcionalidades atuais

**App do paciente** (`apps/patient`)
- Login sem senha: CPF + data de nascimento + código de uso único (OTP), e
  cadastro por convite em QR Code.
- Alerta de urgência real (`alerts.createRedAlert`) com acompanhamento de
  entrega, triagem estruturada determinística e status da solicitação.
- "Meus Dados" (LGPD): exportação, histórico de consentimentos, revogação e
  pedidos de correção e exclusão; aceite dos Termos de Uso.
- Lembretes locais e recebimento de avisos à comunidade por push (Gorush + FCM).

**App do ACS** (`apps/acs`)
- Login institucional com matrícula, senha (Argon2id) e TOTP; refresh token
  rotativo guardado no Keystore e liberado por biometria; bloqueio após 30 s em
  segundo plano e `FLAG_SECURE` na janela.
- Fila de visitas priorizada por risco, restrita à microárea do ACS (RBAC),
  com mapa, territorialização e geofencing.
- Registro de visitas offline em banco local cifrado (SQLCipher), com fila por
  dono, reenvio e detecção de conflito; recebimento de alertas vermelhos por
  MQTT com TLS e confirmação (ACK).

**Backoffice** (`apps/admin`, Flutter Web e Android)
- Login de coordenador/administrador com senha e TOTP obrigatório.
- Indicadores, microáreas, alertas (com escalonamento do alerta vermelho não
  confirmado), auditoria com selo por linha, verificação da cadeia e
  exportação CSV, gestão de contas de ACS e de MFA, pedidos do titular (LGPD),
  avisos agendados e versões dos Termos.

**Backend** (`backend/`, Serverpod)
- Motor de triagem determinístico (verde, amarelo, vermelho), alerta vermelho
  idempotente por microárea publicado no broker, sincronização de visitas,
  colunas clínicas cifradas em repouso (AES-256-GCM) e trilha de auditoria
  encadeada.

Consulte [PROGRESS.md](PROGRESS.md) para o status detalhado dos milestones e
[spec/PRD_system.md](spec/PRD_system.md) para requisitos e decisões técnicas.
As telas estão documentadas em [docs/README.md](docs/README.md).

## Estrutura

```text
apps/
	acs/       Aplicativo Flutter do Agente Comunitário de Saúde
	patient/   Aplicativo Flutter do paciente
	admin/     Backoffice administrativo (Flutter Web e Android)
backend/     Workspace Dart: servidor Serverpod (sinalacs_server) e cliente gerado (sinalacs_client)
infra/       Configuração local de infraestrutura (Mosquitto, Traefik, Gorush)
scripts/     dev/ (configuração e execução local), qa/ (validação e e2e), ci/
spec/        PRD, UX, privacidade e fluxos do produto
docs/        Telas, guias operacionais e planos de implementação
video/       Roteiro e material do vídeo de apresentação
```
````

Se o Step 2 mostrou que `infra/` não contém `gorush`, retire "Gorush" da linha de `infra/`.

- [ ] **Step 4: Reescrever "Segurança e escopo"**

Substituir o parágrafo da seção `## Segurança e escopo` por:

```markdown
O projeto lida com dados de saúde. Não inclua dados reais de pacientes em
testes, logs, capturas de tela ou configurações de desenvolvimento. A
classificação de risco é determinística e não pode ser alterada manualmente,
alertas vermelhos não são descartados em silêncio e o acesso do ACS fica
restrito à própria microárea.

Autenticação, RBAC por microárea, TLS no RPC e no broker (com senha, ACL e
certificado de cliente) estão implementados **na stack local**. Ainda faltam,
entre outros: provisionamento de certificado de cliente por aparelho em
produção, refresh token para o paciente, imposição de append-only da trilha de
auditoria no banco e o deploy de produção — ver [PROGRESS.md](PROGRESS.md) e a
[política de segurança](.github/SECURITY.md).
```

- [ ] **Step 5: Verificação passa**

```bash
rg -n 'dart:io, sem framework|login institucional demonstrativo|sincronização simulada|preparada para SQLCipher|permanecem pendentes de integração real|Integrações de produção com MQTT autenticado, identidade|^\s+tests/ ' README.md ; echo "rg=$?"
```

Esperado: nenhuma linha, `rg=1`. Depois rodar o conferidor de links — nenhuma linha nova.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs(readme): atualiza estado atual, funcionalidades, estrutura e segurança"
```

---

### Task 2: README — configuração, execução, build, testes e CI

**Files:**
- Modify: `README.md` — seções `## Pré-requisitos`, `## Execução local`, `## Build`, `## Testes e análise` (inclui `### Configuração`)

**Interfaces:**
- Consumes: títulos `## Funcionalidades atuais`/`## Estrutura` da Task 1.
- Produces: seção `## Configuração` (nível 2, antes de `## Execução local`) com âncora `#configuração`, citada pelo CONTRIBUTING na Task 3.

- [ ] **Step 1: Verificação que falha**

```bash
rg -n '>=3\.3\.0|25 testes|quatro jobs|em pushes para main e pull|assina builds de release com a chave de debug|senha do Postgres,\s*$' README.md
rg -c '^## Configuração' README.md
rg -n 'apps/admin|run_admin|DEV_ADMIN_PASSWORD' README.md
```

Esperado: a primeira encontra ao menos 4 linhas; a segunda devolve nada (hoje é `### Configuração`, nível 3, dentro de "Testes"); a terceira só acha a linha da árvore de estrutura — não há instrução para rodar o admin.

- [ ] **Step 2: Conferir os fatos**

```bash
rg -n "sdk:" apps/*/pubspec.yaml backend/pubspec.yaml backend/sinalacs_server/pubspec.yaml
rg -n "flutter-version|java-version" .github/workflows/ci.yml | sort -u
./scripts/qa/ci_invariants.sh --checks-obrigatorios | python3 -c 'import json,sys; print([c["context"] for c in json.load(sys.stdin)])'
rg -n '^\s+[A-Z_]+="\$\(secret\)"' scripts/dev/bootstrap_env.sh
rg -n 'captura|--build|-d ' scripts/dev/run_acs.sh | head
```

Esperado (em 2026-10-15): apps `^3.8.0`, backend `^3.12.0`, Flutter 3.44.8; 8 checks obrigatórios + `android-e2e`; dez segredos gerados (`POSTGRES_PASSWORD`, `TEST_DATABASE_PASSWORD`, `MQTT_BACKEND_PASSWORD`, `MQTT_ACS_PASSWORD`, `JWT_SECRET`, `AUDIT_CHAIN_SECRET`, `HEALTH_DATA_ENCRYPTION_KEY`, `CPF_HASH_PEPPER`, `DEV_ACS_PASSWORD`, `DEV_ADMIN_PASSWORD`). Se algum valor diferir, use o medido nos textos abaixo.

- [ ] **Step 3: Reescrever "Pré-requisitos"**

```markdown
## Pré-requisitos

- Flutter com Dart `^3.8.0` para os três apps; a CI usa Flutter 3.44.8.
- Dart `^3.12.0` para o backend (`backend/pubspec.yaml`).
- Android SDK com API 36 e JDK 17 para gerar ou executar os apps no Android.
- Docker Engine com Docker Compose v2 para subir a stack local.
- Emulador Android ou aparelho físico, opcional para execução mobile.

As versões usadas pela CI estão em
[.github/workflows/ci.yml](.github/workflows/ci.yml).
```

- [ ] **Step 4: Mover e reescrever "Configuração" para antes de "Execução local"**

Apagar o `### Configuração` atual (de "**Antes do primeiro `docker compose up`**" até o parágrafo que termina em "piloto de deploy free-tier.") e inserir, imediatamente antes de `## Execução local`:

````markdown
## Configuração

**Antes do primeiro `docker compose up`, gere a configuração local:**

```bash
./scripts/dev/bootstrap_env.sh
```

O script cria o `.env` com segredos aleatórios desta máquina —
`POSTGRES_PASSWORD`, `TEST_DATABASE_PASSWORD`, `MQTT_BACKEND_PASSWORD`,
`MQTT_ACS_PASSWORD`, `JWT_SECRET`, `AUDIT_CHAIN_SECRET`,
`HEALTH_DATA_ENCRYPTION_KEY`, `CPF_HASH_PEPPER`, `DEV_ACS_PASSWORD` e
`DEV_ADMIN_PASSWORD` — e gera `backend/sinalacs_server/config/passwords.yaml`
(gitignored; sem ele a suíte do Serverpod morre sem imprimir nada). Os dois
arquivos ficam com `chmod 600` e nenhum entra no git. O script nunca
sobrescreve sem `--force`; rodado sem `--force` sobre um `.env` antigo, só
acrescenta as variáveis que faltam.

[.env.example](.env.example) é a referência completa das variáveis. O
`docker-compose.yml` declara cada segredo como `${VAR:?...}`: se faltar, o
Compose falha dizendo qual, em vez de subir com uma senha embutida no arquivo
versionado.

**Trocar `POSTGRES_PASSWORD` ou `HEALTH_DATA_ENCRYPTION_KEY` com um `pg_data/`
já existente quebra o ambiente:** a senha só vale na primeira inicialização do
volume e as colunas clínicas já cifradas ficam ilegíveis. Para adotar valores
novos: `docker compose down && rm -rf pg_data/`.

Configuração de servidor e banco vem de `sinalacs_server/config/*.yaml` e pode
ser sobrescrita por variáveis de ambiente (`SERVERPOD_DATABASE_HOST` e
companhia, `SERVERPOD_APPLY_MIGRATIONS`, `SERVERPOD_REDIS_ENABLED`,
`SERVERPOD_INSIGHTS_SERVER_PORT`). O MQTT tem variáveis próprias, lidas por
`sinalacs_server/lib/src/config/app_config.dart`, assim como `JWT_SECRET`,
`APP_ENV` e `ENABLE_DEV_LOGIN` (desligado por padrão). Fora de `development`, o
servidor **recusa subir** se `JWT_SECRET` estiver ausente, vazio ou igual ao
valor de desenvolvimento. Detalhes em [backend/CLAUDE.md](backend/CLAUDE.md).
````

Antes de colar o parágrafo do `--force`, confira em `scripts/dev/bootstrap_env.sh` (procure `ACRESCENTA`) que o acréscimo vale para qualquer variável ausente e não só para `DEV_ADMIN_PASSWORD`; se valer só para essa, escreva "só acrescenta `DEV_ADMIN_PASSWORD`".

- [ ] **Step 5: Acrescentar o backoffice em "Execução local"**

Depois da subseção `### Aplicativo do paciente` (antes de `## Build`), inserir:

````markdown
### Backoffice (admin)

Com a stack de pé e as CAs copiadas (`./scripts/dev/sync_dev_ca.sh`):

```bash
cd apps/admin
flutter pub get
flutter run -d chrome                 # web
flutter run -d emulator-5554          # Android; SINALACS_HOST padrão: https://10.0.2.2/
```

O seed cria o administrador `ADM-001`, com a senha de `DEV_ADMIN_PASSWORD`
(`.env`), **sem TOTP e sem código de ativação**. Antes do primeiro login, emita
um código (válido por 24 h, mostrado uma única vez):

```bash
cd backend/sinalacs_server
dart run bin/issue_staff_activation_code.dart ADM-001 --issued-by <seu-nome>
```

A ferramenta lê as variáveis `SERVERPOD_DATABASE_*`; veja
[backend/CLAUDE.md](backend/CLAUDE.md). Na tela de login, a conta usa esse
código para ativar a verificação em duas etapas.
````

Antes de colar, confira o alvo web: `ls apps/admin/web` deve existir; se não existir, remova a linha `-d chrome`. Confira também se o ACS de desenvolvimento usa `DEV_ACS_PASSWORD`: `rg -n DEV_ACS_PASSWORD docker-compose.yml backend/sinalacs_server/bin | head -3`. Se sim, acrescente ao fim de `### Aplicativo ACS`:

```markdown
O ACS de desenvolvimento entra com a senha de `DEV_ACS_PASSWORD` (`.env`); a
matrícula semeada está em `backend/sinalacs_server/` (seed de desenvolvimento).
```

E substitua a matrícula pela real, achada com `rg -n "matr|enrollment" backend/sinalacs_server/bin/*seed* | head`.

- [ ] **Step 6: Reescrever "Build de release"**

```markdown
### Build de release

O app **ACS** recusa gerar release assinada com a chave de debug: sem chave de
release configurada, `flutter build apk --release` falha. Para um teste local
consciente, `-Psinalacs.allowDebugSigning=true` libera a chave de debug — nunca
para distribuição. Os apps **paciente** e **admin** ainda assinam release com a
chave de debug. Nenhum dos três tem chave de release provisionada; veja
[docs/publicacao-google-play.md](docs/publicacao-google-play.md).
```

- [ ] **Step 7: Reescrever "Testes e análise"**

````markdown
## Testes e análise

Execute cada conjunto a partir do respectivo diretório:

```bash
cd backend && dart pub get && dart analyze
cd backend/sinalacs_server && dart test            # unitários + integração
cd backend/sinalacs_server && dart test test/unit  # só os herméticos, sem banco
cd apps/acs && flutter pub get && flutter analyze && flutter test
cd apps/patient && flutter pub get && flutter analyze && flutter test
cd apps/admin && flutter pub get && flutter analyze && flutter test
```

Os testes de integração do backend usam o harness do Serverpod e exigem o
Postgres de teste em `localhost:9090` (`sinalacs_server/config/test.yaml`). A
validação ponta a ponta contra a stack real (scripts em `scripts/qa/`,
`integration_test/` no emulador) está descrita em
[CONTRIBUTING.md](CONTRIBUTING.md) e no README de cada app.

A CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) roda em toda PR,
em pushes para `main`/`develop` e sob demanda, com nove jobs:
`workflow-lint`, `serverpod-backend`, `backend-docker-build`, `patient-app`,
`acs-app`, `admin-app`, `coverage-report`, `android-e2e` (o único que sobe um
emulador contra a stack) e `admin-android-build`. Todos menos `android-e2e`
são obrigatórios para o merge em `main` e `develop`.
````

Apagar o parágrafo antigo "O backend é um workspace Dart com dois pacotes... 25 testes..." e o "A última validação local cobriu... quatro jobs...".

- [ ] **Step 8: Verificação passa**

```bash
rg -n '>=3\.3\.0|25 testes|quatro jobs|em pushes para main e pull|assina builds de release com a chave de debug|[0-9]+ testes' README.md ; echo "rg=$?"
rg -n '^## ' README.md
```

Esperado: `rg=1`; a ordem dos títulos `##` é: Funcionalidades atuais, Estrutura, Pré-requisitos, Configuração, Execução local, Build, Testes e análise, Deploy, Segurança e escopo, Licença. Rodar o conferidor de links — nenhuma linha nova. Conferir também que a lista de nove jobs bate com a CI:

```bash
python3 - <<'EOF'
import re
readme = open("README.md").read()
ci = open(".github/workflows/ci.yml").read()
jobs_ci = set(re.findall(r"^  ([a-z0-9-]+):\s*$", ci, re.M))
bloco = readme.split("com nove jobs:")[1].split("são obrigatórios")[0]
jobs_readme = set(re.findall(r"`([a-z0-9-]+)`", bloco))
print("faltam no README:", jobs_ci - jobs_readme, "| sobram:", jobs_readme - jobs_ci)
assert jobs_ci == jobs_readme
EOF
```

Esperado: `faltam no README: set() | sobram: set()`.

- [ ] **Step 9: Commit**

```bash
git add README.md
git commit -m "docs(readme): configuração antes da execução, backoffice, release e CI com nove jobs"
```

---

### Task 3: CONTRIBUTING — piso de SDK, admin e verificação de documentação

**Files:**
- Modify: `CONTRIBUTING.md:45-50` (Pré-requisitos)
- Modify: `CONTRIBUTING.md:118-126` (execução dos apps)
- Modify: `CONTRIBUTING.md` — seção `## Pull requests` (acrescentar o conferidor de links)

**Interfaces:**
- Consumes: âncora `README.md#configuração` (Task 2).
- Produces: nada consumido por outras tarefas.

- [ ] **Step 1: Verificação que falha**

```bash
rg -n '>=3\.3\.0|Dart SDK `>=3\.8\.0` para o backend' CONTRIBUTING.md
rg -n 'check_documentation_links|apps/admin && flutter run|bootstrap_env' CONTRIBUTING.md
```

Esperado: a primeira acha 2 linhas (admin já é `^3.8.0`; backend é `^3.12.0`); a segunda não acha nada.

- [ ] **Step 2: Corrigir os pré-requisitos**

Trocar as duas primeiras linhas da lista de `## Pré-requisitos` por:

```markdown
- Flutter SDK com Dart `^3.8.0` para os três aplicativos (`apps/patient`, `apps/acs`, `apps/admin`); a CI usa Flutter 3.44.8.
- Dart SDK `^3.12.0` para o backend.
```

- [ ] **Step 3: Configuração antes da stack**

Em `## Ambiente local`, antes de "Para iniciar PostgreSQL...", inserir:

````markdown
Num clone limpo, gere antes a configuração local (detalhes em
[README.md](README.md#configuração)):

```bash
./scripts/dev/bootstrap_env.sh
```
````

- [ ] **Step 4: Admin na execução dos apps**

No bloco de "Para executar um aplicativo em dispositivo ou emulador", acrescentar a linha do admin:

```bash
./scripts/dev/run_acs.sh      # ACS: preenche os dart-defines a partir do .env
cd apps/patient && flutter run
cd apps/admin && flutter run  # exige código de ativação no primeiro login; ver apps/admin/README.md
```

- [ ] **Step 5: Conferidor de links na seção de PR**

Na seção `## Pull requests`, acrescentar ao fim:

````markdown
Ao alterar documentação, confira os links relativos:

```bash
bash scripts/qa/check_documentation_links.sh
```

O script lista cada `link local ausente` e sai com 1 se houver algum. Evite
gravar contagens de testes nos documentos: elas envelhecem a cada PR.
````

- [ ] **Step 6: Verificação passa**

```bash
rg -n '>=3\.3\.0' CONTRIBUTING.md ; echo "rg=$?"
rg -c 'check_documentation_links|apps/admin && flutter run|bootstrap_env' CONTRIBUTING.md
```

Esperado: `rg=1`; a contagem é 3 ou mais. Rodar o conferidor de links — a âncora `#configuração` é cortada pelo script (ele remove `#...`), então confira à mão que `README.md` tem `## Configuração`.

- [ ] **Step 7: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs(contributing): piso de SDK, admin, bootstrap e conferidor de links"
```

---

### Task 4: READMEs dos apps e do servidor

**Files:**
- Modify: `apps/acs/README.md`
- Modify: `apps/patient/README.md`
- Modify: `apps/admin/README.md` (parágrafo "O login é real...")
- Modify: `backend/sinalacs_server/README.md` (hoje é o modelo do Serverpod e manda subir Redis)

**Interfaces:**
- Consumes: seção `### Backoffice (admin)` do README raiz (Task 2) — o README do admin deve dizer o mesmo sobre o código de ativação.
- Produces: nada.

- [ ] **Step 1: Verificação que falha**

```bash
rg -n 'demonstrativo|autenticação simples' apps/acs/README.md apps/patient/README.md
rg -n 'issue_staff_activation_code|código de ativação' apps/admin/README.md
rg -n 'Redis|starting point' backend/sinalacs_server/README.md
```

Esperado: a primeira e a terceira encontram linhas; a segunda não encontra nada.

- [ ] **Step 2: ACS e paciente**

`apps/acs/README.md`, trocar o parágrafo de descrição por:

```markdown
Aplicativo Flutter do Agente Comunitário de Saúde: login institucional com matrícula, senha e TOTP (refresh token no Keystore, liberado por biometria), fila de visitas priorizada por risco e restrita à microárea, mapa e territorialização, registro de visitas offline em banco cifrado com sincronização, e alertas vermelhos por MQTT com confirmação.

Execute com `./scripts/dev/run_acs.sh` a partir da raiz (não com `flutter run` direto): o script injeta a senha do broker, que não tem valor padrão.
```

`apps/patient/README.md`, trocar o parágrafo de descrição por:

```markdown
Aplicativo Flutter do paciente: login sem senha (CPF + data de nascimento + OTP) e cadastro por convite em QR Code, alerta de urgência, triagem estruturada com classificação de risco determinística, acompanhamento da solicitação, lembretes, avisos por push e "Meus Dados" (direitos do titular, LGPD).
```

Manter o segundo parágrafo (links) de ambos como está.

- [ ] **Step 3: Admin — código de ativação**

Em `apps/admin/README.md`, no parágrafo "O login é real e **sem atalho de desenvolvimento**...", trocar a frase "No primeiro acesso a conta ativa a verificação em duas etapas pela própria tela." por:

```markdown
O seed cria `ADM-001` **sem código de ativação**: antes do primeiro login, emita um com `dart run bin/issue_staff_activation_code.dart ADM-001 --issued-by <seu-nome>` em `backend/sinalacs_server` (válido por 24 h, mostrado uma única vez); com ele, a conta ativa a verificação em duas etapas pela própria tela. Depois, um administrador redefine a MFA de outro membro da equipe pela seção Equipe, que emite o código novo.
```

Confirme antes que o caminho existe: `ls backend/sinalacs_server/bin/issue_staff_activation_code.dart`.

- [ ] **Step 4: README do servidor**

Substituir todo o conteúdo de `backend/sinalacs_server/README.md` por:

````markdown
# sinalacs_server

Servidor Serverpod do SinalACS: endpoints RPC (`lib/src/endpoints/`), regras de
domínio, migrações (`migrations/`) e ferramentas de operador (`bin/`).

Não suba este servidor sozinho com o `docker compose` deste diretório: a stack
de desenvolvimento (PostgreSQL, Mosquitto, Traefik e os seeds) fica na raiz do
repositório.

```bash
./scripts/dev/bootstrap_env.sh   # na raiz, uma vez
docker compose up --build        # na raiz
```

Testes:

```bash
dart test             # unitários + integração (Postgres de teste em localhost:9090)
dart test test/unit   # só os herméticos
```

Comandos do Serverpod, migrações, segredos, seeds e camadas de `lib/src/`:
[backend/CLAUDE.md](../CLAUDE.md). Visão geral e configuração:
[README.md](../../README.md).
````

Antes, confira se existe `docker-compose.yml` dentro de `backend/sinalacs_server/`: `ls backend/sinalacs_server/docker-compose.yml`. Se **não** existir, retire a frase "com o `docker compose` deste diretório".

- [ ] **Step 5: Verificação passa**

```bash
rg -n 'demonstrativo|autenticação simples' apps/acs/README.md apps/patient/README.md ; echo "rg1=$?"
rg -c 'issue_staff_activation_code' apps/admin/README.md
rg -n 'Redis|starting point' backend/sinalacs_server/README.md ; echo "rg3=$?"
```

Esperado: `rg1=1`, contagem `1`, `rg3=1`. Rodar o conferidor de links — os `../../` e `../CLAUDE.md` precisam resolver.

- [ ] **Step 6: Commit**

```bash
git add apps/acs/README.md apps/patient/README.md apps/admin/README.md backend/sinalacs_server/README.md
git commit -m "docs(apps): descrições atuais dos apps, código de ativação do admin e README do servidor"
```

---

### Task 5: Telas do paciente, índice de docs e política de segurança

**Files:**
- Modify: `docs/telas-paciente.md` (seções Autenticação, Alerta, Acompanhamento, Lembretes; última edição 2026-09-21)
- Modify: `docs/README.md` (índice)
- Modify: `.github/SECURITY.md:23-26` (escopo)

**Interfaces:**
- Consumes: nada.
- Produces: nada.

- [ ] **Step 1: Verificação que falha**

```bash
rg -n 'ainda dependem de integração|estado local demonstrativo|Os dados são locais e sintéticos|ainda não foram integrados' docs/telas-paciente.md
rg -n 'apps/admin' .github/SECURITY.md
```

Esperado: a primeira acha 4 linhas; a segunda nada (o admin está fora do escopo declarado).

- [ ] **Step 2: Conferir cada comportamento no código antes de reescrever**

```bash
rg -n 'requestOtp|verifyOtp' apps/patient/lib | head -3          # OTP real
rg -ln 'mobile_scanner|QrScan|qr' apps/patient/lib | head -3     # QR
rg -n 'createRedAlert|statusFor' apps/patient/lib | head -3      # alerta + status reais
rg -n 'class LocalNotificationsReminderScheduler' apps/patient/lib
rg -n 'getCurrentPosition|geolocator' apps/patient/lib | head -3 # localização no alerta
rg -n 'TermsChange|avisos|notice' apps/patient/lib/app | head -5 # cartão de mudança de termos / avisos
```

Para cada item que **não** for encontrado, a frase correspondente do Step 3 sai do texto (não escreva que algo existe sem achar o código). Anote o resultado de cada linha no commit message.

- [ ] **Step 3: Reescrever as quatro seções**

`## Autenticação inclusiva`:

```markdown
A tela inicial pede CPF e data de nascimento e envia um código de uso único (OTP); não há senha. O primeiro acesso também pode vir de um convite em QR Code gerado pela equipe, que leva ao cadastro e ao aceite obrigatório dos Termos de Uso e da Política de Privacidade. Quem entra por OTP sem ter aceitado a versão vigente dos Termos recebe um aviso para aceitar — um aviso, não um bloqueio: o alerta de urgência nunca espera pelo aceite.
```

`## Alerta de urgência` — manter a imagem e trocar o parágrafo por:

```markdown
O botão circular de emergência pede confirmação e então cria um alerta vermelho real no backend (`alerts.createRedAlert`), idempotente, publicado para o ACS da microárea. A tela acompanha a entrega até a confirmação do ACS (`alerts.statusFor`). A localização entra no alerta quando a pessoa a autoriza.
```

`## Acompanhamento de solicitação`:

```markdown
Apresenta a linha do tempo `Enviado`, `Visualizado`, `Em análise` e `Agendado`, com o risco classificado, a partir do estado da solicitação no backend.
```

`## Lembretes`:

```markdown
Lista lembretes de medicamentos e de rotina, com controles de ativação; cada lembrete ativo agenda uma notificação local do sistema. Avisos à comunidade enviados pela equipe chegam por push (Gorush + FCM).
```

Se o Step 2 mostrou que a linha do tempo de status ainda é sintética no app, mantenha "Os dados são locais e sintéticos." e não use o novo texto da seção Acompanhamento.

- [ ] **Step 4: Índice de docs**

Em `docs/README.md`, acrescentar à lista, depois de "Publicação na Google Play":

```markdown
- [Auditoria da CI (2026-09-28)](ci-audit/2026-09-28-avaliacao-ci-develop.md)
- [Apresentação (showcase)](showcase/slides.md)
```

E trocar a frase "As capturas de tela usam dados sintéticos e representam o estado atual de protótipo das interfaces Flutter." por:

```markdown
As capturas de tela usam dados sintéticos e podem estar defasadas em relação às telas atuais; a data de cada captura é a do commit que a adicionou.
```

- [ ] **Step 5: Escopo da política de segurança**

Em `.github/SECURITY.md`, trocar `- Aplicativos em \`apps/acs\` e \`apps/patient\`.` por:

```markdown
- Aplicativos em `apps/acs`, `apps/patient` e `apps/admin` (backoffice).
```

e acrescentar, depois da linha da infraestrutura:

```markdown
- Scripts de desenvolvimento, validação e CI sob `scripts/`.
```

- [ ] **Step 6: Verificação passa**

```bash
rg -n 'ainda dependem de integração|estado local demonstrativo|ainda não foram integrados' docs/telas-paciente.md ; echo "rg=$?"
rg -c 'apps/admin' .github/SECURITY.md
```

Esperado: `rg=1` e contagem `1`. Rodar o conferidor de links — `ci-audit/...` e `showcase/slides.md` precisam resolver.

- [ ] **Step 7: Commit**

```bash
git add docs/telas-paciente.md docs/README.md .github/SECURITY.md
git commit -m "docs: telas do paciente, índice de docs e escopo da política de segurança"
```

---

### Task 6: Varredura final e grafo

**Files:**
- Modify: nenhum, salvo correções que a varredura achar.

- [ ] **Step 1: Varredura de frases que envelhecem**

```bash
rg -n '[0-9]+ testes|quatro jobs|dart:io, sem framework|demonstrativo|ainda não (está|estão) conectad' README.md CONTRIBUTING.md apps/*/README.md backend/sinalacs_server/README.md docs/README.md docs/telas-*.md .github/SECURITY.md ; echo "rg=$?"
```

Esperado: `rg=1`. Qualquer linha encontrada: conferir no código e corrigir no arquivo, com um commit `docs: ...` próprio.

- [ ] **Step 2: Conferidor de links completo**

```bash
bash scripts/qa/check_documentation_links.sh 2>&1 | grep -v '\.worktrees/' ; echo "fim"
```

Esperado: nenhuma linha `link local ausente`.

- [ ] **Step 3: Diff só de documentação**

```bash
git diff --stat origin/develop...HEAD
```

Esperado: só arquivos `.md` (incluindo este plano, se ele for versionado no branch).

- [ ] **Step 4: Atualizar o grafo**

```bash
graphify update .
```

Esperado: termina sem erro. Se `graphify-out/` for versionado e mudar, commitar com `docs(graphify): atualiza o grafo após a revisão da documentação`; se for gitignored, nada a commitar.

- [ ] **Step 5: PR**

Abrir a PR contra `develop` com título `docs: atualiza README e documentação de entrada ao estado de 2026-10-15`, descrevendo em tópicos o que mudou por arquivo e listando os itens fora de escopo da seção Global Constraints. Sem atribuição de IA no corpo.
