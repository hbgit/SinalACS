# Decisão — "pedido de contato" também no app do agente e no backoffice (#167)

> **Data:** 2026-11-19.
> **Issue:** [#167](https://github.com/hbgit/SinalACS/issues/167), aberta na revisão da PR #160 (C-04, #127).
> **IDs:** C-04, P-09, INV-03, RF19.
> **Status:** decidida na implementação da #167 (opção "renomear"); a ratificação do dono fica registrada na revisão da PR.

## Contexto

A P-09 ([decisões de 2026-11-01](decisoes-2026-11-01.md), aprovada em [`spec/escopo_projeto.md`](../../spec/escopo_projeto.md#pendencias)) transformou o alerta do participante em **pedido de contato com o agente participante**, sem rótulo de urgência. A C-04 (#127, PR #160) aplicou isso só ao app do paciente.

O app do ACS e o backoffice continuavam chamando o mesmo pedido de "alerta vermelho" e mostrando "Risco: Vermelho". O participante não vê esses textos, mas o agente participante e a coordenação do piloto veem, e o vocabulário de urgência é justamente o que a P-09 quis tirar do piloto. No servidor, todo alerta nasce de `alerts.createRedAlert` com `riskLevel: 'red'` (`red_alert_service.dart`): no piloto, **todo alerta vermelho é um pedido de contato**.

## Decisão

**Renomear.** O app do ACS e o backoffice passam a chamar o pedido de **"pedido de contato"**, sem "alerta", "vermelho" ou "risco" no rótulo do pedido.

| Onde | Antes | Depois |
|---|---|---|
| ACS, cartão da fila | "Risco: Vermelho" | "Pedido de contato" |
| ACS, aviso com o app bloqueado | "N alertas vermelhos aguardando" | "N pedidos de contato aguardando" |
| ACS, fila vazia, reserva HTTP, conexão | "alerta(s)", "central de alertas" | "pedido(s) de contato", "central de pedidos" |
| ACS, escalonamento e check-in passivo | linha "Risco: Vermelho" | linha "Tipo: Pedido de contato" |
| ACS, mapa | "Alerta selecionado: … • Vermelho", legenda "Vermelho" | "Selecionado: Paciente … • Pedido de contato", legenda "Pedido de contato" |
| ACS, concluir atendimento | "O paciente já vê \"Atendido\"" (falso desde a C-04) | "O participante vê \"Encerrado pelo agente participante\"" |
| Backoffice, aba e tela | "Alertas", "Alertas do grupo do piloto" | "Pedidos de contato" (barra do celular: "Contato") |
| Backoffice, Painel | cartão "Vermelho", seção "Alertas vermelhos" | cartão e seção "Pedidos de contato" |
| Backoffice, faixa de vencidos | "N vermelhos vencidos" | "N pedidos de contato vencidos" |
| Backoffice, linha da lista | "Risco: Vermelho" | "Tipo: Pedido de contato" |
| Backoffice, escalonar | "Escalonar alerta …", "O alerta segue pendente…" | "Escalonar pedido …", "O pedido segue pendente…" |

## O que não muda

- **Comportamento (INV-03).** Entrega com ACK, reserva HTTP (#80), escalonamento (RF19, #44), reforço da coordenação, prioridade máxima na fila e partição fechada dos contadores do Painel (#87) ficam como estão. A mudança é só de texto exibido.
- **Contratos e código interno.** Nenhuma mudança em `alerts.*`, `admin.alerts`/`alertsPulse`/`escalateAlert`, `AlertQueue`, `riskLevel: 'red'`, modelos, tabelas, tópicos MQTT, chaves de widget (`alert_*`, `overdue_red_banner`, `risk_counter_red`) nem nas mensagens de erro geradas pelo servidor.
- **Cor.** O pedido mantém o destaque vermelho de borda e o topo da fila: a cor continua sinal de prioridade para quem atende, acompanhada de texto (WCAG 1.4.1). O que sai é o rótulo de risco.
- **Amarelo e verde.** Os rótulos "Amarelo"/"Verde" (contadores do Painel, legenda do mapa, ramos defensivos do cartão) ficam: nenhum escritor cria alerta nessas cores, e eles não descrevem o pedido de contato. A cor de risco das pessoas na fila de visitas vem da triagem e é outro assunto (C-08, #130).

## Consequências

- Os testes de widget do ACS e do backoffice passam a procurar os textos novos e a garantir que o pedido não aparece como "alerta vermelho" nem "Risco: Vermelho".
- As capturas de tela de `docs/telas-acs.md` e `docs/telas-admin.md` ficam anteriores a esta decisão até serem refeitas.
- Se a decisão for revertida, a reversão é só de texto: nada de contrato, dado ou fluxo depende dos rótulos.
