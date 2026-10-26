# Lacunas do PRD — auditoria de 2026-10-15

Fonte: `spec/PRD_system.md` no commit `73bcb0f` (branch `docs/auditoria-lacunas-prd`, a partir de `develop` em `92106d1`). Cada linha foi medida no código neste commit;
`PROGRESS.md` serviu de hipótese, não de prova. Conferência: `python3 scripts/qa/cobertura_prd.py --final`.

**Linha de base dos testes:** backend 1355/1355 (`dart test`, com `postgres-test`), ACS 544/544, paciente 259/259, admin 459/459 (`flutter test`), scripts/qa 42 testes Python OK. Nenhuma falha.

**Amostragem:** 3 de 3 linhas `entregue` reproduzidas do zero (RF02, RF08, M1.2; 2026-10-15).

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
| RF05 | Painel de status da solicitação | **entregue** | `alerts.resolve` (só ACS do território, só de `acknowledged`, auditado) + `alerts.statusFor` com `resolvedAt`; ACS "Concluir atendimento"; paciente "Atendido pela equipe de saúde". Provas: `red_alert_service_test.dart` (`resolve (#76)`), `red_alert_cycle_test.dart` (`concluir o atendimento (#76)`), `alert_resolve_test.dart`, `patient_app_mvp_test.dart`. | — |
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
| RF17 | Logs de auditoria e conformidade | **parcial** | `audit_logs` encadeado por HMAC-SHA256; filtros, paginação, selo por linha e verificação global no servidor; exportação CSV só pelo admin, registrada na mesma transação; `audit_chain_test.dart`, `admin_endpoint_audit_chain_test.dart` e `admin_endpoint_audit_export_test.dart` passam; e2e `scripts/qa/admin_auditoria_e2e.sh` (2026-10-13/14). | ~~falta trigger/`REVOKE` append-only no banco~~ (#82, 2026-10-25: trigger + `REVOKE` de `PUBLIC`; o superusuário ainda contorna, #96); `audit_exports` fora da cadeia; o CSV vai pela área de transferência (`apps/admin/lib/app/audit_log_screen.dart:389`), sem download; revisão do DPO sobre a exportação. |
| RF19 | Escalonamento de alerta vermelho sem confirmação | **entregue** | `admin.escalateAlert` com motivo de conjunto fechado, idempotente (`alreadyEscalated`) e auditado na mesma transação (`backend/sinalacs_server/lib/src/application/admin/alert_escalation_service.dart:134`); prazo `RED_ALERT_ESCALATION_SECONDS` validado de 30 a 3600 s (`app_config.dart:120`, `app_config_test.dart`); `alert_escalation_service_test.dart` (14 testes) e `admin_endpoint_escalation_test.dart` passam; e2e no emulador 2026-10-12. | O PRD ainda marca RF19 como proposto: atualizar a linha. |
| RNF06 | RBAC | **parcial** | `Authorization.require` e `AdminScope` (UBS do coordenador) com recusa auditada; `authorization_test.dart` e `admin_scope_test.dart` passam; endpoints de dados do staff existem desde a #40 (`admin_endpoint.dart`). | Matriz §4.2.2 não cumprida em duas células: o paciente não lê os próprios logs de auditoria (`PatientDataOverview` não traz acessos) e o acesso do coordenador a outra microárea não pede justificativa. O texto do RNF06 no PRD (issue #40 aberta) está velho. |

### Módulos do backoffice (§2.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| MOD-UBS | Gestão de UBS | **ausente** | Nenhum endpoint cria ou edita UBS: `ubs_endpoint.dart` só tem `myContact`; nenhuma tela no `apps/admin/lib/app/`. | Cadastro/edição de UBS no backoffice, incluindo o telefone da UBS usado pelo botão do ACS (hoje só em seed/SQL). |
| MOD-ACS | Gestão de ACS | **entregue** | `admin.createAcs`/`setAcsMicroArea`/`setAcsActive`/`resetAcsPassword`/`resetAcsMfa`/`resetStaffMfa` + `apps/admin/lib/app/admin_accounts.dart`; `admin_endpoint_accounts_test.dart` passa; e2e `scripts/qa/admin_acs_gestao_e2e.sh` (#43). | Criar coordenador e definir o `ubsId` dele pela interface (hoje só seed/SQL). |
| MOD-RELATORIOS | Relatórios | **parcial** | `admin.indicators` devolve contagem por risco, alertas vermelhos e TMRAV (`AdminIndicators.tmravSeconds`), com polling de 30 s; `admin_read_service_test.dart` passa. | Sem recorte por período, sem exportação de relatório e sem as métricas de produto do §1.3 além do TMRAV (sincronização, aderência, visitas por ACS/dia, retenção). Os eventos do §1.3 já existem em `telemetry_events` (#83); a tela de relatórios sobre eles: #102 (corte da #83). |
| MOD-AUDITORIA | Auditoria | **parcial** | Tela `apps/admin/lib/app/audit_log_screen.dart` com filtros, selo e verificação global (#45). | Ver RF17. |
| MOD-CONFIG | Configurações de sistema | **ausente** | Nenhum endpoint nem tela de configurações do sistema; prazos (`RED_ALERT_ESCALATION_SECONDS`, `RETENTION_*_DAYS`) só por variável de ambiente. | Decidir se o admin edita configurações pela interface (§4.2.2 diz R/W); se sim, endpoint auditado + tela. |

### Módulos do app paciente (§2.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| MOD-MENSAGERIA | Mensageria assíncrona (tickets) | **fora-do-mvp** | Nenhum código de tickets ou mensagens entre paciente e equipe. | v1.5+ no §6.1. |
| MOD-PERFIL-CLINICO | Perfil clínico | **entregue** | `patients.myChronicConditions`/`updateChronicConditions` (`backend/sinalacs_server/lib/src/endpoints/patients_endpoint.dart:33,50`), cifrados em repouso; tela Perfil clínico (`apps/patient/lib/app/app.dart:1138,1714`); `patient_chronic_conditions_endpoint_test.dart` passa. | |

## Invariantes e segurança

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| INV-01 | ACS só vê pacientes da própria microárea | **entregue** | Recusa de outra microárea testada por endpoint: `patients.listMicroArea` e `visits.pull` (`patient_directory_and_territory_test.dart`), `visits.sync` (`visit_sync_service_test.dart`, rejeição de território), `onboarding.generateEnrollmentToken` (`onboarding_service_test.dart:75`), `alerts.acknowledge` (`red_alert_discard_paths_test.dart`), `notices.sendSegmented` (`notices_endpoint_test.dart`), staff por UBS (`admin_scope_test.dart`); todos passam (2026-10-15). |  |
| INV-02 | Classificação de risco não alterável por humano | **entregue** | Nenhum endpoint recebe risco do cliente: `createRedAlert` aceita só `idempotencyKey`, `locationHash` e `locationCell` (`alerts_endpoint.dart`); `triage.evaluate` recebe os sinais e o servidor classifica; o app do paciente não calcula risco (`apps/patient/lib/app/app.dart:1424-1428`). |  |
| INV-03 | Alerta vermelho nunca perdido | **entregue** | Outbox MQTT com ACK, retry e reforço; publicação confirmada por PUBACK (`mqtt_alert_dispatcher_resilience_test.dart`, #56), caminhos de descarte cobertos (`red_alert_discard_paths_test.dart`), `red_alert_cycle_test.dart`; e2e `scripts/qa/mqtt_resiliencia_e2e.sh`; 10/10 alertas entregues na medição de latência. | Reserva por HTTP entregue na #80 (ver R2); com o app em segundo plano e o broker fora, o alerta só aparece quando o ACS volta ao app. |
| INV-04 | Dado de saúde nunca em texto plano | **entregue** | Colunas clínicas cifradas em AES-256-GCM na aplicação (`*Encrypted`/`*KeyVersion` para condições crônicas, respostas de triagem e notas de visita); SQLCipher no ACS (`apps/acs/lib/core/database/encrypted_database.dart`). Desde 2026-10-16 (#75): riscos de triagem e visita cifrados (`resultRiskEncrypted`, `riskLevelBefore/AfterEncrypted`); `alerts.riskLevel` legível por decisão registrada no PRD (INV-04). | — |
| INV-05 | Paciente nunca acessa dado de outro paciente | **entregue** | Token do paciente carrega o `patientId` e os endpoints de paciente leem só dele: `myData`, consentimentos e pedidos (`patient_data_overview_endpoint_test.dart`, `data_subject_rights_endpoint_test.dart`), `statusFor` (`authorization_test.dart`, `red_alert_cycle_test.dart`), token de push por dono (`push_token_endpoint_test.dart`); passam (2026-10-15). |  |

### STRIDE (§4.2.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| STRIDE-S | Spoofing: mensagens falsas no MQTT | **parcial** | Broker com senha + ACL por tópico + certificado de cliente obrigatório (`infra/docker/mosquitto/mosquitto.conf:10`); `scripts/qa/mtls_invariants.sh` OK (2026-10-15). | Certificado de cliente por aparelho em produção (hoje um certificado de dev compartilhado, `acs-area-12.crt`); adiado na #81 (D8) para a issue #94. |
| STRIDE-T | Tampering: triagem alterada no dispositivo | **parcial** | O risco é recalculado no servidor (INV-02), então adulterar a triagem no aparelho não muda a classificação. | Não há a assinatura digital dos dados de triagem no dispositivo que o PRD descreve; decidir se a reclassificação no servidor substitui a assinatura e registrar. |
| STRIDE-R | Repudiation: logs append-only assinados | **parcial** | Cadeia HMAC em `audit_logs` detecta remoção e alteração (`audit_chain_check`). | ~~Append-only no banco não existe~~ — trigger + `REVOKE` desde a #82 (2026-10-25); falta separar o papel do superusuário (#96). |
| STRIDE-I | Information disclosure: PII no dispositivo | **entregue** | SQLCipher no ACS com chave no Keystore (`apps/acs/lib/core/security/database_key_store.dart`), `FLAG_SECURE` na janela do ACS (`secure_window_test`). | O app do paciente guarda lembretes de saúde em texto livre (medicamento, pesagem: `apps/patient/lib/core/reminders/reminder.dart:1`) em `sqflite` sem cifra, por decisão; reavaliar se o campo passar a aceitar diagnóstico. |
| STRIDE-D | Denial of service: inundação MQTT | **ausente** | `infra/docker/mosquitto/mosquitto.conf` sem nenhum limite (`max_connections`, `max_inflight_messages`, `message_size_limit`); nenhum middleware de rate limit no Traefik. | Limites no Mosquitto e rate limit no Traefik. |
| STRIDE-E | Elevation of privilege: outra microárea | **entregue** | Ver INV-01 e RNF06 (`Authorization.require`, recusa auditada). |  |

### Criptografia (§4.2.3)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| CRIPTO-APP-LOCAL | SQLCipher com chave derivada de PIN/biometria | **parcial** | SQLCipher com chave aleatória de 32 bytes guardada no Keystore (`apps/acs/lib/core/security/database_key_store.dart:31`); o arquivo documenta por que não usa PBKDF2 de PIN (`:8`). | Divergência do PRD (§4.2.3 pede chave derivada de PIN/biometria por PBKDF2): atualizar o PRD com a decisão ou amarrar a chave à biometria. |
| CRIPTO-APP-CACHE | SQLCipher com chave rotativa | **entregue** | Rotação por evento (#81, D6): `VisitDatabase.destroy` troca a chave no "Limpar este aparelho" e na limpeza remota; decisão de não rotacionar por calendário registrada em `spec/lgpd_design.md` §5.1; `device_wipe_test.dart`, e2e `acs_remote_wipe_e2e.sh` (chave trocada, banco reaberto vazio). | |
| CRIPTO-APP-TRAEFIK | TLS 1.3 app ↔ Traefik | **entregue** | Traefik com `minVersion: VersionTLS13` (`infra/docker/traefik/dynamic/tls.yaml:22`); `scripts/qa/tls_invariants.sh` OK e `openssl s_client -tls1_2` na 443 recusado (2026-10-15). | Certificado Let's Encrypt em produção (hoje CA de dev). |
| CRIPTO-TRAEFIK-BACKEND | mTLS Traefik ↔ backend | **parcial** | #78 (2026-10-16): Traefik → backend em TLS 1.3 de mão única com a cadeia verificada: o backend escuta TLS na 8080 interna (`API_TLS_*`, `ApiTlsConfig`), o Traefik disca por `https` com o `serversTransport` `backend-tls` (`rootCAs` + `serverName`, sem `insecureSkipVerify`). Provado pelo Grupo E de `tls_invariants.sh`. | mTLS: bloqueado pelo Serverpod 3.4.13, que sobe o socket pelo `relic_io` (`HttpServer.bindSecure` sem `requestClientCertificate`); decisão registrada em `PROGRESS.md`. |
| CRIPTO-POSTGRES | Criptografia no PostgreSQL | **entregue** | AES-256-GCM na aplicação com `HEALTH_DATA_ENCRYPTION_KEY` (decisão §2.2.1 §6, que substituiu pgcrypto); ver INV-04. | Chave em gerenciador de segredos (Vault) em produção; hoje variável de ambiente. |
| CRIPTO-AUDITORIA | Cadeia HMAC-SHA256 da auditoria | **entregue** | HMAC-SHA256 com `AUDIT_CHAIN_SECRET` fora do Postgres; `audit_chain_test.dart` passa. | Rotação do segredo invalida a história (limite conhecido, #45). |

## Não funcionais

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| RNF01 | Latência MQTT < 500 ms (p95) | **parcial** | Entrega de alerta p95 212 ms, 10/10 amostras (meta < 500 ms); `measure_latency.dart --samples 10 --visit-count 100` contra a stack local (2026-10-16 01:27 UTC). | Só stack local, 1 cliente sequencial, 10 amostras (p95 de 10 amostras é quase o máximo): repetir em produção, com carga e mais amostras. |
| RNF02 | Sincronização offline > 99,5 % | **parcial** | Sync 10/10 lotes de 100 visitas sem perda (`measure_latency.dart --samples 10 --visit-count 100` contra a stack local (2026-10-16 01:27 UTC)); `offline_burst_test.dart` prova que nenhuma de 100 se perde em reinício. Com telemetria ativa (2026-10-25, commit d617df7): mesmo comando, 3 rodadas, 10/10 lotes sem perda, p95 de sync 123, 102 e 104 ms (linha de base 112 ms, teto +10 % = 123,2 ms). | Mensurável em campo; medido no piloto (`sync_attempt`/`sync_result` emitidos, #83). |
| RNF03 | Criptografia AES-256 em repouso | **parcial** | Ver INV-04 e CRIPTO-*. | Ver CRIPTO-APP-CACHE. |
| RNF04 | TLS 1.3 em todas as comunicações | **parcial** | #78 (2026-10-16) fechou os três trechos da issue: RPC em TLS 1.3 obrigatório (Grupo B); broker MQTT só em TLS 1.3 na 8883 com mTLS (`tls_version tlsv1.3`, Grupo F; `mtls_invariants.sh` OK); Traefik → backend em TLS 1.3 verificado (Grupo E). Medido também no `emulator-5554` (API 36). | Seguem em texto claro na stack local, fora do escopo da #78: backend → Postgres (`SERVERPOD_DATABASE_REQUIRE_SSL: "false"`, 5432 publicado no host), backend → Gorush (`GORUSH_URL: http://gorush:8088`), Insights (8083) e webServer (8082) dentro do container, dashboard do Traefik (8081, só dev). Produção: no Render o TLS termina na borda e o container segue em HTTP (`backend/DEPLOY.md`); sem prova em aparelho físico nem em API 24–29; mTLS interno (CRIPTO-TRAEFIK-BACKEND). |
| RNF05 | Acessibilidade WCAG 2.1 AA | **parcial** | Matriz de contraste e `meetsGuideline` nos três apps (`apps/*/test/contrast_tokens_test.dart`, `touch_targets_test.dart` no admin), avaliação em `spec/ux_accessibility_assessment.md` (WCAG 2.2 AA, superconjunto do 2.1); linha de base verde. | Foco visível no admin (A11Y-2.4.7) e métricas de interface (A11Y-LCP/FID/CLS) não medidas. |

### SLOs (§4.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| SLO-LOGIN | Login < 1 s | **parcial** | Não medido. | Medir p95 do login do ACS e do paciente (o Argon2id domina o custo). |
| SLO-ALERTA | Alerta publish → ACK < 500 ms | **parcial** | p95 212 ms (meta < 500 ms) por `measure_latency.dart`, stack local, 10 amostras (2026-10-16 UTC). | Só stack local, 1 cliente sequencial, 10 amostras (p95 de 10 amostras é quase o máximo): repetir em produção, com carga e mais amostras. |
| SLO-DASHBOARD | Dashboard ACS < 1,5 s, paginação de 20 | **parcial** | Carga do dashboard não medida; a fila não pagina (lista inteira em `AlertQueue`). | Paginação de 20 itens e medição < 1,5 s. |
| SLO-VISITA | Registro offline < 200 ms | **parcial** | Inserção local sem rede (`offline_visit_queue.dart`), tempo não medido. | Medir a gravação local (< 200 ms). |
| SLO-SYNC | Sync de 50 itens < 5 s | **parcial** | Lote de 100 visitas com p95 112 ms (meta: 50 itens < 5 s), stack local, 10 amostras (2026-10-16 UTC). | Só stack local, 1 cliente sequencial, 10 amostras (p95 de 10 amostras é quase o máximo): repetir em produção, com carga e mais amostras. |
| SLO-MAPA | Mapa < 2 s, clusterização 50+ | **parcial** | Renderização não medida; sem clusterização (ver RF10). | Clusterização para 50+ pinos e medição < 2 s. |
| SLO-TRIAGEM | Cálculo da triagem < 50 ms | **parcial** | Função pura com seis booleanos (`triage_engine.dart`), sem IO; tempo não medido. | Um teste de tempo basta para fechar. |

### Acessibilidade (§4.3)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| A11Y-1.4.3 | Contraste de texto ≥ 4,5:1 | **entregue** | Matriz determinística de contraste nos três apps (`apps/acs/test/contrast_tokens_test.dart`, `apps/patient/test/contrast_tokens_test.dart`, `apps/admin/test/contrast_tokens_test.dart`) mais os de tema claro; linha de base verde. |  |
| A11Y-1.4.11 | Contraste não textual ≥ 3:1 | **parcial** | Tokens de preenchimento conferidos na matriz de contraste. | Não há golden tests (o PRD pede validação visual por golden). |
| A11Y-2.5.1 | Alvos de toque ≥ 48 dp | **entregue** | `androidTapTargetGuideline` no ACS e no paciente, alvos >= 48 dp no admin (`apps/admin/test/notices_a11y_test.dart:22`); botões de 48x52 dp no paciente. |  |
| A11Y-2.5.6 | Botão de pânico ≥ 60 dp | **entregue** | Botão de pânico 208x208 dp (`apps/patient/lib/app/app.dart:1380`) e SAMU 60x60 dp no ACS. |  |
| A11Y-2.4.7 | Foco visível | **parcial** | Nenhum `FocusNode`, `focusColor` ou estilo de foco no `apps/admin/lib` (0 ocorrências); apps móveis usam o padrão do Material. | Indicador de foco visível no backoffice (uso com teclado no desktop/web) e teste. |
| A11Y-3.3.2 | Rótulos e Semantics | **entregue** | `Semantics`/`liveRegion` em status dinâmicos e `labeledTapTargetGuideline` (`apps/acs/test/login_flow_test.dart`, `apps/patient/test/patient_app_mvp_test.dart`). |  |
| A11Y-LCP | LCP < 1,5 s | **parcial** | Não medido. | Medir primeiro quadro do dashboard (< 1,5 s), por exemplo com `integration_test` + timeline. |
| A11Y-FID | FID < 100 ms | **parcial** | Não medido. | Medir a resposta ao toque no botão de pânico (< 100 ms). |
| A11Y-CLS | CLS < 0,1 | **parcial** | Não medido. | Medir estabilidade do layout no carregamento (< 0,1). |

## LGPD e dados

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| LGPD-RF01 | Coleta mínima | **parcial** | `spec/lgpd_data_audit.md` classifica campo a campo as 25 tabelas de domínio da migração `20261014155304871`. | `alert_outbox` aparece com o nome do modelo (`alert_outbox_entry`, `spec/lgpd_data_audit.md:94`) e sem os campos `topic`, `lastError` e `attempts`: corrigir nome e campos e conferir a contagem a cada migração. |
| LGPD-RF02 | Consentimento granular | **entregue** | Consentimento por finalidade com histórico (`consent_logs`, `patients.updateConsent`, `hasGrantedConsent`); token de push só com consentimento; testes de endpoint passam na linha de base. | Validação jurídica do texto dos termos (ver M3.4). |
| LGPD-RF07 | Retenção e exclusão (job de expurgo) | **parcial** | Expurgo diário no servidor por `ExpurgeFutureCall` (`backend/sinalacs_server/lib/src/application/retention/expurge_future_call.dart`, agendado em `server.dart:158`): alertas 2 anos, visitas e triagens 5 anos (`RETENTION_*_DAYS`); `expurge_service_test.dart` e `retention_expurge_test.dart` passam (12 testes, 2026-10-15). | Expurgo no aparelho da fila de um dono que nunca volta (ACS); prazos de OTP, convites e tokens não entram na política. |
| LGPD-RF08 | Direitos do titular (Meus Dados + exportação JSON) | **entregue** | Painel Meus Dados (`patients.myData`, `PatientDataOverview`) e exportação em JSON copiada para a área de transferência (`apps/patient/lib/app/app.dart:2040-2084`, botão `Copiar meus dados (JSON)`); pedidos de exclusão/correção atendidos no backoffice (#42). | Validar as regras de anonimização com o encarregado (DPO); exportação como arquivo, não só área de transferência. |
| LGPD-RF09 | Proteção de dados sensíveis | **parcial** | Ver INV-04, CRIPTO-* e RNF06. | Ver CRIPTO-APP-CACHE e RNF06. |
| LGPD-RF11 | Controle de acesso RBAC | **parcial** | Ver RNF06. | Matriz §4.2.2: paciente lendo os próprios logs e justificativa do coordenador. |

### Modelo de dados e telemetria (§1.3, §3)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| DADOS-TIMESCALE | Logs e telemetria em TimescaleDB | **ausente** | Nenhuma ocorrência de TimescaleDB no repositório; logs e auditoria em tabelas comuns do Postgres. | Decidir se TimescaleDB entra (não está em `spec/stack.md`) ou corrigir o §3.2 do PRD. |
| DADOS-VERSION-OTIMISTA | Versionamento otimista com 409 | **entregue** | `visits.version`; versão divergente devolve `conflict` com a versão do servidor sem sobrescrever, mesma versão é idempotente (`backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart:490-500`); `visit_sync_service_test.dart` passa. | Fechado pela #79 (2026-10-16): `visits.resolveConflict` compara e grava sobre a versão vista; prova em `visit_conflict_resolution_test.dart` e no e2e `acs_full_e2e.sh` (`docs/superpowers/plans/2026-10-16-issue-79-e2e.log`). Aberto: a gravação é leitura-depois-update sem trava de linha (ver `PROGRESS.md`, #79). |
| DADOS-SYNC-TOKEN | sync_token sequencial | **ausente** | Nenhum `sync_token` sequencial; a idempotência é por `localId` + `version` por registro e a descida usa cursor (`visits.pull`). | Decidir se o `sync_token` ainda é necessário ou corrigir o §3.4 do PRD. |
| DADOS-MIGRACAO-ROLLBACK | Migrações com rollback | **ausente** | Migrações do Serverpod só para frente (`backend/sinalacs_server/migrations/*/migration.sql`); nenhum script de rollback. | Rollback por versão ou decisão registrada de restauração por backup. |
| DADOS-CACHE-PACIENTE | Cache local do paciente em `sqflite` com triagens e alertas pendentes (§3.2) | **ausente** | O app do paciente não guarda triagens nem alertas pendentes no aparelho; só lembretes e preferências de consentimento (ver M1.5). | Corrigir o §3.2 do PRD ou decidir guardar o alerta pendente quando não há rede. |
| METRICA-TMRAV | North Star: TMRAV < 90 s | **parcial** | Calculado em `AdminIndicators.tmravSeconds` a partir de `triggeredAt`/`acknowledgedAt`. | Nenhuma medição contra a meta de 90 s (só existe em piloto). |
| METRICA-PRODUTO | Sincronização > 99,5 %, aderência > 90 %, ≥ 8 visitas/ACS/dia, retenção > 70 % (§1.3) | **parcial** | Taxa de sincronização mensurável pelo CLI `telemetry_report.dart` (`eventualSyncRate`, `perAttemptSuccessRate`; #83, 2026-10-25, commit d617df7). Aderência, visitas/ACS/dia na tela e retenção seguem fora. | Indicadores do backoffice a partir de `telemetry_events` (#102, corte da #83). |
| EVT-alert_triggered | Evento alert_triggered | **implementado** | `alert_triggered` gravado no servidor em `alerts.createRedAlert` (`telemetry_events`, paciente só como pseudônimo HMAC, `location_hash` trocado por `location_known`, A1). `./scripts/qa/acs_telemetria_e2e.sh` no emulador (2026-10-25, commit d617df7; log `docs/superpowers/plans/2026-10-25-issue-83-e2e.log`): 1 evento. | Nenhuma para o evento. O TMRAV segue em `AdminIndicators.tmravSeconds`. |
| EVT-alert_received_acs | Evento alert_received_acs | **implementado** | `alert_received_acs` gravado no servidor no primeiro ACK (`alerts.acknowledge`, com `latency_ms` e `channel`; o 2º ACK não cria linha). `./scripts/qa/acs_telemetria_e2e.sh` no emulador (2026-10-25, commit d617df7; log `docs/superpowers/plans/2026-10-25-issue-83-e2e.log`): 1 evento; `dart run bin/telemetry_report.dart` dá `medianAckLatencyMs` 4905. | Nenhuma. |
| EVT-sync_attempt | Evento sync_attempt | **implementado** | `sync_attempt` gravado no aparelho (fila SQLCipher v9, `TelemetryRecorder`) e enviado por `telemetry.ingest` (`TelemetryUploader`). `./scripts/qa/acs_telemetria_e2e.sh` no emulador (2026-10-25, commit d617df7; log `docs/superpowers/plans/2026-10-25-issue-83-e2e.log`): 2 eventos, sem `eventId` duplicado após reenvio forçado de 7. | Nenhuma. Tentativa interrompida só aparece no relatório (`interruptedAttempts`). |
| EVT-sync_result | Evento sync_result | **implementado** | `sync_result` com contagens de sucesso/falha/conflito e `transport_error`. `./scripts/qa/acs_telemetria_e2e.sh` no emulador (2026-10-25, commit d617df7; log `docs/superpowers/plans/2026-10-25-issue-83-e2e.log`): 2 eventos; `eventualSyncRate` 1.0, `perAttemptSuccessRate` 0.5, `interruptedAttempts` 0. | Nenhuma. Taxa de sincronização mensurável pelo CLI `telemetry_report.dart` (ver METRICA-PRODUTO). |
| EVT-visit_registered | Evento visit_registered | **implementado** | `visit_registered` com `offline_flag`, `visit_type` e `alert_id` quando vem da escalonação. `./scripts/qa/acs_telemetria_e2e.sh` no emulador (2026-10-25, commit d617df7; log `docs/superpowers/plans/2026-10-25-issue-83-e2e.log`): 3 eventos, 1 visita ligada ao alerta (`alertLinkedVisits` 1). | Nenhuma. |

## Roadmap, hipóteses e riscos

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| M1.1 | Docker Compose local | **entregue** | `docker-compose.yml` sobe Postgres, Mosquitto, backend, Traefik e Gorush; todos em execução e usados pela medição de latência e pelos scripts TLS/mTLS (2026-10-15). |  |
| M1.2 | CI básica | **entregue** | `.github/workflows/ci.yml` com 9 jobs (`flutter test`, `dart analyze`, build Docker, e2e Android), guardados por `scripts/qa/ci_invariants.sh`. |  |
| M1.3 | Motor de triagem (MCDC, 50 cenários) | **entregue** | Ver RF16: 64 combinações (tabela-verdade completa) + 8 cenários nomeados. | Sem relatório MCDC por ferramenta; a tabela-verdade completa o torna redundante para seis booleanos. |
| M1.4 | FSM de sincronização | **entregue** | `backend/sinalacs_server/lib/src/application/sync/sync_fsm.dart` e a FSM do aparelho em `offline_visit_queue.dart`; testes de transição, conflito e erro passam na linha de base. |  |
| M1.5 | SQLCipher local | **entregue** | SQLCipher no ACS (`apps/acs/lib/core/database/encrypted_database.dart`, `integration_test/encrypted_storage_test.dart`). O paciente usa `sqflite` sem cifra, de propósito, para lembretes e preferências de consentimento. | Lembretes de saúde do paciente em texto livre sem cifra (ver STRIDE-I). |
| M2.1 | App Paciente MVP | **parcial** | Login, alerta, triagem e status no app do paciente (RF01, RF03, RF04, RF05). | SMS real (RF01). |
| M2.2 | App ACS MVP | **entregue** | Login, territorialização, dashboard e registro no ACS (RF07, RF08, RF09, RF11). |  |
| M2.3 | MQTT com TLS (WSS) | **parcial** | MQTT sobre TLS 1.3 com mTLS na 8883 (`mtls_invariants.sh` e Grupo F de `tls_invariants.sh` OK, 2026-10-16). | O critério fala em WSS, e WebSockets (9001) não é publicado por decisão. |
| M2.4 | 100 registros sincronizam em < 5 s | **parcial** | 100 visitas por lote em p95 112 ms, 10/10 (meta < 5 s), `measure_latency.dart` contra a stack local (2026-10-16 UTC); `offline_burst_test.dart`. | Só stack local, 1 cliente sequencial, 10 amostras (p95 de 10 amostras é quase o máximo): repetir em produção, com carga e mais amostras. |
| M2.5 | Testes de caos (Toxiproxy) | **parcial** | Simulador em processo `apps/acs/lib/core/services/network_chaos_simulator.dart` + `network_chaos_test.dart`; resiliência real do broker em `scripts/qa/mqtt_resiliencia_e2e.sh`. | Toxiproxy (0 ocorrências): latência, jitter e partição na rede de verdade entre app, Traefik e broker. |
| M2.6 | Testes de usabilidade em campo | **externo** | Avaliação de acessibilidade e e2e no emulador (`spec/ux_accessibility_assessment.md`). | Beta fechado com 5 ACS e 10 pacientes em campo (dono: produto + UBS). |
| M3.1 | Deploy em produção (Pulumi) | **ausente** | Nenhuma ocorrência de Pulumi; `backend/DEPLOY.md` é só um caminho de demo free-tier, não executado. | IaC (Pulumi) e VPS de produção. |
| M3.2 | Monitoramento (OpenTelemetry) | **ausente** | Nenhuma ocorrência de OpenTelemetry, Prometheus ou Grafana. | Traces e métricas em produção. |
| M3.3 | Testes de carga | **ausente** | Nenhum script de carga (100 ACS simultâneos, 500 alertas/hora); `measure_latency.dart` é sequencial, 1 cliente. | Teste de carga. |
| M3.4 | LGPD compliance | **externo** | Documentos de privacidade, painel de consentimento e direitos do titular entregues (LGPD-RF02, LGPD-RF08). | Revisão jurídica do texto real dos termos e validação do DPO (anonimização, exportação da auditoria). |
| M3.5 | Lançamento v1.0 em UBS piloto | **externo** | Nada no código. | Piloto em 1 UBS (2 microáreas, 50 pacientes), depois de M3.1-M3.4. |

### MVP (§6.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| MVP-LOGIN-60S | 10 pacientes logam em < 60 s | **parcial** | Fluxo OTP funciona (RF01). | SMS real e medição com 10 pacientes. |
| MVP-ALERTA-2S | Alerta chega ao ACS em < 2 s | **parcial** | p95 212 ms na stack local (RNF01). | Só stack local, 1 cliente sequencial, 10 amostras (p95 de 10 amostras é quase o máximo): repetir em produção, com carga e mais amostras. |
| MVP-TRIAGEM-3P | Triagem de 3 perguntas | **entregue** | Seis perguntas, classificação determinística (RF04). | Corrigir 3 para 6 no texto do PRD. |
| MVP-STATUS | Enviado → Visualizado → Atendido | **entregue** | Enviado, Recebido e Atendido aparecem (RF05, #76): `alerts.resolve` (só ACS do território, só de `acknowledged`, auditado) + `alerts.statusFor` com `resolvedAt`; ACS "Concluir atendimento"; paciente "Atendido pela equipe de saúde". | — |
| MVP-LOGIN-ACS | ACS loga com matrícula e senha | **entregue** | Ver RF07. |  |
| MVP-TERRITORIO-30S | Microárea carrega em < 30 s | **parcial** | Cache da microárea entregue (RF08). | Medir o download (< 30 s). |
| MVP-FILA-ORDEM | Lista Vermelho → Amarelo → Verde | **entregue** | Ver RF09. |  |
| MVP-VISITA-OFFLINE | Visita salva local e sincronizada em background | **parcial** | Gravação local e envio quando a rede volta ou o app abre (RF11). | Envio em segundo plano com o app fechado (WorkManager fora da stack). |
| MVP-MQTT-100 | 100 dispositivos, latência < 500 ms | **parcial** | Latência < 500 ms medida com 1 cliente (RNF01). | 100 dispositivos simultâneos não testados (ver M3.3). |
| MVP-MIGRACOES-LOGS | Migrações versionadas e logs estruturados | **parcial** | Migrações versionadas do Serverpod aplicadas no boot e na CI. | Logs estruturados: o backend usa `session.log` e `stdout.writeln` em texto livre (7 pontos em `lib/src`), sem formato estruturado. |

### Hipóteses (§1.2)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| H1 | ACS priorizam mais rápido (−40 %) | **externo** | TMRAV calculado em `AdminIndicators.tmravSeconds`. | Piloto; correlação alerta→visita disponível (`visit_registered.alert_id`, `telemetry_report.medianAlertToVisitSeconds`, #83). |
| H2 | ≥ 80 % completam onboarding sem ajuda | **externo** | Nada instrumentado. | Piloto; registrar conclusão do onboarding sem assistência (evento ausente): #99 (corte da #83). |
| H3 | ≥ 90 % de concordância com avaliação médica | **externo** | Nada no código: não existe classificação médica posterior para comparar. | Piloto com avaliação médica e campo para registrá-la (`risk_level_after` existe em `visits`). |
| H4 | ≥ 99,5 % dos registros offline sincronizam | **externo** | Sync medido em laboratório (RNF02) e, desde a #83, por `sync_attempt`/`sync_result`. | Mensurável em campo; medido no piloto. |

### Riscos (§6.3)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| R1 | Colisão de sincronização | **entregue** | Conflito detectado sem sobrescrever (`visit_sync_service.dart`), guardado fora da retentativa com a cópia do servidor (schema v8, `offline_visit_queue.dart`), tela de comparação lado a lado e decisão do ACS (`resolve_conflicts`, `conflict_*`) e `visits.resolveConflict` com compare-and-set. Emulador: `acs_full_e2e.sh`, 6/6 em 2026-10-16 (`docs/superpowers/plans/2026-10-16-issue-79-e2e.log`). | Conflito de visita legada segue sem tela (quarentena); "manter a do servidor" não deixa trilha no servidor; ver abertos em `PROGRESS.md`, #79. |
| R2 | Falha do MQTT em rede 3G | **entregue** | #80 (2026-10-17). Reconexão com backoff e sessão persistente no MQTT; outbox no servidor reentrega (`mqtt_resiliencia_e2e.sh`); visitas já vão por HTTP; reserva por HTTP dos alertas: `alerts.openForMicroArea` consultado pelo ACS a cada 30 s enquanto o broker está fora (`AlertHttpFallback`, `AlertQueue.mergeFromServer`); no `emulator-5554`, alerta sem outbox chegou à tela em 29,6 s e foi confirmado (`scripts/qa/acs_alert_fallback_e2e.sh`). | Consulta só em primeiro plano (sem WorkManager, fora de `spec/stack.md`); nenhum alerta gravado no aparelho (decisão D5 da #80). |
| R3 | Vazamento de PII no dispositivo | **parcial** | Limpeza do aparelho pelo próprio ACS (`device_wipe_test.dart`); chave do SQLCipher no Keystore; limpeza remota pelo backoffice e rotação da chave por evento (#81, 2026-10-17): `admin.orderDeviceWipe`, `devices.pendingWipe`/`confirmWipe`, `RemoteWipeCoordinator`; prova no emulador API 36 em `./scripts/qa/acs_remote_wipe_e2e.sh` (log `docs/superpowers/plans/2026-10-17-issue-81-e2e.log`). | Certificado de cliente por aparelho (issue #94); chave derivada de biometria, que o PRD pede (a chave do SQLCipher fica no Keystore sem amarração de autenticação, por decisão do `spec/lgpd_design.md` §5.1); aparelho offline nunca alcançado e JWT vivo até 15 min; API 24–29 e aparelho físico sem prova. |
| R4 | Rejeição do ACS | **externo** | Nada no código. | NPS semanal e treinamento (produto + UBS). |
| R5 | Performance do PostgreSQL | **parcial** | 46 índices na migração `20261014155304871`, incluindo `alerts_micro_area_status_idx` e `users_micro_area_idx`. | Particionamento por microárea não existe; sem teste de carga que mostre necessidade (M3.3). |
| R6 | Dependência de SMS gateway | **parcial** | O ACS pode gerar quantas vezes quiser um convite QR de uso único para paciente da microárea dele (`backend/sinalacs_server/lib/src/endpoints/onboarding_endpoint.dart:21`), e `completeEnrollment` emite uma sessão do paciente (`onboarding_endpoint.dart:37,70`): é metade do fallback por QR. Nenhum provedor de SMS (RF01). | Entrada sem o ACS presente quando o SMS falha; biometria; múltiplos provedores de SMS. |
| R7 | Mudanças regulatórias (LGPD) | **externo** | Nada no código. | Comitê de compliance e DPO. |
| R8 | SPOF no Traefik | **ausente** | Uma instância de Traefik no Compose. | Segunda instância e failover (infra de produção, M3.1). |

## Backlog priorizado

Critério: **P0** toca invariante ou o núcleo do MVP (§6.1) sem critério atingido; **P1** requisito de risco Crítico (§2.2) ou risco de impacto 5 (§6.3); **P2** demais RF/RNF e Fase 3; **P3** fora do MVP e correções do PRD; **—** externo, com dono e sem prioridade de engenharia.

| # | Prioridade | Lacuna | IDs | Tipo | Justificativa |
|---|---|---|---|---|---|
| 1 | P0 | **Resolvido (2026-10-16, #75).** Colunas de risco da triagem e do alerta em texto plano (`triage_sessions.resultRisk`/`resultDisplay`, `visits.riskLevelBefore`/`riskLevelAfter`, `alerts.riskLevel`) | INV-04, RNF03, LGPD-RF09 | código | Viola uma invariante; ou cifrar, ou registrar no PRD por que o risco precisa ficar legível para a fila. |
| 2 | P0 | **Resolvido (2026-10-16, #76).** Paciente nunca vê Atendido: nenhum caminho leva o alerta a `resolved` | RF05, MVP-STATUS, M2.1 | código | Critério do núcleo do MVP (§6.1) não atingido; precisa da ação do ACS de encerrar o atendimento. |
| 3 | P0 | Envio de OTP por SMS real (provedor + telefone do paciente) | RF01, MVP-LOGIN-60S, M2.1, R6 | código + externo | Sem SMS o paciente só entra com o ACS presente gerando um QR (R6): não há login por conta própria fora do ambiente de dev; a escolha de provedor/contrato é de produto. |
| 4 | P1 | ~~Broker MQTT aceita TLS 1.2; Traefik → backend em HTTP~~ — resolvido na #78 (2026-10-16): broker só 1.3, Traefik → backend em TLS 1.3 verificado; mTLS interno bloqueado pelo Serverpod | RNF04, M2.3, CRIPTO-TRAEFIK-BACKEND | infra | Risco Crítico; `tls_version tlsv1.3` no `mosquitto.conf` e o caso no `tls_invariants.sh` é pequeno; mTLS interno exige decisão. |
| 5 | P1 | Resolução de conflito de visita no ACS (comparar e escolher versão) | R1, DADOS-VERSION-OTIMISTA | código | Risco de impacto 5; entregue em 2026-10-16 (#79); antes, a visita em conflito ficava parada na fila para sempre. |
| 6 | P1 | ~~Reserva por HTTP para o ACS receber alertas quando o MQTT cai~~ — resolvido na #80 (2026-10-17): `alerts.openForMicroArea` consultado a cada 30 s com o broker fora | R2, INV-03 | código | Risco de impacto 5 em rede 3G; antes, o ACS não tinha como listar alertas pendentes por HTTP. |
| 7 | P1 | ~~Remote wipe~~ e certificado de cliente por aparelho — o remote wipe e a rotação da chave foram entregues na #81 (2026-10-17), mas R3 segue **parcial**; o certificado por aparelho segue na issue #94 | R3, STRIDE-S, CRIPTO-APP-CACHE | código + infra | Risco de impacto 5; o certificado depende de uma lib X.509/CSR fora de `spec/stack.md`, de uma CA de aparelhos e de PKI de produção. |
| 8 | P1 | Auditoria append-only no banco (trigger/`REVOKE`) — **feito na #82 (2026-10-25)**; resto na #96 | RF17, STRIDE-R | código | A cadeia só detecta; o PRD pede logs imutáveis. |
| 9 | P1 | ~~Telemetria estruturada dos eventos do §1.3~~ — **feito na #83 (2026-10-25)** | EVT-*, RNF02, H1, H2, H4, MOD-RELATORIOS | código | Sem os eventos, a North Star e três hipóteses não são mensuráveis no piloto. |
| 10 | P2 | Rate limiting no Mosquitto e no Traefik | STRIDE-D | infra | DoS listado no STRIDE sem mitigação. |
| 11 | P2 | Deploy de produção (Pulumi/VPS), observabilidade e failover do Traefik | M3.1, M3.2, R8 | infra | Fase 3 inteira; pré-requisito do piloto M3.5. |
| 12 | P2 | Teste de carga (100 ACS, 500 alertas/h) e medições de SLO pendentes | M3.3, MVP-MQTT-100, R5, SLO-LOGIN, SLO-DASHBOARD, SLO-VISITA, SLO-TRIAGEM, MVP-TERRITORIO-30S, A11Y-LCP, A11Y-FID, A11Y-CLS | prova | Código existe; falta medir. Paginação de 20 no dashboard junto. |
| 13 | P2 | Testes de caos com Toxiproxy na rede real | M2.5 | prova | O simulador em processo não exercita a rede entre app, Traefik e broker. |
| 14 | P2 | Check-in passivo por geofence nativa | RF12 | código + externo | Bloqueado por revisão de produto/jurídico do texto de divulgação e da localização em segundo plano. |
| 15 | P2 | Clusterização do mapa e chave de Maps de produção | RF10, SLO-MAPA | código | Pedido do §4.1 para 50+ pacientes. |
| 16 | P2 | Push em iOS/APNs, aparelho físico e Gorush hospedado | RF14 | código + infra | Android provado só em emulador. |
| 17 | P2 | Matriz RBAC §4.2.2: paciente lendo os próprios logs; justificativa do coordenador | RNF06, LGPD-RF11 | código |  |
| 18 | P2 | Backoffice: cadastro de UBS (com telefone), coordenador pela interface, configurações do sistema | MOD-UBS, MOD-CONFIG, MOD-ACS | código |  |
| 19 | P2 | Tema claro no backoffice e foco visível | RF18, A11Y-2.4.7, A11Y-1.4.11 | código | Golden tests para contraste não textual junto. |
| 20 | P2 | Expurgo no aparelho do dono que nunca volta; prazos de OTP/convites/tokens na política | LGPD-RF07 | código |  |
| 21 | P2 | `alert_outbox` no inventário LGPD com nome e campos certos | LGPD-RF01 | documentação | Uma tabela; vale prender a contagem num conferidor. |
| 22 | P2 | Logs estruturados no backend | MVP-MIGRACOES-LOGS | código | Hoje `session.log`/`stdout` em texto livre. |
| 23 | P3 | Corrigir o PRD onde o código decidiu outra coisa | RF04 (3→6 perguntas), RF15 (dependência), RF19 (proposto), RNF06 (#40), CRIPTO-APP-LOCAL (PBKDF2), DADOS-TIMESCALE, DADOS-SYNC-TOKEN, DADOS-MIGRACAO-ROLLBACK, STRIDE-T, DADOS-CACHE-PACIENTE | correção do PRD | Texto velho gera auditoria falsa da próxima vez. |
| 24 | P3 | Integração automática com o SAMU | RF13 | fora-do-mvp | v1.5+ no §6.1. |
| 25 | — | Beta em campo, piloto, NPS | M2.6, M3.5, H1, H2, H3, H4, R4 | externo | Dono: produto + UBS. |
| 26 | — | Revisão jurídica dos termos e do DPO (anonimização, exportação da auditoria) | M3.4, LGPD-RF08, R7, RF17 | externo | Dono: jurídico + DPO. |
