# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

SinalACS is a platform that prioritizes Primary Health Care visits in Brazil by turning structured clinical signals into a risk-ranked work queue for the Community Health Agent (ACS). Project documentation, code comments, and UI copy are in Portuguese — match that language for anything user-facing or spec-related. Current state: functional prototype, validated locally via Docker Compose; not production-ready. Already delivered: ACS institutional login (RF07, matrícula + senha/Argon2id, credentials kept locally — no integration with a real identity provider), patient passwordless login (RF01, CPF + birth date + OTP), RBAC per micro-area (RNF06), TLS on the RPC via Traefik (RNF04) and on the broker (password + ACL + client certificate on the local stack, `scripts/qa/mtls_invariants.sh`), TOTP MFA for the ACS login, RF08 micro-area persisted in the encrypted local database (72 h, per owner), the ACS refresh token (rotating, idle window 2 h, absolute cap 8 h from the password+TOTP login, family revoked on reuse/other device/inactive account; the app keeps no password and stores the token in the Keystore) with biometric/screen-lock unlock after 30 s in the background and on cold start (an interface gate, not a key binding — proved on the emulator only) and "Sair e encerrar o turno", `FLAG_SECURE` on the ACS window, release builds that refuse the debug key unless explicitly allowed (a release keystore is still to be provisioned) and the UBS call button. Still missing: biometric bound to the Keystore (`setUserAuthenticationRequired`), a refresh token for the patient (OTP stays 1 h), iOS, the Android theme/AppCompat check on API 24–26 and a device-scoped visit queue (see `PROGRESS.md`, section Pendências do ACS), per-device client-certificate provisioning in production (mTLS is delivered only on the local stack), MFA reset by the coordinator (manual today), a backend for the admin backoffice (`apps/admin` still runs on `MockAdminDataSource`), and a production deploy (`backend/DEPLOY.md` is only a free-tier demo path).

Two core flows:
- **Paciente (patient)**: passwordless auth (OTP), urgency alert, structured triage, request status tracking, "Meus Dados" (LGPD).
- **ACS**: dynamic prioritization, territorialization (micro-area), offline visit registration, micro-area follow-up.

A third app, `apps/admin`, is a read-only backoffice (Indicadores, Microáreas, Alertas, Auditoria) on mock data.

Main RPC endpoints (`backend/sinalacs_server/lib/src/endpoints/`): `auth` (`loginInstitutional`, `requestOtp`, `verifyOtp`, `developmentLogin` — the last only with `ENABLE_DEV_LOGIN`), `onboarding`, `triage.evaluate`, `alerts` (`createRedAlert`, `acknowledge`, `statusFor`), `patients` (`listMicroArea`, `myData`, chronic conditions, `updateConsent`, `requestDataDeletion`, `requestDataCorrection`), `visits` (`sync`, `pull`), `health.check`.

`PROGRESS.md` holds milestone status and the open items with owners. `spec/validation_report.md` is stale in both directions (items it lists as open are closed, and its test counts are far below the real ones) — verify against the code before trusting it.

## Required reading before implementing features

