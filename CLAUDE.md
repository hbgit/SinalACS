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
Services: Traefik `http://localhost`, Traefik dashboard `http://localhost:8081` (dev only, insecure), backend `http://localhost:8080`, Postgres `localhost:5432`, Mosquitto MQTT `localhost:1883` / WS `localhost:9001`.

### Backend (Dart, no framework runtime — plain `dart:io` HTTP server)
```bash
cd backend
dart pub get
dart analyze
dart test
dart test test/red_alert_service_test.dart   # single test file
```
Backend requires the Postgres schema (and seed data) applied before tests/run — migrations live in `backend/lib/src/infrastructure/database/migrations/` and must be applied **in order**, followed by the dev seed:
```bash
psql "$DATABASE_URL" -f backend/lib/src/infrastructure/database/migrations/v1.0.0/01_initial_schema.sql
psql "$DATABASE_URL" -f backend/lib/src/infrastructure/database/migrations/v1.1.0/01_add_alerts_and_visits.sql
psql "$DATABASE_URL" -f backend/lib/src/infrastructure/database/migrations/v1.2.0/01_add_alert_deliveries.sql
psql "$DATABASE_URL" -f backend/lib/src/infrastructure/database/seeds/development.sql
```
The seed is not optional: `red_alert_service.dart` writes alerts against the fixed dev-login UUIDs, and `alerts.patient_id` has a `NOT NULL REFERENCES patients(user_id)` constraint — skipping the seed makes `POST /v1/alerts/red` fail with a foreign-key violation (this was a real CI bug until the seed step was added to `.github/workflows/ci.yml`).

Run the server directly: `dart run backend/bin/server.dart` (needs `AppConfig.fromEnvironment()` env vars — see `backend/lib/src/config/app_config.dart`). Key vars: `DATABASE_URL`, `MQTT_BROKER`/`MQTT_USERNAME`/`MQTT_PASSWORD`/`MQTT_USE_TLS`, `JWT_SECRET`, `PORT` (dynamic port binding, falls back to 8080), `APP_ENV` (`development` by default; when set to `production`, boot fails fast if `JWT_SECRET` is missing instead of using an insecure default), `ENABLE_DEV_LOGIN` (default `false` — gates `/v1/auth/development/login`, returns 404 when unset). See `backend/DEPLOY.md` for a full free-tier pilot deploy runbook (Render + Neon + HiveMQ Cloud).

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

CI (`.github/workflows/ci.yml`) runs four parallel jobs on push/PR to main: `backend` (spins up real Postgres 15 + Mosquitto services, applies all three migrations **and the dev seed**, then `dart analyze && dart test`), `backend-docker-build` (builds `backend/Dockerfile` to catch build breakage before deploy), `patient-app`, `acs-app` (each `flutter analyze && flutter test`, Flutter 3.24.0). Mirror this locally before pushing.

## Architecture

### Backend (`backend/`) — layered, framework-free Dart
The running server (`backend/bin/server.dart`) is a **hand-rolled `dart:io` HttpServer** — no framework, no code generation, manual route matching. `serverpod` was the original stack decision recorded in `spec/stack.md`/`spec/PRD_system.md` but was never actually implemented that way, and the unused `serverpod` package dependency has been removed from `backend/pubspec.yaml`. The Dockerfile (`backend/Dockerfile`) is a multi-stage build — `dart compile exe` (AOT) in a `dart:3.3` build stage, copied into a minimal `debian:bookworm-slim` runtime stage with a non-root user and a `HEALTHCHECK` against `/health`. Layering under `backend/lib/src/`:
- `domain/` — entities (`AlertDelivery`, `AcsEntity`, `PatientEntity`, `TriageSessionEntity`, `VisitEntity`, ...) and enums (`RiskLevel`, `AlertStatus`, `SyncStatus`, `UserRole`). Pure data, no I/O.
- `application/` — use-case services: `alerts/red_alert_service.dart` (red alert creation/ack, idempotency-key dedup, micro-area/role enforcement), `triage/triage_engine.dart` (deterministic symptom → `RiskLevel` mapping, mirrors Manchester Protocol logic), `sync/sync_fsm.dart` (offline-sync finite state machine: `idle → localWrite → queued → syncing → {synced|conflict|error}`), `auth/development_auth_service.dart` (dev-only token issuance, **not** real institutional auth).
- `infrastructure/` — `database/postgres_alert_store.dart` (implements `AlertStore` against Postgres), `database/migrations/vX.Y.Z/*.sql` (ordered, additive schema changes — never edit an already-applied migration, add a new versioned one), `database/seeds/development.sql`, `mqtt/mqtt_alert_dispatcher.dart` (implements `AlertPublisher`, publishes/subscribes per micro-area topic, handles ACK payloads).
- `config/app_config.dart` — env-driven config (DB URL, MQTT broker, JWT secret).

Key pattern: application services depend on abstract interfaces (`AlertPublisher`, `AlertStore`) defined alongside them in `application/`, implemented by `infrastructure/`. Follow this when adding new use cases — keep `application/` testable without real Postgres/MQTT (see how `red_alert_service_test.dart` fakes both).

The HTTP surface in `bin/server.dart` is intentionally minimal and manually routed (`request.uri.path` string/regex matching) — endpoints: `GET /health` (returns `{status, mqtt_connected, db_connected}`; always 200 as soon as the HTTP server is bound, independent of MQTT/DB state), `POST /v1/auth/development/login` (404 unless `ENABLE_DEV_LOGIN=true`), `POST /v1/alerts/red` (idempotency via `Idempotency-Key` header; returns 503 if the MQTT dispatcher isn't connected instead of crashing), `POST /v1/alerts/{id}/ack`. MQTT connects in the background at boot (non-blocking) with exponential-backoff auto-reconnect (`mqtt_alert_dispatcher.dart`), so the server stays responsive even if the broker is temporarily unreachable — see `backend/DEPLOY.md` for why this matters on free-tier hosts that sleep/hibernate.

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
