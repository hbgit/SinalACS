# Classificação das issues — milestones "Pilot" e "v1.0"

Documento de revisão de 2026-11-02. **Nada aqui foi aplicado no GitHub;
aplicar exige aprovação explícita desta tabela.** Plano:
[`docs/superpowers/plans/2026-11-02-milestones-issues.md`](../superpowers/plans/2026-11-02-milestones-issues.md).

Fontes do escopo:
[`spec/escopo_projeto.md`](../../spec/escopo_projeto.md) ·
[`spec/requisitos_piloto.md`](../../spec/requisitos_piloto.md) ·
[`spec/plano_piloto.md`](../../spec/plano_piloto.md) ·
[`spec/trabalhos_futuros.md`](../../spec/trabalhos_futuros.md) ·
[`docs/escopo/mudancas-de-codigo-recomendadas.md`](mudancas-de-codigo-recomendadas.md).

**Critérios.** Pilot = pronto antes da primeira coleta com participantes
(portão de segurança e legal, portão funcional, requisitos Essenciais,
distribuição). v1.0 = Desejáveis, mudanças fora do portão, melhorias e
correções pós-piloto. `futuro` = listado em `spec/trabalhos_futuros.md`
(sem milestone, issue segue aberta). `a-decidir` = não se encaixa, ou
conflito entre `futuro` e um controle de segurança Essencial.

Inventário: 20 issues abertas em 2026-11-02, nenhuma milestone, rótulos
existentes `privacy`, `security`, `enhancement`, `documentation`,
`accessibility` (entre outros). Rótulos novos propostos: `futuro`,
`a-decidir`, `acao-equipe`.

## Divergências

1. **Portão de segurança e legal.** O pedido de 2026-11-02 cita C-01–C-10;
   `spec/plano_piloto.md` inclui também C-11 (autoavaliação local) e C-12
   (revogação na recuperação de acesso). Vale o plano do piloto: o portão é
   C-01, C-02, C-04, C-05, C-06, C-08, C-10, C-11 e C-12; o funcional é C-03.
2. **#96 vai para `a-decidir`, não para `futuro`.** Está em
   `spec/trabalhos_futuros.md`, mas protege a integridade da trilha de
   auditoria (RF17, Essencial) com dados reais de participantes. As duas
   justificativas estão na Tabela; a equipe decide.
3. **#114 em Pilot.** O PR #115 que a cita é só documentação (nota da #90
   apontando para a #114); a regressão do e2e continua aberta.
4. **#103:** a correção entrou em `develop` (PRs #105 e #106; #107 é
   documentação), mas o aceite está pendente; vai para v1.0 como entregue.
5. **Cobertura dos Essenciais revelou duas lacunas fora dos C-NN:** RNF03 no
   app do paciente (lembretes e consentimentos ficam em SQLite sem cifra; o
   app não usa `sqflite_sqlcipher` em `lib/` nem tem PIN) e RNF05 nas telas
   novas do piloto. Viraram as issues N13 e N14.
6. **RF17 não está implementado de fato.** O encadeamento existe
   (`audit_chain_test.dart`), mas a imutabilidade no banco não tem efeito
   enquanto o backend conectar como dono das tabelas: é exatamente a #96
   ("para o REVOKE da auditoria valer"). Na Cobertura, RF17 é `issue` com
   evidência #96; a #96 continua `a-decidir` e é a única pendência de um
   requisito Essencial.
7. **Prazo de 30 dias da retenção local não é decisão da equipe.** Foi
   proposto no plano de 2026-11-01 e registrado em `spec/requisitos_piloto.md`
   (§ INV-03 no piloto) e em C-10 como "prazo proposto, ajustável no TCLE".
   A N8 cita essa origem; o prazo final depende do TCLE (P-04).
8. **P-13 passa a bloquear o piloto.** Sem responsável pela chave de
   assinatura não há APK de release (RNF07). Em `spec/escopo_projeto.md`, a
   coluna "Bloqueia o piloto?" da P-13 passa de "Não" para "Sim (RNF07)" e a
   tabela de ações ganha a linha da P-13; a ação vira a issue N25.
9. **#111 e #117 em Pilot, condicionadas ao RF03 ativo.** RF03 é Desejável,
   mas, com o pilar B no piloto e o pedido de contato existindo (C-04 está no
   portão), a INV-03 vale para todo pedido enviado; um ACK atribuído ao agente
   errado pode fazer um pedido parecer atendido. Se a equipe tirar o RF03 do
   piloto, as duas voltam para v1.0.
10. **#100 e #101 em Pilot.** `telemetry_events` é a fonte da meta de
    sincronização (H4); eventos descartados ou perdidos sem aviso tornam a
    métrica não confiável. A #100 é a essencial; se a equipe preferir, a #101
    pode voltar para v1.0.
11. **Prefixo das ações da equipe.** As issues existentes usam `[P0]`–`[P3]`
    como prioridade; as ações usam `[Ação P-NN]` para não se confundirem.
