# Evidências da issue #56

## Linha de base

Coletada em 2026-10-12, branch `fix/issue-56-mqtt-queda-processo`, sem alterar `lib/` nem `test/`.

- **Biblioteca:** `mqtt_client` 10.11.11 (`backend/pubspec.lock`, dependência transitiva). O cache local tem também 10.5.1, mas o lock fixa 10.11.11; as referências abaixo usam `~/.pub-cache/hosted/pub.dev/mqtt_client-10.11.11/lib/src/connectionhandling/`.
- **Contêineres (`docker-compose.yml`):** `sinalacs-postgres` (l.6), `sinalacs-postgres-test` (l.37), `sinalacs-mosquitto` (l.55), `sinalacs-mosquitto-init` (l.70), `sinalacs-serverpod` (l.111, o backend; **não existe** `sinalacs-backend`), `sinalacs-traefik-init` (l.284), `sinalacs-traefik` (l.317). `gorush` (perfil `push`, `restart: unless-stopped`, l.90) não tem `container_name` (aparece como `sinalacs-gorush-1`).
- **Política de reinício do backend:** `docker inspect` de `sinalacs-serverpod` devolve `RestartPolicy=no` (o único `restart:` do compose é o do gorush). Logo, se o processo cair, o contêiner **não** volta sozinho.
- **Rede:** `sinalacs_default` (único bridge do projeto; `sinalacs-mosquitto` com aliases `sinalacs-mosquitto` e `mosquitto`).
- **`docker-compose.e2e.yml`:** só sobrescreve o `serverpod` (banco `sinalacs_e2e` em `postgres-test`, `ENABLE_DEV_LOGIN=false`, `REQUIRE_ACS_MFA=false`, `SMS_GATEWAY=log`, `RED_ALERT_ESCALATION_SECONDS=30`, `GORUSH_URL`); não altera broker nem rede.
- **Estado da stack no momento:** `sinalacs-serverpod` Up (healthy), `sinalacs-mosquitto` Up, `sinalacs-postgres` e `-test` healthy, `sinalacs-traefik` Up, `sinalacs-gorush-1` Up (healthy).
- **PID 1 do backend:** o `ENTRYPOINT` do Dockerfile (l.85) está em forma shell (`./server --mode=$runmode ...`), mas dentro do contêiner `/proc/1/cmdline` = `./server --mode=production --server-id=default --logging=normal --role=monolith`. Ou seja, o shell fez `exec` e o **PID 1 é o próprio `./server`** (sem `sh` intermediário): a morte do processo Dart encerra o contêiner, e sinais (`docker pause`/`stop`) chegam direto ao Dart.
- **CI (`.github/workflows/ci.yml`, job `serverpod-backend`, l.49):** `working-directory: backend`; o passo de testes é `dart test` (l.111) com `working-directory: backend/sinalacs_server`, suíte completa (unit + integration) contra Postgres de serviço efêmero.
- **Linha de base dos testes relevantes** (`cd backend/sinalacs_server && dart test test/integration/mqtt_alert_dispatcher_test.dart test/unit/alert_outbox_dispatcher_test.dart`, sem Postgres):
  - Resultado real: `00:00 +6: All tests passed!` (6 testes, 0 falhas). Saída inclui apenas logs esperados de stderr (`Entrega do alerta alerta-1 adiada (tentativa N, erro _Exception)` e `Falha ao conectar ao broker MQTT (SocketException). Tentando novamente em segundo plano...`).

## Mapa de propagação de erros

Código do backend: `backend/sinalacs_server/lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart` (abrev. D) e `.../application/alerts/alert_outbox_dispatcher.dart` (abrev. O). Biblioteca (abrev. L) = `mqtt_client-10.11.11/lib/src/connectionhandling/`.

