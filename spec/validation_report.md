# Relatório de Validação — Cobertura do Backend e Integração dos Apps

**Data:** 2026-09-16 · **Branch:** `fix/backend` · **Commit base:** `a9dcbc5`
**Escopo:** diagnóstico. Nenhuma correção de código foi aplicada.
**Ambiente:** Docker 29.8.0 · Flutter 3.44.8 · Dart 3.12.2 · `emulator-5554` (Android 16, API 36, x86_64)

---

## 1. Sumário executivo

**O backend está completo?** Não, mas o que existe é sólido. Os 7 métodos RPC
implementados funcionam, têm cobertura de teste integral (83/83 passando) e
aplicam as invariantes de negócio que prometem. O que falta são requisitos
inteiros do PRD que nunca saíram do papel — 7 dos 18 RF não têm código em lugar
nenhum — e duas tabelas modeladas e migradas que **nenhuma linha de código
escreve**.

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

**Total: 108 testes automatizados passando** (83 backend + 25 no emulador).

Observação de backlog: o `live_check` do ACS relatou **5 alertas reentregues**
ao reconectar, confirmando que a sessão persistente com QoS 1 retém e reentrega
alertas recebidos enquanto o dispositivo estava offline (INV-03).

---

## 3. Matriz de rastreabilidade RF / RNF / INV

Legenda: **`backend`** = endpoint + teste · **`app-only`** = corretamente só no
cliente · **`parcial`** = existe, mas alimentado por dado fabricado ·
**`ausente`** = sem código.

### Requisitos funcionais

| ID | Requisito | Veredicto | Evidência |
|---|---|---|---|
| RF01 | Autenticação passwordless (CPF + nasc. + OTP) | **ausente** | Campos de CPF/data existem na UI mas são decorativos; o login chama `auth.developmentLogin(role)` ignorando a entrada. Sem gateway SMS. |
| RF02 | Onboarding via QR Code | **ausente** | Botão presente; `app.dart:170` emite snackbar "será disponibilizada". |
| RF03 | Botão de alerta de urgência (MQTT) | **parcial** | Endpoint e entrega funcionam (validado em dispositivo). **Mas a geolocalização nunca é lida** — ver L-02. |
| RF04 | Formulário de triagem estruturada | **backend** | `triage.evaluate` exige token, classifica pelo motor determinístico e grava em `triage_sessions` com auditoria. |
| RF05 | Painel de status da solicitação | **ausente** | A tela existe e é 100% `const`. Não há endpoint de leitura para o paciente. Ver L-03. |
| RF06 | Lembretes de saúde | **ausente** | `RemindersScreen` tem lista fixa; salvar descarta. Sem `flutter_local_notifications`. |
| RF07 | Login institucional (matrícula/senha) | **ausente** | Só o token HMAC de desenvolvimento, sob `ENABLE_DEV_LOGIN`. |
| RF08 | Territorialização (cache da microárea) | **parcial** | `patients.listMicroArea` é real e territorializado. A tela "Área" mostra literais — ver L-06. |
| RF09 | Dashboard de priorização dinâmica | **backend** | Fila real alimentada por MQTT, ordenada por risco e idade; valida rejeição de alerta de outra microárea. |
| RF10 | Mapa interativo | **parcial** | Coordenadas são **fabricadas** a partir do hash — ver L-05. |
| RF11 | Registro rápido de visitas offline-first | **backend** | `visits.sync` com dedupe por `localId`, versionamento, conflito e território. Fila SQLCipher no dispositivo. |
| RF12 | Geofencing (check-in passivo) | **ausente** | `RouteService` calcula chegada localmente, mas não há GPS em segundo plano. |
| RF13 | Escalonamento para SAMU/UBS | **ausente** | Ambos os botões são snackbars — ver L-07. |
| RF14 | Avisos segmentados (push) | **ausente** | `NoticesScreen` descarta a entrada. Sem FCM/APNs. |
| RF15 | Sincronização bidirecional | **parcial** | Dispositivo → central funciona e é testado. O sentido central → dispositivo **não existe**: não há endpoint de leitura de visitas/alertas. |
| RF16 | Motor de triagem determinístico | **backend** | `TriageEngine`, determinismo verificado em teste de integração. INV-02 preservado. |
| RF17 | Logs de auditoria e conformidade | **backend** | `audit_logs` encadeado por HMAC; gravou `granted` e `denied_territory` nesta validação; cadeia verificada íntegra. |
| RF18 | Dark mode nativo | **app-only** | Tema único dark nos três apps, com matriz de contraste testada. |

**Contagem:** 4 `backend` · 1 `app-only` · 6 `parcial` · 7 `ausente`.

### Requisitos não funcionais

