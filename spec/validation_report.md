# Relatório de Validação — Cobertura do Backend e Integração dos Apps

**Data:** 2026-09-16 · **Branch:** `fix/backend` · **Commit base:** `a9dcbc5`
**Escopo:** diagnóstico. Nenhuma correção de código foi aplicada.
**Ambiente:** Docker 29.8.0 · Flutter 3.44.8 · Dart 3.12.2 · `emulator-5554` (Android 16, API 36, x86_64)

---

## 1. Sumário executivo

**O backend está completo?** Não, mas o que existe é sólido. Os métodos RPC já
implementados funcionam, têm cobertura de teste integral — a suíte passa
inteira, e a contagem da execução que sustenta este relatório é a da §2 — e
aplicam as invariantes de negócio que prometem. O que falta são requisitos
inteiros do PRD que nunca saíram do papel — **5 dos 18 RF não têm código em
lugar nenhum** (a contagem por veredicto está no fim da §3) — e duas tabelas
modeladas e migradas que **nenhuma linha de código escreve**.

**Os apps têm integração total com o backend?** Depende do nível, e a diferença
entre os dois é o achado central deste relatório:

- **No nível RPC: sim, quase.** Paciente e ACS juntos consomem os 7 métodos.
  Nenhum endpoint está órfão. O caminho crítico (alerta vermelho → broker →
  fila do ACS) foi validado ponta a ponta em hardware real.
- **No nível de tela: não.** 14 telas exibem dado fabricado. O backoffice
  administrativo inteiro é uma casca sobre mock e sequer declara o cliente
  gerado. E o app do paciente mostra a um usuário autenticado uma solicitação
  de visita vermelha que não existe.

**Veredicto de prontidão:** o núcleo clínico de urgência está validado; o
entorno (status ao paciente, backoffice, geolocalização, escalonamento) é
protótipo visual. O sistema não deve tocar paciente real nesta forma.

---

## 2. Evidência de execução

Tudo abaixo foi executado nesta validação, com a stack local de pé e o seed aplicado.

| Bateria | Resultado |
|---|---|
| `dart analyze` (workspace backend) | **limpo**, nenhum problema |
| `dart test` (backend) | **83/83** — 69 unit + 14 integração |
| `scripts/qa/e2e.sh` — leg do paciente | **OK** — health, login, triagem red/green, alerta, idempotência |
| `scripts/qa/e2e.sh` — leg do ACS | **OK** — login, MQTT/TLS, entrega, ACK, sync de visita |
| `integration_test` paciente `-d emulator-5554` | **7/7** |
| `integration_test` ACS `-d emulator-5554` | **14/14** (inclui prova de SQLCipher em disco real) |
| `integration_test` admin `-d emulator-5554` | **4/4** (hermético — não prova integração) |
| `bin/audit_chain_check.dart` | **cadeia íntegra**, 4 linhas verificadas |
| Smoke manual nos 3 apps | executado, telas classificadas na §5 |

**Total desta execução: 108 testes automatizados passando** (83 backend + 25 no emulador).

**As contagens desta seção são o snapshot de 2026-09-16** — a `Data` deste relatório. A suíte
cresce a cada entrega e o número de hoje sai da própria execução do comando, nunca deste texto:
para citar uma contagem atual, reexecute a bateria da §9 em vez de ler estas linhas. (Medido em
2026-09-19, para dar a ordem de grandeza da diferença: o backend está em **212 testes herméticos
e 273 no total**, contra os 83 daqui.)

Observação de backlog: o `live_check` do ACS relatou **5 alertas reentregues**
ao reconectar, confirmando que a sessão persistente com QoS 1 retém e reentrega
alertas recebidos enquanto o dispositivo estava offline (INV-03).

---

## 3. Matriz de rastreabilidade RF / RNF / INV

Legenda: **`backend`** = endpoint + teste · **`backend + app`** = endpoint com
teste **e** consumido de verdade pelo app · **`app-only`** = corretamente só no
cliente · **`parcial`** = existe, mas alimentado por dado fabricado ·
**`ausente`** = sem código.

### Requisitos funcionais

