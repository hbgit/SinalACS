# ISSUE #56 — Backend cai quando o socket MQTT morre — Plano de investigação e correção

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar tarefa a tarefa. Os passos usam checkbox (`- [ ]`).
> **Regra do repositório:** commits e PRs sem atribuição de IA, sem `Co-Authored-By`, sem "Generated with" (CLAUDE.md do projeto). Mensagens de commit em português, no padrão `tipo(escopo): resumo (#56)`.

**Goal:** Uma queda da conexão MQTT (pausa do processo, reinício do Mosquitto, partição de rede) nunca derruba o processo do backend; o dispatcher reconecta com backoff e o outbox entrega os alertas vermelhos pendentes depois, sem expor dados protegidos (VAZ-01) nos logs.

**Architecture:** Primeiro isolar a causa por experimentos com sockets reais (Fases 1–2), só então escolher a correção (Fase 3). A hipótese de trabalho, **ainda não provada**, é que `MqttServerClient` escreve com `client?.add(...)` (`mqtt_client-10.11.11/.../server/mqtt_client_mqtt_server_normal_connection.dart:132-136` e `..._secure_connection.dart:168-172`) num `Socket` do `dart:io`. Um erro de escrita num `Socket` não é lançado por `add`: aparece de forma assíncrona (em `socket.done`/stream), na **zona em que o socket foi criado**. Nenhum `try/catch` do dispatcher o alcança. A correção candidata é um `Zone` filho, criado uma vez pelo dispatcher, com `handleUncaughtError`, dentro do qual `connect()` roda; o erro transitório vira "conexão perdida" e aciona o `_reconnectWithBackoff` existente. `runZonedGuarded` em `run()` é só defesa adicional (Fase 4).

**Tech Stack:** Dart 3 / Serverpod, `mqtt_client ^10.0.0` (resolvido: 10.11.11 em `backend/pubspec.lock`; confirmar na Tarefa 1), `package:test`, `dart:io` (`ServerSocket`, `Process`, `ProcessSignal.sigstop`), Docker Compose, Mosquitto 2 (TLS 8883), `scripts/qa/*.sh`.

**Spec / fontes:** issue #56; `PROGRESS.md` (linhas ~1561 e ~1575: o incidente e o item aberto); `spec/lgpd_data_audit.md` (regra VAZ-01, linha ~291); `scripts/qa/admin_alertas_escalonar_e2e.sh` (cabeçalho, linhas 40-52, explica por que o script passou a pausar o Traefik).

## Global Constraints

- Alerta vermelho nunca é descartado em silêncio (INV-03); a entrega é eventual via outbox.
- Logs do tratamento de erro: **só** tipo do erro (`runtimeType`), componente, etapa e, no máximo, `OSError.errorCode`. Nunca `$error`, `$stackTrace`, `address`, id de paciente/ACS, `locationHash`, payload (VAZ-01). Padrão atual: `stderr.writeln('... (${error.runtimeType}).')`.
- Não reintroduzir a pausa do backend em `admin_alertas_escalonar_e2e.sh` (ele pausa `sinalacs-traefik`). O cenário de falha do broker vive em script próprio.
- Preservar a API pública: `MqttAlertDispatcher({required AppConfig config})`, `connect({onAcknowledgement})`, `publish(AlertDelivery)`, `close()`, `isConnected`, `MqttUnavailableException`, interface `AlertPublisher`. Parâmetros novos só opcionais.
- Fora de escopo: autenticação do ACK por MQTT (`acsId`/`microAreaId` vêm do payload; já registrado no `PROGRESS.md`). Só citar como risco independente.
- Nenhum critério é "atendido" por código alterado ou por um teste isolado verde: cada um precisa da evidência listada na Tarefa 13.
- Nunca declarar teste executado/aprovado sem rodar. Resultados reais vão para o arquivo de evidências (Tarefa 3).

## Review Focus

Entradas/condições que o escopo implica e que ninguém testaria por padrão (cada linha tem teste com dono):

1. Callback `onDisconnected` de um cliente **antigo** disparando depois que um novo já assumiu → não pode derrubar a conexão saudável nem abrir segunda reconexão (Tarefa 7, teste "cliente obsoleto").
2. Cliente "conectado" segundo a biblioteca, mas com socket morto → `publish()` deve lançar `MqttUnavailableException` (e não sumir no vazio) após o erro transitório (Tarefa 7).
3. Publicação QoS 1 aceita localmente (`publishMessage`) e conexão que morre antes do PUBACK → o outbox já chamou `markPublished` (Tarefa 9, hipótese H5).
4. Erro **não** transitório (ex.: `StateError`, `RangeError`) → não pode ser engolido em silêncio (Tarefa 7, teste "erro desconhecido é fatal e observável").
5. Segredos de sentinela (`locationHash`, id de alerta, host) nunca no stderr de nenhum caminho de erro (Tarefa 8).
6. `restart: unless-stopped` mascarando regressão no e2e (container reinicia e o script não percebe) → checar `RestartCount` (Tarefa 11).

---

## Mapa de arquivos

| Arquivo | Papel |
|---|---|
| `backend/sinalacs_server/lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart` (178 linhas) | Cliente MQTT, `_connectOnce`, `_handleDisconnected`, `_reconnectWithBackoff`, `publish`. **Alvo da correção.** |
| `backend/sinalacs_server/lib/server.dart` (`run`, linha 17; `_connectAlertDispatcher`, 146; `_startOutboxSweeper`, 93) | Ponto de entrada; `bin/main.dart` só chama `run(args)`. Sem `runZonedGuarded` hoje. |
| `backend/sinalacs_server/lib/src/application/alerts/alert_outbox_dispatcher.dart` | `AlertOutboxDispatcher`: `drainOnce`, `publishNow`, `_publishOne` (publica síncrono e chama `markPublished`; falha → `markFailed` com backoff). |
| `backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart` | `AlertPublisher`, `AlertOutbox`, `PendingDelivery`. |
| `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` | Cria o `MqttAlertDispatcher` e o `dispatcherFor(session)`. |
| `backend/sinalacs_server/test/integration/mqtt_alert_dispatcher_test.dart` | Teste atual (2 casos; sem broker real). |
| `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart` (caso "com o broker fora…", linha 341) | Ciclo do outbox com `publisher.offline` (publisher falso). |
| `backend/sinalacs_server/test/unit/alert_outbox_dispatcher_test.dart` | Unidade do outbox. |
| `docker-compose.yml` (`serverpod`: linha ~111, sem `restart`; `gorush`: linha 90 tem `restart: unless-stopped`; `mosquitto`: `sinalacs-mosquitto`), `docker-compose.e2e.yml` | Infra local / e2e. |
| `scripts/qa/admin_alertas_escalonar_e2e.sh` (+ `_test.sh`), `scripts/qa/lib_rele.sh`, `scripts/qa/ci_invariants.sh` | Convenções dos scripts de QA e guardas de CI. |
| **Criar** `backend/sinalacs_server/test/support/fake_mqtt_broker.dart` | Broker MQTT 3.1.1 mínimo sobre TCP real. |
| **Criar** `backend/sinalacs_server/test/support/mqtt_dispatcher_probe.dart` | Programa que sobe só o dispatcher (para SIGSTOP/SIGCONT). |
| **Criar** `backend/sinalacs_server/test/integration/mqtt_alert_dispatcher_resilience_test.dart` | Testes de socket real e de processo. |
| **Criar** `scripts/qa/mqtt_resiliencia_e2e.sh` (+ `_test.sh`) | Cenários A/B/C contra a stack Docker real. |
| **Criar** `docs/superpowers/plans/2026-10-12-issue-56-evidencias.md` | Tabela de evidências (padrão do `…issue-44-e2e.log`). |
| Docs a atualizar | `PROGRESS.md` (item "Backend cai…", ~1575, e §1561), `spec/lgpd_data_audit.md` (VAZ-01), `backend/CLAUDE.md` (seção MQTT/outbox), `backend/DEPLOY.md` (só se o restart valer fora do Compose local). |

