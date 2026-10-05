# Progresso das Fases 1 e 2 - Milestones Técnicos

Este documento consolida o que foi implementado no repositório em relação às fases 1 e 2 da Seção 6.2, "Milestones Técnicos", do PRD.

> **Nota de leitura — o backend migrou para Serverpod.** As entradas M1.x e M2.x
> abaixo registram o que era verdade quando foram escritas, e por isso não foram
> reescritas: elas descrevem o servidor `dart:io` roteado à mão, e seus links
> para `backend/bin/`, `backend/lib/` e `backend/test/` apontam para código que
> **não existe mais na árvore atual** — só no histórico do git. O mesmo vale para
> a seção de preparação de deploy, escrita para aquele servidor. Pela mesma
> razão, contagens pontuais citadas nessas entradas (jobs de CI, número de
> testes) refletem o momento em que cada trecho foi escrito, não o estado atual
> do [.github/workflows/ci.yml](.github/workflows/ci.yml) ou da suíte de testes.
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
| M1.5 | SQLCipher (local) | Implementado **no ACS** | [apps/acs/lib/core/database/encrypted_database.dart](apps/acs/lib/core/database/encrypted_database.dart) e [apps/acs/lib/core/database/sqlcipher_visit_store.dart](apps/acs/lib/core/database/sqlcipher_visit_store.dart). **O app do paciente não usa SQLCipher, de propósito**: os dois stores locais dele são [lembretes](apps/patient/lib/core/reminders/sqflite_reminder_store.dart) e [preferências de consentimento](apps/patient/lib/core/consent/sqflite_consent_preferences.dart), sobre `sqflite` puro — horário e texto livre curto não são dado de saúde, e o app do paciente não persiste nada clínico. Esta linha continuava linkando um `apps/patient/lib/core/database/encrypted_database.dart` que **foi removido** — era código morto, sem chamador, que afirmava uma garantia que não entregava (ver a "Correção de registro" da seção M1.5 abaixo, que já dizia isso desde então; a tabela é que ficou para trás). |

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

> **Correção de registro.** Esta entrada afirmava que o milestone estava
> concluído porque a classe `EncryptedLocalDatabase` existia. Ela existia, mas
> **nenhum código de produção a chamava**: o único chamador em todo o
> repositório era o teste unitário, com uma passphrase literal. Pior, o
> "fallback FFI para ambientes de teste/VM" abria o banco **sem criptografia
> nenhuma**, e era justamente o caminho que o CI (Linux) exercitava — o teste
> chamado "deve abrir banco criptografado" não provava nada do que o nome
> prometia. O repositório declarava uma propriedade de segurança que não tinha.

O milestone passou a ser real:

- [apps/acs/lib/core/security/database_key_store.dart](apps/acs/lib/core/security/database_key_store.dart) — a chave de 256 bits vive no Android Keystore / iOS Keychain, nunca no código.
- [apps/acs/lib/core/database/encrypted_database.dart](apps/acs/lib/core/database/encrypted_database.dart) — fora de Android/iOS a abertura **lança**, a menos que se passe `allowUnencryptedForTesting`, flag de nome deliberadamente constrangedor que só os testes de VM usam.
- [apps/acs/lib/core/database/sqlcipher_visit_store.dart](apps/acs/lib/core/database/sqlcipher_visit_store.dart) — o consumidor real: a fila de visitas offline, que antes vivia só em memória e perdia o trabalho de campo ao fechar o app.
- [apps/acs/integration_test/encrypted_storage_test.dart](apps/acs/integration_test/encrypted_storage_test.dart) — a prova, **em dispositivo**: lê o arquivo cru e afirma que ele não começa com `SQLite format 3` nem contém o conteúdo da visita. Verificado em emulador, inclusive por falsificação (removendo o SQLCipher, o teste falha).

A cópia do app do paciente foi removida: era código morto, sem chamador, que
afirmava uma garantia que não entregava.

Permanece fora: chave derivada de PIN/biometria (PRD 4.2.3) — não há fluxo de PIN
nos apps, e a interface de custódia aceita esse segundo fator depois sem migrar
dados.

## Milestones Técnicos - Fase 2

| Milestone | Entregável | Status | Evidência |
|---|---|---|---|
| M2.1 | App Paciente - MVP | Implementado | [apps/patient/lib/app/app.dart](apps/patient/lib/app/app.dart) com login, triagem e status do paciente |
| M2.2 | App ACS - MVP | Implementado | [apps/acs/lib/app/app.dart](apps/acs/lib/app/app.dart) com login, dashboard, territorialização e registro de visita |
| M2.3 | MQTT com TLS | Parcialmente implementado | [apps/acs/lib/core/services/mqtt_secure_client.dart](apps/acs/lib/core/services/mqtt_secure_client.dart) adiciona configuração segura e payload de alerta com TLS/WSS e teste em [apps/acs/test/mqtt_secure_client_test.dart](apps/acs/test/mqtt_secure_client_test.dart) |
| M2.4 | Sincronização Offline-First | Implementado | [apps/acs/lib/core/services/offline_visit_queue.dart](apps/acs/lib/core/services/offline_visit_queue.dart) com lote, retry e conflito, validado em [apps/acs/test/login_flow_test.dart](apps/acs/test/login_flow_test.dart) |
| M2.5 | Testes de Caos (Toxiproxy) | Implementado | [apps/acs/lib/core/services/network_chaos_simulator.dart](apps/acs/lib/core/services/network_chaos_simulator.dart) e [apps/acs/test/network_chaos_test.dart](apps/acs/test/network_chaos_test.dart) simulam latência, jitter e retry em cenários de falha |
| M2.6 | Testes de Usabilidade e Acessibilidade | Implementado | [spec/ux_accessibility_assessment.md](spec/ux_accessibility_assessment.md) — matriz de contraste WCAG 1.4.3 determinística (`contrast_tokens_test.dart`), `meetsGuideline` de contraste/alvo de toque e `liveRegion` (SC 4.1.3) em [apps/acs/test/login_flow_test.dart](apps/acs/test/login_flow_test.dart) e [apps/patient/test/patient_app_mvp_test.dart](apps/patient/test/patient_app_mvp_test.dart), validado ponta a ponta no emulador contra o backend e o broker reais |

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

#### A fila passou a sair do aparelho

O `BackendVisitSynchronizer` existia e era testado, mas **não era injetado**: o app
montava a fila sem ele, `sync()` caía no ramo sem remetente e devolvia erro. Na
prática as visitas nunca subiam, e a retenção — `SqlCipherVisitStore.save()` apaga
do disco tudo que saiu da lista de pendentes — nunca disparava em produção.

Nenhum teste podia ver isso: a UI só é testável com a fila injetada, então a
montagem real nunca era exercitada. A fiação foi extraída para
[apps/acs/lib/core/services/visit_queue_factory.dart](apps/acs/lib/core/services/visit_queue_factory.dart)
e ganhou teste próprio.

Para ligar o sincronizador, o registro passou a guardar `patientId` em vez de
`patientName`. O rótulo antigo era `'Paciente ' + 8 dos 32 dígitos do UUID`:
irreversível, então o servidor recusaria a visita por identificador inválido — e
era texto legível sobre a pessoa num disco que não precisava dele. Agora o
identificador vai ao banco e o rótulo é montado na tela (minimização,
LGPD-RF01). Consequência de produto: a aba "Visita" sem alerta selecionado não
grava mais, porque sem alerta não há paciente.

O schema local subiu para v2 (`patient_id`), com `onUpgrade` que **recria** a
tabela — nem `local_queue` nem a `offline_visits` v1 guardavam o UUID. Isso perde
visitas pendentes gravadas antes da atualização, que de qualquer forma o servidor
recusaria. **A partir do primeiro release real, essa migração precisa preservar
dados.**

A tela ganhou contador de pendentes/conflitos e o botão "Sincronizar agora" — o
gatilho é manual, para o ACS decidir quando gastar dados em campo.

Dois defeitos vizinhos apareceram no caminho e foram corrigidos: `sync()`
devolvia `synced` quando o servidor recusava uma visita (o status `error` caía no
ramo `default`), o que a prendia na fila em silêncio; e `visits.sync` reportava
"este alerta não pertence à sua microárea" para erro de sessão.

#### O app passou a dizer o que está errado

Dois defeitos vizinhos, com a mesma forma: o app sabia e não contava.

O painel tinha **um slot de banner para dois estados** (`_feedError ?? _storageError`).
Em campo o broker e o armazenamento caem juntos, e o `??` sempre mostrava o do
broker: o ACS via "sem conexão com a central" e nunca descobria que as visitas
do dia não estavam sendo salvas. O subtítulo era fixo, então quando o banner
exibido era o de disco ele ainda afirmava algo sobre alertas. E o aviso de
persistência era calculado uma vez, no `initState` — falhas posteriores de
gravação ficavam invisíveis. Agora são dois banners independentes, cada um com
seu texto, e o de persistência é lido do estado corrente da fila a cada build.
A tela de visita ganhou o mesmo aviso inline: é onde a pessoa acabou de gravar.

Os avisos de infraestrutura passaram a usar o azul de destaque. `docs/telas-acs.md`
reserva a cor para a gravidade clínica, e um card vermelho de falha técnica
competia com o alerta vermelho de um paciente na mesma lista.

O segundo defeito: **`SINALACS_MQTT_PASSWORD` tinha um default que nunca
funcionou**. O broker cria `acs-area-12` com `MQTT_ACS_PASSWORD`, segredo
aleatório por máquina, então nenhum valor embutido no código poderia acertá-lo —
e toda a documentação mandava rodar `flutter run` sem `--dart-define` nenhum. O
resultado era um app que nunca recebia alerta e dizia apenas "sem conexão".

- O default saiu. Vazio virou estado detectável, e a tela diz que o aplicativo
  foi compilado sem a senha.
- `scripts/dev/run_acs.sh` lê o `.env`, roda o `sync_dev_ca.sh` (a CA é asset
  gitignored que o build exige) e preenche os quatro dart-defines.
- As falhas do feed viraram `AlertFeedFailure` classificada. Senha ausente, CA
  ausente, credencial recusada e broker inalcançável eram a mesma frase; o
  `mqtt_client` já trazia o motivo no CONNACK e o código o descartava, junto com
  o próprio erro, que agora vai para `dart:developer`.

Verificado no emulador, os quatro caminhos: compilado sem senha, compilado pelo
script, senha errada e broker parado — cada um com sua mensagem.

#### O app desistia do broker na primeira tentativa

`_connectFeed()` rodava **uma vez**, no `initState`. Se falhasse, o app nunca
mais tentava — o banner ficava na tela até alguém fechar e reabrir o
aplicativo. O `autoReconnect` do `mqtt_client` não cobria isso: ele só age
**depois** de uma conexão bem-sucedida, e as duas rotas de erro do cliente
chamam `disconnect()`, que o desliga de propósito para o cliente não ficar
órfão tentando para sempre.

Em campo isso significava um ACS que abre o app na zona rural sem sinal ficar
sem alerta pelo resto do turno, mesmo com o sinal voltando cinco minutos
depois — e como a sessão MQTT é persistente, o broker estava guardando esses
alertas com QoS 1 o tempo todo, só esperando uma conexão que nunca vinha.

`AcsHomeShell` passou a retentar sozinho quando a falha é **transitória**
(broker inalcançável, ou `brokerUnavailable` do CONNACK — nunca senha ausente,
CA ausente, ou credencial/identificador recusado, que não mudam sozinhos):
backoff de 2s a 60s em [reconnect_schedule.dart](apps/acs/lib/core/services/reconnect_schedule.dart),
os mesmos valores do `MqttAlertDispatcher` do backend. O banner ganhou "Tentar
agora" para quem já vê o sinal voltar, e voltar do segundo plano dispara uma
tentativa imediata — é o gatilho que mais importa, porque o sinal costuma
voltar com a tela apagada.

Defeito vizinho, a outra metade do mesmo problema: o chip do cabeçalho também
era escrito uma única vez. Uma queda **depois** de uma conexão bem-sucedida
nunca chegava a ele, que continuava dizendo "em linha" para sempre enquanto o
`autoReconnect` trabalhava por baixo em silêncio. `AlertFeed.onConnectionChanged`
subiu para a interface como campo mutável para o shell poder assinar mudanças
de estado a qualquer momento, não só no retorno do `start()`.

#### `flutter build apk` puro ainda entregava um APK que nunca conectava

Os dois defeitos acima foram fechados, mas sobrava uma lacuna: mesmo sem
`SINALACS_MQTT_PASSWORD`, `flutter build apk` compilava normalmente. O defeito
só se denunciava em tempo de execução, pelo banner "compilado sem a senha" —
tarde demais para quem já distribuiu o APK.

[apps/acs/android/app/build.gradle.kts](apps/acs/android/app/build.gradle.kts)
ganhou uma guarda em `doFirst` das tarefas `compileFlutterBuild*`: decodifica a
propriedade `dart-defines` (o Flutter Gradle Plugin já lê essa mesma
propriedade) e falha, com o comando certo, se `SINALACS_MQTT_PASSWORD` não
estiver lá. Precisou ser `doFirst` de tarefa, e não bloco de configuração —
senão dispararia em todo `gradlew`, inclusive o sync do Android Studio, que não
passa define nenhum. Escotilha explícita para quem quer de propósito um APK
sem senha (por exemplo, para reproduzir o banner):
`-Psinalacs.allowMissingMqttPassword=true`, no molde constrangedor-de-digitar
de `allowUnencryptedForTesting`.

Aproveitado para tirar a senha do `argv`: `run_acs.sh` passou de `--dart-define`
para `--dart-define-from-file`, com um arquivo temporário (`mktemp`, 0600) que
um `trap` apaga ao sair. A troca exigiu remover o `exec` das duas chamadas ao
`flutter` — `exec` substitui o processo do shell, e o `trap` nunca rodaria,
deixando o arquivo com a senha esquecido em `/tmp` depois de cada execução.
`scripts/qa/e2e.sh` continua passando a senha por `argv`: aquele caminho roda
`flutter test`/`dart run`, não `flutter build`, e não passa pela guarda.

#### O registro de visitas não tinha caminho algum na operação real

`alerts.createRedAlert` é o único produtor de alertas, e crava sempre
`riskLevel: 'red'` — emergência, com SAMU. O cartão do painel tinha **um**
botão, mutuamente exclusivo entre "Acionar SAMU / Atender" e "Iniciar rota de
visita" conforme o risco; como só chega vermelho, o segundo era código morto em
produção — só alcançável injetando um alerta amarelo à mão no broker. Com
`patientId` obrigatório desde a fiação da sincronização, e sem nenhum alerta
não-vermelho para habilitar o formulário, a aba "Visita" ficou inalcançável: o
PRD mede engajamento do ACS em **≥ 8 visitas/dia**, e visita de rotina — o
padrão de uso real — não tinha de onde partir.

Dois caminhos, não um. O reativo já tinha meio-caminho andado: a tela de
escalonamento ganhara, numa mudança anterior não documentada aqui, um segundo
botão "Iniciar rota de visita" (`Key('escalation_visit')`) com o aviso "a
visita é acompanhamento do caso e não substitui o acionamento do SAMU" — o ACS
aciona o SAMU primeiro, visita depois. Verificado que já funciona ponta a
ponta; nada mexido ali.

O que faltava era o de rotina: `patients.listMicroArea` (backend, novo) lista
os pacientes da microárea do ACS — a microárea vem do token, nunca de um
parâmetro, e a consulta é um JOIN em duas etapas
(`OrmPatientDirectoryStore`, `backend/sinalacs_server/lib/src/infrastructure/database/`)
porque `Patient` não guarda microárea: ela vive em `users`, e `Patient.id` É o
UUID do usuário. O payload é só nome e condições crônicas — o que
`spec/lgpd_design.md` autoriza para visita de rotina, nada além.
`VisitRegistrationScreen` ganhou o seletor (`Key('patient_picker')`): sem
alerta selecionado, busca por nome e uma lista; escolher libera o formulário
exatamente como um alerta faria. O nome vive só em memória, para o rótulo —
`OfflineVisitRecord` continua carregando apenas o UUID, mesma disciplina já
estabelecida para o caminho por alerta.

Dois furos adjacentes fechados no caminho, achados ao implementar o diretório:

- **Territorialização do sync, furo do INV-01.** `VisitSyncService` validava
  que o ACS é territorializado, mas nunca que o PACIENTE pertence ao mesmo
  território — qualquer UUID de paciente existente era aceito, de qualquer
  microárea. `VisitStore.microAreaOfPatient` fecha isso; a recusa é por visita
  (na época, `SyncStatus.error` — virou `SyncStatus.rejected`, terminal, numa
  mudança posterior, ver abaixo), não descarta o resto do lote.
- **`audit_logs` era tabela morta.** Existia desde a migração-base,
  documentada como "trilha de auditoria de acesso a dados sensíveis
  append-only", e nenhuma linha de código escrevia nela — este PR introduzia a
  primeira leitura em massa de PHI do sistema. `AuditTrail`
  (`backend/sinalacs_server/lib/src/application/audit/`) liga os dois pontos
  que este PR cria: a leitura da lista de pacientes (evento, sem enumerar quem
  foi lido — listar recriaria o prontuário dentro do próprio log) e a recusa
  por território (com o UUID do paciente envolvido). `ipHash` nunca é IP em
  claro — SHA-256 sobre `request.remoteInfo`, que o próprio Serverpod já
  resolve corretamente atrás do Traefik (prefere `Forwarded`/`X-Forwarded-For`
  antes do endereço da conexão). A escrita é best-effort: uma trilha fora do ar
  não pode impedir o ACS de trabalhar, só faz o processo logar a falha. A
  assinatura em hash chain que `spec/lgpd_design.md` (LGPD-RT03) descreve
  continua não implementada, e os demais endpoints sensíveis (alertas, ack,
  triagem) ainda não escrevem na trilha.

Seed de desenvolvimento ganhou cinco pacientes sintéticos (nomes obviamente
fictícios) na microárea do ACS, mais um sexto fora dela — para o seletor ser
demonstrável e para provar territorialização sem precisar de outra stack de
teste.

