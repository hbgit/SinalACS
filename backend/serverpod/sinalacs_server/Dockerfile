# Build a partir da raiz do workspace:
#   docker build -f sinalacs_server/Dockerfile backend/serverpod

# Estágio de build
FROM dart:3.8.0 AS build

# Workspace mínimo, preservando as versões travadas do pubspec.lock.
WORKDIR /app
COPY pubspec.lock .
COPY sinalacs_server sinalacs_server
RUN printf '%s\n' \
  'name: _' \
  'environment:' \
  '  sdk: ^3.8.0' \
  'workspace:' \
  '  - sinalacs_server' \
  > pubspec.yaml
RUN dart pub get

# Compila o executável AOT.
WORKDIR /app/sinalacs_server
RUN dart compile exe bin/main.dart -o bin/server

# Fallback para diretórios possivelmente ausentes.
RUN mkdir -p config web migrations

# Estágio final
FROM alpine:latest
WORKDIR /app

# curl é necessário para o HEALTHCHECK, que hosts free-tier usam para acordar o
# serviço; ca-certificates para o TLS do broker e do Postgres gerenciado.
RUN apk add --no-cache curl ca-certificates \
    && adduser -D -h /app app

ENV runmode=production
ENV serverid=default
ENV logging=normal
ENV role=monolith

COPY --from=build /runtime/ /
COPY --from=build /app/sinalacs_server/bin/server server
COPY --from=build /app/sinalacs_server/config/ config/
COPY --from=build /app/sinalacs_server/web/ web/
COPY --from=build /app/sinalacs_server/migrations/ migrations/

# Necessário para o filtro de log de endpoints no Insights.
COPY --from=build /app/sinalacs_server/lib/src/generated/protocol.yaml lib/src/generated/protocol.yaml

USER app

# 8080 API, 8081 Insights, 8082 web. A porta do Insights colide com o dashboard
# do Traefik no docker-compose deste repositório, e lá é remapeada via
# SERVERPOD_INSIGHTS_SERVER_PORT.
EXPOSE 8080 8081 8082

# O endpoint de saúde agora é RPC (POST /health/check), e não mais GET /health:
# o Serverpod não expõe rotas REST. A forma da resposta foi preservada —
# {status, mqttConnected, dbConnected} — e responde ok assim que o servidor sobe,
# independentemente do estado do broker e do banco.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s \
  CMD curl -fsS -X POST -H 'Content-Type: application/json' -d '{}' \
      http://localhost:${SERVERPOD_API_SERVER_PORT:-8080}/health/check || exit 1

ENTRYPOINT ./server --mode=$runmode --server-id=$serverid --logging=$logging --role=$role