---

# FASE 1 — Inspeção e mapa do fluxo de falha (somente leitura)

### Task 1: Linha de base e versões

**Objetivo:** confirmar versão da biblioteca, nomes reais dos contêineres, redes e como a CI roda os testes do backend.

**Arquivos:** `backend/pubspec.lock`, `docker-compose.yml`, `docker-compose.e2e.yml`, `.github/workflows/ci.yml` (job `serverpod-backend`), `backend/sinalacs_server/Dockerfile` (linha 85: `ENTRYPOINT ./server …`, forma shell → conferir quem é o PID 1).

- [ ] **Step 1:** Registrar versão e comandos:
```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
grep -A6 '^  mqtt_client:' backend/pubspec.lock | grep version
grep -n 'container_name\|restart:' docker-compose.yml
cat docker-compose.e2e.yml
grep -n 'dart test\|serverpod' .github/workflows/ci.yml | head -30
docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null
docker inspect -f '{{json .NetworkSettings.Networks}}' sinalacs-mosquitto 2>/dev/null
```
- [ ] **Step 2:** Rodar a linha de base dos testes relevantes e anotar resultado real (sem Postgres de teste, o que não precisar de banco):
```bash
cd backend/sinalacs_server
dart test test/integration/mqtt_alert_dispatcher_test.dart test/unit/alert_outbox_dispatcher_test.dart
```
**Esperado:** passam. **Conclusão:** versão, nome da rede do Compose, comando de CI e PID 1 do contêiner anotados em "Linha de base" do arquivo de evidências (Tarefa 3). **Risco:** se a stack não estiver de pé, `docker compose up -d` precisa de `.env` (`./scripts/dev/bootstrap_env.sh`).

### Task 2: Mapa de propagação de erros (leitura de código, sem editar)

**Objetivo:** responder, com `arquivo:linha`, cada item 1–10 da Fase 1 do pedido e separar *tratado* × *pode escapar*.

**Arquivos:** `mqtt_alert_dispatcher.dart`, `~/.pub-cache/hosted/pub.dev/mqtt_client-10.11.11/lib/src/connectionhandling/**`, `server.dart`, `alert_outbox_dispatcher.dart`.

- [ ] **Step 1:** Preencher a tabela abaixo no arquivo de evidências, verificando cada linha no código (já observado; confirmar e completar):

| Caminho | Observado | Tratado? |
|---|---|---|
| `connect()` → `_connectOnce` falha | `try/catch` + `_reconnectWithBackoff` (dispatcher:35-46) | sim |
| Reconexão em laço | `try/catch` por tentativa; backoff 2 s→60 s (dispatcher:129-142) | sim |
| Socket fecha/erra **com leitura ativa** | `socket.listen(onData, onError: onError, onDone: onDone)` → `MqttConnectionBase.onError/onDone` → `onDisconnected` → `_handleDisconnected` | sim (via biblioteca) |
| Ping do keepalive | `sendMessage` dentro de `try/catch (e)` (keep_alive:117-130) | síncrono apenas |
| **Escrita** `client?.add(bytes)` (`send`) | `Socket.add` não lança em falha de I/O; o erro vai ao `done` do socket / zona de criação | **a verificar (H1)** |
| `publish()` → `publishMessage` | síncrono; devolve sem esperar PUBACK; `_publishOne` já chama `markPublished` | **a verificar (H5)** |
| `_teardownCurrentConnection` → `previousClient?.disconnect()` | sem `try/catch`; dispara `onDisconnected` do cliente velho | **a verificar (H4)** |
| `_handleDisconnected` | não verifica *qual* cliente chamou | **a verificar (H4)** |
| `run()` em `server.dart` | `void run(...) async`, sem `runZonedGuarded` | sem rede de proteção |

- [ ] **Step 2:** Listar as hipóteses a testar (cada uma com experimento da Fase 2):
  - **H1** erro assíncrono de escrita em socket cuja contraparte já fechou, entregue à zona de criação do socket (raiz), não capturado.
  - **H2** o timer do keepalive (dormente durante a pausa) dispara em rajada no `unpause` e escreve no socket antes de o evento de leitura/`onDone` ser processado (ordem de eventos).
  - **H3** só o `docker pause` do backend reproduz; reinício do broker e partição de rede são tratados pela biblioteca (`onDone`/`onError`).
  - **H4** callback de cliente obsoleto e `disconnect()` sobre socket morto causam reconexão duplicada ou exceção no teardown.
  - **H5** com socket morto mas estado "connected", `publish()` aceita a mensagem, o outbox a marca publicada e ela se perde (viola INV-03).
- [ ] **Step 3:** Listar o que **falta saber**: qual zona recebe o erro; se a exceção vem do `Socket` plano ou do `SecureSocket` (a stack usa TLS 8883); o stack trace completo.

**Conclusão:** seção "Mapa" e lista H1–H5 no arquivo de evidências. **Dependência:** nenhuma.

### Task 3: Criar o arquivo de evidências

**Arquivos:** Criar `docs/superpowers/plans/2026-10-12-issue-56-evidencias.md`.

- [ ] **Step 1:** Criar com estas seções vazias e a tabela:
```markdown
# Evidências da issue #56
## Linha de base
## Mapa de propagação de erros
## Hipóteses (H1–H5) e status: aberta | confirmada | refutada
## Tabela de experimentos
| ID | Cenário | Comando | Resultado | Exit code | Mensagem/pilha (sanitizada) | Processo vivo? | Tempo até reconectar | Efeito nos pendentes |
|---|---|---|---|---|---|---|---|---|
## Regressão final
```
- [ ] **Step 2:** Commit:
```bash
git add docs/superpowers/plans/2026-10-12-issue-56-evidencias.md
git commit -m "docs(#56): esqueleto do registro de evidências da investigação"
```