Verificado no emulador, contra a stack local rodando de verdade: o seletor
lista os pacientes reais do Postgres; escolher um e sincronizar grava
`syncStatus: synced` no servidor; o arquivo do banco cifrado, puxado do
aparelho depois de gravar e sincronizar pelo seletor, não contém o nome em
nenhum ponto (nem o logcat); uma visita para paciente de outra microárea volta
como `error` (na época — ver abaixo) e grava a linha `denied_territory` em
`audit_logs`, sem tocar `visits`; o caminho por alerta (vermelho → SAMU →
escalonamento → visita) continua idêntico ao de antes desta mudança.

#### A cadeia de hash da trilha de auditoria, e a recusa que ficava presa na fila para sempre

Duas dívidas registradas explicitamente no PR anterior, fechadas nesta mudança.

**A cadeia de hash de `audit_logs` (LGPD-RT03).** A trilha ganhara escritores
no PR anterior, mas só fazia `insertRow` — qualquer um com acesso de escrita ao
Postgres editava ou apagava uma linha sem deixar rastro, o que não serve ao
não-repúdio que a spec promete. `audit_logs` ganhou três colunas: `sequence`
(posição, contígua, índice único), `previousHash` (o `entryHash` da linha
anterior, ou `AuditChain.genesisHash` — 64 zeros — na primeira) e `entryHash`
(HMAC-SHA256 do conteúdo da linha). A chave é um segredo PRÓPRIO
(`AUDIT_CHAIN_SECRET`), nunca derivado do `JWT_SECRET`: os dois precisam poder
rotacionar de forma independente, e SHA-256 sem chave não detectaria uma
reescrita completa por quem tem acesso de escrita ao banco — exatamente o
adversário que a §458 de `spec/lgpd_design.md` descreve.
`OrmAuditTrail.record` agora lê a última linha e insere a próxima dentro da
MESMA transação, sob `pg_advisory_xact_lock`, para duas gravações concorrentes
não lerem a mesma linha anterior e bifurcarem a cadeia. `AuditChainVerifier` (e
o `bin/audit_chain_check.dart` que o expõe como script) reconstrói a cadeia
inteira e detecta edição, remoção ou reordenação de qualquer linha — verificado
ao vivo: adulterar uma linha por `UPDATE` direto no Postgres faz o verificador
falhar exatamente na `sequence` afetada. Fora de escopo, registrado na spec: o
append-only em si não é imposto pelo banco (sem trigger/`REVOKE`) — a cadeia
*detecta* a violação, não a impede.

**Recusa definitiva presa na fila para sempre.** `VisitSyncService._syncOne`
colapsava seis motivos de falha distintos no mesmo `SyncStatus.error`, e
`OfflineVisitQueue._applyOutcomes` reenfileirava `error` incondicionalmente.
Para a recusa territorial isso era retentativa eterna garantida: a checagem de
território roda antes do lookup por `localId`, então o reenvio falha de forma
idêntica para sempre, e nada no aparelho explicava por quê. `SyncStatus` ganhou
`rejected`, terminal: localId vazio, UUID malformado, território incompatível e
visita de outro agente agora retornam `rejected` (só "paciente não encontrado"
continua `error` — pode ser cadastrado depois, é legitimamente retentável).
`SyncFsm` ganhou o estado espelhado, sem transição de saída. No aparelho,
`OfflineVisitRecord` ganhou `rejectionReason`; a fila ganhou uma quarta lista
(`_rejected`, ao lado de pendente/sincronizada/conflito) que sai da retentativa
mas continua no disco — `VisitStore.save` passou a persistir pendentes MAIS
recusadas, não só pendentes, senão a recusada sumiria do aparelho no instante
da recusa, antes de o ACS decidir. A tela ganhou o contador
(`Key('rejected_visits_count')`) e um botão de descarte com confirmação
(`Key('discard_rejected')`) — nada remove a recusada do aparelho sem essa
confirmação explícita. `encrypted_database.dart` foi de v3 a v4 com
`ALTER TABLE ... ADD COLUMN rejection_reason` — a primeira migração aditiva
desde que o schema existe; as anteriores (v1 → v2) recriavam a tabela porque o
app ainda não tinha tido release.

Verificação: 83 testes no backend (69 unit + 14 integração, incluindo a
gravação real de duas linhas encadeadas contra Postgres e a checagem do
`pg_advisory_xact_lock` — a cadeia de hash tem cobertura própria em
`test/unit/audit_chain_test.dart`, incluindo detecção de edição, remoção,
renumeração e segredo errado), 89 testes herméticos no app ACS (6 novos:
recusa saindo da fila sem reenviar, precedência sobre conflito, `discardRejected`,
persistência da recusada em disco, migração v3 → v4 preservando linhas, e o
fluxo completo de descarte com confirmação na tela).

### M2.5 - Testes de Caos

Foi adicionada a simulação de degradação de rede em [apps/acs/lib/core/services/network_chaos_simulator.dart](apps/acs/lib/core/services/network_chaos_simulator.dart):

- latência artificial
- jitter controlado
- perda de pacote
- particionamento de rede
- sinalização explícita de retry

Os cenários de falha foram validados em [apps/acs/test/network_chaos_test.dart](apps/acs/test/network_chaos_test.dart), cobrindo os casos críticos de rede instável e retry.

### M2.6 - Testes de Usabilidade e Acessibilidade

[spec/ux_accessibility_assessment.md](spec/ux_accessibility_assessment.md) documenta a auditoria
completa contra a baseline WCAG 2.1 AA do PRD (§4.3). A primeira versão do relatório media
contraste manualmente contra o fundo do `Scaffold`, mas texto de risco/status é renderizado
dentro de `Card` — produziu um falso positivo e deixou passar duas falhas piores (vermelho e azul
de preenchimento usados como cor de texto, abaixo de 4.5:1 sobre o card). A revisão trocou a
medição manual por uma matriz determinística
(`apps/{acs,patient}/test/contrast_tokens_test.dart`), corrigiu os tokens separando cor de
PREENCHIMENTO de cor de TEXTO (`redOnSurface`/`accentOnSurface` no ACS,
`dangerOnSurface`/`accentOnSurface` no paciente, em
[apps/acs/lib/app/acs_theme.dart](apps/acs/lib/app/acs_theme.dart) e
[apps/patient/lib/app/patient_theme.dart](apps/patient/lib/app/patient_theme.dart)), e adicionou:

- `meetsGuideline(textContrastGuideline/androidTapTargetGuideline/labeledTapTargetGuideline)` em
  [apps/acs/test/login_flow_test.dart](apps/acs/test/login_flow_test.dart) e
  [apps/patient/test/patient_app_mvp_test.dart](apps/patient/test/patient_app_mvp_test.dart)
- alvo de toque de 60x60 dp no botão "Ligar para o SAMU (192)", que não tinha `minimumSize`
  (default de 40dp de altura visual — a medição anterior de "48x52 dp" estava incorreta)
- `Semantics(liveRegion: true)` em sete pontos de status dinâmico (WCAG 4.1.3, critério ausente
  da avaliação original), incluindo a confirmação do alerta de emergência do paciente
- o cartão de alerta da fila do ACS passou a ser lido como uma frase única pelo leitor de tela,
  em vez de nós soltos

Validado ponta a ponta no emulador Android (`emulator-5554`): o app Paciente disparou um alerta de
emergência real contra o backend em Docker Compose, e o app ACS recebeu pelo broker MQTT/TLS real,
exibindo o novo contraste, o botão do SAMU no novo tamanho e o risco traduzido corretamente. Os 14
testes de integração em dispositivo de `apps/acs/integration_test/` (inclusive o que lê o arquivo
do banco criptografado) passam sobre o código revisado.

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
| Dockerfile multi-stage (AOT) | Build com `dart compile exe`, imagem runtime mínima, usuário non-root e `HEALTHCHECK` | Implementado | [backend/sinalacs_server/Dockerfile](backend/sinalacs_server/Dockerfile) |
| Remoção de dependência morta | `serverpod` removido do `pubspec.yaml` (não havia nenhum import real no código) | Implementado | [backend/pubspec.yaml](backend/pubspec.yaml) |
| `JWT_SECRET` obrigatório em produção | Falha rápida no boot quando `APP_ENV=production` e o segredo não foi definido, em vez do fallback inseguro silencioso | Implementado | [backend/lib/src/config/app_config.dart](backend/lib/src/config/app_config.dart) |
| Gate do dev-login | `/v1/auth/development/login` responde 404 a menos que `ENABLE_DEV_LOGIN=true` seja definido explicitamente | Implementado | [backend/bin/server.dart](backend/bin/server.dart) |
| Validação do build Docker na CI | Novo job builda a imagem multi-stage a cada push/PR | Implementado | [.github/workflows/ci.yml](.github/workflows/ci.yml) |
| Correção de gap na CI | A CI nunca aplicava o seed de dados antes de rodar os testes, o que fazia o teste de integração de alerta vermelho falhar por violação de chave estrangeira; corrigido aplicando o seed no mesmo passo das migrações | Implementado | [.github/workflows/ci.yml](.github/workflows/ci.yml) |
| Documentação do piloto free-tier | Passo a passo de provisionamento (Render, Neon, HiveMQ Cloud) e limitações conhecidas | Implementado | [backend/DEPLOY.md](backend/DEPLOY.md), seção "Deploy" do [README.md](README.md) |

### Verificação realizada

Como o ambiente de desenvolvimento não tinha o Dart SDK instalado, a
verificação foi feita via Docker, reproduzindo o setup da CI:

- Build da imagem multi-stage concluído com sucesso (`docker build -f backend/sinalacs_server/Dockerfile backend/sinalacs_server`), incluindo a compilação AOT via `dart compile exe`.
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
- [x] M1.5 - SQLCipher local (ver a correção de registro na seção M1.5)

### Fase 2

- [x] M2.1 - App Paciente - MVP
- [x] M2.2 - App ACS - MVP
- [x] M2.3 - MQTT com TLS + ciclo de alerta vermelho validado em stack local
- [x] M2.4 - Sincronização Offline-First
- [x] M2.5 - Testes de Caos
- [x] M2.6 - Testes de Usabilidade

Atenção: o código atual já valida a operação crítica de alerta vermelho em ambiente local com backend real e stack Docker, mas ainda não substitui produção operacional com autenticação institucional real, broker com mTLS e integração completa com dados de saúde e gestão territorial.

---

## Finalização do app ACS (2026-10-01)

Plano: `docs/superpowers/plans/2026-10-01-finalizacao-app-acs.md`. Medido no `emulator-5554`.

- **RF12 — permissão de localização.** O manifesto do ACS não declarava `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` (nem `INTERNET`, que só vinha de plugin): sem elas o GPS do check-in nunca chegava, e os testes passavam porque injetam a posição. Declaradas e guardadas por `test/android_manifest_test.dart`. `./scripts/qa/acs_gps_e2e.sh [--sem-permissao]` prova a permissão em runtime e falha com o manifesto antigo. **Não prova a chegada de um fix de GPS**: neste AVD (Android 16, Play Services) nem `adb emu geo fix`, nem provider de teste, nem `forceLocationManager` entregam posição ao app; GPS real em aparelho físico segue sem prova em dispositivo.
- **RF13 — SAMU.** O botão abre o discador com 192 (`core/services/emergency_dialer.dart`, `url_launcher`, `<queries>` para `tel:`), sem ligar sozinho e sem `CALL_PHONE`; sem discador mostra o número em texto; trava de toque duplo. "Ligar para a UBS" também abre o discador, com o telefone de `ubs.contactPhone` entregue por `ubs.myContact` (RPC do ACS; a UBS vem do token); sem telefone cadastrado, avisa e não liga. O cadastro do número cabe ao backoffice (ainda mock): hoje vale a seed.
- **E2E do ACS no banco de teste.** `./scripts/qa/acs_full_e2e.sh`: login institucional real (senha errada e certa), seletor restrito à microárea, visita sincronizada e conferida no servidor. A senha do ACS chega pelo relé `otp_relay.py` (`/acs`, opt-in por `E2E_FIXTURES_FILE`), fora do `--dart-define` e do APK. **Não cobre MQTT/ACK**: o `aclfile` do broker só libera o UUID de microárea do seed de dev, e as fixtures são aleatórias; isso segue provado por `smoke`/`red_alert_cycle` na stack de dev.
- **Defeito do app achado pelo e2e:** `AcsHomeShell.dispose()` parava o feed MQTT com `onConnectionChanged` ainda ligado, e o `setState` caía em elemento defunct. Corrigido (`test/shell_dispose_test.dart`).
- **Minors da revisão — fechados (2026-10-01).** Plano: `docs/superpowers/plans/2026-10-01-minors-da-revisao-do-app-acs.md`. (1) A contagem do `validation_report.md` foi corrigida e passou a ter conferidor (`scripts/qa/contagem_validation_report.py`). (2) `deniedForever`: `acs_gps_e2e.sh --sem-permissao` leva a permissão a negada-de-vez recusando o diálogo do sistema numa rodada só (`pm set-permission-flags` não existe no Android 16; `flutter drive` desinstala o app ao terminar). (3)(4) O script de GPS aborta se o app já está instalado (`--reinstalar` autoriza; reinstalar apaga a fila SQLCipher e o Keystore de dev), mostra o erro do build e remove o app de teste ao sair. (5) RNF06 também conferido por `patients.listMicroArea`, e o seletor deve abrir sem filtro. (6) O relé serve `/acs` uma única vez por execução. (7) A checagem da porta 8765 enxerga qualquer endereço (`scripts/qa/lib_rele.sh`). Os novos testes de shell/Python (`lib_rele_test.sh`, `acs_gps_e2e_test.sh`, `contagem_validation_report_test.py`) **não** estão ligados à CI (exigiria mexer no workflow vigiado por `ci_invariants.sh`).
- **Revisão do app ACS e fechamento (2026-10-02).** Plano: `docs/superpowers/plans/2026-10-02-revisao-e-fechamento-do-app-acs.md`. (1) **Fonte ampliada (RNF05/WCAG 1.4.4):** o ACS estourava o layout a 130% e 200% de fonte; corrigidos o chip de conexão e o título do cabeçalho (altura agora cresce com a escala, `acsHeaderHeight`), o `_InfoRow`, o botão "Atualizar dados da microárea", o dropdown "Status do atendimento" da aba Visita (`isExpanded`) e a folha "Mais" (agora rola); guardado por `test/support/layout_harness.dart` e `test/text_scale_test.dart`, que percorrem as quatro abas e os cinco itens de "Mais". (2) **Manifesto:** `android:allowBackup="false"` (o padrão era `true`: o backup automático podia levar o banco local e as preferências para a nuvem) e nome legível "SinalACS ACS"; o APK de release foi medido (`aapt2`: INTERNET, localização em primeiro plano e ACCESS_NETWORK_STATE do `connectivity_plus`; sem `debuggable`, sem localização em segundo plano) e abriu no emulador sem `FATAL`. (3) **M2.4/RNF02:** 100 visitas offline provadas na fila (`test/offline_burst_test.dart`) e contra o servidor real no emulador: **118 ms** (meta < 5000), conferidas por `pull`. (4) **Tema:** `ThemeController` coberto (`test/theme_controller_test.dart`) e `spec/ui_design.md` corrigido (dizia tema fixo escuro). **Continua aberto:** assinatura de release com chave própria (ainda a de debug), `FLAG_SECURE` (decisão de produto/LGPD: a lista da microárea mostra nome e condições crônicas), RF08 persistido, refresh token, iOS, botão da UBS. **(fechado depois — ver a seção Pendências do ACS (2026-10-02): RF08, `FLAG_SECURE`, assinatura de release e botão da UBS estão fechados; refresh token e iOS seguem abertos.)**
- **Fora:** iOS (`apps/acs/ios/` não existe). (Refresh token estava aqui; entregue em 2026-10-03.)
- **RF08 — cache persistido e cifrado (72 h, por dono) (2026-10-02).** `MicroAreaDirectory` + `MicroAreaCacheStore` guardam a última lista da microárea na base SQLCipher do ACS (schema v6, tabelas `micro_area_cache`/`micro_area_cache_meta`), chaveada por `userId|microAreaId`, validade de 72 h, só no lugar de falha recuperável de rede; a tela avisa de quando é a lista. Decisão de LGPD em `spec/lgpd_design.md` §5.11, escrita antes do código. Provado no emulador (`full_journey_e2e.dart`): serve sem rede e o arquivo do banco não contém o nome do paciente.
- **MFA do ACS (2026-10-02).** MFA/TOTP do ACS entregue (RF07, LGPD-RT06): TOTP no `loginInstitutional`, ativação por matrícula+senha+código, replay barrado, exigida fora de `development` (`REQUIRE_ACS_MFA`); refresh token e redefinição por coordenador seguem abertos. **Com MFA ligada, o ACS precisa se autenticar de novo (matrícula + senha + código) mais ou menos a cada 15 minutos**, porque ainda não existe refresh token e o código TOTP é de uso único: `renewSession` recebe `MfaRequiredException`, esquece a credencial em memória e falha de forma não recuperável, e `AcsBackend.onSessionExpired` faz o painel EMPILHAR a tela de reautenticação por cima (uma só por vez). O painel não é desmontado: fila de alertas já recebidos por MQTT (o broker não reentrega o que foi confirmado com PUBACK), feed MQTT (autentica por senha+certificado, não pelo JWT), fila de visitas e formulários em andamento sobrevivem; login do MESMO usuário só dá `pop`, de OUTRO usuário descarta o painel (RNF06). Confirmar um alerta com a sessão vencida mostra a mensagem e o alerta segue sem confirmação. No app: o login ganha o campo `totp_field` (só dígitos, 6) quando o servidor responde `MfaRequiredException`; `MfaEnrollmentRequiredException` abre `MfaEnrollmentScreen` (QR + chave + código; o segredo não é gravado no aparelho). Provas: `test/mfa_login_test.dart` (5), `test/totp_support_test.dart`, casos de fonte ampliada em `test/text_scale_test.dart` e o último teste de `integration_test/full_journey_e2e.dart` (liga a MFA pelo RPC e entra pela tela com o código do passo atual, depois de esperar o passo avançar); `test/session_reauth_test.dart` (5: alerta e formulário preservados, ACK com mensagem, outro usuário, sem rota dupla). Ruling: a tela de ativação é provada por teste de widget, não no emulador (o e2e mantém `REQUIRE_ACS_MFA=false` para os outros testes).
- **mTLS do broker (2026-10-02).** Entregue **na stack local**: `require_certificate true`, certificado de cliente para o backend e para o ACS (asset de desenvolvimento `assets/certs/acs_client.*`, copiado por `sync_dev_ca.sh`, gitignorado), senha e ACL mantidos; `scripts/qa/mtls_invariants.sh` prova os quatro casos. **Aberto:** provisionamento por aparelho em produção (CSR no cadastro, chave no Keystore); o release com a chave de dev é barrado pelo Gradle (`-Psinalacs.allowDevClientKey=true` só para teste local).
- **Aberto fora do ACS:** `apps/patient` — manifesto `main` sem `INTERNET` explícito (hoje herdado de dependência); medir com `aapt2 dump permissions` no APK de release antes de mexer.

