# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

SinalACS is a platform that prioritizes Primary Health Care visits in Brazil by turning structured clinical signals into a risk-ranked work queue for the Community Health Agent (ACS). Project documentation, code comments, and UI copy are in Portuguese — match that language for anything user-facing or spec-related. Current state: functional prototype, validated locally via Docker Compose; not production-ready (no real institutional auth, no mTLS on the broker, no production deploy).

Two core flows:
- **Paciente (patient)**: simple auth, urgency alert, structured triage, request status tracking.
- **ACS**: dynamic prioritization, territorialization (micro-area), offline visit registration, micro-area follow-up.

## Required reading before implementing features

Read these before making product/architecture decisions — when project docs conflict with generic conventions, the project docs win:
- [spec/PRD_system.md](spec/PRD_system.md) — requirements, JTBD, invariants, metrics.
- [spec/stack.md](spec/stack.md) — stack/infra architecture decisions.
- [spec/ui_design.md](spec/ui_design.md) — visual language and UX behavior.
- [spec/lgpd_design.md](spec/lgpd_design.md) — privacy/LGPD design.
- [AGENTS.md](AGENTS.md) — full agent working rules (Portuguese), summarized below.

## Business/security invariants (do not violate)

- An ACS's micro-area restricts their data access to that territory only.
- Risk classification (triage) must be deterministic — never alterable by manual intervention in the triage flow itself.
- Red alerts must never be silently dropped.
- Health data must follow LGPD privacy rules; never put real patient data in tests, logs, screenshots, or dev config.

## Commands

### Local stack (Postgres + Mosquitto + backend + Traefik)
```bash
docker compose up --build
docker compose down
```
Services: Traefik `http://localhost`, Traefik dashboard `http://localhost:8081` (dev only, insecure), backend `http://localhost:8080`, Postgres `localhost:5432`, Mosquitto MQTT over TLS `localhost:8883` (the only port the broker exposes — anonymous 1883 and WebSockets 9001 are not published). The `database-seed` service applies the dev seed once the server is healthy.

### Backend (Serverpod 3.4.13 — Dart workspace)
`backend/` is a Dart workspace with two packages: `sinalacs_server` (the Serverpod server) and `sinalacs_client` (the generated, typed Dart client — published but not yet consumed by the Flutter apps).
```bash
cd backend
dart pub get
dart analyze
cd sinalacs_server
dart test                                          # 25 tests: 16 unit + 9 integration
dart test test/unit                                # hermetic only, no database needed
dart test test/unit/red_alert_service_test.dart    # single test file
```
Integration tests use Serverpod's `withServerpod` harness, which needs the test database from `sinalacs_server/config/test.yaml` — Postgres on `localhost:9090`, database `sinalacs_test`, user `postgres`, password from the `test:` block of `config/passwords.yaml` (gitignored). The harness applies migrations itself and rolls the database back after each case, so there is **no** manual schema or seed step.

After changing any `.spy.yaml` model or adding an endpoint, regenerate and create a migration (from `backend/sinalacs_server`):
```bash
dart pub global activate serverpod_cli   # once
serverpod generate
serverpod create-migration
```