---

# FASE 2 — Reprodução e isolamento (antes de qualquer correção)

Regra: nenhuma linha da tabela vira "causa confirmada" sem repetição (≥ 5 execuções por cenário A; ≥ 3 por B e C) e pilha completa. Ninguém altera `lib/` nesta fase.

### Task 4: Broker falso e sonda de processo (infra de teste, sem tocar `lib/`)

**Arquivos:** Criar `backend/sinalacs_server/test/support/fake_mqtt_broker.dart`, `backend/sinalacs_server/test/support/mqtt_dispatcher_probe.dart`.

**Produz:** `FakeMqttBroker.start({int port = 0})`, `.port`, `.connectCount`, `.publishCount`, `.ignorePings`, `.dropClients()`, `.close()`.

- [ ] **Step 1:** Escrever `fake_mqtt_broker.dart` (MQTT 3.1.1 mínimo: CONNECT→CONNACK, SUBSCRIBE→SUBACK, PINGREQ→PINGRESP, PUBLISH QoS1→PUBACK):
```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Broker MQTT 3.1.1 mínimo sobre TCP real, só para testar o dispatcher.
class FakeMqttBroker {
  FakeMqttBroker._(this._server);

  final ServerSocket _server;
  final _clients = <Socket>[];
  final _buffers = <Socket, BytesBuilder>{};

  int connectCount = 0;
  int publishCount = 0;
  bool ignorePings = false;

  int get port => _server.port;

  static Future<FakeMqttBroker> start({int port = 0}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    final broker = FakeMqttBroker._(server);
    server.listen(broker._accept);
    return broker;
  }

  void _accept(Socket socket) {
    _clients.add(socket);
    socket.listen(
      (data) => _onData(socket, data),
      onError: (_) {},
      onDone: () {
        _clients.remove(socket);
        _buffers.remove(socket);
      },
      cancelOnError: true,
    );
  }

  void _onData(Socket socket, List<int> data) {
    final builder = _buffers.putIfAbsent(socket, BytesBuilder.new)..add(data);
    final bytes = builder.takeBytes();
    var offset = 0;
    while (offset + 2 <= bytes.length) {
      var length = 0;
      var multiplier = 1;
      var i = offset + 1;
      int digit;
      do {
        if (i >= bytes.length) {
          _buffers[socket] = BytesBuilder()..add(bytes.sublist(offset));
          return;
        }
        digit = bytes[i++];
        length += (digit & 127) * multiplier;
        multiplier *= 128;
      } while (digit & 128 != 0);
      final end = i + length;
      if (end > bytes.length) {
        _buffers[socket] = BytesBuilder()..add(bytes.sublist(offset));
        return;
      }
      _handle(socket, bytes[offset], bytes.sublist(i, end));
      offset = end;
    }
  }

  void _handle(Socket socket, int header, Uint8List body) {
    switch (header >> 4) {
      case 1: // CONNECT
        connectCount++;
        socket.add([0x20, 0x02, 0x00, 0x00]);
      case 8: // SUBSCRIBE
        socket.add([0x90, 0x03, body[0], body[1], 0x01]);
      case 12: // PINGREQ
        if (!ignorePings) socket.add([0xD0, 0x00]);
      case 3: // PUBLISH
        publishCount++;
        if ((header >> 1) & 3 == 1) {
          final topicLength = (body[0] << 8) | body[1];
          socket.add([0x40, 0x02, body[2 + topicLength], body[3 + topicLength]]);
        }
    }
  }

  /// Fecha todas as conexões abertas, mas continua aceitando novas.
  void dropClients() {
    for (final socket in List.of(_clients)) {
      socket.destroy();
    }
  }

  Future<void> close() async {
    dropClients();
    await _server.close();
  }
}
```
- [ ] **Step 2:** Escrever `mqtt_dispatcher_probe.dart`: lê `MQTT_BROKER` do ambiente, cria `AppConfig` como `_config()` do teste atual (copiar o construtor, trocando `mqttBroker`), chama `connect()`, imprime `PRONTO` no stdout e fica vivo (`await Completer<void>().future`). Aceita `LOCATION_SENTINEL` só para imprimir nada: a sonda **não** loga nada além do que o dispatcher loga (o teste inspeciona o stderr real).
- [ ] **Step 3:** Smoke do broker falso: teste mínimo que conecta um `MqttAlertDispatcher` ao `FakeMqttBroker` e espera `isConnected == true` e `connectCount == 1`.
```bash
cd backend/sinalacs_server && dart test test/integration/mqtt_alert_dispatcher_resilience_test.dart
```
**Esperado:** PASS (o código atual já conecta). **Commit:** `test(#56): broker MQTT falso sobre TCP real e sonda de processo`.
**Risco:** o fake cobre só o subconjunto acima; se o dispatcher enviar outro pacote, ele é ignorado, não rejeitado.

### Task 5: Cenário A — `docker pause` do backend (reprodução do incidente)

**Arquivos:** Criar `scripts/qa/mqtt_resiliencia_e2e.sh` (esqueleto nesta tarefa; completo nas Tarefas 6 e 10). Seguir o estilo de `admin_alertas_escalonar_e2e.sh` (cabeçalho explicativo, `set -euo pipefail`, `trap` de limpeza que faz `unpause` de tudo, source de `lib_rele.sh` se aplicável).

- [ ] **Step 1:** Subir a stack igual ao e2e (mesmo override `docker-compose.e2e.yml` para o MQTT com mTLS, pois é o que o incidente usou) e anotar `StartedAt`/`RestartCount`:
```bash
docker compose -f docker-compose.yml -f docker-compose.e2e.yml up -d
docker inspect -f '{{.State.Running}} {{.State.StartedAt}} {{.RestartCount}}' sinalacs-serverpod
docker logs -f --since 0s sinalacs-serverpod > "$ART/A.log" 2>&1 &
```
- [ ] **Step 2:** Executar (repetir ≥ 5 vezes, `ART` por execução):
```bash
T0=$(date +%s.%N); docker pause sinalacs-serverpod; sleep 120
docker unpause sinalacs-serverpod; sleep 15
docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}} fin={{.State.FinishedAt}} rc={{.RestartCount}}' sinalacs-serverpod
docker logs --since "$T0" sinalacs-serverpod 2>&1 | tail -40
docker logs --since 120s sinalacs-mosquitto 2>&1 | grep -i 'disconnect\|keepalive\|socket error'
```
- [ ] **Step 3:** Registrar na tabela: processo vivo?, exit code, mensagem e pilha (sanitizada), se `FinishedAt` coincide com o `unpause`, taxa (n quedas / n execuções). Para capturar a pilha completa (o log do incidente só tem a primeira linha), nesta fase **somente**, rodar uma execução com o ambiente `MQTT_...` normal e `docker logs` sem `tail`; se a pilha não aparecer, rodar a sonda local (Task 5b).
- [ ] **Step 4:** Restaurar: `docker unpause sinalacs-serverpod || true; docker compose up -d`.

