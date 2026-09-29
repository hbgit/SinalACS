---
name: validacao-e2e
description: Como validar a conexão real dos apps Flutter com o backend do SinalACS — scripts/qa/e2e.sh, tool/live_check.dart, integration_test no emulador e o que a CI cobre. Use ao rodar validação ponta a ponta, testes em dispositivo, ou ao mexer em scripts/qa.
---

### Validating the real connection to the backend

`flutter test` stays hermetic (it only runs `test/`, where the backend is a fake). Anything that needs the live stack lives outside it:

```bash
./scripts/qa/e2e.sh              # sobe a stack, valida na VM, derruba
./scripts/qa/e2e.sh --keep       # mantém a stack de pé
./scripts/qa/e2e.sh --emulator   # + smoke (integration_test/smoke_test.dart) num emulador já aberto
./scripts/qa/e2e.sh --emulator --full  # + a bateria integration_test inteira dos três apps
```

The script brings up Docker Compose, waits for the healthcheck, applies the seed, runs `scripts/dev/sync_dev_ca.sh` (copies the **two** development CAs — the broker's and the RPC's — into `apps/acs/assets/certs/` and `apps/patient/assets/certs/`, which are gitignored and regenerated), runs `scripts/qa/tls_invariants.sh` (the four groups that measure RNF04/L-08 on the live stack: HTTPS with the dev CA, TLS 1.3 only, no cleartext path to the RPC, and the script-side https host rule), and then runs each app's `tool/live_check.dart`. Those scripts run on the plain Dart VM — no emulator — using the apps' own network code: the patient one covers health/login/triage/alert/idempotency, and the ACS one covers the full cycle including the MQTT/TLS subscription and `visits.sync`. Both tools read the RPC CA from `infra/docker/traefik/runtime/certs/ca.crt` themselves, and neither takes an https host for granted — a missing CA stops the leg with the path in the message instead of reporting "the backend did not answer".

`integration_test/` in each app holds the on-device version, excluded from `flutter test` by construction. Run it against an already-running emulator with `--dart-define=SINALACS_HOST=https://10.0.2.2/` (and, for the ACS, `SINALACS_MQTT_HOST=10.0.2.2` plus `SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD"` — without the password the suite fails in `setUpAll` with the command you need). `scripts/qa/e2e.sh --emulator` already passes all three.

`--emulator` alone runs only `integration_test/smoke_test.dart` in the patient and ACS apps — one test each, chaining what only the device proves (patient: health → login → red triage → idempotent alert over HTTPS with the asset CA; ACS: login → red alert via MQTT/TLS + ACK → visit unreadable in the real SQLCipher file → sync removes it from disk). Every file under `integration_test/` costs a build plus an `adb install`, which dominated the CI job's time, so the rest of the suite (`backend_connection_test.dart`, `red_alert_cycle_test.dart`, `encrypted_storage_test.dart`, `map_flow_test.dart` and the admin's hermetic smoke) runs only with `--full`. Run `--full` by hand before touching network, local crypto, map or admin layout on device — CI no longer covers wrong-key / v1-migration / lost-key SQLCipher cases, the in-app micro-area rejection, the ACK of a missing alert, visit resend idempotency, or the map flow. Retries of `flutter test` happen only when the output contains `Broken pipe` (the known transient `adb install` failure); a real red test fails at once. CI has eight jobs; seven of them never need a live backend, and the eighth — `android-e2e` — is the one that does: it brings the whole stack up inside the runner (`bootstrap_env.sh`, then `e2e.sh --emulator --keep` — smoke only, KVM enabled via udev rule, AVD snapshot and pub/Gradle caches) before running `measure_latency.dart`. Don't write "the CI never needs a backend": that job exists precisely to exercise the real path, which is also why `tls_invariants.sh` runs from inside `e2e.sh` rather than only by hand.

The RPC is **HTTPS on 443** (RNF04/L-08): Traefik terminates TLS with a development certificate, and publishing 8080 in cleartext was REMOVED, not restricted. Anything that still points at `http://…:8080/` does not connect.

Debug builds of all three apps carry `android/app/src/debug/res/xml/network_security_config.xml`, which today declares `cleartextTrafficPermitted="false"` and no exception; release manifests are untouched. Do **not** read that file as the barrier, though: it was measured on the emulator (API 36) that `dart:io` completes a cleartext POST even with the exception removed, so what actually closes the path is the missing port — the app's own host validation (`requireSecureHost` in each `BackendClient`) is the remaining gate on the `--dart-define`.

A CI (`.github/workflows/ci.yml`) precisa de backend em UM job, o `android-e2e`; os outros sete não. O job `admin-android-build` é o único do repositório que executa Gradle: `analyze` e `test` são cegos a um `namespace` inconsistente, AGP/Kotlin incompatíveis, uma `MainActivity` no pacote errado ou um merge de manifesto quebrado. Ele cobre o admin, e não o ACS, porque `apps/acs/android/app/build.gradle.kts` falha de propósito sem `SINALACS_MQTT_PASSWORD`. Espelhe isso localmente antes de dar push.