| ID | Requisito | Veredicto | Evidência |
|---|---|---|---|
| RF01 | Autenticação passwordless (CPF + nasc. + OTP) | **backend + app** | `auth.requestOtp`/`verifyOtp` com CPF validado por dígito verificador, hasheado em HMAC-SHA-256 com `CPF_HASH_PEPPER` (§2.5/§2.6 de `spec/lgpd_data_audit.md`), código de 6 dígitos com TTL de 5 min, teto de 5 verificações, intervalo de 60 s e auditoria por desfecho (`otp_challenges`). **O provedor de SMS não está escolhido**: `SMS_GATEWAY=log` escreve o código no log e só é aceito em `development`. Ver `docs/superpowers/plans/2026-09-18-rf01-login-passwordless-otp.md`; lacunas em `PROGRESS.md`. |
| RF02 | Onboarding via QR Code | **ausente** | Botão presente; `app.dart:170` emite snackbar "será disponibilizada". |
| RF03 | Botão de alerta de urgência (MQTT) | **parcial** | Endpoint e entrega funcionam (validado em dispositivo). O app agora tenta ler a localização e envia somente um hash truncado; sem permissão/GPS usa `unknownLocationHash` e informa a pessoa. A precisão e o risco de reidentificação ainda exigem decisão de produto — ver L-02/L-05. |
| RF04 | Formulário de triagem estruturada | **backend** | `triage.evaluate` exige token, classifica pelo motor determinístico e grava em `triage_sessions` com auditoria. |
| RF05 | Painel de status da solicitação | **backend** | `alerts.statusFor` lê o status do alerta mais recente do paciente autenticado pelo próprio token — sem `patientId` como parâmetro, então um token só pode ler o próprio status (INV-05). A tela deixou de ser `const` e consome o endpoint (fecha L-03). |
| RF06 | Lembretes de saúde | **ausente** | `RemindersScreen` tem lista fixa; salvar descarta. Sem `flutter_local_notifications`. |
| RF07 | Login institucional (matrícula/senha) | **backend + app** | `auth.loginInstitutional` verifica a senha com Argon2id contra `user_credentials`, bloqueia após 5 tentativas por 15 min (F6) e audita cada desfecho; o app ACS envia o que a pessoa digita. A credencial nasce do seed de desenvolvimento (`bin/seed_acs_credentials.dart`, o único caminho pelo qual uma credencial passa a existir — depois dele a tabela só é escrita para contar tentativas, em `OrmAcsCredentialStore` —, e que se recusa a rodar fora de `APP_ENV=development`), então um deploy que não rode esse seed sobe **sem nenhum caminho de login**. MFA/TOTP e refresh token seguem ausentes por decisão de escopo — ver `docs/superpowers/plans/2026-09-18-rf07-login-institucional-acs.md`. |
| RF08 | Territorialização (cache da microárea) | **parcial** | `patients.listMicroArea` é real, territorializado, e a tela "Área" agora mostra o número real de pacientes (L-06 fechado). Continua parcial: a chamada é ao vivo a cada abertura/ciclo periódico, não um cache `sqflite` persistido em disco que sobrevive offline — esse é o trabalho que falta para RF08 completo. |
| RF09 | Dashboard de priorização dinâmica | **backend** | Fila real alimentada por MQTT, ordenada por risco e idade; valida rejeição de alerta de outra microárea. |
| RF10 | Mapa interativo | **parcial** | Coordenadas são **fabricadas** a partir do hash — ver L-05. |
| RF11 | Registro rápido de visitas offline-first | **backend** | `visits.sync` com dedupe por `localId`, versionamento, conflito e território. Fila SQLCipher no dispositivo. |
| RF12 | Geofencing (check-in passivo) | **ausente** | `RouteService` calcula chegada localmente, mas não há GPS em segundo plano. |
| RF13 | Escalonamento para SAMU/UBS | **ausente** | Ambos os botões são snackbars — ver L-07. |
| RF14 | Avisos segmentados (push) | **ausente** | `NoticesScreen` descarta a entrada. Sem FCM/APNs. |
| RF15 | Sincronização bidirecional | **backend** | Dispositivo → central e central → dispositivo funcionam e são testados dos dois lados: ACS (`visits.pull`) e paciente (`alerts.statusFor`, RF05). Ambos rodam automaticamente ao abrir a tela, em ciclo periódico enquanto o app está em primeiro plano (ACS, em qualquer aba) ou enquanto a tela de Status está aberta (paciente), e por botão manual. Do lado ACS, o pull continua sendo só referência somente leitura (contagem exibida na tela), sem gravar as visitas puxadas na fila offline local — persistir esse resultado como registro local segue como trabalho futuro (ver nota em `VisitPullService`), fora do escopo deste plano. |
| RF16 | Motor de triagem determinístico | **backend** | `TriageEngine`, determinismo verificado em teste de integração. INV-02 preservado. |
| RF17 | Logs de auditoria e conformidade | **backend** | `audit_logs` encadeado por HMAC; gravou `granted` e `denied_territory` nesta validação; cadeia verificada íntegra. |
| RF18 | Dark mode nativo | **app-only** | Tema único dark nos três apps, com matriz de contraste testada. |

