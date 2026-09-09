# Progresso das Fases 1 e 2 - Milestones Técnicos

Este documento consolida o que foi implementado no repositório em relação às fases 1 e 2 da Seção 6.2, "Milestones Técnicos", do PRD.

> **Nota de leitura — o backend migrou para Serverpod.** As entradas M1.x e M2.x
> abaixo registram o que era verdade quando foram escritas, e por isso não foram
> reescritas: elas descrevem o servidor `dart:io` roteado à mão, e seus links
> para `backend/bin/`, `backend/lib/` e `backend/test/` apontam para código que
> **não existe mais na árvore atual** — só no histórico do git. O mesmo vale para
> a seção de preparação de deploy, escrita para aquele servidor.
>
> O estado atual está descrito na seção
> ["Migração para Serverpod"](#migração-para-serverpod) ao final deste documento,
> e em [CLAUDE.md](CLAUDE.md), que é a referência atualizada de arquitetura e
> comandos.

## Resumo executivo

A Fase 1 está concluída no código e validada por testes locais. A Fase 2 avançou além do MVP inicial: o backend já implementa e valida o ciclo crítico de alerta vermelho com autenticação, idempotência, publicação no broker e confirmação de recebimento pelo ACS em ambiente local com Docker Compose. Além das Fases 1 e 2, a seção ["Preparação de deploy — piloto em serviços free-tier (backend)"](#preparação-de-deploy--piloto-em-serviços-free-tier-backend) mais abaixo documenta um trabalho complementar de preparação do backend para hospedagem gratuita (fora da numeração M1.x/M2.x/M3.x do PRD).

### Status geral

- M1.1: Implementado
- M1.2: Implementado
- M1.3: Implementado
- M1.4: Implementado
- M1.5: Implementado
- M2.1: Implementado
- M2.2: Implementado
- M2.3: Implementado
- M2.4: Implementado
- M2.5: Implementado
- M2.6: Implementado

## Milestones Técnicos - Fase 1

| Milestone | Entregável | Status | Evidência |
|---|---|---|---|
| M1.1 | Docker-Compose local (Stack completa) | Implementado | [docker-compose.yml](docker-compose.yml) com PostgreSQL, Mosquitto, backend (serviço ainda nomeado `serverpod` no compose por herança do nome original, mas roda o backend Dart puro) e Traefik |
| M1.2 | CI Pipeline básica | Implementado | [.github/workflows/ci.yml](.github/workflows/ci.yml) com 4 jobs: backend, build da imagem Docker do backend, e os dois apps Flutter |
| M1.3 | Motor de Triagem (algoritmo) | Implementado | [backend/lib/src/application/triage/triage_engine.dart](backend/lib/src/application/triage/triage_engine.dart) e [backend/test/triage_engine_test.dart](backend/test/triage_engine_test.dart) |
| M1.4 | FSM de Sincronização | Implementado | [backend/lib/src/application/sync/sync_fsm.dart](backend/lib/src/application/sync/sync_fsm.dart) e [backend/test/sync_fsm_test.dart](backend/test/sync_fsm_test.dart) |
| M1.5 | SQLCipher (local) | Implementado | [apps/patient/lib/core/database/encrypted_database.dart](apps/patient/lib/core/database/encrypted_database.dart) e [apps/acs/lib/core/database/encrypted_database.dart](apps/acs/lib/core/database/encrypted_database.dart) |

## O que já está pronto - Fase 1

### M1.1 - Stack local em containers

A infraestrutura local já foi criada em [docker-compose.yml](docker-compose.yml):

- PostgreSQL 15
- Mosquitto
- Backend Dart (serviço nomeado `serverpod` no compose por legado, mas sem o framework em uso)
- Traefik

Esse componente atende ao critério do PRD de subir a stack completa em ambiente local via Docker Compose.

### M1.2 - CI básica

A pipeline de integração contínua foi criada e evoluída em [.github/workflows/ci.yml](.github/workflows/ci.yml):

- backend: provisiona PostgreSQL e Mosquitto, aplica as migrações e o seed de desenvolvimento, executa `dart analyze` e `dart test`
- build da imagem Docker do backend: valida que o `Dockerfile` multi-stage builda, sem publicar a imagem
- app paciente: `flutter analyze` + `flutter test`
- app ACS: `flutter analyze` + `flutter test`

Isso atende ao requisito do PRD de rodar lint e testes em GitHub Actions e agora cobre também a validação do back-end com o stack local do SinalACS. Ver a seção "Preparação de deploy" mais abaixo para o detalhe de quando/por que o passo de seed e o job de build Docker foram adicionados.

### M1.3 - Motor de triagem

O motor de classificação de risco foi implementado em [backend/lib/src/application/triage/triage_engine.dart](backend/lib/src/application/triage/triage_engine.dart).

A lógica é determinística e mapeia sinais clínicos para risco vermelho, amarelo ou verde, em linha com a intenção do PRD.

Também há testes específicos em [backend/test/triage_engine_test.dart](backend/test/triage_engine_test.dart), demonstrando a validação do comportamento principal.

### M1.4 - FSM de sincronização

A máquina de estados de sincronização foi implementada em [backend/lib/src/application/sync/sync_fsm.dart](backend/lib/src/application/sync/sync_fsm.dart).

Ela cobre os estados principais de sincronização offline-first, incluindo:

- idle
- localWrite
- queued
- syncing
- conflict
- synced
- error

Os cenários de transição e conflito foram validados em [backend/test/sync_fsm_test.dart](backend/test/sync_fsm_test.dart).

### M1.5 - Criptografia local com SQLCipher

A camada de banco local criptografado foi adicionada em:

- [apps/patient/lib/core/database/encrypted_database.dart](apps/patient/lib/core/database/encrypted_database.dart)
- [apps/acs/lib/core/database/encrypted_database.dart](apps/acs/lib/core/database/encrypted_database.dart)

A implementação usa SQLCipher para plataformas móveis e fallback FFI para ambientes de teste/VM, preservando a exigência de proteção de dados sensíveis em repouso.

## Milestones Técnicos - Fase 2

| Milestone | Entregável | Status | Evidência |
|---|---|---|---|
| M2.1 | App Paciente - MVP | Implementado | [apps/patient/lib/app/app.dart](apps/patient/lib/app/app.dart) com login, triagem e status do paciente |
| M2.2 | App ACS - MVP | Implementado | [apps/acs/lib/app/app.dart](apps/acs/lib/app/app.dart) com login, dashboard, territorialização e registro de visita |
| M2.3 | MQTT com TLS | Parcialmente implementado | [apps/acs/lib/core/services/mqtt_secure_client.dart](apps/acs/lib/core/services/mqtt_secure_client.dart) adiciona configuração segura e payload de alerta com TLS/WSS e teste em [apps/acs/test/mqtt_secure_client_test.dart](apps/acs/test/mqtt_secure_client_test.dart) |
| M2.4 | Sincronização Offline-First | Implementado | [apps/acs/lib/core/services/offline_visit_queue.dart](apps/acs/lib/core/services/offline_visit_queue.dart) com lote, retry e conflito, validado em [apps/acs/test/login_flow_test.dart](apps/acs/test/login_flow_test.dart) |
| M2.5 | Testes de Caos (Toxiproxy) | Implementado | [apps/acs/lib/core/services/network_chaos_simulator.dart](apps/acs/lib/core/services/network_chaos_simulator.dart) e [apps/acs/test/network_chaos_test.dart](apps/acs/test/network_chaos_test.dart) simulam latência, jitter e retry em cenários de falha |
| M2.6 | Testes de Usabilidade | Implementado | [apps/acs/test/login_flow_test.dart](apps/acs/test/login_flow_test.dart) e [apps/patient/test/patient_app_mvp_test.dart](apps/patient/test/patient_app_mvp_test.dart) validam labels semânticas e área mínima de toque para os principais botões |

## O que já está pronto - Fase 2

### M2.1 - App Paciente - MVP

O fluxo do paciente foi implementado em [apps/patient/lib/app/app.dart](apps/patient/lib/app/app.dart):

- login inicial do paciente
- triagem estruturada com opções de sintomas
- cálculo determinístico de risco
- tela de status da solicitação

Esse MVP atende ao requisito do PRD de coleta de sintomas e classificação de risco com lógica fechada, ainda sem integração de backend ou envio real via MQTT.

### M2.2 - App ACS - MVP

O app ACS foi implementado com fluxo funcional em [apps/acs/lib/app/app.dart](apps/acs/lib/app/app.dart):

- login institucional
- dashboard de priorização
- microárea / territorialização
- registro de visita em tela específica
- cartão visual de priorização por risco

Esse é o MVP do ACS conforme o escopo do PRD, ainda sem integração real com backend, autenticação institucional real, dados dinâmicos vindos do servidor ou sincronização central completa.

### M2.3 - MQTT com TLS e ciclo de alerta vermelho

Foi adicionada a camada de transporte MQTT segura em [apps/acs/lib/core/services/mqtt_secure_client.dart](apps/acs/lib/core/services/mqtt_secure_client.dart):

- configuração com TLS/WSS
- tópico por microárea
- payload de alerta com identificadores e localizações
- payload de confirmação de recebimento (ACK) do ACS
- parser seguro para rejeitar mensagens incompatíveis ou malformadas

No backend, a cadeia de alerta foi validada em [backend/lib/src/application/alerts/red_alert_service.dart](backend/lib/src/application/alerts/red_alert_service.dart), [backend/lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart](backend/lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart) e [backend/lib/src/domain/entities/alert_delivery.dart](backend/lib/src/domain/entities/alert_delivery.dart), com testes em [backend/test/red_alert_service_test.dart](backend/test/red_alert_service_test.dart), [backend/test/red_alert_lifecycle_test.dart](backend/test/red_alert_lifecycle_test.dart) e [backend/test/red_alert_http_integration_test.dart](backend/test/red_alert_http_integration_test.dart).

Essa implementação cobre o contrato real de entrega de alerta vermelho e confirmação de ACK em ambiente local, mas ainda não substitui autenticação mTLS real nem integração com infraestrutura de produção.

### M2.4 - Sincronização Offline-First

A fila local de visitas foi evoluída em [apps/acs/lib/core/services/offline_visit_queue.dart](apps/acs/lib/core/services/offline_visit_queue.dart):

- registro de visita em estado pendente
- lote de sincronização com resposta explícita
- retry de reprocessamento em fila
- detecção de conflito em payloads divergentes
- contagem de pendentes, sincronizados e conflitos

A validação foi incluída em [apps/acs/test/login_flow_test.dart](apps/acs/test/login_flow_test.dart), cobrindo o fluxo de sucesso e o caso de conflito com reprocessamento.

### M2.5 - Testes de Caos

Foi adicionada a simulação de degradação de rede em [apps/acs/lib/core/services/network_chaos_simulator.dart](apps/acs/lib/core/services/network_chaos_simulator.dart):

- latência artificial
- jitter controlado
- perda de pacote
- particionamento de rede
- sinalização explícita de retry

Os cenários de falha foram validados em [apps/acs/test/network_chaos_test.dart](apps/acs/test/network_chaos_test.dart), cobrindo os casos críticos de rede instável e retry.

### M2.6 - Testes de Usabilidade e Acessibilidade

Foi implementada a validação de UX básica em [apps/acs/test/login_flow_test.dart](apps/acs/test/login_flow_test.dart) e [apps/patient/test/patient_app_mvp_test.dart](apps/patient/test/patient_app_mvp_test.dart):

- rótulos semânticos para leitores de tela
- mínimo de 48x48 dp nos principais botões de ação
- manutenção do fluxo principal logo após a validação de acessibilidade

O app também foi ajustado para expor essas metas corretamente em [apps/acs/lib/app/app.dart](apps/acs/lib/app/app.dart) e [apps/patient/lib/app/app.dart](apps/patient/lib/app/app.dart).

## Preparação de deploy — piloto em serviços free-tier (backend)

Este trabalho é complementar às Fases 1 e 2 e **não corresponde ao milestone
M3.1 do PRD** ("Deploy em Produção (Pulumi)" — infraestrutura imutável
provisionada em VPS). É um caminho mais leve e gratuito para colocar o
backend no ar como piloto/demo, resolvendo bloqueadores técnicos que
impediam qualquer hospedagem free-tier de rodar o backend hoje. Runbook
completo em [backend/DEPLOY.md](backend/DEPLOY.md).

| Item | Entregável | Status | Evidência |
|---|---|---|---|
| Porta configurável | Leitura de `PORT` do ambiente, com fallback 8080 | Implementado | [backend/bin/server.dart](backend/bin/server.dart) |
| Boot desacoplado do MQTT | Servidor HTTP passa a aceitar requisições mesmo com o broker indisponível no momento do deploy | Implementado | [backend/bin/server.dart](backend/bin/server.dart) |
| Reconexão MQTT com backoff | Retry exponencial (2s a 60s) e correção do client-id fixo que causava colisão em redeploys | Implementado | [backend/lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart](backend/lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart) |
| Resposta controlada quando o MQTT está fora do ar | `POST /v1/alerts/red` retorna 503 em vez de derrubar o processo | Implementado | [backend/bin/server.dart](backend/bin/server.dart) |
| SSL na conexão PostgreSQL | `useSSL: true` por padrão, com opção `?sslmode=disable` para desenvolvimento local | Implementado | [backend/lib/src/infrastructure/database/postgres_alert_store.dart](backend/lib/src/infrastructure/database/postgres_alert_store.dart) |
| `/health` com diagnóstico | Corpo da resposta passa a incluir `mqtt_connected` e `db_connected` | Implementado | [backend/bin/server.dart](backend/bin/server.dart) |
| Dockerfile multi-stage (AOT) | Build com `dart compile exe`, imagem runtime mínima, usuário non-root e `HEALTHCHECK` | Implementado | [backend/Dockerfile](backend/Dockerfile) |
| Remoção de dependência morta | `serverpod` removido do `pubspec.yaml` (não havia nenhum import real no código) | Implementado | [backend/pubspec.yaml](backend/pubspec.yaml) |
| `JWT_SECRET` obrigatório em produção | Falha rápida no boot quando `APP_ENV=production` e o segredo não foi definido, em vez do fallback inseguro silencioso | Implementado | [backend/lib/src/config/app_config.dart](backend/lib/src/config/app_config.dart) |
| Gate do dev-login | `/v1/auth/development/login` responde 404 a menos que `ENABLE_DEV_LOGIN=true` seja definido explicitamente | Implementado | [backend/bin/server.dart](backend/bin/server.dart) |
| Validação do build Docker na CI | Novo job builda a imagem multi-stage a cada push/PR | Implementado | [.github/workflows/ci.yml](.github/workflows/ci.yml) |
| Correção de gap na CI | A CI nunca aplicava o seed de dados antes de rodar os testes, o que fazia o teste de integração de alerta vermelho falhar por violação de chave estrangeira; corrigido aplicando o seed no mesmo passo das migrações | Implementado | [.github/workflows/ci.yml](.github/workflows/ci.yml) |
| Documentação do piloto free-tier | Passo a passo de provisionamento (Render, Neon, HiveMQ Cloud) e limitações conhecidas | Implementado | [backend/DEPLOY.md](backend/DEPLOY.md), seção "Deploy" do [README.md](README.md) |

### Verificação realizada

Como o ambiente de desenvolvimento não tinha o Dart SDK instalado, a
verificação foi feita via Docker, reproduzindo o setup da CI:

- Build da imagem multi-stage concluído com sucesso (`docker build -f backend/Dockerfile backend`), incluindo a compilação AOT via `dart compile exe`.
- `dart analyze` sem nenhum problema encontrado.
- Suíte completa de testes (`dart test`) passando — 18/18, incluindo o teste de integração HTTP real (`red_alert_http_integration_test.dart`) contra PostgreSQL e Mosquitto reais em containers, cobrindo login, criação de alerta vermelho e ACK via HTTP.
- Container rodando com `PORT` dinâmico e broker MQTT inexistente: `/health` respondeu 200 com `mqtt_connected: false` e `db_connected: true`, sem travar o boot; `POST /v1/alerts/red` retornou 503 corretamente.
- Boot com `APP_ENV=production` e sem `JWT_SECRET`: processo falhou imediatamente com mensagem clara, como esperado.
- `/v1/auth/development/login` sem `ENABLE_DEV_LOGIN`: respondeu 404, confirmando o gate.

### O que ainda falta para este piloto ir ao ar

O provisionamento em si (criar as contas/recursos no Render, Neon e HiveMQ
Cloud e configurar os secrets) é manual e está documentado em
[backend/DEPLOY.md](backend/DEPLOY.md), mas ainda não foi executado.

### Relação com o PRD

Este trabalho reduz risco técnico e serve de base para o M3.1 real, mas
**não substitui** nenhum dos requisitos formais de produção: provisionamento
imutável via Pulumi em VPS, redes privadas, TLS 1.3 ponta a ponta, ACLs MQTT
dinâmicas por microárea, autenticação institucional real com RBAC,
observabilidade completa (OpenTelemetry/Prometheus/Grafana — M3.2) e revisão
de LGPD antes de qualquer piloto com pacientes reais (M3.4). O dev-login
continua sendo o único mecanismo de autenticação do ambiente piloto e não
deve ser usado com dados reais de pacientes.

## Observações importantes

- A Fase 1 está concluída e documentada no repositório.
- A Fase 2 já possui um fluxo funcional de alerta vermelho validado em ambiente local: autenticação, idempotência, publicação no broker, ACK e ciclo completo HTTP via backend.
- O nível de maturidade atual é de protótipo funcional com integração real em stack local, e não de produto pronto para produção.
- Ainda permanecem pendentes itens de produção real, como autenticação institucional real, mTLS/segurança de broker em ambiente de produção, sincronização central completa e integrações com dados reais de saúde e geolocalização.

## Status final do checklist

### Fase 1

- [x] M1.1 - Docker Compose local
- [x] M1.2 - CI básica
- [x] M1.3 - Motor de triagem
- [x] M1.4 - FSM de sincronização
- [x] M1.5 - SQLCipher local

### Fase 2

- [x] M2.1 - App Paciente - MVP
- [x] M2.2 - App ACS - MVP
- [x] M2.3 - MQTT com TLS + ciclo de alerta vermelho validado em stack local
- [x] M2.4 - Sincronização Offline-First
- [x] M2.5 - Testes de Caos
- [x] M2.6 - Testes de Usabilidade

Atenção: o código atual já valida a operação crítica de alerta vermelho em ambiente local com backend real e stack Docker, mas ainda não substitui produção operacional com autenticação institucional real, broker com mTLS e integração completa com dados de saúde e gestão territorial.

---

## Migração para Serverpod

Trabalho posterior às Fases 1 e 2, fora da numeração M1.x/M2.x/M3.x do PRD. O
[PRD](spec/PRD_system.md) e o [spec/stack.md](spec/stack.md) registravam
Serverpod como decisão original de stack, justificada por "isomorfismo Dart:
type-safety end-to-end entre Flutter e o backend". A decisão não havia sido
implementada — o servidor era um `HttpServer` do `dart:io` com roteamento
manual. Esta migração a executou.

### O que motivou

O custo da dívida era mensurável. `RiskLevel` é o nó de maior betweenness do
sistema, ligando as entidades Paciente, Alerta, Sessão de Triagem e Visita — mas
o tipo não sobrevivia à fronteira. Existiam quatro grafias independentes do mesmo
conceito de três valores (`red` no enum do backend, `'VERMELHO'` na fila offline
do ACS, `'Risco: Vermelho'` na interface do paciente, e o valor no fio MQTT),
sustentadas só por convenção. O cliente gerado pelo Serverpod é o mecanismo que
fecha esse buraco.

### Estado atual

| Item | Situação |
|---|---|
| Servidor | Serverpod 3.4.13, workspace Dart em `backend/` com `sinalacs_server` e `sinalacs_client` |
| Schema | 11 tabelas como modelos `.spy.yaml`, mais `alert_idempotency_keys`; migrações geradas e aplicadas pelo servidor no boot |
| Endpoints | RPC: `alerts.createRedAlert`, `alerts.acknowledge`, `auth.developmentLogin`, `health.check`, `triage.evaluate` |
| Testes | 25 verdes — 16 unitários herméticos e 9 de integração sobre o harness `withServerpod` |
| Cliente gerado | Publicado em `backend/sinalacs_client`, **ainda não consumido pelos apps Flutter** |

### Decisões de schema que valem registro

O ORM do Serverpod exige chave primária de coluna única chamada `id`, e só sabe
referenciar o `id` do pai. Isso obrigou duas mudanças:

- `patients` e `acs` usavam herança por chave compartilhada, com `user_id` sendo
  PK e FK ao mesmo tempo. O `id` dessas tabelas passou a ser **o próprio UUID do
  usuário**, o que preservou a semântica de `patient_id`, manteve os UUIDs fixos
  do seed e recuperou 9 das 11 foreign keys. As duas que não voltam são
  `patients.id → users.id` e `acs.id → users.id`: o Serverpod não expressa "meu
  id também é chave estrangeira".
- `alert_deliveries` tinha PK composta `(alert_id, acs_id)`, não suportada.
  Ganhou `id` próprio, com o par virando índice UNIQUE — mesma garantia de
  unicidade.

Divergências aceitas e registradas: 17 colunas passaram de `TIMESTAMPTZ` para
`timestamp without time zone`, 3 de `jsonb` para `json`, e as PKs usam
`gen_random_uuid()` v4.

### Defeitos corrigidos no caminho

- **Identificador de alerta que colidia.** O gerador derivava o id do relógio
  (`'00000000-0000-4000-8000-' + microssegundos % 1e12`), colidindo a cada ~11,6
  dias e entre requisições no mesmo microssegundo. Passou a UUID v4. Colisão de
  identificador é uma forma silenciosa de perder um alerta vermelho (INV-03).
- **Idempotência volátil.** Era um `Map` em memória: sumia no restart e não valia
  entre instâncias. Passou à tabela `alert_idempotency_keys`, verificada com
  reinício de servidor entre as duas chamadas.
- **Linha órfã.** Uma falha de publicação deixava no banco um alerta `pending`
  nunca publicado, e ainda consumia a chave de idempotência. `createRedAlert`
  passou a rodar em transação: se a publicação falha, nada fica gravado e o
  cliente pode retentar de verdade.
- **Vazamento na reconexão MQTT.** Cada reconexão deixava um listener vivo no
  cliente anterior, e uma tempestade de reconexão disparava o callback de ACK em
  duplicata. A subscription anterior passou a ser cancelada antes de assumir a
  nova.
- **ACK assíncrono não aguardado.** O callback era invocado sem `await`, então
  falha ao registrar um ACK virava erro assíncrono não tratado — um ACK perdido
  em silêncio deixa um alerta eternamente pendente.

### Infraestrutura

O serviço one-shot `database-init` foi removido: seu guard era tudo-ou-nada
sobre a existência de `public.users` e pulava em silêncio um banco parcialmente
migrado. As migrações passaram a ser aplicadas pelo servidor no boot, via
`SERVERPOD_APPLY_MIGRATIONS`. A configuração de banco deixou de ser
`DATABASE_URL` e passou às variáveis `SERVERPOD_DATABASE_*`.

O módulo `serverpod_auth_idp_server`, que veio no template e nenhum endpoint
usava, foi removido — a migração-base caiu de 86 para 50 tabelas.

O backend `dart:io` foi removido da árvore; o histórico do git o preserva.

### O que continua em aberto

- **Autenticação institucional.** O acesso segue sendo o token HMAC de
  desenvolvimento, gated por `ENABLE_DEV_LOGIN`. Gov.br e matrícula da
  Secretaria continuam não implementados.
- **Apps Flutter não consomem o cliente gerado.** `sinalacs_client` existe e é
  publicado, mas `apps/acs` e `apps/patient` seguem com dados locais — e por isso
  o `RiskLevel` ainda não atravessa a fronteira na prática.
- **Risco residual de entrega.** MQTT não participa da transação: se a publicação
  tem êxito e o commit falha, o alerta chega ao ACS sem linha no banco. Raro e
  erra para o lado seguro quanto à INV-03; fechar por completo exigiria outbox
  pattern.
- **Deploy não executado.** O runbook em [backend/DEPLOY.md](backend/DEPLOY.md)
  foi reescrito para Serverpod, mas continua sem ter sido rodado.
