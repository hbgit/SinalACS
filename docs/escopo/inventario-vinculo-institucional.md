# Inventário — o que pressupõe vínculo institucional (2026-11-01)

Levantamento que embasa o diagnóstico D1–D12 de
[`docs/superpowers/plans/2026-11-01-escopo-educativo-aberto.md`](../superpowers/plans/2026-11-01-escopo-educativo-aberto.md)
e as soluções do [registro de decisões](decisoes-2026-11-01.md).

**Fora do inventário:** histórico (`PROGRESS.md`, planos, auditorias datadas em
`docs/auditoria-prd/` e `docs/ci-audit/`) não entra: é registro, não
especificação. Também ficam de fora as ocorrências técnicas sem relação com
vínculo institucional (ex.: `192.168.0.10` como IP de exemplo em
`.env.example`, `docker-compose.yml` e `video/README.md`).

**Como reproduzir** (comando puro, sem ferramentas do ambiente original):

```bash
git --no-pager grep -nIiE 'e-SUS|eSUS|CNES|\bCNS\b|CADSUS|RNDS|DATASUS|SISAB|Gov\.br|ICP-Brasil|\bUBS\b|Secretaria|prefeitura|munic[ií]pi|matr[ií]cula|SAMU|\b192\b|Pulumi|cert-manager|Fluentd|SMS|Manchester|Play Store|Google Play' -- '*.md' '*.yaml' '*.yml' '.env.example' 'apps/*/lib/*.dart' 'apps/*/lib/**/*.dart' ':!PROGRESS.md' ':!docs/superpowers/**' ':!docs/ci-audit/**' ':!docs/auditoria-prd/**' ':!docs/escopo/**' ':!graphify-out/**'
```

Em 2026-11-01 o comando devolveu 408 linhas; abaixo estão agrupadas por
parágrafo ou por tema. Destino: **reescrever** (documento muda neste ciclo),
**Futuro** (remetido a `spec/trabalhos_futuros.md`) ou **C-NN** (mudança de
código recomendada, ver `docs/escopo/mudancas-de-codigo-recomendadas.md`).

