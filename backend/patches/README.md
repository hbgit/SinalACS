# Patches do backend

## `serverpod-3.4.13-api-server-adapter.patch` — fork pinado do Serverpod (#90)

**Por quê.** O trecho Traefik → backend exige mTLS (RNF04, issue #90): o
backend só aceita quem apresenta certificado de cliente assinado pela CA do
RPC, recusado no handshake. O Serverpod 3.4.13 sobe o apiServer por
`RelicApp.serve` → `relic_io` → `HttpServer.bindSecure`, sem
`requestClientCertificate`; e mesmo esse flag não bastaria, porque o
`HttpServer.bindSecure` do SDK não repassa `requireClientCertificate` — com
`request` sozinho o handshake completa e a aplicação só vê
`request.certificate == null`. A recusa real exige
`SecureServerSocket.bind(requireClientCertificate: true)` embrulhado para
`HttpServer.listenOn`, e isso só é possível se a aplicação ligar o socket.
`Server.start` é fixo em `_app.serve(...)` no 3.4.13, no 4.0.4 e no
4.1.0-rc.1 (medido em 2026-10-27): não há versão para a qual subir.

**O patch.** Um parâmetro nomeado opcional, `apiServerAdapterFactory`, em
`Serverpod(...)`, plumbado até `Server.start`: com ele, o servidor chama
`RelicApp.run(() => factory(address, port, securityContext))` em vez de
`serve`; sem ele, nada muda. Nenhuma semântica de mTLS entra no fork — ela
fica em `sinalacs_server/lib/src/runtime/mtls_api_server.dart`.

**Onde está.** Fork público `hbgit/serverpod`:

- branch `sinalacs/3.4.13-api-server-adapter` — a tag `3.4.13` + este commit;
  é o que `backend/pubspec.yaml` consome por `dependency_overrides`, **pelo
  SHA do commit, nunca pelo nome do branch**;
- branch `upstream/api-server-adapter` — o mesmo patch sobre o `main`
  (linha 4.x), base da proposta upstream:
  https://github.com/serverpod/serverpod/issues/5923.

**Refazer o fork do zero.**

```bash
git clone --branch 3.4.13 https://github.com/serverpod/serverpod.git
cd serverpod && git switch -c sinalacs/3.4.13-api-server-adapter
git am <caminho-deste-repo>/backend/patches/serverpod-3.4.13-api-server-adapter.patch
cd packages/serverpod && dart pub get && dart analyze && dart test test/server test/util test/endpoint
```

**Ao subir o Serverpod.** Primeiro rebase do patch no fork (para 4.x a
base é o branch `upstream/api-server-adapter`, que já resolve o conflito de
`_port` → `port`), depois o SHA novo no `dependency_overrides`, depois o
resto. O build Docker busca o fork **anônimo** (repositório público; o
estágio de build não tem credencial) — ver `sinalacs_server/Dockerfile`.

**Critério de saída.** No dia em que uma versão oficial expuser este gancho
ou recusar no handshake por configuração, remover o `dependency_overrides`
e este diretório; o Grupo E de `scripts/qa/tls_invariants.sh` é a prova de
equivalência.
