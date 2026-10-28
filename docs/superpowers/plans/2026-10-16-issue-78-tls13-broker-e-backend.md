# Issue #78 — TLS 1.3 no broker MQTT e no trecho Traefik → backend (RNF04) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar o RNF04 na stack local: o broker passa a recusar TLS 1.2, e o Traefik passa a falar com o backend por TLS 1.3 com a cadeia verificada (decisão de 2026-10-16: TLS de mão única, sem mTLS), cada propriedade presa por uma asserção no `scripts/qa/tls_invariants.sh`.

**Architecture:** O broker ganha `tls_version tlsv1.3` no listener 8883. O backend ganha `ApiTlsConfig` (lido de `API_TLS_CERT_PATH`/`API_TLS_KEY_PATH`): quando as duas variáveis existem, o `Serverpod` sobe o apiServer com `SecurityContextConfig(apiServer: …)` e `minimumTlsProtocolVersion = tls1_3`; quando nenhuma existe, segue em HTTP, que é o caminho do Render (`backend/DEPLOY.md`), onde o TLS termina na borda. O `traefik-init` emite uma segunda folha, assinada pela CA do RPC, para o backend, e o Traefik a verifica por um `serversTransport` com `rootCAs` e `serverName`.

**Tech Stack:** Mosquitto 2 (`eclipse-mosquitto:2`), Traefik v2.11 (provider `file` + labels do Docker), Serverpod 3.4.13 / Dart 3.12 (`dart:io` `SecurityContext`), OpenSSL, bash.

**Spec:** issue #78 (`gh issue view 78`), item 4 (P1) de `docs/auditoria-prd/2026-10-15-lacunas-prd.md`, linhas RNF04, M2.3 e CRIPTO-TRAEFIK-BACKEND; requisito em `spec/PRD_system.md:156` (RNF04, "TLS 1.3 em todas as comunicações").

## Global Constraints

- Idioma: comentários, mensagens de erro, saída dos scripts e documentação em português, como o resto do repositório.
- **Decisão registrada (2026-10-16):** Traefik → backend é TLS 1.3 **de mão única**. Não há mTLS porque o Serverpod 3.4.13 chama `relic_io` → `HttpServer.bindSecure` sem `requestClientCertificate` (`~/.pub-cache/hosted/pub.dev/relic_io-1.2.0/lib/src/adapter/bind_http_server.dart:39`), então o processo não consegue exigir certificado de cliente. Sem sidecar e sem fork: o `spec/stack.md` não prevê serviço novo.
- A porta interna do backend continua **8080** (só o esquema muda para https); nenhuma porta nova é publicada no host.
- `API_TLS_CERT_PATH` e `API_TLS_KEY_PATH` vêm juntos ou não vêm: só uma das duas definida é erro de boot (`StateError`), como `MQTT_CLIENT_CERT_PATH`/`MQTT_CLIENT_KEY_PATH` em `app_config.dart:219`. String vazia ou só de espaços conta como ausente.
- O `Dockerfile` do backend **não** muda: o `HEALTHCHECK` dele (http) continua valendo para o Render; a stack local sobrepõe o healthcheck no `docker-compose.yml`.
- A CA do RPC (`infra/docker/traefik/runtime/certs/ca.crt`/`ca.key`) é **preservada** entre subidas; só as folhas são regeradas. Não regerar a CA (invalidaria os assets dos apps, ver o cabeçalho de `infra/docker/traefik/init.sh`).
- A chave da folha do backend fica em **644** (o backend roda como uid 1000 e a lê; mesma razão de `backend.key` em `PROGRESS.md:1524`); `ca.key` continua 600 e **não** é montada no backend.
- Cada asserção nova no `tls_invariants.sh` vem com o controle positivo que impede o verde por acidente (regra do cabeçalho do script).
- Sem dado real de paciente em teste, log ou captura.
- Commits sem atribuição de IA (regra do `CLAUDE.md` da raiz, que prevalece sobre o lembrete de atribuição).
- Branch: `feat/issue-78-tls13` a partir de `develop`.
- Emulador **disponível e obrigatório**: `emulator-5554` (`sdk_gphone64_x86_64`, API 36), conferido em 2026-10-16. O `adb` não está no PATH, então use `export PATH="$HOME/Android/Sdk/platform-tools:$PATH"` antes dos passos de emulador. As provas no emulador **não** são opcionais neste plano: se uma falhar, a tarefa não está pronta.

