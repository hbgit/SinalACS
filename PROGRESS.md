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
  em memória.
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
   existir.
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
  ele receberia um SMS novo a cada 15 minutos. O ACS continua com 15 minutos e renovação pela
  credencial mantida em memória (RF07). A assimetria é deliberada e está escrita em
  `spec/lgpd_design.md`.
- **Refresh token rotativo continua ausente** (LGPD-RT06) — é o que permitiria voltar o TTL do
  paciente aos 15 minutos sem quebrar a experiência.
- **MFA/TOTP ausente** (achado F5 de `spec/security_assessment.md`).
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
