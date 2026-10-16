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
| RF07 | Login institucional (matrícula + senha) | **a-verificar** | | |
| RF08 | Territorialização (cache da microárea) | **a-verificar** | | |
| RF09 | Dashboard de priorização dinâmica | **a-verificar** | | |
| RF10 | Mapa interativo | **a-verificar** | | |
| RF11 | Registro rápido de visitas offline-first | **a-verificar** | | |
| RF12 | Geofencing (check-in passivo) | **a-verificar** | | |
| RF13 | Escalonamento para SAMU/UBS | **a-verificar** | | |
| RF14 | Avisos segmentados à comunidade (push) | **a-verificar** | | |
| RF15 | Sincronização bidirecional | **a-verificar** | | |

## Núcleo, auditoria e backoffice

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| RF16 | Motor de triagem determinístico (Manchester) | **a-verificar** | | |
| RF17 | Logs de auditoria e conformidade | **a-verificar** | | |
| RF19 | Escalonamento de alerta vermelho sem confirmação | **a-verificar** | | |
| RNF06 | RBAC | **a-verificar** | | |

### Módulos do backoffice (§2.1)

| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| MOD-UBS | Gestão de UBS | **a-verificar** | | |
| MOD-ACS | Gestão de ACS | **a-verificar** | | |
| MOD-RELATORIOS | Relatórios | **a-verificar** | | |
| MOD-AUDITORIA | Auditoria | **a-verificar** | | |
| MOD-CONFIG | Configurações de sistema | **a-verificar** | | |

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
