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
| `publish()` → `publishMessage` | D:156-165: confere `client != null` e `state == connected`, chama `publishMessage` (síncrono, devolve sem esperar PUBACK) e retorna; `_publishOne` chama `markPublished` logo depois (O:58-62) | **não (H5 confirmada, Tarefa 9)** |
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
| H1 | **confirmada no Docker/TLS** (8/8 quedas em A e C, `SocketException` não capturada, sem pilha no log; pilha e zona obtidas na Tarefa 6b: erro no `done` do sink do socket, sem ouvinte, na zona do `connect`) ; não reproduzida na sonda isolada sem TLS (10 execuções do cenário base + 3 variações, Task 5b) |
| H2 | **compatível, não isolada**: a queda ocorre ≤ 0,6 s após o `unpause` (5/5), mas não se observou a ordem de eventos; na sonda sem TLS a ordem foi sempre leitura/`onDone` antes de escrita |
| H3 | **refutada**: reinício do Mosquitto (B) não derruba (0/3, reconexão em ~2 s); a partição de rede (C) derruba (3/3) sem pausa artificial do backend |
| H4 | aberta |
| H5 | **confirmada** (Tarefa 9, broker falso TCP plano + banco de teste): o outbox marca `publishedAt` sem PUBACK e, numa queda nesse instante, a mensagem se perde sem retransmissão; correção **não aplicada** (muda o contrato de `AlertPublisher`, aguarda decisão do usuário) |

## Tabela de experimentos
| ID | Cenário | Comando | Resultado | Exit code | Mensagem/pilha (sanitizada) | Processo vivo? | Tempo até reconectar | Efeito nos pendentes |
|---|---|---|---|---|---|---|---|---|
| 5b-1 | Sonda isolada (Linux, TCP plano, broker falso): SIGSTOP, `dropClients()`, 35 s, SIGCONT, 10 s | `dart test test/integration/mqtt_alert_dispatcher_resilience_test.dart -n 'processo congelado'` x10 | 10/10 passaram: sem queda, sem stderr, reconectou (`connectCount` 2) | n/a (vivo) | nenhuma | sim | <10 s após SIGCONT | n/a |
| 5b-2 | Variação A: `ignorePings=true`, sem drop | script temporário (não versionado), 1 execução | processo vivo, sem stderr; não reconectou em 10 s (`connectCount` 1) | n/a | nenhuma | sim | não reconectou na janela | n/a |
| 5b-3 | Variação B: 2000 bytes não lidos enviados ao cliente e depois `destroy()` (fechamento com dados pendentes) | idem, 1 execução | vivo, sem stderr, reconectou (2) | n/a | nenhuma | sim | <10 s | n/a |
| 5b-4 | Variação C: drop + `ignorePings` | idem, 1 execução | vivo, sem stderr, reconectou (2) | n/a | nenhuma | sim | <10 s | n/a |

Notas 5b: o SIGSTOP atinge o próprio `dartvm` da sonda (não há processo lançador intermediário). **Não coberto:** TLS (a stack usa 8883; exigiria certificados no broker falso) e RST real com dados pendentes no lado do broker (o `destroy()` do Dart fecha com FIN/RST conforme o kernel; não foi forçado `SO_LINGER 0`). Conclusão honesta: com socket plano, a biblioteca recebe o fim da conexão antes de escrever, por isso o erro assíncrono de escrita não apareceu; H1 não está refutada para TLS nem para `docker pause` real.

### Tarefas 5 e 6: experimentos no Docker (stack de desenvolvimento, MQTT sobre TLS 8883 com certificado de cliente)

Stack usada: a **de desenvolvimento** em execução (`docker compose up -d`), não a de e2e; o `docker-compose.e2e.yml` não altera broker nem rede e o backend já usa `MQTT_USE_TLS=true` com `MQTT_CLIENT_CERT_PATH`/`MQTT_CLIENT_KEY_PATH`, portanto o canal é o mesmo do incidente (TLS 1.3, mTLS). PID 1 do backend = `./server` (sem `sh`): a exceção não tratada encerra o contêiner (exit 255, `RestartCount` continua 0 porque `RestartPolicy=no`; o script religou com `docker start`). Script: `scripts/qa/mqtt_resiliencia_e2e.sh todos` (A x5, B x3, C x3), executado em 2026-10-12 entre 21:02 e 21:29 UTC. Os horários abaixo vêm de `docker logs -t` do backend e do Mosquitto.

