# Backend — `backend/` (Serverpod)

Carregado ao trabalhar em `backend/`. Regras gerais do repositório ficam no `CLAUDE.md` da raiz.

### Backend (Serverpod 3.4.13 — Dart workspace)
`backend/` is a Dart workspace with two packages: `sinalacs_server` (the Serverpod server) and `sinalacs_client` (the generated, typed Dart client consumed by the patient and ACS Flutter apps).
```bash
cd backend
dart pub get
dart analyze
cd sinalacs_server
dart test                                          # 96 tests: 77 unit + 19 integration
dart test test/unit                                # hermetic only, no database needed
dart test test/unit/red_alert_service_test.dart    # single test file
```
Integration tests use Serverpod's `withServerpod` harness, which needs the test database from `sinalacs_server/config/test.yaml` — Postgres on `localhost:9090`, database `sinalacs_test`, user `postgres`, password from the `test:` block of `config/passwords.yaml` (gitignored). The harness applies migrations itself and rolls the database back after each case, so there is **no** manual schema or seed step.

Start that database with the `test` profile of the root compose:

```bash
docker compose --profile test up -d postgres-test
```

It replaced `backend/sinalacs_server/docker-compose.yaml`, the Serverpod template
compose that carried four passwords in cleartext in git and was referenced by
nothing.

Because `config/passwords.yaml` is gitignored, it is missing from any fresh checkout. Locally `scripts/dev/bootstrap_env.sh` generates it; CI generates it in the job. Without it, Serverpod fails while loading config and calls `exit(1)`; since Dart's `exit()` does not flush stdout, the error message is lost and the whole suite dies with exit code 1 and **zero** output. If you ever see that signature, check this file first. The password in it **must** match `TEST_DATABASE_PASSWORD` in `.env` — the bootstrap script keeps them aligned and warns when they drift.

After changing any `.spy.yaml` model or adding an endpoint, regenerate and create a migration (from `backend/sinalacs_server`):
```bash
dart pub global activate serverpod_cli   # once
serverpod generate
serverpod create-migration
```