## Review Focus

1. **O backend não reconecta ao broker depois da troca de versão.** O cliente MQTT do backend (Dart/BoringSSL) e o do ACS precisam negociar 1.3; um cliente que só fala 1.2 cairia em silêncio, com o `health.check` ainda "ok". O esperado é `mqttConnected: true` depois do reinício do broker. Fica preso na Task 1 (asserção F3).
2. **O Traefik desliga a verificação da cadeia.** Um `insecureSkipVerify: true` global (`--serversTransport.insecureSkipVerify`) ou no transporte deixaria o caminho cifrado mas sem autenticar o backend, e todos os testes comportamentais continuariam verdes. O esperado é o script acusar. Fica preso na Task 3 (asserção E4, estática).
3. **Texto claro na 8080 interna voltando sem ninguém notar.** Por exemplo, alguém apaga `API_TLS_*` do compose: o backend volta a HTTP, o Traefik recebe erro e o RPC cai, mas a causa fica escondida. O esperado é o script dizer que a 8080 interna atende em claro. Fica preso na Task 3 (asserção E1).
4. **Só uma das variáveis `API_TLS_*` definida** (erro de digitação no compose ou no Render). O esperado é o servidor recusar subir com a mensagem nomeando as duas, em vez de cair para HTTP em silêncio. Fica preso na Task 2.
5. **O SAN da folha do backend não casa com o nome que o Traefik usa.** O Traefik disca pelo IP do container, e sem `serverName` a verificação falharia com 502 vago. O esperado é o RPC responder 200 por `https://localhost/` (Grupo A já existente) e o healthcheck interno passar por `https://localhost:8080`. Fica preso na Task 3: o Grupo A e a asserção E2 juntos.

---

### Task 1: Broker MQTT só aceita TLS 1.3

**Files:**
- Modify: `infra/docker/mosquitto/mosquitto.conf` (listener 8883)
- Modify: `scripts/qa/tls_invariants.sh` (novo Grupo F, antes do resumo final; atualizar o cabeçalho)

**Interfaces:**
- Consumes: stack de pé (`./scripts/qa/e2e.sh --keep`); `infra/docker/mosquitto/runtime/certs/{ca.crt,backend.crt,backend.key}`.
- Produces: Grupo F do `tls_invariants.sh`, que a Task 3 estende com o Grupo E e a Task 4 cita na documentação.

- [ ] **Step 1: Criar a branch**

```bash
git switch develop && git pull && git switch -c feat/issue-78-tls13
```

- [ ] **Step 2: Escrever o Grupo F no `tls_invariants.sh`** (`== Grupo F: o broker MQTT fala TLS 1.3, e só ele ==`), com três asserções, todas na `localhost:8883` e todas com `-cert backend.crt -key backend.key -CAfile ca.crt` do runtime do Mosquitto (o broker tem `require_certificate true`):
  - **F1 (controle positivo):** `openssl s_client -brief -connect localhost:8883 -tls1_3 …` imprime `Protocol version: TLSv1.3` e não imprime `verify error`.
  - **F2:** `openssl s_client -brief … -tls1_2 …` **não** estabelece conexão (mesmo critério do Grupo B: falha se `rc == 0` ou se aparecer `CONNECTION ESTABLISHED`). A mensagem de falha cita `tls_version tlsv1.3` em `infra/docker/mosquitto/mosquitto.conf`.
  - **F3:** o backend continua conectado ao broker. Faça um laço de até 60 s (intervalo de 3 s) em `curl -sS --cacert "$rpc_ca" https://localhost/health/check` até o corpo conter `"mqttConnected":true`, e falhe com o último corpo recebido. É isto que prova que o cliente MQTT do backend negocia 1.3.

  Se algum certificado faltar, faça `falha` com o caminho, sem abortar: o script acumula as falhas.