| ID | Cenário | Resultado | Exit code | Erro (sanitizado) | Vivo? | Fim vs. evento | Reconexão |
|---|---|---|---|---|---|---|---|
| A1 | `docker pause` 120 s + `unpause` | **caiu** | 255 | `Unhandled exception: SocketException: Broken pipe (OS Error: Broken pipe, errno = 32), address = <x>, port = <x>`; sem pilha | não | `FinishedAt` 21:04:25.28 = `unpause` 21:04:25 | só após `docker start` manual (processo novo conecta ao broker em ~15 s) |
| A2 | idem | **caiu** | 255 | idêntico (Broken pipe, errno 32) | não | fin 21:07:03.56 = unpause 21:07:03 | idem |
| A3 | idem | **caiu** | 255 | idêntico | não | fin 21:09:41.83 = unpause 21:09:41 | idem |
| A4 | idem | **caiu** | 255 | idêntico | não | fin 21:12:20.10 = unpause 21:12:20 | idem |
| A5 | idem | **caiu** | 255 | idêntico | não | fin 21:14:58.38 = unpause 21:14:58 | idem |
| B1 | `docker restart sinalacs-mosquitto` | sobreviveu | n/a | nenhum | sim (`rc=0` em +5/10/20/40 s) | n/a | 21:15:36.84 broker sobe, 21:15:38.64 backend reconecta (~2 s, primeiro backoff) |
| B2 | idem | sobreviveu | n/a | nenhum | sim | n/a | 21:16:55.26 -> 21:16:57.04 (~2 s) |
| B3 | idem | sobreviveu | n/a | nenhum | sim | n/a | 21:18:13.64 -> 21:18:15.45 (~2 s) |
| C1 | broker fora da rede 100 s e reconectado com alias `mosquitto` | **caiu** | 255 | `Unhandled exception: SocketException: Connection reset by peer (OS Error: Connection reset by peer, errno = 104), address = <x>, port = <x>`; sem pilha | não | `FinishedAt` 21:21:18.39 ~ religação da rede (aprox.; ver nota) | só após `docker start` |
| C2 | idem | **caiu** | 255 | idêntico (errno 104) | não | fin 21:24:45.75; religação calculada 21:24:45.5 | idem |
| C3 | idem | **caiu** | 255 | idêntico (errno 104) | não | fin 21:28:18.79; religação calculada 21:28:19 | idem |

Taxas: A 5/5 quedas, B 0/3, C 3/3. Durante a partição (C) o backend seguia vivo (`Running=true rc=0`) e o broker registrou `Client sinalacs-backend-* disconnected: exceeded timeout.` (também em A, 20 a 45 s após o início da pausa): o broker derruba o cliente silencioso, e o backend só descobre ao voltar a escrever/ler. Alias do broker conferido após cada `network connect` (`[mosquitto sinalacs-mosquitto]`); a stack voltou saudável.

Notas e limites:
- O log do contêiner não traz **nenhuma** linha de pilha (`#0`, `.dart:`): só `Unhandled exception:` e a mensagem do `SocketException`, o que é típico de erro assíncrono entregue sem `StackTrace`. A pilha completa continua desconhecida; para obtê-la seria preciso um `runZonedGuarded`/`PlatformDispatcher.onError` de diagnóstico no backend (fora do escopo desta tarefa, que não altera `lib/`).
- Duas assinaturas: `EPIPE` (errno 32, A: escrita num socket já fechado pelo broker) e `ECONNRESET` (errno 104, C: o par responde RST ao primeiro pacote após a religação). Ambas aparecem como a mesma exceção não tratada, o que reforça H1 (erro de I/O de socket sem dono).
- Diferença entre sonda e Docker: a sonda sem TLS (5b) não derrubou; o Docker com TLS 1.3/mTLS derrubou 8/8. A sonda também não fez o socket receber RST/EPIPE de verdade (o broker falso fechava antes). A diferença provável é TLS (o `SecureSocket` escreve/lê pela camada TLS) e o RST real do kernel; não foi isolado qual dos dois.
- O script na 1ª execução filtrava `docker logs --since` pelo fuso errado (os arquivos `A*.back.log` ficaram vazios e a coluna de reconexão do script saiu `n/a`); corrigido no commit seguinte (`--since` em epoch). Os horários desta tabela foram extraídos manualmente do `docker logs -t`.
- Efeito nos pendentes (alertas vermelhos durante a interrupção): não medido; é a Tarefa 10b.
- Impacto: como o backend não reinicia (`RestartPolicy=no`) e a queda acontece com apenas 45 s de silêncio do broker/rede, uma partição de rede real derruba o backend de produção sem recuperação.

