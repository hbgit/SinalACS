# Deploy do backend — piloto em serviços free-tier

**Este é um caminho de demonstração/piloto gratuito, não um deploy de
produção.** Ele não substitui os requisitos descritos em
[spec/PRD_system.md](../spec/PRD_system.md) e [README.md](../README.md)
(Pulumi, redes privadas, TLS 1.3, ACLs MQTT dinâmicas, autenticação
institucional real, RBAC por microárea, observabilidade e revisão de LGPD).
**Não use este ambiente com dados reais de pacientes.**

## Por que este caminho existe

O backend é um servidor [Serverpod](https://serverpod.dev) 3.4.13 em Dart, e
roda em qualquer host que suporte um container Docker sempre ativo com uma
conexão TCP de saída de longa duração (necessária para o MQTT). As
características que tornam isso viável em hosts free-tier:

- **O Serverpod aplica as próprias migrations no boot** quando
  `SERVERPOD_APPLY_MIGRATIONS=true`, então não há passo manual de schema.
- **Boot desacoplado do MQTT** — a sonda de saúde responde mesmo com o broker
  indisponível, e a conexão MQTT reconecta sozinha com backoff exponencial se
  cair. Isso importa em hosts que hibernam por inatividade.
- **Redis é opcional** e fica desligado (`SERVERPOD_REDIS_ENABLED=false`), o
  que elimina um serviço do piloto.
- **`Dockerfile` multi-stage** com `dart compile exe` (AOT) sobre `alpine`, com
  usuário não-root e `HEALTHCHECK` que faz `POST /health/check`.
- **`JWT_SECRET` obrigatório quando `APP_ENV=production`** — falha rápida no
  boot em vez de usar um segredo previsível.
- **`auth.developmentLogin`** (acesso sem senha, único mecanismo de auth do
  piloto) fica atrás da flag `ENABLE_DEV_LOGIN`; sem ela, falha como se o
  endpoint não existisse.

> **Serverpod é RPC, não REST.** Não há rotas como `GET /health` ou
> `POST /v1/alerts/red`: o cliente gerado chama métodos, que trafegam como
> `POST /<endpoint>/<método>` com corpo JSON. Isso muda como se valida o
> serviço — ver a seção 5.

## Serviços recomendados

| Componente | Serviço | Por quê | Fallback |
|---|---|---|---|
| Compute (backend) | [Render](https://render.com) — Free Web Service | Deploy direto do `Dockerfile`, HTTPS automático, healthcheck configurável. Hiberna após ~15 min sem tráfego HTTP — a conexão MQTT cai junto e volta sozinha ao acordar | [Koyeb](https://koyeb.com) free tier |
| Banco de dados | [Neon](https://neon.tech) — Free tier Postgres | SSL obrigatório, sem extensões especiais exigidas pelas migrations, autosuspend transparente no protocolo Postgres | [Supabase](https://supabase.com) free tier (pausa o projeto inteiro após ~1 semana sem uso) |
| Broker MQTT | [HiveMQ Cloud](https://www.hivemq.com/mqtt-cloud-broker/) — Serverless free tier | TLS com CA pública padrão, autenticação usuário/senha compatível com `MQTT_USERNAME`/`MQTT_PASSWORD` | [EMQX Cloud](https://www.emqx.com/en/cloud) Serverless free tier |

## Passo a passo

### 1. Provisionar o Postgres (Neon)

Criar um projeto no Neon e anotar host, porta, nome do banco, usuário e senha
**separadamente** — o Serverpod não usa uma `DATABASE_URL` única, e sim as
variáveis `SERVERPOD_DATABASE_*` da tabela abaixo.

### 2. Migrations

**Não há passo manual.** O servidor aplica as migrations de `migrations/` no
boot quando `SERVERPOD_APPLY_MIGRATIONS=true`, e registra o que já aplicou na
tabela `serverpod_migrations`.

### 3. Provisionar o broker MQTT (HiveMQ Cloud)

Criar um cluster serverless gratuito, um usuário/senha, e anotar o host
(formato `host:8883`).

### 4. Criar o serviço no Render

Apontar um Web Service para este repositório, com
`backend/sinalacs_server/Dockerfile` como Dockerfile e **`backend` como
contexto de build** — o build precisa do `pubspec.lock` compartilhado entre
`sinalacs_server` e `sinalacs_client`.

Configurar como variáveis de ambiente secretas (nunca commitadas):

| Variável | Valor |
|---|---|
| `SERVERPOD_DATABASE_HOST` | host do Neon |
| `SERVERPOD_DATABASE_PORT` | `5432` |
| `SERVERPOD_DATABASE_NAME` | nome do banco |
| `SERVERPOD_DATABASE_USER` | usuário do Neon |
| `SERVERPOD_DATABASE_PASSWORD` | senha do Neon |
| `SERVERPOD_DATABASE_REQUIRE_SSL` | `true` |
| `SERVERPOD_APPLY_MIGRATIONS` | `true` |
| `SERVERPOD_REDIS_ENABLED` | `false` |
| `SERVERPOD_API_SERVER_PORT` | a porta que o Render injeta em `PORT` |
| `MQTT_BROKER` | `host:8883` do HiveMQ Cloud |
| `MQTT_USERNAME` / `MQTT_PASSWORD` | credenciais criadas no HiveMQ Cloud |
| `MQTT_USE_TLS` | `true` |
| `JWT_SECRET` | gerado com `openssl rand -hex 32` — nunca usar o fallback de dev |
| `APP_ENV` | `production` |
| `ENABLE_DEV_LOGIN` | `true` (decisão consciente — é o único mecanismo de auth do piloto) |

Não setar `MQTT_CA_CERT_PATH` — o HiveMQ Cloud usa certificado de CA pública, e
o cliente MQTT confia nas CAs padrão do sistema quando essa variável não é
definida.

O Serverpod abre três portas: API (8080), Insights (8081) e web (8082). Num Web
Service do Render só a porta da API fica pública, o que é o desejado — **o
Insights não deve ser exposto**.

### 5. Validar

A sonda de saúde é RPC, então precisa de `POST` com corpo JSON:

```bash
curl -X POST https://<seu-app>.onrender.com/health/check \
  -H 'Content-Type: application/json' -d '{}'
# {"__className__":"ServiceHealth","status":"ok","mqttConnected":true,"dbConnected":true}
```

**O seed não é opcional para um piloto utilizável.** As migrations criam o
schema, mas não inserem dados. O `auth.developmentLogin` emite tokens para
UUIDs fixos, e `alerts.patientId` tem chave estrangeira para `patients` — sem
o seed, `alerts.createRedAlert` falha com violação de FK:

```bash
psql "postgresql://<user>:<senha>@<host>/<banco>?sslmode=require" \
  -v ON_ERROR_STOP=1 \
  -f sinalacs_server/lib/src/infrastructure/database/seeds/development.sql
```

Em seguida, o ciclo completo — login, alerta e confirmação:

```bash
U=https://<seu-app>.onrender.com
H='Content-Type: application/json'

TOKEN=$(curl -s -X POST $U/auth/developmentLogin -H "$H" -d '{"role":"patient"}' \
  | sed 's/.*"accessToken":"\([^"]*\)".*/\1/')

curl -X POST $U/alerts/createRedAlert -H "$H" \
  -d "{\"accessToken\":\"$TOKEN\",\"idempotencyKey\":\"piloto-1\",\"locationHash\":\"hash\"}"
```

Repetir a mesma chamada com a mesma `idempotencyKey` deve devolver o **mesmo**
`alertId`, sem gravar nem publicar de novo. Depois, autenticar como `acs` e
chamar `alerts.acknowledge` com esse `alertId`.

O mesmo ciclo está automatizado em
[`sinalacs_server/test/integration/red_alert_cycle_test.dart`](sinalacs_server/test/integration/red_alert_cycle_test.dart),
que roda contra o harness local.

## Limitações conhecidas deste piloto

- Render free hiberna após inatividade — o primeiro request após acordar tem
  latência alta (cold start); considere um ping externo periódico em
  `/health/check` durante janelas de demonstração.
- Sem ACL dinâmica por microárea no MQTT — o modelo de autenticação do broker
  gerenciado free-tier é usuário/senha único, mesma limitação já presente no
  Mosquitto local (`infra/docker/mosquitto/aclfile`).
- Dev-login continua sendo a única forma de autenticação — qualquer pessoa com
  a URL pode se autenticar como paciente ou ACS. Não é adequado para uso com
  dados reais.
- A publicação MQTT não participa da transação do banco. Se a publicação tiver
  êxito e o commit falhar, o alerta chega ao ACS sem linha no banco, e o ACK
  não encontra o que atualizar. É raro e erra para o lado seguro quanto à
  INV-03 (o alerta não se perde, a auditoria sim); fechar isso por completo
  exigiria outbox pattern.