- [ ] **Step 3: Rodar e ver o RED**

Run: `./scripts/qa/e2e.sh --keep` (se a stack não estiver de pé) e depois `./scripts/qa/tls_invariants.sh`
Expected: `FALHA — … TLS 1.2 …` no F2 (a auditoria mediu em 2026-10-15 que o broker negocia TLSv1.2), com F1 e F3 `ok`, e saída diferente de 0.

- [ ] **Step 4: Acrescentar `tls_version tlsv1.3` ao listener 8883 do `mosquitto.conf`**, logo depois de `keyfile`, com um comentário de uma linha: RNF04, mínimo do listener no Mosquitto 2, provado pelo Grupo F do `tls_invariants.sh`.

- [ ] **Step 5: Aplicar e ver o GREEN**

Run: `docker compose up -d --force-recreate mosquitto && ./scripts/qa/tls_invariants.sh && ./scripts/qa/mtls_invariants.sh`
Expected: `OK — as propriedades do RNF04 conferem.` (F1–F3 `ok`) e `OK — o broker exige certificado de cliente e mantém a senha`. Isso mostra que o `mosquitto_pub` do `eclipse-mosquitto:2` também negocia 1.3.

- [ ] **Step 6: Provar o cliente MQTT do ACS no emulador** (o ACS usa Dart/BoringSSL, mas a prova precisa ser medida):

Run: `export PATH="$HOME/Android/Sdk/platform-tools:$PATH" && adb -s emulator-5554 get-state && ./scripts/qa/e2e.sh --emulator`
Expected: `device`, depois smoke + `red_alert_cycle` verdes. O `red_alert_cycle` é o teste em que o ACS recebe o alerta pelo broker já limitado a 1.3. Se ficar vermelho, a tarefa não fecha: investigue a negociação TLS do cliente MQTT do app antes de seguir.

- [ ] **Step 7: Commit**

```bash
git add infra/docker/mosquitto/mosquitto.conf scripts/qa/tls_invariants.sh
git commit -m "fix(infra): broker MQTT só aceita TLS 1.3 (#78)"
```

---

### Task 2: `ApiTlsConfig`, o apiServer do Serverpod em TLS 1.3

**Files:**
- Create: `backend/sinalacs_server/lib/src/config/api_tls_config.dart`
- Create: `backend/sinalacs_server/test/unit/api_tls_config_test.dart`
- Modify: `backend/sinalacs_server/lib/server.dart:21` (construção do `Serverpod`)

**Interfaces:**
- Produces:
  - `class ApiTlsConfig { final String certificatePath; final String keyPath; }`
  - `static ApiTlsConfig? ApiTlsConfig.fromMap(Map<String, String> environment)`: devolve `null` quando nenhuma das duas variáveis está definida (vazia ou só espaços conta como ausente), devolve a instância quando as duas estão, e lança `StateError('API_TLS_CERT_PATH e API_TLS_KEY_PATH devem vir juntos.')` quando só uma está.
  - `SecurityContext toSecurityContext()`: `SecurityContext(withTrustedRoots: false)`, `useCertificateChain(certificatePath)`, `usePrivateKey(keyPath)`, `minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3`. Um arquivo ausente ou ilegível deixa a exceção do `dart:io` propagar, para o boot falhar fechado.
  - Variáveis de ambiente `API_TLS_CERT_PATH` e `API_TLS_KEY_PATH`, que a Task 3 define no compose.

