# Escopo do projeto SinalACS

> O SinalACS é uma ferramenta de educação em saúde, de código aberto, desenvolvida pelo Grupo de Pesquisa PRISM da Universidade Federal de Roraima (UFRR), em cooperação com o PET-Saúde: Inovação e Saúde Digital. O conteúdo e as orientações exibidos têm caráter educativo e não substituem consulta, diagnóstico ou tratamento por profissionais de saúde. O SinalACS não é um serviço de emergência: em caso de risco de vida, ligue 192 (SAMU).

Este documento é a fonte da verdade sobre a natureza, o público e o escopo do
SinalACS. Os requisitos priorizados estão em
[`requisitos_piloto.md`](requisitos_piloto.md), o piloto em
[`plano_piloto.md`](plano_piloto.md) e o que depende de instituições de saúde
em [`trabalhos_futuros.md`](trabalhos_futuros.md). O
[PRD](PRD_system.md) e os demais documentos de `spec/` descrevem a concepção
original, voltada à operação dentro da Atenção Primária; quando divergirem
deste documento, vale este documento.

<a id="natureza-do-projeto"></a>
## Natureza do projeto

O SinalACS é desenvolvido pelo Grupo de Pesquisa PRISM da Universidade Federal
de Roraima (UFRR), em cooperação com o Programa de Educação pelo Trabalho para
a Saúde (PET-Saúde): Inovação e Saúde Digital, iniciativa do Núcleo de
Telessaúde da UFRR. O responsável é o Prof. Herbert Oliveira Rocha, líder do
Grupo PRISM. O código é aberto, de livre uso, sob a licença MIT.

O foco principal do projeto é a **educação social em saúde**. O papel
secundário é o apoio a questões de saúde, sem substituir atendimento
profissional.

Neste momento não há vínculo com unidades de saúde públicas ou privadas. A
implementação, a hospedagem e a operação do SinalACS não dependem da
infraestrutura, dos sistemas ou dos dados dessas unidades. Integrações com
serviços de saúde são tratadas apenas como trabalhos futuros.

<a id="pilares"></a>
## Pilares

**Pilar A — Educação em saúde para a comunidade, sem cadastro.** Conteúdo
educativo offline com fontes citadas (RF20), aviso educativo (RF21), uso sem
cadastro (RF22), lembretes locais (RF06) e a autoavaliação educativa (RF04,
RF16), com três saídas: "Cuidar-se em casa", "Procurar atendimento" e
"Ligar 192".

**Pilar B — Apoio ao acompanhamento comunitário por agentes participantes,
como atividade de extensão do PET-Saúde.** Convite por QR (RF02), acesso do
participante sem CPF (RF24), pedido de contato com o agente participante
(RF03), login do agente (RF07), território, fila e visita offline
(RF08–RF11) e sincronização (RF15).

Se a equipe decidir pilotar só o pilar A, os requisitos do pilar B passam a
Desejáveis e o piloto encurta.

<a id="aviso-educativo"></a>
## Aviso educativo

Versão longa (documentação, texto legal, tela "Sobre"):

> O SinalACS é uma ferramenta de educação em saúde, de código aberto, desenvolvida pelo Grupo de Pesquisa PRISM da Universidade Federal de Roraima (UFRR), em cooperação com o PET-Saúde: Inovação e Saúde Digital. O conteúdo e as orientações exibidos têm caráter educativo e não substituem consulta, diagnóstico ou tratamento por profissionais de saúde. O SinalACS não é um serviço de emergência: em caso de risco de vida, ligue 192 (SAMU).

Versão curta (telas):

> Conteúdo educativo. Não substitui atendimento profissional. Emergência: ligue 192.

Regra: toda tela inicial dos apps, o texto legal e toda página de entrada da
documentação exibem uma das duas versões, copiada literalmente, sem paráfrase.

<a id="publico-alvo"></a>
## Público-alvo

- **Pessoas da comunidade** que buscam informação em saúde (pilar A) e, no
  piloto, participantes acompanhados por um agente (pilar B).
- **Agentes participantes:** estudantes do PET-Saúde sob supervisão de
  preceptor (decisão proposta P-03, status: Proposta).
- **Preceptores e coordenação do PET-Saúde**, que supervisionam os agentes e
  revisam o conteúdo educativo.
- **Desenvolvedores e pesquisadores** que reutilizam o código.

<a id="dentro-do-escopo"></a>
## Dentro do escopo

- Conteúdo educativo offline, com fontes citadas.
- Autoavaliação educativa determinística, com as três saídas "Cuidar-se em
  casa", "Procurar atendimento" e "Ligar 192" — orientação, nunca
  classificação de risco clínico.
- Lembretes locais, sem servidor.
- Uso sem cadastro do pilar A.
- Pilar B como atividade de extensão do PET-Saúde.
- Backoffice para a equipe do projeto.
- Implantação replicável por terceiros: um `docker compose` e o APK assinado
  publicado em GitHub Releases.