**Resultado esperado (hipótese):** processo sai com 255 no `unpause`. Se **não** cair nas 5 execuções, H1/H2 ficam "não reproduzida no Docker" e a decisão passa a depender da Task 5b.
**Critério de conclusão:** ≥ 5 linhas na tabela, todas com exit code, estado e logs. **Risco:** estado do contêiner de teste fica pausado se o script morrer — o `trap` precisa fazer `docker unpause`.

### Task 5b: Mesma hipótese, sem Docker (SIGSTOP/SIGCONT com broker falso)

**Objetivo:** reproduzir H1/H2 num processo isolado para obter pilha completa e um teste automatizado.

- [ ] **Step 1:** Escrever o teste (vai falhar/ficar vermelho se H1 for verdadeira — é o teste de regressão do defeito) em `mqtt_alert_dispatcher_resilience_test.dart`:
```dart
test('processo congelado e conexão derrubada: sobrevive e reconecta', () async {
  final broker = await FakeMqttBroker.start();
  final probe = await Process.start('dart', ['run', 'test/support/mqtt_dispatcher_probe.dart'],
      environment: {'MQTT_BROKER': 'localhost:${broker.port}'});
  final stderrText = StringBuffer();
  probe.stderr.transform(utf8.decoder).listen(stderrText.write);
  await probe.stdout.transform(utf8.decoder).firstWhere((s) => s.contains('PRONTO'));
  expect(broker.connectCount, 1);

  var saiu = false;
  unawaited(probe.exitCode.then((_) => saiu = true));

  probe.kill(ProcessSignal.sigstop);
  broker.dropClients();                        // broker "expira" a conexão ociosa
  await Future<void>.delayed(const Duration(seconds: 35)); // > keepAlivePeriod (30 s)
  probe.kill(ProcessSignal.sigcont);

  await Future<void>.delayed(const Duration(seconds: 10));
  expect(saiu, isFalse, reason: 'o processo caiu: $stderrText');
  expect(broker.connectCount, greaterThan(1), reason: 'não reconectou');
  probe.kill();
  await broker.close();
}, timeout: const Timeout(Duration(seconds: 90)), tags: 'resiliencia');
```
- [ ] **Step 2:** Rodar 10 vezes e contar quedas:
```bash
cd backend/sinalacs_server
for i in $(seq 10); do dart test test/integration/mqtt_alert_dispatcher_resilience_test.dart -n 'processo congelado' ; done 2>&1 | tee "$ART/5b.log"
```
(Declarar a tag `resiliencia` em `dart_test.yaml` do pacote — conferir se o arquivo existe; se não, criar com `tags: {resiliencia: {}}`.)
- [ ] **Step 3:** Se o processo cair, capturar `$stderrText` completo (a pilha) no arquivo de evidências, sanitizado. Se **não** cair (ordem de eventos favorável), tentar a variação: `broker.ignorePings = true` e quebra de conexão por *RST* (broker fecha com dados não lidos no buffer de entrada: enviar bytes ao cliente antes de `destroy()`), e documentar a taxa.
**Critério de conclusão:** hipótese H1 marcada *confirmada* (queda reproduzida com pilha mostrando `Socket`/`_SocketStreamConsumer`/`done`) ou *não reproduzida em N execuções*. **Esse teste fica vermelho até a Tarefa 7 e é o gate de regressão.**
**Risco:** `ProcessSignal.sigstop` só existe em Linux/macOS (aceito: CI é `ubuntu-24.04`); o teste deve ter `skip` em Windows.

### Task 6: Cenários B (reinício do Mosquitto) e C (partição de rede)

**Arquivos:** `scripts/qa/mqtt_resiliencia_e2e.sh`.

- [ ] **Step 1 — Cenário B:**
```bash
docker restart sinalacs-mosquitto
# coletar por 90 s: processo vivo? reconectou? (log do mosquitto: "New client connected ... sinalacs-backend-")
for t in 5 10 20 40 60 90; do sleep $((t)); docker inspect -f '{{.State.Running}} rc={{.RestartCount}}' sinalacs-serverpod; done
docker logs --since 2m sinalacs-mosquitto 2>&1 | grep 'sinalacs-backend'
docker logs --since 2m sinalacs-serverpod 2>&1 | grep -i 'MQTT\|Unhandled'
```
- [ ] **Step 2 — Cenário C (mecanismo: desconectar o broker da rede do Compose; não exige `NET_ADMIN`; simula NAT que descarta a conexão sem FIN/RST):**
```bash
REDE=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' sinalacs-mosquitto)   # nome real, confirmado na Task 1
docker network disconnect "$REDE" sinalacs-mosquitto
sleep 100                                   # > 1,5 × keepalive (30 s) para a biblioteca declarar o timeout
docker inspect -f '{{.State.Running}} rc={{.RestartCount}}' sinalacs-serverpod
docker network connect --alias mosquitto "$REDE" sinalacs-mosquitto   # o alias de serviço precisa voltar
sleep 90
```
  Conferir o alias com `docker inspect` antes/depois; se o alias não voltar, `docker compose up -d --force-recreate mosquitto`.
- [ ] **Step 3:** Para A, B e C medir: tempo de `docker unpause`/`restart`/`connect` até a linha de reconexão no log do Mosquitto (timestamps `docker logs -t`), `RestartCount`, exit code, e o efeito nos pendentes (criar 1 alerta vermelho com `scripts/qa/e2e.sh`/fixtures durante a interrupção — ver Tarefa 10 — e consultar `alert_outbox_entries`).
- [ ] **Step 4:** Restaurar `docker compose up -d` e conferir `docker compose ps`.
**Critério de conclusão:** tabela de evidências com A (≥5), B (≥3), C (≥3). Hipótese H3 (só a pausa derruba) *confirmada* ou *refutada*. **Risco:** B e C podem **também** derrubar o processo (caso em que a urgência sobe: queda real sem pausa artificial).

### Task 7-pre (GATE G1) — Decisão baseada em evidência

Antes da Fase 3, escrever no arquivo de evidências: causa confirmada (qual zona recebeu o erro, qual tipo, qual pilha), cenários que derrubam, os que não derrubam, e as hipóteses ainda abertas. **Se H1 não foi reproduzida em lugar nenhum**, parar e revisar este plano com o usuário em vez de implementar a correção abaixo. **Se H1 foi confirmada**, seguir.

