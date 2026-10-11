# Resultado da verificação — lacunas da fonte a 200% no ACS (2026-10-06)

| Lacuna | Estado | Evidência |
|---|---|---|
| L1: só 360x800 | ABERTO | `text_scale_test.dart` varre o painel só em `Size(360, 800)`; o único 320 dp é `app_lock_gate_test.dart:413` (320x480, só a tela de bloqueio); nenhuma ocorrência de paisagem em `test/` nem `integration_test/` |
| L2: `save_visit` alcançável | ABERTO | `save_visit` aparece em `login_flow_test.dart`, `visit_owner_flow_test.dart`, `device_wipe_test.dart` e `full_journey_e2e.dart`, todos em escala 1.0; `text_scale_test.dart` não o cita |
| L3: rótulo do chip | ABERTO | nenhuma ocorrência de `broker_status` em `test/` nem `integration_test/`; o `Chip` (`app.dart` ~3590) usa `maxLines: 1` com elipse e nenhum `Semantics` próprio |
