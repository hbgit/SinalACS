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
  banco. **O relógio é o resíduo que sobra, e não o que decidia o par:** era o conteúdo (status +
  payload) que distinguia os dois casos, deterministicamente, e é o que a subseção abaixo fecha.
  Este parágrafo dizia antes que "a propriedade anti-enumeração vale no conteúdo e **não** no
  relógio" — o inverso, e a frase errada é parte do mesmo defeito. Com gateway de verdade o termo
  dominante é a ida ao provedor; a correção é tirar o envio do caminho de resposta (ou impor um
  piso constante de tempo), e é endurecimento para quando o provedor for escolhido — não deste
  estágio, em que `SMS_GATEWAY=log` não faz chamada nenhuma.
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
distinguia os dois casos, deterministicamente — esse era o oráculo, e era o que faltava fechar. O
**relógio** é o que não se mede com confiança: 200 amostras keep-alive por caso, com distribuições
que se sobrepõem. Depois desta correção é o conteúdo que está igual; o relógio segue desigual e
segue sendo resíduo, não sinal.

**O que a correção não resolve** — ninguém deve ler "oráculo fechado" como "enumeração inviável":

- **Não entrou limite nenhum.** O caminho de sonda continua sem rate limit por origem, que é a
  lacuna já registrada nesta lista. Quem varre continua varrendo à vontade; o que acabou foi o
  sinal determinístico de volta. Cada acerto ainda manda um SMS para a pessoa.
- **A UX perdeu o aviso de "aguarde um minuto".** Com o intervalo mínimo silencioso, quem pede o
  código duas vezes em menos de um minuto não vê aviso nenhum e fica esperando um SMS que não vem.
  O servidor não pode mais dizer isso — quem sabe quando pediu por último é o **app**, e é lá que a
  mensagem passa a morar. Hoje o app não implementa a espera: a tela não diz nada. **Dono: quem
  mexer no app do paciente** — este RF01 não fecha com a mensagem de volta ao servidor, porque ela
  só seria alcançável por quem já acertou o par.
- **`otp_challenges` não tem retenção** (Minor do mesmo review). Não há `DELETE` nem limpeza em
  `lib/` nem em `bin/`: desafios expirados e consumidos ficam para sempre, cada um com `userId`,
  dois timestamps e `codeHash` — "Crítico — credencial" no inventário de
  [`spec/lgpd_data_audit.md`](spec/lgpd_data_audit.md) —, então a tabela é um rastro de tentativas
  de login sem prazo. **Registrado, não implementado**: depende de decidir prazo e de quem executa
  a limpeza, como as outras retenções do projeto.

### Um defeito do RF02 que esta entrega mediu — com dono (2026-09-19)

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