### Tarefa 6b: pilha e zona do `SocketException` (sonda TLS/mTLS com `runZonedGuarded`)

Sonda: `backend/sinalacs_server/test/support/mqtt_dispatcher_probe_tls.dart` (dispatcher real, TLS 1.3 + mTLS contra o Mosquitto real, `main` dentro de `runZonedGuarded` com `zoneValues {#marker}` e `ZoneSpecification.errorCallback`, que registra a pilha síncrona de onde o erro é anexado a um Future/Stream; saída em arquivo fora do repositório). Compilada com `dart compile exe` e executada **num contêiner `dart:3.12.2` na rede `sinalacs_default`**, falando com `mosquitto:8883`.

**Desvio do método pedido (rodar no host):** a sonda no host contra a porta publicada (docker-proxy) **não reproduziu**: SIGSTOP de 60 s (broker registrou `exceeded timeout`) e `docker pause` do broker por 100 s, 1 execução cada, o processo seguiu vivo e sem erro (provavelmente porque o proxy do host mantém/fecha a conexão de outra forma que a ponte direta). Por isso a reprodução válida é a de dentro da rede Docker, equivalente ao backend real. Hostname `mosquitto` está no SAN do certificado do broker.

| Cenário (n) | Zona do `connect` | Resultado |
|---|---|---|
| `docker pause` do contêiner da sonda 55 s + unpause (3) | guardada | erro capturado pelo guarda 3/3, `errno=32`, processo vivo |
| idem (3) | **raiz** (`Zone.root.run`) | `Unhandled exception: SocketException: Broken pipe` e **exit 255** 3/3 |
| broker fora da rede 100 s + `connect --alias mosquitto` (3) | guardada | capturado 3/3, `errno=104` (Connection reset by peer), vivo |
| idem (1) | raiz | `Unhandled exception`, exit 255 |
| `docker pause` do broker 100 s (3) | guardada | capturado 3/3, `errno=104` (2x "Connection reset by peer", 1x "Read failed (... errno = 104)"), vivo |

**Pilha.** O erro final entregue ao handler **não tem pilha** (`StackTrace.empty`, 9/9 casos guardados): é erro de Future sem `StackTrace`. A pilha da origem foi obtida pelo `errorCallback` (pilha síncrona no ponto em que o erro é anexado). Frames sanitizados, de baixo para cima (a sequência é a mesma nos 9 casos):

```
_RawReceivePort._handleMessage            (dart:isolate-patch)   // evento nativo do socket
_NativeSocket.multiplex                   (dart:io-patch/socket_patch)
_NativeSocket.reportError
new _RawSocket.<closure>  -> _StreamController.addError           // erro no stream do RawSocket
_RawSecureSocket._reportError             (dart:io/secure_socket) // camada TLS
_Socket._onError          (dart:io-patch)  -> _SocketStreamConsumer.done  (Completer.completeError)
_StreamSinkImpl._completeDoneError        (dart:io/io_sink)       // completa o Future `done` do IOSink do socket
```

O último passo, em microtask (`_microtaskLoop`, `Future._propagateToListeners`, `_StreamSinkImpl._controller.<closure>`), completa o Future `Socket.done` com erro **sem ouvinte**: é este que vira exceção não tratada. Nenhum frame do `mqtt_client` nem do `MqttAlertDispatcher` aparece (nada de `_SecureFilterImpl` ou de ping explícito na pilha: a falha vem do evento nativo do socket).