| ID | Arquivo:linha | Trecho resumido | Tipo | Destino |
|---|---|---|---|---|
| I-01 | `spec/PRD_system.md:14` | "Problema Central": visitas domiciliares da Atenção Primária; e-SUS APS como registro passivo | D1 | reescrever |
| I-02 | `spec/PRD_system.md:29,117,151,451` | Motor "inspirado no Protocolo de Manchester"; RF16 "(Manchester)" | D1 | reescrever |
| I-03 | `spec/idea.md:8-9` | Conceito: substituir o modelo de visitas; e-SUS APS como concorrente | D1 | reescrever |
| I-04 | `spec/sys_flow.md:16` | Plataforma de triagem para a Atenção Primária | D1 | reescrever |
| I-05 | `CLAUDE.md:7`, `AGENTS.md:15` | Visão geral: priorização de visitas da Atenção Primária | D1 | reescrever |
| I-06 | `docs/roteiro-video-sponsor.md:17,42,44`, `docs/showcase/slides.md:43` | e-SUS APS como "moat" | D1 | reescrever |
| I-07 | `spec/PRD_system.md` §1.2 (H1, H3) e §1.3 (TMRAV, aderência, visitas/dia) | Hipóteses e métricas medidas dentro de uma UBS | D2 | Futuro |
| I-08 | `spec/PRD_system.md:563-564` | Dimensionamento "2 UBS × 2.500 pacientes", "2 UBS × 50 ACS" | D2 | Futuro |
| I-09 | `spec/PRD_system.md` RF03, INV-03, RF19; §6.1 "Alerta chega ao ACS em < 2s" | Botão de urgência que promete resposta | D3 | reescrever |
| I-10 | `docs/telas-paciente.md:29` | Status do alerta com "classificação de risco" e "Atendido" | D3 | reescrever; C-04 |
| I-11 | `spec/ux_ui_test_plan.md:57` | Botão "pânico" | D3 | Futuro (texto do plano de teste antigo) |
| I-12 | `spec/PRD_system.md:136,1010` | RF01 CPF + SMS OTP | D7 | Futuro (P-10) |
| I-13 | `spec/PRD_system.md:142,1014`, `README.md:26,181`, `apps/acs/README.md:3`, `apps/admin/README.md:3` | Login "institucional" por matrícula | D4 | reescrever (identificador emitido pelo projeto) |
| I-14 | `spec/idea.md:35` | Matrícula da Secretaria de Saúde ou Gov.br | D4 | Futuro |
| I-15 | `docs/telas-acs.md:13`, `docs/telas-admin.md:13`, `docs/showcase/slides.md:190-192` | "matrícula/CNS", SSO/gov.br no roadmap | D4 | reescrever; Futuro |
| I-16 | `spec/PRD_system.md:104,336-436,587-595` | "Gestão de UBS"; modelo `UBS employs ACS`; coordenador (UBS) | D4 | reescrever (UBS = grupo do piloto) |
| I-17 | `docs/telas-admin.md:28,40,46,55,65,75` | Indicadores, microáreas, alertas e auditoria "da UBS" | D4 | reescrever |
| I-18 | `docs/telas-acs.md:59`, `spec/lgpd_design.md:590` | Wipe "pela coordenação da UBS" | D4 | reescrever |
| I-19 | `spec/lgpd_data_audit.md:165-185` | Tabela `ubs` como unidade de saúde, lotação institucional | D4 | reescrever (aviso no topo) |
| I-20 | `backend/sinalacs_server/lib/src/models/ubs.spy.yaml`, `staff_account.spy.yaml`, `api/admin_*.spy.yaml`, `api/ubs_contact.spy.yaml` | Modelo de dados com UBS e matrícula | D4 | C-06 (dívida técnica) |
| I-21 | `apps/patient/lib/app/app.dart:1966,2035` | "A equipe da UBS analisa o pedido", "Avisos da UBS" | D4 | C-06 |
| I-22 | `apps/acs/lib/app/device_wiped_screen.dart:46-47` | "a pedido da coordenação da UBS", "alertas continuam com a equipe da UBS" | D4 | C-06 |
| I-23 | `apps/admin/lib/app/app.dart:341,716`, `admin_accounts.dart:421,507,681`, `audit_log_screen.dart:498`, `core/data/mock_admin_data_source.dart:112` | Rótulos "UBS" no backoffice | D4 | C-06 |
| I-24 | `apps/acs/lib/app/app.dart` (login e textos), `apps/admin/lib/app/login_screen.dart`, `mfa_enrollment_screen.dart` (ACS e admin) | Rótulo "Matrícula" no login | D4 | C-06 (texto); identificador mantém o nome técnico |
| I-25 | `spec/PRD_system.md:111,148,1026`, `spec/idea.md:39` | RF13 Escalonamento para SAMU/UBS; integração SAMU | D5 | Futuro |
| I-26 | `apps/acs/lib/app/app.dart:4017,4051`, `apps/acs/lib/core/services/emergency_dialer.dart`, `apps/acs/pubspec.yaml:34` | Botão "Ligar para a UBS" ao lado de 192 | D5 | C-07 |
| I-27 | `docs/telas-acs.md:47`, `docs/showcase/slides.md:273-276`, `docs/roteiro-video-sponsor.md:153-154,167` | Ações de SAMU ou UBS no app do ACS | D5 | reescrever; Futuro |
| I-28 | `spec/lgpd_design.md:132,259,374` | Compartilhamento com SAMU, UBS, Secretaria; integrações Gov.br | D6 | Futuro |
| I-29 | `spec/lgpd_design.md:501,850` | Secretaria como controlador e como solicitante de relatórios | D6 | reescrever |
| I-30 | `apps/patient/lib/core/legal/legal_documents.dart:113,126,131,145,185,216` | Controlador e DPO "da Secretaria", "sua UBS", SAMU | D6 | C-01 |
| I-31 | `.env.example:212-216`, `docker-compose.e2e.yml:18`, `backend/sinalacs_server/lib/src/models/otp_challenge.spy.yaml:4` | `SMS_GATEWAY` obrigatório fora de development | D7 | **C-05 (issue #128):** a exigência caiu — ausente fora de `development` vale desligado |
| I-32 | `spec/idea.md:21`, `spec/sys_flow.md:22`, `docs/roteiro-video-sponsor.md:53` | Acesso por CPF + SMS | D7 | Futuro |
| I-33 | `spec/PRD_system.md:1070,1082,1346` | Risco R6 dependência de SMS Gateway; custo de SMS | D7 | Futuro |
| I-34 | `spec/stack.md:18`, `spec/sys_flow.md:29`, `README.md:319`, `spec/PRD_system.md:127,1055,1163-1174,1338` | Pulumi em "VPS robustas" | D8 | Futuro |
| I-35 | `spec/PRD_system.md:158`, `backend/DEPLOY.md:6,111,199` | cert-manager, autenticação institucional real como requisito | D8 | reescrever |
| I-36 | `spec/PRD_system.md:1182,1298-1305` | Compose de produção, Fluentd | D8 | Futuro |
| I-37 | `spec/test_plan.md:60,128,161` | MQTT via WebSockets no Traefik, Traefik redundante, "corte de rede na UBS" | D8 | Futuro |
| I-38 | `docs/publicacao-google-play.md` (todo), `docs/README.md:8`, `spec/stack.md:74` | Publicação na Google Play; Managed Google Play institucional | D8 | Futuro (distribuição por APK no piloto) |
| I-39 | `spec/idea.md:105`, `spec/PRD_system.md:1059` | Piloto com 2–3 ACS em uma única UBS; "1 UBS piloto" | D9 | Futuro; `spec/plano_piloto.md` |
| I-40 | `docs/roteiro-video-sponsor.md:125-136`, `docs/showcase/slides.md:399` | "1 UBS · 2 microáreas · 50 pacientes" | D9 | Futuro |
| I-41 | `spec/PRD_system.md:1068` | Risco R4 com dono "UBS" | D9 | Futuro |
| I-42 | `spec/security_assessment.md:124` | IdP real "e-SUS APS/CNS" | D10 | Futuro |
| I-43 | `LICENSE:3` | "Copyright (c) 2026 Herbert" | D11 | P-01 (condicional) |
| I-44 | `.github/CODE_OF_CONDUCT.draft.md` | Código de conduta em rascunho, sem contato | D11 | P-06 |
| I-45 | `README.md`, `spec/PRD_system.md` (topo) | Nenhum aviso de conteúdo educativo | D12 | reescrever |
| I-46 | `docs/publicacao-google-play.md:441,701-704` | Aviso de que o app não substitui o SAMU existe só para a loja | D12 | reescrever |
| I-47 | `AGENTS.md:94`, `CLAUDE.md:112`, `backend/CLAUDE.md:105`, `spec/stack.md:6`, `spec/idea.md:27`, `spec/sys_flow.md:213`, `spec/test_plan.md:9,133`, `spec/lgpd_design.md:436`, `docs/showcase/slides.md:38`, `docs/showcase/preview.html:16`, `spec/ui_acs/acs_3_dashboard_priorizacao.html:38`, `spec/ui_paciente/paciente_3_triagem.html:41`, `docs/publicacao-google-play.md:701` | "Manchester" em texto de produto e regras de trabalho | D1 | reescrever (M-05) |
| I-48 | `backend/sinalacs_server/lib/src/endpoints/triage_endpoint.dart:7`, `backend/sinalacs_client/lib/src/protocol/client.dart:1291`, `video/roteiro.timing.json:140` | "Manchester" em código e roteiro de vídeo | D1 | C-09 |
