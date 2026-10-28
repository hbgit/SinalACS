# Issue #90 — mTLS Traefik ↔ backend — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:executing-plans (execução **Native**, decisão do dono em 2026-10-27) tarefa a tarefa, com um **checkpoint de revisão independente depois da Task 5** (núcleo de segurança: patch do fork + `ApiTlsConfig` + wrapper do `SecureServerSocket`) antes de tocar Traefik, Compose e testes de stack — ver a seção "Checkpoint de revisão". Os passos usam checkbox (`- [ ]`). **Decisão do dono registrada em 2026-10-27: os itens 1 a 4 do "Ponto de decisão" foram aprovados, com as condições anotadas em cada um.** As condições viraram passos nas tarefas; nenhuma delas é opcional.

**Objetivo:** o backend passa a exigir, no handshake TLS da 8080 interna, um certificado de cliente assinado pela CA de desenvolvimento do RPC; o Traefik passa a apresentar esse certificado (`serversTransport.certificates`); um processo na rede do Compose sem o certificado é recusado antes de qualquer byte HTTP; o Grupo E de `scripts/qa/tls_invariants.sh` prova o caso negativo e o positivo; os apps continuam falando com o backend via Traefik (regressão no emulador).

**Arquitetura:** o Serverpod 3.4.13 sobe o apiServer por `RelicApp.serve` → `IOAdapter.bind` → `HttpServer.bindSecure`, sem como exigir certificado de cliente, e as versões 4.0.4 e 4.1.0-rc.1 têm a **mesma** chamada fixa (medido). A recomendação é um **fork pinado do Serverpod 3.4.13** com um patch mínimo e genérico — um `apiServerAdapterFactory` opcional que deixa a aplicação fornecer o `Adapter` do relic — consumido por `dependency_overrides` no workspace `backend/`. Toda a lógica de mTLS fica **no repositório** (`sinalacs_server`): `SecureServerSocket.bind(requireClientCertificate: true)` embrulhado num `ServerSocket` que o `HttpServer.listenOn` aceita, e `IOAdapter(httpServer)`. O `traefik-init` emite duas folhas `clientAuth` com a CA do RPC (uma para o Traefik, outra para o healthcheck do container), o Traefik as apresenta pelo `serversTransport` `backend-tls` que já existe, e `API_TLS_CLIENT_CA_PATH` passa a ser obrigatória junto com `API_TLS_CERT_PATH`/`API_TLS_KEY_PATH`.

**Tecnologias:** Serverpod 3.4.13 (Dart 3.12.2, `relic`/`relic_io` 1.2.0), `dart:io` (`SecureServerSocket`, `HttpServer.listenOn`), Traefik v2.11 (`serversTransports`), Docker Compose, OpenSSL, bash (`scripts/qa`), emulador Android (`emulator-5554`).

**Spec:** issue #90 (`gh issue view 90`), continuação da #78 (PR #89; plano `docs/superpowers/plans/2026-10-16-issue-78-tls13-broker-e-backend.md`, que registrou a decisão "TLS de mão única, sem fork e sem sidecar" em 2026-10-16). Requisito RNF04 (`spec/PRD_system.md:158`), linha CRIPTO-TRAEFIK-BACKEND de `docs/auditoria-prd/2026-10-15-lacunas-prd.md:96`. Fora do escopo (a issue é explícita): Postgres, Gorush, portas 8082/8083 e painel 8081.

## Restrições globais

- Português em código, comentários, mensagens, commits e documentação. Sem atribuição de IA em commits e PR (`CLAUDE.md`).
- **Não enfraquecer o TLS 1.3 Traefik → backend que existe:** `serverName: sinalacs-serverpod` e `rootCAs: [/certs/ca.crt]` do `backend-tls` ficam; nenhum `insecureSkipVerify` em lugar nenhum (E4 já cobra); `minimumTlsProtocolVersion = tls1_3` do `ApiTlsConfig` fica.
- **Nenhuma chave privada no git:** tudo nasce em `infra/docker/traefik/runtime/` (gitignored, `.gitignore:30`), gerado pelo `traefik-init`. Chave lida só por root → `600`; chave lida por outro uid → `644` (decisão em `PROGRESS.md:1525`, presa por `scripts/qa/dev_key_permissions_test.sh`).
- **Fora do escopo, intocados:** `postgres`, `gorush`, `SERVERPOD_DATABASE_REQUIRE_SSL`, Insights 8083, webServer 8082, dashboard 8081. RNF04 continua **parcial** por eles depois desta issue.
- **Um só escritor da configuração TLS do apiServer:** `ApiTlsConfig` (`lib/src/config/api_tls_config.dart`). A regra "as variáveis vêm juntas ou não vêm" passa a valer para **três** variáveis (`API_TLS_CERT_PATH`, `API_TLS_KEY_PATH`, `API_TLS_CLIENT_CA_PATH`). Sem as três = HTTP (caminho do Render, `backend/DEPLOY.md`), como hoje.
- **O fork do Serverpod carrega um só patch, genérico e sem semântica de mTLS:** `apiServerAdapterFactory`. Nada de lógica do SinalACS dentro do fork — assim o diff upstream é pequeno e o fork é descartável no dia em que o upstream expuser o ganho.
- `backend/pubspec.lock` muda **só** na entrada de `serverpod` (passa de `hosted` para `git`, mesma versão 3.4.13). Qualquer outra linha movendo é regressão a investigar.
- Sondas negativas **sempre** com controle positivo antes (desenho de `tls_invariants.sh` e `mtls_invariants.sh`): "recusado" com a stack no chão não conta.
- Testes de integração do backend: `dart test -j 1`. Nenhum dado real.

## Diagnóstico e reprodução (feito em 2026-10-27, `develop` em `d64e23c`)

Estado atual, medido com a stack de desenvolvimento de pé: um container **qualquer** na rede do Compose (`sinalacs_default`), sem certificado de cliente, completa o handshake TLS 1.3 com o backend e recebe o `health/check`.

```bash
# Comando-evidência (vira a base do caso negativo E5 do tls_invariants.sh).
# Roda de FORA do container do backend, como faria um container comprometido.
rede="$(docker inspect sinalacs-serverpod -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
docker run --rm --network "$rede" \
  -v "$PWD/infra/docker/traefik/runtime/backend/ca.crt:/ca.crt:ro" \
  curlimages/curl:8.10.1 -sS --max-time 10 --tlsv1.3 --cacert /ca.crt \
  -X POST -H 'Content-Type: application/json' -d '{}' \
  -w '\nHTTP %{http_code} verify=%{ssl_verify_result}\n' \
  https://sinalacs-serverpod:8080/health/check
```

Saída medida hoje (o defeito): `{"__className__":"ServiceHealth","status":"ok","mqttConnected":true,"dbConnected":true}` / `HTTP 200 verify=0`. Com `-v`, o handshake mostra `Server hello`, `Certificate (11)`, `Finished (20)` e **nenhum `Request CERT (13)`**: o servidor nunca pede o certificado. Depois da Task 7, o mesmo comando tem de terminar sem nenhuma linha HTTP (curl exit 35 ou 56, `HTTP 000`).

## Investigação do bloqueio (feita em 2026-10-27)

Verificado no `~/.pub-cache` e nos tarballs do pub.dev (`https://pub.dev/api/archives/<pacote>-<versão>.tar.gz`, descompactados em diretório isolado):

| Camada | Versão em uso | Última publicada | O que faz | Expõe `requestClientCertificate`/`requireClientCertificate`? |
|---|---|---|---|---|
| `dart:io` | 3.12.2 | — | `HttpServer.bindSecure(…, requestClientCertificate)` chama `SecureServerSocket.bind` **sem** repassar `requireClientCertificate` (`_http/http_impl.dart:3481-3499`). `SecureServerSocket.bind` tem os dois flags (`io/secure_server_socket.dart:72-73`). `HttpServer.listenOn(ServerSocket)` existe, mas `SecureServerSocket implements ServerSocketBase<SecureSocket>`, não `ServerSocket`. | Só `request` pelo `HttpServer`; `require` só pelo `SecureServerSocket` |
| `relic_io` | 1.2.0 | 1.2.0 (2.0.0-rc.2 em pré-lançamento) | `bindHttpServer` chama `HttpServer.bindSecure(address, port, context, backlog:, v6Only:, shared:)` (`lib/src/adapter/bind_http_server.dart:39`). **Idêntico em 2.0.0-rc.2.** `IOAdapter(this._server)` aceita um `HttpServer` já ligado. | Não |
| `serverpod` | 3.4.13 | 4.0.4 (4.1.0-rc.1 em pré-lançamento) | `Server.start` chama `_app.serve(address: anyIPv6, port:, securityContext:)` fixo (`lib/src/server/server.dart:172`). **Idêntico em 4.0.4 e 4.1.0-rc.1** (`server.dart:182`). `RelicApp.run(adapterFactory)` existe no `relic_core` e é o que `serve` usa por baixo. | Não |

