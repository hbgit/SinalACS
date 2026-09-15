# Análise de Cibersegurança — SinalACS

> Referência: NIST Cybersecurity Framework (CSF) 2.0 como estrutura principal,
> complementado por controles do NIST SP 800-53 Rev. 5 onde fez sentido
> detalhar. Ver [issue #1](../../../issues/1).

## 1. Contexto e metodologia

Esta análise é uma revisão estática (leitura de código, configuração e
documentação — sem testes de penetração ativos) do estado do repositório na
revisão avaliada. Cobre:

- `backend/sinalacs_server` (Serverpod/Dart): endpoints, autenticação,
  autorização por microárea, MQTT, banco, auditoria, configuração.
- `apps/acs`, `apps/patient`, `apps/admin` (Flutter): apenas superficialmente,
  focando em como consomem a autenticação do backend.
- `infra/docker`, `backend/DEPLOY.md`: topologia do piloto free-tier.
- `spec/lgpd_design.md`, `spec/PRD_system.md`, `README.md`,
  `.github/SECURITY.md`: requisitos já assumidos pelo projeto, para checar
  aderência técnica.

**Nota importante sobre desatualização da issue**: a issue #1 descreve um
servidor `dart:io` cru (`backend/bin/server.dart`, `postgres_alert_store.dart`)
que já não existe nesta revisão — o backend migrou para o framework
**Serverpod**. Vários pontos levantados na issue já foram endereçados nessa
migração (autenticação JWT HMAC com verificação por endpoint, autorização por
microárea reforçada no banco, MQTT com ACK e outbox transacional, segredos com
fail-closed fora de `development`). Isso é registrado explicitamente abaixo em
cada achado correspondente, para não reabrir como novo o que já foi corrigido
— e para focar o esforço no que **de fato** continua em aberto.

Severidade: **Crítica / Alta / Média / Baixa / Informativa**, considerando que
o projeto é um piloto acadêmico sem dados reais de pacientes (conforme
`README.md` e `.github/SECURITY.md`), não um sistema em produção com dados
sensíveis reais.

## 2. Sumário executivo

| ID | Achado | Função CSF | Severidade | Status |
|----|--------|-----------|------------|--------|
| F1 | Dev-login como único mecanismo de autenticação | PROTECT (PR.AA) | Alta | Conhecido/documentado, sem mitigação |
| F2 | ACL do broker MQTT no piloto não segrega por microárea | PROTECT (PR.DS/PR.AA) | Alta | Regressão dev→piloto, não documentada como risco |
| F3 | TLS do MQTT não é obrigatório por ambiente | PROTECT (PR.DS) | Média | Gap de "fail closed" |
| F4 | Autorização por endpoint é manual, não há enforcement central | PROTECT (PR.AA) | Média/Alta | Débito de arquitetura |
| F5 | Ausência de MFA para ACS | PROTECT (PR.AA) | Média | Gap frente a LGPD-RF11 |
| F6 | Sem rate limiting / anti-automação no `developmentLogin` | PROTECT (PR.AA) | Média | Gap |
| F7 | Gestão de segredos correta em código, mas sem cofre/rotação | PROTECT (PR.DS) | Baixa/Média | Parcialmente mitigado |
| F8 | Sem correlação/alerta de eventos de segurança (SIEM) | DETECT (DE.CM) | Média | Gap |
| F9 | Sem plano de resposta a incidentes / SLA ANPD | RESPOND (RS.MA/RS.CO) | Alta (para LGPD) | Gap |
| F10 | Sem scanning automatizado de dependências | IDENTIFY (ID.RA) | Média | Gap |
| F11 | Drift entre `README.md` e o estado real de segurança | GOVERN (GV.OC) | Informativa | Documentação desatualizada |
| F12 | Sem plano de recuperação/backup testado para o piloto | RECOVER (RC.RP) | Baixa | Gap (aceitável em piloto) |

## 3. Achados detalhados por função do NIST CSF 2.0

### GOVERN (GV)

**F11 — Documentação de postura de segurança desatualizada (Informativa)**
*Categoria:* GV.OC (Contexto organizacional) · *SP 800-53:* PL-2

`README.md`, seção "Segurança e escopo", ainda afirma que "as garantias de
autenticação, autorização por microárea e entrega MQTT com ACK permanecem
pendentes de integração real". Isso não reflete mais o código: `auth_endpoint.dart`
emite JWT HMAC verificado em cada chamada, `orm_alert_store.dart` reforça o
filtro de microárea no predicado SQL (`t.microAreaId.equals(microAreaUuid)`,
linha 109), e `mqtt_alert_dispatcher.dart` + `alert_outbox_dispatcher.dart`
implementam entrega com ACK e retry.

Documentação desatualizada nos dois sentidos é um risco: subestimar a
maturidade atrasa a priorização correta (revisores podem redescobrir o que já
existe); superestimar levaria a assumir garantias que não existem — o que não
é o caso aqui, mas vale manter o README como fonte de verdade viva.

*Recomendação:* atualizar a seção para descrever com precisão o que está
implementado (dev-login JWT + autorização por microárea reforçada no banco)
versus o que continua pendente (autenticação institucional real, MFA, ACL de
microárea no broker gerenciado — ver F1, F2, F5).

**Governança geral (sem achado numerado)**: não há política de segurança
formal além de `.github/SECURITY.md` (que é boa, mas é uma política de
*divulgação de vulnerabilidades*, não de governança de risco). Para o escopo
de um TCC/piloto, isso é proporcional; não recomendamos um programa de GRC
completo, apenas registrar como item de "aceite de risco" formal antes de
qualquer uso com dados reais, dado que `README.md` e `.github/SECURITY.md` já
proíbem dados reais no piloto.

### IDENTIFY (ID)

**F10 — Ausência de scanning automatizado de dependências (Média)**
*Categoria:* ID.RA-01 (vulnerabilidades identificadas e registradas) · *SP 800-53:* RA-5, SA-11

`.github/workflows/ci.yml` roda `dart analyze` e os testes, mas não há
`dependabot.yml`, nem passo de `dart pub outdated`/OSV-Scanner/`govulncheck`
equivalente para o ecossistema Dart, nem verificação de dependências dos apps
Flutter (`apps/acs`, `apps/patient`, `apps/admin`) e dos módulos Node
(`video/remotion`). `backend/sinalacs_server/pubspec.lock` fixa `serverpod:
3.4.13`, `mqtt_client: ^10.0.0`, `crypto: ^3.0.3`, `uuid: ^4.5.0` — não há como
avaliar CVEs conhecidos sem acesso à base do pub.dev/OSV no momento desta
análise; o ponto não é que exista uma vulnerabilidade confirmada, é a
ausência de qualquer processo contínuo para detectá-la.

*Recomendação:* habilitar Dependabot (ou Renovate) para `pubspec.yaml` dos
quatro pacotes Dart e para `video/remotion/package.json`; adicionar um job de
CI que rode `dart pub outdated --mode=null-safety` (ou equivalente) e falhe em
vulnerabilidades conhecidas de severidade alta/crítica.

### PROTECT (PR)

**F1 — Dev-login como único mecanismo de autenticação (Alta)**
*Categoria:* PR.AA-01/03 (identidades e credenciais geridas) · *SP 800-53:* IA-2, IA-5

`auth_endpoint.dart` expõe `developmentLogin(role)`, que emite um token válido
sem senha real para dois UUIDs fixos de seed. É corretamente gateado por
`ENABLE_DEV_LOGIN` (retorna `EndpointDisabledException` como 404, não 403,
para não revelar a rota — boa prática de "fail closed sem vazar existência").
Mas, conforme `backend/DEPLOY.md` ("Limitações conhecidas deste piloto"), esse
é **o único mecanismo de autenticação existente**: "qualquer pessoa com a URL
pode se autenticar como paciente ou ACS". Isso já é conhecido e documentado
pelo projeto — o achado aqui é formalizar a severidade e um caminho de saída.

*Recomendação:* definir e priorizar a integração com identidade institucional
real (ex.: e-SUS APS/CNS para profissionais de saúde, ou um IdP simples com
OAuth2/OIDC para o escopo do TCC) antes de qualquer uso fora do ambiente de
demonstração controlada. Enquanto isso persistir, manter `ENABLE_DEV_LOGIN`
desligado por padrão em qualquer ambiente exposto publicamente (verificar
`backend/DEPLOY.md` para confirmar que a variável não está setada como
`true` no Render).

**F2 — ACL do broker MQTT no piloto não segrega por microárea (Alta)**
*Categoria:* PR.AA-05 / PR.DS-02 (confidencialidade em trânsito, menor
privilégio) · *SP 800-53:* AC-3, AC-6, SC-8

Comparando `infra/docker/mosquitto/aclfile` (ambiente local) com
`backend/DEPLOY.md`: localmente, o Mosquitto aplica ACL por tópico — o usuário
`acs-area-12` só pode ler
`sinalacs/v1/microareas/00000000-.../alerts` da própria microárea. Já no
caminho de deploy documentado (`backend/DEPLOY.md`, seção "Limitações
conhecidas deste piloto"), o broker gerenciado free-tier (HiveMQ Cloud) usa
"usuário/senha único" — sem ACL dinâmica por microárea. Isso é uma
**regressão de confidencialidade entre desenvolvimento e o piloto real**:
qualquer cliente com a credencial única do broker pode assinar
`sinalacs/v1/#` e ver `patientId`, `microAreaId` e `locationHash` de alertas
de **todas** as microáreas, não só a própria — mesmo que o backend e o app do
ACS façam a coisa certa. A invariante de territorialização (INV-01), reforçada
corretamente no banco (`orm_alert_store.dart:106-112`), não se estende ao
transporte MQTT em produção.

*Recomendação:* no curto prazo, documentar explicitamente esse risco residual
em `backend/DEPLOY.md` (hoje ele lista a limitação técnica, mas não o impacto
de confidencialidade que decorre dela). No médio prazo, avaliar um broker
gerenciado com ACL por tópico no tier gratuito (ex.: EMQX Cloud, já citado como
alternativa na mesma tabela do `DEPLOY.md`) ou aplicar criptografia de
payload por microárea antes de publicar, para que a credencial única do
broker não seja suficiente para ler o conteúdo.

**F3 — TLS do MQTT não é obrigatório por ambiente (Média)**
*Categoria:* PR.DS-02 (dados em trânsito) · *SP 800-53:* SC-8, SC-13

`AppConfig.fromMap` (`app_config.dart:84`) lê `mqttUseTls` de
`MQTT_USE_TLS == 'true'`, com default `false`, e não há validação equivalente
à de `JWT_SECRET`/`AUDIT_CHAIN_SECRET` que recuse subir em `APP_ENV=production`
sem essa flag ligada. Ou seja: o padrão de "falhar no boot em vez de na
primeira requisição" — que o próprio time já aplicou corretamente aos
segredos (`_resolveSecret`, `app_config.dart:101-126`) — não foi estendido ao
transporte MQTT. Um operador que esqueça `MQTT_USE_TLS=true` em produção não
recebe erro nenhum; o tráfego (incluindo `locationHash` e IDs de pacientes)
simplesmente vai em texto claro.

*Recomendação:* aplicar a mesma política de fail-closed: `AppConfig` deve
recusar subir com `appEnv != 'development'` e `mqttUseTls == false`, no mesmo
padrão de `_resolveSecret`.

**F4 — Autorização por endpoint é manual, sem enforcement central (Média/Alta)**
*Categoria:* PR.AA-05 (least privilege / segurança por padrão) · *SP 800-53:* AC-3, AC-6

Todos os endpoints (`alerts_endpoint.dart`, `patients_endpoint.dart`,
`visits_endpoint.dart`, `triage_endpoint.dart`, `health_endpoint.dart`)
declaram `requireLogin => false` — abrindo mão do mecanismo de sessão nativo
do Serverpod — e cada método chama manualmente
`AlertRuntime.instance.auth.verifyToken(accessToken)`. Isso funciona hoje
porque todo endpoint que toca dado sensível lembra de chamar `_authenticate`.
Mas é um padrão "seguro por convenção", não "seguro por padrão": nada no
framework impede que um endpoint futuro que manipule dados de saúde seja
adicionado sem essa chamada — ele simplesmente ficaria aberto, e nenhum teste
de tipo pegaria isso automaticamente (só revisão humana ou um teste dedicado).
`triage_endpoint.dart` já é hoje um exemplo de endpoint sem autenticação —
aparentemente intencional (a classificação é determinística e sem dado do
paciente), mas isso reforça que a decisão de "quem precisa de token" está
espalhada, não centralizada.

*Recomendação:* extrair a verificação de token para um método de classe-base
ou um `Endpoint` intermediário (`AuthenticatedEndpoint extends Endpoint`) que
todo endpoint sensível estenda, de forma que esquecer a chamada vire erro de
compilação/design óbvio, não uma omissão silenciosa. Adicionar um teste que
enumere os endpoints e falhe se um novo endpoint com acesso a
`Session.db`/dados de paciente não herdar dessa base.

**F5 — Ausência de MFA para ACS (Média)**
*Categoria:* PR.AA-01 · *SP 800-53:* IA-2(1)

`spec/lgpd_design.md` (LGPD-RF11) já define como critério de aceite "MFA para
ACS", mas a única autenticação existente (F1) não implementa nenhum segundo
fator. Enquanto o dev-login for o mecanismo de autenticação, MFA não é
aplicável tecnicamente; o achado é para não perder o requisito de vista
quando a autenticação institucional (F1) for desenhada.

*Recomendação:* incluir MFA no desenho da autenticação institucional futura
desde já, em vez de tratá-lo como incremento posterior.

**F6 — Sem rate limiting no `developmentLogin` (Média)**
*Categoria:* PR.AA-01 · *SP 800-53:* AC-7, SC-5

`AuthEndpoint.developmentLogin` não tem limite de tentativas nem
throttling — hoje isso importa pouco porque não há senha para forçar (o
`role` só aceita `patient`/`acs`), mas o padrão importa: quando a
autenticação real (F1) substituir isso, o mesmo endpoint (ou seu sucessor)
precisa nascer com rate limiting, para não repetir a lacuna.

*Recomendação:* tratar como pré-requisito de design da autenticação
institucional, não como item avulso.

**F7 — Gestão de segredos correta em código, sem cofre/rotação (Baixa/Média)**
*Categoria:* PR.DS-01 · *SP 800-53:* SC-12, SC-28

Ponto positivo a registrar: `AppConfig._resolveSecret`
(`app_config.dart:101-126`) já faz o que a maioria dos projetos deste porte
não faz — recusa subir em `staging`/`production` sem `JWT_SECRET`/
`AUDIT_CHAIN_SECRET` próprios, e recusa mesmo que alguém copie o valor de
desenvolvimento para outro ambiente por engano. O `.gitignore` protege
`config/passwords.yaml`, e o CI corrigiu recentemente
(`ci.yml`, comentário nas primeiras linhas do job) uma senha de teste que
estava compartilhada com o arquivo local gitignorado. O que falta é só
maturidade operacional: os segredos hoje vivem como variáveis de ambiente
simples no Render, sem cofre dedicado (Vault, AWS/GCP Secret Manager) nem
rotação programada.

*Recomendação:* aceitável para o estágio de piloto; registrar como item de
hardening antes de produção real, não como bloqueador agora.

### DETECT (DE)

**F8 — Sem correlação/alerta de eventos de segurança (Média)**
*Categoria:* DE.CM-01/03 (monitoramento contínuo) · *SP 800-53:* AU-6, AU-12, SI-4

A issue original afirmava que "o backend só usa `print`" — isso está
desatualizado: a migração para Serverpod trouxe `sessionLogs` estruturados
(`config/*.yaml`, `consoleLogFormat: json` em produção) e um serviço de
auditoria dedicado, `AuditTrail` (`audit_trail.dart`), que grava eventos
`granted`/`denied_territory` de acesso a dado sensível numa trilha
append-only com cadeia de hash (`auditChainSecret`) — desenhada
especificamente para atender "logs de acesso com quem, quando e quais dados"
(LGPD-RF11) e o alerta de tentativa de acesso fora da microárea. Isso é uma
base sólida que a issue não previa.

O que continua faltando é a camada seguinte: não há nada que **leia** essa
trilha e gere alerta ativo (ex.: N tentativas de `denied_territory` do mesmo
usuário em M minutos), nem centralização fora do host do Render (que
hiberna e não retém logs entre reinícios de forma confiável, conforme
`backend/DEPLOY.md`). Falhas de auditoria também só vão para
`stderr.writeln` (`audit_trail.dart:58`), sem alerta.

*Recomendação:* para o escopo do piloto, o mínimo viável é exportar
`sessionLogs` e a tabela `audit_logs` para um destino persistente fora do
Render (mesmo que seja um job periódico simples), e alertar manualmente sobre
`denied_territory` como parte da rotina do responsável técnico enquanto não
houver orçamento para uma ferramenta de SIEM.

### RESPOND (RS)

**F9 — Sem plano de resposta a incidentes / SLA de notificação (Alta para conformidade LGPD)**
*Categoria:* RS.MA-01, RS.CO-02 · *SP 800-53:* IR-1, IR-4, IR-6

`.github/SECURITY.md` cobre bem a **divulgação coordenada de
vulnerabilidades** (relato privado, prazo de confirmação em 5 dias úteis,
divulgação em até 90 dias) — mas o próprio documento é explícito sobre seu
limite: "não substitui... resposta a incidentes. Um evento real que envolva
dados pessoais ou de saúde pode exigir medidas adicionais". `spec/lgpd_design.md`
(LGPD-RF12) já formaliza a obrigação legal: notificação à ANPD e aos
titulares em até 72h (legal) / 48h (recomendado), com "capacidade de
identificar titulares afetados em até 24 horas" — nenhum desses processos
está documentado ou testado.

*Recomendação:* redigir um runbook curto de resposta a incidentes
(quem aciona, como isolar o `ENABLE_DEV_LOGIN`/rotacionar segredos em
minutos, como consultar `audit_logs` para escopo do incidente, template de
comunicação à ANPD/titulares) — não precisa ser extenso dado o estágio do
projeto, mas precisa existir antes de qualquer piloto com usuários reais,
mesmo que sintéticos por enquanto.

### RECOVER (RC)

**F12 — Sem plano de recuperação/backup testado (Baixa)**
*Categoria:* RC.RP-01 · *SP 800-53:* CP-9, CP-10

`backend/DEPLOY.md` documenta bem as limitações de disponibilidade do piloto
free-tier (hibernação do Render, autosuspend do Neon), mas não há menção a
backup do Postgres (Neon free tier) nem a um teste de restauração. Para um
piloto sem dados reais, a severidade é baixa; registrar como item a resolver
antes de qualquer dado real trafegar pelo sistema.

*Recomendação:* documentar a política de retenção/backup do Neon (mesmo que
seja "o free tier não garante backup, logo nenhum dado real deve trafegar
aqui" — o que já é consistente com o restante da política do projeto).

## 4. Priorização recomendada

1. **Antes de qualquer dado real (bloqueadores)**: F1 (autenticação
   institucional), F2 (ACL do broker MQTT no piloto), F9 (runbook de
   incidentes com SLA de notificação).
2. **Curto prazo, baixo custo de implementação**: F3 (fail-closed de TLS no
   MQTT), F4 (endpoint base com autenticação obrigatória), F11 (atualizar
   README).
3. **Médio prazo**: F5 (MFA), F6 (rate limiting), F10 (scanning de
   dependências no CI).
4. **Hardening contínuo, sem bloquear o piloto**: F7 (cofre de segredos), F8
   (alerta ativo sobre a trilha de auditoria), F12 (backup/restore).

## 5. Referências

- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework)
- [NIST SP 800-53 Rev. 5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)
- [`CLAUDE.md`](../CLAUDE.md) — invariantes de negócio/segurança (INV-01,
  INV-02, INV-03)
- [`spec/lgpd_design.md`](lgpd_design.md) — LGPD-RF09, RF11, RF12, RF13
- [`spec/PRD_system.md`](PRD_system.md) — seção 6.2 (M3.2 observabilidade,
  M3.4 LGPD Compliance)
- [`backend/DEPLOY.md`](../backend/DEPLOY.md) — limitações conhecidas do
  piloto free-tier
- [`.github/SECURITY.md`](../.github/SECURITY.md) — política de divulgação
  de vulnerabilidades