- [ ] **Step 1: Escrever os testes que falham.** Em `test/unit/api_tls_config_test.dart`, sem tag (não precisam de banco). O `setUpAll` gera uma CA e uma folha `localhost` num `Directory.systemTemp.createTempSync()` usando `Process.run('openssl', …)` (`req -x509` para a CA e `req` + `x509 -req` com `subjectAltName=DNS:localhost,IP:127.0.0.1` para a folha); o `tearDownAll` apaga o diretório.

```dart
group('ApiTlsConfig.fromMap', () {
  test('sem as duas variáveis devolve null (HTTP, caminho do Render)', () {
    expect(ApiTlsConfig.fromMap({}), isNull);
  });
  test('string vazia ou só de espaços conta como ausente', () {
    expect(ApiTlsConfig.fromMap({'API_TLS_CERT_PATH': '', 'API_TLS_KEY_PATH': '  '}), isNull);
  });
  test('só o certificado é erro de boot que nomeia as duas', () {
    expect(() => ApiTlsConfig.fromMap({'API_TLS_CERT_PATH': '/x.crt'}),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('API_TLS_CERT_PATH'), contains('API_TLS_KEY_PATH')))));
  });
  test('só a chave também é erro de boot', () {
    expect(() => ApiTlsConfig.fromMap({'API_TLS_KEY_PATH': '/x.key'}), throwsStateError);
  });
  test('as duas juntas produzem os caminhos', () {
    final c = ApiTlsConfig.fromMap({'API_TLS_CERT_PATH': '/a.crt', 'API_TLS_KEY_PATH': '/a.key'})!;
    expect(c.certificatePath, '/a.crt');
    expect(c.keyPath, '/a.key');
  });
});

group('ApiTlsConfig.toSecurityContext', () {
  test('arquivo inexistente falha no boot, não cai para HTTP', () {
    expect(() => ApiTlsConfig(certificatePath: '/nao/existe.crt', keyPath: '/nao/existe.key')
        .toSecurityContext(), throwsA(anything));
  });
  test('servidor com o contexto aceita TLS 1.3 e recusa TLS 1.2', () async {
    // HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx), respondendo 200.
    // `openssl s_client -brief -connect 127.0.0.1:<porta> -tls1_3 -CAfile <ca>`:
    //   stdout+stderr contém 'Protocol version: TLSv1.3' e não contém 'verify error'.
    // `openssl s_client ... -tls1_2`: não contém 'CONNECTION ESTABLISHED' e exitCode != 0.
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/api_tls_config_test.dart`
Expected: FAIL na compilação (`ApiTlsConfig` não existe).

- [ ] **Step 3: Implementar `api_tls_config.dart`** conforme as Interfaces, com o cabeçalho explicando duas coisas: por que as variáveis são opcionais (o Render termina o TLS na borda e fala HTTP com o container) e por que não há mTLS (a linha do `relic_io` citada nas Global Constraints).

- [ ] **Step 4: Rodar e ver passar**

Run: `cd backend/sinalacs_server && dart test test/unit/api_tls_config_test.dart`
Expected: os 7 testes passam.

- [ ] **Step 5: Ligar no `server.dart`.** Antes de `Serverpod(...)`, faça `final apiTls = ApiTlsConfig.fromMap(Platform.environment);` e passe `securityContextConfig: apiTls == null ? null : SecurityContextConfig(apiServer: apiTls.toSecurityContext())`. O `SecurityContextConfig` é exportado por `package:serverpod/serverpod.dart`. Insights (8083) e webServer (8082) ficam em HTTP: nenhum dos dois é publicado nem roteado pelo compose.

- [ ] **Step 6: Suíte do backend sem regressão**

Run: `cd backend/sinalacs_server && dart analyze && docker compose --profile test up -d postgres-test && dart test -j 1`
Expected: `No issues found!` e todos os testes passando (o boot em HTTP sem `API_TLS_*` segue igual).

- [ ] **Step 7: Commit**