## Pendências do ACS (2026-10-02)

Plano: `docs/superpowers/plans/2026-10-02-pendencias-do-acs-flag-secure-ubs-rf08-mfa-assinatura-mtls.md`. Fecha as pendências deixadas pela revisão de 2026-10-02 (linha "Continua aberto" acima). Um commit de fechamento por tarefa; provas medidas no `emulator-5554`.

- **T1 — `FLAG_SECURE` (`0930522`).** Janela inteira do ACS protegida. Prova: `scripts/qa/acs_secure_window.sh` (`dumpsys window`) e teste de fonte. Aberto: capturas de tela do ACS (`docs/telas-acs.md`) agora saem pretas e não há procedimento para regenerá-las.
- **T2 — assinatura de release (`e37bf5d`).** `assembleRelease` falha sem chave própria (`key.properties` ou `SINALACS_KEYSTORE_*`); debug só com `-Psinalacs.allowDebugSigning=true`. Prova: `scripts/qa/acs_release_signing.sh`. Aberto: **o keystore de release real e o segredo dele na CI não existem**.
- **T3 — botão da UBS (`b28f9be`, `7160e4c`).** `ubs.contactPhone` (nullable) entregue por `ubs.myContact`; sem telefone o botão avisa e não liga; a consulta da UBS não trava o botão do SAMU. Prova: testes do app e do servidor, `full_journey_e2e`. Aberto: o cadastro do telefone pelo backoffice (mock); vale a seed.
- **T4 — RF08 persistido (`43c58fa`).** Cache da microárea na base SQLCipher (schema v6), por dono, 72 h, só em falha recuperável de rede; decisão de LGPD em `spec/lgpd_design.md` §5.11. Prova: testes e `full_journey_e2e` (serve sem rede; o arquivo do banco não contém o nome). Aberto: ver Minors adiados.
- **T5 — MFA TOTP, backend (`d6718dd`, `dc517f7`).** RFC 6238, segredo cifrado AES-256-GCM, replay e corrida de ativação barrados (5 logins simultâneos, 1 sessão), `REQUIRE_ACS_MFA` exigida fora de `development`. Prova: suíte do backend. Aberto: sem lockout progressivo além do limite de 5 tentativas/15 min.
- **T6 — MFA no app (`abb8438`, `69c19d4`).** Campo do código no login, tela de ativação com QR, expiração de sessão sem renovação silenciosa. Prova: `mfa_login_test`, `text_scale_test` e o último teste de `full_journey_e2e` no emulador. Aberto: ver a consequência da sessão de 15 min abaixo.
- **T7 — mTLS, broker e backend (`38beea2`, `0e8484b`).** `require_certificate true`, senha e ACL mantidas, backend apresenta certificado. Prova: `scripts/qa/mtls_invariants.sh` (recusa sem certificado e de outra CA, aceite com ambos; distingue recusa de falha de infraestrutura). Aberto: só na stack local.
- **T8 — mTLS, app (`05fcd1c`).** O ACS apresenta o certificado de cliente (asset de desenvolvimento `assets/certs/acs_client.*`); o release com essa chave dentro falha a build. Prova do app com mTLS: `./scripts/qa/e2e.sh --emulator` (smoke + `red_alert_cycle`) e `mtls_invariants.sh`; o `full_journey_e2e` NÃO cobre MQTT. Aberto: **provisionamento de certificado por aparelho em produção** (CSR no cadastro, chave no Keystore).
- **T9 — registro e barra final.** Este texto, o `CLAUDE.md` da raiz e a barra completa (resultados no relatório da tarefa).

### Decisões do plano (D1–D8)

- **D1:** `FLAG_SECURE` na janela inteira do ACS, não só na lista (a lista aparece em Área, Visita e no seletor); `screencap` e gravação saem pretos.
- **D2:** chave de release de `apps/acs/android/key.properties` ou `SINALACS_KEYSTORE_*`; sem chave a build falha; debug só com licença explícita; o plano não cria keystore nem segredo de CI.
- **D3:** telefone da UBS em `ubs.contactPhone` nullable, via `ubs.myContact`; sem número o botão avisa; o cadastro é do backoffice.
- **D4:** o cache de RF08 guarda só o que a tela de visita já mostra, na base SQLCipher, 72 h, chave `userId|microAreaId`, apagado ao mudar o dono ou vencer, só no lugar de falha recuperável de rede.
- **D5:** MFA = TOTP RFC 6238 (SHA-1, 6 dígitos, 30 s, janela ±1), segredo cifrado com a chave dos dados clínicos, ativação sem token (matrícula + senha + código), `REQUIRE_ACS_MFA` falsa em `development` e verdadeira fora.
- **D6:** ~~refresh token e redefinição de MFA por coordenador ficam fora.~~ **Superado em 2026-10-03** quanto ao refresh token (ver "Refresh token e desbloqueio biométrico do ACS" abaixo); a redefinição de MFA por coordenador segue fora.
- **D7:** mTLS mantém a senha MQTT (`require_certificate true` sem `use_identity_as_username`): certificado e senha.
- **D8:** o certificado de cliente do ACS vem de asset de desenvolvimento; a chave privada no APK serve só ao dev e o release com ela falha; o mTLS fica entregue na stack local e aberto para produção.

### Consequência de produto — resolvida em 2026-10-03

*Histórico (superado pelo refresh token, seção abaixo).* Com MFA ligada e sem refresh token, a sessão do ACS (15 min) não pode ser renovada em silêncio (o código TOTP é de uso único): **o ACS reautentica com matrícula + senha + código cerca de a cada 15 minutos**; o painel, os alertas e os formulários são preservados (a tela de login é empilhada por cima). A decisão foi implementar o refresh token.

### Continua aberto

(Refresh token: fechado em 2026-10-03.) Redefinição de MFA por coordenador (hoje manual: zerar as quatro colunas `totp*` do ACS); provisionamento de certificado por aparelho em produção; keystore de release como segredo na CI; cadastro do telefone da UBS pelo backoffice; iOS.

- **Adivinhação de TOTP:** para quem já tem a senha, o orçamento é o bloqueio fixo de 5 tentativas por 15 min (cerca de 0,14% por dia); precisa de bloqueio progressivo antes de qualquer implantação fora do desenvolvimento.
- **Cadastro da MFA é trust-on-first-use:** quem souber a senha primeiro pode ativá-la; não há redefinição pelo próprio ACS e a redefinição por coordenador é manual.
- **`FLAG_SECURE` escurece captura e gravação:** `screencap`/`screenrecord` do ACS saem pretos, inclusive o pipeline de vídeo (`video/capture/lib.sh`, linhas 142 e 161). Consequência conhecida; um build de debug com opt-out documentado NÃO foi adicionado (decisão pendente). Para capturar telas do ACS hoje, só com a janela desprotegida (remover temporariamente a flag na `MainActivity`) ou fotografando o aparelho.

### Minors adiados

- T1: o script de `FLAG_SECURE` usa `awk` com `exit` sobre o pipe do `dumpsys` (risco de SIGPIPE com `pipefail`) e `sleep 6` fixo; `secure_window_test` só confere string no fonte; falta documentar como regenerar as capturas do ACS.
- T2: `acs_release_signing.sh` não é hermético contra `SINALACS_KEYSTORE_*` já exportadas; `hasProperty` vale mesmo com `=false`; a mensagem não diz qual das quatro propriedades falta; `apksigner` escolhido por ordem lexical.
- T3: o store do ORM faz duas consultas; "UBS não encontrada" vira `AlertPermissionException`; `capture-acs.sh` cita o rótulo antigo da UBS.
- T4: relógio do aparelho voltado serve cache de mais de 72 h; o cache do dono anterior só some no próximo load; o guard do `main.dart` é por string.
- T5: sem lockout progressivo contra adivinhação de TOTP; ruído de reformatação em `institutional_auth_service`; confirmar que o log do Serverpod não registra o retorno de endpoint (`secretBase32`).
- T6: preexistente: `renewSession` com falha não recuperável que não é MFA re-tenta o login a cada sync e pode bloquear a conta.
- T7: chaves privadas de cliente em modo 644 em dev; o teste "production sem TLS" só verifica a ausência do erro de certificado; cert/chave ignorados em silêncio se o TLS está desligado.
- T8: `sync_dev_ca.sh` não confere que `acs-area-12.key` é o par do certificado e deixa `.tmp` se interrompido; doc de `alert_feed.dart` passa de 100 colunas; `buildMqttSecurityContext` ignora certificado sem chave em silêncio.

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
| Schema | 13 tabelas como modelos `.spy.yaml` (as 11 originais mais `alert_idempotency_keys` e `alert_outbox` — ver "cadeia de hash" e "outbox pattern" abaixo); migrações geradas e aplicadas pelo servidor no boot |
| Endpoints | RPC: `alerts.createRedAlert`, `alerts.acknowledge`, `auth.developmentLogin`, `health.check`, `triage.evaluate`, `patients.listMicroArea`, `visits.sync` |
| Testes | 16 arquivos (12 unitários herméticos, 4 de integração) sobre o harness `withServerpod`; contagem estática de `test(` no código-fonte, não uma execução nesta revisão — rodar `cd backend/sinalacs_server && dart test` contra a stack local para o número de casos passando |
| Cliente gerado | Publicado em `backend/sinalacs_client`; **paciente e ACS já o consomem** por dependência local (ver M2.4 acima); `apps/admin` ainda não |

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
  Secretaria continuam não implementados. **Atualização (2026-09-18):** no app
  do ACS isso deixou de valer — o login é institucional (matrícula + senha,
  RF07), verificado com Argon2id contra `user_credentials`; o token de
  desenvolvimento continua existindo para as ferramentas e para o app do
  paciente. O que segue não implementado é a integração com Gov.br e com um
  cadastro institucional real: a credencial do ACS nasce do seed de
  desenvolvimento, não de um sistema da Secretaria (ver a seção abaixo).
  **Atualização (2026-09-19):** o app do paciente também deixou de usar o token
  de desenvolvimento — o login dele é passwordless (CPF + data de nascimento +
  código OTP, RF01) —, então o `developmentLogin` ficou só nas ferramentas
  (`tool/`, `integration_test/`) dos dois apps, contra uma stack com
  `ENABLE_DEV_LOGIN=true` (ver a seção do RF01 ao fim deste arquivo).
- ~~**Apps Flutter não consomem o cliente gerado.**~~ Desatualizado: os dois
  apps já consomem `sinalacs_client` por dependência de caminho e falam com o
  backend real (ver M2.4 acima) — `RiskLevel` atravessa a fronteira desde a
  triagem.
- ~~**Risco residual de entrega.** MQTT não participa da transação: se a
  publicação tem êxito e o commit falha, o alerta chega ao ACS sem linha no
  banco... fechar por completo exigiria outbox pattern.~~ Desatualizado: a
  tabela `alert_outbox` e `AlertOutboxDispatcher`
  (`backend/sinalacs_server/lib/src/application/alerts/alert_outbox_dispatcher.dart`)
  implementam o outbox pattern, com teste próprio em
  `test/unit/alert_outbox_dispatcher_test.dart`.
- **Deploy não executado.** O runbook em [backend/DEPLOY.md](backend/DEPLOY.md)
  foi reescrito para Serverpod, mas continua sem ter sido rodado.

---

## Refresh token e desbloqueio biométrico do ACS (2026-10-03)

Plano: `docs/superpowers/plans/2026-10-03-refresh-token-e-biometria-do-acs.md`. Fecha o "reautentica a cada 15 minutos" que a MFA tinha criado e supera a D6 do plano de 2026-10-02.

- **Backend.** Tabela `acs_refresh_tokens` (migração `20261003151950052`; hash SHA-256, família, aparelho — o `deviceId` é o identificador da instalação, UUID aleatório, não uma atestação de hardware: protege contra token vazado sem ele, não contra comprometimento do aparelho). Janela ociosa de 2 h, teto absoluto de 8 h desde o login por senha + TOTP, tolerância de reuso de 30 s. Reuso fora da tolerância, aparelho diferente e conta inativa ou sem microárea revogam a família; a mensagem é uma só, `Sessão expirada. Entre novamente.`. A microárea é relida do banco a cada refresh. INSERT condicional atômico e revogação em duas passagens contra a corrida. Auditoria `session_refresh` (`refresh_granted`, `refresh_granted_grace`, `denied_*`). `auth.refreshSession` e `auth.logout` são públicos por desenho e estão na allowlist de `endpoint_auth_posture_test.dart`. `loginInstitutional` só emite o token com `deviceId` não-branco. O JWT do ACS segue em 15 min; o paciente segue sem refresh (OTP, 1 h).
- **App.** Não retém mais a senha. Refresh token e `deviceId` (UUID aleatório) no Keystore (`secure_session_token_store.dart`); renovação single-flight. `AppLockGate` (`local_auth` 3.0.2) acima do Navigator bloqueia após 30 s em segundo plano; painel, MQTT, filas e formulários continuam montados. A partida a frio exige biometria ou bloqueio de tela antes de retomar a sessão (aparelho sem bloqueio de tela: login completo). "Entrar com senha" empilha a reautenticação opaca de duração zero. "Sair e encerrar o turno" revoga a família e **não** apaga a fila de visitas. `MainActivity` virou `FlutterFragmentActivity` e mantém `FLAG_SECURE`; `USE_BIOMETRIC` no manifesto.
- **Limite de desenho.** *(Reescrito em 2026-10-05.)* O refresh token agora só é decifrado depois do `BiometricPrompt` com `CryptoObject` sobre uma chave RSA do Keystore criada com `setUserAuthenticationRequired(true)` e autenticação a cada uso (envelope AES-256-GCM + RSA-OAEP, `KeystoreVault.kt`; ver "Biometria amarrada ao Keystore" abaixo), uma vez por partida a frio. O `AppLockGate` continua sendo portão de **interface** para os 30 s em segundo plano: depois do desbloqueio o token fica em RAM durante o processo. A chave do SQLCipher e o token de envio diferido seguem sem esse vínculo, por desenho. O ganho contra o roubo vem do cofre somado à janela de 2 h / teto de 8 h e à revogação (reuso, "Sair").
- **Prova.** Suítes: backend 536, ACS 336. Emulador `emulator-5554` (API 36, `google_apis_playstore`): `acs_full_e2e.sh` 4/4, e `--esperar-jwt` com renovação silenciosa após a expiração real do JWT (871 s), sem tela de reautenticação, `refresh_granted` em `audit_logs` e zero `denied*`; o bloqueio com BiometricPrompt real após mais de 30 s em segundo plano, desbloqueado por PIN e por digital (digital errada ou cancelamento não desbloqueiam); `FLAG_SECURE` intacto (`acs_secure_window.sh`). O e2e automatizado usa um `BiometricGate` de teste na retomada da partida a frio. Na rodada achou-se e corrigiu-se `e2e.sh` quebrado no branch (`live_check.dart` importava `dart:ui` pelo Keystore).
- **Não provado:** Android ≤ 8.1 (API 24–27) (o tema herda `@android:style/Theme.*.NoTitleBar`, e o README do `local_auth_android` pede AppCompat para Android 8.1 ou anterior; `minSdk` é 24), aparelho físico, `lockedOut` por tentativas, iOS, o prompt real na partida a frio com sessão guardada (só o do bloqueio por inatividade foi exercitado à mão por adb; `KEYCODE_HOME` no lugar de `SLEEP`/`WAKEUP`). *(O prompt na partida a frio foi provado em 2026-10-05 por `acs_keystore_bound_e2e.sh`.)*
- **Aberto:** (a) ~~biometria ligada ao Keystore (`setUserAuthenticationRequired`) em vez de portão de UI~~ — fechada em 2026-10-05 para o refresh token, com prova no emulador API 36 (ver "Biometria amarrada ao Keystore" abaixo; o que segue aberto está lá); (b) revogação de todas as famílias de um ACS e redefinição de MFA pela coordenação (hoje manual); (c) limpeza periódica de `acs_refresh_tokens` (hoje o login só poda os tokens vencidos do próprio usuário); (d) iOS não existe; (e) refresh token do **paciente** (OTP segue em 1 h); (f) tema Android/AppCompat em Android ≤ 8.1 (API 24–27); (g) ~~a fila de visitas do app não é escopada por dono~~ — fechada em 2026-10-04 (ver "Fila de visitas por dono e corrida do login" abaixo); (h) pops programáticos enquanto o app está bloqueado não são interceptados (limitação documentada no `AppLockGate`); (i) ~~resta uma janela estreita de logout concorrente com renovação~~ — fechada pela revisão final (I-1, abaixo); (j) **M-2:** o login por senha não revoga a família que substitui: a família anterior do mesmo aparelho segue válida até o teto de 8 h (ou a janela ociosa de 2 h) e só cai pelo reuso ou pelo "Sair"; (k) **rate limit** em `auth.refreshSession`/`auth.logout` (públicos, sem token): é infraestrutura — middleware `ratelimit` do Traefik na rota do RPC —, não código do endpoint; (l) **M-7:** em dois refreshes concorrentes com o MESMO token, o perdedor que recebe o filho pela tolerância é auditado como `refresh_granted` em vez de `refresh_granted_grace` (a trilha subconta o uso da tolerância).
- **Revisão final do branch (corrigido aqui).** **I-1 (INV-01/RNF06):** uma renovação em voo podia sobrescrever um login mais novo — o ACS B entrava por "Entrar com senha" enquanto a renovação lenta de A estava em voo, e o resultado de A gravava o token e a sessão de A por cima: o painel de B passava a usar o JWT de A. Agora `BackendClient` tem uma geração (epoch): login e logout a incrementam (o logout antes **e** depois da chamada de rede), e a renovação que começou numa geração anterior termina recuperável, sem gravar o filho, sem expor a sessão e sem `onSessionExpired` (a família filha fica abandonada). Fecha também o logout concorrente com renovação, inclusive a renovação iniciada durante a chamada de logout. **I-2 (alerta vermelho nunca descartado em silêncio):** "Sair e encerrar o turno" diz quantos alertas seguem sem confirmação ("Eles saem deste aparelho, mas continuam pendentes no servidor") e o botão vira "Sair mesmo assim"; a saída não é bloqueada. Também: a reautenticação de "Entrar com senha" que não abre devolve a flag e mantém a cobertura (M-3), e `_tryResume` sempre solta `_resuming` (M-4).