| Caminho | Observado (arquivo:linha) | Tratado? |
|---|---|---|
| `connect()` → `_connectOnce` falha | `try/catch` e `unawaited(_reconnectWithBackoff())` (D:40-48) | sim |
| Reconexão em laço | `while (!_closed)`, `try/catch` por tentativa, backoff 2 s → 60 s dobrando (D:139-153; constantes D:23-24; dobra em D:150) | sim |
| Socket fecha/erra **com leitura ativa** | `socket.listen(onData, onError: onError, onDone: onDone)` (L:server/mqtt_client_mqtt_server_secure_connection.dart:208) → `MqttConnectionBase.onError`/`onDone` (L:mqtt_client_mqtt_connection_base.dart:65-73 / 77-85) → `_disconnect()` + `onDisconnected!()` → `_handleDisconnected` (D:134-137, ligado em D:58) | sim (via biblioteca) |
| Ping do keepalive | `sendMessage(pingMsg)` dentro de `try { } catch (e)` (L:mqtt_client_mqtt_connection_keep_alive.dart:117-130); `pingRequired` é callback de `Timer` (L:keep_alive:91, 140) | síncrono apenas |
| Resposta a PINGREQ do broker (`MqttPingResponseMessage`) | `_connectionHandler.sendMessage(pingMsg)` em L:keep_alive:190, **sem** `try/catch` (envio síncrono; o erro assíncrono do socket continua sem dono) | a verificar (H1) |
| **Escrita** `client?.add(bytes)` (`send`) | L:server/mqtt_client_mqtt_server_secure_connection.dart:168-171 (`client?.add(messageBytes.toList())`); `Socket.add` não lança em falha de I/O: o erro vai ao `done`/zona de criação do socket | **a verificar (H1)** |
| `publish()` → `publishMessage` | D:156-165: confere `client != null` e `state == connected`, chama `publishMessage` (síncrono, devolve sem esperar PUBACK) e retorna; `_publishOne` chama `markPublished` logo depois (O:58-62) | **a verificar (H5)** |
| `_teardownCurrentConnection` → `previousClient?.disconnect()` | D:125-132; sem `try/catch`; `disconnect()` sem `auto` chama `onDone()` (L:base:89-95) que roda `onDisconnected` do cliente velho | **a verificar (H4)** |
| `_handleDisconnected` | D:134-137: só testa `_closed`/`_reconnecting`, não identifica *qual* cliente chamou; callback do cliente velho (D:131 → L:base:77-85) é tratado como queda do atual quando `_reconnecting` é falso (ex.: caminho de `connect()` inicial ou `close()` com `_closed` falso) | **a verificar (H4)** |
| Ouvinte de mensagens `_handleMessages` | `try/catch` ao redor de `await handler(ack)` (D:111-121); log só com `runtimeType` | sim |
| `_publishOne` | `try/catch` ao redor de `publish` + `markPublished`; falha → `markFailed` e log (O:58-76) | sim (mas só vê falhas **síncronas** de `publish`) |
| `_startListening` na biblioteca | `try/catch on Exception` com `print` (L:server/mqtt_client_mqtt_server_connection.dart:116-125) | só exceções síncronas do `listen` |
| `connectionHandler` via `connect()` do cliente | `connect` da lib: `.catchError`/`on SocketException`/`HandshakeException`/`TlsException` na conexão (L:secure_connection.dart:67-95) | sim (só na fase de conexão) |
| `run()` em `lib/server.dart` | `void run(List<String> args) async` (l.17), sem `runZonedGuarded` nem `PlatformDispatcher`/handler global; `runtime.dispatcher.connect(...)` em l.149 (`_connectAlertDispatcher`) | sem rede de proteção |
| Reinício do contêiner | `RestartPolicy=no` no `sinalacs-serverpod` | sem recuperação automática |

### Hipóteses (a testar na Fase 2)

- **H1** erro assíncrono de escrita em socket cuja contraparte já fechou, entregue à zona de criação do socket (raiz), não capturado.
- **H2** o timer do keepalive (dormente durante a pausa) dispara em rajada no `unpause` e escreve no socket antes de o evento de leitura/`onDone` ser processado (ordem de eventos).
- **H3** só o `docker pause` do backend reproduz; reinício do broker e partição de rede são tratados pela biblioteca (`onDone`/`onError`).
- **H4** callback de cliente obsoleto e `disconnect()` sobre socket morto causam reconexão duplicada ou exceção no teardown.
- **H5** com socket morto mas estado "connected", `publish()` aceita a mensagem, o outbox a marca publicada e ela se perde (viola INV-03).

### O que falta saber

- Qual zona recebe o erro assíncrono (zona raiz do `Socket` ou a da criação em `connect`).
- Se a exceção vem do `Socket` plano ou do `SecureSocket` (a stack usa TLS 8883; `send` está na classe `MqttServerSecureConnection`).
- O stack trace completo e o exit code do processo na queda.
- Se a resposta a PINGREQ (L:keep_alive:190, sem `try/catch`) é alcançável com socket morto.

## Hipóteses (H1–H5) e status: aberta | confirmada | refutada

| Hipótese | Status |
|---|---|
| H1 | não reproduzida (10 execuções do cenário base + 3 variações, Task 5b; sem TLS) |
| H2 | não reproduzida (mesmas execuções; a ordem observada foi sempre leitura/`onDone` antes de escrita) |
| H3 | aberta |
| H4 | aberta |
| H5 | aberta |

## Tabela de experimentos
| ID | Cenário | Comando | Resultado | Exit code | Mensagem/pilha (sanitizada) | Processo vivo? | Tempo até reconectar | Efeito nos pendentes |
|---|---|---|---|---|---|---|---|---|
| 5b-1 | Sonda isolada (Linux, TCP plano, broker falso): SIGSTOP, `dropClients()`, 35 s, SIGCONT, 10 s | `dart test test/integration/mqtt_alert_dispatcher_resilience_test.dart -n 'processo congelado'` x10 | 10/10 passaram: sem queda, sem stderr, reconectou (`connectCount` 2) | n/a (vivo) | nenhuma | sim | <10 s após SIGCONT | n/a |
| 5b-2 | Variação A: `ignorePings=true`, sem drop | script temporário (não versionado), 1 execução | processo vivo, sem stderr; não reconectou em 10 s (`connectCount` 1) | n/a | nenhuma | sim | não reconectou na janela | n/a |
| 5b-3 | Variação B: 2000 bytes não lidos enviados ao cliente e depois `destroy()` (fechamento com dados pendentes) | idem, 1 execução | vivo, sem stderr, reconectou (2) | n/a | nenhuma | sim | <10 s | n/a |
| 5b-4 | Variação C: drop + `ignorePings` | idem, 1 execução | vivo, sem stderr, reconectou (2) | n/a | nenhuma | sim | <10 s | n/a |

Notas 5b: o SIGSTOP atinge o próprio `dartvm` da sonda (não há processo lançador intermediário). **Não coberto:** TLS (a stack usa 8883; exigiria certificados no broker falso) e RST real com dados pendentes no lado do broker (o `destroy()` do Dart fecha com FIN/RST conforme o kernel; não foi forçado `SO_LINGER 0`). Conclusão honesta: com socket plano, a biblioteca recebe o fim da conexão antes de escrever, por isso o erro assíncrono de escrita não apareceu; H1 não está refutada para TLS nem para `docker pause` real.

## Regressão final