| ID | Requisito | Veredicto | Evidência |
|---|---|---|---|
| RNF01 | Latência MQTT < 500 ms (p95) | **não medido** | Entrega funciona; não há instrumentação de latência. |
| RNF02 | Sincronização offline > 99,5% | **não medido** | Semântica correta e testada; taxa nunca medida. |
| RNF03 | Criptografia AES-256 em repouso | **backend/app** | SQLCipher provado em dispositivo (o arquivo não contém o conteúdo em texto claro e não abre com chave errada). **No PostgreSQL não há criptografia de coluna** — `pgcrypto` previsto no PRD não foi adotado. |
| RNF04 | TLS 1.3 em todas as comunicações | **parcial** | Broker em TLS com verificação de hostname. **O RPC do backend é HTTP puro** na 8080, sem TLS, inclusive do emulador. |
| RNF05 | Acessibilidade WCAG AA | **app-only** | Matrizes de contraste, alvos de toque e `liveRegion` testados nos três apps. |
| RNF06 | RBAC | **ausente** | Todo endpoint é `requireLogin => false`; só há checagem ad-hoc de `user.role`. `triage.evaluate` deixou de ser público (exige token e papel `patient`), mas não existe camada formal de RBAC. |

### Invariantes de negócio

| ID | Invariante | Veredicto | Evidência desta validação |
|---|---|---|---|
| INV-01 | ACS não vê paciente de outra microárea | **aplicado** | `patients.listMicroArea` devolveu exatamente 5 pacientes e excluiu `…0009` (outra microárea). Token de paciente foi recusado com `AlertPermissionException`. `visits.sync` recusa por território e audita `denied_territory`. |
| INV-02 | Risco não alterável por humano na triagem | **aplicado** | `TriageEndpoint` é função pura sem campo editável; app do paciente não recalcula risco no cliente. |
| INV-03 | Alerta vermelho nunca descartado | **aplicado** | Outbox transacional (`alert_outbox`, 70 linhas) + QoS 1 com sessão persistente; 5 alertas de backlog reentregues na reconexão. |
| INV-04 | Dado de saúde nunca em texto plano | **aplicado no dispositivo** | Provado por `encrypted_storage_test.dart` em hardware. **Não aplicado no servidor** — as colunas do PostgreSQL são texto claro. |
| INV-05 | Paciente não acessa dado de outro paciente | **vacuamente verdadeiro** | Não existe endpoint de leitura voltado ao paciente. Vira risco real no momento em que RF05 for implementado. |

---

## 4. Matriz de consumo: método RPC × app

| Método RPC | Paciente | ACS | Admin |
|---|---|---|---|
| `auth.developmentLogin` | ✅ `backend_client.dart:99` | ✅ `backend_client.dart:88` | ❌ |
| `health.check` | ⚠️ só em `live_check`/teste | ⚠️ declarado, **nunca chamado** | ❌ |
| `triage.evaluate` | ✅ `backend_client.dart:128` | — | ❌ |
| `alerts.createRedAlert` | ✅ `backend_client.dart:152` | — | ❌ |
| `alerts.acknowledge` | — | ✅ `backend_client.dart:113` | ❌ |
| `visits.sync` | — | ✅ `backend_client.dart:125` | ❌ |
| `patients.listMicroArea` | — | ✅ `backend_client.dart:138` | ❌ |
| **Cobertura** | **4/7** | **5/7** | **0/7** |

**União paciente+ACS: 7/7.** Nenhum endpoint do backend está sem consumidor.

Dois métodos de interface mortos: `PatientBackend.health()` só é chamado por
ferramenta de teste, e `AcsBackend.health()` não é chamado em lugar nenhum.

**Canal não-RPC:** alertas chegam ao ACS exclusivamente por MQTT/TLS no tópico
`sinalacs/v1/microareas/<microAreaId>/alerts`. Não existe endpoint de listagem
de alertas — se o broker cair, não há caminho alternativo de leitura.

---

## 5. Inventário de dado fabricado, por tela

| App | Tela | Origem | Observação |
|---|---|---|---|
| Paciente | Login | **real** | Autentica de verdade; campos CPF/nascimento são decorativos. |
| Paciente | Triagem | **real** | 6 sintomas, risco vem do servidor. |
| Paciente | Urgência | **real (parcial)** | Cria alerta real, mas sempre com `unknownLocationHash`. |
| Paciente | **Status** | **hardcoded** | "Solicitação #4082 · Triagem Vermelha · hoje às 09:30" — **confirmado em tela**. |
| Paciente | Perguntas | **hardcoded** | Resposta automática fixa sobre vacinação. |
| Paciente | Perfil clínico | **hardcoded** | Condições fixas; salvar descarta. |
| Paciente | Lembretes | **hardcoded** | Medicações fixas. |
| ACS | Login | **real** | |
| ACS | **Fila** | **real** | Alerta criado via RPC apareceu ao vivo no emulador. |
| ACS | **Área** | **hardcoded** | Diz "142 cadastrados"; o backend tem **5** nessa microárea. |
| ACS | Mapa | **sintético** | `alertPositionFor()` deriva lat/lng do hash em torno de Brasília. |
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