## Biometria amarrada ao Keystore — refresh token do ACS (2026-10-05)

Plano: `docs/superpowers/plans/2026-10-05-biometria-amarrada-ao-keystore.md`. Fecha o item (a) da seção anterior.

- **App.** `AuthBoundSessionTokenStore` (`lib/core/security/auth_bound_session_token_store.dart`) com `MethodChannelKeystoreVault` e o cofre nativo `KeystoreVault.kt`: uma chave AES-256-GCM descartável cifra o token; a chave AES vai cifrada com a pública RSA-2048/OAEP (SHA-256, MGF1-SHA-1) de um par do Android Keystore com `setUserAuthenticationRequired(true)`, validade 0 (a cada uso), `BIOMETRIC_STRONG | DEVICE_CREDENTIAL` na API 30+ e só biometria forte antes. `write` sela sem prompt (a rotação de 15 min segue silenciosa); `read` só devolve a RAM; `unlock` é o único que decifra, com `BiometricPrompt` + `CryptoObject`, uma vez por partida a frio (`_tryResume`). `cancelled`/`lockedOut` mantêm o blob; `invalidated` (chave morta ou blob corrompido) apaga o blob e cai no login com "Sua sessão expirou. Entre novamente."; teto de 2 min no `unseal` (o lado nativo pode descartar o pedido sem callback). O token do `flutter_secure_storage` das instalações antigas é migrado (selado e apagado) no primeiro `contains()`/`unlock`. `MemorySessionTokenStore`/`SecureStorageSessionTokenStore` devolvem `notRequired`, e aí vale o `BiometricGate` de UI de antes (é o caminho do `integration_test`).
- **Prova no emulador** (`emulator-5554`, API 36, `google_apis_playstore`, PIN + digital 1): `./scripts/qa/acs_keystore_bound_e2e.sh --pin <PIN> [--preparar] [--nova-digital] [--remover-bloqueio]`, com o app de verdade (`run_acs.sh --build`) e o ACS do seed na stack de desenvolvimento. Verde em 2026-10-05: (1) com token guardado, a partida a frio mostra o diálogo do `BiometricPrompt` (systemui) e o painel não está na tela; (2) a digital 1 abre o painel; (3) a digital 2 não abre, o prompt continua, cancelar volta ao login **sem** o aviso, o blob continua no `SharedPreferences` e a partida seguinte entra com a digital 1; (4) o cenário do revisor: o app vai ao segundo plano com o prompt aberto (e antes de ele abrir); na volta nada fica preso ("Retomando a sessão…" some, o botão de login está habilitado), o blob continua e a partida seguinte entra; (5) remover o bloqueio de tela e pôr um PIN novo: a partida seguinte não abre prompt, mostra "Sua sessão expirou. Entre novamente." e apaga o blob (sem laço). O `dumpsys fingerprint` registrou `acceptCrypto`/`rejectCrypto`, ou seja, autenticações com `CryptoObject`. Também visto: com o emulador sem PIN nem digital, o login deixa o token só em RAM (`SharedPreferences` vazio) e a partida a frio cai no login completo, sem prompt. Não-regressão verde: `./scripts/qa/e2e.sh --emulator` (smoke), `acs_full_e2e.sh` (5/5, `SecureStorageSessionTokenStore` → `notRequired` → `BiometricGate` de teste) e `acs_secure_window.sh`. Suíte do ACS: 516 (`flutter test`).
- **Achado da prova: digital nova NÃO invalida a chave na API 30+.** Depois de cadastrar uma segunda digital (`--nova-digital`, ou à mão em Configurações › Segurança), a partida a frio abre o prompt e a digital **antiga** entra. Esperava-se "Sua sessão expirou" sem prompt. Causa: com `DEVICE_CREDENTIAL` permitido, a chave inclui o SID do bloqueio de tela, e o token de autenticação da digital também o carrega, então `setInvalidatedByBiometricEnrollment(true)` não tem efeito. Não há laço de prompt e o PIN continua exigido para cadastrar digital; quem sabe o PIN já abre o cofre de qualquer forma, então a perda de segurança é pequena. Ficar com a invalidação exigiria uma chave só de biometria (sem o PIN no prompt: aparelho só com PIN cairia sempre no login completo) ou uma chave-sentinela só de biometria. Decisão em aberto; os comentários do código foram corrigidos para não prometer a invalidação.
- **Segue aberto:** (a1) invalidação por digital nova na API 30+ (achado acima); (a2) a chave do SQLCipher e o token de envio diferido seguem sem vínculo à autenticação, **por desenho** (a fila offline e o envio de outro dono funcionam sem o dono presente); (a3) API 24–29 sem prova (só biometria forte no prompt; o item (f) da seção anterior continua aberto), e aparelho físico também sem prova; (a4) aparelho sem biometria nem bloqueio de tela, ou API 24–29 sem biometria forte: o token fica só em RAM e **cada partida a frio exige login completo**; (a5) o teto de 2 min do `unseal` vira `cancelled` no Dart, mas o prompt nativo pode continuar aberto, órfão (UX); (a6) depois de cancelar o prompt (ou de ir ao segundo plano com ele aberto) a tela de login não oferece "tentar de novo": volta-se a tentar com uma nova partida a frio ou entrando com senha; (a7) `lockedOut` por tentativas não foi provado no emulador; (a8) a RSA-2048 é gerada na thread principal no primeiro `seal` (engasgo possível em aparelho lento).

## Fila de visitas por dono e corrida do login (2026-10-04)

Plano: `docs/superpowers/plans/2026-10-03-fila-de-visitas-por-dono-e-corrida-do-login.md` (decisões D1–D9). Fecha o item (g) acima e a corrida residual do `login()`.

- **Fechado: corrida do `login()`.** `BackendClient._exclusive` é uma seção crítica serial e não reentrante: login, `developmentLogin`, a leitura do token e a confirmação da renovação, e o logout trocam época, token do Keystore e `_session` dentro dela; a rede (refresh, logout no servidor) fica fora. Uma renovação iniciada na janela da gravação do login lê o token novo e não toca na sessão do usuário seguinte.
- **Fechado: fila de visitas por dono (RNF06).** Schema local v7 (`offline_visits.owner`, aditivo): `VisitStorage.forOwner(userId)` só lê, conta, grava e apaga `WHERE owner = ?`; o `save()` de B nunca toca nas linhas de A. Linhas do schema v6 ficam em **quarentena** (`owner IS NULL`): nenhum dono as carrega, conta, envia ou descarta; só `LegacyVisitStore` as vê. `localId` já existente em outro dono vira `VisitLocalIdConflict` (a unicidade é global). Cursor do pull por `userId|microAreaId` (o cursor global antigo foi abandonado; cada dono recomeça do `epoch`, idempotente por `localId`). Fila e pull são resolvidos por sessão e recriados por dono; o sincronizador recusa sessão ou token de outro dono (checagem no push e `expectedUserId` conferido **depois** de resolvido o token, para a renovação de A que espera a seção do login de B nunca enviar sob o token de B). Isso fecha também o caminho de perda de dado clínico por `discardRejected()` de outro ACS.
- **Backend.** `visits.syncLegacy` (sessão de ACS territorializado **só como transporte**): grava com `authorship = legacyUnclaimed`, `acsId` nulo e `originDeviceId`; teto de 200 entradas (`VisitSyncService.maxLegacyBatch`); valida paciente e território do transportador (visita de outra microárea ou paciente divergente: recusa genérica); reenvio idêntico (mesmo `localId`, mesma versão) devolve `synced`; auditoria `visit_legacy_sync` do lote e, por visita, `visit_legacy_sync_item` (`resourceId` = `visits.id`) gravadas só depois do laço; ACS inativo recusado (`isActiveAcs`). `visits.syncDeferred` e `visits.revokeUploadToken` autenticam pelo **token de envio**, não pelo JWT (na allowlist de `endpoint_auth_posture_test.dart`): tabela `acs_upload_tokens` (migrações `20261004013108186` e `20261004014924364`; só hash SHA-256, 7 dias, um por usuário+aparelho, escopo único, advisory lock na troca), emitido no `loginInstitutional` junto do refresh token (só com `deviceId` real); a visita é gravada com a autoria do dono do token e a microárea é relida do banco. `OpaqueToken` é o gerador/hasher compartilhado com o refresh token. Tabelas de domínio na migração mais recente: **20** (`definition.sql`).
- **App.** `UploadTokenStore` (`secure_upload_token_store.dart`): um token por dono no Keystore (`acs_upload_token|<userId>`) mais um índice de donos; o envio também tenta o dono de toda linha no disco, então o índice é otimização. `DeferredFlushService.flushAll()` (single-flight, não lança): o legado sobe pela sessão atual como transporte; cada dono com token sobe por `syncDeferred`, em lotes de 100; uma visita só sai do aparelho em `synced`; o token é revogado e apagado só com a lista do dono vazia; o dono da sessão atual é pulado (a fila é do painel). Gatilhos: painel aberto, retomada do app e conexão que volta (`connectivity_plus`). "Sair e encerrar o turno" sincroniza a fila do painel, sobe o resto (teto de 20 s por etapa, `sessionEndSendTimeout`) e diz o que fica no aparelho e por quê. "Limpar este aparelho": congela a área, espera o refresh em voo e `VisitDatabase.wipeAllData` apaga `offline_visits`, `sync_cursor` e o cache da microárea numa transação **só se não houver NENHUMA linha** (inclusive recusada, legado ou de outro dono) nem fila só em RAM; o arquivo e a chave ficam. Textos distinguem "ainda não enviadas", "recusadas ou em revisão" e "de outra conta sem chave de envio".
- **Prova.** Suítes: backend 609, ACS 476. Emulador `emulator-5554` (API 36): `encrypted_storage_test.dart` (dois donos + quarentena no mesmo arquivo SQLCipher real, migração v6 preservando linhas, arquivo sem o texto das notas) e `full_journey_e2e.dart` via `acs_full_e2e.sh` com dois ACS (`acsB`) nas fixtures: A (com MFA) registra visita offline e sai; B entra e não a vê; a conexão volta e `flushAll` sobe a de A com `acsId` de A; uma visita legada plantada no banco v6 sobe com `authorship = legacyUnclaimed`, `acsId` nulo e `originDeviceId`; `psql` confere `visits`, `audit_logs` e que não resta token de envio ativo de A nem de B. **O offline é SIMULADO**: um decorator de `AcsBackend` no teste recusa as chamadas de envio de visita (não é a rede do aparelho caindo) e o gatilho de conectividade é alimentado por um `StreamController`.
- **Não provado:** token de envio vencido ou recusado no aparelho; rejeição por "versão diferente" e por território no aparelho; retomada a frio com fila de outro dono; `e2e.sh --full`; execução em segundo plano; Android ≤ 8.1 (API 24–27); aparelho físico; iOS.
- **Aberto, com motivo.** (1) **Execução em segundo plano do SO (WorkManager):** o envio é só em primeiro plano; `workmanager` é pacote fora de `spec/stack.md` (exige decisão), roda em isolate sem UI e não teria prova no emulador (D8). (2) **Wipe forçado por supervisor:** não existe login de supervisor/coordenador (D9); o wipe é do ACS e só abre com tudo enviado. (3) **Token de envio vencido (7 dias) ou recusado deixa a fila do dono presa** até o dono entrar de novo, e **bloqueia o wipe** do aparelho. (4) **Retenção/expurgo LGPD de dono que nunca volta** continua dependendo do envio: sem token válido e sem login dele, as visitas ficam cifradas no aparelho sem prazo. (5) **ACS inativo ainda é aceito em `visits.sync`/`pull`** até o JWT vencer; `isActiveAcs` só é checado no `syncLegacy` (e no `syncDeferred` pelo token). (6) Não há CHECK no banco para `acsId` nulo ⇔ `authorship = legacyUnclaimed`. (7) Oráculo de existência de `localId` residual (um `localId` existente de outro paciente é recusado, um inexistente é inserido), igual ao `visits.sync`; o mesmo `localId` duas vezes no lote gera dois itens de auditoria, e uma falha do commit depois do laço pode deixá-los órfãos. (8) **Sem teto de lote no `visits.sync` existente** (o teto de 200 vale para `syncLegacy`/`syncDeferred`; mudar o existente seria regressão da fila do app). (9) **Microárea trocada:** visitas antigas do dono terminam `rejected` de forma terminal. (10) **`rejected` por "versão diferente"** (a visita já existe no servidor com autor, em outra versão) fica em quarentena e exige revisão: uma edição offline de linha já enviada fica presa por escolha segura. (11) `deleteExpiredFor` fora da transação da troca de token (deadlock teórico); a classe gerada `AcsUploadToken` é exposta ao cliente. (12) `uploadToken`/`refreshToken` trafegam como argumento de RPC (nota do VAZ-03).
- **Janelas conhecidas (documentadas).** Dono só em RAM (a fila não conseguiu gravar) cujo token de envio é revogado pelo envio diferido enquanto há visitas pendentes só em memória (elas só sobem pela sessão dele, que ganha outro token ao entrar); `VisitRegistrationScreen._loadPatients` grava o cache da microárea fora do congelamento do wipe; `close()` durante um `open()` em voo deixa a conexão aberta; `_upgrade` a partir do schema v1 não cria `sync_cursor`/`micro_area_cache` (pré-existente); o single-flight de `BackendClient.renewSession` tem folga (uma renovação entre o enfileiramento do login e o corpo da seção abre um voo extra, absorvido pela tolerância de 30 s); logout concorrente com renovação respondida antes dela dispara `onSessionExpired` no meio do "Sair" (pré-existente); um Keystore travado bloqueia todas as seções críticas. A janela do teto de 20 s do "Sair" seguida de um ciclo B/A (fila antiga regravando às cegas o disco de uma fila nova do mesmo dono) foi **fechada** pela revisão final: a fila com envio em voo (`OfflineVisitQueue.isSyncing`) não sai da memória, então o próximo login do dono reencontra a MESMA fila. O compare-and-clear do token de envio também foi fechado: `UploadTokenStore.compareAndClear` roda dentro da cadeia serial do store.
- **Revisão final (2026-10-04), corrigido.** **C-1 (pré-existente, perda de dado):** `OfflineVisitQueue._applyOutcomes` refazia a fila só com o lote capturado antes do envio, então uma visita registrada com o lote no servidor sumia da memória e, no `save` seguinte, do disco; agora quem chegou durante o envio continua pendente, e `sync()` é single-flight (uma segunda chamada recebe o resultado do envio em voo; o lote nunca sai duas vezes). **I-1:** a recuperação "chave não abre o arquivo → apaga arquivo e chave e recomeça" só roda para o erro de chave errada do SQLCipher (`SQLITE_NOTADB`/"file is not a database", ou o `open_failed` em que o `sqflite_sqlcipher` 3.2.0 o converte no Android); erro de migração, de E/S, `PlatformException` ou qualquer outro sobe, nada é apagado e a fila segue em RAM (`persistenceFailed`). Como no Android a chave errada e uma falha passageira chegam como o mesmo `open_failed`, a recuperação só roda se uma segunda tentativa de abrir também falhar, e nunca apaga o arquivo: ele vai para uma cópia única `<nome>.recuperado`, ainda cifrada e com a chave apagada — **ilegível ao app e ao suporte**, só um artefato forense (os bytes ficam caso a chave antiga um dia seja restaurada de um backup do aparelho/Keystore); as visitas pendentes desse arquivo não são recuperáveis; se mover falhar, o erro sobe e nada é tocado; "Limpar este aparelho" apaga também a cópia. **I-2:** fila com envio em voo não é descartada (ver acima). **M-5:** `compareAndClear` em série. Textos: o "Sair" explica a espera ("Enviando as visitas pendentes antes de sair…") e diz que o que ficou sobe "quando o aplicativo estiver aberto com conexão (em até 7 dias)".
- **Aberto da revisão final.** **Recuperação de chave no Android:** `open_failed` é indistinguível entre chave errada e falha real de abertura; uma falha real que persista nas duas tentativas move o arquivo e troca a chave, e sem restaurar a chave antiga as visitas do arquivo movido ficam ilegíveis (perda de acesso às pendentes). Opção futura: guardar a chave antiga sob `<chave>.recuperado` até o "Limpar este aparelho". **M-1:** recusas de território do legado ficam lembradas só em memória (`DeferredFlushService._legacyRejectedBy`), então cada partida do app reenvia a mesma visita legada e o servidor grava de novo `denied_territory` sob o ACS que só a transportou (inocente). Correção: persistir o conjunto de recusas por transportador ou auditar com outro `result`. **M-3:** "Sair" sem rede deixa o token de envio do dono válido (no Keystore e no servidor) por até 7 dias, mesmo sem visita pendente, até um envio diferido rodar com rede e revogá-lo; desativar a conta o corta (`syncDeferred` confere a conta). **Downgrade:** `onDowngrade: onDatabaseDowngradeDelete` (`encrypted_database.dart`) **apaga** o banco quando o APK volta para uma build anterior ao schema v7 — visitas não enviadas, cursor e cache da microárea se perdem.

## Login institucional do ACS (RF07) — o que ficou de fora (2026-09-18)