---

# FASE 3 — Correção no dispatcher (só depois do gate G1)

### Task 7: Zona protegida + estado consistente + reconexão sem duplicidade

**Objetivo:** erros assíncronos de I/O do cliente MQTT viram "conexão perdida" tratada; o resto continua observável.

**Arquivos:** Modificar `backend/sinalacs_server/lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart`; testar em `mqtt_alert_dispatcher_resilience_test.dart`.

**Por que zona e não `try/catch`:** o erro de escrita é entregue assincronamente à zona em que o `Socket` nasceu (`client.connect(...)`). Por isso a zona precisa envolver a **chamada a `connect()`** (e a criação do cliente). Um `try/catch` ao redor de `publishMessage` ou `await connect()` não o vê. A Tarefa 5b deve ter provado isso; se a pilha mostrar outra origem, ajustar este passo antes de editar.

**Produz (assinaturas):**
- `MqttAlertDispatcher({required AppConfig config, Duration initialBackoff = const Duration(seconds: 2), Duration maxBackoff = const Duration(seconds: 60)})`
- privados: `late final Zone _zone`, `bool _isTransient(Object e)`, `Future<void> _markConnectionLost(MqttServerClient client)`, `void _onAsyncError(Object e, StackTrace s)`.
- `@visibleForTesting Future<void> simulateAsyncErrorForTest(Object error)`.

- [ ] **Step 1: testes (falham antes da mudança).** Em `mqtt_alert_dispatcher_resilience_test.dart`, com `FakeMqttBroker` e `initialBackoff: Duration(milliseconds: 100)`:
```dart
test('reconecta depois que o broker derruba a conexão e volta a publicar', () async {
  final broker = await FakeMqttBroker.start();
  final d = MqttAlertDispatcher(
      config: _config(broker.port), initialBackoff: const Duration(milliseconds: 100));
  await d.connect();
  expect(d.isConnected, isTrue);

  broker.dropClients();
  await _until(() => broker.connectCount >= 2 && d.isConnected);

  d.publish(_delivery());
  await _until(() => broker.publishCount == 1);
  await d.close(); await broker.close();
});

test('durante a queda publish lança MqttUnavailableException e não some no vazio', () async {
  final broker = await FakeMqttBroker.start();
  final d = MqttAlertDispatcher(
      config: _config(broker.port), initialBackoff: const Duration(seconds: 5));
  await d.connect();
  await broker.close();                       // nada mais aceita conexões
  await _until(() => !d.isConnected);
  expect(() => d.publish(_delivery()), throwsA(isA<MqttUnavailableException>()));
  await d.close();
});

test('erro transitório assíncrono não escapa para a zona raiz e aciona reconexão', () async {
  final broker = await FakeMqttBroker.start();
  final d = MqttAlertDispatcher(
      config: _config(broker.port), initialBackoff: const Duration(milliseconds: 100));
  await d.connect();
  final escapou = <Object>[];
  await runZonedGuarded(() async {
    await d.simulateAsyncErrorForTest(
        const SocketException('Broken pipe', osError: OSError('Broken pipe', 32)));
    await _until(() => broker.connectCount >= 2 && d.isConnected);
  }, (e, _) => escapou.add(e));
  expect(escapou, isEmpty);
  await d.close(); await broker.close();
});

test('cliente obsoleto: onDisconnected antigo não derruba a conexão nova', () async {
  // Reconecta uma vez e dispara o callback do cliente anterior; connectCount deve
  // permanecer 2 e isConnected true após 500 ms.
});

test('erro desconhecido não é engolido: é registrado e encerra de forma controlada', () async {
  // Injetar um onFatal via parâmetro opcional `void Function(Object) onFatal` (default: exit(70)
  // após log); o teste passa um callback que registra e confirma que foi chamado com StateError.
});
```
  `_until(bool Function() cond, {Duration timeout = const Duration(seconds: 5)})` é um helper local que faz polling a cada 25 ms e falha com `fail('timeout')`. `_config(int port)` copia o `_config()` do teste atual com `mqttBroker: 'localhost:$port'`.
  Rodar: `dart test test/integration/mqtt_alert_dispatcher_resilience_test.dart` → **Esperado: FAIL** (parâmetros/métodos inexistentes).

- [ ] **Step 2: implementar.** Alterações em `mqtt_alert_dispatcher.dart`:
```dart
MqttAlertDispatcher({
  required AppConfig config,
  Duration initialBackoff = const Duration(seconds: 2),
  Duration maxBackoff = const Duration(seconds: 60),
  void Function(Object error)? onFatal,
})  : _config = config,
      _initialBackoff = initialBackoff,
      _maxBackoff = maxBackoff,
      _backoff = initialBackoff,
      _onFatal = onFatal ?? _exitFatal {
  _zone = Zone.current.fork(
    specification: ZoneSpecification(
      handleUncaughtError: (self, parent, zone, error, stack) =>
          _onAsyncError(error, stack),
    ),
  );
}

static void _exitFatal(Object error) => exit(70); // EX_SOFTWARE: o Docker reinicia (Task 11)

bool _isTransient(Object e) =>
    e is SocketException ||
    e is TlsException ||
    e is HandshakeException ||
    e is TimeoutException ||
    e is MqttException ||           // inclui ConnectionException/NoConnectionException
    e is StateError && e.message == 'socket is null';
```
  (Conferir com a pilha real da Task 5b quais tipos aparecem; a lista acima é o ponto de partida, não uma suposição final.)
  - `_connectOnce`: criar o cliente e chamar `await _zone.run(() => client.connect(user, pass))` (a criação do `Socket` passa a ocorrer dentro da zona). Trocar o `..onDisconnected = _handleDisconnected` por `late final MqttServerClient client; client = MqttServerClient.withPort(...)..onDisconnected = () => _handleDisconnected(client);`.
  - `_handleDisconnected(MqttServerClient origem)`: `if (_closed || !identical(origem, _client)) return;` depois `unawaited(_markConnectionLost(origem))`. (Corrige H4: cliente obsoleto é ignorado.)
  - `_markConnectionLost(client)`: `if (_reconnecting) return;` `await _teardownCurrentConnection();` (zera `_client`, para que `publish()` lance `MqttUnavailableException` mesmo que a biblioteca ainda diga "connected") e `unawaited(_reconnectWithBackoff());`.
  - `_onAsyncError(error, stack)`: se `_isTransient(error)`: `stderr.writeln('Erro de E/S no cliente MQTT (${error.runtimeType}${_errno(error)}); reconectando.')` e `final c = _client; if (c != null) unawaited(_markConnectionLost(c))`. Senão: `stderr.writeln('Erro fatal no cliente MQTT (${error.runtimeType}).')` e `_onFatal(error)`. `_errno(e)` devolve `', errno=${e.osError!.errorCode}'` só para `SocketException` com `osError`, senão `''`. **Nunca** interpolar `error` ou `stack`.
  - `_teardownCurrentConnection`: envolver `previousClient?.disconnect()` em `try { … } catch (error) { stderr.writeln('Falha ao encerrar cliente MQTT antigo (${error.runtimeType}).'); }`.
  - `_reconnectWithBackoff`: usar `_initialBackoff/_maxBackoff` em vez das constantes estáticas; garantir que `_reconnecting = false` fique num `finally`.
  - `simulateAsyncErrorForTest(Object e)`: `@visibleForTesting Future<void> simulateAsyncErrorForTest(Object e) async { _zone.run(() { Future<void>.error(e); }); await Future<void>.delayed(Duration.zero); }`. **Atenção:** esse seam prova a política do handler, **não** o comportamento de um socket real; o teste de socket real continua sendo o da Tarefa 5b.
  - Garantir que `publish()` também rode `client.publishMessage` dentro de `_zone.run` (a escrita ocorre na zona do socket, mas o `Timer` do keepalive é criado na zona onde `connect()` rodou — confirmar na Tarefa 5b qual zona de fato recebe o erro; se for outra, ajustar aqui e documentar).
