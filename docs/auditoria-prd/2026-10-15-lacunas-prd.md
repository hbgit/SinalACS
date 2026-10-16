# Lacunas do PRD — auditoria de 2026-10-15

Fonte: `spec/PRD_system.md` no commit `73bcb0f` (branch `docs/auditoria-lacunas-prd`, a partir de `develop` em `92106d1`). Cada linha foi medida no código neste commit;
`PROGRESS.md` serviu de hipótese, não de prova. Conferência: `python3 scripts/qa/cobertura_prd.py --final`.

**Linha de base dos testes:** backend 1355/1355 (`dart test`, com `postgres-test`), ACS 544/544, paciente 259/259, admin 459/459 (`flutter test`), scripts/qa 42 testes Python OK. Nenhuma falha.

**Legenda de status:** `entregue` (código + prova do critério do PRD) · `parcial` (código sem o critério provado)
· `ausente` · `fora-do-mvp` (ausente e listado em v1.5+ no §6.1) · `externo` (falta só ação de terceiro).

Linhas com prefixo `MOD-`, `STRIDE-`, `CRIPTO-`, `SLO-`, `A11Y-`, `DADOS-`, `EVT-` e `MVP-` cobrem itens do PRD sem ID
próprio; o conferidor exige apenas os IDs do PRD.

## Paciente

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| RF01 | Autenticação passwordless (CPF + nascimento + OTP) | **parcial** | Fluxo CPF + nascimento + OTP em `auth.requestOtp`/`verifyOtp`; `passwordless_auth_service_test.dart` passa; e2e real em `scripts/qa/patient_full_e2e.sh` (2026-09-30). Único gateway é `LoggingSmsGateway` (`backend/sinalacs_server/lib/src/application/auth/sms_gateway.dart:36`), que só escreve o código no log em `APP_ENV=development`. | Escolher e integrar provedor de SMS (implementar `SmsGateway`); criar coluna de telefone do paciente (hoje o destino é o CPF, `sms_gateway.dart:12`). |
| RF02 | Onboarding via QR Code | **entregue** | Convite de uso único em `onboarding_endpoint.dart:21` (`generateEnrollmentToken`) e `:38` (`completeEnrollment`); `qr_flutter` no ACS, `mobile_scanner` no paciente (`apps/patient/lib/app/qr_scanner.dart`); `onboarding_service_test.dart` recusa outra microárea; `qr_scanner_test`, `onboarding_flow_test`, `enrollment_qr_test` passam (36 testes, 2026-10-15). |  |
| RF03 | Botão de alerta de urgência (MQTT, GPS) | **entregue** | Botão `panic_button` 208x208 dp (`apps/patient/lib/app/app.dart:1380`); localização por `GeolocatorLocationReader` vira geocélula arredondada + hash antes do envio (`app.dart:1300-1320`); `alerts.createRedAlert` publica via outbox MQTT; ciclo provado em `red_alert_cycle_test.dart` (integração) e entrega p95 212 ms medida por `scripts/qa/measure_latency.dart` (2026-10-16 UTC). |  |
| RF04 | Triagem estruturada (árvore de decisão) | **entregue** | Seis perguntas sim/não em `TriageSymptom` (`apps/patient/lib/app/app.dart:1429`) mapeadas 1:1 para `TriageEngine.evaluate` (`backend/sinalacs_server/lib/src/application/triage/triage_engine.dart`); risco calculado só no servidor. | O §6.1 fala em 3 perguntas e o código usa 6: atualizar o texto do PRD (correção do PRD, não do código). |
| RF05 | Painel de status da solicitação | **parcial** | `alerts.statusFor` + tela de status (`apps/patient/lib/app/app.dart:2518`) mostram Enviado (pending) e Recebido pela equipe (acknowledged); sincronização periódica testada em `patient_app_mvp_test.dart`. | Nenhum código leva o alerta a `resolved` (só existe no enum `alert_status.spy.yaml:8`), então o paciente nunca vê Atendido: falta a ação do ACS de encerrar o atendimento e a transição no backend. |
| RF06 | Lembretes de saúde (notificação local) | **entregue** | `flutter_local_notifications` + `apps/patient/lib/core/reminders/` (agendador e store `sqflite`); testes em `apps/patient/test/reminders/` passam. Sem endpoint por decisão §2.2.1 (§3.1). |  |
| RF18 | Modo escuro nativo | **parcial** | Paciente e ACS seguem o tema do sistema (`ThemeController` com `ThemeMode.system`, `darkTheme:` em `apps/patient/lib/app/app.dart:164` e `apps/acs/lib/app/app.dart:554`), com testes de contraste nos dois temas (`contrast_tokens_test.dart`, `contrast_tokens_light_test.dart`). | O backoffice (`apps/admin/lib/app/admin_theme.dart:48`) só tem tema escuro fixo (`Brightness.dark`), sem tema claro nem `themeMode`. |