O login do ACS deixou de ser o token HMAC de desenvolvimento: o app envia
matrícula e senha a `auth.loginInstitutional`, o servidor verifica a senha com
Argon2id contra a tabela `user_credentials`, bloqueia a conta por 15 minutos
após 5 tentativas falhas e audita cada desfecho em `audit_logs` — o rate
limiting que o achado F6 de `spec/security_assessment.md` pedia. As decisões de
escopo estão em
`docs/superpowers/plans/2026-09-18-rf07-login-institucional-acs.md`. O que este
plano **não** fez:

- **MFA/TOTP para o ACS.** Exigido por LGPD-RF11/LGPD-RT06 e pelo achado F5. O
  critério de MVP do PRD pede "matrícula e senha", e não existe fluxo de
  enrollment de TOTP em nenhum dos apps.
- **Refresh token rotativo, e o TTL de 1h/8h.** Exigidos por LGPD-RT06. Na
  prática a sessão dura 15 minutos e a renovação depende da credencial mantida
  em memória. *(Superado em 2026-10-03: refresh token do ACS entregue; o app não
  guarda mais a senha.)*
- **Limite de tentativas por origem (IP).** O bloqueio é por conta, não por
  origem: um atacante com muitas matrículas válidas distribui as tentativas.
- **Amplificação anônima no caminho da matrícula inexistente.** Toda tentativa
  com matrícula desconhecida executa uma derivação Argon2id **descartada** —
  ~70–80 ms e 19 MiB medidos na stack —, e esse caminho não é limitado (o
  bloqueio só cobre contas existentes) nem auditável (`audit_logs.userId` é
  obrigatório e tem FK para `users`: um sujeito que não existe não tem como
  deixar linha). Cada decisão isolada se sustenta; a combinação não — qualquer
  anônimo transforma o servidor num amplificador de CPU e memória. Correção
  estrutural barata, ainda não feita: um teto global de derivações simultâneas.
  Registrado no achado F6 de `spec/security_assessment.md`.
- **Um deploy que não rode o seed não tem como ninguém entrar.** A credencial
  institucional nasce de `bin/seed_acs_credentials.dart` — o único caminho pelo
  qual uma credencial passa a existir (depois dela a tabela só é escrita para
  contar tentativas e limpar bloqueio, em `OrmAcsCredentialStore`) — e esse
  script **recusa** rodar fora de `APP_ENV=development`. Antes desta mudança a
  stack nova funcionava de imediato, porque o app chamava
  `auth.developmentLogin`; agora o app só chama `loginInstitutional`, então uma
  instalação sem o seed (um `APP_ENV=production` qualquer) sobe com o app **sem
  nenhum caminho de login**. A proveniência da credencial estava documentada; a
  consequência, não.
- **Troca de senha pelo próprio ACS.** Não há fluxo; `saveCredential` existe no
  serviço para que o seed e uma futura troca o usem.

E quatro lacunas que só apareceram durante a execução. Nenhuma delas é um
defeito:

1. **Sem caminho de volta ao login quando a renovação falha de forma não
   recuperável.** `BackendClient._requireToken` falha com `isRecoverable:
   false` e a mensagem aparece no banner da tela que fez a chamada, mas nada
   navega de volta à tela de login — a pessoa reinicia o app; `renewSession`
   nem está na interface `AcsBackend`, então a UI não tem como chamá-la.
   Alcançável em dois casos: conta bloqueada por tentativas feitas em outro
   lugar, ou senha trocada no servidor. Não foi corrigido aqui de propósito: o
   plano não especifica nenhum fluxo de navegação, e inventar UI sem plano é o
   que o processo alerta contra. Candidato a um plano próprio.
2. **A credencial vive até o processo morrer, sem caminho de limpeza.** Não há
   logout: o record fica acessível pela instância de `BackendClient` enquanto o
   app viver. É consequência direta de adiar o refresh token; some quando ele
   existir. *(Fechado em 2026-10-03: a senha não é mais retida e há "Sair".)*
3. **`autofillHints` sem `AutofillGroup`** provavelmente não faz nada no
   aparelho: o gerenciador de senhas do Android precisa do grupo (e de
   `finishAutofillContext()`) para oferecer preenchimento.
4. **A renovação e a recusa são provadas contra um servidor RPC falso**
   (`dart:io`, espelhando o protocolo do Serverpod 3.4.13), não contra o
   servidor vivo — `apps/acs/test/support/fake_rpc_server.dart`. Quem executou
   evitou de propósito gastar o bloqueio de 5 tentativas do `ACS-001` com
   senhas erradas. A prova é do caminho, não do servidor real.

---

## Login passwordless do paciente (RF01) — o que ficou de fora (2026-09-19)

O login do paciente deixou de ser o token HMAC de desenvolvimento: o app envia CPF (validado por
dígito verificador, e hasheado no servidor em HMAC-SHA-256 com `CPF_HASH_PEPPER`), data de
nascimento e o código de 6 dígitos recebido, e o servidor só emite a sessão depois de
`auth.verifyOtp`. As decisões de escopo estão em
`docs/superpowers/plans/2026-09-18-rf01-login-passwordless-otp.md`. O que este plano **não** fez:

- **O provedor de SMS não foi escolhido.** Hoje `SMS_GATEWAY=log` escreve o código no log do
  servidor e só é aceito em `development`; fora dele o boot falha nomeando a variável. Falta a
  decisão de produto/infra: conta no provedor, custo por mensagem, contrato, e o que fazer
  quando o envio falha.
- **Não existe coluna de telefone** em `users`/`patients` nem no ER do PRD. O gateway de
  desenvolvimento recebe o CPF formatado como identificador de destino; um gateway real precisa
  do número, o que é decisão de produto — e dado pessoal novo, a coletar com finalidade e
  retenção próprias (`spec/lgpd_data_audit.md`).
- **A sessão do paciente passou a 1 hora** (`AuthEndpoint.patientSessionLifetime`), e não aos 15
  minutos do padrão, aplicando LGPD-RT06. O motivo: o código OTP não pode ser reapresentado como
  a senha do ACS pode, então **não há renovação silenciosa** para o paciente — com 15 minutos
  ele receberia um SMS novo a cada 15 minutos. O ACS continua com 15 minutos e renovação pelo
  refresh token (desde 2026-10-03; antes, credencial mantida em memória, RF07). A assimetria é deliberada e está escrita em
  `spec/lgpd_design.md`.
- **Refresh token rotativo continua ausente para o paciente** (LGPD-RT06; o do ACS existe desde 2026-10-03) — é o que permitiria voltar o TTL do
  paciente aos 15 minutos sem quebrar a experiência.
- **MFA/TOTP do ACS: entregue em 2026-10-02** (achado F5 de `spec/security_assessment.md`; ver a entrada "MFA do ACS" do app).
- **Sem limite de tentativas por origem (IP).** O teto de 5 verificações é por desafio e o
  intervalo de 60 s é por CPF; nada olha de onde vem a chamada — o mesmo vale para o pedido de
  código em si, que não tem limite nenhum.
- **`requestOtp` não equaliza o TEMPO de resposta** — é a lacuna que o comentário de
  `requestOtp` em
  `backend/sinalacs_server/lib/src/application/auth/passwordless_auth_service.dart` chama de
  "registrada na Task 8", e é por isso que ela está nesta lista. O caminho válido faz um
  `latestOpen`, um `save` e o envio do código, enquanto as recusas retornam na **primeira**
  condição — logo depois do `findByCpfHash` e **antes** do `latestOpen`, sem nenhuma outra ida ao
  banco. **Dois canais, os dois abertos:** o CONTEÚDO (status + payload) distinguia os dois casos
  deterministicamente — era o oráculo, e é o que a subseção abaixo fecha —, e o RELÓGIO **continua
  distinguindo**, e com uma amostra de cada lado, sem estatística nenhuma (a subseção abaixo traz a
  medição). Este parágrafo dizia antes que "a propriedade anti-enumeração vale no conteúdo e
  **não** no relógio" — o inverso, e a frase errada é parte do mesmo defeito. Com gateway de verdade o termo dominante é a ida ao provedor; a correção é tirar
  o envio do caminho de resposta (ou impor um piso constante de tempo sobre o handler inteiro), e é
  endurecimento para quando o provedor for escolhido — não deste estágio, em que `SMS_GATEWAY=log`
  não faz chamada nenhuma. O piso que resolve é o do handler inteiro, e não o do envio: o delta que
  separa é **anterior** a qualquer envio.
- **Biometria e leitura de QR Code.** `spec/sys_flow.md` lista "SMS/OTP, biometria ou QR Code
  gerado pelo ACS" como critérios de aceite do RF01. Biometria não existe em nenhum app; a
  leitura de QR pelo app do paciente também não — o onboarding pede para "colar ou digitar o
  código do convite".

### O oráculo de `requestOtp` — e a frase invertida deste documento (2026-09-19)

O review final de branch não aprovou o RF01 por um achado **Critical**: `requestOtp` respondia
**diferente na segunda chamada** conforme o par CPF + nascimento existisse. Medido contra a stack,
quatro chamadas por caso, só status e classe de exceção:

```
par cadastrado, nascimento certo   -> 200, 400, 400, 400
par cadastrado, nascimento errado  -> 200, 200, 200, 200
CPF não cadastrado (DV válido)     -> 200, 200, 200, 200
```