Read these before making product/architecture decisions — when project docs conflict with generic conventions, the project docs win:
- [spec/PRD_system.md](spec/PRD_system.md) — requirements, JTBD, invariants, metrics.
- [spec/stack.md](spec/stack.md) — stack/infra architecture decisions.
- [spec/ui_design.md](spec/ui_design.md) — visual language and UX behavior.
- [spec/lgpd_design.md](spec/lgpd_design.md) — privacy/LGPD design.
- [spec/lgpd_data_audit.md](spec/lgpd_data_audit.md) — field-by-field LGPD sensitivity classification for every persisted table (19 domain tables plus Serverpod's own; the count changes with every migration — re-measure it in the `definition.sql` of the latest `backend/sinalacs_server/migrations/*/`, and see L-17 of `spec/validation_report.md` for the drift this line has already accumulated).
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
`JWT_SECRET`, `AUDIT_CHAIN_SECRET` and `HEALTH_DATA_ENCRYPTION_KEY`, writes
`backend/sinalacs_server/config/passwords.yaml` with the same test-database
password, and `chmod 600` on both. It never overwrites existing files without
`--force`, and warns when `pg_data/` predates a rotation: `POSTGRES_PASSWORD`
only takes effect on the volume's first init (old password keeps being
required, backend won't connect), and a rotated `HEALTH_DATA_ENCRYPTION_KEY`
doesn't block boot but makes already-encrypted clinical columns unreadable —
to adopt a new value of either, `docker compose down && rm -rf pg_data/`.

**Updating an existing `pg_data/` to this branch loses dev clinical data
silently.** Migration `20260917191250458` (Track E, RNF03/INV-04) does
`DROP COLUMN` — no backfill — on `patients.chronicConditions`,
`triage_sessions.answers` and `visits.notes`, replacing each with an
encrypted column pair (`*Encrypted`/`*KeyVersion`, see
[backend/CLAUDE.md](backend/CLAUDE.md)). Acceptable at this project's stage
(prototype, no real data anywhere), but a `pg_data/` volume from before this
branch will apply that migration on next boot and drop those three columns'
existing content with no warning. Either `docker compose down && rm -rf
pg_data/` before starting on the new schema, or accept the loss of synthetic
dev data in those three fields.

Rotating the MQTT passwords is enough on its own: `infra/docker/mosquitto/init.sh`
rewrites the broker's `passwordfile` on every boot. It used to only create it
when absent, so a changed password silently did nothing and the broker kept
rejecting the new one.

### Local stack (Postgres + Mosquitto + backend + Traefik)
```bash
docker compose up --build
docker compose down
```
Services: Traefik `http://localhost`, Traefik dashboard `http://localhost:8081` (dev only, insecure), backend `https://localhost/` (HTTPS on :443, terminated by Traefik; cleartext 8080 is no longer published), Postgres `localhost:5432`, Mosquitto MQTT over TLS `localhost:8883` (the only port the broker exposes — anonymous 1883 and WebSockets 9001 are not published). The dev seed runs in four steps: `database-seed` applies `development.sql` once the server is healthy, `health-data-seed` then fills the encrypted clinical columns, `acs-credential-seed` writes the ACS's institutional credential (RF07) and `cpf-hash-seed` writes the patients' CPF hashes (RF01) — the last three because plain SQL cannot produce a value only Dart can compute (AES-256-GCM there, Argon2id and the HMAC-SHA-256 keyed by `CPF_HASH_PEPPER` here; without the hashes, no seeded patient could log in). See [backend/CLAUDE.md](backend/CLAUDE.md).

### Backend, apps e validação E2E

Estes detalhes saíram daqui para carregar sob demanda, em vez de ocupar contexto em toda sessão:

- [backend/CLAUDE.md](backend/CLAUDE.md) — comandos do Serverpod, migrações, segredos, seed e camadas de `lib/src/`. Carrega ao trabalhar em `backend/`.
- [apps/CLAUDE.md](apps/CLAUDE.md) — comandos e arquitetura dos três apps Flutter, incluindo criptografia local, MQTT, fila offline e tokens de contraste WCAG. Carrega ao trabalhar em `apps/`.
- Skill `validacao-e2e` — como validar a conexão real com o backend (`scripts/qa/e2e.sh`, `tool/live_check.dart`, `integration_test` no emulador).

## Architecture

Ver [backend/CLAUDE.md](backend/CLAUDE.md) e [apps/CLAUDE.md](apps/CLAUDE.md) para a arquitetura detalhada de cada camada.

### `spec/`
Product/architecture source of truth (PRD, UX flows, LGPD design, stack decisions) plus static HTML prototypes under `spec/ui_acs/` and `spec/ui_paciente/` — these are the visual reference for building out the real Flutter screens, not live code.

## Working rules for this repo

- Prefer simple, predictable solutions aligned with the stack already chosen (Flutter + Dart backend + Postgres + MQTT) over introducing new frameworks/services not in `spec/stack.md`.
- Keep triage/prioritization logic deterministic and consistent with the Manchester Protocol model referenced in the PRD — do not make risk classification probabilistic or user-overridable.
- When touching sync behavior (backend `SyncFsm` or the ACS `offline_visit_queue.dart`), preserve retry/queue/conflict semantics — offline-first correctness is the primary architectural risk called out in `AGENTS.md`.
- When reusing a clinical fill color (`red`/`accent`/`danger`/`yellow`/`green`) as text or icon color in the Flutter apps, use the `*OnSurface` token and measure contrast against the surface it actually renders on (commonly `Card`/`surfaceRaised`), not the Scaffold background — see the WCAG contrast tokens section in [apps/CLAUDE.md](apps/CLAUDE.md), `spec/ux_accessibility_assessment.md` and each app's `test/contrast_tokens_test.dart`.
- CI lives in [.github/workflows/ci.yml](.github/workflows/ci.yml) and runs on every PR, on pushes to `main`/`develop`, and by hand (`gh workflow run CI --ref <branch>`). 9 jobs: `workflow-lint`, `serverpod-backend`, `backend-docker-build`, `patient-app`, `acs-app`, `admin-app`, `coverage-report`, `android-e2e` (the only one that boots a real emulator against the stack), `admin-android-build`. `workflow-lint` runs actionlint plus `scripts/qa/ci_invariants.sh`, which fails when: this job list drifts from `JOBS_DOCUMENTADOS`; a job leaves the pinned runner (`RUNNER = 'ubuntu-24.04'`, never `ubuntu-latest`); an action drops below its node24 major (`checkout@v7`, `setup-java@v6`, `cache@v6`, `upload-artifact@v7`); the workflow gains a `paths` filter or loses the per-PR/per-SHA `concurrency` group; `android-e2e` loses its `pg_data/` cleanup step; or the AVD cache key does not end in `-<RUNNER>`. `workflow-lint` also runs `scripts/ci/decode_secret_file_test.sh`, `scripts/qa/ci_push_e2e_test.sh` and `scripts/qa/ci_invariants_fcm_test.sh`, and `ci_invariants.sh` additionally fails when the secrets `FCM_CREDENTIALS_BASE64`/`GOOGLE_SERVICES_JSON_BASE64` appear inside a `run:` or in the job-level `env:`, when a decode step comes after the E2E step, when the `if: always()` cleanup step is missing, when the emulator loses `target: google_apis` (Play Services; the action's default image is AOSP and FCM returns no token) or when the AVD cache key does not contain it. `android-e2e` decodes both secrets (service-account key to a temp file + `GOOGLE_APPLICATION_CREDENTIALS`, `google-services.json` into `apps/patient/android/app/`) and, when they exist, ends with `scripts/qa/ci_push_e2e.sh` (real Gorush and FCM); without them (fork PRs) it skips.
- `main` and `develop` are protected: the 8 checks from `./scripts/qa/ci_invariants.sh --checks-obrigatorios` (every job except `android-e2e`, tied to GitHub Actions app 15368) must pass to merge, and `main` also requires a PR; admins can still push directly. `android-e2e` has been green since the fixes of 2026-09-28 but stays informational until it builds a longer history. The script does not read the live protection: after renaming or adding a job, re-apply it (see `CONTRIBUTING.md` › CI e merge) or PRs wait forever for a check that no longer exists. Moving to Ubuntu 26.04 (`ubuntu-latest` migrates on 2026-10-19; a rehearsal ran 9/9 green) is a PR that changes `runs-on`, `RUNNER` and the AVD key suffix together, and needs an actionlint that knows the `ubuntu-26.04` label. History in `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`; known gaps in the guard are issues #19–#21, #23–#24 (#22 fixed — `on:` as a string/list is normalized instead of crashing, and an unrecognized flag exits 2 with a usage message instead of silently exiting 0).
- Never commit real patient data, credentials, or the dev Docker Compose secrets into anything beyond local development.
- Never include AI attributions, "Co-Authored-By", or "Generated with Claude Code" labels in git commits or PR descriptions.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
