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
- [spec/lgpd_data_audit.md](spec/lgpd_data_audit.md) — field-by-field LGPD sensitivity classification for every persisted table (11 domain tables plus Serverpod's own).
- [spec/ux_accessibility_assessment.md](spec/ux_accessibility_assessment.md) — WCAG 2.2 AA audit (contrast, touch targets, semantics) for the ACS/patient/admin apps; read before touching any color used as text/icon, not just fill.
- [spec/ux_ui_test_plan.md](spec/ux_ui_test_plan.md) — UX/UI test plan derived from `spec/ui_design.md` (visual/interaction behavior, complementary to the accessibility assessment).
- [AGENTS.md](AGENTS.md) — full agent working rules (Portuguese), summarized below.

## Business/security invariants (do not violate)

- An ACS's micro-area restricts their data access to that territory only.
- Risk classification (triage) must be deterministic — never alterable by manual intervention in the triage flow itself.
- Red alerts must never be silently dropped.
- Health data must follow LGPD privacy rules; never put real patient data in tests, logs, screenshots, or dev config.

## Commands

### Configuration — run this first

```bash
./scripts/dev/bootstrap_env.sh      # cria .env e config/passwords.yaml
```

There is no committed `.env`, and the stack will not start without one: every
secret in `docker-compose.yml` is declared as `${VAR:?...}`, so a missing value
fails the Compose interpolation by name instead of falling back to a password
baked into the versioned file. [.env.example](.env.example) is the full
reference for every variable.

The script generates random per-machine values for `POSTGRES_PASSWORD`,
`TEST_DATABASE_PASSWORD`, `MQTT_BACKEND_PASSWORD`, `MQTT_ACS_PASSWORD`,
`JWT_SECRET` and `AUDIT_CHAIN_SECRET`, writes `backend/sinalacs_server/config/passwords.yaml` with the
same test-database password, and `chmod 600` on both. It never overwrites
existing files without `--force`, and warns when `pg_data/` predates a rotation
(`POSTGRES_PASSWORD` only takes effect on the volume's first init — to adopt a
new one, `docker compose down && rm -rf pg_data/`).

Rotating the MQTT passwords is enough on its own: `infra/docker/mosquitto/init.sh`
rewrites the broker's `passwordfile` on every boot. It used to only create it
when absent, so a changed password silently did nothing and the broker kept
rejecting the new one.

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
dart test                                          # 83 tests: 69 unit + 14 integration
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

### Flutter apps (ACS and patient)
```bash
cd apps/acs      # or apps/patient
flutter pub get
flutter analyze
flutter test
flutter test test/login_flow_test.dart   # single test file
flutter run                 # patient only
flutter build apk --debug   # debug APK, validated with compileSdk/targetSdk 36
```
For the ACS app, run `./scripts/dev/run_acs.sh` (or `--build` for the APK) instead of bare `flutter run`: `SINALACS_MQTT_PASSWORD` is a compile-time constant with **no default**, and the broker's password is generated per machine by `bootstrap_env.sh`. The script reads `.env`, runs `sync_dev_ca.sh` (the CA is a gitignored asset the build requires) and passes all four defines via `--dart-define-from-file` (a temp file it creates and deletes, so the password never sits in `flutter`'s argv). `apps/acs/android/app/build.gradle.kts` makes a bare `flutter build apk` **fail** with the right command instead of silently producing an APK that never connects; the escape hatch for a deliberately-passwordless build (e.g. to see the "compiled without the password" banner) is `-Psinalacs.allowMissingMqttPassword=true`.

`apps/admin` (package `sinalacs_admin`) is a real backoffice app now, not a skeleton — see Architecture below. Same commands apply (`cd apps/admin && flutter pub get && flutter analyze && flutter test`); it's the only one of the three with Flutter Web enabled (`flutter build web` works), and since the Android platform was added it also runs on a device: `flutter run -d emulator-5554`, `flutter build apk --debug`, and `flutter test integration_test -d emulator-5554`. Unlike the ACS app there is no wrapper script and no `--dart-define` to remember — the admin has no secrets.

### Validating the real connection to the backend

`flutter test` stays hermetic (it only runs `test/`, where the backend is a fake). Anything that needs the live stack lives outside it:

```bash
./scripts/qa/e2e.sh              # sobe a stack, valida na VM, derruba
./scripts/qa/e2e.sh --keep       # mantém a stack de pé
./scripts/qa/e2e.sh --emulator   # inclui integration_test em um emulador já aberto
```