**Marcador de zona.** Em todo passo da cadeia `Zone.current[#marker]` era `ZONA_PROBE` (a zona onde o `connect` rodou). O `handler` do `runZonedGuarded` roda na zona **pai**, por isso lá o marcador vale `null` (esperado; não indica zona raiz). A prova de zona é comportamental: com o `connect` dentro da zona guardada o erro é capturado (9/9); com o `connect` em `Zone.root.run` e só `main` guardado, o erro **escapa** do guarda e derruba o processo (4/4, exit 255, mesma mensagem do log do backend). Ou seja, o erro é entregue à zona em que o socket foi criado (zona do `client.connect`), não à zona do chamador original nem sempre à raiz.

**Escrita ou leitura?** Escrita no caso errno 32 (EPIPE só ocorre ao escrever: o keepalive PINGREQ de 30 s do cliente, ou publicação, num socket que o broker já fechou), reportada pelo evento nativo e propagada ao `done` do sink de saída. Nos casos errno 104, 2 de 3 execuções de `docker pause` do broker/partição mostraram "Connection reset by peer" no mesmo caminho do `done` do sink (escrita), e 1 mostrou "Read failed (errno 104)" (leitura); em todos o fim da cadeia é o mesmo Future `done` do sink sem ouvinte. Conclusão: a falha **na escrita** (ou o erro propagado ao `done`) é o que não tem dono; a distinção exata escrita/leitura por execução não é observável só com a pilha.

**Status de H1: confirmada** (erro de I/O de socket entregue ao Future `Socket.done` do sink, sem ouvinte, na zona de criação do socket; reproduzido 9/9 na sonda com TLS no Docker e 4/4 em zona raiz com queda do processo). Limites: não testado dentro do `Serverpod` real (a zona do `connect` no servidor depende de onde `MqttAlertDispatcher.connect` é chamado em `server.dart`); a reconexão pós-erro na zona guardada não foi medida.

**Implicação para a Tarefa 7.** O dado sustenta uma `Zone` (`runZonedGuarded`) **ao redor de `client.connect(...)`** (e de tudo que cria o `MqttServerClient`/socket): o socket e seu `Future done` nascem na zona corrente no momento do `connect`, e é nela que o erro é entregue. Reconexões partem de `Timer`/`Future.delayed` agendados dentro da zona (herdam a zona), mas **`_connectOnce` precisa ser chamado dentro da zona protegida em toda tentativa**, inclusive a iniciada por `_handleDisconnected` (callback registrado pelo `mqtt_client`, que roda na zona onde foi atribuído). Não basta guardar a criação do `MqttServerClient` sem o `connect`: o socket é criado no `connect`. Não basta envolver só o `main` do servidor se o `connect` for chamado em outra zona (por exemplo callbacks do Serverpod na raiz): como visto, `Zone.root.run` escapa do guarda. Recomenda-se o `runZonedGuarded` dentro de `_connectOnce` (zona própria por conexão), com o handler apenas registrando o tipo/errno e disparando a reconexão.

Para restaurar: após os testes o broker foi religado com `--alias mosquitto` (perdeu o alias do nome do contêiner, resolvido por DNS do mesmo jeito), `docker compose up -d` e o `sinalacs-serverpod` (que caiu com a pausa/partição do broker, exatamente o defeito investigado) foi religado; tudo saudável ao final.

### Tarefa 7: correção no dispatcher (zona protegida em volta de `client.connect`)

