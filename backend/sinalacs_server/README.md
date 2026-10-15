# sinalacs_server

Servidor Serverpod do SinalACS: endpoints RPC (`lib/src/endpoints/`), regras de
domínio, migrações (`migrations/`) e ferramentas de operador (`bin/`).

Não suba este servidor sozinho: a stack de desenvolvimento (PostgreSQL,
Mosquitto, Traefik e os seeds) fica na raiz do repositório.

```bash
./scripts/dev/bootstrap_env.sh   # na raiz, uma vez
docker compose up --build        # na raiz
```

Testes:

```bash
dart test             # unitários + integração (Postgres de teste em localhost:9090)
dart test test/unit   # só os herméticos
```

Comandos do Serverpod, migrações, segredos, seeds e camadas de `lib/src/`:
[backend/CLAUDE.md](../CLAUDE.md). Visão geral e configuração:
[README.md](../../README.md).
