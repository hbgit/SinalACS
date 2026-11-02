# Plano de piloto do SinalACS

> Conteúdo educativo. Não substitui atendimento profissional. Emergência: ligue 192.

Plano do primeiro piloto, coerente com a natureza do projeto descrita em
[`escopo_projeto.md`](escopo_projeto.md) e com as prioridades de
[`requisitos_piloto.md`](requisitos_piloto.md). As decisões P-NN citadas aqui
são **propostas** (status: Proposta) até a equipe mudar o status em
[`escopo_projeto.md#pendencias`](escopo_projeto.md#pendencias).

## Objetivo

Avaliar se o SinalACS:

- (a) apoia ações de educação em saúde na comunidade;
- (b) é usável por pessoas com baixo letramento digital;
- (c) funciona offline sem perda de dados;
- (d) pode ser implantado por terceiros com baixo custo.

## Participantes

Decisão proposta P-05 (status: Proposta):

- **2 a 3 agentes participantes:** estudantes do PET-Saúde sob supervisão de
  preceptor (decisão proposta P-03).
- **15 a 30 participantes da comunidade.**
- **Território:** `[A DEFINIR]`, definido pelo PET-Saúde.

Critérios de inclusão: 18 anos ou mais; aparelho Android 7.0 ou superior
(API 24, o piso atual dos apps); TCLE assinado.

Critérios de exclusão: menores de idade (o fluxo de menores ainda está adiado
nos apps); ACS em exercício da função no papel de agente.

## Duração

8 semanas: 1 de preparação, 6 de uso e 1 de encerramento. A data de início
depende do parecer do Comitê de Ética em Pesquisa (P-04).

## Pré-requisitos de código

Detalhe em [`docs/escopo/mudancas-de-codigo-recomendadas.md`](../docs/escopo/mudancas-de-codigo-recomendadas.md).
O portão tem dois níveis.

**Segurança e legal — nenhuma coleta com participantes antes de:**

- **C-01:** controlador, encarregado e aviso educativo no texto legal.
- **C-02:** aviso educativo na primeira abertura.
- **C-04:** pedido de contato sem rótulo de urgência; "Ligar 192" antes de
  qualquer pedido.
- **C-05:** acesso sem CPF e sem SMS (RF24).
- **C-06:** a palavra "UBS" aparece hoje a participantes (app do paciente,
  texto legal, app do agente), logo entra no portão.
- **C-08:** autoavaliação com três saídas (P-11).
- **C-11:** autoavaliação local no pilar A, sem sessão e sem registro no
  servidor (hoje `triage.evaluate` exige login e grava no servidor).
- **C-10:** "Apagar meus dados" no app do paciente e retenção local de
  30 dias dos eventos de auditoria do aparelho.

**Funcional — obrigatório se o pilar A estiver no piloto:**

- **C-03:** biblioteca de conteúdo educativo. Sem ela não há como medir o
  objetivo (a) nem o ganho de conhecimento.

## Pré-requisitos não técnicos

- **P-02:** confirmação jurídica do controlador e nome e contato do
  encarregado.
- **P-03:** confirmação, pela coordenação do PET-Saúde, de quem exerce o
  papel de agente.
- **P-04:** parecer do CEP; a submissão na Plataforma Brasil começa em
  paralelo à documentação.
- **P-05:** território.
- **P-07:** lista de temas e revisores do conteúdo educativo.
- **P-11:** parecer jurídico sobre o enquadramento regulatório.

## Dados

- Só dados sintéticos até P-02 e P-04 estarem resolvidas.
- Depois, o mínimo necessário (RNF09): nenhum dado pessoal no pilar A; no
  pilar B, identificador pseudônimo, sem CPF.
- Nenhum dado de unidade de saúde.
- O app é distribuído por APK assinado publicado em GitHub Releases (RNF07).

## Métricas

| Métrica | Fonte | Meta proposta |
|---|---|---|
| Usabilidade (System Usability Scale, SUS) | Questionário pós (RF23) | ≥ 68 |
| Primeiro uso concluído sem ajuda (herda H2 do PRD) | Observação na sessão de preparação | ≥ 80% |
| Sincronização offline bem-sucedida (herda H4 do PRD) | `telemetry_events` (`sync_result`) | ≥ 99,5% |
| Ganho de conhecimento | Questionário pré/pós; instrumento `[A DEFINIR]` (P-07) | Ganho positivo; meta `[A DEFINIR]` |
| Custo mensal de hospedagem | Fatura do provedor | ≤ R$ 50 (teto proposto em P-08) |
| Sessões sem falha | Telemetria | ≥ 99% |
| Reconhecimento do aviso educativo | Pergunta no questionário pós | ≥ 90% |

## Critérios de sucesso e de parada

**Sucesso:** as metas de usabilidade, sincronização e reconhecimento do aviso
são atingidas **e** nenhum incidente de segurança ou de expectativa de socorro
é registrado. As demais métricas são informativas.

**Parada (M-09):**

- Se menos de 90% dos participantes reconhecerem o aviso educativo na
  primeira semana, o piloto pausa e a tela é corrigida antes de retomar.
- Qualquer relato de participante que esperou socorro do app também pausa o
  piloto até a causa ser corrigida.

## Ética, LGPD e encerramento

Controlador, encarregado e base legal seguem a decisão proposta P-02 (status:
Proposta): controlador UFRR, por meio do projeto, com o líder do PRISM como
pesquisador responsável; encarregado institucional da UFRR (nome e contato
`[A DEFINIR]`); base legal art. 11, II, "c" da LGPD, com TCLE. Nenhuma coleta
com participantes começa antes do parecer do CEP (P-04). Se RF23 usar
formulário externo, o serviço consta como operador no TCLE.

**Encerramento (M-04):**

1. Exportar o necessário à pesquisa já anonimizado. Com amostra de 15 a 30
   pessoas num território pequeno, o risco de reidentificação é real; o
   critério mínimo proposto é retirar o território e qualquer geolocalização,
   agregar a idade em faixas e não exportar texto livre. O critério final é
   `[A DEFINIR]` no TCLE (P-04).
2. Apagar os dados identificáveis do servidor e dos aparelhos dos agentes
   (wipe remoto existente, #81).
3. **O pilar A não é alcançado pelo wipe:** o uso é sem cadastro e os
   aparelhos não estão registrados. A eliminação dos dados locais do
   participante depende de C-10 — a opção "Apagar meus dados", comunicada a
   todos no encerramento junto com a orientação de que desinstalar o app
   também apaga — e da expiração automática dos eventos locais em 30 dias.
4. Registrar a eliminação na trilha de auditoria.

Prazo para concluir o encerramento: `[A DEFINIR]`, fixado no TCLE (P-04).

## Riscos

| Risco | Mitigação |
|---|---|
| Participante tratar o pedido de contato como emergência | Aviso educativo (RF21), botão "Ligar 192" antes de qualquer pedido, critério de parada |
| Enquadramento como software como dispositivo médico | Autoavaliação com três saídas, sem classificação de risco; parecer jurídico (P-11) |
| Perda de aparelho de agente | Wipe remoto (#81) |
| Custo acima do teto | Camada gratuita ou VPS mínima; revisão do teto (P-08) |
| Atraso do parecer do CEP | Submissão em paralelo à documentação (P-04) |