Run the server directly: `dart run backend/sinalacs_server/bin/main.dart`. Serverpod reads `config/*.yaml` plus `config/passwords.yaml`, and every setting can be overridden by environment variable: `SERVERPOD_DATABASE_HOST`/`_PORT`/`_NAME`/`_USER`/`_PASSWORD`/`_REQUIRE_SSL`, `SERVERPOD_APPLY_MIGRATIONS` (applies migrations at boot — this is what replaced the manual `psql` steps), `SERVERPOD_REDIS_ENABLED` (Redis is optional and off), and `SERVERPOD_INSIGHTS_SERVER_PORT` (remapped to 8083 in `docker-compose.yml`, because Serverpod's default 8081 is the Traefik dashboard here).

MQTT is not part of Serverpod and keeps its own env vars, read by `AppConfig.fromEnvironment()` in `backend/sinalacs_server/lib/src/config/app_config.dart`: `MQTT_BROKER`/`MQTT_USERNAME`/`MQTT_PASSWORD`/`MQTT_USE_TLS`/`MQTT_CA_CERT_PATH`, plus `JWT_SECRET`, `AUDIT_CHAIN_SECRET`, `APP_ENV` and `ENABLE_DEV_LOGIN` (default `false` — gates `auth.developmentLogin`, which fails as if the route did not exist when off).

Outside `development`, boot fails fast when `JWT_SECRET` or `AUDIT_CHAIN_SECRET` is absent, empty, blank, or equal to its own development fallback (`AppConfig.developmentJwtSecret` / `AppConfig.developmentAuditChainSecret`) — those fallbacks live in versioned code, so they're public, and `JWT_SECRET` signs tokens that carry role and micro-area while `AUDIT_CHAIN_SECRET` keys the `audit_logs` hash chain. The two are deliberately independent secrets — rotating one must not affect the other. The shared validation logic is `_resolveSecret`, covered by `test/unit/app_config_test.dart`; `AppConfig.fromMap()` exists so the rules are testable without touching `Platform.environment`.

The dev seed (`sinalacs_server/lib/src/infrastructure/database/seeds/development.sql`) is not optional for a running stack: `auth.developmentLogin` issues tokens for fixed UUIDs, and `alerts.patientId` has a foreign key to `patients` — without the seed, `alerts.createRedAlert` fails with a foreign-key violation. In `docker-compose.yml` the `database-seed` service applies it after the server is healthy.

The seed runs in **two** steps. `development.sql` is plain SQL over `psql`, so it cannot produce the AES-256-GCM value that `patients.chronicConditionsEncrypted` now holds (Track E, RNF03/INV-04): it inserts the rows with an empty ciphertext, and the `health-data-seed` compose service then runs `bin/seed_health_data.dart`, which reuses `HealthDataCipher` to fill those columns. That service reuses the server image (`sinalacs/server:local`) precisely so both processes derive the key from the same `HEALTH_DATA_ENCRYPTION_KEY`. Pasting a fixed ciphertext into the `.sql` was the alternative, and was rejected because it duplicates the encryption logic outside Dart and breaks silently on any key or algorithm change.

`HEALTH_DATA_ENCRYPTION_KEY` follows the same `_resolveSecret` rule as the other two secrets, with one extra constraint: it **must be 64 hex characters** (`openssl rand -hex 32`), because `HealthDataCipher` decodes it byte by byte into an AES-256 key. `AppConfig.developmentHealthDataEncryptionKey` is therefore a hex literal, not a phrase like the other two development fallbacks — an earlier non-hex literal made the first `encrypt()` in development throw `FormatException`.

The three clinical columns are encrypted at the ORM boundary only: `OrmPatientDirectoryStore`, `OrmTriageSessionStore` and `OrmVisitStore` take a `HealthDataCipher` and translate to/from the plaintext types (`PatientDirectoryEntry`, `TriageSessionRecord`, `VisitRecord`) that `application/` works with. Keep it that way — a service that decides whether to encrypt is the failure mode this design exists to prevent.


### Backend (`backend/`) — Serverpod workspace
`backend/` is a Dart workspace with `sinalacs_server` (the server) and `sinalacs_client` (the generated typed client). Serverpod was the original stack decision recorded in `spec/stack.md`/`spec/PRD_system.md`; it was not implemented at first — the server was a hand-rolled `dart:io` HttpServer — and was adopted later, replacing it. The Dockerfile (`backend/sinalacs_server/Dockerfile`) is a multi-stage build: `dart compile exe` (AOT) on `dart:3.8.0`, copied into `alpine` with a non-root user, `curl` for the healthcheck, and a `HEALTHCHECK` that does `POST /health/check`.

Layering under `backend/sinalacs_server/lib/src/`:
- `models/` — the schema as `.spy.yaml` model files: 14 tables, 4 enums (`RiskLevel`, `AlertStatus`, `SyncStatus`, `UserRole`), typed exceptions, and endpoint result types. `serverpod generate` turns these into Dart classes shared by server and client; `serverpod create-migration` turns them into SQL under `migrations/`.
- `application/` — use-case services, unchanged by the migration: `alerts/red_alert_service.dart` (red alert creation/ack, idempotency, micro-area/role enforcement), `triage/triage_engine.dart` (deterministic symptom → `RiskLevel`, mirrors Manchester Protocol logic), `sync/sync_fsm.dart` (`idle → localWrite → queued → syncing → {synced|conflict|error}`), `auth/development_auth_service.dart` (dev-only HMAC tokens, **not** real institutional auth).
- `infrastructure/` — `database/orm_alert_store.dart` (implements `AlertStore` over the Serverpod ORM), `database/seeds/development.sql`, `mqtt/mqtt_alert_dispatcher.dart` (implements `AlertPublisher`, publishes/subscribes per micro-area topic, handles ACK payloads).
- `endpoints/` — the RPC surface. `runtime/alert_runtime.dart` holds process-scoped state (MQTT dispatcher, config), because endpoints are constructed per request.
- `config/app_config.dart` — MQTT and auth env vars. Database and server settings come from Serverpod's `config/*.yaml`.

Never hand-edit anything under `lib/src/generated/` or `migrations/` — run `serverpod generate` / `serverpod create-migration` instead.

Key pattern: application services depend on abstract interfaces (`AlertPublisher`, `AlertStore`) defined alongside them in `application/`, implemented by `infrastructure/`. Follow this when adding new use cases — keep `application/` testable without real Postgres/MQTT (see how `test/unit/red_alert_service_test.dart` fakes both).

**Serverpod is RPC, not REST**, so there are no URL routes to match: the generated client calls methods. Endpoints: `health.check` (returns `{status, mqttConnected, dbConnected}`; answers as soon as the server is up, independent of MQTT/DB state), `auth.developmentLogin` (throws `EndpointDisabledException` unless `ENABLE_DEV_LOGIN=true`, preserving the old 404-not-403 semantics), `alerts.createRedAlert` (idempotency key is a method parameter, not a header; throws `AlertDispatchUnavailableException` if the MQTT dispatcher isn't connected), `alerts.acknowledge`, `triage.evaluate` (exige `accessToken`; classifica pelo `TriageEngine` determinístico, grava a sessão em `triage_sessions` com o `patientId` vindo do token — nunca de parâmetro, INV-05 — e escreve uma linha `write`/`triage_session` em `audit_logs`; só o papel `patient` é aceito, um ACS recebe `AlertPermissionException`), `visits.sync` (batch upload of visits registered offline by the ACS; deduplicated by the device-generated `localId`, which has a unique index on `visits`, version-checked — a mismatched `version` returns `SyncStatus.conflict` and never overwrites — and territory-checked against the patient's own micro-area, not just the caller's; a malformed identifier, a territory mismatch, or a visit owned by another ACS all return the terminal `SyncStatus.rejected`, distinct from the retryable `SyncStatus.error` used for things like an unknown patient, so the device queue knows which failures are worth retrying), and `patients.listMicroArea` (the ACS's routine-visit patient picker; the micro-area comes from the caller's token, never a parameter, and every call is written to `audit_logs`, whose rows are hash-chained — `AuditChain`/`AuditChainVerifier` in `application/audit/`, keyed by `AUDIT_CHAIN_SECRET` — so tampering with a row is detectable even by someone with direct Postgres write access; `bin/audit_chain_check.dart` verifies the chain on demand). Errors are typed exceptions declared in `.spy.yaml` and serialized to the client, replacing HTTP status codes. MQTT connects in the background after boot (non-blocking) with exponential-backoff auto-reconnect, so the server stays responsive even if the broker is unreachable — this matters on free-tier hosts that sleep/hibernate.