- [ ] **Step 3:** Rodar:
```bash
dart test test/integration/mqtt_alert_dispatcher_resilience_test.dart test/integration/mqtt_alert_dispatcher_test.dart
dart analyze lib test
```
  **Esperado:** todos PASS, inclusive o de SIGSTOP/SIGCONT da Tarefa 5b (agora verde), sem warnings.
- [ ] **Step 4:** Repetir o laço de 10 execuções da Tarefa 5b e registrar 10/10 sem queda. **Commit:** `fix(mqtt): erros assíncronos do socket viram queda de conexão tratada e reconexão com backoff (#56)`.
**Riscos:** (a) `Zone.fork` não alcança timers criados em outras zonas — verificar na pilha real; (b) `_exitFatal` com `exit(70)` precisa passar pelo `Serverpod` shutdown? Avaliar e, se o Serverpod tiver API de parada ordenada, usá-la; (c) `autoReconnect` permanece `false` de propósito (evita duas lógicas de reconexão).

### Task 8: Teste de privacidade dos logs (VAZ-01)

**Arquivos:** `mqtt_alert_dispatcher_resilience_test.dart`.

- [ ] **Step 1:** Teste que captura `stderr` do processo-sonda (Task 5b) **e** o `IOOverrides` do processo de teste, usando sentinelas: `alertId` `00000000-0000-4000-8000-0000000000aa`, `locationHash: 'sentinela-vaz01-local'`, host `localhost`, o clientId `sinalacs-backend-`. Forçar cada caminho de erro (queda, falha de reconexão, erro de teardown, erro fatal) e afirmar:
```dart
for (final proibido in ['sentinela-vaz01-local', '0000000000aa', 'localhost', 'Broken pipe', 'StackTrace', '#0 ']) {
  expect(capturado, isNot(contains(proibido)));
}
expect(capturado, contains('SocketException'));   // tipo, sim
```
- [ ] **Step 2:** Rodar → PASS. Se `localhost` vazar (por `SocketException.toString`), é bug: corrigir `_onAsyncError`. **Commit:** `test(mqtt): logs do erro tratado não carregam identidade, local nem payload (#56)`.
- [ ] **Step 3:** Atualizar a linha **VAZ-01** em `spec/lgpd_data_audit.md` (~291) listando os novos pontos de `stderr.writeln` com os novos números de linha.

### Task 9: Recuperação do outbox (`red_alert_cycle`) e hipótese H5

**Arquivos:** `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart` (novo `test` ao lado da linha 341); `backend/sinalacs_server/test/integration/mqtt_alert_dispatcher_resilience_test.dart`; leitura de `alert_outbox_dispatcher.dart:57-71`.

- [ ] **Step 1 (teste de regressão do fluxo completo, com dispatcher real + broker falso + banco de teste):** seguindo o `setUp` do arquivo (`sessionBuilder`, `_seed`), trocar `publisher` por um `MqttAlertDispatcher` real apontado ao `FakeMqttBroker`. Sequência assertiva:
  1. `connect()`; `isConnected` true.
  2. `broker.close()` (interrupção); aguardar `!isConnected`.
  3. `createRedAlert` → resposta `published == false`; `Alert.db.find` = 1; `AlertOutboxEntry` com `publishedAt == null`.
  4. Novo `FakeMqttBroker.start(port: <mesma>)`; aguardar `isConnected`.
  5. `drainOnce()` com relógio +5 min (como o caso da linha 341) → `broker.publishCount == 1`, `publishedAt != null`.
  6. Segundo `drainOnce()` → `publishCount` continua 1 (sem duplicidade).
  7. ACK via `endpoints.alerts.acknowledge` → `acknowledged == true`.
- [ ] **Step 2:** Rodar `dart test test/integration/red_alert_cycle_test.dart` (precisa do Postgres de teste: `docker compose up -d postgres-test` e o `passwords.yaml` do `bootstrap_env.sh`). **Esperado:** PASS.
- [ ] **Step 3 (H5, experimento antes de decidir):** teste com `FakeMqttBroker` que **não responde PUBACK** e derruba o cliente logo após receber o PUBLISH: ver se `publish()` já devolveu sem erro e se o outbox marcou `publishedAt` (o código lê assim: `_publishOne` chama `markPublished` logo após `publish` síncrono). Registrar o resultado.
  - Se H5 **confirmada** (alerta marcado publicado sem PUBACK e perdido): isso viola INV-03 e **muda a interface** (`AlertPublisher.publish` passaria a `Future<void>` que completa no PUBACK, via `client.published`/`MqttPublishMessage` id). **Parar e consultar o usuário** antes de mexer em `AlertPublisher` (muda `red_alert_service.dart`, o publisher falso dos testes e `alert_outbox_dispatcher.dart`). Se **refutada** (ex.: o QoS1 é retransmitido pela biblioteca na reconexão do mesmo cliente — mas o dispatcher cria cliente **novo** a cada reconexão), documentar o porquê.
- [ ] **Commit:** `test(outbox): alerta vermelho gravado na queda do broker é entregue após a reconexão (#56)`.

---

# FASE 4 — Proteção global (defesa adicional)

### Task 10: Avaliar e (se justificável) aplicar `runZonedGuarded` em `run()`

**Arquivos:** `backend/sinalacs_server/lib/server.dart:17` (`run`), `bin/main.dart`.