**Contagem:** 7 `backend` · 2 `backend + app` · 1 `app-only` · 3 `parcial` · 5 `ausente`.

### Requisitos não funcionais

| ID | Requisito | Veredicto | Evidência |
|---|---|---|---|
| RNF01 | Latência MQTT < 500 ms (p95) | **não medido** | Entrega funciona; não há instrumentação de latência. |
| RNF02 | Sincronização offline > 99,5% | **não medido** | Semântica correta e testada; taxa nunca medida. |
| RNF03 | Criptografia AES-256 em repouso | **backend/app** | SQLCipher provado em dispositivo (o arquivo não contém o conteúdo em texto claro e não abre com chave errada). **No PostgreSQL não há criptografia de coluna** — `pgcrypto` previsto no PRD não foi adotado. |
| RNF04 | TLS 1.3 em todas as comunicações | **parcial** | Broker em TLS com verificação de hostname (já era) e o RPC agora atrás do Traefik com HTTPS em :443 e TLS 1.3 mínimo — a porta 8080 em texto claro deixou de ser publicada. **Continua parcial** por dois motivos, e o certificado é só o primeiro: (a) o certificado é de desenvolvimento — a folha é emitida pela CA de dev `SinalACS Dev RPC CA` e regerada no boot (auto-assinada é a CA, que é preservada entre subidas), então produção depende de `cert-manager` e de um domínio real, que este repositório não tem; (b) e **comprar o certificado não fecharia o requisito sozinho** — quem termina TLS é a borda e a última perna (proxy → processo) continua em texto claro, no piloto (Render) e também aqui, onde o `loadbalancer` do Traefik fala http com o container na 8080 (`docker-compose.yml`), então é o par `cert-manager` **+ rede privada** que fecha, como registra `backend/DEPLOY.md` em "Limitações conhecidas". Ver `docs/superpowers/plans/2026-09-18-tls-rpc-rnf04-l08.md`. |
| RNF05 | Acessibilidade WCAG AA | **app-only** | Matrizes de contraste, alvos de toque e `liveRegion` testados nos três apps. |
| RNF06 | RBAC | **parcial** | `Authorization.require` é a única regra de papel e de presença de território no token (a comparação entre a microárea do paciente e a do ACS segue em cada caso de uso) e um teste de postura cobre os 7 endpoints, mas `requireLogin` segue `false` (o `AuthenticationHandler` do Serverpod não está conectado) e os papéis `coordinator`/`admin` não têm caminho de emissão. |

### Invariantes de negócio

| ID | Invariante | Veredicto | Evidência desta validação |
|---|---|---|---|
| INV-01 | ACS não vê paciente de outra microárea | **aplicado** | `patients.listMicroArea` devolveu exatamente 5 pacientes e excluiu `…0009` (outra microárea). Token de paciente foi recusado com `AlertPermissionException`. `visits.sync` recusa por território e audita `denied_territory`. |
| INV-02 | Risco não alterável por humano na triagem | **aplicado** | O risco vem de `TriageEngine.evaluate`, determinístico, e é o mesmo valor gravado em `TriageSession.resultRisk`; `triage.evaluate` não aceita nenhum campo de risco vindo do cliente, e o app do paciente não recalcula risco. |
| INV-03 | Alerta vermelho nunca descartado | **aplicado** | Outbox transacional (`alert_outbox`, 70 linhas) + QoS 1 com sessão persistente; 5 alertas de backlog reentregues na reconexão. |
| INV-04 | Dado de saúde nunca em texto plano | **aplicado no dispositivo** | Provado por `encrypted_storage_test.dart` em hardware. **Não aplicado no servidor** — as colunas do PostgreSQL são texto claro. |
| INV-05 | Paciente não acessa dado de outro paciente | **aplicado** | `alerts.statusFor` lê o status do alerta mais recente do próprio paciente: `patientId` nunca é parâmetro, vem sempre de `user.id` do token — mesma disciplina de `triage.evaluate`/`visits.pull`, então um token só alcança o próprio status por construção. Token de ACS é recusado com `AlertPermissionException`. Provado em `red_alert_service_test.dart` (grupo `statusFor (RF05)`) e `red_alert_cycle_test.dart`. Fechado por `docs/superpowers/plans/2026-09-18-sync-periodica-rf05-l06.md` (L-03). |