## ACS

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| RF07 | Login institucional (matrícula + senha) | **entregue** | `auth.loginInstitutional` (matrícula + senha Argon2id + TOTP), refresh token rotativo preso ao Keystore; `mfa_login_test.dart` passa (2026-10-15); prova no emulador API 36 em `scripts/qa/acs_keystore_bound_e2e.sh`. | Fora do critério do PRD, mas aberto: invalidar a chave com digital nova em API 30+, provar o Keystore em API 24-29, troca de senha pelo próprio ACS. |
| RF08 | Territorialização (cache da microárea) | **entregue** | Cache da microárea por dono com validade de 72 h (`apps/acs/lib/core/services/micro_area_directory.dart:9`, `apps/acs/lib/core/database/micro_area_cache_store.dart`), sobre SQLCipher; `micro_area_cache_store_test.dart` passa. | Tempo de carga (< 30 s do MVP) não medido: ver `MVP-TERRITORIO-30S`. |
| RF09 | Dashboard de priorização dinâmica | **entregue** | `AlertQueue._sort` ordena por risco e, no mesmo risco, pelo mais antigo (`apps/acs/lib/core/services/alert_queue.dart:150`); teste `deve ordenar por risco e, no mesmo risco, pelo mais antigo` (`apps/acs/test/login_flow_test.dart:422`) passa na linha de base. | Paginação de 20 itens do SLO não existe (ver `SLO-DASHBOARD`). |
| RF10 | Mapa interativo | **parcial** | Tela de mapa com `GoogleMap` (`apps/acs/lib/app/app.dart:2501`), geocélula e círculo de incerteza; `map_screen_test.dart` (4 testes) passa; `integration_test/map_flow_test.dart`. Chave por `GOOGLE_MAPS_API_KEY` (`apps/acs/android/app/build.gradle.kts:72`). | Sem clusterização de pinos (PRD §4.1 pede para 50+ pacientes); renderização < 2 s não medida; sem chave de Maps de produção provisionada. |
| RF11 | Registro rápido de visitas offline-first | **entregue** | Fila offline por dono (`apps/acs/lib/core/services/offline_visit_queue.dart`, schema v7) com lote, retry e conflito; `offline_burst_test.dart` (100 visitas, reinício, nenhuma perdida) passa; envio disparado por volta da rede (`connectivityChanges`, `apps/acs/lib/app/app.dart:72`); sync de 100 visitas p95 112 ms (`measure_latency.dart`, 2026-10-16 UTC). | Upload em segundo plano pelo SO (WorkManager fora de `spec/stack.md`); desbloquear fila com token de 7 dias expirado. |
| RF12 | Geofencing (check-in passivo) | **parcial** | `GeofencingScreen` (`apps/acs/lib/app/app.dart:3303`) calcula distância até a geocélula com GPS em primeiro plano; `scripts/qa/acs_gps_e2e.sh` e `integration_test/geofence_gps_e2e.dart`. | Check-in passivo não existe: nenhuma geofence nativa, sem localização em segundo plano, e toda visita sai com `arrivalMethod: manual` (`apps/acs/lib/core/services/backend_visit_synchronizer.dart:67-72`); escolha de plugin e texto de divulgação aguardam revisão de produto/jurídico. |
| RF13 | Escalonamento para SAMU/UBS | **entregue** | Discador do SAMU 192 e da UBS por `url_launcher` sem ligar sozinho (`apps/acs/lib/core/services/emergency_dialer.dart:4-8`); `escalation_dialer_test.dart` e `escalation_ubs_test.dart` passam. | Integração automática com o SAMU é v1.5+ (§6.1). |
| RF14 | Avisos segmentados à comunidade (push) | **parcial** | `notices.sendSegmented` (`backend/sinalacs_server/lib/src/endpoints/notices_endpoint.dart`), registro de token só com consentimento, Gorush; entrega no tray Android via FCM provada no emulador (`scripts/qa/push_e2e.sh`, 2026-09-30) e no CI quando há segredos (`scripts/qa/ci_push_e2e.sh`); `notices_screen_test.dart` passa. | iOS/APNs, prova em aparelho físico e Gorush hospedado fora do Compose local. |
| RF15 | Sincronização bidirecional | **entregue** | Subida `visits.sync` e descida `visits.pull` por cursor (`backend/sinalacs_server/lib/src/endpoints/visits_endpoint.dart`), FSM em `backend/sinalacs_server/lib/src/application/sync/sync_fsm.dart`, consumo no ACS (`visit_pull_service.dart`, `sync_cursor_store.dart`); `visit_pull_service_test.dart` passa. | A coluna Dependência do RF15 no PRD ainda diz ainda não conectado ao cliente: corrigir o PRD. |