```bash
git add backend/sinalacs_server/lib/src/config/api_tls_config.dart backend/sinalacs_server/test/unit/api_tls_config_test.dart backend/sinalacs_server/lib/server.dart
git commit -m "feat(backend): apiServer em TLS 1.3 quando API_TLS_* está definido (#78)"
```

---

### Task 3: Traefik → backend por TLS 1.3 verificado na stack local

**Files:**
- Modify: `infra/docker/traefik/init.sh` (segunda folha, em diretório próprio)
- Modify: `infra/docker/traefik/dynamic/tls.yaml` (`http.serversTransports.backend-tls`)
- Modify: `docker-compose.yml` (serviço `serverpod`: env, volume, `depends_on`, `healthcheck`, labels)
- Modify: `scripts/qa/tls_invariants.sh` (novo Grupo E; o Grupo C passa a falar da 8080 *publicada* versus a *interna*)
- Modify: `scripts/qa/dev_key_permissions_test.sh` (incluir a chave nova, esperando 644)

**Interfaces:**
- Consumes: `API_TLS_CERT_PATH`/`API_TLS_KEY_PATH` da Task 2; Grupo F da Task 1 (o script continua um só).
- Produces: folha `infra/docker/traefik/runtime/backend/{ca.crt,backend.crt,backend.key}` (CN `sinalacs-serverpod`, SAN `DNS:sinalacs-serverpod,DNS:serverpod,DNS:localhost,IP:127.0.0.1`, `extendedKeyUsage=serverAuth`, mesmas `basicConstraints`/`keyUsage` da folha do Traefik), montada no backend em `/app/rpc-certs:ro`; transporte `backend-tls@file`.

- [ ] **Step 1: Escrever o Grupo E no `tls_invariants.sh`** (`== Grupo E: o Traefik fala com o backend por TLS 1.3, e só por ele ==`). Rode as sondas **dentro** do container do backend com `docker exec sinalacs-serverpod curl …`: a imagem já traz `curl`, porque o `HEALTHCHECK` do Dockerfile o usa, e a 8080 não é publicada. A CA no container é `/app/rpc-certs/ca.crt`.
  - **E1:** `curl -sS --max-time 5 http://localhost:8080/health/check` **não** devolve corpo com `"status"`. Mensagem de falha: "a 8080 interna atende em texto claro — o `API_TLS_*` do serviço serverpod deixou de valer".
  - **E2 (controle positivo):** `curl -sS -v --tlsv1.3 --cacert /app/rpc-certs/ca.crt https://localhost:8080/health/check` devolve `"status"`, e o `-v` mostra `TLSv1.3`.
  - **E3:** `curl -sS --tlsv1.2 --tls-max 1.2 --cacert /app/rpc-certs/ca.crt https://localhost:8080/health/check` falha (exit ≠ 0).
  - **E4 (estática, não precisa da stack):** `grep -rniE 'insecureSkipVerify' infra/docker/traefik/dynamic docker-compose.yml` não encontra nada, e `docker-compose.yml` contém `loadbalancer.serverstransport=backend-tls@file` e `loadbalancer.server.scheme=https`.

  Se o `docker exec` falhar por o container não existir, conte como `falha` com a mensagem de subir a stack: o Grupo A já denuncia esse estado.

- [ ] **Step 2: Rodar e ver o RED**

Run: `./scripts/qa/tls_invariants.sh`
Expected: falha em E1 (a 8080 interna responde em claro hoje), E2, E3 (sem TLS não há o que negociar) e E4. Os Grupos A, B, C, D e F seguem `ok`.

- [ ] **Step 3: `init.sh` emite a folha do backend.** Extraia a emissão atual da folha (tmp → assinar → `mv`, com o diagnóstico de CA trocada) para uma função `emitir_folha <dir> <nome> <cn> <san>` e chame-a duas vezes: uma para `server` em `$certs_dir`, com o SAN atual mais `RPC_CERT_SAN_EXTRA`, e outra para `backend` em `$runtime_dir/backend`, com o SAN das Interfaces, sem o extra. Copie `ca.crt` para `$runtime_dir/backend/`. Modos: diretório 755, `.crt` e `.key` 644. Atualize o cabeçalho: agora são duas folhas, e só a do backend vai para o container do backend, que nunca enxerga `ca.key`.