---

## 4. Matriz de consumo: método RPC × app

| Método RPC | Paciente | ACS | Admin |
|---|---|---|---|
| `auth.developmentLogin` | ✅ só em `tool/` e `integration_test/` — `backend_client.dart:180` | ✅ só em `tool/` e `integration_test/` — `backend_client.dart:160` | ❌ |
| `auth.loginInstitutional` | — | ✅ `backend_client.dart:113` | ❌ |
| `auth.requestOtp` | ✅ `backend_client.dart:147` | — | ❌ |
| `auth.verifyOtp` | ✅ `backend_client.dart:161` | — | ❌ |
| `health.check` | ⚠️ só em `live_check`/teste | ❌ saiu da interface (L-14) | ❌ |
| `onboarding.generateEnrollmentToken` | ❌ | ❌ | ❌ |
| `onboarding.completeEnrollment` | ✅ `backend_client.dart:266` | — | ❌ |
| `triage.evaluate` | ✅ `backend_client.dart:210` | — | ❌ |
| `alerts.createRedAlert` | ✅ `backend_client.dart:247` | — | ❌ |
| `alerts.statusFor` | ✅ `backend_client.dart:228` | — | ❌ |
| `alerts.acknowledge` | — | ✅ `backend_client.dart:185` | ❌ |
| `visits.sync` | — | ✅ `backend_client.dart:197` | ❌ |
| `visits.pull` | — | ✅ `backend_client.dart:212` | ❌ |
| `patients.listMicroArea` | — | ✅ `backend_client.dart:220` | ❌ |
| **Cobertura** | **8/14** (7 + `health.check`, que só as ferramentas usam) | **6/14** | **0/14** |

**União paciente+ACS: 13/14.** Com uma exceção, nenhum endpoint do backend
está sem consumidor: `onboarding.generateEnrollmentToken` é o gerador de
token de convite do lado da unidade de saúde (RF02) e só tem consumidor em
teste (`onboarding_endpoint_test.dart`) — nasceu para o backoffice/posto,
que ainda não existe (L-01).

Um método de interface permanece voltado somente à ferramenta de validação:
`PatientBackend.health()` é usado por `tool/live_check.dart`; o ACS não mantém
uma cópia desse método, pois seu `health.check` não é usado pelo app nem pelas
ferramentas atuais.

**Canal não-RPC:** alertas chegam ao ACS exclusivamente por MQTT/TLS no tópico
`sinalacs/v1/microareas/<microAreaId>/alerts`. Não existe endpoint de listagem
de alertas — se o broker cair, não há caminho alternativo de leitura.

---

## 5. Inventário de dado fabricado, por tela