## Núcleo, auditoria e backoffice

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| RF16 | Motor de triagem determinístico (Manchester) | **entregue** | `TriageEngine.evaluate` puro, sem IO (`backend/sinalacs_server/lib/src/application/triage/triage_engine.dart`); `triage_engine_test.dart` cobre as 64 combinações dos seis sinais (tabela-verdade completa, o que implica MCDC) mais 8 cenários nomeados; passa (2026-10-15). | O critério de 50 cenários do M1.3 está superado pelas 64 combinações; nenhum relatório de cobertura MCDC por ferramenta (ver M1.3). |
| RF17 | Logs de auditoria e conformidade | **parcial** | `audit_logs` encadeado por HMAC-SHA256; filtros, paginação, selo por linha e verificação global no servidor; exportação CSV só pelo admin, registrada na mesma transação; `audit_chain_test.dart`, `admin_endpoint_audit_chain_test.dart` e `admin_endpoint_audit_export_test.dart` passam; e2e `scripts/qa/admin_auditoria_e2e.sh` (2026-10-13/14). | Cadeia só detecta adulteração: falta trigger/`REVOKE` append-only no banco (nenhum nas migrações); `audit_exports` fora da cadeia; o CSV vai pela área de transferência (`apps/admin/lib/app/audit_log_screen.dart:389`), sem download; revisão do DPO sobre a exportação. |
| RF19 | Escalonamento de alerta vermelho sem confirmação | **entregue** | `admin.escalateAlert` com motivo de conjunto fechado, idempotente (`alreadyEscalated`) e auditado na mesma transação (`backend/sinalacs_server/lib/src/application/admin/alert_escalation_service.dart:134`); prazo `RED_ALERT_ESCALATION_SECONDS` validado de 30 a 3600 s (`app_config.dart:120`, `app_config_test.dart`); `alert_escalation_service_test.dart` (14 testes) e `admin_endpoint_escalation_test.dart` passam; e2e no emulador 2026-10-12. | O PRD ainda marca RF19 como proposto: atualizar a linha. |
| RNF06 | RBAC | **parcial** | `Authorization.require` e `AdminScope` (UBS do coordenador) com recusa auditada; `authorization_test.dart` e `admin_scope_test.dart` passam; endpoints de dados do staff existem desde a #40 (`admin_endpoint.dart`). | Matriz §4.2.2 não cumprida em duas células: o paciente não lê os próprios logs de auditoria (`PatientDataOverview` não traz acessos) e o acesso do coordenador a outra microárea não pede justificativa. O texto do RNF06 no PRD (issue #40 aberta) está velho. |