Run the server directly: `dart run backend/sinalacs_server/bin/main.dart`. Serverpod reads `config/*.yaml` plus `config/passwords.yaml`, and every setting can be overridden by environment variable: `SERVERPOD_DATABASE_HOST`/`_PORT`/`_NAME`/`_USER`/`_PASSWORD`/`_REQUIRE_SSL`, `SERVERPOD_APPLY_MIGRATIONS` (applies migrations at boot — this is what replaced the manual `psql` steps), `SERVERPOD_REDIS_ENABLED` (Redis is optional and off), and `SERVERPOD_INSIGHTS_SERVER_PORT` (remapped to 8083 in `docker-compose.yml`, because Serverpod's default 8081 is the Traefik dashboard here).

MQTT is not part of Serverpod and keeps its own env vars, read by `AppConfig.fromEnvironment()` in `backend/sinalacs_server/lib/src/config/app_config.dart`: `MQTT_BROKER`/`MQTT_USERNAME`/`MQTT_PASSWORD`/`MQTT_USE_TLS`/`MQTT_CA_CERT_PATH`, plus `JWT_SECRET`, `APP_ENV` (when `production`, boot fails fast if `JWT_SECRET` is missing) and `ENABLE_DEV_LOGIN` (default `false` — gates `auth.developmentLogin`, which fails as if the route did not exist when off).

The dev seed (`sinalacs_server/lib/src/infrastructure/database/seeds/development.sql`) is not optional for a running stack: `auth.developmentLogin` issues tokens for fixed UUIDs, and `alerts.patientId` has a foreign key to `patients` — without the seed, `alerts.createRedAlert` fails with a foreign-key violation. In `docker-compose.yml` the `database-seed` service applies it after the server is healthy.

### Flutter apps (ACS and patient)
```bash
cd apps/acs      # or apps/patient
flutter pub get
flutter analyze
flutter test
flutter test test/login_flow_test.dart   # single test file
flutter run
flutter build apk --debug   # debug APK, validated with compileSdk/targetSdk 36
```
`apps/admin` exists only as a pubspec skeleton (backoffice), no implementation yet.

CI (`.github/workflows/ci.yml`) runs four parallel jobs on push/PR to main: `serverpod-backend` (spins up the Postgres the test harness expects on port 9090, then `dart analyze` and the full 25-test suite), `backend-docker-build` (builds `backend/sinalacs_server/Dockerfile` to catch build breakage before deploy), `patient-app`, `acs-app` (each `flutter analyze && flutter test`, Flutter 3.24.0). Mirror this locally before pushing.

## Architecture

### Backend (`backend/`) — Serverpod workspace
`backend/` is a Dart workspace with `sinalacs_server` (the server) and `sinalacs_client` (the generated typed client). Serverpod was the original stack decision recorded in `spec/stack.md`/`spec/PRD_system.md`; it was not implemented at first — the server was a hand-rolled `dart:io` HttpServer — and was adopted later, replacing it. The Dockerfile (`backend/sinalacs_server/Dockerfile`) is a multi-stage build: `dart compile exe` (AOT) on `dart:3.8.0`, copied into `alpine` with a non-root user, `curl` for the healthcheck, and a `HEALTHCHECK` that does `POST /health/check`.

Layering under `backend/sinalacs_server/lib/src/`:
- `models/` — the schema as `.spy.yaml` model files: 11 tables, 4 enums (`RiskLevel`, `AlertStatus`, `SyncStatus`, `UserRole`), typed exceptions, and endpoint result types. `serverpod generate` turns these into Dart classes shared by server and client; `serverpod create-migration` turns them into SQL under `migrations/`.
- `application/` — use-case services, unchanged by the migration: `alerts/red_alert_service.dart` (red alert creation/ack, idempotency, micro-area/role enforcement), `triage/triage_engine.dart` (deterministic symptom → `RiskLevel`, mirrors Manchester Protocol logic), `sync/sync_fsm.dart` (`idle → localWrite → queued → syncing → {synced|conflict|error}`), `auth/development_auth_service.dart` (dev-only HMAC tokens, **not** real institutional auth).
- `infrastructure/` — `database/orm_alert_store.dart` (implements `AlertStore` over the Serverpod ORM), `database/seeds/development.sql`, `mqtt/mqtt_alert_dispatcher.dart` (implements `AlertPublisher`, publishes/subscribes per micro-area topic, handles ACK payloads).
- `endpoints/` — the RPC surface. `runtime/alert_runtime.dart` holds process-scoped state (MQTT dispatcher, config), because endpoints are constructed per request.
- `config/app_config.dart` — MQTT and auth env vars. Database and server settings come from Serverpod's `config/*.yaml`.

Never hand-edit anything under `lib/src/generated/` or `migrations/` — run `serverpod generate` / `serverpod create-migration` instead.

Key pattern: application services depend on abstract interfaces (`AlertPublisher`, `AlertStore`) defined alongside them in `application/`, implemented by `infrastructure/`. Follow this when adding new use cases — keep `application/` testable without real Postgres/MQTT (see how `test/unit/red_alert_service_test.dart` fakes both).

**Serverpod is RPC, not REST**, so there are no URL routes to match: the generated client calls methods. Endpoints: `health.check` (returns `{status, mqttConnected, dbConnected}`; answers as soon as the server is up, independent of MQTT/DB state), `auth.developmentLogin` (throws `EndpointDisabledException` unless `ENABLE_DEV_LOGIN=true`, preserving the old 404-not-403 semantics), `alerts.createRedAlert` (idempotency key is a method parameter, not a header; throws `AlertDispatchUnavailableException` if the MQTT dispatcher isn't connected), `alerts.acknowledge`, and `triage.evaluate`. Errors are typed exceptions declared in `.spy.yaml` and serialized to the client, replacing HTTP status codes. MQTT connects in the background after boot (non-blocking) with exponential-backoff auto-reconnect, so the server stays responsive even if the broker is unreachable — this matters on free-tier hosts that sleep/hibernate.

### Flutter apps (`apps/acs/`, `apps/patient/`)
Both follow the same skeleton: `lib/main.dart` → `lib/app/app.dart` (+ `*_theme.dart` for the dark, high-legibility, low-noise visual language — see `spec/ui_design.md`) → `lib/core/`. Shared `core/` concerns:
- `database/encrypted_database.dart` — local persistence via `sqflite_sqlcipher`, with an FFI fallback for test/VM environments where SQLCipher isn't available.
- ACS-only, in `apps/acs/lib/core/services/`: `mqtt_secure_client.dart` (TLS/WSS MQTT client, per-micro-area topics, alert + ACK payload parsing with malformed-message rejection), `offline_visit_queue.dart` (offline-first visit queue: pending → sync batch → retry/conflict detection, drives the same state shape as the backend's `SyncFsm`), `network_chaos_simulator.dart` (injects latency/jitter/packet loss/partition for testing offline resilience — see `apps/acs/test/network_chaos_test.dart`).

Neither app is yet wired to the real backend HTTP/MQTT endpoints end-to-end (per `PROGRESS.md`) — triage/risk logic in the patient app and prioritization in the ACS app currently run client-side against local/mock data, mirroring the backend's `triage_engine.dart` logic but not yet calling it over the network.

Color is a clinical signal only in these apps: red/yellow/green map strictly to `RiskLevel`, never used decoratively.

### `spec/`
Product/architecture source of truth (PRD, UX flows, LGPD design, stack decisions) plus static HTML prototypes under `spec/ui_acs/` and `spec/ui_paciente/` — these are the visual reference for building out the real Flutter screens, not live code.

## Working rules for this repo

- Prefer simple, predictable solutions aligned with the stack already chosen (Flutter + Dart backend + Postgres + MQTT) over introducing new frameworks/services not in `spec/stack.md`.
- Keep triage/prioritization logic deterministic and consistent with the Manchester Protocol model referenced in the PRD — do not make risk classification probabilistic or user-overridable.
- When touching sync behavior (backend `SyncFsm` or the ACS `offline_visit_queue.dart`), preserve retry/queue/conflict semantics — offline-first correctness is the primary architectural risk called out in `AGENTS.md`.
- Never commit real patient data, credentials, or the dev Docker Compose secrets into anything beyond local development.