Duas chamadas decidiam o par — o código de status **era** o oráculo. O mecanismo é de ordem: a
recusa (`record == null || !_sameDay(...)`) retornava **antes** do `latestOpen`, então o `throw` do
intervalo de 60 s só era alcançável depois de o par estar confirmado. **A precondição era o
segredo**, e o comentário que ficava ali dizia o contrário ("lançar é seguro: chegar neste ponto
exige CPF e nascimento corretos, então a exceção não revela nada") — foi assim que o defeito
atravessou uma revisão anterior, e o mesmo raciocínio invertido é o da frase que este documento
trazia.

**Corrigido em 2026-09-19:** o intervalo mínimo deixou de lançar e passou a `return` em silêncio —
não cria desafio, não envia SMS, não audita e não produz sinal distinguível. O mesmo probe, depois
da correção, devolve `200, 200, 200, 200` nos três casos; uma única linha no log do gateway para os
doze chamados. A igualdade ganhou teste nos dois níveis — unitário e endpoint (`duas chamadas
respondem o mesmo com e sem cadastro`) —, porque ela não existia: dois testes no mesmo `group`
prendiam um a igualdade na primeira chamada e o outro a violação na segunda, e os dois ficavam
verdes. O que mudou, as duas transcrições e a tabela de mutantes estão na seção fix-10 do
relatório da Task 4 — `task-4-report.md`, na pasta de trabalho do SDD (`.superpowers/sdd/…`, fora
do versionamento, como as rodadas anteriores; por isso o vínculo aqui é por nome, e não um link).

**A frase que este documento trazia estava invertida.** Dizia que "a propriedade anti-enumeração
vale no conteúdo e **não** no relógio": é o inverso. O **conteúdo** (status + payload) era o que
distinguia os dois casos, deterministicamente — esse era o oráculo, e era o que faltava fechar.
Depois desta correção é o conteúdo que está igual. **O relógio continua desigual, e é o outro
oráculo — medido, não suposto.**

#### O canal de tempo está ABERTO (2026-09-19)

Medido contra a stack, 300 amostras keep-alive por caso, tempo de parede do `POST /auth`, uma
conexão só (na 1ª chamada do par correto o desafio é apagado antes de cada amostra, fora da janela
medida — sem isso a amostra cairia no ramo do intervalo mínimo):

| caso | p50 | faixa [min, max] |
|---|---|---|
| par correto, 1ª chamada | **3,21 ms** | 2,76 – 6,63 ms |
| par correto, dentro do intervalo mínimo | 0,80 ms | 0,51 – 1,41 ms |
| CPF não cadastrado (DV válido) | **0,39 ms** | 0,29 – 1,01 ms |
| CPF cadastrado, nascimento errado | 0,46 ms | 0,31 – 0,84 ms |

- **A separação não precisa de estatística.** As faixas do par correto e do CPF não cadastrado
  **não se cruzam**, e os 90 000 pares cruzados separaram: **uma amostra de cada lado decide**.
  Duas medições independentes, com o mesmo desenho (keep-alive, 200 a 400 amostras por caso),
  concordam dentro de poucos por cento: o revisor mediu 3,21 ms contra 0,40 ms; esta rodada mediu
  3,21 ms contra 0,39 ms.
- **Dentro do intervalo mínimo a diferença encolhe, mas não some:** esse ramo faz o `latestOpen` e
  mais nada, e ainda assim **fica acima do acaso** (AUC 0,675 na medição intercalada do review
  final, contra 0,5 de uma separação ao acaso). ~~era ~2× a recusa (AUC 0,956 nesta medição; 0,981,
  0,996 e 0,986 nas três do revisor)~~ A **magnitude** medida em blocos **não se reproduziu** no
  desenho intercalado (p50 1,19×, contra os ~2× daqui), e o motivo é o ambiente em que foi medida,
  não o fenômeno — ver o fim desta subseção. O que **as duas medições sustentam** é o piso — o sinal
  nunca chega a indistinguível —, e é isso que se afirma. É o único destes números que **admite
  interseção**: nesta medição as faixas se cruzam em parte, e o revisor registrou o mesmo em uma
  das rodadas dele.
- **O delta é o `latestOpen`, e isso agrava o caso.** Ele só é alcançado **depois** de o par estar
  conferido, então o relógio **não é ruído alheio ao segredo: é correlacionado com ele** — quem
  responde rápido é quem não passou pela conferência. E ele é **anterior a qualquer envio**: o
  ramo do intervalo mínimo, que não envia, não grava e não audita, já separa. A correção
  registrada (tirar o envio do caminho de resposta) ataca o termo do provedor e **não alcança esse
  delta**; o que alcançaria é um piso constante sobre o **handler inteiro**, que é medida mais
  forte do que a registrada e só vale acima do caminho mais lento.
- **`verifyOtp` tem canal de tempo próprio, e é a barreira MAIS BAIXA** — ver o item com dono na
  lista abaixo. Ele existe, é decidível e **não precisa da data de nascimento**: onde o
  `requestOtp` no par correto separa com AUC **1,0000** (os extremos nem se tocam), o `verifyOtp`
  separa com **0,9636** — **mais fraca** que aquela, e era "e mais forte" o que esta linha dizia.
  Quem for atacar a enumeração do RF01 começa por ele, e não pelo caminho mais caro.
- **A ordem entre as duas últimas linhas da tabela não é fato.** "CPF não cadastrado" (0,39 ms) e
  "CPF cadastrado, nascimento errado" (0,46 ms) estão a menos de 0,1 ms um do outro, e essa ordem
  **troca de sinal entre ambientes** — é artefato de medição, não canal, e não deve ser lida como
  propriedade de nenhum dos dois caminhos. Canal é a distância entre essas duas linhas e o par
  correto, essa sim estável e grande.

O parágrafo anterior a esta subseção dizia "o que **não se mede** com confiança é o tamanho da
diferença", e a seção dizia "resíduo, não sinal": as duas frases eram **falsas**, e são a mesma
classe de afirmação de segurança não medida que deixou o C1 atravessar duas revisões. O parágrafo
se contradizia sozinho — se o relógio não se medisse, não haveria nada a corrigir nele.

**O que a correção não resolve** — ninguém deve ler "oráculo fechado" como "enumeração inviável":

- **`verifyOtp` tem canal de tempo próprio, e não é regressão desta rodada.** Medido em blocos, em
  2026-09-19: ~~CPF cadastrado com desafio aberto ~4,0 ms (p50) contra ~1,7 ms do CPF não
  cadastrado, faixas sem interseção, **AUC 0,997** na medição do revisor (0,990 sem desafio
  aberto)~~ Na medição **intercalada** do review final, **4,58 ms contra 3,62 ms, com as caudas se
  tocando, AUC 0,9636** — e é este o número que o registro sustenta. A comparação "**e mais
  forte**" que esta lista trazia não se sustenta de nenhum dos dois lados: o canal do `requestOtp`
  no par correto é AUC **1,0000**, e o daqui é **mais fraco** que aquele.
  **Uma chamada responde "este CPF é paciente da unidade" — e sem precisar da data de
  nascimento**, que é justamente o fator que `requestOtp` exige. Não foi introduzido aqui e não
  estava em brief nenhum; existe porque o caminho do CPF cadastrado faz o `latestOpen`, o
  `registerAttempt` e a auditoria, e o do CPF inexistente só faz o `findByCpfHash`. A **Global
  Constraint nº 2** (anti-enumeração) é do **RF**, não do método: quem ler "oráculo fechado" nesta
  seção fecha o RF01 achando que ela vale, e ela **não vale em `verifyOtp` tampouco**.
  **Dono: quem implementar o gateway de SMS real** — o piso de tempo (sobre o handler inteiro, ver
  acima) só faz sentido quando o provedor for escolhido, e é a mesma pessoa que vai mexer no
  caminho de envio; hoje esse dono não existe, e o provedor continua não escolhido nesta lista.
- **Não entrou limite nenhum.** O caminho de sonda continua sem rate limit por origem, que é a
  lacuna já registrada nesta lista. Quem varre continua varrendo à vontade; o que acabou foi o
  sinal determinístico de volta. Cada acerto ainda manda um SMS para a pessoa.
- **A UX perdeu o aviso de "aguarde um minuto".** Com o intervalo mínimo silencioso, quem pede o
  código duas vezes em menos de um minuto não vê aviso nenhum e fica esperando um SMS que não vem.
  O servidor não pode mais dizer isso — quem sabe quando pediu por último é o **app**, e é lá que a
  mensagem passa a morar. Hoje o app não implementa a espera: a tela não diz nada. **Dono: quem
  mexer no app do paciente** — este RF01 não fecha com a mensagem de volta ao servidor, porque ela
  só seria alcançável por quem já acertou o par.

  **FECHADO em 2026-09-21.** `_PatientLoginScreenState` (`apps/patient/lib/app/app.dart`) passou a
  guardar `_ultimoPedidoEm` no sucesso de `requestOtp` e a desabilitar `enter_button` por 60s
  (`_otpResendCooldown`), com um `Semantics(liveRegion: true)` avisando quanto falta —
  inteiramente do lado do app, sem depender de resposta nenhuma do servidor. Coberto por
  `passwordless_login_test.dart`: "depois de pedir o código, 'Entrar sem senha' fica desativado
  com aviso de cooldown".
- **`otp_challenges` não tem retenção** (Minor do mesmo review). Não há `DELETE` nem limpeza em
  `lib/` nem em `bin/`: desafios expirados e consumidos ficam para sempre, cada um com `userId`,
  dois timestamps e `codeHash` — "Crítico — credencial" no inventário de
  [`spec/lgpd_data_audit.md`](spec/lgpd_data_audit.md) —, então a tabela é um rastro de tentativas
  de login sem prazo. **Registrado, não implementado**: depende de decidir prazo e de quem executa
  a limpeza, como as outras retenções do projeto.

#### A medição intercalada do review final: a magnitude é do ambiente (2026-09-19)

O review final de branch mediu de novo, com desenho **intercalado**, os números desta subseção — e
**dois deles não se reproduziram**. Cada caso foi medido ao lado do seu controle, na mesma conexão
keep-alive, 250 pares por bloco, por HTTPS via Traefik: é esse desenho que separa o custo fixo do
ambiente do delta que se quer medir.

| comparação | em blocos (este registro) | intercalada (review final) |
|---|---|---|
| `requestOtp` no intervalo mínimo × recusa | ~2×; AUC 0,956 / 0,981 / 0,996 / 0,986 | p50 **1,19×**; AUC **0,675** |
| `verifyOtp`, CPF existe × não existe | ~4,0 × ~1,7 ms; AUC 0,997 / 0,990 | **4,58 × 3,62 ms**, caudas se tocando; AUC **0,9636** |
| `requestOtp` no par correto × CPF não cadastrado | 3,21 × 0,39 ms, sem interseção | **AUC 1,0000**, separação perfeita |

- **O encolhimento do ramo do intervalo mínimo tem mecanismo, e é por isso que o número antigo não
  é falso — é do ambiente.** O ramo do intervalo mínimo e a recusa fazem **uma consulta indexada
  cada** (o primeiro acha uma linha em `otp_challenges`, o segundo acha zero em `users`), e o
  TLS/Traefik soma ~0,5 ms a **toda** chamada, comprimindo a razão: o registro foi medido na 8080
  em texto claro, e contra a 443 a razão encolhe. O que **sobrevive às duas medições** é o piso — o
  sinal nunca chega a indistinguível —, e é o que este documento afirma. A razão exata, essa, só
  vale junto com o ambiente em que foi medida.
- **A ordem entre "CPF não cadastrado" e "nascimento errado" não é fato** — é artefato de menos de
  0,1 ms, que **troca de sinal entre ambientes**; a ressalva ficou ao pé da tabela, na lista de
  bullets acima.
- **A AUC 0,997 do `verifyOtp` vem da re-revisão da rodada 10** — a do commit `cdac75b`, cujos
  achados viraram a rodada 11 —, está no registro da sessão e foi citada no brief da rodada 11, que
  é de onde este documento a copiou. O review final **não a sustenta**: a medição intercalada dele
  é **0,9636**, com as caudas se tocando, e ele foi explícito nisso. As duas ficam no registro; o
  que muda é a conclusão, que passa a ser a que as duas medições juntas sustentam — o canal do
  `verifyOtp` **existe, é decidível e não precisa da data de nascimento**, e é a **barreira mais
  baixa** do RF01, não a mais alta. **Número sem medição viva não sustenta afirmação de segurança**
  — a mesma classe de defeito que esta sessão inteira caçou, uma vez mais.
- **Duas frases da mesma classe continuam dentro do código, e não foram tocadas nesta rodada.** No
  arquivo da doc do `requestOtp`
  (`backend/sinalacs_server/lib/src/application/auth/passwordless_auth_service.dart`), o ramo do
  intervalo mínimo é descrito com "AUC 0,96 a 0,99 entre duas medições independentes" (`:150`) e
  "já é ~2× mais lento que a recusa" (`:159`) — nenhuma das duas sobrevive à medição intercalada
  (0,675 e 1,19×) —, e a doc do `verifyOtp` (`:226-230`) repete "faixas sem interseção" e "mais
  forte que ele", que é a comparação que o review final desmentiu. ~~**Registrado, não corrigido**:
  esta rodada mexe em `apps/patient/lib/app/app.dart` e neste `PROGRESS.md`, e só neles.~~ **Dono:
  quem implementar o gateway de SMS real** — o mesmo dono do piso de tempo na lista acima, e quem
  vai mexer nesse arquivo de qualquer jeito. É a mesma classe do comentário do app do paciente que
  esta rodada corrigiu: afirmação em código que a medição deixou de sustentar, no arquivo que o
  próximo leitor do RF01 abre.

  **FECHADO em `cb63566`** (rodada final 2, mesmo dia). O motivo do adiamento era de escopo — o brief
  listava dois arquivos —, e a discordância de quem executou ("são quatro linhas, sem risco de
  comportamento") estava certa: eu a aceitei. As quatro cláusulas foram corrigidas **no arquivo de
  código**, `+28 −11`, **só linhas `///`** (conferido: nenhuma linha alterada deixa de começar com
  `///`). O que entrou: `:154` o ramo do intervalo mínimo passou a "acima do acaso — AUC 0,675 na
  medição intercalada, contra 0,5", com a magnitude declarada **do ambiente** e o mecanismo (uma
  consulta indexada de cada lado, mais o custo fixo do TLS/Traefik que comprime a razão); `:167`
  "mais lento que a recusa — p50 1,19×"; `:239-243` o `verifyOtp` virou "**as caudas se tocando**:
  AUC 0,9636" e "**mais FRACO que ele**", com a razão explícita: o que faz dele o mais perigoso
  **não é a força, é o custo** — não precisa da data de nascimento. A manchete do `requestOtp`
  (AUC 1,0000, reproduzida pelo review final) **não foi tocada**, e ganhou só a nota de que os
  **absolutos** são da era do texto claro, com os do TLS ao lado (~4,7 ms e ~0,93 ms) e a separação
  igual — sem ela o arquivo passaria a ter absolutos de dois ambientes, os dois datados de
  2026-09-19, lendo como contradição. **O "~1,5×" que eu tinha escrito no lugar desses dois pares
  foi removido** (re-review escopado, Minor): ele era derivado, não medido, e não fechava com o
  resto do parágrafo — um custo aditivo não escala os **dois** absolutos pelo mesmo fator, e a
  aritmética confirma: ~×1,46 num e ~×2,38 no outro. É o mesmo defeito que esta rodada inteira
  caçou, uma última vez, e por isso o parágrafo passou a **dar os dois pares medidos** em vez do
  fator que os ligava. `dart test` → **276, exit 0**; `dart analyze` → exit 0 (33 `info`, **nenhuma** deste
  arquivo). As referências `:150`/`:159`/`:226-230` desta entrada **não apontam mais** para as
  frases — hoje são `:154`, `:167`, `:239-243` —, e o original fica riscado acima como registro.

  **Uma ressalva que fica, e é menor:** a frase do código que remete a esta lista diz *"registrada
  com dono no `PROGRESS.md`"*. Ela não é falsa — o dono **está** registrado —, mas lê mais forte do
  que é, porque **o dono é um papel sem ocupante**: "quem implementar o gateway de SMS real", e o
  provedor continua não escolhido. Fica como está, com esta nota.

### Um defeito do RF02 que esta entrega mediu — com dono (2026-09-19)

> **Resolvido:** `completeEnrollment` já emite `patientSessionLifetime`; `onboarding_endpoint_test.dart` prende o valor. Esta seção descreve o defeito como foi medido.

`onboarding_endpoint.dart:62` faz `issueToken(user)` — o default de **15 minutos** — para
`role: UserRole.patient`, e o app consome esse token como sessão
(`apps/patient/lib/core/network/backend_client.dart:259-273`). Ou seja: **há dois caminhos de
sessão do paciente e eles discordam** — 1 hora no login passwordless (RF01) e 15 minutos no
onboarding (RF02) —, e no onboarding a renovação silenciosa também não existe, porque não há
credencial para renovar: quem conclui o cadastro cai para fora em 15 minutos, sem aviso e sem
caminho de volta que não seja entrar de novo pelo código.

Não foi corrigido aqui de propósito: é mudança de comportamento de outra entrega. **Dono: o
RF02.** O que torna o registro necessário está escrito em dois lugares, e nenhum deles é o
comentário do `auth_endpoint.dart` — esse declara o TTL de 1 hora **deste** caminho e o motivo
(o código OTP não se reapresenta, então não há renovação silenciosa) e aponta a lacuna do
onboarding, mas não fala em leitor futuro. Quem diz, com essas palavras, é o **par de testes de
integração** que prende cada metade da assimetria: `institutional_login_test.dart` (15 minutos,
ACS) escreve que "os dois números precisam aparecer na suíte, senão um leitor futuro lê a
diferença como descuido e 'conserta' um dos lados", e `passwordless_login_test.dart` (1 hora,
paciente) que é "a diferença entre as duas que precisa continuar sendo lida como decisão, não
como descuido" — o plano registra o mesmo nas Global Constraints. O lado mais provável de um
leitor "consertar" é o TTL do login, que tem motivo para ser 1 hora.

**FECHADO (2026-09-21).** `onboarding_endpoint.dart:62` passou a chamar `issueToken(user,
lifetime: AuthEndpoint.patientSessionLifetime)`, alinhando `completeEnrollment` com `verifyOtp`:
os dois caminhos de emissão do papel `patient` agora concordam em 1 hora, pelo mesmo motivo (nem
o código OTP nem o convite de uso único se reapresentam, então nenhum dos dois tem renovação
silenciosa). `onboarding_endpoint_test.dart` ganhou a mesma asserção de TTL que
`passwordless_login_test.dart` já tinha para `verifyOtp`, usando `AlertRuntimeHarness.tokenLifetime`.
O comentário de `apps/patient/lib/core/network/auth_session.dart:73`, que descrevia a hora como
regra só do login, foi atualizado para descrever os dois caminhos.

## Finalização do app paciente — telas soltas do menu "Mais" (2026-09-21)

Plano de fechamento de `apps/patient` que sobrou de fora do que RF01–RF06 cobriam. As mudanças
de RF02 (TTL do onboarding) e a UX de cooldown do OTP já estão registradas acima, nas seções que
elas fecham; esta entrada cobre o resto:

- **Perfil clínico deixou de ser protótipo.** `ClinicalProfileScreen` lia/escrevia um
  `Map<String, bool>` local que o botão "Salvar" descartava. Ganhou dois métodos novos em
  `PatientsEndpoint` — `myChronicConditions`/`updateChronicConditions`, papel `patient` apenas,
  `patientId` sempre do token (INV-05) — que leem/gravam `patients.chronicConditionsEncrypted`
  de verdade (AES-256-GCM), fechando a lacuna que o comentário de `OrmPatientDirectoryStore` já
  antecipava ("quando um endpoint de cadastro existir..."). Catálogo de condições
  (diabetes, hipertensão, uso contínuo de insulina) vem de `spec/idea.md`, não inventado. Coberto
  por `patient_directory_service_test.dart` (fake), `patient_chronic_conditions_endpoint_test.dart`
  (Postgres + cifra reais) e um grupo novo em `patient_app_mvp_test.dart`.
- **"Dúvidas" foi removida**, não terminada — a tela era chat com resposta automática fixa, sem
  backend, e contradizia a exclusão explícita de mensageria assíncrona do escopo MVP
  (`spec/PRD_system.md` §6.1). Saiu do enum `PatientDestination`, do menu "Mais" e do código.
- **`spec/validation_report.md` §5 estava com três linhas erradas** para o app paciente: Perfil
  clínico e Perguntas foram atualizadas por este plano; Lembretes já estava real desde antes
  (`RemindersScreen`/`sqflite_reminder_store.dart`/`flutter_local_notifications`) e a linha "hardcoded"
  nunca tinha sido corrigida — achado desta rodada de exploração, não mudança de comportamento.
- **`spec/ux_accessibility_assessment.md`**: 'Concluir cadastro' (onboarding) saiu de "não medido"
  — era o mesmo defeito de nó inerte dos outros três sítios já corrigidos (`Semantics(button: true)`
  sem `MergeSemantics`). Medido e corrigido.

**Atualização (2026-09-21, mesmo dia):** o painel "Meus Dados" acima descrito como fora de escopo
**entrou nesta mesma rodada**, afinal. `PatientsEndpoint.myData` agrega `patients` + `users` +
`consent_logs` + `triage_sessions`/`alerts` (só `resultRisk`/`riskLevel` e o timestamp — nunca o
conteúdo cifrado de uma triagem nem a localização de um alerta) num único `PatientDataOverview`,
três modelos novos em `models/api/` (`PatientDataOverview`, `PatientConsentRecord`,
`PatientRiskEvent`, nenhum com `table:`, então sem migração). Tela `MyDataScreen` no app, no lugar
que "Dúvidas" deixou vago no menu "Mais"; "exportar" é copiar o JSON para a área de transferência —
sem infraestrutura de e-mail/arquivo nesta etapa. Coberto por
`patient_data_overview_service_test.dart` (fake), `patient_data_overview_endpoint_test.dart`
(Postgres real, as quatro tabelas) e um grupo novo em `patient_app_mvp_test.dart` (inclusive a
varredura de nó de botão inerte, que 'Concluir cadastro' mostrou não ser dispensável). Fica de fora
ainda: revogar consentimento a partir deste painel (já existe em `RemindersScreen`/onboarding) e o
SLA de 15 dias para pedidos que exigem intervenção humana — isso é processo, não código. Endurecimento
de segurança do RF01 (rate limit por IP, canal de tempo, retenção de `otp_challenges`, refresh token)
continua como já registrado acima, sem dono novo.

## Direitos do titular no app paciente — LGPD-RF05 e LGPD-RF08 (2026-09-28)

"Meus dados" deixou de ser só leitura. O paciente agora:

- **concede ou revoga** por conta própria as duas finalidades opcionais
  (`localReminders`, `segmentedPush`) — `patients.updateConsent` grava uma
  linha nova assinada em `consent_logs` (append-only; a assinatura sai de
  `signedConsentLog`, a mesma função do onboarding). Revogar pede confirmação
  explícita. Revogar lembretes cancela na hora os lembretes agendados no
  aparelho, e o espelho local (`ConsentPreferences`) passa a ser alinhado ao
  servidor sempre que "Meus dados" carrega — o que também resolve o aparelho que
  entrou pelo login OTP sem passar pelo onboarding;
- **pede exclusão** (`patients.requestDataDeletion`, idempotente enquanto houver
  uma aberta) ou **correção** (`patients.requestDataCorrection`, texto livre de
  até 500 caracteres, cifrado com AES-256-GCM em `data_subject_requests`), e vê
  a situação e o prazo (15 dias) de cada pedido.

O que **não** foi feito, de propósito:

- **Ninguém atende os pedidos.** `status` só é escrito como `open`: o backoffice
  (`apps/admin`) ainda roda sobre `MockAdminDataSource`. O prazo de 15 dias é
  exibido mas não é cumprido por sistema nenhum. **Dono:** quem der backend ao
  admin.
- **`healthDataProcessing` não tem interruptor.** É a base legal do app inteiro,
  inclusive do alerta de emergência; `updateConsent` recusa essa finalidade com
  `DataRightsException` e aponta para o pedido de exclusão. Parar o tratamento
  depois da exclusão atendida (LGPD-RF07, "em até 15 dias") depende do mesmo
  atendimento acima.
- **Corrida de dois pedidos de exclusão simultâneos — resolvida (2026-09-29).**
  A criação passou a ser atômica (`createDeletionRequestIfNoneOpen`, com
  `pg_advisory_xact_lock` por titular, já que o Serverpod não declara `WHERE` em
  índice e um índice único parcial não é possível); ver "Fechamento das
  pendências do paciente".
- **`segmentedPush` tem leitor no código e o aviso chega a um emulador Android** (RF14, ver
  "RF14: Gorush e FCM provados no emulador"): falta hospedar o Gorush fora do Compose local,
  iOS/APNs e um teste em aparelho físico.

## QR Code do onboarding e documentos legais (2026-09-29)

Plano: `docs/superpowers/plans/2026-09-29-qr-onboarding-e-documentos-legais.md`, branch `fix/patient`.

**RF02 de ponta a ponta.** O ACS ganhou "Mais › Convidar paciente": escolhe um paciente da própria microárea, gera o convite (`onboarding.generateEnrollmentToken`, que existia sem nenhum chamador) e mostra o QR Code (`qr_flutter`), com validade de 15 minutos e o código em texto para digitação. O paciente lê com "Ler QR Code com a câmera" (`mobile_scanner`, permissão `CAMERA`, câmera opcional na instalação), que preenche o mesmo campo do código; QR que não tem o formato do convite (43 caracteres base64url) é recusado sem sobrescrever o campo. O PRD citava `qr_code_scanner`, pacote descontinuado — trocado por `mobile_scanner`.

**LGPD-RF18/RF19/RF10.** Termo de Uso e Política de Privacidade versão 2026.1 no app paciente (`lib/core/legal/legal_documents.dart`): resumo visual em passos (fluxo do dado), texto completo em seções, histórico de versões. Abrem antes do cadastro (link no login e no onboarding) e depois em "Mais › Privacidade e termos". O aceite é explícito, desmarcado por padrão e obrigatório; vira `ConsentPurpose.termsOfUse` em `consent_logs`, na mesma transação dos outros consentimentos, com `version = consentPolicyVersion`. `updateConsent` recusa alterá-lo. Um teste do app falha se a versão exibida divergir da carimbada pelo backend.

**Ficou de fora, de propósito:**
- O texto 2026.1 precisa de revisão jurídica e dos dados reais do controlador e do encarregado (hoje genéricos: "Secretaria Municipal de Saúde do seu município").
- Aviso de mudança com 15 dias de antecedência e novo aceite quando a versão mudar: só existe uma versão; não há mecanismo de reaceite no login. — **reaceite resolvido**, ver "Aceite do termo no login OTP" (o aviso de 15 dias segue pendente).
- Pacientes que entram por CPF + OTP (RF01) sem ter passado pelo onboarding nunca aceitaram o termo — o seed inclusive. Falta um aceite no primeiro login. — **resolvido**, ver "Aceite do termo no login OTP".
- Canal de dúvidas é "fale com o ACS ou a UBS", sem canal digital próprio.
- A página da câmera (`_CameraScanPage`) só roda no aparelho; os testes cobrem o fluxo com um leitor duplo. Validar no emulador com um QR gerado pelo app do ACS.
- Contagens de teste depois desta entrega: backend 329, paciente 167, ACS 168.