**Perguntas a responder no arquivo de evidências (com experimento, não por opinião):**
1. Quais erros uma zona global intercepta? Só os não capturados nas zonas descendentes que não tenham `handleUncaughtError` próprio. Erros de timers/`Future`s criados **dentro** de `runZonedGuarded(run…)` (inclui `Timer.periodic` do outbox em `_startOutboxSweeper`). Não intercepta: erros em isolates, erros de sockets criados em zona raiz antes dela, nem o que o `Serverpod` captura internamente. Experimento: sonda mínima que lança `Future.error(SocketException(...))` dentro e fora da zona.
2. Dispatcher × global: o dispatcher já tem zona filha com `handleUncaughtError`; um erro tratado ali **não sobe** à zona pai, logo não há log duplicado. O global só vê o que o dispatcher não alcança.
3. A zona global cobriria o cliente? Com a zona do dispatcher bifurcada de `Zone.current` no construtor (que roda dentro de `run`), sim: é filha da global.
4. Política: o global **não** engole. Para erro transitório de E/S sem dono (`SocketException`/`TlsException`) fora do dispatcher: registra tipo e **mantém vivo**; para qualquer outro: registra tipo e sai com código ≠ 0 (restart do Docker assume). Isso evita "viver em estado inconsistente".
5. Duplicação de log: o global usa componente `processo` no texto, o dispatcher usa `MQTT`.

- [ ] **Step 1:** Teste de unidade em `test/unit/` para uma função pura `bool isTransientIoError(Object e)` extraída para um arquivo pequeno (`lib/src/runtime/uncaught_error_policy.dart`) e reutilizada pelo dispatcher (`_isTransient`) — evita lista duplicada.
- [ ] **Step 2:** Alterar `bin/main.dart`: `void main(List<String> args) { runZonedGuarded(() => run(args), onUncaughtError); }` com `onUncaughtError` aplicando a política acima, sem interpolar `error`/pilha. Manter `run` como está (o `Serverpod` lê `args`).
- [ ] **Step 3:** `dart analyze` e `dart test test/unit`. **Commit:** `feat(runtime): rede de proteção global para erros assíncronos sem dono (#56)`.
**Se a avaliação mostrar que a zona global traz risco (ex.: interfere no shutdown do Serverpod), não aplicar e registrar o motivo.** **Dependência:** Task 7 concluída (a global nunca substitui a local).

---

# FASE 5 — E2E no emulador e na stack real

### Task 10b: `mqtt_resiliencia_e2e.sh` — cenários de broker, com alerta vermelho de verdade

**Arquivos:** `scripts/qa/mqtt_resiliencia_e2e.sh`, `scripts/qa/mqtt_resiliencia_e2e_test.sh`. Conferir antes em `scripts/qa/ci_invariants.sh` e `ci_invariants_test.sh` se há lista de scripts que exija registro; seguir o padrão `*_test.sh` dos vizinhos (`admin_alertas_escalonar_e2e_test.sh`).

- [ ] **Step 1:** Completar o script com os cenários B e C (e A como opção `--com-pausa-do-backend`, **desligada por padrão** e documentada como diagnóstico). Em cada cenário: (1) criar um alerta vermelho **durante** a interrupção usando o mesmo mecanismo de fixture/login do e2e existente (`scripts/qa/e2e.sh`/`patient_full_e2e.sh` — reaproveitar a função em vez de duplicar); (2) restaurar a conexão; (3) afirmar `RestartCount == 0` e `StartedAt` inalterado; (4) afirmar que a linha do outbox passa a `publishedAt IS NOT NULL` (consulta ao banco `sinalacs_e2e` por `docker exec sinalacs-postgres psql …`, só contagens, sem imprimir colunas protegidas); (5) afirmar que o ACS no emulador recebe o card (reutilizar a verificação do `admin_alertas_escalonar_e2e.sh` / `acs_full_e2e.sh`).
- [ ] **Step 2:** `bash scripts/qa/mqtt_resiliencia_e2e_test.sh` (teste do script: parsing de flags e que a opção de pausa do backend não vem ligada) e `shellcheck` se o repositório usa.
- [ ] **Step 3:** Rodar no emulador (instruções em `scripts/qa/run_android_e2e.sh`/skill `validacao-e2e`): `./scripts/qa/mqtt_resiliencia_e2e.sh --com-regressao-offline` conforme o padrão dos vizinhos. Registrar log em `docs/superpowers/plans/2026-10-12-issue-56-e2e.log`.
- [ ] **Step 4:** Rodar de novo `./scripts/qa/admin_alertas_escalonar_e2e.sh --com-regressao-offline` e provar que continua verde **sem** pausa do backend.
**Política de CI:** `android-e2e` já é informativo e não-requerido; este script fica **opcional** (suíte de resiliência manual/noturna), não entra nos 8 checks obrigatórios (mexer neles exige reaplicar a proteção de branch — ver `CONTRIBUTING.md`). O teste SIGSTOP (Tarefa 5b) e o `red_alert_cycle` (Tarefa 9) rodam no job `serverpod-backend` se a CI já executa `dart test` desses diretórios; confirmar na Task 1 e, se a tag `resiliencia` for pesada (35 s), rodá-la só em `dart test -t resiliencia` num passo separado do mesmo job (sem criar job novo, para não quebrar `JOBS_DOCUMENTADOS`).
**Critério de conclusão:** logs anexados; cada cenário B/C com alerta entregue pós-reconexão; `RestartCount 0`.

---

# FASE 6 — Resiliência operacional (defesa em profundidade)

### Task 11: `restart: unless-stopped` no serviço `serverpod`

**Arquivos:** `docker-compose.yml` (serviço `serverpod`, ~linha 111; o `restart` da linha 90 é do Gorush); verificar `docker-compose.e2e.yml` (override).

- [ ] **Step 1:** Antes de alterar, fixar o comportamento esperado e as limitações no arquivo de evidências:
  - Reinicia em saída ≠ 0 (inclusive 255 e o `exit(70)` da Task 7); **não** reinicia após `docker stop`/`docker compose stop`; `docker pause` não aciona.
  - Reinício não re-avalia `depends_on`: se o Postgres ainda não está de pé, o backend cai e o Docker o relança com backoff exponencial (comportamento aceitável, registrar).
  - O boot reaplica migrações (`SERVERPOD_APPLY_MIGRATIONS: "true"`) — idempotente; conferir.
  - Não recupera nada que dependa do processo vivo: ACKs MQTT chegados durante a janela de queda são perdidos (o broker não retém: sessão limpa) e o alerta pendente só sai depois de o backend subir e o sweeper rodar (`_outboxSweepInterval`, `server.dart`). Logo, **não substitui** as Tarefas 7 e 9.
  - Pode mascarar regressão: um crash seguido de restart parece "backend de pé" para o e2e.