The script brings up Docker Compose, waits for the healthcheck, applies the seed, runs `scripts/dev/sync_dev_ca.sh` (copies the broker CA into `apps/acs/assets/certs/`, which is gitignored and regenerated), and then runs each app's `tool/live_check.dart`. Those scripts run on the plain Dart VM — no emulator — using the apps' own network code: the patient one covers health/login/triage/alert/idempotency, and the ACS one covers the full cycle including the MQTT/TLS subscription and `visits.sync`.

`integration_test/` in each app holds the on-device version, excluded from `flutter test` by construction. Run it against an already-running emulator with `--dart-define=SINALACS_HOST=http://10.0.2.2:8080/` (and, for the ACS, `SINALACS_MQTT_HOST=10.0.2.2` plus `SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD"` — without the password the suite fails in `setUpAll` with the command you need). `scripts/qa/e2e.sh --emulator` already passes all three. CI's four jobs are unchanged and never need a backend.

Debug builds of all three apps carry `android/app/src/debug/res/xml/network_security_config.xml`, which permits cleartext only to `10.0.2.2` and loopback; release manifests are untouched.

CI (`.github/workflows/ci.yml`) runs six parallel jobs on push/PR to main: `serverpod-backend` (spins up the Postgres the test harness expects on port 9090, then `dart analyze` and the full 25-test suite), `backend-docker-build` (builds `backend/sinalacs_server/Dockerfile` to catch build breakage before deploy), `patient-app`, `acs-app`, `admin-app` (each `flutter analyze && flutter test`, Flutter 3.44.8), and `admin-android-build` (`flutter build apk --debug` with a Gradle cache). That last one is the only job in the repository that executes Gradle at all: `analyze` and `test` are blind to an inconsistent `namespace`, incompatible AGP/Kotlin, a `MainActivity` in the wrong package or a broken manifest merge. It covers the admin rather than the ACS because `apps/acs/android/app/build.gradle.kts` deliberately fails the build without `SINALACS_MQTT_PASSWORD`. Mirror this locally before pushing.

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