- [ ] **Step 4: `dynamic/tls.yaml` ganha o transporte**

```yaml
http:
  serversTransports:
    backend-tls:
      # O Traefik disca pelo IP do container; o nome verificado é o do SAN da folha do backend.
      serverName: sinalacs-serverpod
      # A mesma CA do RPC que assina a folha do backend; o Traefik já monta runtime/certs em /certs.
      rootCAs:
        - /certs/ca.crt
```

Não há `insecureSkipVerify` em lugar nenhum (a asserção E4 cobra isso).

- [ ] **Step 5: `docker-compose.yml`, serviço `serverpod`:**
  - `environment`: `API_TLS_CERT_PATH: /app/rpc-certs/backend.crt` e `API_TLS_KEY_PATH: /app/rpc-certs/backend.key`.
  - `volumes`: `- ./infra/docker/traefik/runtime/backend:/app/rpc-certs:ro`.
  - `depends_on`: `traefik-init: { condition: service_completed_successfully }`.
  - `healthcheck`: `test: ["CMD-SHELL", "curl -fsS -X POST -H 'Content-Type: application/json' -d '{}' --cacert /app/rpc-certs/ca.crt https://localhost:8080/health/check || exit 1"]`, com `interval: 30s`, `timeout: 3s`, `start_period: 20s`, os mesmos valores do Dockerfile.
  - labels: acrescentar `traefik.http.services.sinalacs.loadbalancer.server.scheme=https` e `traefik.http.services.sinalacs.loadbalancer.serverstransport=backend-tls@file`, e reescrever o comentário de `server.port=8080`, que hoje diz "O processo segue escutando em texto claro aqui dentro" e passa a dizer que o processo escuta TLS 1.3 na 8080 interna.

- [ ] **Step 6: `dev_key_permissions_test.sh`** passa a exigir 644 em `infra/docker/traefik/runtime/backend/backend.key`, no mesmo formato das outras chaves de folha.

- [ ] **Step 7: Aplicar e ver o GREEN**

Run: `docker compose up -d --build --force-recreate traefik-init traefik serverpod && docker compose ps serverpod && ./scripts/qa/tls_invariants.sh && ./scripts/qa/dev_key_permissions_test.sh`
Expected: `serverpod` `healthy`; `OK — as propriedades do RNF04 conferem.` com A–F `ok` (o Grupo A, 200 por `https://localhost/`, é o que prova que o Traefik verificou a folha pelo `serverName`); o teste de permissões verde.

- [ ] **Step 8: Bateria ponta a ponta sem regressão**

Run: `export PATH="$HOME/Android/Sdk/platform-tools:$PATH" && ./scripts/qa/e2e.sh && ./scripts/qa/e2e.sh --emulator`
Expected: as duas verdes. O `e2e.sh` já chama o `tls_invariants.sh`, e o `--emulator` prova o caminho emulador → `10.0.2.2:443` → Traefik → `https://serverpod:8080`, que é o trecho que esta tarefa mudou.

- [ ] **Step 9: Jornadas do ACS e do backoffice no emulador** (as duas passam pelo Traefik → backend e uma delas pausa o Traefik):

Run: `./scripts/qa/acs_full_e2e.sh && ./scripts/qa/admin_alertas_escalonar_e2e.sh`
Expected: as duas verdes. No escalonamento, o backend precisa continuar no ar com o mesmo `StartedAt` depois do `docker pause`/`unpause` do Traefik. Com isso fica provado que a reconexão do Traefik ao backend em TLS se recupera sozinha.

- [ ] **Step 10: Commit**