- Cada `_connectOnce` roda `client.connect(...)` numa zona própria do cliente, derivada de `Zone.root` (não da zona de uma requisição) com `handleUncaughtError` que conhece o cliente de origem: um erro tardio do socket de um cliente substituído não derruba o atual; o resultado volta ao chamador por um `Completer` externo (um `await _zone.run(...)` direto ficava pendurado numa falha de `connect`, porque um `Future` com erro não cruza fronteiras de zona de erro).
- Política: `SocketException`, `TlsException` (inclui `HandshakeException`), `TimeoutException`, `ConnectionException`, `NoConnectionException` e `StateError('socket is null')` viram queda de conexão (descarta o cliente, `publish` passa a lançar `MqttUnavailableException`, reconexão com backoff). Qualquer outro erro: registro só do tipo e `onFatal` (padrão `exit(70)`).
- Cliente obsoleto: `onDisconnected` carrega o cliente que o registrou e é ignorado se ele não for mais o atual (H4 corrigida no código).
- Prova com socket real (antes da correção falhava, depois 20/20): `FakeMqttBroker.resetClients()` fecha com RST (`SO_LINGER 0`); o `SocketException` errno 104 completa o `Socket.done` do cliente e, antes da correção, escapava para a zona do teste; com a correção é tratado e o dispatcher reconecta e publica.
- Achado colateral: o próprio broker falso não escutava o `done` dos sockets aceitos; um EPIPE do lado do broker caía na zona do teste. Corrigido no fixture.
- Revisão (rodada 1): erro depois de `close()` não chama `onFatal`; uma queda na janela da troca de cliente, com o laço de reconexão ainda ativo, zera `_client` e o laço tenta de novo (antes saía com um cliente morto).
- Ainda pendente: reexecução dos cenários A e C no Docker com TLS (o gate real).

## Tarefa 7v: re-execução com a correção

Imagem reconstruída com `docker compose up -d --build serverpod` (HEAD `85d802d`; imagem criada às 21:09:32 -04, depois do commit de 21:05; container recriado, saudável, e o Mosquitto registrou o `sinalacs-backend-*` da nova instância). `StartedAt` do backend: `2026-10-13T01:09:36Z`, **idêntico antes e depois de todas as execuções**; `RestartCount=0`, `ExitCode=0`, `State.Status=running` em todas as 11 execuções (o script não precisou de `docker start`). Nenhum `crash.log` foi gerado. Nenhuma execução derrubou o processo.

| Cenário | Antes (sem a correção) | Depois (7v) | Reconexão ao broker (novo `sinalacs-backend-*`) | stderr do backend (sanitizado) |
|---|---|---|---|---|
| A: `docker pause` do backend 120 s | queda 5/5 (exit 255) | **0/5 quedas**, vivo 5/5 | 5/5, ~2 s após o `unpause` (122,1 s contados desde o `pause`) | 4/5: `Erro de E/S no cliente MQTT (SocketException, errno=32); reconectando.`; 1/5 (A2): nenhuma linha de erro |
| C: broker fora da rede 100 s | queda 3/3 | **0/3 quedas**, vivo 3/3 | 3/3: 103,8 s, 108,9 s, 105,0 s desde a desconexão | 3/3: `... (SocketException, errno=104); reconectando.` |
| B: `docker restart` do Mosquitto | sem queda 0/3 | **0/3 quedas**, vivo 3/3 | 3/3, 2,0 s após o início do restart | nenhuma linha de erro |

VAZ-01: nos logs do backend de todas as execuções só aparecem tipo e errno; busca por IP, `:8883`, `mosquitto`, `localhost` e `payload` nos `*.back.log` sem nenhuma ocorrência. Comando: `scripts/qa/mqtt_resiliencia_e2e.sh A 5`, `C 3`, `B 3` (o script passou a imprimir também `started=` em cada RESULT).

Conclusão: a correção da Tarefa 7 resolve A e C na stack Docker real com TLS; B segue sem queda. Limite: não há criação de alerta durante a interrupção (Tarefa 10).

## Tarefa 9: recuperação do outbox e experimento H5

Testes em `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart`, grupo `com o MqttAlertDispatcher real e o broker falso`: `MqttAlertDispatcher` real (backoff 100 ms, `onFatal` gravado) injetado por `AlertRuntime.overridePublisher`, `FakeMqttBroker` em `127.0.0.1` (TCP plano) e o Postgres de teste do harness (`sinalacs-postgres-test`). O broker falso ganhou `dropOnPublish` (conta o PUBLISH, não responde PUBACK e destrói a conexão). Limite: sem TLS; a queda real do socket TLS (RST/EPIPE) foi provada no Docker na Tarefa 7v, e o caminho aqui testado (outbox → `publish` → reconexão) não passa pela camada TLS.