## Aceite do termo no login OTP (2026-09-29)

Plano: `docs/superpowers/plans/2026-09-29-aceite-do-termo-no-login-otp.md`, branch `fix/patient`.

**O que existe.** `patients.acceptTermsOfUse` (só paciente) grava `termsOfUse` `granted` com `consentPolicyVersion` em `consent_logs`, pela mesma trilha assinada de `updateConsent`, que continua recusando esse propósito. No app, depois de `verifyOtp` o login (hoje consulta `hasAcceptedCurrentTerms`; ver "Fechamento das pendências do paciente") lê o status; se a linha mais recente de `termsOfUse` não for `granted` na versão `legalDocumentsVersion` (`needsTermsAcceptance`), abre `TermsAcceptanceScreen`. Isso cobre pacientes do seed e de OTP sem onboarding, e o reaceite quando a versão mudar. A sessão do onboarding de 1 hora, que estava no escopo pedido, já estava no código; só os comentários e docs foram corrigidos.

**Ficou de fora, de propósito:**
- O aceite **não é portão duro**: "Agora não" e uma falha de `hasAcceptedCurrentTerms` entram direto, porque o alerta de urgência nunca pode ficar atrás de uma tela de aceite. Consequência: quem pula pode seguir sem aceite registrado, e o aviso volta no próximo login.
- Aviso de mudança com 15 dias de antecedência: feito depois (ver "Menores do push e aviso de 15 dias"); revisão jurídica do texto segue pendente.
- ~~`acceptTermsOfUse` grava uma linha nova a cada chamada~~ — resolvido na rodada "Menores adiados e push do paciente": o aceite é idempotente e atômico.
- Contagens de teste depois desta entrega: backend 333, paciente 182, ACS 168.

## Fechamento das pendências do paciente (2026-09-29)

Plano: `docs/superpowers/plans/2026-09-29-fechamento-de-pendencias-do-paciente.md`, branch `fix/patient`.

**O que foi fechado:**
- O login por OTP consulta `patients.hasAcceptedCurrentTerms` (um `bool`) em vez de ler o painel "Meus dados" inteiro: menos dados no aparelho e nenhuma linha de auditoria de leitura por login. A consulta tem teto de 3 s.
- `acceptTermsOfUse` ficou idempotente: com o aceite vigente já gravado, devolve a linha existente e não cresce o histórico.
- Pedidos de exclusão simultâneos deixam uma só linha aberta (lock por titular). A repetição agora também é auditada, com `result: repeated`.
- A linha de auditoria de consentimento passou a levar o `resourceId` da linha gravada.
- Câmera do onboarding: o toque duplo em "Ler QR Code" abre uma leitura só, e o aviso de QR inválido some quando a pessoa volta a digitar.
- O texto de uma correção que falhou volta ao reabrir o diálogo; é descartado ao enviar ou cancelar.
- ACS: o convite expirado some da tela e pede um novo.

**Ficou de fora, de propósito:**
- `ipHash` e `userAgent` `nao-aplicavel-painel-titular` em `consent_logs` seguem como estão: é um marcador deliberado de ausência (o request HTTP já é auditado em `audit_logs`), documentado em `signed_consent_log.dart`. Guardar o IP do titular ali é uma decisão de privacidade, não um conserto.
- A prova da corrida cobre o store ORM, não o endpoint: o endpoint grava `audit_logs`, que tem FK para `users` e cadeia de hash, e a limpeza manual do grupo sem rollback quebraria os dois.
- Backoffice que atende os pedidos e o push (RF14) seguem pendentes; o aviso de 15 dias foi feito depois, ver "Menores do push e aviso de 15 dias".
- Contagens de teste depois desta entrega: backend 346, paciente 182, ACS 172.

## Menores adiados e push do paciente (2026-09-29)

Plano: `docs/superpowers/plans/2026-09-29-menores-adiados-e-push-do-paciente.md`, branch `fix/patient`.

**O que foi fechado:**
- `patients.acceptTermsOfUse` é atômico: `recordConsentUnlessCurrent` grava sob advisory lock por titular, então duas chamadas simultâneas deixam uma linha só (teste de corrida contra Postgres real, três chamadas).
- Os advisory locks por titular usam a forma de duas chaves (`lockPerSubject`, namespaces em `subject_lock.dart`), que não divide espaço com a chave única da cadeia de auditoria.
- O diálogo de correção não fecha mais ao tocar fora (`barrierDismissible: false`); só "Cancelar" descarta o rascunho. Dois testes de caracterização entraram: cancelar limpa o rascunho e o botão de ler QR volta a funcionar depois que o leitor lança.
- **RF14, lado do paciente:** tabela `push_tokens`, `devices.registerPushToken` (só paciente, só com o consentimento `segmentedPush` vigente, uma linha por token, o token de outro titular troca de dono) e revogação de `segmentedPush` apaga os tokens do titular. No app, `PushTokenSource` (padrão `NoPushTokenSource`, sem Firebase) registra o aparelho depois do login, do onboarding e ao conceder "Avisos da equipe", em silêncio: recusa ou falha nunca atrasa a home nem o alerta.

**Achados do revisor final, corrigidos:** o consentimento era lido fora da transação do registro, então registrar × revogar em paralelo deixava um token ligado a um titular que já tinha revogado; hoje `registerIfConsented` lê e grava sob um lock por titular, e a revogação (`deleteAllFor`) espera o mesmo lock (teste de corrida de 40 iterações contra Postgres real). E um aparelho apresentado por quem não consentiu perde o vínculo do titular anterior, porque o token prova que o aparelho está na mão de outra pessoa.

**Ficou de fora, de propósito:**
- ~~Revogar grava o `denied` e apaga os tokens em duas operações~~ — resolvido na rodada "Menores do push e aviso de 15 dias": as duas coisas são uma transação só.
- `devices.registerPushToken` só grava auditoria na **troca de dono** do token (`push_token`); registrar e repetir não, porque a revogação já deixa `consent_log`.
- ~~Sem teto de tokens por titular; sem teste da fonte que nunca completa; `PushTokenScope.of` sem `maybeOf`~~ — resolvidos na rodada "Menores do push e aviso de 15 dias".
- Envio segmentado, tela de avisos do ACS e captura do token nativo: **o código do envio e a tela foram feitos depois**, ver "RF14: envio de avisos segmentados com Gorush". Depois disso o lado nativo Android do token e a entrega real foram provados no emulador (ver "RF14: Gorush e FCM provados no emulador"); continuam pendentes o Gorush hospedado fora do Compose local e iOS/APNs (§3.2, revisado em 2026-09-29).
- Apagar tokens ao atender o pedido de exclusão: pertence ao backoffice que atende os pedidos, ainda inexistente.
- ~~Aviso de 15 dias de mudança dos termos~~ — feito na rodada "Menores do push e aviso de 15 dias" (a agenda está vazia); revisão jurídica do texto 2026.1 segue pendente.
- O erro de um pedido em "Meus dados" aparece no topo da lista, fora da tela para quem rolou até o botão (anterior a esta rodada).
- Baseline do `dart analyze` do backend: 44 infos (eram 41), os três novos são o mesmo `prefer_initializing_formals` que o resto dos serviços já tem.
- Contagens de teste: backend 359, paciente 190, ACS 172.

## Revisão do RF14: Gorush no lugar do Firebase (2026-09-29)

Só especificação; nenhum código mudou. `spec/stack.md`, `spec/PRD_system.md`, `spec/lgpd_design.md`, `spec/validation_report.md` e o §3.2 de `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` passaram a descrever o envio por **Gorush** (auto-hospedado), com segmentação em SQL restrita a quem consentiu.

- A tabela continua `push_tokens` (já existe); o nome `user_push_tokens` não foi adotado.
- **Riverpod só no push do paciente** (decisão de 2026-09-29): `flutter_riverpod` na captura e no registro do token; o resto segue por `InheritedWidget`.
- **O Gorush não elimina as credenciais:** é relé para FCM/APNs, então Android ainda precisa de uma credencial FCM e iOS de uma chave APNs. A pendência muda de "projeto Firebase" para "hospedar o Gorush e provisionar credenciais".
- Em aberto: o pacote que captura o token nativo em cada plataforma (`firebase_messaging` ou canal nativo no Android; pacote leve de APNs no iOS).
- O plano `2026-09-29-menores-do-push-e-aviso-de-mudanca-dos-termos.md` não é afetado: não toca envio nem provedor.

## RF14: envio de avisos segmentados com Gorush (2026-09-29)

Plano: `docs/superpowers/plans/2026-09-29-rf14-gorush-avisos-segmentados.md`, branch `fix/patient`.

**O que existe:**
- **Infra:** serviço `gorush` no `docker-compose.yml` sob o perfil `push` (sem porta publicada), `GORUSH_URL` no `AppConfig` (vazio desliga o envio), `infra/docker/gorush/` com `config.yml` e README.
- **Backend:** `GorushClient` (`dart:io`, 5 s, poda de tokens inválidos), `NoticeService` e `notices.sendSegmented` (só ACS; microárea do token; consentimento `segmentedPush` mais recente por titular; filtro opcional de crônicos; 0 destinatários não chama o Gorush; auditoria `community_notice` sem o texto).
- **ACS:** `NoticesScreen` real (título 60, mensagem 240, público, resultado "X de Y pacientes").
- **Paciente:** `pushTokenSourceProvider` (único uso de `flutter_riverpod`, ^3.4.3) e `NativePushTokenSource` sobre o canal `sinalacs/push_token`.
- Contagens de teste: backend 390, paciente 197, ACS 178.

**O que NÃO estava provado nessa rodada (superado pela seção "RF14: Gorush e FCM provados no emulador", abaixo):**
- ~~Nenhum teste fala com um Gorush ou com o FCM/APNs de verdade~~ — provado em 2026-09-30 no emulador Android.
- ~~O lado nativo do canal (Kotlin/Swift) não existe~~ — o lado Android existe; o iOS (Swift) continua inexistente.
- As credenciais FCM (conta de serviço) e APNs (chave `.p8`) são da organização e não estão no repositório; o `config.yml` foi escrito sem conferir os nomes das chaves contra uma tag fixa do `appleboy/gorush`, e o Compose usa `:latest` — _superado em 2026-09-30: imagem fixada em `1.22.0` e configuração conferida contra o FCM real_.
- O `async` do app do paciente subiu de 2.11.0 para 2.13.1 por causa do Riverpod 3.

**Fora de escopo:** migrar o resto do paciente para Riverpod, salvar o token no SQLite local, histórico ou agendamento de avisos.

**Achados do revisor final do RF14, corrigidos:** timeout do envio agora é "resultado desconhecido" (mensagem manda conferir antes de reenviar, auditoria `unknown`), porque o Gorush com `sync: true` pode entregar depois do limite de 5 s e o "tente de novo" duplicaria o aviso; "aceitos" passou a ser alvos menos falhas, sem confiar em `counts`; `MismatchSenderId` deixou de apagar tokens (é erro de configuração do servidor e esvaziaria a microárea) e a string de erro do FCM v1 entrou; `hide_messages: true` no `config.yml`. **Deferido:** `HttpClient` sem `close()`, resposta JSON de forma inesperada fora do erro tipado, desempate por timestamp igual, `INNER JOIN` com `patients`, Gorush em loop sem credenciais, auditoria `granted` com 0 aceitos, nome do teste de auditoria que promete mais do que verifica.

## Menores do push e aviso de 15 dias (2026-09-29)

Plano: `docs/superpowers/plans/2026-09-29-menores-do-push-e-aviso-de-mudanca-dos-termos.md`, branch `fix/patient`.

**O que foi fechado:**
- A revogação de `segmentedPush` grava o `denied` e apaga os tokens do titular numa transação só, sob o lock por titular (`recordConsentRevokingPush`); um teste com falha injetada depois de apagar os tokens prova que nada fica pela metade.
- A troca de dono de um token de push é auditada (`push_token`, sem o token); cada titular fica com no máximo 10 tokens (o mais antigo sai); a regra do aceite vigente existe num lugar só (`isCurrentAcceptance`).
- **Aviso de 15 dias (LGPD-RF18):** `TermsChangeSchedule` (recusa vigência a menos de 15 dias da publicação), `patients.termsChangeNotice` e um cartão dispensável na home do paciente. A agenda real (`upcomingTermsChange`) está **vazia**: nenhuma mudança de termos está anunciada, então o cartão nunca aparece em produção até alguém agendar uma. O canal do aviso é só dentro do app (push ainda não chega a aparelhos; SMS é só de OTP).
- `PushTokenScope.maybeOf` e o teste da fonte de token que nunca completa.
- Contagens de teste: backend 411, paciente 207, ACS 178. Analyze do backend em 51 infos.

**Ficou de fora, de propósito:**
- O contraste do texto do cartão não foi medido contra a superfície em que ele renderiza.
- O caso "agenda ativa" só é provado no serviço e no app com um backend falso; nenhum teste de integração exercita uma agenda ativa porque a constante do repositório é `null`.
- O cartão só aparece quando a home abre; quem já está com o app aberto não o vê até reabrir.

**Achados do revisor final, corrigidos:** o cartão de aviso descia o botão de pânico (e, chegando de forma assíncrona, o moveria sob o dedo), então **não aparece mais na aba de urgência** (teste em tela 360x640); a regra dos 15 dias usava `assert`, que não roda em release, e passou a `ArgumentError`; `spec/lgpd_design.md` ainda listava o aviso como pendente. **Deferido:** poda do teto por `id` sem `userId` (corrida rara com troca de dono), empate de `updatedAt` na poda, injeção de "sem agenda" no serviço, contraste do texto/botão/ícone de fechar do cartão, auditoria da troca de dono sem o dono anterior, `Semantics(header)` do cartão. **Limite conhecido:** a regra dos 15 dias compara datas declaradas; um `publishedAt` retroativo passa.

## Menores do RF14 e texto novo dos termos (2026-09-30)

Plano: `docs/superpowers/plans/2026-09-30-menores-do-rf14-e-texto-novo-dos-termos.md`, branch `fix/patient`.

**O que foi fechado:**
- **Registro de token:** a poda do teto apaga por id **e** titular e poupa o token recém-gravado (um relógio que voltou o faria parecer o mais antigo); o consentimento mais recente desempata por `id` (no registro, na consulta do login e na gravação do aceite); a troca de dono audita também o **dono anterior** (`push_token`, `result = lost`); `DataSubjectRightsService` aceita um leitor de agenda injetável (`termsChangeReader`).
- **Envio de avisos:** `GorushClient` encerrável e um só por processo; corpo 2xx ilegível é "resultado desconhecido" (nunca "tente de novo"); `logs` fora de forma é tolerado; falha ao apagar tokens inválidos depois do envio não vira erro; auditoria `not_delivered` quando nenhum aparelho aceitou; `LEFT JOIN` com `patients` (quem não tem linha clínica recebe "para todos" e só fica fora do filtro de crônicos).
- **Texto novo dos termos durante os 15 dias (LGPD-RF18):** `UpcomingLegalDocuments`/`upcomingLegalDocuments` (hoje `null`), `UpcomingDocumentsScope` e "Ler o texto novo" no cartão, oferecido só quando o app carrega exatamente a versão que o servidor anunciou. Um teste (`upcoming_legal_documents_test.dart`) lê a agenda do backend e falha se as duas pontas divergirem.
- Cartão de aviso: `Semantics(header)` no título e os três pares de contraste que o tema gera (texto, botão e ícone de fechar) medidos contra o `Card`.
- Contagens de teste: backend 423, paciente 219, ACS 178. Analyze do backend em 51 infos.

**Ficou de fora, de propósito:**
- Nenhuma mudança real foi agendada: `upcomingTermsChange` e `upcomingLegalDocuments` seguem `null`, então o cartão e o texto novo só são provados com agendas de teste.
- Um app antigo, sem o texto embarcado, vê só "Ler os termos atuais" durante os 15 dias. Não há marcação do que mudou (diff) nem aviso a quem já está com o app aberto.
- A amarração backend×app só é provada por mutação temporária: sem agenda real, o teste passa com os dois `null`.
- O teste "a poda só apaga tokens do próprio titular" é de caracterização: em execução sequencial ele não reproduz a corrida.
- ~~Lado nativo do token de push, credenciais FCM/APNs e Gorush real seguem pendentes.~~ — superado em 2026-09-30 para Android (ver "RF14: Gorush e FCM provados no emulador"); iOS/APNs, aparelho físico e Gorush hospedado seguem pendentes.
- O atendimento do pedido de exclusão (backoffice, ainda inexistente) precisa apagar `push_tokens` e gravar `denied` em `segmentedPush`: `requestDataDeletion` hoje não faz nenhum dos dois, e o `LEFT JOIN` com `patients` deixa de servir de rede de segurança quando a exclusão apagar a linha clínica e mantiver `users`.

**Achados do revisor final, corrigidos:** o detalhe do texto novo (`LegalDocumentScreen`) dizia "vigente desde" e o histórico chamava a versão futura de vigente, 15 dias antes da data — agora diz "passa a valer em <data>", com teste; o teste de amarração backend×app passava em silêncio quando não entendia a agenda (aspas duplas, constante, `;` no resumo, comentário enganoso) — agora o leitor tem três estados e **lança** em vez de tratar "não entendi" como "sem agenda". **Deferido:** a linha `lost` grava o dono anterior como `userId` de um `write` que ele não fez (documentado em `spec/lgpd_data_audit.md`); o registro recusado apaga o vínculo do dono anterior sem rastro; o desempate por id é estável mas arbitrário (e o painel "Meus dados" ordena só por timestamp); corrida da poda contra outra troca de dono pode gerar um 500 no registro; `catch (_)` sem log na poda de tokens do envio; `on StateError` no `GorushClient` cobre mais do que o `postUrl`; `failed` inflado por `failed-push` repetido do mesmo token; o `FilledButton.tonal` "Ler o texto novo" sem contraste medido; a poda sem desempate final por `id`.


