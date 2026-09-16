---
name: validacao-e2e
description: Como validar a conexão real dos apps Flutter com o backend do SinalACS — scripts/qa/e2e.sh, tool/live_check.dart, integration_test no emulador e o que a CI cobre. Use ao rodar validação ponta a ponta, testes em dispositivo, ou ao mexer em scripts/qa.
---

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

A CI (`.github/workflows/ci.yml`) nunca precisa de backend. O job `admin-android-build` é o único do repositório que executa Gradle: `analyze` e `test` são cegos a um `namespace` inconsistente, AGP/Kotlin incompatíveis, uma `MainActivity` no pacote errado ou um merge de manifesto quebrado. Ele cobre o admin, e não o ACS, porque `apps/acs/android/app/build.gradle.kts` falha de propósito sem `SINALACS_MQTT_PASSWORD`. Espelhe isso localmente antes de dar push.