| App | Tela | Origem | Observação |
|---|---|---|---|
| Paciente | Login | **real** | Autentica de verdade — o login é CPF + data de nascimento + código OTP (RF01); os campos deixaram de ser decorativos. |
| Paciente | Triagem | **real** | 6 sintomas, risco vem do servidor. |
| Paciente | Urgência | **real (parcial)** | Lê localização em primeiro plano, envia somente `locationHash` e explicita o fallback quando GPS/permissão falham; ainda não há validação E2E em dispositivo nesta revisão. |
| Paciente | **Status** | **real** | Consome `alerts.statusFor` (RF05); mostra o status real do alerta mais recente do paciente, não mais o texto fixo "Solicitação #4082 · Triagem Vermelha". Fechado por `docs/superpowers/plans/2026-09-18-sync-periodica-rf05-l06.md` (L-03). |
| Paciente | Perguntas | **removida (2026-09-21)** | Era resposta automática fixa sobre vacinação, sem backend — contradizia a exclusão explícita de mensageria assíncrona do escopo MVP (`spec/PRD_system.md` §6.1). Tirada do menu "Mais" e do código. |
| Paciente | Perfil clínico | **real (2026-09-21)** | Lê/grava `patients.myChronicConditions`/`updateChronicConditions` — condições crônicas cifradas (AES-256-GCM) via `Patient.chronicConditionsEncrypted`, não mais fixas. |
| Paciente | Lembretes | **real** | Esta linha estava desatualizada: `RemindersScreen` já persiste em SQLite local (`sqflite_reminder_store.dart`) e agenda via `flutter_local_notifications`, gated por consentimento — não há lista fixa de exemplo. |
| ACS | Login | **real** | |
| ACS | **Fila** | **real** | Alerta criado via RPC apareceu ao vivo no emulador. |
| ACS | **Área** | **real** | Consome `patients.listMicroArea` ao vivo; mostra a contagem real de pacientes da microárea, não mais "142 cadastrados" fixo. Fechado por `docs/superpowers/plans/2026-09-18-sync-periodica-rf05-l06.md` (L-06). |
| ACS | Mapa | **sintético** | `alertPositionFor()` (a fabricação de lat/lng por hash em torno de Brasília) foi removida; o mapa agora desenha a geocélula real (`locationCell`, ~1,1 km), não mais uma posição fabricada — ver §6 abaixo. |
| ACS | Visita | **real** | Seletor vem de `patients.listMicroArea`; fila vai a `visits.sync`. |
| ACS | Escalonamento | **stub** | SAMU e UBS são snackbars. |
| ACS | Avisos | **stub** | Entrada descartada. |
| Admin | Login | **sem autenticação** | Entrou **sem credencial válida** nesta validação. |
| Admin | Indicadores | **mock** | Mostrou 2/2/2 e TMRAV 78s; o banco real tinha **70 alertas** (43 pendentes, 27 confirmados). |
| Admin | Microáreas | **mock** | 3 entradas fixas. |
| Admin | Alertas | **mock** | 6 alertas fixos com datas fixas. |
| Admin | Auditoria | **mock + memória** | Só mostra o que a própria sessão registrou; morre com o processo. |

---

## 6. Esquema morto: tabelas modeladas que ninguém escreve

Agora **7 tabelas** recebem escrita do servidor (`visits`, `audit_logs`,
`alerts`, `alert_idempotency_keys`, `alert_deliveries`, `alert_outbox`,
`triage_sessions`) e 5 são populadas pelo seed. Uma fica de fora inteiramente:

| Tabela | Referências fora de `generated/` | Consequência |
|---|---|---|
| `triage_sessions` | `TriageSessionService.evaluateAndRecord`, chamado por `triage.evaluate` | Grava a sessão com o `patientId` do token e audita (RF17); o risco continua vindo só do `TriageEngine` (INV-02). |
| `consent_logs` | **nenhuma** | LGPD-RF02 (consentimento granular) tem tabela, migração e modelo, mas nenhum escritor. |

**Atualização (L-04 fechada):** `triage_sessions` passou a ter escritor —
`TriageSessionService`, gravado por `triage.evaluate`, que agora exige token e
identifica o paciente. `consent_logs` continua sem escritor.

Consequência mensurável: a tabela `alerts` só recebe risco `red` (é o único
caminho de escrita). Portanto **os contadores "Amarelo" e "Verde" do backoffice
não têm fonte possível hoje** — nem se o admin fosse ligado ao backend real. O
mesmo vale para a TMRAV segmentada por risco, que é a métrica *North Star* do PRD.

---

## 7. Critérios de aceite do PRD nunca medidos

| Milestone | Critério declarado | Realidade verificada |
|---|---|---|
| M1.3 | "Cobertura 100% MCDC; classifica 50 cenários" | `triage_engine_test.dart` tem **3** casos para 2⁶ = 64 combinações |
| M2.3 | "MQTT via WebSockets (WSS)" | Implementado como TCP/TLS na 8883; WSS não é publicado pelo broker |
| M2.4 | "100 registros offline sincronizam em < 5 s" | Nunca medido |
| M2.5 | "Testes de caos (Toxiproxy)" | Toxiproxy não existe; o caos é client-side, fora da CI |
| §5.3 | Pirâmide 70/20/10 | Nenhuma medição de cobertura existe no repositório |

`PROGRESS.md` marca M1.3, M2.3, M2.4 e M2.5 como "Implementado".

---

## 8. Lacunas priorizadas

### P0 — impedem uso com paciente real

- **L-01 · Backoffice sem integração alguma.** 0/11 métodos; `sinalacs_client`
  nem consta do `pubspec.yaml`; login é `pushReplacement` puro, gated só por
  `kDebugMode`; a trilha de auditoria exigida pelo PRD §4.2.2 é uma `List` em
  memória. O app exibe números que contradizem o banco.