<a id="fora-do-escopo"></a>
## Fora do escopo

Cada item abaixo está detalhado em [`trabalhos_futuros.md`](trabalhos_futuros.md).

- Serviço de emergência ou promessa de atendimento.
- Diagnóstico e classificação de risco clínico.
- Integração (Futuro) com e-SUS APS, CNES, CNS/CADSUS, RNDS, Gov.br, SAMU, UBS ou
  Secretaria de Saúde.
- Uso de dados ou de infraestrutura de unidades de saúde.
- ACS em exercício da função atuando como agente do piloto.
- Coleta de CPF e envio de SMS no piloto.
- Distribuição pela Play Store.

<a id="papeis-no-piloto"></a>
## Papéis no piloto

| Papel no código | Papel no piloto |
|---|---|
| `patient` | Participante da comunidade |
| `acs` | Agente participante: estudante do PET-Saúde sob supervisão de preceptor; **não** um ACS em exercício da função |
| `coordinator` | Preceptor ou coordenação do piloto |
| `admin` | Administração técnica (equipe do PRISM) |

A tabela `ubs` do modelo de dados (`ubs.spy.yaml`) representa, no piloto, um
**grupo do piloto**, não uma unidade de saúde. A renomeação é a mudança C-06
de [`docs/escopo/mudancas-de-codigo-recomendadas.md`](../docs/escopo/mudancas-de-codigo-recomendadas.md).

<a id="pendencias"></a>
## Pendências

Fonte viva das decisões pendentes. A origem é o
[registro de decisões de 2026-11-01](../docs/escopo/decisoes-2026-11-01.md),
que guarda a justificativa de cada uma.

| ID | Pendência | Decisão proposta | Ainda depende de | Bloqueia o piloto? | Status |
|---|---|---|---|---|---|
| P-01 | Titular dos direitos no `LICENSE` | "Copyright (c) 2026 Herbert Oliveira Rocha e contribuidores do SinalACS (Grupo de Pesquisa PRISM/UFRR)"; licença MIT mantida | Consulta ao NIT da UFRR: `[A DEFINIR]` | Não | Proposta |
| P-02 | Controlador e encarregado de dados | Controlador: UFRR, por meio do projeto, com o líder do PRISM como pesquisador responsável; encarregado: o encarregado institucional da UFRR; base legal: art. 11, II, "c" da LGPD, com TCLE | Nome e contato do encarregado da UFRR: `[A DEFINIR]`; confirmação jurídica | **Sim** | Proposta |
| P-03 | Quem exerce o papel de agente | Estudantes do PET-Saúde sob supervisão de preceptor; não usar ACS em exercício da função | Coordenação do PET-Saúde | **Sim** | Proposta |
| P-04 | Comitê de Ética (CEP) e TCLE | Tratar como obrigatório e iniciar a submissão na Plataforma Brasil em paralelo à documentação | Parecer do CEP: `[A DEFINIR]` | **Sim** | Proposta |
| P-05 | Número de participantes e local | 2 a 3 agentes; 15 a 30 participantes da comunidade; território definido pelo PET-Saúde | Território: `[A DEFINIR]` | Sim (local) | Proposta |
| P-06 | Contato público (segurança e conduta) | Private Vulnerability Reporting e Discussions no GitHub; e-mail só quando houver endereço institucional. Passo manual do mantenedor: ativar os dois recursos nas configurações do repositório (agentes não alteram configurações do GitHub) | Endereço institucional: `[A DEFINIR]` | Não | Proposta |
| P-07 | Fonte e revisão do conteúdo educativo | Materiais públicos do Ministério da Saúde e da BVS, sempre citados; revisão pelos preceptores do PET-Saúde antes de cada versão | Lista de temas e revisores: `[A DEFINIR]` | **Sim** (RF20) | Proposta |
| P-08 | Orçamento mensal de hospedagem | Camada gratuita ou VPS mínima; teto de R$ 50/mês, revisto na data da contratação | Fonte de recurso, se houver custo: `[A DEFINIR]` | Não | Proposta |
| P-09 | Alerta ao agente no piloto | Manter como "pedido de contato", sem rótulo de urgência; maior gravidade na autoavaliação mostra "Ligar 192", sem envio ao agente | — | Sim (C-04) | Proposta |
| P-10 | Login do participante | Conteúdo e lembretes sem login; acompanhamento por convite QR do agente (RF02) + PIN local; identificador pseudônimo; sem CPF, sem SMS; e-mail opcional | — | Sim (C-05) | Proposta |
| P-11 | Enquadramento regulatório | Autoavaliação como orientação educativa com três saídas, sem classificação de risco clínico; solicitar parecer jurídico (RDC Anvisa nº 657/2022) | Parecer jurídico: `[A DEFINIR]` | Sim | Proposta |

Status possíveis: Proposta, Aprovada, Rejeitada, Substituída. Só a equipe do
projeto muda o status. Pendências novas recebem o próximo número (P-12 em
diante); nenhuma é renumerada.