```bash
git add infra/docker/traefik/init.sh infra/docker/traefik/dynamic/tls.yaml docker-compose.yml scripts/qa/tls_invariants.sh scripts/qa/dev_key_permissions_test.sh
git commit -m "feat(infra): Traefik fala com o backend por TLS 1.3 verificado (#78)"
```

---

### Task 4: Documentação, decisão registrada e fechamento

**Files:**
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (linhas RNF04 `:107`, M2.3 `:175`, CRIPTO-TRAEFIK-BACKEND `:96`, item 4 `:231`)
- Modify: `PROGRESS.md` (nova entrada `#78` na seção de segurança/RNF04, ao lado das de mTLS em `:574`)
- Modify: `backend/CLAUDE.md:37` (deixa de dizer "the process still listens on cleartext 8080 inside the container") e `:39` (as variáveis `API_TLS_CERT_PATH`/`API_TLS_KEY_PATH` e o `ApiTlsConfig`)
- Modify: `backend/DEPLOY.md` (nota TLS em `:93`: no Render, deixar `API_TLS_*` vazias)
- Modify: `CLAUDE.md` da raiz (em "Already delivered", o trecho "TLS on the RPC via Traefik (RNF04)" passa a citar TLS 1.3 também no Traefik→backend e no broker)
- Modify: `apps/CLAUDE.md:71` e o comentário de `scripts/qa/admin_alertas_escalonar_e2e.sh:41` (`serverpod:8080` passa a ser https)

**Interfaces:**
- Consumes: resultados medidos das Tasks 1–3: datas, comandos e as provas no `emulator-5554` (API 36).

- [ ] **Step 1: Atualizar os documentos.**
  - Na auditoria, RNF04 passa a **atendido na stack local**. M2.3 continua **parcial**, mas só pelo WSS: a 9001 segue não publicada por decisão, e o TLS 1.3 está resolvido. CRIPTO-TRAEFIK-BACKEND passa a **parcial**, com TLS 1.3 de mão única e cadeia verificada; o mTLS fica bloqueado pelo `relic_io` sem `requestClientCertificate`.
  - O `PROGRESS.md` registra a decisão, as provas (Grupos E e F do `tls_invariants.sh`, `mtls_invariants.sh`, o teste unitário, `e2e.sh --emulator`, `acs_full_e2e.sh` e `admin_alertas_escalonar_e2e.sh` no `emulator-5554`, API 36, com a data) e os itens em aberto: mTLS interno, produção (o Render termina o TLS na borda) e a falta de prova em aparelho físico e em API 24–29 (a negociação do 1.3 só foi medida no emulador API 36).

- [ ] **Step 2: Verificar os links**

Run: `./scripts/qa/check_documentation_links.sh`
Expected: sai 0.

- [ ] **Step 3: Atualizar o grafo**

Run: `graphify update .`
Expected: termina sem erro.

- [ ] **Step 4: Commit**

```bash
git add docs/auditoria-prd/2026-10-15-lacunas-prd.md PROGRESS.md backend/CLAUDE.md backend/DEPLOY.md CLAUDE.md apps/CLAUDE.md scripts/qa/admin_alertas_escalonar_e2e.sh graphify-out
git commit -m "docs: registra TLS 1.3 no broker e no Traefik→backend (#78)"
```

- [ ] **Step 5: Issue de acompanhamento do mTLS interno.** **Confirme com o usuário antes**, porque é ação externa. Crie a issue com `gh issue create --title "mTLS Traefik ↔ backend bloqueado pelo Serverpod (requestClientCertificate)"` e um corpo que cite a linha do `relic_io`, a decisão de 2026-10-16 e as alternativas descartadas (sidecar, fork). Ponha o número dela no `PROGRESS.md` e na auditoria, num commit à parte.

- [ ] **Step 6: Push e PR para `develop`**, que também é ação externa e precisa de confirmação. O corpo do PR fecha a #78 e resume a decisão. CI esperada: os 9 jobs verdes. O `android-e2e` sobe a stack pelo compose, então exercita o healthcheck novo.