- **L-02 · ~~Todo alerta vermelho sai sem localização.~~** PARCIALMENTE RESOLVIDO —
  `GeolocatorLocationReader` tenta ler a posição em primeiro plano, normaliza a
  coordenada e envia somente `locationHash`; permissão negada, serviço desligado
  ou timeout usam `unknownLocationHash` com aviso explícito na tela. Ainda falta
  validar o fluxo em emulador/dispositivo e aprovar a precisão de localização
  perante LGPD; o risco de reidentificação espacial está ligado à recomendação
  #9 de `spec/lgpd_data_audit.md`.
- **L-03 · ~~Tela de Status mente para o paciente.~~** RESOLVIDO — a tela
  deixou de ser `const` e consome `alerts.statusFor` (RF05), mostrando o
  status real do alerta mais recente do paciente autenticado em vez de uma
  árvore fixa anunciando triagem vermelha em análise. Ver
  `docs/superpowers/plans/2026-09-18-sync-periodica-rf05-l06.md`.
- **L-04 · ~~A triagem não deixa registro.~~** RESOLVIDO — `triage.evaluate`
  exige `accessToken`, grava em `triage_sessions` e audita. Ver
  `docs/superpowers/plans/2026-09-16-triagem-persistida.md`.

### P1 — comprometem a operação de campo

- **L-05 · Mapa com coordenadas inventadas.** Note que isto **não é só um stub**:
  o envelope MQTT carrega apenas o hash, por minimização LGPD. RF10 e o desenho
  de privacidade estão em conflito direto — resolver exige decisão de produto,
  não só código.
  **Atualização (Task 3, `docs/superpowers/plans/2026-09-17-decisoes-produto-pos-validacao-implementacao.md`):**
  a decisão de produto foi tomada (célula de baixa resolução, não coordenada
  exata) e está implementada de ponta a ponta — paciente calcula
  `locationCell` (`apps/patient/lib/core/privacy/location_cell.dart`), o
  backend propaga `locationCell`/`location_cell` opcional
  (`Alert`/`AlertDelivery`/`createRedAlert`), e o mapa do ACS
  (`apps/acs/lib/app/app.dart`) desenha um círculo de incerteza no centro da
  célula via `parseLocationCell`
  (`apps/acs/lib/core/geo/location_cell.dart`), sem marcador para alertas sem
  célula. `alertPositionFor` (a fabricação por hash) foi removida. Provado por
  `apps/acs/test/location_cell_test.dart`,
  `apps/acs/test/mqtt_secure_client_test.dart` e
  `apps/acs/test/map_screen_test.dart` — suíte completa do ACS roda verde
  (`flutter analyze && flutter test`, falhas restantes são só
  `encrypted_database_test.dart` por `libsqlite3.so` ausente neste ambiente,
  pré-existente e não relacionado). O veredito de RF10/L-05 permanece
  `parcial` nesta tabela porque reclassificar a matriz inteira é decisão de
  produto separada, fora do escopo desta task.
- **L-06 · ~~Tela "Área" com números falsos que contradizem o backend (142 vs
  5).~~** RESOLVIDO — a tela agora consome `patients.listMicroArea` ao vivo
  (mesma chamada real que já territorializava a fila/visita) e mostra a
  contagem real de pacientes da microárea, atualizada ao abrir a tela e em
  ciclo periódico. Ver
  `docs/superpowers/plans/2026-09-18-sync-periodica-rf05-l06.md`. RF08
  continua `parcial` — ver linha RF08 acima.
- **L-07 · Escalonamento SAMU não funciona.** O botão mais crítico da UI de
  emergência é um snackbar.
- **L-08 · ~~RPC sem TLS. O backend fala HTTP puro na 8080; só o broker usa
  TLS. RNF04 não é atendido.~~** RESOLVIDO em desenvolvimento — o RPC só é
  alcançável por HTTPS em :443, terminado pelo Traefik, com TLS 1.3 mínimo e a
  CA de desenvolvimento copiada para os dois apps por `sync_dev_ca.sh`; a
  publicação de 8080 foi removida, então não há caminho sem criptografia. O que
  falta é o certificado de produção (domínio + `cert-manager`), que é decisão
  de infraestrutura — **mas ele não basta sozinho**: quem termina TLS é a borda,
  e a última perna (proxy → processo) continua em texto claro, tanto no piloto
  quanto aqui (o `loadbalancer` do Traefik fala http com o container na 8080).
  É o par `cert-manager` **+ rede privada** que fecha a diferença; ver
  "Limitações conhecidas" em `backend/DEPLOY.md`. Ver
  `docs/superpowers/plans/2026-09-18-tls-rpc-rnf04-l08.md`.