**Serverpod is RPC, not REST**, so there are no URL routes to match: the generated client calls methods. Endpoints: `health.check` (returns `{status, mqttConnected, dbConnected}`; answers as soon as the server is up, independent of MQTT/DB state), `auth.developmentLogin` (throws `EndpointDisabledException` unless `ENABLE_DEV_LOGIN=true`, preserving the old 404-not-403 semantics), `alerts.createRedAlert` (idempotency key is a method parameter, not a header; throws `AlertDispatchUnavailableException` if the MQTT dispatcher isn't connected), `alerts.acknowledge`, `triage.evaluate`, `visits.sync` (batch upload of visits registered offline by the ACS; deduplicated by the device-generated `localId`, which has a unique index on `visits`, version-checked — a mismatched `version` returns `SyncStatus.conflict` and never overwrites — and territory-checked against the patient's own micro-area, not just the caller's; a malformed identifier, a territory mismatch, or a visit owned by another ACS all return the terminal `SyncStatus.rejected`, distinct from the retryable `SyncStatus.error` used for things like an unknown patient, so the device queue knows which failures are worth retrying), and `patients.listMicroArea` (the ACS's routine-visit patient picker; the micro-area comes from the caller's token, never a parameter, and every call is written to `audit_logs`, whose rows are hash-chained — `AuditChain`/`AuditChainVerifier` in `application/audit/`, keyed by `AUDIT_CHAIN_SECRET` — so tampering with a row is detectable even by someone with direct Postgres write access; `bin/audit_chain_check.dart` verifies the chain on demand). Errors are typed exceptions declared in `.spy.yaml` and serialized to the client, replacing HTTP status codes. MQTT connects in the background after boot (non-blocking) with exponential-backoff auto-reconnect, so the server stays responsive even if the broker is unreachable — this matters on free-tier hosts that sleep/hibernate.

### Flutter apps (`apps/acs/`, `apps/patient/`)
Both follow the same skeleton: `lib/main.dart` → `lib/app/app.dart` (+ `*_theme.dart` for the dark, high-legibility, low-noise visual language — see `spec/ui_design.md`) → `lib/core/`. Shared `core/` concerns:
- `database/encrypted_database.dart` (ACS only) — local persistence via `sqflite_sqlcipher`. **INV-04 of the PRD says health data is never persisted in plaintext**, so opening outside Android/iOS throws unless the caller passes `allowUnencryptedForTesting: true`. That flag is deliberately embarrassing to type: `grep` for it and you see every place that gave up the guarantee — today, only VM tests. It used to be the *default* behaviour off-mobile, which is why the old test named "deve abrir banco criptografado" proved nothing on Linux CI.
- `security/database_key_store.dart` (ACS only) — the 256-bit key lives in the Android Keystore / iOS Keychain (`flutter_secure_storage`), never in code. **Not** derived from a PIN, though `spec/PRD_system.md` 4.2.3 prescribes PBKDF2-from-PIN: no PIN flow exists in the apps, and the decision plus its reversibility is recorded in `spec/lgpd_design.md` §5.1. `SqlCipherVisitStore` recovers from a lost key (reinstall, backup restore) by discarding the unreadable file instead of leaving the app permanently stuck.
- **Encryption is only actually proven on a device**: `apps/acs/integration_test/encrypted_storage_test.dart` reads the raw database file and asserts it neither starts with `SQLite format 3` nor contains the visit content. `flutter test` cannot prove this — on Linux everything goes through the unencrypted FFI path, which is the trap that produced the original gap.
- ACS-only, in `apps/acs/lib/core/services/`: `mqtt_secure_client.dart` (TCP/TLS MQTT client on 8883 — the broker's only published listener; trusts the dev CA from an asset via `setTrustedCertificatesBytes`, keeps hostname verification on, uses a persistent session with a stable client id so the broker re-delivers alerts that arrived while the device was offline), `alert_feed.dart` (builds the MQTT config from the session and feeds `alert_queue.dart`; classifies failures into `AlertFeedFailure.transient` — a missing password/CA asset or a refused credential is not, an unreachable broker is), `reconnect_schedule.dart` (pure 2s→60s exponential backoff, same scale as the server's `MqttAlertDispatcher`, with no `Timer` of its own so it is testable without a fake clock — used by `AcsHomeShell` in `app.dart` to retry the *first* connection to the broker on its own when the failure is transient, with a "Tentar agora" button on the banner and an immediate retry on returning from the background; a permanent failure, such as a missing password, is not retried. `mqtt_client`'s own `autoReconnect` only takes over *after* a first successful connection — before that there is nothing to reconnect, which is why this existed as a real gap: a device that opened the app without signal used to need a restart to ever receive the alerts the broker was already holding for it with QoS 1), `offline_visit_queue.dart` (offline-first visit queue backed by a `VisitStore` — in production `SqlCipherVisitStore`, so visits survive closing the app; a store failure sets `persistenceFailed` and the queue keeps working in RAM rather than blocking field work, surfaced as its **own** banner (`Key('storage_error')`) alongside — never instead of — the broker one, plus an inline warning on the visit screen; the two used to share one slot through a `??`, so a field outage hid the fact that visits were not being saved — pushed to `visits.sync` through `backend_visit_synchronizer.dart`, wired in production by `visit_queue_factory.dart`; a conflict returns to the queue instead of being discarded, a per-visit retryable `error` also stays pending and is reported with the server's message, a network failure keeps the batch pending, and a per-visit terminal `rejected` leaves the retry queue but stays visible on the device (`rejectedCount`/`rejectedVisits`, `Key('rejected_visits_count')`) with the server's reason until the ACS explicitly discards it (`discardRejected()`, `Key('discard_rejected')`, behind a confirmation dialog) — nothing removes a rejected visit from disk on its own). An `OfflineVisitRecord` carries the patient's **UUID**, never a display label: when the visit comes from an alert the screen builds `Paciente <8 hex>` at render time, `visits.sync` rejects anything that is not a UUID, and the local schema (`offline_visits`, v4) has `patient_id` plus a nullable `rejection_reason`. The backend only ever publishes `riskLevel: 'red'` (emergency, routed to escalation), so a routine visit — the PRD's actual usage pattern, ≥8/ACS/day — cannot start from an alert at all; `patients.listMicroArea` (backend, territorialized by the caller's token, never a client-supplied micro-area) and the picker it feeds in `VisitRegistrationScreen` (`Key('patient_picker')`) exist for that path, showing name and chronic conditions per `spec/lgpd_design.md`'s routine-visit minimization rule — the picked name lives only in memory for the label, never written to `offline_visits` or logged. The red-alert path keeps its own way in too: the escalation screen's "Iniciar rota de visita" (`Key('escalation_visit')`) — the ACS visits after triggering SAMU, not instead of it. `VisitSyncService` also checks that the patient's micro-area matches the ACS's, not just that the ACS is territorialized; a mismatch is the terminal `SyncStatus.rejected` per-visit (never discards the rest of the batch) and writes an `audit_logs` row (`result: denied_territory`) per `spec/lgpd_design.md`'s access-monitoring requirement — the first writer that table ever had. `EncryptedLocalDatabase._upgrade` drops and recreates the table on v1 → v2 — acceptable only because the app had not shipped a release yet; from v3 → v4 onward the migration is additive (`ALTER TABLE ... ADD COLUMN`) and preserves existing rows, which is what any migration after a real release must do. Sync is triggered by hand from the visit screen ("Sincronizar agora" plus pending/conflict counters), not automatically, `network_chaos_simulator.dart` (injects latency/jitter/packet loss/partition for testing offline resilience — see `apps/acs/test/network_chaos_test.dart`).

Topic namespace must agree in three places: the server's `AlertDelivery.topicPrefix`, the broker ACL (`infra/docker/mosquitto/aclfile`), and `alertTopicFor()` in `mqtt_secure_client.dart` — all `sinalacs/v1/microareas/<microAreaId>/alerts`, where `<microAreaId>` is the seed UUID, not `area-12`.

Both apps consume the generated `sinalacs_client` by path dependency and talk to the real backend. The network layer lives in `lib/core/network/` in each app: `backend_config.dart` (host via `--dart-define`, defaulting to `http://10.0.2.2:8080/`, the machine as seen from the Android emulator), `backend_client.dart` (a `PatientBackend`/`AcsBackend` interface plus the real `BackendClient`, which translates the typed backend exceptions into `BackendFailure` messages in Portuguese), `auth_session.dart` (reads the dev token's payload — **without** verifying the signature, which is the server's job — only to learn the micro-area and the 15-minute expiry) and `backend_scope.dart`. The UI depends on the interface, never on the generated `Client`, which is what keeps the widget tests hermetic; the live path is checked by `tool/live_check.dart` in each app and by `integration_test/`.

Risk classification now comes **only** from `triage.evaluate`: the patient app's client-side string-matching rule is gone, and its triage form asks the six symptoms the server's engine actually takes. The ACS dashboard is fed by `AlertQueue`, which receives alerts over MQTT and orders them deterministically by risk and then by age; it rejects alerts from another micro-area and de-duplicates re-deliveries (QoS 1 is at-least-once).

Color is a clinical signal only in these apps: red/yellow/green map strictly to `RiskLevel`, never used decoratively.

**WCAG contrast tokens**: `app/acs_theme.dart`, `app/patient_theme.dart` and `app/admin_theme.dart` each carry a text-safe variant of every clinical fill color — `redOnSurface`/`accentOnSurface` (ACS), `dangerOnSurface`/`accentOnSurface` (patient), `redOnSurface`/`accentOnSurface` (admin). `red`/`accent`/`danger` only clear WCAG 1.4.3's 4.5:1 as a *fill* (e.g. white text on a red button); reused as *text* color on `surfaceRaised`/`Card` — where risk/status text is actually rendered — they drop to ~3:1. `acsOnSurface()`/`adminOnSurface()` (and the patient-app equivalent) convert fill → text color at the single point where a `switch (riskLevel)` used to feed both, instead of at every call site. The admin's `accentOnSurface` (`#818CF8`, indigo-400) is deliberately *not* the ACS's `#60A5FA`: the admin's fill is indigo `#4F46E5`, not the ACS's blue `#2563EB` — the shared rule across apps is "same color, -400 step," not a literal value, and copying the ACS constant would have passed contrast while clashing with the accent-colored border right next to it. `test/contrast_tokens_test.dart` in each app checks the full token×surface matrix by computing relative luminance directly (`test/support/contrast.dart`) rather than by eyeballing a contrast checker against the wrong surface — which is exactly the false positive/negative `spec/ux_accessibility_assessment.md` documents from the original manual audit. The same pass added `minimumSize` (48×52dp, 64×60dp for the SAMU emergency call) per WCAG 2.5.5 and `Semantics(liveRegion: true)` on dynamic status messages (login errors, feed/storage errors, rejected-visit counts) per WCAG 4.1.3.

### Admin app (`apps/admin/`)
Package `sinalacs_admin`, read-only backoffice. Same skeleton as ACS/patient: `lib/main.dart` → `lib/app/app.dart` (+ `admin_theme.dart`) → `lib/core/data/`. Unlike ACS/patient it does not consume `sinalacs_client` yet: `AdminDataSource` (`lib/core/data/admin_data_source.dart`) is an abstract interface whose models (`RiskLevel`, `AlertStatus`, `DashboardIndicators`, `MicroAreaSummary`, `AlertSummary`, `AuditLogEntry`) mirror the backend's `.spy.yaml` models field-for-field, backed today only by `MockAdminDataSource` — swapping in a real implementation over `sinalacs_client` shouldn't require reshaping the screens, the same DI pattern as `PatientBackend`/`AcsBackend`. `AdminHomeShell` exposes four read-only sections: **Indicadores** (risk counters + TMRAV, the PRD's North Star metric), **Microáreas** (ACS↔microarea binding), **Alertas** (filterable by micro-area/status, with filter options sourced from the fetched data itself rather than a hardcoded list — a hardcoded list would silently drop a real micro-area as a selectable option) and **Auditoria** (an `audit_logs` viewer). Every screen touching sensitive data calls `dataSource.recordAccess(actionType: 'view', resourceType: ...)` *before* rendering it, per `spec/PRD_system.md` §4.2.2 (admin access must itself be audited) — the audit log screen audits its own access too, and a failed `recordAccess` blocks the data from rendering rather than failing open. Login is intentionally local-only, **not** wired to `auth.developmentLogin`: the backend's `auth_endpoint.dart` only accepts `role: 'patient'`/`role: 'acs'`, there is no fixed dev user for `admin`, so real auth is out of scope until the backend supports it (see the `LoginScreen` doc comment in `app.dart`). The "ambiente de desenvolvimento" banner is informational, not access control — the actual gate is `devLoginEnabled`, which defaults to `kDebugMode` and disables the login bypass outside debug builds. Layout is desktop-first per `spec/PRD_system.md` §2.1: `NavigationRail` above `AdminBreakpoints.rail`, `NavigationBar` below, same `ThemeData` either way. The breakpoints live in `lib/app/admin_layout.dart` (`rail` 640, `stacked` 480, `counterCardMin` 160) plus `adminHeaderHeight()`, which exists because `PreferredSizeWidget.preferredSize` is a getter with no `BuildContext` — without it the two-line header clips instead of growing under a large system font. Android was added after the web-only phase, and mobile is a complement, never a replacement: below `stacked` the two alert filters stack instead of sharing a row, `_LinhaComSelo` moves a `ListTile`'s `trailing` badge down into the subtitle (Microáreas and Auditoria had the same squeeze), `_InfoRow` stacks label over value, the header's "Acesso auditado" chip becomes an icon that keeps its `Semantics` label, and the counter cards use a computed grid instead of a fixed `width: 160`. `NavigationRail` is `scrollable: true` because a phone in landscape clears the 640 threshold with only ~288dp of height left — it fits by a few pixels at default font size and overflows at 150%. The guard against regressing any of this is that the ten original widget tests still pass **unedited** at 800×600; the new `test/responsive_layout_test.dart`, `text_scale_test.dart`, `alerts_filters_layout_test.dart`, `admin_header_test.dart` and `touch_targets_test.dart` drive `test/support/layout_harness.dart`, whose header documents the three ways an overflow test silently goes blind (checking before paint, never scrolling a `ListView` past the first fold, and `takeException()` consuming one exception per call) — `test/layout_harness_sanity_test.dart` proves the detector still detects. **`apps/admin/integration_test/` is hermetic**, unlike the ACS and patient ones described above: it runs on `MockAdminDataSource`, so `flutter test integration_test -d emulator-5554` needs no `docker compose`, no seed and no `--dart-define`. `apps/admin` is the only one of the three apps with Flutter Web enabled and the only one versioning `pubspec.lock` from the start (the other two adopted that convention later). `docs/telas-admin.md` documents its five screens with real screenshots, mirroring `docs/telas-acs.md`. CI covers it in the `admin-app` job, identical in shape to `acs-app`/`patient-app`.

### `spec/`
Product/architecture source of truth (PRD, UX flows, LGPD design, stack decisions) plus static HTML prototypes under `spec/ui_acs/` and `spec/ui_paciente/` — these are the visual reference for building out the real Flutter screens, not live code.

## Working rules for this repo

- Prefer simple, predictable solutions aligned with the stack already chosen (Flutter + Dart backend + Postgres + MQTT) over introducing new frameworks/services not in `spec/stack.md`.
- Keep triage/prioritization logic deterministic and consistent with the Manchester Protocol model referenced in the PRD — do not make risk classification probabilistic or user-overridable.
- When touching sync behavior (backend `SyncFsm` or the ACS `offline_visit_queue.dart`), preserve retry/queue/conflict semantics — offline-first correctness is the primary architectural risk called out in `AGENTS.md`.
- When reusing a clinical fill color (`red`/`accent`/`danger`/`yellow`/`green`) as text or icon color in the Flutter apps, use the `*OnSurface` token and measure contrast against the surface it actually renders on (commonly `Card`/`surfaceRaised`), not the Scaffold background — see the WCAG contrast tokens note above and `spec/ux_accessibility_assessment.md`.
- Never commit real patient data, credentials, or the dev Docker Compose secrets into anything beyond local development.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