- [ ] **Step 2:** Editar: adicionar `restart: unless-stopped` ao serviço `serverpod`.
- [ ] **Step 3:** Fazer o `mqtt_resiliencia_e2e.sh` (e o `admin_alertas_escalonar_e2e.sh`) falharem se `RestartCount > 0`, para a política não esconder regressão (já previsto na Task 10b; garantir também no segundo script, que hoje compara só `StartedAt`).
- [ ] **Step 4:** Validar com saída real do processo:
```bash
docker compose up -d
PID=$(docker exec sinalacs-serverpod sh -c 'pgrep -f "^./server" | head -1')
docker exec sinalacs-serverpod kill -9 "$PID"
sleep 20; docker inspect -f '{{.State.Status}} rc={{.RestartCount}} exit={{.State.ExitCode}}' sinalacs-serverpod
curl -fsSk https://localhost/health || true
```
  (Se o PID 1 do contêiner for o `sh` do `ENTRYPOINT` em forma shell, o `kill` do filho derruba o `sh` também; conferir na Task 1. Alternativa: `docker kill -s KILL sinalacs-serverpod` e **observar empiricamente** se a política dispara; não assumir.) **Esperado:** `rc=1`, estado `running`, `/health` volta.
- [ ] **Step 5:** `docker compose config -q` e `./scripts/qa/ci_invariants.sh` (o guarda de CI não deve reclamar). **Commit:** `chore(compose): reinício automático do backend após saída inesperada (#56)`.
- [ ] **Step 6:** Se `backend/DEPLOY.md` descreve o caminho free-tier, apenas anotar que a política de reinício do hospedeiro é responsabilidade dele; não alterar mais nada de infra.

---

# FASE 7 — Documentação e validação final

### Task 12: Documentação

- [ ] `PROGRESS.md`: fechar o item "Backend cai quando o socket MQTT morre…" (~1575) com causa confirmada (ou limitação), referência à #56 e ao arquivo de evidências; ajustar a §1561 (o texto que chama o defeito de "latente").
- [ ] `spec/lgpd_data_audit.md`: VAZ-01 atualizado (Tarefa 8).
- [ ] `backend/CLAUDE.md`: parágrafo curto na seção do MQTT/outbox: zona protegida do dispatcher, política transitório × fatal, `initialBackoff` injetável, comando do teste `-t resiliencia`.
- [ ] `docs/superpowers/plans/2026-10-12-issue-56-evidencias.md`: preencher tabela, hipóteses e riscos residuais.
- [ ] `./scripts/qa/check_documentation_links.sh` e `graphify update .`. **Commit:** `docs(#56): causa, decisões, evidências e riscos residuais`.

### Task 13: Regressão final e checklist dos critérios de aceite

- [ ] Rodar, e **colar a saída real** no arquivo de evidências:
```bash
cd backend/sinalacs_server
dart analyze lib test
dart test test/unit test/integration/mqtt_alert_dispatcher_test.dart
dart test -t resiliencia
dart test test/integration/red_alert_cycle_test.dart          # precisa de postgres-test
cd ../.. && ./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_test.sh
./scripts/qa/mqtt_resiliencia_e2e.sh
./scripts/qa/admin_alertas_escalonar_e2e.sh --com-regressao-offline
```
- [ ] Marcar cada critério **somente** com a evidência indicada:

| Critério | Evidência exigida |
|---|---|
| Causa isolada e documentada | Tabela com A/B/C, H1–H5 confirmadas/refutadas/abertas, pilha completa sanitizada |
| Processo resiliente | Teste SIGSTOP/SIGCONT 10/10 sem queda; B e C com `RestartCount 0`; reconexão com tempos medidos e backoff observado nos logs |
| Teste automatizado de falha MQTT | Testes da Tarefa 7 e 5b (o do seam é rotulado como política, não socket real) |
| Recuperação dos alertas | `red_alert_cycle` da Tarefa 9 + B/C da Tarefa 10b com alerta criado durante a queda |
| Privacidade dos logs | Teste da Tarefa 8 verde, VAZ-01 atualizada |
| Regressão evitada | `admin_alertas_escalonar_e2e.sh` verde sem pausa do backend; suíte existente verde |
| Evidências de execução | Comandos e saídas no arquivo de evidências |

- [ ] Abrir PR para `develop`/`main` (PR sem atribuição de IA), aguardando os 8 checks obrigatórios.

---

## Self-review (feito)

- **Cobertura:** Fases 1–7 do pedido → Tarefas 1–13; cenários A/B/C → 5, 5b, 6, 10b; privacidade → 8; outbox → 9; restart → 11; global → 10; docs → 12.
- **Placeholders:** os dois testes marcados com comentário "// …" na Tarefa 7 (`cliente obsoleto` e `erro desconhecido`) são os únicos esboços. O executor deve completá-los seguindo o padrão dos três anteriores *antes* de implementar; as asserções estão descritas no comentário.
- **Consistência de nomes:** `FakeMqttBroker`, `_markConnectionLost`, `_onAsyncError`, `_isTransient`, `simulateAsyncErrorForTest`, `initialBackoff`/`maxBackoff`, `onFatal`, tag `resiliencia`.
- **Pontos que dependem de resultado de experimento (não presumidos):** zona real que recebe o erro (Tarefa 5b → ajusta Tarefa 7), lista de tipos transitórios (pilha real), H5 e eventual mudança de `AlertPublisher` (consultar o usuário), PID do contêiner e comportamento de `docker kill` (Tarefa 11), nome da rede Docker (Tarefa 1).

## Resumo executivo

- **Sequência:** 1→3 (linha de base e evidências) → 4→6 (reproduzir A, A sem Docker, B, C) → gate G1 → 7→9 (correção, privacidade, outbox) → 10 (global, opcional) → 10b (e2e) → 11 (restart) → 12→13.
- **Arquivos principais:** `mqtt_alert_dispatcher.dart`, `alert_outbox_dispatcher.dart`, `server.dart`/`bin/main.dart`, `docker-compose.yml`, `scripts/qa/mqtt_resiliencia_e2e.sh`, `red_alert_cycle_test.dart`.
- **Testes obrigatórios:** resiliência com broker falso (reconexão, publish durante a queda, cliente obsoleto, erro fatal), SIGSTOP/SIGCONT de processo, privacidade de logs, `red_alert_cycle` com dispatcher real.
- **No emulador/stack real:** `mqtt_resiliencia_e2e.sh` (B e C com alerta criado durante a queda; A só como diagnóstico) e o e2e da #44 sem pausa do backend.
- **Riscos residuais:** H5 (QoS 1 sem esperar PUBACK pode perder alerta já marcado publicado — pode exigir mudar `AlertPublisher`); ACKs MQTT perdidos durante a janela de queda; erros fatais com `exit(70)` dependem do restart do Docker; ACK sem autenticação segue aberto (fora do escopo).