### P2 — dívida de qualidade e processo

**Atualização (Task 7, 2026-09-16):** L-10, L-11, L-12 e L-13 passaram a ter
endereçamento de código. A CI ganhou um job de E2E Android com
`./scripts/qa/e2e.sh --emulator`, o harness passou a incluir o admin e a fixar
`-d emulator-5554`, a cobertura ganhou script/artifacts dedicados e os ramos de
backend listados em L-13 receberam testes focados. As métricas RNF01/RNF02
agora têm coleta automatizada em `scripts/qa/measure_latency.dart`, mas os
valores continuam dependentes de stack/broker disponíveis no ambiente em que o
script rodar.

- **L-09 · RNF06 (RBAC) — camada de autorização implementada, papéis
  institucionais ainda ausentes.** `Authorization.require` centraliza a decisão
  de papel e de presença de território no token — a comparação entre a microárea
  do paciente e a do ACS continua em cada caso de uso — e substituiu as 8
  checagens ad-hoc; os 4 endpoints
  integralmente autenticados estendem `AuthenticatedEndpoint` e um teste de
  postura impede um endpoint novo de nascer público. O que **não** mudou: os
  papéis `coordinator` e `admin` continuam sem caminho de emissão e sem
  endpoint que os exercite — isso é o backend do backoffice (L-01), fora do
  escopo desta rodada. Ver
  `docs/superpowers/plans/2026-09-18-rbac-camada-autorizacao.md`.
- **L-10 · CI não executa nenhum `integration_test`.** O do admin é hermético
  (sem stack, sem seed, sem `--dart-define`) — é ganho imediato.
- **L-11 · `scripts/qa/e2e.sh` ignora o admin** e não passa `-d emulator-5554`
  (com 3 devices visíveis o comando é ambíguo) nem `GOOGLE_MAPS_API_KEY`, então
  `map_flow_test.dart` sempre testa o ramo "sem chave".
- **L-12 · Sem medição de cobertura** em nenhum pacote.
- **L-13 · Ramos sem asserção no backend:** `health.check` com `dbConnected:false`;
  `acknowledge` de alerta inexistente e `alertId` vazio pelo endpoint;
  `visits.sync` com lista vazia e desfechos `synced`/`conflict`/`error` pelo
  endpoint; `patients.listMicroArea` com token inválido.
  `mqtt_alert_dispatcher.dart` (161 linhas) tem **zero** referências em `test/`.
- **L-14 · Código morto:** `AlertDispatchUnavailableException` é declarado e
  nunca lançado; o método `health()` foi removido da interface do ACS por não
  ter consumidores. `PatientBackend.health()` permanece somente na ferramenta
  de validação do paciente.
- **L-15 · `applicationId` do paciente é `com.example.sinalacs_patient`**,
  o default do template — impublicável. ACS e admin já usam `br.com.prismrr.*`.
- **L-16 · Criação da AVD não é documentada** em lugar nenhum, embora
  `emulator-5554` seja tratado como dado por CLAUDE.md, AGENTS.md e specs.
- **L-17 · Drift documental**, todos verificados nesta validação:
  - `PROGRESS.md` — caminhos `backend/lib/...` inexistentes, "18/18 testes" (são 83), "CI com 4 jobs" (são 6), milestones medidos marcados como feitos.
  - `CLAUDE.md` — "11 tabelas" (são 13); descreve a perda de alerta no commit como risco aberto, mas o outbox já existe.
    **Atualização (2026-09-19):** o número medido hoje é **16 tabelas de domínio** — o
    `definition.sql` da migração mais recente (`20260919032710552`) tem 29 `CREATE TABLE`, 13
    delas `serverpod_*`. O "13" acima era o estado de `20260917125250890`; desde então entraram
    `enrollment_tokens` (RF02) e o par `otp_challenges`/`user_credentials` (RF01/RF07). O
    `CLAUDE.md` da raiz foi alinhado a 16 e o `backend/CLAUDE.md` ("16 tables") mede o mesmo.
    Reconte no `definition.sql` da migração mais recente antes de citar o número — ele muda a
    cada migração.
  - `CONTRIBUTING.md` — "a CI usa Flutter 3.24.0" (usa 3.44.8).
  - `spec/sys_flow.md` — afirma que o backend acessa Postgres "sem ORM" e cita `PROGRESS.md` para um motor de sync não conectado.
  - ~~`docs/README.md` — não linka `telas-admin.md`.~~ **Correção (2026-09-19): falso.** O
    `docs/README.md:5` linka `telas-admin.md`, e o arquivo existe. Uma verificação de uma linha
    derruba a afirmação — e ela ficou aqui desde a validação original, no meio de uma lista cujo
    propósito é justamente registrar drift verificado.

