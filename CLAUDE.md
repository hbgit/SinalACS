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
Services: Traefik `http://localhost`, Traefik dashboard `http://localhost:8081` (dev only, insecure), backend `http://localhost:8080`, Postgres `localhost:5432`, Mosquitto MQTT over TLS `localhost:8883` (the only port the broker exposes — anonymous 1883 and WebSockets 9001 are not published). The `database-seed` service applies the dev seed once the server is healthy, and `health-data-seed` then fills the encrypted clinical columns (which plain SQL cannot produce) — see [backend/CLAUDE.md](backend/CLAUDE.md).

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
- When reusing a clinical fill color (`red`/`accent`/`danger`/`yellow`/`green`) as text or icon color in the Flutter apps, use the `*OnSurface` token and measure contrast against the surface it actually renders on (commonly `Card`/`surfaceRaised`), not the Scaffold background — see the WCAG contrast tokens note above and `spec/ux_accessibility_assessment.md`.
- Never commit real patient data, credentials, or the dev Docker Compose secrets into anything beyond local development.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