12. **Títulos de #77 e #118** perdem o prefixo de prioridade (`[P0]`,
    `[P1]`), que dizia "prioridade alta" para algo fora do piloto; o rótulo
    `futuro` já carrega a classificação.

## Tabela

| # | Título | Milestone | Rótulos a adicionar | Justificativa | Ação | Situação |
|---|---|---|---|---|---|---|
| 118 | [P1] PKI de produção da CA de aparelhos (escopo 5 da #94) | — | `futuro` | `spec/trabalhos_futuros.md` § Distribuição e infraestrutura de produção (#118); a CA do piloto tem dono na N12 | bloco de escopo | aberta |
| 117 | [P2] ACK com identidade de aparelho | Pilot | — | INV-03 vale para todo pedido de contato enviado (C-04 no portão); condicionada ao RF03 ativo no piloto — se sair, volta para v1.0 | manter | aberta |
| 116 | [P3] Chave do certificado do aparelho no TEE | — | `futuro` | `spec/trabalhos_futuros.md` (#116) | rotular futuro | aberta |
| 114 | acs_full_e2e.sh: primeiro teste falha no tap em sync_visits | Pilot | — | RF08 e RF11 Essenciais: e2e do fluxo do agente | manter | aberta |
| 111 | ACK de um segundo ACS: avisar o app | Pilot | — | INV-03 vale para todo pedido de contato enviado (C-04 no portão); condicionada ao RF03 ativo no piloto — se sair, volta para v1.0 | manter | aberta |
| 103 | android-e2e: notificação FCM não chega à bandeja | v1.0 | — | RF14 Desejável | manter | entregue em develop (PRs #105, #106); aceite pendente |
| 102 | [P2] Métricas do §1.3 no backoffice | v1.0 | — | melhoria pós-piloto; as métricas do piloto vêm de `telemetry_events` e dos questionários (`spec/plano_piloto.md` § Métricas) | bloco de escopo | aberta |
| 101 | [P3] Reemitir alert_triggered/alert_received_acs perdidos | Pilot | — | eventos perdidos tornam não confiável a métrica de sincronização (H4) do piloto; pode voltar para v1.0 se a equipe preferir (a #100 cobre o essencial) | manter | aberta |
| 100 | [P3] Sinalizar eventos de telemetria descartados | Pilot | — | sem a sinalização não se sabe quanto se perdeu: a métrica de sincronização ≥ 99,5% (H4, RNF02) deixa de ser confiável | manter | aberta |
| 99 | [P2] Evento de onboarding sem assistência (H2) | v1.0 | — | H2 é medida por observação no piloto (`spec/plano_piloto.md` § Métricas); o roteiro de observação está na N24 | manter | aberta |
| 96 | [P2] Separar papéis do Postgres (RF17) | — | `a-decidir` | (a) está em `spec/trabalhos_futuros.md` (#96); (b) é a única pendência do RF17, Essencial: sem ela o REVOKE da auditoria não vale e o papel da aplicação ainda altera registros | a decidir | aberta |
| 94 | [P1] Certificado de cliente MQTT por aparelho | Pilot | — | RNF04 Essencial | manter | entregue em develop (PR #119) |
| 90 | mTLS Traefik ↔ backend | Pilot | — | RNF04 Essencial | manter | entregue em develop (PR #113) |
| 88 | ACK repetido reescreve o ACS do alerta | v1.0 | — | RF03 Desejável; INV-03 | manter | entregue em develop (PR #112) |
| 87 | Backoffice sem contador "Concluídos" (RF05) | v1.0 | — | RF05 Desejável | bloco de escopo | entregue em develop (PRs #108, #109, #110) |
| 86 | ACK de alerta já concluído (RF05) | v1.0 | — | RF05 Desejável | manter | entregue em develop (PR #104) |
| 83 | [P1] Telemetria estruturada dos eventos do §1.3 | Pilot | — | fonte da métrica de sincronização (H4) do piloto | manter | entregue em develop (PR #98) |
| 81 | [P1] Remote wipe e certificado de cliente por aparelho | Pilot | — | encerramento do piloto apaga os aparelhos dos agentes (M-04) | manter | entregue em develop (PR #93) |
| 77 | [P0] Envio do OTP por SMS real (RF01) | — | `futuro` | `spec/trabalhos_futuros.md` "RF01 com CPF e SMS"; P-10 aprovada (sem CPF, SMS ou e-mail) | bloco de escopo | aberta |
| 15 | docs: guia para publicar app na Google Play Store | — | `futuro` | `spec/trabalhos_futuros.md` (Play Store); piloto usa APK em GitHub Releases (RNF07) | rotular futuro | aberta |

Resumo: Pilot 9 (#117, #114, #111, #101, #100, #94, #90, #83, #81) · v1.0 6 (#103, #102, #99, #88, #87, #86) · `futuro` 4 (#118, #116, #77, #15) · `a-decidir` 1 (#96). Issues novas: 25 (N1–N25) — 22 em Pilot (14 de código ou documentação e 8 ações da equipe) e 3 em v1.0.

## Para a equipe decidir

| # | Pergunta | Justificativa (a) | Justificativa (b) | Responsável |
|---|---|---|---|---|
| 96 | Pilot, v1.0 ou futuro? | está em `spec/trabalhos_futuros.md` | única pendência do RF17 (Essencial): sem ela o REVOKE da auditoria não vale | `[A DEFINIR]` |
| 111, 117 | O RF03 (pedido de contato) fica ativo no piloto? | se sim, Pilot (INV-03 sobre todo pedido enviado) | se não, voltam para v1.0 | `[A DEFINIR]` |
| 101 | Pilot ou v1.0? | Pilot: eventos perdidos afetam a métrica H4 | v1.0: a #100 já cobre o essencial | `[A DEFINIR]` |

## Cobertura dos Essenciais

| ID | Requisito | Situação | Evidência |
|---|---|---|---|
| RF02 | Onboarding por QR | implementado | `apps/patient/test/enrollment_qr_test.dart`, `apps/patient/test/qr_scanner_test.dart` |
| RF04 | Autoavaliação estruturada | lacuna | N7 (C-08), N9 (C-11) |
| RF06 | Lembretes locais | implementado | `apps/patient/test/reminders/reminder_scheduler_test.dart` |
| RF07 | Login do agente | implementado | `backend/sinalacs_server/test/integration/institutional_login_test.dart` (identificador opaco + senha + bloqueio; o teste não supõe matrícula da Secretaria) |
| RF08 | Territorialização | implementado | `apps/acs/test/micro_area_cache_store_test.dart`, `backend/sinalacs_server/test/integration/patient_directory_and_territory_test.dart` |
| RF09 | Fila priorizada | implementado | `apps/acs/test/alert_queue_merge_test.dart` |
| RF10 | Mapa | implementado | `apps/acs/integration_test/map_flow_test.dart` |
| RF11 | Visita offline | implementado | `apps/acs/test/visit_owner_flow_test.dart`, `apps/acs/test/offline_visit_queue_conflict_test.dart`; regressão do e2e em #114 |
| RF15 | Sincronização | implementado | `apps/acs/test/visit_pull_service_test.dart`, `backend/sinalacs_server/test/unit/sync_fsm_test.dart` |
| RF16 | Motor determinístico | implementado | `backend/sinalacs_server/test/unit/triage_engine_test.dart` |
| RF17 | Auditoria | issue | #96 (`a-decidir`): sem a separação de papéis o REVOKE não vale; o encadeamento está em `backend/sinalacs_server/test/unit/audit_chain_test.dart` |
| RF20 | Conteúdo educativo offline | lacuna | N3 (C-03) |
| RF21 | Aviso educativo | lacuna | N2 (C-02), N1 (C-01) |
| RF22 | Uso sem cadastro | lacuna | N3 (C-03), N9 (C-11) |
| RF24 | Acesso sem CPF/SMS/e-mail e recuperação | lacuna | N5 (C-05), N10 (C-12) |
| RNF02 | Sincronização offline | implementado | `apps/acs/test/offline_visit_queue_concurrency_test.dart`; medição em #83, confiabilidade da medição em #100 e #101 |
| RNF03 | Cifra em repouso | lacuna | N13 (app do paciente); no agente, `apps/acs/test/encrypted_database_test.dart` |
| RNF04 | TLS 1.3 | implementado | `scripts/qa/tls_invariants.sh`, `scripts/qa/mtls_invariants.sh`; #90, #94 |
| RNF05 | Acessibilidade WCAG AA | lacuna | N14 (fluxos do piloto, novos ou não); contraste atual: `apps/patient/test/contrast_tokens_test.dart` |
| RNF06 | RBAC | implementado | `backend/sinalacs_server/test/unit/authorization_test.dart` |
| RNF07 | Implantável por terceiros | lacuna | N11 (APK), N12 (compose), N25 (custódia da chave, P-13) |
| RNF08 | Sem serviço pago obrigatório | lacuna | N5 (C-05 retira a exigência de `SMS_GATEWAY`) |
| RNF09 | Coleta mínima | lacuna | N9 (C-11), N5 (C-05), N8 (C-10) |
| RNF10 | pt-BR, MIT e CC BY 4.0 | implementado | `README.md`, `LICENSE` |

## Issues novas

### N1 — [C-01] Texto legal do app do paciente: controlador, encarregado e aviso educativo
Milestone: Pilot
Rótulos: `privacy`
<!-- corpo -->
## Objetivo
Atualizar o texto legal do app do paciente: controlador e encarregado conforme a decisão aprovada P-02, sem "da Secretaria" nem "sua UBS", e com o aviso educativo canônico longo.

## Critério de aceite
- [ ] `apps/patient/lib/core/legal/legal_documents.dart` sem "Secretaria" nem "UBS".
- [ ] Aviso educativo longo copiado literalmente de `spec/escopo_projeto.md#aviso-educativo`.
- [ ] Nova `LegalVersion` e novo `consentPolicyVersion`.
- [ ] Nome e contato do encarregado: `[A DEFINIR]` até a ação de P-02 concluir.

## Referências
IDs: C-01, RF21, P-02
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: P-02 (nome e contato do encarregado)
<!-- /corpo -->

### N2 — [C-02] Aviso educativo na primeira abertura e em "Sobre"
Milestone: Pilot
Rótulos: `enhancement`
<!-- corpo -->
## Objetivo
Mostrar o aviso educativo canônico na primeira abertura e numa tela "Sobre" dos apps do paciente e do agente.

## Critério de aceite
- [ ] Primeira abertura exibe o aviso curto e só segue após confirmação.
- [ ] Tela "Sobre" exibe o aviso longo, copiado literalmente.
- [ ] Teste de widget para as duas telas nos dois apps.

## Referências
IDs: C-02, RF21
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#aviso-educativo
Bloqueado por: —
<!-- /corpo -->

### N3 — [C-03] Biblioteca de conteúdo educativo offline (pilar A)
Milestone: Pilot
Rótulos: `enhancement`
<!-- corpo -->
## Objetivo
Biblioteca de conteúdo educativo no app do paciente, offline e sem login, com fontes citadas (portão funcional, obrigatório se o pilar A estiver no piloto).

## Critério de aceite
- [ ] Conteúdo disponível sem conta e sem rede.
- [ ] Cada tema cita a fonte (Ministério da Saúde ou BVS).
- [ ] A pasta do conteúdo traz aviso de licença CC BY 4.0 com atribuição; a tela "Sobre" indica código MIT e conteúdo CC BY 4.0.
- [ ] Temas e revisores conforme a ação de P-07.

## Referências
IDs: C-03, RF20, RF22, P-07
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: P-07 (lista de temas e revisores)
<!-- /corpo -->

### N4 — [C-04] Pedido de contato sem rótulo de urgência e saída "Ligar 192" sem envio
Milestone: Pilot
Rótulos: `enhancement`
<!-- corpo -->
## Objetivo
Transformar o alerta do paciente em pedido de contato com o agente participante, sem rótulo de urgência; a saída "Ligar 192" da autoavaliação não gera pedido e fica registrada numa trilha local cifrada (a criar).

## Critério de aceite
- [ ] "Ligar 192" aparece antes de qualquer pedido de contato.
- [ ] A saída "Ligar 192" exige escolha explícita para fechar e grava um evento local cifrado.
- [ ] O status não usa "Atendido" como promessa.
- [ ] Testes: pedido enviado nunca some (testes de INV-03 seguem verdes); a saída 192 grava o evento local e não chama `alerts.createRedAlert`.

## Referências
IDs: C-04, RF03, RF05, P-09, INV-03
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/requisitos_piloto.md#inv-03-no-piloto
Bloqueado por: N13 (cifra local do evento)
<!-- /corpo -->

### N5 — [C-05] Acesso do participante sem CPF, SMS ou e-mail (RF24)
Milestone: Pilot
Rótulos: `privacy`
<!-- corpo -->
## Objetivo
Login do participante por convite QR + PIN local, com identificador pseudônimo, sem CPF, SMS ou e-mail; cria a credencial de dispositivo do participante. Retira a exigência de `SMS_GATEWAY` fora de `development`.

## Critério de aceite
- [ ] O login não usa e-mail, CPF nem telefone.
- [ ] Credencial de dispositivo vinculada ao identificador pseudônimo e protegida pelo PIN local.
- [ ] O backend sobe no perfil do piloto sem `SMS_GATEWAY`.
- [ ] Endereço ou ponto de referência da visita segue RF09/RF10, fora desta mudança.
- [ ] Testes exigidos: teste de widget confirma que o fluxo de login não tem campo de CPF, telefone nem e-mail; teste de integração sobe o backend no perfil do piloto sem `SMS_GATEWAY`.

## Referências
IDs: C-05, RF24, RNF08, RNF09, P-10
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: —
<!-- /corpo -->

### N6 — [C-06] Trocar "UBS" nos textos dos apps por grupo e coordenação do piloto
Milestone: Pilot
Rótulos: `enhancement`
<!-- corpo -->
## Objetivo
Trocar "UBS" e "coordenação da UBS" nos textos dos três apps por "grupo do piloto" e "coordenação do piloto". A tabela `ubs` não muda aqui.

## Critério de aceite
- [ ] Nenhum texto visível dos apps cita "UBS" (conferir as linhas listadas em C-06).
- [ ] Testes de widget atualizados.

## Referências
IDs: C-06
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: —
<!-- /corpo -->

### N7 — [C-08] Autoavaliação com três saídas, sem classificação de risco
Milestone: Pilot
Rótulos: `enhancement`
<!-- corpo -->
## Objetivo
Mostrar o resultado da autoavaliação como uma de três saídas — "Cuidar-se em casa", "Procurar atendimento", "Ligar 192" — sem cor nem rótulo de risco clínico. O cálculo do motor não muda (INV-02); o envio da saída "Ligar 192" é tratado em C-04.

## Critério de aceite
- [ ] Nenhuma tela do participante exibe "classificação de risco" ou cor como resultado clínico.
- [ ] Mesma entrada, mesmo resultado do motor.

## Referências
IDs: C-08, RF04, RF16, P-11
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: C-04
<!-- /corpo -->

### N8 — [C-10] "Apagar meus dados" e retenção local de 30 dias
Milestone: Pilot
Rótulos: `privacy`
<!-- corpo -->
## Objetivo
Opção "Apagar meus dados", disponível sem cadastro, que apaga banco local, lembretes e a trilha local de eventos; expiração automática dos eventos locais em 30 dias. O prazo de 30 dias foi proposto no plano de 2026-11-01 e está em `spec/requisitos_piloto.md` (§ INV-03 no piloto) e em C-10 como "prazo proposto, ajustável no TCLE"; não passou por decisão da equipe e deve ser confirmado no TCLE (P-04).

## Critério de aceite
- [ ] Depois de "Apagar meus dados" não resta nenhum evento local.
- [ ] Evento com mais de 30 dias some na próxima abertura.
- [ ] Com sessão do pilar B, a opção também encerra a sessão e abre o pedido de eliminação existente.

## Referências
IDs: C-10, RNF09, P-04
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: C-04 (trilha local); prazo final depende do TCLE (P-04)
<!-- /corpo -->

### N9 — [C-11] Autoavaliação local no pilar A, sem sessão nem registro no servidor
Milestone: Pilot
Rótulos: `privacy`
<!-- corpo -->
## Objetivo
No pilar A, rodar a autoavaliação no aparelho, sem `accessToken` e sem gravar em `triage_sessions`; a chamada remota fica só no pilar B.

## Critério de aceite
- [ ] Sem login, a autoavaliação produz o mesmo resultado que o motor do backend para as 64 combinações de sinais.
- [ ] Nenhuma chamada de rede na autoavaliação do pilar A.
- [ ] O teste de paridade das 64 combinações roda no CI a cada mudança em qualquer um dos dois motores (aparelho e backend), não só na entrega: a INV-02 passa a depender de duas implementações iguais.

## Referências
IDs: C-11, RF04, RF16, RF22, RNF09
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: —
<!-- /corpo -->

### N10 — [C-12] Recuperação de acesso que invalida a credencial do aparelho anterior
Milestone: Pilot
Rótulos: `security`
<!-- corpo -->
## Objetivo
Recuperar o acesso do participante por novo convite QR do agente, vinculado ao mesmo identificador pseudônimo, após confirmação presencial. A reemissão invalida no servidor a credencial de dispositivo anterior; revogar o JWT é opcional, dado o prazo de 1 h. Essa invalidação não existe hoje.

## Critério de aceite
- [ ] O novo convite reusa o identificador e o histórico.
- [ ] A credencial do aparelho anterior é recusada pelo servidor logo após a reemissão.
- [ ] Limite documentado: aparelho perdido que nunca mais se conecta fica protegido só pela cifra local com PIN (RNF03).

## Referências
IDs: C-12, RF24, P-10
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: C-05
<!-- /corpo -->

### N11 — [RNF07] APK assinado publicado em GitHub Releases
Milestone: Pilot
Rótulos: `enhancement`
<!-- corpo -->
## Objetivo
Publicar os APKs do piloto, assinados com chave de release, em GitHub Releases, sem depender de loja paga.

## Critério de aceite
- [ ] Chave de assinatura de release provisionada, com responsável e backup (P-13).
- [ ] APK do paciente e do agente publicados num release com notas e hash.
- [ ] Instruções de instalação no README.

## Referências
IDs: RNF07, RNF08, P-13
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/stack.md
Bloqueado por: P-13 (custódia da chave)
<!-- /corpo -->

### N12 — [RNF07] Compose do piloto: um host, Let's Encrypt e documentação única
Milestone: Pilot
Rótulos: `documentation`
<!-- corpo -->
## Objetivo
Definir e documentar uma única montagem do piloto e resolver a divergência entre `spec/stack.md` §0 (um host, Traefik + Let's Encrypt, Mosquitto no mesmo host) e `backend/DEPLOY.md` (serviços free-tier externos).

## Critério de aceite
- [ ] Um compose do piloto que sobe com um comando num host.
- [ ] TLS 1.3 com certificado Let's Encrypt.
- [ ] `spec/stack.md` §0 e `backend/DEPLOY.md` descrevem a mesma montagem.
- [ ] Custo mensal estimado dentro do teto da decisão aprovada P-08.
- [ ] Chave da CA de aparelhos do piloto fora do repositório, com custódia e backup definidos (a PKI de produção segue em #118, `futuro`).

## Referências
IDs: RNF07, RNF04, P-08, P-13
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/stack.md
Bloqueado por: —
<!-- /corpo -->

### N13 — [RNF03] Cifra local dos dados do app do paciente com PIN
Milestone: Pilot
Rótulos: `privacy`
<!-- corpo -->
## Objetivo
Cifrar em repouso os dados locais do app do paciente que sejam dado de saúde (autoavaliação, trilha local de eventos, dados do pilar B). Duas situações: no **pilar A** (sem cadastro, sem PIN), a chave fica no Android Keystore, presa ao aparelho, sem segredo do usuário; no **pilar B**, a chave é liberada pelo PIN local. Limite do pilar A: a cifra protege contra extrair o banco do aparelho, não contra alguém usando o celular desbloqueado — a mitigação é a expiração em 30 dias e o "Apagar meus dados" (N8). Hoje o app usa SQLite sem cifra (lembretes e consentimentos, por decisão registrada no código) e não tem PIN. Depois de C-12, a cifra local é a única proteção de um aparelho perdido que não volta a se conectar.

## Critério de aceite
- [ ] Banco local com dado de saúde cifrado (AES-256): chave no Keystore no pilar A; chave liberada pelo PIN no pilar B.
- [ ] Limite do pilar A documentado no app e em `spec/lgpd_design.md` §0.
- [ ] Teste que abre o banco sem a chave e falha.
- [ ] Decisão sobre lembretes e consentimentos registrada (manter sem cifra ou cifrar).

## Referências
IDs: RNF03, RF24, C-04, C-10, C-11, C-12
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/requisitos_piloto.md
Bloqueado por: C-05 (PIN, só para o pilar B)
<!-- /corpo -->

### N14 — [RNF05] Acessibilidade WCAG AA dos fluxos do piloto no app do paciente
Milestone: Pilot
Rótulos: `accessibility`
<!-- corpo -->
## Objetivo
Garantir WCAG 2.2 AA (contraste, alvos de toque, semântica) em todos os fluxos do piloto no app do paciente, novos ou já existentes — aviso educativo, biblioteca de conteúdo, convite por QR, PIN, autoavaliação e suas três saídas, pedido de contato, lembretes, "Apagar meus dados" — para um público de baixo letramento digital.

## Critério de aceite
- [ ] Cada tela desses fluxos passa no `semantics_scan` e nos testes de contraste do app.
- [ ] Alvos de toque ≥ 48 dp.
- [ ] Revisão manual com leitor de tela registrada.

## Referências
IDs: RNF05, C-02, C-03, C-04, C-05, C-08, C-10
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/ux_accessibility_assessment.md
Bloqueado por: —
<!-- /corpo -->

### N15 — [C-07] Discagem só para 192 no app do agente
Milestone: v1.0
Rótulos: `enhancement`
<!-- corpo -->
## Objetivo
Manter só a discagem para 192 no app do agente e retirar "Ligar para a UBS".

## Critério de aceite
- [ ] Botão "Ligar para a UBS" removido; discagem para 192 mantida.

## Referências
IDs: C-07, RF13
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: —
<!-- /corpo -->

### N16 — [C-09] Remover "Manchester" do código e do roteiro de vídeo
Milestone: v1.0
Rótulos: `documentation`
<!-- corpo -->
## Objetivo
Remover a marca de comentários de código e do roteiro de vídeo (M-05).

## Critério de aceite
- [ ] Nenhuma ocorrência em `backend/**/lib`, `apps/**` e `video/`.

## Referências
IDs: C-09
Escopo: https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md
Bloqueado por: —
<!-- /corpo -->

### N17 — [C-06b] Renomear a tabela ubs para grupo do piloto (migração)
Milestone: v1.0
Rótulos: `enhancement`
<!-- corpo -->
## Objetivo
Renomear a tabela `ubs` e os campos `ubsId` para refletir "grupo do piloto", com migração do Serverpod. Dívida técnica fora do portão (o texto visível é C-06).

## Critério de aceite
- [ ] Migração gerada e aplicada sem perda de dados.
- [ ] Seeds e testes atualizados.

## Referências
IDs: C-06
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#papeis-no-piloto
Bloqueado por: —
<!-- /corpo -->

### N18 — [Ação P-02] Contato com o encarregado de dados da UFRR
Milestone: Pilot
Rótulos: `acao-equipe`
<!-- corpo -->
## Objetivo
Contato com o encarregado de dados da UFRR (decisão aprovada P-02).

## Critério de aceite
- [ ] Nome e contato do encarregado registrados; confirmação jurídica obtida.

## Referências
IDs: P-02
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#acoes
Bloqueado por: —
Responsável: `[A DEFINIR]`
<!-- /corpo -->

### N19 — [Ação P-03] Confirmação com a coordenação do PET-Saúde
Milestone: Pilot
Rótulos: `acao-equipe`
<!-- corpo -->
## Objetivo
Confirmar com a coordenação do PET-Saúde quem exerce o papel de agente, a capacitação prévia e o preceptor (decisão aprovada P-03).

## Critério de aceite
- [ ] Agentes e preceptor definidos; capacitação planejada.

## Referências
IDs: P-03
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#acoes
Bloqueado por: —
Responsável: `[A DEFINIR]`
<!-- /corpo -->

### N20 — [Ação P-04] Submissão na Plataforma Brasil
Milestone: Pilot
Rótulos: `acao-equipe`
<!-- corpo -->
## Objetivo
Submeter o projeto do piloto ao Comitê de Ética em Pesquisa pela Plataforma Brasil (decisão aprovada P-04).

## Critério de aceite
- [ ] Projeto e TCLE redigidos (controlador e encarregado conforme P-02; agentes, capacitação e território conforme P-03 e P-05; instrumentos conforme P-12).
- [ ] Submetido na Plataforma Brasil (data registrada aqui).
- [ ] Parecer emitido e registrado.

## Referências
IDs: P-04, P-02, P-03, P-05, P-12
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#acoes
Bloqueado por: P-02, P-03, P-05, P-12
Responsável: `[A DEFINIR]`
<!-- /corpo -->

### N21 — [Ação P-05] Definição do território com o PET-Saúde
Milestone: Pilot
Rótulos: `acao-equipe`
<!-- corpo -->
## Objetivo
Definir o território do piloto com o PET-Saúde (decisão aprovada P-05).

## Critério de aceite
- [ ] Território registrado.

## Referências
IDs: P-05
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#acoes
Bloqueado por: —
Responsável: `[A DEFINIR]`
<!-- /corpo -->

### N22 — [Ação P-07] Lista de temas e revisores do conteúdo educativo
Milestone: Pilot
Rótulos: `acao-equipe`
<!-- corpo -->
## Objetivo
Definir a lista de temas e os revisores do conteúdo educativo (decisão aprovada P-07).

## Critério de aceite
- [ ] Lista de temas e revisores registrada.

## Referências
IDs: P-07, C-03
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#acoes
Bloqueado por: —
Responsável: `[A DEFINIR]`
<!-- /corpo -->

### N23 — [Ação P-11] Pedido de parecer à Procuradoria Federal junto à UFRR
Milestone: Pilot
Rótulos: `acao-equipe`
<!-- corpo -->
## Objetivo
Pedir parecer jurídico sobre o enquadramento regulatório da autoavaliação (decisão aprovada P-11).

## Critério de aceite
- [ ] Parecer registrado.

## Referências
IDs: P-11, C-08
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#acoes
Bloqueado por: —
Responsável: `[A DEFINIR]`
<!-- /corpo -->

### N24 — [Ação P-12] Instrumentos dos questionários e serviço de aplicação
Milestone: Pilot
Rótulos: `acao-equipe`
<!-- corpo -->
## Objetivo
Definir o questionário de conhecimento pré/pós, o SUS, a pergunta de reconhecimento do aviso, o roteiro de observação do primeiro uso (métrica H2, ver #99) e o serviço de aplicação (decisão proposta P-12, status: Proposta).

## Critério de aceite
- [ ] Instrumentos definidos, incluindo o roteiro de observação do primeiro uso, e submetidos ao CEP junto com o projeto (P-04).
- [ ] Serviço definido e registrado como operador na §0 de `spec/lgpd_design.md` e no TCLE.

## Referências
IDs: P-12, RF23, P-04
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#acoes
Bloqueado por: —
Responsável: `[A DEFINIR]`
<!-- /corpo -->

### N25 — [Ação P-13] Custódia do repositório e da chave de assinatura do APK
Milestone: Pilot
Rótulos: `acao-equipe`
<!-- corpo -->
## Objetivo
Definir o responsável e o backup da chave de assinatura de release do APK e a custódia do repositório em organização do PRISM no GitHub (decisão proposta P-13, status: Proposta). Sem essa custódia não há APK de release (RNF07) e, portanto, não há piloto.

## Critério de aceite
- [ ] Responsável pela chave e pelo backup registrado.
- [ ] Decisão sobre a organização do PRISM no GitHub registrada.

## Referências
IDs: P-13, RNF07
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#acoes
Bloqueado por: —
Responsável: `[A DEFINIR]`
<!-- /corpo -->

## Reescritas de escopo

### #118 — [P1] PKI de produção da CA de aparelhos (escopo 5 da #94)
Título novo: PKI de produção da CA de aparelhos (escopo 5 da #94)
<!-- bloco -->
> **Escopo revisto (2026-11-02):** classificada como **futuro** — a PKI de produção está em [`spec/trabalhos_futuros.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/trabalhos_futuros.md) e não é pré-requisito do piloto. No piloto, "UBS" no texto abaixo corresponde a um grupo do piloto ([`spec/escopo_projeto.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#papeis-no-piloto)). Texto original mantido abaixo.
<!-- /bloco -->
<!-- comentario -->
<!-- escopo-2026-11-02 -->
Classificada como **futuro**: a PKI de produção da CA de aparelhos está em [`spec/trabalhos_futuros.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/trabalhos_futuros.md) e não é pré-requisito do piloto. A issue segue aberta.

Também acrescentei no topo do corpo um bloco de escopo, porque o texto cita "UBS", que no piloto corresponde a um grupo do piloto, e o título perdeu o "[P1]". O texto original foi mantido abaixo do bloco. A CA do piloto ganhou dono numa issue própria (compose do piloto).
<!-- /comentario -->

### #116 — [P3] Chave do certificado do aparelho no TEE
Título novo: —
<!-- bloco -->
<!-- /bloco -->
<!-- comentario -->
<!-- escopo-2026-11-02 -->
Classificada como **futuro**: a chave do certificado no TEE está em [`spec/trabalhos_futuros.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/trabalhos_futuros.md). Não é pré-requisito do piloto; a issue segue aberta.
<!-- /comentario -->

### #102 — [P2] Métricas do §1.3 no backoffice
Título novo: —
<!-- bloco -->
> **Escopo revisto (2026-11-02):** milestone **v1.0**. As métricas do piloto vêm de `telemetry_events` e dos questionários ([`spec/plano_piloto.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/plano_piloto.md) § Métricas); esta tela é melhoria pós-piloto. Onde o texto abaixo diz "UBS", no piloto leia-se grupo do piloto ([`spec/escopo_projeto.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#papeis-no-piloto)). Texto original mantido abaixo.
<!-- /bloco -->
<!-- comentario -->
<!-- escopo-2026-11-02 -->
Movida para a milestone **v1.0**: as métricas do piloto saem de `telemetry_events` e dos questionários ([`spec/plano_piloto.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/plano_piloto.md)), então esta tela não é pré-requisito.

Acrescentei no topo do corpo um bloco de escopo, porque o texto cita "UBS", que no piloto corresponde a um grupo do piloto. O texto original foi mantido abaixo do bloco.
<!-- /comentario -->

### #96 — [P2] Separar papéis do Postgres para o REVOKE da auditoria valer (RF17)
Título novo: —
<!-- bloco -->
<!-- /bloco -->
<!-- comentario -->
<!-- escopo-2026-11-02 -->
Marcada **a-decidir**. Há duas justificativas em conflito:

- (a) está em [`spec/trabalhos_futuros.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/trabalhos_futuros.md) (separação de papéis do banco), o que a classificaria como futuro;
- (b) é a **única pendência do RF17**, Essencial em [`spec/requisitos_piloto.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/requisitos_piloto.md): sem a separação de papéis o REVOKE não vale e o papel da aplicação ainda consegue alterar registros da trilha de auditoria num piloto com dados reais de participantes, o que a colocaria em Pilot.

A equipe decide entre Pilot, v1.0 ou futuro. A issue segue aberta.
<!-- /comentario -->

### #87 — Backoffice sem contador "Concluídos": alerta resolvido some dos indicadores (RF05)
Título novo: —
<!-- bloco -->
> **Escopo revisto (2026-11-02):** milestone **v1.0** (RF05 é Desejável no piloto, [`spec/requisitos_piloto.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/requisitos_piloto.md)). Entregue em `develop` (PRs #108–#110); fecha no merge para `main`. "UBS" no texto abaixo corresponde, no piloto, a um grupo do piloto. Texto original mantido abaixo.
<!-- /bloco -->
<!-- comentario -->
<!-- escopo-2026-11-02 -->
Movida para a milestone **v1.0**: RF05 é Desejável no piloto ([`spec/requisitos_piloto.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/requisitos_piloto.md)). A entrega já está em `develop` e a issue fecha no merge para `main`.

Acrescentei no topo do corpo um bloco de escopo, porque o texto cita "UBS". O texto original foi mantido abaixo do bloco.
<!-- /comentario -->

### #77 — [P0] Envio do OTP por SMS real (RF01)
Título novo: Envio do OTP por SMS real (RF01)
<!-- bloco -->
> **Escopo revisto (2026-11-02):** classificada como **futuro**. A decisão aprovada P-10 tira CPF, SMS e e-mail do login do participante no piloto: o acesso é por convite QR + PIN local (RF24, mudanças C-05 e C-12 em [`docs/escopo/mudancas-de-codigo-recomendadas.md`](https://github.com/hbgit/SinalACS/blob/develop/docs/escopo/mudancas-de-codigo-recomendadas.md)). RF01 com CPF e SMS está em [`spec/trabalhos_futuros.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/trabalhos_futuros.md). Texto original mantido abaixo.
<!-- /bloco -->
<!-- comentario -->
<!-- escopo-2026-11-02 -->
Classificada como **futuro**. A decisão aprovada P-10 tira CPF, SMS e e-mail do login do participante no piloto; o acesso passa a ser por convite QR + PIN local (RF24; C-05 e C-12). RF01 com CPF e SMS está em [`spec/trabalhos_futuros.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/trabalhos_futuros.md).

O título perdeu o "[P0]", que indicava prioridade máxima para algo fora do piloto. Um bloco de escopo foi acrescentado no topo do corpo, e o texto original foi mantido abaixo dele. A issue segue aberta.
<!-- /comentario -->

### #15 — docs: guia de boas práticas e passo a passo para publicar app na Google Play Store
Título novo: —
<!-- bloco -->
<!-- /bloco -->
<!-- comentario -->
<!-- escopo-2026-11-02 -->
Classificada como **futuro**: a publicação na Play Store está em [`spec/trabalhos_futuros.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/trabalhos_futuros.md). No piloto, os apps são distribuídos como APK assinado em GitHub Releases (RNF07). Não é pré-requisito do piloto; a issue segue aberta.
<!-- /comentario -->