---

## 9. Anexo — reexecutar a bateria

```bash
export PATH="$HOME/Android/Sdk/platform-tools:$PATH"   # adb não está no PATH
cd /caminho/para/SinalACS

# 0) stack + seed  (o seed já roda sozinho: depends_on serverpod healthy)
docker compose up --build -d
# Copia as DUAS CAs de desenvolvimento — a do broker (MQTT em 8883) e a do RPC
# (HTTPS em 443, terminado pelo Traefik). São CAs separadas de propósito; o
# script confere com `openssl verify` que cada uma assina a folha em uso.
#
# ~~e aborta sem copiar nada se alguma não assinar.~~ — **FALSO, medido em
# 2026-09-19 em sandbox com certificados descartáveis.** A cópia é POR PAR
# (app × CA) e a conferência acontece dentro de cada par, então a abortagem cai
# no MEIO da sequência: com a CA do RPC não assinando a folha, o script copia a
# CA do broker para o ACS e SÓ ENTÃO falha, imprimindo "nada foi copiado". Medido
# nos dois estados possíveis do asset:
#   * asset já preenchido — o ACS fica com a CA NOVA do broker e a CA ANTIGA do
#     RPC (hash do dev_ca.crt muda, o do dev_rpc_ca.crt não), e o paciente não é
#     tocado, porque o laço é por app (ACS inteiro antes do paciente);
#   * asset vazio (clone limpo) — o ACS fica só com a CA do broker e o paciente
#     com nada.
# É exatamente o caso que o `openssl verify` foi acrescentado para pegar: quem
# reexecutar esta bateria com um `runtime/` trocado fica com asset em estado
# misto achando que nada mudou.
#
# Melhoria registrada e NÃO implementada (esta rodada é só documentação):
# conferir os quatro pares antes de copiar qualquer um torna o "nada foi
# copiado" verdadeiro. Medido em sandbox nos dois sentidos — na falha, os quatro
# assets ficam intactos; no caminho bom, as quatro cópias saem iguais às de hoje.
./scripts/dev/sync_dev_ca.sh

# 1) backend
docker compose --profile test up -d postgres-test
cd backend && dart pub get && dart analyze
cd sinalacs_server && dart test                      # suíte completa (unit + integração)

# 2) integração sem dispositivo
cd ../.. && ./scripts/qa/e2e.sh --keep

# 3) emulador — sempre com -d explícito
set -a; source .env; set +a
cd apps/patient && flutter test integration_test -d emulator-5554 \
  --dart-define=SINALACS_HOST=https://10.0.2.2/
cd ../acs && flutter test integration_test -d emulator-5554 \
  --dart-define=SINALACS_HOST=https://10.0.2.2/ \
  --dart-define=SINALACS_MQTT_HOST=10.0.2.2 \
  --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" \
  --dart-define=GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY"
cd ../admin && flutter test integration_test -d emulator-5554

# 4) cadeia de auditoria
AUDIT_CHAIN_SECRET="$AUDIT_CHAIN_SECRET" SERVERPOD_DATABASE_HOST=localhost \
  SERVERPOD_DATABASE_PASSWORD="$POSTGRES_PASSWORD" \
  dart run backend/sinalacs_server/bin/audit_chain_check.dart

docker compose down
```

**Armadilha conhecida:** se `TEST_DATABASE_PASSWORD` no `.env` divergir do bloco
`test:` de `config/passwords.yaml`, o Serverpod chama `exit(1)` sem esvaziar o
stdout e a suíte morre com código 1 e **zero linhas de log**. Nesta validação os
dois estavam alinhados (o YAML apenas cita o valor entre aspas).