**Regressão (Step 1-2), PASS (8/8 execuções do grupo):** broker fechado → `createRedAlert` aceito com `published == false`, 1 `Alert` e 1 `AlertOutboxEntry` com `publishedAt == null` → broker novo na **mesma porta** → dispatcher reconecta sozinho → `drainOnce` com relógio +5 min publica 1 (`publishCount == 1`, `publishedAt` preenchido) → segundo `drainOnce` publica 0 e `publishCount` segue 1 → `alerts.acknowledge` devolve `acknowledged == true`.

**Experimento H5 (Step 3).** Leitura do código: `publish()` (D:347-364) é `void` e chama `client.publishMessage`, que monta a mensagem, a guarda em `publishedMessages` do `PublishingManager` **do cliente atual** e chama `sendMessage` → `Socket.add` (assíncrono: falha de E/S vai ao `done`/zona, não ao chamador). `_publishOne` (O:58-62) chama `markPublished` logo em seguida. Não há espera de PUBACK. A biblioteca 10.11.11 não tem nenhum código de retransmissão de QoS 1 (busca por `resend`/`retransmi`/`republish` em `lib/src`: só um comentário sobre recepção duplicada), e o dispatcher cria um `MqttServerClient` **novo** a cada reconexão, descartando o mapa `publishedMessages` do anterior.

| Variante | `publish()` | `createRedAlert.published` | `publishedAt` no outbox | Broker recebeu | Após reconexão (cliente novo) | `drainOnce` seguinte |
|---|---|---|---|---|---|---|
| Socket destruído pelo broker no mesmo turno, imediatamente antes de `publish` (o dispatcher ainda vê `connected`; gancho `_PublisherComGancho` chama `broker.dropClients()`) | devolveu sem erro | `true` | preenchido | **0 PUBLISH** | reconectou (`connectCount` 2), `publishCount` continua 0 após 500 ms | 0 (nada pendente) |
| Broker recebe o PUBLISH, não responde PUBACK e derruba a conexão (`dropOnPublish`) | devolveu sem erro | `true` | preenchido antes de qualquer PUBACK | 1 PUBLISH, sem PUBACK | reconectou, sem retransmissão (`publishCount` continua 1) | 0 |