Upstream: `gh search issues --repo serverpod/serverpod 'client certificate'`, `--repo serverpod/relic 'certificate'` e `--repo dart-lang/sdk 'HttpServer bindSecure requireClientCertificate'` em 2026-10-27 não acham nenhuma issue sobre certificado de cliente no servidor (a única do relic, #395, é sobre TLS no `relic_native`). O changelog do Serverpod cita "Improves client certificate security" num advisory antigo, que é sobre o **cliente** HTTP, não sobre o servidor. **Conclusão:** não existe versão para a qual subir; um upgrade para 4.x (major, com mudanças de API) não resolveria nada e está fora desta issue.

Viabilidade de contribuir upstream: a mudança natural é em dois repositórios — `relic_io` ganhar `requestClientCertificate`/`requireClientCertificate` em `bindHttpServer`/`IOAdapter.bind`/`serve` (e, para o *require*, ligar por `SecureServerSocket` + `HttpServer.listenOn`, porque o `bindSecure` do SDK não repassa o flag), e o Serverpod plumbar isso em `SecurityContextConfig`. Dois ciclos de release, sem prazo que o SinalACS controle, e a linha 3.4.x pode não receber a feature. Por isso o fork temporário, e por isso o patch do fork é o **gancho genérico** (`apiServerAdapterFactory`), que é também a proposta a abrir upstream: ele resolve o nosso caso sem o upstream precisar decidir a semântica de mTLS.

Prova de conceito (`dart:io` puro, feita em diretório temporário fora do repositório, com uma CA descartável): um `SecureServerSocket.bind(…, requireClientCertificate: true)` embrulhado num `ServerSocket` mínimo (`StreamView<Socket> implements ServerSocket`, com `address`/`port`/`close`) e passado a `HttpServer.listenOn` **funciona**: `curl` sem certificado recebe erro TLS (`curl: (56) … unexpected eof while reading`, `HTTP 000`), com certificado da CA recebe 200, com certificado de **outra** CA recebe o mesmo erro TLS. O `HttpServer.bindSecure(requestClientCertificate: true)` sozinho **não** serve ao critério: sem certificado o handshake completa e a aplicação vê `request.certificate == null` (a recusa seria HTTP 401, não handshake). Detalhe medido que o teste precisa respeitar: `openssl s_client -brief` sem certificado imprime `CONNECTION ESTABLISHED` / `TLSv1.3` **mesmo recusado** — no TLS 1.3 o cliente conclui o seu lado antes de o servidor validar o certificado dele — então as sondas negativas usam `curl` e afirmam a **ausência de resposta HTTP**, não o texto do `s_client`.

## Análise das alternativas

| | (A) Fork pinado do Serverpod 3.4.13 + mTLS no processo | (B) Sidecar de terminação mTLS (stunnel/nginx) na frente da 8080 | (C) Rede Docker interna só com Traefik + backend |
|---|---|---|---|
| Atende o critério "sem certificado → recusa no handshake"? | **Sim** — `requireClientCertificate: true` (PoC acima) | Sim, no sidecar; o backend em si continua aceitando qualquer um, então a 8080 do backend tem de deixar de ser alcançável (`network_mode: service:sidecar` ou porta só em `127.0.0.1`) | **Não** — é mitigação. O backend escuta em `anyIPv6` e continua na rede `default` com Postgres, Mosquitto e Gorush; esses três seguem alcançando a 8080 sem certificado |
| Autentica o Traefik? | Sim, pela CA do RPC | Sim, pela CA do RPC | Não |
| `spec/stack.md` | **Dentro** — Serverpod continua o backend; muda a *procedência* do pacote (git pinado), não a stack | **Fora** — serviço novo não previsto; exige decisão de arquitetura e nova entrada no `docker-compose.yml`, nova imagem, novo par de certificados, dois TLS em sequência (ou o backend volta a HTTP atrás do sidecar, perdendo o que a #78 entregou) | Dentro |
| Complexidade e risco | Patch de ~15 linhas no fork (um parâmetro novo plumbado de `Serverpod` → `Server.start`), ~60 linhas Dart no repositório, 2 folhas novas no `traefik-init`. Risco: manutenção do fork no próximo upgrade do Serverpod (rebase de um patch pequeno); e o `ServerSocket` embrulhado depende de o `_HttpServer` só usar `listen`/`address`/`port`/`close` (preso por teste) | Mais um processo para subir, logar e manter; `network_mode: service:` quebra o DNS do backend e o provider Docker do Traefik; stunnel não fala HTTP (não há healthcheck de aplicação nele) | Baixa complexidade, mas não fecha a issue e dá falsa sensação de segurança |
| Manutenção | Rebase do fork a cada upgrade do Serverpod até o upstream aceitar o gancho | Imagem e configuração de um componente a mais, para sempre | Nenhuma |

**Recomendação: (A).** É a única que atende o critério de aceite como *autenticação* e fica dentro do `spec/stack.md`. O custo é manter um fork pinado por commit com um patch pequeno, genérico e com proposta upstream aberta — custo que a #78 recusou quando o escopo era "TLS 1.3 nos três trechos" e que esta issue existe justamente para reavaliar. (C) pode ser somada depois como defesa em profundidade, mas não substitui (A). (B) só se (A) for recusada **e** o dono aceitar mudar o `spec/stack.md`.

## Ponto de decisão — respondido pelo dono em 2026-10-27

A recomendação **não sai do `spec/stack.md`**, mas reverte uma decisão registrada (2026-10-16: "sem fork") e envolve ações externas. O dono aprovou os quatro itens, com condições que agora são parte do plano:

1. **Fork pinado do Serverpod — APROVADO, com condições.** `hbgit/serverpod` (fork de `serverpod/serverpod`), branch `sinalacs/3.4.13-api-server-adapter` a partir da tag `3.4.13`, **um** commit de patch, consumido por `dependency_overrides` apontando para o **SHA** (nunca para o branch); diff versionado em `backend/patches/serverpod-3.4.13-api-server-adapter.patch`. Condições: (a) **registro da reversão** da decisão da #78 em `spec/stack.md`, numa nota-ADR curta com três coisas — o motivo (bloqueio upstream comprovado: `Server.start` fixo em 3.4.13, 4.0.4 e 4.1.0-rc.1; `relic_io` sem o flag; `bindSecure` do SDK sem `require`), o **critério de saída** (remover o fork e voltar ao pub.dev no dia em que o gancho — ou equivalente que recuse no handshake — entrar numa versão oficial) e o **custo de upgrade** (subir para 4.x exige rebase do patch antes de qualquer outra coisa) → Task 10; (b) **o build Docker busca o fork sem credencial** (repositório público; prova por `docker build` numa máquina sem `~/.gitconfig`/credential helper, isto é, com `GIT_CONFIG_GLOBAL=/dev/null` no estágio de build, e pelo job `backend-docker-build` da CI, que não tem token) → Task 2; (c) **o cliente Flutter não é afetado**: num workspace Dart o `dependency_overrides` só vale no `pubspec.yaml` da **raiz** (`backend/pubspec.yaml`; um override num membro é ignorado com aviso), então ele mora lá por regra do pub, mas o único pacote que depende de `serverpod` é `sinalacs_server` — `sinalacs_client` depende de `serverpod_client` e os três apps de `serverpod_client`/`serverpod_flutter`, todos do pub.dev; a prova é `git diff --stat -- backend/sinalacs_client apps/*/pubspec.lock` vazio e `grep -n '^  serverpod:' apps/*/pubspec.yaml backend/sinalacs_client/pubspec.yaml` sem resultado → Task 2.
2. **Issue upstream — APROVADO, com condições.** O patch é proposto contra o **`main`** (linha 4.x; `Server.start` lá é idêntico, então o mesmo diff aplica) num segundo branch do fork, `upstream/api-server-adapter`; o branch `sinalacs/3.4.13-…` continua sendo o consumido. A issue traz a **evidência** de que `requestClientCertificate` sozinho não recusa no handshake (saída da PoC: handshake completo, `request.certificate == null`, HTTP 401 só na aplicação) — é o que justifica o gancho de adapter em vez de uma flag, e evita o upstream "resolver" com a flag errada → Task 10.
3. **Três variáveis juntas ou nenhuma — APROVADO, com condições.** (a) **Fail-fast no boot**: cert + chave sem CA (ou qualquer subconjunto próprio) → o processo não sobe e a mensagem nomeia as três variáveis e diz que TLS de mão única não é mais uma configuração válida; nunca cai para mão única em silêncio → Task 3 (já era `StateError` em `fromMap`; a condição fixa o **texto** e acrescenta o teste de que o boot do container falha, Task 7 mutação b). (b) **Inventário de quem fala direto com a 8080** feito antes de executar — seção abaixo.
4. **Folha de cliente para o healthcheck — APROVADO, com condições.** Folha **distinta** da do Traefik, CN próprio `sinalacs-healthcheck`, EKU restrito a `clientAuth`, **validade curta** (`healthcheck_days=90`, contra 825 das demais; a folha é regerada a cada `traefik-init`, e o Grupo E ganha a asserção E9, que acusa quando faltam menos de 7 dias) → Tasks 6 e 8. Limite registrado: as duas origens são distinguíveis pelo CN no TLS, mas o backend **não loga** o CN do cliente hoje (nem o Serverpod nem o relic expõem o `peerCertificate` ao handler); registrar isso no `PROGRESS.md` como aberto, fora do escopo.
5. **Rede interna como defesa em profundidade (C)** — fica **fora** deste plano (issue de continuação).

## Inventário: quem fala com a 8080 do backend (condição 3b, levantado em 2026-10-27)

`grep -rn ':8080' --include='*.dart' --include='*.sh' --include='*.yml' --include='*.yaml' --include='*.py' --include=Dockerfile --include='*.md'` fora de `pg_data/`, `build/`, `graphify-out/` e dos planos, mais os defaults de host dos apps e das ferramentas:

| Cliente | Hoje | Depois da #90 | Tarefa |
|---|---|---|---|
| `HEALTHCHECK` do `docker-compose.yml` (`curl … https://localhost:8080/health/check`, dentro do container) | TLS de mão única | **Quebra** sem certificado → recebe `healthcheck.{crt,key}` | Task 7 |
| Grupo E de `tls_invariants.sh` (E1–E3 por `docker exec` no container do backend) | sondas sem certificado | **Quebra** a positiva E2 → reescrito de fora da rede, com certificado na positiva | Task 8 |
| Grupos C e D de `tls_invariants.sh` (`http://localhost:8080`, texto claro, negativos) | recusados | inalterados (continuam negativos) | — |
| `HEALTHCHECK` do `Dockerfile` (`http://localhost:8080`, caminho do Render) | HTTP, sem `API_TLS_*` | inalterado: sem as três variáveis o apiServer segue em HTTP | — (uma frase em `backend/DEPLOY.md`) |
| `dart run bin/main.dart` fora do Compose, e o harness `withServerpod` dos testes de integração | HTTP (não leem `API_TLS_*`) | inalterados; quem exportar `API_TLS_CERT_PATH`/`KEY_PATH` à mão passa a precisar da terceira | `backend/CLAUDE.md` (Task 10) |
| Traefik (`serversTransport backend-tls`) | TLS verificado, sem certificado de cliente | **Quebra** → `certificates` | Task 7 |
| Apps (`SINALACS_HOST`, default `https://10.0.2.2/` ou `https://localhost:8443/` via `adb reverse`), `tool/live_check.dart`, `tool/send_notice.dart`, `tool/schedule_notice.dart`, `scripts/qa/measure_latency.dart` | todos pelo Traefik em :443 (`requireSecureHost` recusa `http://…:8080`) | inalterados | — (Task 9 prova) |
| `apps/*/test/*` com `http://10.0.2.2:8080/` | é a **fixture negativa** de `requireSecureHost` | inalterados | — |
| `scripts/qa/admin_alertas_escalonar_e2e.sh:41`, `video/README.md:144`, `spec/PRD_system.md:741` | só comentário/histórico | inalterados | — |

Conclusão: só três consumidores reais da 8080 existem (healthcheck do Compose, Grupo E, Traefik) e os três estão nas Tasks 7 e 8. Nenhum app, ferramenta ou teste fala com a 8080 diretamente.

## Risco coberto: handshake falho é erro no stream do listener (DoS)

No `SecureServerSocket`, um handshake que falha vira `addError` no stream do socket servidor (`RawSecureServerSocket._onData` → `catchError` → `_controller.addError`). Medido no SDK 3.12.2 e no relic 1.2.0:

- `_HttpServer.listenOn` escuta o socket com `onError` que **ignora `HandshakeException`** ("bound to a single request, and are not fatal for the server", `_http/http_impl.dart:3564-3570`) e repassa os demais ao stream de requests; `cancelOnError` não é usado.
- O relic escuta `adapter.requests.listen(_handleRequest)` dentro de `catchTopLevelErrors` (`relic_core/lib/src/relic_server.dart:97-108`), que só **loga** erros assíncronos; e `bin/main.dart` ainda tem o `runZonedGuarded` da #56.
- PoC: 30 conexões sem certificado + 10 de outra CA + 10 conexões TCP com bytes inválidos abortadas no meio do handshake, **depois** a sonda positiva recebe 200 e o stderr do servidor fica vazio.

Decisões do plano: (1) o wrapper `SecureServerSocketAsServerSocket` **não** usa `cancelOnError` e acrescenta, como defesa em profundidade, `handleError` que descarta `TlsException` (inclui `HandshakeException`) e `SocketException` do caminho de aceitação, contando-os e logando só o tipo (VAZ-01: nada do peer) — para o listener não depender de um detalhe do SDK; (2) teste unitário "rajada de handshakes falhos não derruba o listener" na Task 4; (3) asserção **E8** no Grupo E (Task 8): 20 sondas negativas seguidas e, em seguida, a positiva ainda recebe 200; (4) mutação (d) na Task 8: trocar o `handleError` por um `map` que relança como `StateError` — o resultado esperado é que E8 e o unitário **continuem verdes** (a camada do SDK protege) e o log do backend ganhe a linha de erro; se E8 ficar vermelho, o SDK mudou e o wrapper é a única proteção, o que é informação a registrar no `PROGRESS.md`. A mutação é medida, não gate.

## Mapa de arquivos

- **Fork (repositório externo `hbgit/serverpod`, branch `sinalacs/3.4.13-api-server-adapter`):**
  - Create: `packages/serverpod/lib/src/server/api_server_adapter_factory.dart` — `typedef ApiServerAdapterFactory`.
  - Modify: `packages/serverpod/lib/src/server/server.dart` (construtor `Server` e `start`), `packages/serverpod/lib/src/server/serverpod.dart` (construtor `Serverpod`, repasse ao `Server`), `packages/serverpod/lib/serverpod.dart` (export).
- **Repositório:**
  - Create: `backend/patches/serverpod-3.4.13-api-server-adapter.patch`, `backend/patches/README.md`.
  - Modify: `backend/pubspec.yaml` (`dependency_overrides`), `backend/pubspec.lock` (só a entrada `serverpod`), `backend/sinalacs_server/pubspec.yaml` (`relic` como dependência direta), `backend/sinalacs_server/Dockerfile` (copia o `pubspec.yaml` real).
  - Create: `backend/sinalacs_server/lib/src/runtime/mtls_api_server.dart`; Test: `backend/sinalacs_server/test/unit/mtls_api_server_test.dart`.
  - Modify: `backend/sinalacs_server/lib/src/config/api_tls_config.dart`; Test: `backend/sinalacs_server/test/unit/api_tls_config_test.dart`.
  - Modify: `backend/sinalacs_server/lib/server.dart` (`Serverpod(… apiServerAdapterFactory:)`).
  - Modify: `infra/docker/traefik/init.sh` (duas folhas `clientAuth`), `infra/docker/traefik/dynamic/tls.yaml` (`certificates` do `backend-tls`), `docker-compose.yml` (`API_TLS_CLIENT_CA_PATH`, healthcheck com certificado, comentários), `scripts/qa/e2e_stack.sh` (lista de arquivos que o `traefik-init` tem de produzir).
  - Modify: `scripts/qa/tls_invariants.sh` (Grupo E), `scripts/qa/dev_key_permissions_test.sh`.
  - Modify (docs): `CLAUDE.md`, `backend/CLAUDE.md:39`, `spec/stack.md` (nota ao lado da do broker, `:76`), `docs/auditoria-prd/2026-10-15-lacunas-prd.md:96,107,231`, `PROGRESS.md`, `.claude/skills/validacao-e2e/SKILL.md:17`, `backend/DEPLOY.md` (uma frase: no Render as três variáveis ficam vazias).

## Review Focus

Entradas que a issue implica e que nenhum teste cobria; cada uma ganha um teste na tarefa dona:

1. **Duas das três `API_TLS_*` definidas** (por exemplo, `.env` antigo com cert+key e sem `CLIENT_CA`) → o boot tem de **falhar nomeando as três**, nunca subir em TLS de mão única. → Task 3 (`fromMap`).
2. **Certificado de cliente de outra CA com CN plausível** (`sinalacs-traefik`) → recusado no handshake. → Task 4 (unitário) e Task 8 (E6 na stack).
3. **Folha do Traefik emitida com `extendedKeyUsage=serverAuth`** (reuso descuidado de `emitir_folha`) → o BoringSSL do backend recusa como certificado de cliente e o Traefik devolve 5xx para **todo** app, com uma mensagem que não diz por quê. → Task 6 (`openssl x509 -ext extendedKeyUsage` nas duas folhas) e Task 8 (E7).
4. **`docker compose up -d` com a stack de pé regera as folhas** sem recriar o Traefik → o Traefik segue com a folha antiga em memória; ela continua válida (825 dias, sem revogação), então **não quebra** — mas o `e2e_stack.sh up` com `--force-recreate` tem de continuar encontrando os arquivos novos. → Task 7 (lista de arquivos do `e2e_stack.sh`).
5. **Código de saída do `curl` varia com a versão do OpenSSL** (35 ou 56 na recusa TLS) → as sondas afirmam "nenhuma linha HTTP e nenhum `"status"`", nunca um código fixo. → Task 4 e Task 8.
6. **Upgrade futuro do Dart SDK muda o `_HttpServer`** e o `ServerSocket` embrulhado deixa de bastar → o teste unitário que liga de verdade e sonda com `curl` acusa. → Task 4.

---

### Task 1: Fork pinado do Serverpod com o gancho `apiServerAdapterFactory`

**Files (fork `hbgit/serverpod`, branch `sinalacs/3.4.13-api-server-adapter`, base tag `3.4.13`):**
- Create: `packages/serverpod/lib/src/server/api_server_adapter_factory.dart`
- Modify: `packages/serverpod/lib/src/server/server.dart:105-125` (construtor) e `:160-185` (`start`)
- Modify: `packages/serverpod/lib/src/server/serverpod.dart:386-425` (campo + construtor) e `:590-601` (construção do `Server`)
- Modify: `packages/serverpod/lib/serverpod.dart` (export do typedef)
- Create (repositório): `backend/patches/serverpod-3.4.13-api-server-adapter.patch`, `backend/patches/README.md`

**Interfaces:**
- Produces: `typedef ApiServerAdapterFactory = FutureOr<Adapter> Function(InternetAddress address, int port, SecurityContext? securityContext);` (import `dart:async`, `dart:io`, `package:relic/relic.dart`), exportado por `package:serverpod/serverpod.dart`.
- Produces: `Serverpod(args, serializationManager, endpoints, {…, SecurityContextConfig? securityContextConfig, ApiServerAdapterFactory? apiServerAdapterFactory})` — novo parâmetro nomeado, opcional, padrão `null`.
- Comportamento em `Server.start`: `factory == null` → `_app.serve(address: anyIPv6, port: _port, securityContext: _securityContext)` **inalterado**; `factory != null` → `_app.run(() => factory(io.InternetAddress.anyIPv6, _port, _securityContext))`. `_actualPort`, `_relicServer`, log e tratamento de erro continuam os mesmos.

- [ ] **Step 1: Criar o fork e o branch** (ação externa — só depois do item 1 do Ponto de decisão)

```bash
gh repo fork serverpod/serverpod --clone=false --org hbgit 2>/dev/null || gh repo fork serverpod/serverpod --clone=false
git clone --depth 50 --branch 3.4.13 https://github.com/hbgit/serverpod.git /tmp/claude-1000/-home-rock-Documents-Dev-APPs-SinalACS/cab90aba-7955-4af2-a40f-8109919254cc/scratchpad/serverpod-fork
cd /tmp/claude-1000/-home-rock-Documents-Dev-APPs-SinalACS/cab90aba-7955-4af2-a40f-8109919254cc/scratchpad/serverpod-fork && git switch -c sinalacs/3.4.13-api-server-adapter
```

Confirmar antes de editar: `grep -n 'resolution' packages/serverpod/pubspec.yaml` não acha nada (verificado em 2026-10-27 no raw da tag: o pacote **não** usa `resolution: workspace`, então a dependência `git` + `path: packages/serverpod` resolve).

- [ ] **Step 2: Escrever o patch** — o typedef no arquivo novo; em `Server`, campo `final ApiServerAdapterFactory? _apiServerAdapterFactory` e parâmetro nomeado `ApiServerAdapterFactory? apiServerAdapterFactory` no construtor; em `start`, o `if` descrito nas Interfaces; em `Serverpod`, campo + parâmetro + repasse na construção do `Server` (`:590`); export no `serverpod.dart`. Doc-comment em inglês (é o idioma do upstream), dizendo que o gancho existe para quem precisa de opções de bind que o `serve` não expõe (por exemplo, `requireClientCertificate`).

- [ ] **Step 3: Verificar que o fork compila e que o comportamento padrão não mudou**

Run: `cd packages/serverpod && dart pub get && dart analyze && dart test test/unit 2>&1 | tail -3` (dentro do clone do fork)
Expected: `No issues found!` e a suíte unitária do pacote verde (a mesma contagem que no `3.4.13` sem o patch — medir antes com `git stash`).

- [ ] **Step 4: Commit no fork, push, anotar o SHA**

```bash
git add -A && git commit -m "feat(server): optional apiServerAdapterFactory to supply the API server Adapter"
git push -u origin sinalacs/3.4.13-api-server-adapter
git rev-parse HEAD   # <SHA> usado na Task 2
git format-patch -1 --stdout > /home/rock/Documents/Dev/APPs/SinalACS/backend/patches/serverpod-3.4.13-api-server-adapter.patch
```

- [ ] **Step 4b: O mesmo patch contra o `main` (decisão 2: a proposta upstream vai para a linha 4.x)**

```bash
git fetch origin main && git switch -c upstream/api-server-adapter origin/main
git cherry-pick <SHA>          # Server.start é idêntico no main (medido em 4.0.4/4.1.0-rc.1); conflito só se o construtor mudou
cd packages/serverpod && dart analyze && dart test test/unit 2>&1 | tail -2
git push -u origin upstream/api-server-adapter
```

Expected: `cherry-pick` limpo (ou conflito trivial no construtor de `Serverpod`), análise e unitários verdes. Esse branch é só a proposta; o `dependency_overrides` continua apontando para o `<SHA>` do branch 3.4.13.

- [ ] **Step 5: `backend/patches/README.md`** — três parágrafos: por que o fork existe (#90, bloqueio do `relic_io`/`Server.start`), como refazê-lo a partir da tag `3.4.13` com `git am`, e a regra "o `dependency_overrides` aponta para SHA, nunca para branch; ao subir o Serverpod, rebase do patch primeiro e issue upstream linkada".

- [ ] **Step 6: Commit (repositório)**

```bash
git add backend/patches
git commit -m "build(serverpod): patch do fork pinado com apiServerAdapterFactory (#90)"
```

### Task 2: `dependency_overrides` e Dockerfile que o preserva

**Files:**
- Modify: `backend/pubspec.yaml`, `backend/pubspec.lock`, `backend/sinalacs_server/pubspec.yaml`, `backend/sinalacs_server/Dockerfile:14-25`

**Interfaces:**
- Consumes: `<SHA>` da Task 1.
- Produces: `package:serverpod/serverpod.dart` passa a exportar `ApiServerAdapterFactory`; `package:relic/relic.dart` passa a ser importável de `sinalacs_server` (`IOAdapter`, `Adapter`).

- [ ] **Step 1: Teste de falha primeiro — o import ainda não existe**

Criar `backend/sinalacs_server/test/unit/serverpod_fork_test.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

/// O fork pinado do Serverpod (#90) expõe o gancho que o 3.4.13 do pub.dev não tem.
void main() {
  test('Serverpod exporta ApiServerAdapterFactory (fork pinado, #90)', () {
    ApiServerAdapterFactory? f;
    expect(f, isNull);
  });
}
```

Run: `cd backend/sinalacs_server && dart test test/unit/serverpod_fork_test.dart`
Expected: FALHA de compilação, `Undefined class 'ApiServerAdapterFactory'`.

- [ ] **Step 2: Override no workspace** — em `backend/pubspec.yaml`:

```yaml
dependency_overrides:
  # Fork pinado do Serverpod 3.4.13 com o gancho apiServerAdapterFactory (#90).
  # Patch e motivo: backend/patches/README.md. SHA, nunca branch.
  serverpod:
    git:
      url: https://github.com/hbgit/serverpod.git
      ref: <SHA>
      path: packages/serverpod
```

Em `backend/sinalacs_server/pubspec.yaml`, `dependencies:` ganha `relic: ^1.2.0` (já resolvido como transitiva em 1.2.0; só vira direta para o `IOAdapter` ser importável sem o lint `depend_on_referenced_packages`).

Run: `cd backend && dart pub get && git diff --stat pubspec.lock`
Expected: só a entrada `serverpod` muda (`source: git`, `resolved-ref: <SHA>`, `version: "3.4.13"`); `relic` não se move.

- [ ] **Step 3: Rodar o teste do Step 1**

Run: `cd backend/sinalacs_server && dart test test/unit/serverpod_fork_test.dart`
Expected: PASS.

- [ ] **Step 4: Dockerfile preserva o override** — hoje o estágio de build **gera** um `pubspec.yaml` de raiz por `printf` (`Dockerfile:17-24`), que perderia o `dependency_overrides`. Trocar por copiar o real e tirar o membro que não entra na imagem:

```dockerfile
COPY pubspec.yaml pubspec.lock .
COPY sinalacs_server sinalacs_server
# O workspace real lista também o sinalacs_client, que não entra na imagem; o
# dependency_overrides (fork pinado do Serverpod, #90) tem de entrar, por isso
# o arquivo é copiado em vez de gerado aqui.
RUN sed -i '/^  - sinalacs_client$/d' pubspec.yaml
RUN dart pub get
```

A imagem `dart:3.12.2` tem `git 2.47.3` (medido), necessário para a dependência `git`.

Run: `docker build -f backend/sinalacs_server/Dockerfile backend -t sinalacs/server:local 2>&1 | tail -3`
Expected: build concluído; `docker run --rm --entrypoint sh sinalacs/server:local -c 'true'` sai 0. O estágio de build não monta `~/.gitconfig` nem recebe token: o `dart pub get` clona `https://github.com/hbgit/serverpod.git` **anônimo** (decisão 1b). Repetir sem cache de camadas — `docker build --no-cache …` — para a prova não vir de uma camada antiga; e o job `backend-docker-build` da CI (sem credencial) é a segunda prova, na Task 10.

- [ ] **Step 4b: O cliente Flutter não é afetado (decisão 1c)**

Run: `cd backend/sinalacs_client && dart pub get && cd ../.. && for a in acs patient admin; do (cd apps/$a && flutter pub get >/dev/null); done; git diff --stat -- backend/sinalacs_client apps/*/pubspec.lock; grep -n '^  serverpod:' apps/*/pubspec.yaml backend/sinalacs_client/pubspec.yaml`
Expected: `git diff --stat` **vazio** e o `grep` sem resultado — nenhum app nem o cliente gerado dependem de `serverpod`; só de `serverpod_client`/`serverpod_flutter` do pub.dev. (O override mora em `backend/pubspec.yaml` porque o pub só honra `dependency_overrides` na raiz do workspace; isso é regra do pub, não escolha.)

- [ ] **Step 5: Suíte unitária e análise**

Run: `cd backend && dart analyze && cd sinalacs_server && dart test test/unit 2>&1 | tail -2`
Expected: `No issues found!`; unitários verdes.

- [ ] **Step 6: Commit**

```bash
git add backend/pubspec.yaml backend/pubspec.lock backend/sinalacs_server/pubspec.yaml backend/sinalacs_server/Dockerfile backend/sinalacs_server/test/unit/serverpod_fork_test.dart
git commit -m "build(backend): Serverpod pelo fork pinado; Dockerfile preserva o dependency_overrides (#90)"
```

### Task 3: `ApiTlsConfig` com a CA dos certificados de cliente (três variáveis juntas)

**Files:**
- Modify: `backend/sinalacs_server/lib/src/config/api_tls_config.dart`
- Test: `backend/sinalacs_server/test/unit/api_tls_config_test.dart`

**Interfaces:**
- Produces: `const ApiTlsConfig({required String certificatePath, required String keyPath, required String clientCaPath})`.
- Produces: `static ApiTlsConfig? fromMap(Map<String, String> environment)` — lê `API_TLS_CERT_PATH`, `API_TLS_KEY_PATH`, `API_TLS_CLIENT_CA_PATH`; as três ausentes/brancas → `null`; qualquer subconjunto próprio → `StateError` com a mensagem **exata** `API_TLS_CERT_PATH, API_TLS_KEY_PATH e API_TLS_CLIENT_CA_PATH devem vir juntas: o apiServer exige certificado de cliente (#90) e TLS sem essa exigência não é mais uma configuração válida.` (decisão 3a: fail-fast, texto que diz o porquê; a exceção sobe por `run()` e o processo sai ≠ 0 — a mutação (b) da Task 8 prova no container).
- Produces: `SecurityContext toSecurityContext()` — o de hoje mais `..setTrustedCertificates(clientCaPath)..setClientAuthorities(clientCaPath)`; `withTrustedRoots: false` fica (só a CA do RPC assina clientes aceitos).

- [ ] **Step 1: Testes que falham** — em `api_tls_config_test.dart`, no grupo `fromMap`: `'só duas das três é erro de boot que nomeia as três'` (cert+key sem CA → `StateError` contendo `API_TLS_CERT_PATH`, `API_TLS_KEY_PATH`, `API_TLS_CLIENT_CA_PATH`; repetir para cert+CA e key+CA via loop de três casos), `'as três juntas produzem os caminhos'` (`clientCaPath == '/ca.crt'`). Atualizar os testes existentes `'só o certificado…'` e `'só a chave…'` para esperar os três nomes, e `'as duas juntas produzem os caminhos'` passa a ser o caso de **erro** (duas sem a terceira). No grupo `toSecurityContext`, o `setUpAll` passa `clientCaPath: caPath`.

Run: `cd backend/sinalacs_server && dart test test/unit/api_tls_config_test.dart`
Expected: FALHA — `No named parameter with the name 'clientCaPath'`.

- [ ] **Step 2: Implementar** conforme as Interfaces. Reescrever o cabeçalho do arquivo: o parágrafo "É TLS de mão única, de propósito (decisão de 2026-10-16)…" sai e entra: desde a #90 o apiServer **exige** certificado de cliente assinado pela CA de `API_TLS_CLIENT_CA_PATH`; o bind com `requireClientCertificate` está em `lib/src/runtime/mtls_api_server.dart` (Task 4) porque o `HttpServer.bindSecure` do SDK e o `relic_io` não expõem o flag — o Serverpod é consumido por fork pinado (`backend/patches/README.md`).

- [ ] **Step 3: Rodar**

Run: `cd backend/sinalacs_server && dart test test/unit/api_tls_config_test.dart`
Expected: PASS (todos; o `'servidor com o contexto aceita TLS 1.3 e recusa TLS 1.2'` continua verde — ele usa `bindSecure` sem pedir certificado, e `setClientAuthorities` sem o flag não muda o handshake).

- [ ] **Step 4: Commit**

```bash
git add backend/sinalacs_server/lib/src/config/api_tls_config.dart backend/sinalacs_server/test/unit/api_tls_config_test.dart
git commit -m "feat(tls): API_TLS_CLIENT_CA_PATH obrigatória junto com cert e chave; contexto confia só na CA do RPC (#90)"
```

### Task 4: Bind do apiServer exigindo certificado de cliente

**Files:**
- Create: `backend/sinalacs_server/lib/src/runtime/mtls_api_server.dart`
- Test: `backend/sinalacs_server/test/unit/mtls_api_server_test.dart`

**Interfaces:**
- Produces: `Future<HttpServer> bindRequiringClientCertificate(InternetAddress address, int port, SecurityContext context)` — `SecureServerSocket.bind(address, port, context, requireClientCertificate: true)` embrulhado por `SecureServerSocketAsServerSocket` e entregue a `HttpServer.listenOn`.
- Produces: `class SecureServerSocketAsServerSocket extends StreamView<Socket> implements ServerSocket` — `address`, `port` e `close()` delegados ao `SecureServerSocket` (o `_HttpServer` só usa esses quatro membros, medido no SDK 3.12.2 em `_http/http_impl.dart:3510`). O stream passado ao `super` é `inner.handleError(_registrarHandshakeFalho, test: (e) => e is TlsException || e is SocketException)`: um handshake falho **nunca** chega ao `HttpServer` como erro, não há `cancelOnError`, e `_registrarHandshakeFalho` incrementa `handshakesRecusados` (campo `int`, exposto para o teste) e loga só o tipo do erro (`[tls] handshake recusado: HandshakeException`), nunca endereço ou bytes do peer (VAZ-01). Construtor: `SecureServerSocketAsServerSocket(SecureServerSocket inner, {void Function(String) log = print})`.
- Produces: `Future<Adapter> mtlsApiServerAdapter(InternetAddress address, int port, SecurityContext? securityContext)` — a `ApiServerAdapterFactory` da Task 1; `securityContext == null` → `StateError('mtlsApiServerAdapter exige SecurityContext: sem API_TLS_* o apiServer sobe em HTTP pelo caminho padrão do Serverpod.')` (falha fechada); senão `IOAdapter(await bindRequiringClientCertificate(...))`.

- [ ] **Step 1: Testes que falham** — `mtls_api_server_test.dart` gera, no `setUpAll`, a mesma CA + folha de servidor que `api_tls_config_test.dart` (`openssl` em `Directory.systemTemp`) **mais** uma folha de cliente (`cliente.ext` = `extendedKeyUsage=clientAuth`, CN `traefik-de-teste`) **e** uma segunda CA com uma folha de cliente própria (`fora.crt`). O servidor de teste responde `{"status":"ok"}` a qualquer pedido. Sondas com `Process.run('curl', […])` (curl está no host e no runner), sempre `--tlsv1.3 --cacert ca.crt -sS --max-time 5 -w '\nHTTP %{http_code}'`:

```dart
test('sem certificado de cliente: nenhuma resposta HTTP', () async {
  final r = await curl([]);                          // sem --cert/--key
  expect(r.exitCode, isNot(0));
  expect(r.stdout, isNot(contains('"status"')));
  expect(r.stdout, contains('HTTP 000'));
});
test('certificado assinado pela CA: 200 e corpo', () async {
  final r = await curl(['--cert', cliCrt, '--key', cliKey]);
  expect(r.exitCode, 0);
  expect(r.stdout, allOf(contains('"status"'), contains('HTTP 200')));
});
test('certificado de outra CA: nenhuma resposta HTTP', () async {
  final r = await curl(['--cert', foraCrt, '--key', foraKey]);
  expect(r.exitCode, isNot(0));
  expect(r.stdout, isNot(contains('"status"')));
});
test('TLS 1.2 com certificado válido continua recusado', () async {
  final r = await curl(['--tlsv1.2', '--tls-max', '1.2', '--cert', cliCrt, '--key', cliKey]);
  expect(r.exitCode, isNot(0));
});
test('rajada de handshakes falhos não derruba o listener (DoS)', () async {
  for (var i = 0; i < 20; i++) {
    await curl([]);                                  // sem certificado
    await curl(['--cert', foraCrt, '--key', foraKey]); // outra CA
  }
  // conexão TCP que manda lixo e fecha no meio do handshake
  final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
  s.add([0x16, 0x03, 0x01, 0x00, 0x05, 0x6c, 0x69, 0x78, 0x6f]);
  await s.flush(); await s.close();
  final r = await curl(['--cert', cliCrt, '--key', cliKey]);
  expect(r.stdout, allOf(contains('"status"'), contains('HTTP 200')));
  expect(wrapper.handshakesRecusados, greaterThanOrEqualTo(40));
  expect(logLines, everyElement(isNot(contains('127.0.0.1'))));
});
test('mtlsApiServerAdapter sem SecurityContext falha fechado', () {
  expect(() => mtlsApiServerAdapter(InternetAddress.loopbackIPv4, 0, null),
      throwsA(isA<StateError>()));
});
test('mtlsApiServerAdapter devolve um Adapter na porta ligada', () async {
  final a = await mtlsApiServerAdapter(InternetAddress.loopbackIPv4, 0, ctx);
  expect(a.port, greaterThan(0));
  await a.close();
});
```

Run: `cd backend/sinalacs_server && dart test test/unit/mtls_api_server_test.dart`
Expected: FALHA — `Target of URI doesn't exist: 'package:sinalacs_server/src/runtime/mtls_api_server.dart'`.

- [ ] **Step 2: Implementar** conforme as Interfaces. Cabeçalho do arquivo (em português) com as três razões de o arquivo existir: o `HttpServer.bindSecure` do SDK não repassa `requireClientCertificate`; `SecureServerSocket` não implementa `ServerSocket`, por isso o embrulho; o `relic_io`/Serverpod ligam o socket sozinhos, por isso o gancho do fork. Citar a medida da PoC: `s_client` imprime `CONNECTION ESTABLISHED` mesmo recusado, então nenhuma sonda deste trecho pode afirmar recusa pelo texto do `s_client`.

- [ ] **Step 3: Rodar**

Run: `cd backend/sinalacs_server && dart test test/unit/mtls_api_server_test.dart`
Expected: PASS (7). Para o caso de DoS o teste constrói o wrapper diretamente (`bindRequiringClientCertificate` recebe um `log` opcional repassado ao wrapper e expõe o wrapper via um segundo retorno ou um `@visibleForTesting`) — decidir a forma mais simples que deixe `handshakesRecusados` e as linhas de log observáveis.

- [ ] **Step 4: Commit**

```bash
git add backend/sinalacs_server/lib/src/runtime/mtls_api_server.dart backend/sinalacs_server/test/unit/mtls_api_server_test.dart
git commit -m "feat(tls): apiServer liga com requireClientCertificate pelo gancho do fork (#90)"
```

### Task 5: Ligar o gancho no `server.dart`

**Files:**
- Modify: `backend/sinalacs_server/lib/server.dart:20-35`

**Interfaces:**
- Consumes: `ApiTlsConfig.fromMap` (Task 3), `mtlsApiServerAdapter` (Task 4), `Serverpod(… apiServerAdapterFactory:)` (Task 1).

- [ ] **Step 1: Teste que falha** — `test/unit/server_wiring_test.dart` lê o texto de `lib/server.dart` (mesmo estilo de `endpoint_auth_posture_test.dart`) e exige que a construção do `Serverpod` contenha `apiServerAdapterFactory: apiTls == null ? null : mtlsApiServerAdapter` **e** `SecurityContextConfig(apiServer: apiTls.toSecurityContext())` no mesmo bloco — para o TLS do apiServer e o `require` do certificado não poderem ser ligados separadamente.

Run: `cd backend/sinalacs_server && dart test test/unit/server_wiring_test.dart`
Expected: FALHA.

- [ ] **Step 2: Implementar** — em `run()`:

```dart
final pod = Serverpod(
  args, Protocol(), Endpoints(),
  securityContextConfig: apiTls == null
      ? null
      : SecurityContextConfig(apiServer: apiTls.toSecurityContext()),
  // #90: com API_TLS_* o apiServer é ligado por nós, exigindo certificado de
  // cliente assinado pela CA de API_TLS_CLIENT_CA_PATH (mtls_api_server.dart).
  apiServerAdapterFactory: apiTls == null ? null : mtlsApiServerAdapter,
);
```

Atualizar o comentário acima (`:21-24`): "TLS 1.3 **mútuo** no apiServer quando API_TLS_* está definido (RNF04, #78 e #90)".

- [ ] **Step 3: Rodar unitários + análise**

Run: `cd backend && dart analyze && cd sinalacs_server && dart test test/unit 2>&1 | tail -2`
Expected: verde.

- [ ] **Step 4: Commit**

```bash
git add backend/sinalacs_server/lib/server.dart backend/sinalacs_server/test/unit/server_wiring_test.dart
git commit -m "feat(tls): Serverpod sobe o apiServer pelo adapter com mTLS quando API_TLS_* existe (#90)"
```

## Checkpoint de revisão (depois da Task 5, antes da Task 6)

O núcleo de segurança está pronto e ainda não há Traefik, Compose nem teste de stack mexidos. Antes de seguir:

- [ ] Rodar `superpowers:requesting-code-review` com um revisor **independente** (subagente novo, sem este contexto) sobre: o patch do fork (`backend/patches/*.patch`), `api_tls_config.dart`, `mtls_api_server.dart`, `server.dart` e os testes das Tasks 2–5. Pedir especificamente: (1) o wrapper `ServerSocket` cobre tudo que o `_HttpServer` usa e não engole erro que **deveria** derrubar o boot (porta ocupada, arquivo de certificado ilegível — esses acontecem no `bind`, antes do stream, e têm de continuar propagando); (2) nenhum caminho sobe em TLS de mão única; (3) o gancho do fork não muda o comportamento padrão; (4) nada do peer vai para log.
- [ ] Tratar os achados pelo `superpowers:receiving-code-review` (verificar antes de aceitar). Só então a Task 6.

### Task 6: `traefik-init` emite as folhas de cliente (Traefik e healthcheck)

**Files:**
- Modify: `infra/docker/traefik/init.sh:150-215` (`emitir_folha` e as chamadas), `:216-230` (permissões)
- Modify: `scripts/qa/dev_key_permissions_test.sh`

**Interfaces:**
- Produces: `emitir_folha <dir> <nome> <cn> <eku> <dias> <san>` — `eku` ∈ {`serverAuth`, `clientAuth`}; `dias` é a validade (`server_days=825` para as duas folhas de servidor e para a do Traefik; `healthcheck_days=90` para a do healthcheck — decisão 4: validade curta, regerada a cada `traefik-init`); `san` vazio omite a linha `subjectAltName` do `.ext` (o OpenSSL recusa SAN vazio); `keyUsage=digitalSignature,keyEncipherment` para servidor e `digitalSignature` para cliente.
- Produces (arquivos): `runtime/certs/traefik-client.crt|key` (CN `sinalacs-traefik`, `clientAuth`, sem SAN; chave **600**, lida só pelo Traefik, que roda como root — medido `uid=0`) e `runtime/backend/healthcheck.crt|key` (CN `sinalacs-healthcheck`, `clientAuth`, 90 dias; chave **644**, lida pelo `curl` do healthcheck como uid 1000). As duas folhas de cliente são **distintas** (chave, CN e validade próprias): a do healthcheck pode ser regerada ou removida sem tocar na do Traefik. A folha `backend` continua `serverAuth` com o SAN de hoje; `server` idem.

- [ ] **Step 1: Teste que falha** — `dev_key_permissions_test.sh` ganha: `runtime/certs/traefik-client.key` em `600`; `runtime/backend/healthcheck.key` em `644`; `openssl x509 -in <folha> -noout -ext extendedKeyUsage` contém `TLS Web Client Authentication` para as duas folhas de cliente e **não** contém para `backend.crt` (Review Focus 3). Mensagens de erro no padrão do arquivo.

Run: `./scripts/qa/dev_key_permissions_test.sh`
Expected: FALHA — `traefik-client.key ausente…`.

- [ ] **Step 2: Implementar no `init.sh`** — generalizar `emitir_folha` (5º parâmetro), chamar quatro vezes (`server`, `backend`, `traefik-client`, `healthcheck`), `chmod 600 "$certs_dir/traefik-client.key"`, `chmod 644 "$backend_dir/healthcheck.crt" "$backend_dir/healthcheck.key"`, e imprimir ao fim `openssl x509 … -ext extendedKeyUsage` das duas folhas de cliente. Atualizar o cabeçalho ("SÃO QUATRO folhas desde a #90…") e o comentário de permissões.

- [ ] **Step 3: Reaplicar o init com a stack de pé, sem apagar a CA**

Run: `docker compose up -d --force-recreate traefik-init && ls -l infra/docker/traefik/runtime/certs/traefik-client.* infra/docker/traefik/runtime/backend/healthcheck.* && ./scripts/qa/dev_key_permissions_test.sh`
Expected: os quatro arquivos existem com os modos acima; `OK — …`. A linha `CA de desenvolvimento do RPC reaproveitada` aparece no log do `traefik-init` (a CA **não** foi regerada: `sync_dev_ca.sh` não precisa rodar).

- [ ] **Step 4: Commit**

```bash
git add infra/docker/traefik/init.sh scripts/qa/dev_key_permissions_test.sh
git commit -m "feat(traefik-init): folhas clientAuth para o Traefik e para o healthcheck, assinadas pela CA do RPC (#90)"
```

### Task 7: Traefik apresenta o certificado; Compose exige a CA e o healthcheck se autentica

**Files:**
- Modify: `infra/docker/traefik/dynamic/tls.yaml` (`http.serversTransports.backend-tls`)
- Modify: `docker-compose.yml` (serviço `serverpod`: `environment`, `healthcheck`, comentários; serviço `traefik`: nada muda nos mounts — `runtime/certs` já está em `/certs`)
- Modify: `scripts/qa/e2e_stack.sh:45-50` (lista de arquivos exigidos depois do `traefik-init`)

**Interfaces:**
- Produces (`tls.yaml`):

```yaml
    backend-tls:
      serverName: sinalacs-serverpod
      rootCAs:
        - /certs/ca.crt
      # #90: o backend exige certificado de cliente; este é o do Traefik,
      # emitido pelo traefik-init com a CA do RPC (clientAuth).
      certificates:
        - certFile: /certs/traefik-client.crt
          keyFile: /certs/traefik-client.key
```

- Produces (`docker-compose.yml`, `serverpod`): `API_TLS_CLIENT_CA_PATH: /app/rpc-certs/ca.crt`; healthcheck `curl -fsS … --cacert /app/rpc-certs/ca.crt --cert /app/rpc-certs/healthcheck.crt --key /app/rpc-certs/healthcheck.key https://localhost:8080/health/check`.

- [ ] **Step 1: Ordem que prova cada metade.** Primeiro só o backend (Step 2): a stack tem de **quebrar** — Traefik sem certificado devolve 5xx em `https://localhost/health/check` e o container fica `unhealthy`. É a prova de que o `require` vale contra o Traefik real. Só então o Traefik e o healthcheck (Step 3) consertam.

- [ ] **Step 2: Backend exige** — `API_TLS_CLIENT_CA_PATH` no `environment`, e recriar o backend com a imagem da Task 2:

Run: `docker compose up -d --build serverpod && sleep 25 && curl -sS --cacert infra/docker/traefik/runtime/certs/ca.crt -o /dev/null -w '%{http_code}\n' https://localhost/health/check; docker inspect -f '{{.State.Health.Status}}' sinalacs-serverpod`
Expected: `502` ou `500` (o Traefik registra `remote error: tls: certificate required` ou `unexpected EOF` em `docker compose logs traefik`) e `unhealthy`/`starting`. **Esse vermelho é o esperado neste passo.** Também: `docker compose logs --tail 5 serverpod` não mostra erro de boot.

- [ ] **Step 3: Traefik apresenta e o healthcheck se autentica** — editar `tls.yaml` e o `healthcheck` do Compose; reescrever os comentários do `docker-compose.yml` que hoje dizem "TLS 1.3 de mão única"/"não exige certificado" (bloco `API_TLS_*`, label `server.port`, healthcheck) e o comentário do `tls.yaml` sobre o Grupo E.

Run: `docker compose up -d --force-recreate traefik serverpod && for _ in $(seq 1 30); do [[ "$(docker inspect -f '{{.State.Health.Status}}' sinalacs-serverpod)" == healthy ]] && break; sleep 2; done; docker inspect -f '{{.State.Health.Status}}' sinalacs-serverpod; curl -sS --cacert infra/docker/traefik/runtime/certs/ca.crt https://localhost/health/check`
Expected: `healthy` e o corpo `{"__className__":"ServiceHealth","status":"ok",…}` — **agora** só possível porque o Traefik apresentou `traefik-client.crt`.

- [ ] **Step 4: O comando-evidência do diagnóstico agora é recusado**

Run: o bloco `docker run … curlimages/curl …` da seção "Diagnóstico e reprodução".
Expected: nenhuma linha JSON; `HTTP 000`; `curl: (35|56) …`.

- [ ] **Step 5: `e2e_stack.sh`** — acrescentar `healthcheck.crt`, `healthcheck.key` (em `runtime/backend/`) e `traefik-client.crt`, `traefik-client.key` (em `runtime/certs/`) ao laço que confere o que o `traefik-init` produziu (`:45-50`), com a mensagem `falta $f depois do traefik-init`.

Run: `bash -n scripts/qa/e2e_stack.sh && grep -c 'healthcheck\.\|traefik-client\.' scripts/qa/e2e_stack.sh`
Expected: sintaxe ok; `4` ocorrências (ou 2 linhas com os pares).

- [ ] **Step 6: Commit**

```bash
git add infra/docker/traefik/dynamic/tls.yaml docker-compose.yml scripts/qa/e2e_stack.sh
git commit -m "feat(traefik): apresenta certificado de cliente ao backend; healthcheck autenticado; backend exige a CA do RPC (#90)"
```

### Task 8: Grupo E do `tls_invariants.sh` — negativo, positivo e as duas estáticas

**Files:**
- Modify: `scripts/qa/tls_invariants.sh:124-185` (Grupo E)

**Interfaces:**
- As sondas E1–E3, E5 e E6 passam a rodar de **fora** do container do backend — de um container efêmero na rede do Compose, que é o processo do modelo de ameaça da issue — com a imagem que a stack já construiu (`sinalacs/server:local` traz o mesmo `curl 8.22` do healthcheck; `--entrypoint curl`, roda como uid 1000). Helper:

```bash
rede="$(docker inspect "$backend_container" -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
# sonda_8080 <args do curl...> — monta runtime/backend em /c (CA + folha do healthcheck) e $tmp em /f
sonda_8080() {
  # --user com o uid do host: no runner do CI o usuário é 1001 e o $tmp (mktemp,
  # 700) não seria legível pelo uid 1000 da imagem; os arquivos de runtime/backend
  # são 644 e continuam legíveis. chmod 644 nos arquivos de $tmp, como o
  # mtls_invariants.sh já faz.
  docker run --rm --network "$rede" --entrypoint curl --user "$(id -u):$(id -g)" \
    -v "$PWD/infra/docker/traefik/runtime/backend:/c:ro" -v "$tmp:/f:ro" \
    sinalacs/server:local -sS -v --max-time 5 -X POST -H 'Content-Type: application/json' -d '{}' \
    -w '\nHTTP %{http_code}\n' "$@" 2>&1
}
```

- Asserções (cada `ok`/`falha` no padrão do arquivo):
  - **E1** texto claro: `sonda_8080 http://sinalacs-serverpod:8080/health/check` sem `"status"`.
  - **E2** (controle positivo, **com** certificado): `--tlsv1.3 --cacert /c/ca.crt --cert /c/healthcheck.crt --key /c/healthcheck.key https://sinalacs-serverpod:8080/health/check` → contém `"status"` **e** `TLSv1.3` **e** `HTTP 200`. Sem E2 verde, E5 e E6 são declarados `falha` com a mensagem "sem controle positivo, a recusa seria verdade por acidente".
  - **E3** TLS 1.2 **com** certificado → sem `"status"` (hoje E3 não apresenta certificado; depois da #90 seria recusado por dois motivos e o teste não distinguiria).
  - **E5 (novo, o caso negativo da issue):** mesma linha de E2 **sem** `--cert/--key` → saída **sem** `"status"`, **sem** nenhuma linha que comece por `< HTTP/` e **com** `HTTP 000`. Mensagem de falha: "a 8080 interna atendeu um cliente sem certificado — o `requireClientCertificate` do `mtls_api_server.dart` ou a `API_TLS_CLIENT_CA_PATH` deixaram de valer".
  - **E6 (novo):** certificado de **outra** CA (gerado em `$tmp` com `openssl`, como `mtls_invariants.sh:28-35` faz, CN `sinalacs-traefik` de propósito) → mesma asserção de E5. Mensagem: "a 8080 interna aceitou certificado de outra CA — o contexto confia em mais do que a CA do RPC".
  - **E4** (estática, estendida): além do que já cobra, `infra/docker/traefik/dynamic/tls.yaml` tem `certFile: /certs/traefik-client.crt` e `keyFile: /certs/traefik-client.key` **dentro** do bloco `backend-tls` (`awk '/backend-tls:/,/^[^ ]/'`), e `docker-compose.yml` tem `API_TLS_CLIENT_CA_PATH` no serviço `serverpod`.
  - **E7 (novo, nos arquivos gerados):** `openssl x509 -in infra/docker/traefik/runtime/certs/traefik-client.crt -noout -ext extendedKeyUsage` contém `TLS Web Client Authentication`, e `openssl verify -CAfile infra/docker/traefik/runtime/certs/ca.crt …/traefik-client.crt` sai 0 — a folha que o Traefik apresenta é um certificado de cliente **desta** CA.
  - **E8 (novo, DoS):** 20 sondas negativas seguidas (10 sem certificado, 10 com o de outra CA) e, **depois**, a sonda positiva de E2 ainda devolve `"status"` + `HTTP 200`, e `docker inspect -f '{{.RestartCount}}' sinalacs-serverpod` continua `0`. Mensagem de falha: "handshakes recusados derrubaram o listener da 8080 — o `handleError` do `SecureServerSocketAsServerSocket` ou o tratamento do SDK deixaram de valer".
  - **E9 (novo, validade da folha do healthcheck):** `openssl x509 -in infra/docker/traefik/runtime/backend/healthcheck.crt -noout -checkend 604800` sai 0 (mais de 7 dias de validade) e a folha difere da do Traefik (`openssl x509 -noout -serial` diferentes). Mensagem de falha: "a folha do healthcheck vence em menos de 7 dias: `docker compose up -d --force-recreate traefik-init` a regera; sem isso o backend fica unhealthy sem dizer por quê".
  - Comentário do grupo: o Grupo A é o controle positivo **do Traefik** (o 200 em `https://localhost/health/check` só existe porque o Traefik apresentou a folha); a seção da PoC sobre o `s_client` e o TLS 1.3 explica por que as negativas usam `curl` e "nenhuma linha HTTP".

- [ ] **Step 1: Escrever o Grupo E novo e rodar contra a stack da Task 7** (os testes nascem depois da implementação da stack porque medem a stack; mas a ordem de escrita do script é antes de considerar a Task 7 "pronta": a Task 7 só fecha com este grupo verde).

Run: `./scripts/qa/tls_invariants.sh`
Expected: `OK — as propriedades do RNF04 conferem.` com E1–E9 `ok` (grupos A–D e F inalterados e verdes).

- [ ] **Step 2: Mutações (cada uma restaurada antes da seguinte)** — (a) comentar `certificates:` do `backend-tls` e `docker compose restart traefik` → Grupo A falha (5xx) e E4 acusa; (b) `API_TLS_CLIENT_CA_PATH` removido do Compose e `up -d serverpod` → o boot falha com a mensagem exata da Task 3 em `docker compose logs serverpod`, o container reinicia (`restart: unless-stopped`) e o Grupo A acusa `não está healthy` — é a prova do fail-fast da decisão 3a; (c) trocar `requireClientCertificate: true` por `false` em `mtls_api_server.dart`, rebuild → **E5 acusa** (é o teste do defeito desta issue; registrar a saída no `PROGRESS.md`); (d) trocar o `handleError` do wrapper por `.map((s) => s)` seguido de um `transform` que relança todo erro como `StateError` → rebuild, rodar E8 e o unitário de DoS: resultado **esperado** é continuarem verdes (a camada do SDK ignora `HandshakeException`) com uma linha `Asynchronous error` do relic no log para o caso do TCP abortado; qualquer vermelho aqui significa que o wrapper é a única proteção — registrar o que se mediu, nos dois casos, no `PROGRESS.md`.

- [ ] **Step 3: Commit**

```bash
git add scripts/qa/tls_invariants.sh
git commit -m "test(tls): Grupo E sonda a 8080 de fora da rede: sem certificado e de outra CA recusados, com certificado 200 (#90)"
```

### Task 9: Regressão — suíte do backend, `e2e.sh` e emulador

**Files:** nenhum novo; registro em `PROGRESS.md` (Task 10).

- [ ] **Step 1: Backend inteiro**

Run: `docker compose --profile test up -d postgres-test && cd backend/sinalacs_server && dart test -j 1 2>&1 | tail -3`
Expected: todos verdes (a contagem sobe pelos testes das Tasks 2–5; anotar o número).

- [ ] **Step 2: Bateria sem aparelho** (sobe a stack do zero, roda `tls_invariants.sh` e os dois `live_check.dart` via Traefik)

Run: `./scripts/qa/e2e.sh --keep 2>&1 | tail -15 && ./scripts/qa/mtls_invariants.sh && ./scripts/qa/dev_key_permissions_test.sh`
Expected: `OK — as propriedades do RNF04 conferem.`, os dois `live_check` ok, `OK — o broker exige certificado…`, `OK — ca.key em 600…`.

- [ ] **Step 3: Emulador — login e RPC real pelo Traefik** (o critério da issue). Subir o `sinalacs_ci36` (binário em `~/Android/Sdk/emulator/emulator`, **com janela**, conforme `PROGRESS.md`), esperar `adb devices` listar `emulator-5554`.

Run: `./scripts/qa/e2e.sh --emulator --keep 2>&1 | tail -20`
Expected: `smoke_test.dart` do paciente (health → login OTP → triagem → alerta, tudo por `https://localhost:8443` → Traefik → backend com mTLS) e do ACS (login institucional → alerta MQTT + ACK → `visits.sync`) verdes. É o login e **várias** chamadas RPC reais passando pelo Traefik.

- [ ] **Step 4: Jornada completa do ACS (opcional, recomendado)**

Run: `./scripts/qa/acs_full_e2e.sh 2>&1 | tail -10`
Expected: verde; se o `flutter test` travar no teardown, `adb kill-server` (nota do `PROGRESS.md` da #88).

- [ ] **Step 5: Voltar à stack de desenvolvimento**

Run: `docker compose up -d && ./scripts/qa/tls_invariants.sh | tail -1`
Expected: `OK — …`.

### Task 10: Documentação, auditoria do PRD, issue upstream e PR

**Files:**
- Modify: `CLAUDE.md` (parágrafo "Already delivered…": "on the Traefik → backend hop (one-way TLS 1.3 … no mTLS, Serverpod cannot request a client certificate — #78)" → "mutual TLS 1.3 … the backend requires a client certificate signed by the RPC dev CA, Serverpod consumed through a pinned fork — #90"; e no "Still missing" tirar o mTLS interno), `backend/CLAUDE.md:39` (texto de `API_TLS_*`: três variáveis, fail-fast, fork, `mtls_api_server.dart`), `spec/stack.md` (**nota-ADR** `> **Traefik → backend com mTLS e fork pinado do Serverpod (2026-10-xx, #90):** …` ao lado da do broker em `:76`, com as três partes exigidas pela decisão 1a: **motivo** — `Server.start` fixo em `_app.serve` no 3.4.13, 4.0.4 e 4.1.0-rc.1, `relic_io` sem `requestClientCertificate`, `HttpServer.bindSecure` sem `requireClientCertificate`, e `requestClientCertificate` sozinho não recusa no handshake; **critério de saída** — remover o `dependency_overrides` e voltar ao pub.dev quando uma versão oficial expuser o gancho ou recusar no handshake por configuração, com o Grupo E como prova de equivalência; **custo de upgrade** — todo upgrade do Serverpod, em especial para 4.x, começa pelo rebase do patch no fork e pela atualização do SHA; reverte explicitamente o "sem fork" da #78), `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (`:96` CRIPTO-TRAEFIK-BACKEND → **entregue** na stack local, evidência Grupo E; `:107` RNF04 segue **parcial** só por Postgres/Gorush/8082/8083/8081; `:231` item 4 atualizado), `PROGRESS.md` (entrada `#90` depois da `#78` em `:575`, com as provas, as quatro mutações da Task 8, o inventário da 8080 e os abertos: produção — no Render o TLS termina na borda e nada disto se aplica; rebase do fork a cada upgrade; rede interna como defesa em profundidade; o backend não loga o CN do certificado de cliente; Traefik roda como root e lê `ca.key` do mesmo mount, pré-existente), `.claude/skills/validacao-e2e/SKILL.md:17` ("the four groups" → os seis grupos, E com mTLS), `backend/DEPLOY.md` (uma frase: as três `API_TLS_*` ficam vazias no Render).

- [ ] **Step 1: Editar os seis documentos.** Depois: `grep -rn -i 'mão única\|requestClientCertificate' --include='*.md' . | grep -v docs/superpowers/plans` só devolve menções históricas (a entrada da #78 no `PROGRESS.md` e a tabela de lacunas, agora com "superado pela #90").

Run: `python3 -I scripts/qa/cobertura_prd.py --final && ./scripts/qa/check_documentation_links.sh`
Expected: `ok` nos dois (a linha CRIPTO-TRAEFIK-BACKEND com status em negrito e evidência na coluna certa — ver `PROGRESS.md:1738` para o formato que o script exige).

- [ ] **Step 2: Issue upstream** (decisão 2, aprovada). Título: `Allow supplying the API server's relic Adapter (needed for requireClientCertificate / mTLS)`. Corpo, em inglês: contexto (reverse proxy que precisa autenticar-se com certificado de cliente; `Server.start` chama `_app.serve` fixo — citar `main` e 3.4.13; `relic_io.bindHttpServer` não expõe `requestClientCertificate`; `HttpServer.bindSecure` do SDK não expõe `requireClientCertificate`); a **evidência** de que `requestClientCertificate: true` sozinho **não** recusa no handshake — colar a medida da PoC: handshake completo, `request.certificate == null`, recusa só na aplicação (401), enquanto `SecureServerSocket.bind(requireClientCertificate: true)` + `HttpServer.listenOn` recusa antes de qualquer byte HTTP — e dizer explicitamente que por isso uma flag `requestClientCertificate` em `SecurityContextConfig` **não** resolveria o caso; a proposta (link para o branch `upstream/api-server-adapter` contra o `main`: `apiServerAdapterFactory`, ~15 linhas, sem mudar o padrão), e a alternativa (`requireClientCertificate` plumbado por `relic_io` até o `SecureServerSocket`). Oferecer o PR a partir do branch; abri-lo como draft **só** se os mantenedores responderem que aceitam a direção (uma ação externa a mais; perguntar ao dono antes).

```bash
gh issue create --repo serverpod/serverpod --title '…' --body-file /tmp/claude-1000/-home-rock-Documents-Dev-APPs-SinalACS/cab90aba-7955-4af2-a40f-8109919254cc/scratchpad/upstream-issue.md
gh issue comment 90 --body 'Issue upstream: <link>. Fork pinado: hbgit/serverpod@<SHA> (backend/patches/README.md).'
```

Pôr o link no `PROGRESS.md` e em `backend/patches/README.md`.

- [ ] **Step 3: Commit da documentação**

```bash
git add CLAUDE.md backend/CLAUDE.md spec/stack.md docs/auditoria-prd/2026-10-15-lacunas-prd.md PROGRESS.md .claude/skills/validacao-e2e/SKILL.md backend/DEPLOY.md backend/patches/README.md
git commit -m "docs: mTLS Traefik ↔ backend entregue na stack local; fork pinado do Serverpod e issue upstream registrados (#90)"
```

- [ ] **Step 4: PR para `develop`** (branch `feat/issue-90-mtls-traefik-backend`, criado de `develop` antes da Task 1). Corpo: o comando-evidência antes/depois, a tabela de critérios abaixo, as mutações da Task 8, a decisão do fork com link para `backend/patches/README.md` e a issue upstream. Os 8 checks obrigatórios (`./scripts/qa/ci_invariants.sh --checks-obrigatorios`) têm de passar — atenção ao `backend-docker-build` (Dockerfile novo) e ao `serverpod-backend` (`dart pub get` com dependência `git`).

## Critérios de aceite da issue → tarefa → prova

| Critério (issue #90) | Tarefa | Prova |
|---|---|---|
| O Traefik apresenta um certificado de cliente assinado pela CA de dev do RPC (`serversTransport.certificates`) | Task 6 (emissão), Task 7 (`tls.yaml`) | E4 (estática: `certFile`/`keyFile` no `backend-tls`), E7 (`extendedKeyUsage` clientAuth + `openssl verify` contra a CA), Grupo A (200 via Traefik só possível com a folha), mutação (a) da Task 8 |
| Sem esse certificado, uma conexão à 8080 interna é recusada no handshake | Task 3, 4, 5 (backend exige), Task 7 (`API_TLS_CLIENT_CA_PATH`) | Unitário `sem certificado de cliente: nenhuma resposta HTTP` (Task 4); E5 na stack (Task 8); comando-evidência do diagnóstico passando a `HTTP 000`; mutação (c) |
| O Grupo E ganha o caso negativo e o positivo | Task 8 | E5/E6 (negativos: sem certificado, outra CA) e E2 (positivo com certificado, TLS 1.3, 200) |
| Não enfraquecer `serverName`/`rootCAs` | Restrição global | E4 continua exigindo `backend-tls@file` sem `insecureSkipVerify`; `serverName`/`rootCAs` intocados no diff do `tls.yaml` |
| Regressão: os apps continuam falando com o backend via Traefik | Task 9 | `e2e.sh --keep` (live_check paciente e ACS), `e2e.sh --emulator` (smoke dos dois apps no `emulator-5554`), `acs_full_e2e.sh` |
| Um cliente sem certificado não derruba o listener (o bloqueio não vira DoS) | Task 4 (wrapper com `handleError`), Task 8 | Unitário `rajada de handshakes falhos não derruba o listener`; E8 na stack; mutação (d) medida |
| Fail-fast: cert + chave sem CA não sobe em mão única | Task 3 | Unitário `só duas das três…` com a mensagem exata; mutação (b) no container |
| Cliente Flutter e `sinalacs_client` intocados pelo fork | Task 2 | `git diff --stat -- backend/sinalacs_client apps/*/pubspec.lock` vazio; `grep '^  serverpod:'` sem resultado |
| Fora do escopo intocado (Postgres, Gorush, 8082/8083, 8081) | Restrição global | `git diff develop -- docker-compose.yml` não toca `postgres`, `gorush`, `SERVERPOD_DATABASE_REQUIRE_SSL`, `8081:8080`; RNF04 segue parcial na auditoria por eles |
| Sem chave privada no git | Restrição global | `git status --porcelain infra/docker/traefik/runtime apps/*/assets/certs` vazio; `dev_key_permissions_test.sh` verde |

## Checklist final

- [x] Ponto de decisão respondido pelo dono (itens 1–4, aprovados com condições em 2026-10-27) e registrado no topo deste plano.
- [ ] Checkpoint de revisão independente feito depois da Task 5, achados tratados antes da Task 6.
- [ ] Nota-ADR em `spec/stack.md` com motivo, critério de saída e custo de upgrade do fork.
- [ ] `docker build --no-cache` sem credencial e `backend-docker-build` verdes (fork público).
- [ ] Fork `hbgit/serverpod@<SHA>` existe, patch versionado em `backend/patches/`, `pubspec.lock` só com a entrada `serverpod` alterada.
- [ ] `dart analyze` limpo; `dart test -j 1` do backend verde (contagem anotada no `PROGRESS.md`).
- [ ] `./scripts/qa/tls_invariants.sh` 100 % `ok` (E1–E9), `mtls_invariants.sh` 4/4, `dev_key_permissions_test.sh` ok.
- [ ] Quatro mutações da Task 8 executadas — (a), (b), (c) acusadas; (d) medida — e saídas no `PROGRESS.md`.
- [ ] `e2e.sh --emulator` verde no `emulator-5554`; `acs_full_e2e.sh` verde (ou motivo registrado).
- [ ] Comando-evidência do diagnóstico: `HTTP 200` antes → `HTTP 000` depois, os dois registrados no `PROGRESS.md`.
- [ ] `cobertura_prd.py --final` e `check_documentation_links.sh` ok; CRIPTO-TRAEFIK-BACKEND **entregue (stack local)**; RNF04 **parcial** com a lista dos trechos fora do escopo.
- [ ] Issue upstream aberta e linkada na #90 (se aprovada); `#90` referenciada no `PROGRESS.md`.
- [ ] PR para `develop` com os 8 checks obrigatórios verdes; nenhuma atribuição de IA.
