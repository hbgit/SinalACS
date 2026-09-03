# Deploy do backend — piloto em serviços free-tier

**Este é um caminho de demonstração/piloto gratuito, não um deploy de
produção.** Ele não substitui os requisitos descritos em
[spec/PRD_system.md](../spec/PRD_system.md) e [README.md](../README.md)
(Pulumi, redes privadas, TLS 1.3, ACLs MQTT dinâmicas, autenticação
institucional real, RBAC por microárea, observabilidade e revisão de LGPD).
**Não use este ambiente com dados reais de pacientes.**

## Por que este caminho existe

O backend (Dart puro sobre `dart:io`, sem Serverpod em uso real) pode rodar em
qualquer host que suporte um container Docker sempre ativo com uma conexão
TCP de saída de longa duração (necessária para o MQTT). As mudanças de código
que tornam isso possível em hosts free-tier já estão no repositório:

- `PORT` lido do ambiente (`backend/bin/server.dart`), em vez de fixo em 8080.
- Boot do servidor HTTP desacoplado da conexão MQTT — `/health` responde
  mesmo que o broker esteja indisponível no momento do deploy; a conexão MQTT
  reconecta sozinha com backoff exponencial se cair (útil em hosts que
  hibernam por inatividade).
- Conexão com o PostgreSQL usa SSL por padrão
  (`backend/lib/src/infrastructure/database/postgres_alert_store.dart`) —
  pode ser desligado localmente com `?sslmode=disable` na `DATABASE_URL`.
- `Dockerfile` multi-stage com `dart compile exe` (AOT) sobre uma imagem
  runtime mínima, com `HEALTHCHECK` apontando para `/health`.
- `JWT_SECRET` obrigatório quando `APP_ENV=production` (falha rápida no boot
  em vez de usar um segredo previsível).
- `/v1/auth/development/login` (login sem senha, único mecanismo de auth do
  piloto) fica atrás da flag `ENABLE_DEV_LOGIN` — se não setada, responde 404.

## Serviços recomendados

| Componente | Serviço | Por quê | Fallback |
|---|---|---|---|
| Compute (backend) | [Render](https://render.com) — Free Web Service | Deploy direto do `Dockerfile`, HTTPS automático, healthcheck configurável para `/health`. Hiberna após ~15 min sem tráfego HTTP — a conexão MQTT cai junto e volta sozinha ao acordar (reconexão com backoff já implementada) | [Koyeb](https://koyeb.com) free tier |
| Banco de dados | [Neon](https://neon.tech) — Free tier Postgres | SSL obrigatório (compatível com o código), sem extensões especiais exigidas pelas migrations, `DATABASE_URL` no formato padrão. Autosuspend de compute é transparente no protocolo Postgres | [Supabase](https://supabase.com) free tier (pausa o projeto inteiro após ~1 semana sem uso) |
| Broker MQTT | [HiveMQ Cloud](https://www.hivemq.com/mqtt-cloud-broker/) — Serverless free tier | TLS com CA pública padrão, autenticação usuário/senha compatível com `MQTT_USERNAME`/`MQTT_PASSWORD` já existentes | [EMQX Cloud](https://www.emqx.com/en/cloud) Serverless free tier |

## Passo a passo

### 1. Provisionar o Postgres (Neon)

Criar um projeto no Neon e copiar a connection string (`DATABASE_URL`, já vem
com `sslmode=require`).

### 2. Aplicar as migrations e o seed

O backend não aplica migrations automaticamente no boot — são 3 arquivos SQL
planos, aplicados manualmente (mesmos comandos usados na CI):

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f lib/src/infrastructure/database/migrations/v1.0.0/01_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f lib/src/infrastructure/database/migrations/v1.1.0/01_add_alerts_and_visits.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f lib/src/infrastructure/database/migrations/v1.2.0/01_add_alert_deliveries.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f lib/src/infrastructure/database/seeds/development.sql
```

O seed é obrigatório: o login de desenvolvimento sempre emite os mesmos UUIDs
fixos de paciente/ACS, e `alerts.patient_id` referencia `patients(user_id)` —
sem o seed, `POST /v1/alerts/red` falha com violação de chave estrangeira.

### 3. Provisionar o broker MQTT (HiveMQ Cloud)

Criar um cluster serverless gratuito, um usuário/senha, e anotar o host
(formato `host:8883`).

### 4. Criar o serviço no Render

Apontar um Web Service para este repositório, `backend/Dockerfile` como
Dockerfile. Configurar como variáveis de ambiente secretas (nunca commitadas):

| Variável | Valor |
|---|---|
| `DATABASE_URL` | connection string do Neon (já com `sslmode=require`) |
| `MQTT_BROKER` | `host:8883` do HiveMQ Cloud |
| `MQTT_USERNAME` / `MQTT_PASSWORD` | credenciais criadas no HiveMQ Cloud |
| `MQTT_USE_TLS` | `true` |
| `JWT_SECRET` | gerado com `openssl rand -hex 32` — nunca usar o fallback de dev |
| `APP_ENV` | `production` |
| `ENABLE_DEV_LOGIN` | `true` (decisão consciente — é o único mecanismo de auth do piloto) |

Não setar `MQTT_CA_CERT_PATH` — o HiveMQ Cloud usa certificado de CA pública,
e o cliente MQTT já confia nas CAs padrão do sistema quando essa variável não
é definida. `PORT` é injetado automaticamente pelo Render.

### 5. Validar

```bash
curl https://<seu-app>.onrender.com/health
# {"status":"ok","mqtt_connected":true,"db_connected":true}
```

Em seguida, repetir o fluxo de login + alerta vermelho + ACK descrito em
`backend/test/red_alert_http_integration_test.dart`, agora contra a URL
pública.

## Limitações conhecidas deste piloto

- Render free hiberna após inatividade — o primeiro request após acordar tem
  latência alta (cold start); considere um ping externo periódico em
  `/health` durante janelas de demonstração.
- Sem pool de conexões PostgreSQL — uma única conexão é aberta no boot; picos
  de tráfego concorrente não são um cenário suportado neste estágio.
- Sem ACL dinâmica por microárea no MQTT — o modelo de autenticação do
  broker gerenciado free-tier é usuário/senha único, mesma limitação já
  presente no Mosquitto local (`infra/docker/mosquitto/aclfile`).
- Dev-login continua sendo a única forma de autenticação — qualquer pessoa
  com a URL pode se autenticar como paciente ou ACS. Não é adequado para uso
  com dados reais.