Apenas **6 tabelas** recebem escrita do servidor (`visits`, `audit_logs`,
`alerts`, `alert_idempotency_keys`, `alert_deliveries`, `alert_outbox`) e 5 são
populadas pelo seed. Duas ficam de fora inteiramente:

| Tabela | Referências fora de `generated/` | Consequência |
|---|---|---|
| `triage_sessions` | **nenhuma** | A triagem calcula o risco e **descarta**. Não há histórico clínico, nem vínculo entre triagem e paciente — `triage.evaluate` sequer recebe `accessToken`. RF17 não cobre a triagem. |
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

- **L-01 · Backoffice sem integração alguma.** 0/7 métodos; `sinalacs_client`
  nem consta do `pubspec.yaml`; login é `pushReplacement` puro, gated só por
  `kDebugMode`; a trilha de auditoria exigida pelo PRD §4.2.2 é uma `List` em
  memória. O app exibe números que contradizem o banco.
- **L-02 · Todo alerta vermelho sai sem localização.**
  `apps/patient/lib/app/app.dart:306` envia `unknownLocationHash`
  incondicionalmente. `geolocator: ^12.0.0` está no `pubspec` e tem **zero** uso
  em `lib/`. RF03 exige geolocalização; o ACS recebe um alerta de emergência que
  não diz onde é.
- **L-03 · Tela de Status mente para o paciente.** Árvore `const` anunciando
  triagem vermelha em análise. Um paciente pode acreditar que um pedido de
  socorro está sendo tratado quando nada foi registrado.
- **L-04 · ~~A triagem não deixa registro.~~** RESOLVIDO — `triage.evaluate`
  exige `accessToken`, grava em `triage_sessions` e audita. Ver
  `docs/superpowers/plans/2026-09-16-triagem-persistida.md`.

### P1 — comprometem a operação de campo

- **L-05 · Mapa com coordenadas inventadas.** Note que isto **não é só um stub**:
  o envelope MQTT carrega apenas o hash, por minimização LGPD. RF10 e o desenho
  de privacidade estão em conflito direto — resolver exige decisão de produto,
  não só código.
- **L-06 · Tela "Área" com números falsos** que contradizem o backend (142 vs 5).
- **L-07 · Escalonamento SAMU não funciona.** O botão mais crítico da UI de
  emergência é um snackbar.
- **L-08 · RPC sem TLS.** O backend fala HTTP puro na 8080; só o broker usa TLS.
  RNF04 não é atendido.

### P2 — dívida de qualidade e processo

- **L-09 · RNF06 (RBAC) ausente**; `triage.evaluate` é publicamente acessível
  sem autenticação.
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
  nunca lançado; `health()` está morto nas duas interfaces de app.
- **L-15 · `applicationId` do paciente é `com.example.sinalacs_patient`**,
  o default do template — impublicável. ACS e admin já usam `br.com.prismrr.*`.
- **L-16 · Criação da AVD não é documentada** em lugar nenhum, embora
  `emulator-5554` seja tratado como dado por CLAUDE.md, AGENTS.md e specs.
- **L-17 · Drift documental**, todos verificados nesta validação:
  - `PROGRESS.md` — caminhos `backend/lib/...` inexistentes, "18/18 testes" (são 83), "CI com 4 jobs" (são 6), milestones medidos marcados como feitos.
  - `CLAUDE.md` — "11 tabelas" (são 13); descreve a perda de alerta no commit como risco aberto, mas o outbox já existe.
  - `CONTRIBUTING.md` — "a CI usa Flutter 3.24.0" (usa 3.44.8).
  - `spec/sys_flow.md` — afirma que o backend acessa Postgres "sem ORM" e cita `PROGRESS.md` para um motor de sync não conectado.
  - `docs/README.md` — não linka `telas-admin.md`.

---

## 9. Anexo — reexecutar a bateria

```bash
export PATH="$HOME/Android/Sdk/platform-tools:$PATH"   # adb não está no PATH
cd /caminho/para/SinalACS

# 0) stack + seed  (o seed já roda sozinho: depends_on serverpod healthy)
docker compose up --build -d
./scripts/dev/sync_dev_ca.sh

# 1) backend
docker compose --profile test up -d postgres-test
cd backend && dart pub get && dart analyze
cd sinalacs_server && dart test                      # 83 testes

# 2) integração sem dispositivo
cd ../.. && ./scripts/qa/e2e.sh --keep

# 3) emulador — sempre com -d explícito
set -a; source .env; set +a
cd apps/patient && flutter test integration_test -d emulator-5554 \
  --dart-define=SINALACS_HOST=http://10.0.2.2:8080/
cd ../acs && flutter test integration_test -d emulator-5554 \
  --dart-define=SINALACS_HOST=http://10.0.2.2:8080/ \
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