## RF14: Gorush e FCM provados no emulador (2026-09-30)

Plano: `docs/superpowers/plans/2026-09-30-gorush-fcm-e2e-emulador.md`, branch `fix/patient`. **Provado no `emulator-5554` (Android 16, Google Play, projeto Firebase `sinal-acs`, Gorush 1.22.0 no Compose local), pelo `scripts/qa/push_e2e.sh --negativos`, que saiu com 0:**

- Um aviso enviado pelo ACS (`notices.sendSegmented`) atravessa backend → Gorush → FCM → Play Services e **aparece na bandeja do aparelho** com o título e o texto enviados (`recipients=1 accepted=1`, auditoria `granted`).
- O app obtém um **token FCM real** pelo canal `sinalacs/push_token` (`MainActivity.kt`, `firebase-messaging`, plugin do Google Services aplicado **só** quando `google-services.json` existe: sem o arquivo o APK compila e o app degrada para "sem push").
- **Casos negativos observados contra o FCM real:** token falso podado e token real mantido; linha `ios` mantida (não é erro de token) e sem derrubar o Android; Gorush parado falha em ~3 s com "Tente de novo" e nenhum token apagado; revogar apaga os tokens e o envio seguinte tem `recipients=0`; app desinstalado devolve `NotRegistered` e o token é podado.

**O que a execução real corrigiu (nenhum teste com servidor falso pegaria):**
- `ios.enabled: true` sem a chave APNs derrubava o boot do Gorush (código 1), e `access_log/error_log: "-"` calava todo log: o erro do boot ficava invisível.
- O Gorush devolve o token **mascarado** por padrão (`log.hide_token`), então a poda nunca casava; o `config.yml` usa `hide_token: false` e o cliente só poda tokens que ele enviou. A string de erro do FCM v1 (`The registration token is not a valid FCM registration token`) não estava na lista.
- O `GorushClient` tratava todo estouro de tempo como "resultado desconhecido": com o Gorush parado isso dizia "alguns pacientes podem já ter recebido" e nada tinha sido enviado. A conexão agora tem tempo próprio (2 s): estourar ali é "inacessível, tente de novo".
- O ambiente do shell trazia `GORUSH_CREDENTIALS_DIR` apontando para um **arquivo**; o Compose o prioriza sobre o `.env` e montou o arquivo como `/credentials` (o Gorush caía). `push_e2e.sh` ignora o valor do ambiente, com aviso.

**Limites (o que continua sem prova):**
- **iOS/APNs:** sem app iOS, sem chave APNs, `ios.enabled: false`. **`accepted` superconta tokens `ios` enquanto o iOS está desligado** (o Gorush os descarta sem log e eles entram como aceitos): sem app iOS não há token `ios`, então só aparece em teste.
- **Aparelho físico:** só emulador. A entrega com o celular bloqueado, em modo economia de bateria ou sem Play Services não foi exercida.
- O registro foi feito por `developmentLogin` dentro de um teste de integração, **não** pelo fluxo de tela (login OTP → `registerPushDevice`), que só tem testes de widget com backend falso. O app também não trata renovação de token (`onNewToken`) nem abre tela ao tocar na notificação.
- O teste de registro **segura o app instalado** por `PUSH_HOLD_SECONDS`: o `flutter test` desinstala o app ao terminar e o token morre. Sem a permissão `POST_NOTIFICATIONS` (Android 13+) o token registra mas o aviso não aparece; o teste concede a permissão por `adb`, e no app real quem a pede é o `main.dart`.
- Com FCM em primeiro plano a mensagem de notificação não vai para a bandeja: o teste manda o app para segundo plano.
- `hide_token: false` faz o `docker logs` do Gorush imprimir tokens de aparelho; o teste deixou um token **já morto** aparecer na saída. Em produção, restringir o acesso ao log do Gorush.
- Gorush hospedado fora do Compose local, rotação da chave da conta de serviço e a chave em modo `644` em `/opt/apps_android/` (cópia fora do repositório, legível por outros usuários da máquina).

**Achados do revisor final do e2e, corrigidos:**
- **Auto-init do FCM:** com o `google-services.json` no build, o `firebase-messaging` gerava o token e falava com o Google em **toda abertura do app**, antes do login e sem consentimento `segmentedPush`. O manifesto agora traz `firebase_messaging_auto_init_enabled=false` (teste `android_push_manifest_test.dart` lê o manifesto; o APK foi conferido com `aapt2`; o `getToken()` explícito **continua trazendo token** com o auto-init desligado, provado no emulador, e a entrega ponta a ponta repetida passou).
- **`e2e.sh --full` vermelho para quem não tem as credenciais:** `push_native_token_test` e `push_register_test` só rodam com `--dart-define=PUSH_E2E=1` (o `push_e2e.sh` passa); sem o define são pulados. Um bug meu apareceu ao provar isso no emulador: `bool.fromEnvironment` só aceita o texto `true`, então `=1` teria **pulado o próprio teste do e2e**; a comparação passou a ser `String.fromEnvironment('PUSH_E2E') == '1'`.
- Docs que contradiziam o código: `spec/lgpd_design.md` (parágrafo truncado que dizia "nada envia") foi reescrito; dois resquícios deste arquivo foram marcados como superados.

**Lacuna que continua aberta (LGPD):** o aparelho ainda pede o token ao FCM depois de **todo login**, mesmo sem consentimento; o servidor recusa e não o guarda, mas o Google já foi contatado. Fechar isso exige o app conhecer o consentimento antes de pedir o token (espelho local, como `localReminders`). **Deferido:** `hide_token: false` tem alternativa que não imprime token no log (casar a máscara por comprimento + sufixo só quando única) e o comentário "não liga a nenhuma pessoa sem o banco" subestima o risco (o token é identificador pseudônimo e o Google o liga ao aparelho); usar `HttpClient.connectionTimeout` em vez do `timeout` sobre `postUrl`; `accepted` superconta `ios` e um cliente adulterado pode registrar `ios`; `push_e2e.sh` apaga `push_tokens` do dev e termina com o consentimento `granted`, e o `kill` pode deixar o `flutter test` órfão; `appleboy/gorush:1.22.0` por tag e não por digest; o build da CI com `firebase-messaging` no classpath ainda não foi observado (a branch não tem execução de CI).


## Token de push só com consentimento (2026-09-30)

Plano: `docs/superpowers/plans/2026-09-30-finalizacao-app-paciente.md`, branch `fix/patient`.

- `registerPushDevice` pergunta ao servidor (`patients.hasGrantedConsent`, `bool`, sem auditoria de leitura, sem ler o painel) antes de falar com o FCM e fecha na dúvida (sem consentimento vigente, falha ou mais de 3 s; resposta tardia descartada). Onboarding (só com a caixa marcada) e o interruptor de "Meus dados" registram sem perguntar. Fecha a lacuna LGPD de "pede o token depois de todo login".
- **Revisão independente (subagente, 2026-09-30):** a primeira versão lia `myData` a cada login (dossiê decifrado + linha de auditoria falsa, inclusive onde nunca viria token); trocada pelo endpoint novo. Também: teste de que conceder não consulta de novo, teste do teto de 3 s (a resposta tardia é descartada), onboarding sem leitura à toa, comentário da constante no lugar certo. **Deferido:** empate exato de `timestamp` em `consent_logs` (o painel ordena só por tempo; o endpoint novo usa o desempate do servidor); revogação no intervalo entre resposta e token (ver `spec/lgpd_design.md`).
- Testes: paciente 233, backend 433.
- **Provado em 2026-09-30 no `emulator-5554` (AVD `Medium_Phone`):** `tool/live_check.dart` OK; `e2e.sh --keep --emulator` (smoke paciente e ACS) OK; `backend_connection_test` 7/7; `push_e2e.sh --negativos` saiu com 0 (entrega, token falso podado, Gorush parado, revogação). `ci_invariants.sh` OK e `flutter build apk --debug` sem `google-services.json` OK. A conferência do login OTP de paciente sem consentimento é coberta por teste de widget, não por execução no aparelho.
- **Segue aberto:** iOS/APNs, aparelho físico, Gorush hospedado, revisão jurídica dos termos 2026.1, backoffice que atende exclusão/correção, refresh token, menores deferidos do RF14, endpoint leve de consentimento (evita a auditoria de leitura por login).


## Teste completo do paciente contra o banco de teste (2026-09-30)

Plano: `docs/superpowers/plans/2026-09-30-teste-completo-paciente-banco-de-teste.md`, branch `fix/patient`.

- **Stack de e2e** (`docker-compose.e2e.yml` + `scripts/qa/e2e_stack.sh up|seed|down|psql`): o mesmo backend e o Gorush apontados para `sinalacs_e2e` dentro do `postgres-test` (efêmero), com `ENABLE_DEV_LOGIN=false`. Os seeds de desenvolvimento não sobem. O container do `serverpod` tem nome fixo: a stack de e2e e a de desenvolvimento não coexistem.
- **Dados fixos substituídos:** UUIDs `0000…000N` e CPFs do seed, `developmentLogin` (paciente e ACS), `seedMicroAreaId`. Em vez deles, fixtures geradas por execução (`bin/seed_e2e_fixtures.dart`, 7 testes do gerador; backend 440, paciente 238), login do paciente por OTP real (relé `scripts/qa/otp_relay.py`) e do ACS por matrícula e senha. Sem manifesto os helpers caem no login de desenvolvimento (a CI segue igual). **Não mudam:** os widget tests com `FakePatientBackend` (herméticos), `development.sql` e `developmentLogin` (a stack de desenvolvimento e o `android-e2e` dependem deles).
- **Provado em `emulator-5554`:** `full_journey_test` 3/3 (código errado não entra e o certo entra; termos; triagem vermelha; alerta; status; "Meus dados" só do próprio paciente; o ACS da microárea lista os dela e não o da outra), `backend_connection_test`, e `push_e2e.sh --e2e-db --negativos` (aviso na bandeja pelo Gorush e FCM reais, token falso podado, Gorush parado, revogação), com o banco de desenvolvimento idêntico antes e depois. O banco de e2e mostrou `denied_code`, `otp_requested`, um alerta do paciente crônico e **uma** leitura de `patient_data_overview` (só "Meus dados"; o login não lê mais o painel).
- **O que a execução real achou:** o teste de jornada errou por dois detalhes do teste (faltava `terms_gate_checkbox`; o texto é `Risco: Vermelho`); um manifesto esquecido fazia o `live_check` tentar OTP contra a stack de desenvolvimento (agora só com `E2E_FIXTURES_FILE`, e `down` apaga o manifesto); o OTP impõe 60 s entre pedidos do mesmo paciente, o que pediu um paciente por consumidor e uma espera no `push_e2e.sh`.
- **Limites:** só emulador; o GPS é um leitor fixo (o diálogo de permissão do sistema não é alcançável pelo `flutter test`); a CI não roda isto (precisa do relé e, para o push, das credenciais do FCM); migrar o `android-e2e` para a stack de e2e é outro plano.
- **Flaky achado e corrigido:** na 1ª execução completa, `push_e2e.sh` falhou com "título não está na bandeja" (um `sleep 10` fixo contra a entrega do FCM); passou a esperar até 45 s pelo texto na bandeja. Depois disso `patient_full_e2e.sh` saiu com 0 e `--sem-push` também; o banco de desenvolvimento ficou idêntico.
- **Revisão independente do e2e (subagente):** 0 Critical, 4 Important, corrigidos — (I1) a senha do ACS ia no `--dart-define` (argv e APK): o manifesto do aparelho não traz mais o bloco `acs` e o território virou `tool/territory_check.dart` no host; (I2) o `down` apaga o manifesto antes do `drop` e o cleanup avisa se falhar; (I3) `up`/`down` avisam que o `sinalacs-serverpod` da stack de desenvolvimento é substituído e como voltá-lo; (I4) o corte do código do OTP usa o relógio do host (`/now`). A reexecução achou ainda um relé órfão ocupando a porta 8765 e devolvendo código velho: os runners agora recusam subir nesse caso. **Adiado (Minor):** `.pyc` versionado em `scripts/qa/__pycache__`; relé sem checagem de `Host`; o seeder confia em host/porta do ambiente; manifesto criado com umask antes do `chmod 600`; `PGPASSWORD` no argv do `docker exec`; CPFs sintéticos com DV válido podem coincidir com CPFs reais; o teste não prova que o erro de código não gasta outro pedido; `na_bandeja` sob `pipefail`; `up` depende de certificados/mosquitto já inicializados e esconde a causa.
- **Minors do e2e fechados (2026-09-30):** `.pyc` fora do git; relé recusa `Host` alheio (403) e se encerra em 45 min; seeder exige host local e a porta 9090 (`e2eSeedRefusal`); manifesto criado 0600/0700 antes de receber o conteúdo; `PGPASSWORD` herdado do ambiente; `up` mostra a causa da falha e tem timeout; `na_bandeja` sem SIGPIPE; o relé conta os códigos (`/count`) e a jornada exige exatamente um pedido; risco do CPF sintético registrado em `spec/lgpd_design.md`. Testes: backend 440→445, paciente 239→240.


## Credenciais do FCM e Gorush no CI (2026-09-30)

Plano: `docs/superpowers/plans/2026-09-30-ci-credencial-fcm.md`, branch `fix/patient`.

- `scripts/ci/decode_secret_file.sh` decodifica `FCM_CREDENTIALS_BASE64` (arquivo `0600` em `$RUNNER_TEMP` + `GOOGLE_APPLICATION_CREDENTIALS`) e `GOOGLE_SERVICES_JSON_BASE64` (`apps/patient/android/app/google-services.json`, conferindo o pacote), sempre por `env:` do passo, sem imprimir conteúdo, sem sobrescrever nem apagar arquivo de dev fora do CI, e sem falhar em PR de fork (secret ausente = `::notice`). 53 asserções; 4 mutações mortas.
- `scripts/qa/ci_push_e2e.sh` instala a chave no diretório que o Gorush monta e roda o `push_e2e.sh` (caminho feliz) por último no `run_android_e2e.sh`, propagando o resultado. O emulador do CI passou para `target: google_apis` (a imagem padrão da action é AOSP, sem Play Services).
- `ci_invariants.sh` ganhou `check_credenciais_fcm` (9 grupos); 12 mutações do `ci.yml` são reprovadas; os três testes de shell rodam no `workflow-lint`.
- **Não provado:** o primeiro run no runner. A imagem `google_apis` não foi exercitada aqui (o emulador local é a Google Play); se o FCM não entregar token, trocar para `google_apis_playstore` (ver o plano, Task 5). O push adiciona ~6 min ao `android-e2e` (limite 60 min).
- **Política em aberto:** qualquer PR de dentro do repositório recebe os secrets; um autor com escrita poderia imprimi-los editando o `ci.yml`. Saída: Environment do GitHub com revisores obrigatórios.
- **Revisão independente (CI do FCM):** 1 Critical e 1 Important, corrigidos. (C1) o Gorush (uid 1000) não lia a chave `0600` do usuário `runner` (uid 1001): o serviço roda agora com `GORUSH_UID/GORUSH_GID` (provado no Docker real: uid do dono = `healthy`; outro uid = `permission denied`). (I1) as credenciais existiam em disco durante ações de terceiros: a decodificação foi para logo antes do E2E e o guarda exige que não haja `uses:` entre elas e o E2E (13 mutações). **Adiado (Minor):** `check_credenciais_fcm` não cobre `env:` de workflow, `with:` de ação nem `toJSON(secrets)`; a mutação de ordem só testa a ausência do passo; `set -e` com falha no `trap ... down` troca o código de saída (já era assim); `SHELLOPTS=xtrace` herdado imprimiria o secret (falta `set +x`); `${!nome}` executa código se o nome da variável for hostil (hoje são constantes); `--cleanup-temp` compara só o prefixo; o `tmp` pode sobrar se `chmod`/`mv` falharem; o cabeçalho de `push_e2e.sh` ainda diz "NÃO roda na CI"; `project_id` no log público; o push soma ~6 min ao limite de 60.
- **Provado no runner (2026-09-30, run `36790685752`, commit `32e6e88`):** 9/9 jobs verdes. No `android-e2e`: as duas decodificações passaram; o emulador `google_apis` deu token FCM; o Gorush subiu com o uid do runner; `push_e2e.sh` saiu com `chave ok para o projeto sinal-acs`, `tokens no banco: 1`, `recipients=1 accepted=1` e `OK — o aviso chegou ao emulador`. O log não contém chave, `private_key` nem `api_key` (0 ocorrências). Isto fecha o risco da imagem `google_apis` e o do uid do container.
- **A 1ª execução do mesmo run falhou** em "FCM_CREDENTIALS_BASE64 não é um base64 válido": o valor cadastrado estava errado (o guarda recusou e nada vazou). Refeito o secret, a re-execução (`gh run rerun --failed`) passou. O erro de base64 agora traz diagnóstico sem valores (tamanho, alfabeto, JSON em claro, base64url).
- **Minors da revisão do CI do FCM fechados (2026-09-30):** (M1/M2) o `check_credenciais_fcm` varre o texto bruto (cada secret só 1x, no `env:` do passo que o decodifica: cobre `env:` de workflow, `with:`, `toJSON(secrets)`, `secrets[...]`), exige o passo do E2E e a limpeza DEPOIS dele, e a mutação de ordem agora move o bloco de verdade (20 mutações); (M3) `trap ... down || true` preserva o exit do script; (M4–M7) `decode_secret_file.sh`: `set +x` primeiro, nomes de variável validados (`[A-Za-z_][A-Za-z0-9_]*`), `--cleanup-temp` normaliza o caminho (`..`) e um `trap` apaga o temporário se algo falhar (67 asserções); (M8) cabeçalho do `push_e2e.sh` corrigido; (M9) o `project_id` não é impresso no CI; (M10) `set -m` + `parar_arvore` matam o `flutter test` (neto do subshell), provado no emulador sem órfãos, e o tempo medido no run `36790685752` foi 13 min 19 s de 60 (passo do E2E 8 min 24 s). Sem Minors abertos deste trabalho.