**Status de H5: confirmada.** Um alerta vermelho pode ficar marcado como publicado no outbox enquanto a mensagem MQTT nunca chegou ao broker (variante 1), e nenhum mecanismo a reentrega: o outbox já a deu por entregue e o cliente novo não herda a mensagem em voo. O alerta segue gravado e `pending` no banco (o escalonamento da #44 e a consulta do paciente continuam vendo-o), mas o canal de entrega ao ACS falhou em silêncio, o que viola INV-03. A variante 2 mostra a mesma ausência de confirmação; com um broker real, que pode ter roteado a mensagem antes de cair, ela é "entrega não confirmada", não necessariamente perda. Os dois testes afirmam o comportamento **atual** e estão rotulados `H5 (lacuna, comportamento atual)`: devem falhar e ser invertidos quando a correção entrar.

**Correção proposta (não aplicada, decisão do usuário pendente):**
- `AlertPublisher.publish` passa a `Future<void>` que completa no PUBACK do `messageIdentifier` devolvido por `publishMessage` (escutar `client.published`, ou o callback `onPublished`, filtrando pelo id) e falha com `MqttUnavailableException` em queda da conexão ou num tempo limite (ex.: 10 s). Arquivos: `lib/src/application/alerts/red_alert_service.dart` (interface), `lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart` (mapa id → `Completer`, completado no PUBACK e falhado em `_markConnectionLost`/`close`).
- `AlertOutboxDispatcher._publishOne` faz `await _publisher.publish(...)` e só então `markPublished`; falha ou tempo limite → `markFailed` com backoff (a entrega pode duplicar, o que o QoS 1 já admite e o ACK idempotente absorve). Arquivo: `lib/src/application/alerts/alert_outbox_dispatcher.dart`.
- Ajustes nos publishers falsos dos testes (`implements AlertPublisher` em `test/integration/red_alert_cycle_test.dart`, `test/unit/red_alert_service_test.dart`, `test/unit/alert_outbox_dispatcher_test.dart`, `test/unit/red_alert_lifecycle_test.dart` e `test/unit/red_alert_discard_paths_test.dart`; o único chamador de `publish` em `lib/` é `alert_outbox_dispatcher.dart:60`), e inversão dos dois testes H5.

## Regressão final

### Tarefa 10: `runZonedGuarded` global em `bin/main.dart` (defesa em profundidade)

Sonda mínima (`dart run`, script fora do repositório): `runZonedGuarded` com handler que só anota o tipo; dentro dele, `Future.error(SocketException)` em várias configurações. Resultados:

| Caso | Quem recebeu |
|---|---|
| E0: `Future.error(SocketException)` num `Timer` criado **fora** da zona (sonda sem zona) | ninguém: `Unhandled exception: SocketException` no stderr e o processo cai (a assinatura da #56) |
| E1: `Future.error` sem dono criado dentro da zona | global |
| E2: `Timer.periodic` criado dentro com callback `async` que lança (caso do `_startOutboxSweeper`) | global |
| E3: zona filha de `Zone.root` com `handleUncaughtError` próprio (como a do dispatcher) | só a filha; global **não** viu |
| E4: zona filha de `Zone.current` com handler próprio | só a filha; global não viu (sem log duplicado) |
| E5: zona filha de `Zone.current` **sem** handler | global (o erro sobe) |
| E7: `async` sem await que lança depois de `run` retornar (`run` é `void ... async`) | global |

Respostas às 6 perguntas:
1. A zona global intercepta erros de Futures/Timers criados dentro dela (E1, E2, E7) e de zonas filhas sem handler (E5). Não intercepta: o que nasce em zona criada de `Zone.root` (E3), isolates, sockets/timers criados antes dela (E0). O `Serverpod.start()` já roda o próprio `runZonedGuarded` (serverpod 3.4.13, `serverpod.dart:685`), com `ExitException` -> `exit(code)` e demais erros logados com `_exitCode = 1`: esses nunca sobem à global. O `Timer.periodic` do outbox é criado após `await pod.start()`, ou seja, na continuação de `run`, na zona global (E2); o `catch` dele já cobre o caso comum.
2. Dispatcher x global: não há log duplicado; o erro tratado na zona do dispatcher não sobe (E3, E4). O global só vê o que o dispatcher não alcança.
3. A zona do dispatcher é bifurcada de `Zone.root` (Tarefa 7), não de `Zone.current`; logo **não** é filha da global. Consequência: o global não cobre o cliente MQTT (e não precisa; a local é que decide). O que a global cobre é o resto do processo (outbox, `unawaited(_connectAlertDispatcher)`, FutureCalls fora do guarda do Serverpod).
4. Política aplicada (`lib/src/runtime/uncaught_error_policy.dart`): `isTransientIoError` (a mesma lista do dispatcher, agora compartilhada) -> registra tipo (+errno) e mantém vivo; qualquer outro -> registra só o tipo e `exit(70)`. Verificado com a sonda: `SocketException` errno 104 -> processo vivo, rc=0; `StateError` -> `[processo] Erro assíncrono não tratado (StateError); encerrando.` e rc=70, sem texto da mensagem nem pilha.
5. Log: prefixo `[processo]` (o dispatcher usa `MQTT`), só tipo e errno (VAZ-01), coberto por teste de unidade.
6. Risco ao Serverpod: `exit()` não depende de zona; sinais (`ProcessSignal.watch`) e o shutdown do Serverpod não passam por erro de zona; `args` seguem iguais. `dart compile exe bin/main.dart` compila. Não subi o servidor completo (a stack Docker de dev não foi tocada); a verificação do boot completo fica para a E2E da Tarefa 10b/11. Decisão: **aplicada**.

### Tarefa 10b: cenários do broker com alerta vermelho real (`mqtt_resiliencia_e2e.sh`)

Logs completos: `docs/superpowers/plans/2026-10-12-issue-56-e2e.log` (no disco; `*.log` é ignorado pelo git, por isso não versionado). Stack de e2e (banco `sinalacs_e2e`), imagem com a correção da Tarefa 7 e a zona global da Tarefa 10 (45e4a98). O alerta é criado pelo login OTP real do paciente `main` da fixture (`apps/patient/tool/live_check.dart`). Depois de restaurar: (a) `RestartCount`/`StartedAt`; (b) `alert_outbox."publishedAt"` (só contagem); (c) entrega pelo broker a um assinante QoS 1 de sessão persistente (`mosquitto_sub` dentro do contêiner do broker, usuário/certificado do backend). O card no app do ACS **não** foi verificado: o ACL só libera ao `acs-area-12` a microárea do seed de dev, e a das fixtures é sorteada.

**Boot real com a zona global (pendência da Tarefa 10):** `docker compose up -d --build serverpod` com 45e4a98 -> `running healthy`, `rc=0`, `GET https://localhost/` -> 200, migrações e webserver normais, backend conectado ao broker.

| Execução | Cenário | Processo (a) | Outbox (b) | Broker entregou (c) | `published` na resposta |
|---|---|---|---|---|---|
| 1 | base | vivo, rc=0 | 1 (1 tentativa) | sim | true |
| 1 | B (stop, alerta, start) | vivo, rc=0, mesmo StartedAt | 1 (3 tentativas) | sim | false |
| 1 | C_INICIO (+49 s de partição) | vivo, rc=0 | 1 (1 tentativa) | **não** | **true** |
| 1 | C_FIM (+114 s de partição) | vivo, rc=0 | 1 (1 tentativa) | **não** | **true** |
| 2 | base | vivo, rc=0 | 1 | sim | true |
| 2 | B | vivo, rc=0 | 1 (3 tentativas) | sim | false |
| 2 | C_INICIO / C_FIM | vivo, rc=0 | 1 / 1 | **não / não** | **true / true** |
| 2 | A (pausa 120 s, alerta logo após o unpause; diagnóstico) | vivo, rc=0 | 1 (2 tentativas) | sim | false |

(O `ATRASO_C` de 5 s virou ~49 s porque o login do C_INICIO esperou o intervalo de 60 s do OTP desde o login do B.)

**H5 reproduzida no Docker/TLS, em cenário realista (partição de rede), 4/4 alertas perdidos.** No broker, o cliente `sinalacs-backend-*` caiu por `exceeded timeout` ~45 s depois da partição (1,5 x keepalive de 30 s). O backend **não** percebeu a queda durante toda a partição (100 s + espera do login): só detectou ao religar a rede, com `SocketException errno=104` (o broker respondeu RST aos segmentos retransmitidos), e reconectou ~5 s depois. Nesse intervalo `publish()` aceitou as duas mensagens, `createRedAlert` respondeu `published=true`, o outbox carimbou `publishedAt` e nada foi reentregue após a reconexão: o assinante esperou 120 s sem receber. O alerta continua `pending` no banco (visível ao escalonamento da #44), mas a entrega MQTT ao ACS se perdeu em silêncio (INV-03).

Achado novo, que agrava H5: a janela "socket morto, estado connected" não é de milissegundos. O `mqtt_client` envia PINGREQ a cada 30 s, mas não derruba a conexão quando o PINGRESP não chega (o dispatcher não configura timeout de resposta do ping; a opção do pacote, `disconnectOnNoResponsePeriod`, existe na 10.11.11 com padrão 0 = desligada, e não é usada), então numa partição sem FIN/RST o backend fica "conectado" até a rede voltar ou o TCP desistir. A correção proposta na Tarefa 9 (aguardar PUBACK com prazo antes de `markPublished`) fecha a perda; um timeout de PINGRESP reduziria a janela. Nenhuma das duas foi aplicada (decisão do usuário).

B e A passaram: com FIN/RST imediato (B) ou erro de escrita no unpause (A, `errno=32`), o dispatcher marca a queda antes do `publish`, o outbox registra a falha (`MqttUnavailableException`) e reentrega após a reconexão. Em nenhuma execução o processo caiu ou reiniciou (`rc=0`, `StartedAt` constante em cada execução).

`admin_alertas_escalonar_e2e.sh --com-regressao-offline` (emulator-5554, sem pausa do backend, agora exigindo também `RestartCount 0`): verde. Painel atualizado pelo pulso em 29,9 s, botão 8,3 s após o prazo, Traefik pausado 120 s com o backend vivo e sem reinício, asserts do banco e cadeia de auditoria ok (21 linhas), e a jornada offline do ACS (`acs_full_e2e.sh`, 5 testes) verde.