### Módulos do backoffice (§2.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| MOD-UBS | Gestão de UBS | **ausente** | Nenhum endpoint cria ou edita UBS: `ubs_endpoint.dart` só tem `myContact`; nenhuma tela no `apps/admin/lib/app/`. | Cadastro/edição de UBS no backoffice, incluindo o telefone da UBS usado pelo botão do ACS (hoje só em seed/SQL). |
| MOD-ACS | Gestão de ACS | **entregue** | `admin.createAcs`/`setAcsMicroArea`/`setAcsActive`/`resetAcsPassword`/`resetAcsMfa`/`resetStaffMfa` + `apps/admin/lib/app/admin_accounts.dart`; `admin_endpoint_accounts_test.dart` passa; e2e `scripts/qa/admin_acs_gestao_e2e.sh` (#43). | Criar coordenador e definir o `ubsId` dele pela interface (hoje só seed/SQL). |
| MOD-RELATORIOS | Relatórios | **parcial** | `admin.indicators` devolve contagem por risco, alertas vermelhos e TMRAV (`AdminIndicators.tmravSeconds`), com polling de 30 s; `admin_read_service_test.dart` passa. | Sem recorte por período, sem exportação de relatório e sem as métricas de produto do §1.3 além do TMRAV (sincronização, aderência, visitas por ACS/dia, retenção). |
| MOD-AUDITORIA | Auditoria | **parcial** | Tela `apps/admin/lib/app/audit_log_screen.dart` com filtros, selo e verificação global (#45). | Ver RF17. |
| MOD-CONFIG | Configurações de sistema | **ausente** | Nenhum endpoint nem tela de configurações do sistema; prazos (`RED_ALERT_ESCALATION_SECONDS`, `RETENTION_*_DAYS`) só por variável de ambiente. | Decidir se o admin edita configurações pela interface (§4.2.2 diz R/W); se sim, endpoint auditado + tela. |

## Invariantes e segurança

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| INV-01 | ACS só vê pacientes da própria microárea | **a-verificar** | | |
| INV-02 | Classificação de risco não alterável por humano | **a-verificar** | | |
| INV-03 | Alerta vermelho nunca perdido | **a-verificar** | | |
| INV-04 | Dado de saúde nunca em texto plano | **a-verificar** | | |
| INV-05 | Paciente nunca acessa dado de outro paciente | **a-verificar** | | |

### STRIDE (§4.2.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| STRIDE-S | Spoofing: mensagens falsas no MQTT | **a-verificar** | | |
| STRIDE-T | Tampering: triagem alterada no dispositivo | **a-verificar** | | |
| STRIDE-R | Repudiation: logs append-only assinados | **a-verificar** | | |
| STRIDE-I | Information disclosure: PII no dispositivo | **a-verificar** | | |
| STRIDE-D | Denial of service: inundação MQTT | **a-verificar** | | |
| STRIDE-E | Elevation of privilege: outra microárea | **a-verificar** | | |

### Criptografia (§4.2.3)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| CRIPTO-APP-LOCAL | SQLCipher com chave derivada de PIN/biometria | **a-verificar** | | |
| CRIPTO-APP-CACHE | SQLCipher com chave rotativa | **a-verificar** | | |
| CRIPTO-APP-TRAEFIK | TLS 1.3 app ↔ Traefik | **a-verificar** | | |
| CRIPTO-TRAEFIK-BACKEND | mTLS Traefik ↔ backend | **a-verificar** | | |
| CRIPTO-POSTGRES | Criptografia no PostgreSQL | **a-verificar** | | |
| CRIPTO-AUDITORIA | Cadeia HMAC-SHA256 da auditoria | **a-verificar** | | |

## Não funcionais

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| RNF01 | Latência MQTT < 500 ms (p95) | **a-verificar** | | |
| RNF02 | Sincronização offline > 99,5 % | **a-verificar** | | |
| RNF03 | Criptografia AES-256 em repouso | **a-verificar** | | |
| RNF04 | TLS 1.3 em todas as comunicações | **a-verificar** | | |
| RNF05 | Acessibilidade WCAG 2.1 AA | **a-verificar** | | |

### SLOs (§4.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| SLO-LOGIN | Login < 1 s | **a-verificar** | | |
| SLO-ALERTA | Alerta publish → ACK < 500 ms | **a-verificar** | | |
| SLO-DASHBOARD | Dashboard ACS < 1,5 s, paginação de 20 | **a-verificar** | | |
| SLO-VISITA | Registro offline < 200 ms | **a-verificar** | | |
| SLO-SYNC | Sync de 50 itens < 5 s | **a-verificar** | | |
| SLO-MAPA | Mapa < 2 s, clusterização 50+ | **a-verificar** | | |
| SLO-TRIAGEM | Cálculo da triagem < 50 ms | **a-verificar** | | |

### Acessibilidade (§4.3)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| A11Y-1.4.3 | Contraste de texto ≥ 4,5:1 | **a-verificar** | | |
| A11Y-1.4.11 | Contraste não textual ≥ 3:1 | **a-verificar** | | |
| A11Y-2.5.1 | Alvos de toque ≥ 48 dp | **a-verificar** | | |
| A11Y-2.5.6 | Botão de pânico ≥ 60 dp | **a-verificar** | | |
| A11Y-2.4.7 | Foco visível | **a-verificar** | | |
| A11Y-3.3.2 | Rótulos e Semantics | **a-verificar** | | |
| A11Y-LCP | LCP < 1,5 s | **a-verificar** | | |
| A11Y-FID | FID < 100 ms | **a-verificar** | | |
| A11Y-CLS | CLS < 0,1 | **a-verificar** | | |

## LGPD e dados

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| LGPD-RF01 | Coleta mínima | **a-verificar** | | |
| LGPD-RF02 | Consentimento granular | **a-verificar** | | |
| LGPD-RF07 | Retenção e exclusão (job de expurgo) | **a-verificar** | | |
| LGPD-RF08 | Direitos do titular (Meus Dados + exportação JSON) | **a-verificar** | | |
| LGPD-RF09 | Proteção de dados sensíveis | **a-verificar** | | |
| LGPD-RF11 | Controle de acesso RBAC | **a-verificar** | | |

### Modelo de dados e telemetria (§1.3, §3)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| DADOS-TIMESCALE | Logs e telemetria em TimescaleDB | **a-verificar** | | |
| DADOS-VERSION-OTIMISTA | Versionamento otimista com 409 | **a-verificar** | | |
| DADOS-SYNC-TOKEN | sync_token sequencial | **a-verificar** | | |
| DADOS-MIGRACAO-ROLLBACK | Migrações com rollback | **a-verificar** | | |
| EVT-alert_triggered | Evento alert_triggered | **a-verificar** | | |
| EVT-alert_received_acs | Evento alert_received_acs | **a-verificar** | | |
| EVT-sync_attempt | Evento sync_attempt | **a-verificar** | | |
| EVT-sync_result | Evento sync_result | **a-verificar** | | |
| EVT-visit_registered | Evento visit_registered | **a-verificar** | | |

## Roadmap, hipóteses e riscos

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| M1.1 | Docker Compose local | **a-verificar** | | |
| M1.2 | CI básica | **a-verificar** | | |
| M1.3 | Motor de triagem (MCDC, 50 cenários) | **a-verificar** | | |
| M1.4 | FSM de sincronização | **a-verificar** | | |
| M1.5 | SQLCipher local | **a-verificar** | | |
| M2.1 | App Paciente MVP | **a-verificar** | | |
| M2.2 | App ACS MVP | **a-verificar** | | |
| M2.3 | MQTT com TLS (WSS) | **a-verificar** | | |
| M2.4 | 100 registros sincronizam em < 5 s | **a-verificar** | | |
| M2.5 | Testes de caos (Toxiproxy) | **a-verificar** | | |
| M2.6 | Testes de usabilidade em campo | **a-verificar** | | |
| M3.1 | Deploy em produção (Pulumi) | **a-verificar** | | |
| M3.2 | Monitoramento (OpenTelemetry) | **a-verificar** | | |
| M3.3 | Testes de carga | **a-verificar** | | |
| M3.4 | LGPD compliance | **a-verificar** | | |
| M3.5 | Lançamento v1.0 em UBS piloto | **a-verificar** | | |

### MVP (§6.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| MVP-LOGIN-60S | 10 pacientes logam em < 60 s | **a-verificar** | | |
| MVP-ALERTA-2S | Alerta chega ao ACS em < 2 s | **a-verificar** | | |
| MVP-TRIAGEM-3P | Triagem de 3 perguntas | **a-verificar** | | |
| MVP-STATUS | Enviado → Visualizado → Atendido | **a-verificar** | | |
| MVP-LOGIN-ACS | ACS loga com matrícula e senha | **a-verificar** | | |
| MVP-TERRITORIO-30S | Microárea carrega em < 30 s | **a-verificar** | | |
| MVP-FILA-ORDEM | Lista Vermelho → Amarelo → Verde | **a-verificar** | | |
| MVP-VISITA-OFFLINE | Visita salva local e sincronizada em background | **a-verificar** | | |
| MVP-MQTT-100 | 100 dispositivos, latência < 500 ms | **a-verificar** | | |
| MVP-MIGRACOES-LOGS | Migrações versionadas e logs estruturados | **a-verificar** | | |

### Hipóteses (§1.2)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| H1 | ACS priorizam mais rápido (−40 %) | **a-verificar** | | |
| H2 | ≥ 80 % completam onboarding sem ajuda | **a-verificar** | | |
| H3 | ≥ 90 % de concordância com avaliação médica | **a-verificar** | | |
| H4 | ≥ 99,5 % dos registros offline sincronizam | **a-verificar** | | |

### Riscos (§6.3)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| R1 | Colisão de sincronização | **a-verificar** | | |
| R2 | Falha do MQTT em rede 3G | **a-verificar** | | |
| R3 | Vazamento de PII no dispositivo | **a-verificar** | | |
| R4 | Rejeição do ACS | **a-verificar** | | |
| R5 | Performance do PostgreSQL | **a-verificar** | | |
| R6 | Dependência de SMS gateway | **a-verificar** | | |
| R7 | Mudanças regulatórias (LGPD) | **a-verificar** | | |
| R8 | SPOF no Traefik | **a-verificar** | | |

## Backlog priorizado

(preenchido ao final da auditoria)
