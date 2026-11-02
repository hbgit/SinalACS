# Escopo educativo e aberto — plano de revisão das especificações

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reescrever especificações, requisitos e diretrizes do SinalACS para o escopo real do projeto — educação social em saúde, código aberto, sem vínculo com unidades de saúde — e deixar registrado, com portão explícito, o que falta para um piloto de baixo custo e baixa dependência institucional.

**Architecture:** Mudança só de documentação (e, no máximo, comentários de configuração). Quatro documentos novos passam a ser a fonte da verdade do escopo: `spec/escopo_projeto.md` (com a tabela viva de pendências), `spec/requisitos_piloto.md`, `spec/plano_piloto.md` (com o portão de código antes do piloto) e `spec/trabalhos_futuros.md`. Os documentos existentes recebem aviso de escopo e ajustes pontuais. As mudanças de código necessárias ficam em `docs/escopo/mudancas-de-codigo-recomendadas.md`, separadas em **portão do piloto** e **demais**, sem implementação neste plano.

**Tech Stack:** Markdown em pt-BR; verificação por `git grep` puro (sem dependência de `rtk` ou `graphify`).

**Spec:** pedido da equipe (seção "Contexto do pedido") e o registro de decisões [`docs/escopo/decisoes-2026-11-01.md`](../../escopo/decisoes-2026-11-01.md) (melhorias M-01–M-09, soluções para D1–D12, decisões propostas P-01–P-11). **Precedência:** o registro vale para o *conteúdo* das decisões P-NN (o que foi proposto e de quem ainda depende); este plano vale para a *execução* e para a *redação final* (rótulos exatos, IDs, resolução de condicionais como C-06, ordem das tarefas). Um agente não desfaz uma redação ou resolução deste plano por ela ser mais específica que o registro.

## Contexto do pedido

- Desenvolvido pelo Grupo de Pesquisa PRISM da UFRR, em cooperação com o PET-Saúde: Inovação e Saúde Digital (Núcleo de Telessaúde da UFRR). Responsável: Prof. Herbert Oliveira Rocha, líder do Grupo PRISM. Licença MIT.
- Foco principal: educação social em saúde. Papel secundário: apoio a questões de saúde, sem substituir atendimento profissional.
- Código aberto e de livre uso.
- Sem vínculo atual com unidades de saúde públicas ou privadas: implementação, hospedagem e operação não podem depender da infraestrutura, dos sistemas ou dos dados delas.
- Integrações com serviços de saúde só como "trabalhos futuros".

## Diagnóstico e solução adotada

| # | Onde | O que pressupõe vínculo | Solução (registro §3) |
|---|---|---|---|
| D1 | `spec/PRD_system.md` §1.1, `spec/idea.md` | Produto definido como gestão de visitas da Atenção Primária; nenhum requisito de conteúdo educativo. | Pilares A/B (M-02); RF20 e RF22 são o núcleo do pilar A; texto original do PRD vira "Contexto de origem". |
| D2 | PRD §1.2–1.3 | H1, H3, TMRAV como meta de atendimento, aderência à avaliação médica, ≥ 8 visitas/ACS/dia. | Passam a Futuro; o piloto mede SUS, sincronização, ganho de conhecimento e reconhecimento do aviso. |
| D3 | RF03, INV-03, RF19, status "Atendido" | Botão de urgência que promete resposta. | No piloto vira **pedido de contato com o agente participante**, sem rótulo de urgência; maior gravidade na autoavaliação mostra só "Ligar 192" e **não** envia pedido (P-09). |
| D4 | RF07, RNF06, `ubs.spy.yaml`, telas | Matrícula da Secretaria, CNS, Gov.br, UBS, coordenador de UBS. | Identificador emitido pela equipe do projeto; `ubs` = grupo do piloto até C-06. |
| D5 | RF13, `emergency_dialer.dart`, "Ligar para a UBS" no app do ACS | Encaminhamento ao SAMU/UBS pelo sistema. | Só discagem local para 192 (C-07); RF13 Futuro. |
| D6 | `lgpd_design.md`, `legal_documents.dart` | Controlador e encarregado "da Secretaria"; "sua UBS". | Papéis conforme P-02; nova `LegalVersion` (C-01). **Bloqueia o piloto.** |
| D7 | RF01, `SMS_GATEWAY` | CPF + OTP por SMS pago. | Sem CPF e sem SMS no piloto (P-10). |
| D8 | `stack.md`, PRD §8, `production.yaml` | Infraestrutura de produção institucional. | Perfis Local / Piloto / Futuro e distribuição por APK (M-03). |
| D9 | `idea.md`, PRD §6 | Piloto dentro de uma UBS. | `spec/plano_piloto.md` com o PET-Saúde como campo de prática (P-03, P-05). |
| D10 | `security_assessment.md` | IdP e-SUS APS/CNS. | Identidade própria do projeto; IdP oficial é Futuro. |
| D11 | `LICENSE`, código de conduta | Titular incompleto; conduta em rascunho. | P-01 e P-06. |
| D12 | README, PRD | Sem aviso educativo fora dos Termos. | Aviso canônico (RF21) em documentação, telas e texto legal (M-08). |

## Global Constraints

- Toda documentação nova ou alterada em português do Brasil.
- **Decisões propostas não são decisões aprovadas.** Todo texto que use uma decisão P-NN a apresenta como "decisão proposta (status: Proposta)" até o status mudar em `spec/escopo_projeto.md#pendencias`. Nunca escrever "aprovado", "deferido" ou "conforme parecer".
- Não inventar informação institucional. Os únicos nomes e vínculos permitidos são os do registro de decisões (UFRR, PRISM, PET-Saúde, Núcleo de Telessaúde, Prof. Herbert Oliveira Rocha). Encarregado da UFRR, contatos, território, parecer do CEP, parecer jurídico, resposta do NIT e fonte de recurso ficam como `[A DEFINIR]`.
- Identificadores existentes (RF01–RF19, RNF01–RNF06, INV-01–INV-05, LGPD-RF01–LGPD-RF21) **não mudam de significado nem são renumerados**. Requisitos novos começam em **RF20** e **RNF07**.
- Prioridade do piloto usa só três rótulos: **Essencial**, **Desejável**, **Futuro**.
- Nenhum requisito **Essencial** depende de unidade de saúde, de sistema oficial (e-SUS, CNES, CNS/CADSUS, RNDS, Gov.br, SAMU) ou de serviço pago sem alternativa gratuita (inclui SMS e Play Store).
- **A palavra "Manchester" sai de todo texto de produto, inclusive "inspirado em"** (M-05). O motor continua determinístico; descrevê-lo como "motor de autoavaliação determinístico por árvore de decisão fechada". Ocorrências em código-fonte vão para a lista de mudanças (C-09); em histórico (`PROGRESS.md`, planos e auditorias datados) ficam.
- Autoavaliação no texto de produto tem exatamente três saídas, com estes rótulos: **"Cuidar-se em casa"**, **"Procurar atendimento"**, **"Ligar 192"** (P-11). Não usar "classificação de risco" nem cores como resultado clínico em texto voltado a participantes.
- Aviso educativo canônico (copiar literalmente):
  - Versão longa: "O SinalACS é uma ferramenta de educação em saúde, de código aberto, desenvolvida pelo Grupo de Pesquisa PRISM da Universidade Federal de Roraima (UFRR), em cooperação com o PET-Saúde: Inovação e Saúde Digital. O conteúdo e as orientações exibidos têm caráter educativo e não substituem consulta, diagnóstico ou tratamento por profissionais de saúde. O SinalACS não é um serviço de emergência: em caso de risco de vida, ligue 192 (SAMU)."
  - Versão curta (telas): "Conteúdo educativo. Não substitui atendimento profissional. Emergência: ligue 192."
- Código-fonte não é alterado. Exceção: comentários em `.env.example` e `config/*.yaml`. `LICENSE` só muda se P-01 estiver com status "Aprovada" (Task 9).
- Invariantes do `CLAUDE.md` continuam valendo (determinismo, pedido/alerta nunca descartado em silêncio, LGPD, sem dado real em testes); a regra que cita Manchester é reescrita sem a marca, mantendo o sentido.
- Configurações do GitHub (Private Vulnerability Reporting, Discussions) **não** são alteradas por agente: ficam como passo manual do mantenedor.
- Commits sem atribuição de IA (regra do `CLAUDE.md` do projeto).

## Review Focus

1. **Decisão proposta apresentada como aprovada** — "o controlador é a UFRR" sem "(proposta)". Pinado na Task 10, Step 3.
2. **Promessa residual de socorro ou rótulo de urgência** — "alerta de urgência", "será atendido", "chega ao ACS em < 2 s" em texto do piloto. Pinado na Task 5, Step 4 e Task 10, Step 2.
3. **"Manchester" residual** em spec, docs, README, CLAUDE.md ou AGENTS.md. Pinado na Task 8, Step 3 e Task 10, Step 4.
4. **INV-03 contornada pela saída "Ligar 192"** — o texto diz que a saída não envia nada e ninguém explica por que isso não é descarte silencioso. Pinado na Task 3, Step 2b e Task 10, Step 2b. (Renumeração acidental continua pinada na Task 3, Step 3.)
5. **Aviso educativo divergente** entre documentos. Pinado na Task 10, Step 5.

---

## Estrutura de arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `docs/escopo/decisoes-2026-11-01.md` | Versionar (já existe, não alterar) | Registro histórico das decisões propostas. |
| `docs/escopo/inventario-vinculo-institucional.md` | Criar | Evidências D1–D12. |
| `spec/escopo_projeto.md` | Criar | Natureza, pilares A/B, público, dentro/fora, aviso, papéis, **tabela viva de pendências P-01–P-11**. |
| `spec/requisitos_piloto.md` | Criar | RF/RNF com prioridade; RF20–RF24, RNF07–RNF10. |
| `spec/plano_piloto.md` | Criar | Objetivo, participantes, duração, pré-requisitos de código, dados, métricas, sucesso e parada, ética/LGPD e encerramento, riscos. |
| `spec/trabalhos_futuros.md` | Criar | O que depende de instituição ou de serviço pago. |
| `docs/escopo/mudancas-de-codigo-recomendadas.md` | Criar esqueleto na Task 4; preencher na Task 9 | C-01–C-10, com o portão do piloto em dois níveis (segurança/legal e funcional). |
| `spec/PRD_system.md`, `spec/stack.md`, `spec/lgpd_design.md`, `spec/lgpd_data_audit.md`, `spec/idea.md`, `spec/security_assessment.md`, `spec/sys_flow.md`, `spec/test_plan.md` | Modificar | Aviso de escopo, ajustes pontuais, remoção de "Manchester". |
| `README.md`, `backend/DEPLOY.md`, `docs/telas-*.md`, `docs/showcase/slides.md`, `docs/roteiro-video-sponsor.md`, `docs/publicacao-google-play.md` | Modificar | Aviso, natureza, "Manchester". |
| `CONTRIBUTING.md`, `CLAUDE.md`, `AGENTS.md`, `backend/CLAUDE.md`, `.github/SECURITY.md` | Modificar | Natureza do projeto, regra de escopo, contato por GitHub. |
| `.env.example`, `backend/sinalacs_server/config/production.yaml` | Só comentários | `SMS_GATEWAY` e perfil de produção fora do piloto. |
| `PROGRESS.md` | Modificar | Seção curta com link para as pendências e para C-01–C-10 (sem copiar a tabela). |
| `LICENSE` | Condicional | Só com P-01 "Aprovada". |

Ordem das tarefas (M-06): o plano de piloto (Task 4) vem antes do PRD (Task 5), para o PRD já nascer com links válidos.

---

### Task 1: Branch de trabalho e inventário de evidências

**Files:**
- Create: `docs/escopo/inventario-vinculo-institucional.md`
- Add (sem alterar): `docs/escopo/decisoes-2026-11-01.md`

**Interfaces:**
- Produces: tabela `ID (I-NN) | Arquivo:linha | Trecho resumido | Tipo (D1–D12) | Destino (reescrever / Futuro / C-NN)`. Mensagens de commit das Tasks 5–9 citam I-NN quando tratam um item.

- [ ] **Step 0: Pré-condição — o registro de decisões já existe**

Run: `[ -e docs/escopo/decisoes-2026-11-01.md ] || { echo 'registro ausente: peça o arquivo à equipe; não recrie nem reescreva'; exit 1; }`
Expected: nenhuma saída. Se falhar, parar o plano. O registro foi produzido fora do repositório e nunca é gerado nem editado por agente.

- [ ] **Step 1: Criar a branch e uma pasta temporária**

Run: `git switch develop && git pull --ff-only && git switch -c docs/escopo-educativo-aberto && export SCRATCH=$(mktemp -d)`
Expected: `Switched to a new branch 'docs/escopo-educativo-aberto'`. As Tasks 1 e 10 usam `$SCRATCH`.

- [ ] **Step 2: Gerar a lista bruta (comando replicável, M-07)**

Run: `git --no-pager grep -nIiE 'e-SUS|eSUS|CNES|\bCNS\b|CADSUS|RNDS|DATASUS|SISAB|Gov\.br|ICP-Brasil|\bUBS\b|Secretaria|prefeitura|munic[ií]pi|matr[ií]cula|SAMU|\b192\b|Pulumi|cert-manager|Fluentd|SMS|Manchester|Play Store|Google Play' -- '*.md' '*.yaml' '*.yml' '.env.example' 'apps/*/lib/*.dart' 'apps/*/lib/**/*.dart' ':!PROGRESS.md' ':!docs/superpowers/**' ':!docs/ci-audit/**' ':!docs/auditoria-prd/**' ':!docs/escopo/**' ':!graphify-out/**' > "$SCRATCH/ocorrencias.txt"; wc -l < "$SCRATCH/ocorrencias.txt"`
Expected: algumas centenas de linhas. As linhas em `apps/` alimentam a lista C-NN, nunca edição.

- [ ] **Step 3: Escrever o inventário**

Uma linha por ocorrência relevante (agrupar repetições do mesmo parágrafo), classificada em D1–D12. Cabeçalho do arquivo: "Histórico (`PROGRESS.md`, planos, auditorias datadas) não entra: é registro, não especificação."

- [ ] **Step 4: Verificar cobertura**

Run: `for d in D1 D2 D3 D4 D5 D6 D7 D8 D9 D10 D11 D12; do printf '%s ' $d; grep -c "| $d |" docs/escopo/inventario-vinculo-institucional.md; done`
Expected: todos ≥ 1.

- [ ] **Step 5: Commit**

```bash
git add docs/escopo/decisoes-2026-11-01.md docs/escopo/inventario-vinculo-institucional.md
git commit -m "docs(escopo): registro de decisões e inventário do vínculo institucional"
```

---

### Task 2: Documento de escopo (`spec/escopo_projeto.md`)

**Files:**
- Create: `spec/escopo_projeto.md`

**Interfaces:**
- Produces: âncoras `#natureza-do-projeto`, `#pilares`, `#aviso-educativo`, `#dentro-do-escopo`, `#fora-do-escopo`, `#papeis-no-piloto`, `#pendencias`. Pendências P-01–P-11 (tarefas seguintes acrescentam P-12+ se surgirem; nunca renumeram).

- [ ] **Step 1: Escrever as seções, nesta ordem**

1. `## Natureza do projeto` — o "Contexto do pedido" em prosa, com o responsável e a frase "Neste momento não há vínculo com unidades de saúde públicas ou privadas".
2. `## Pilares` (M-02) — **Pilar A, educação em saúde para a comunidade, sem cadastro** (RF20, RF21, RF22, RF06, RF04 como autoavaliação educativa). **Pilar B, apoio ao acompanhamento comunitário por agentes participantes, como atividade de extensão do PET-Saúde** (RF02, RF03 como pedido de contato, RF07–RF11, RF15, RF24). Frase: "Se a equipe decidir pilotar só o pilar A, os requisitos do pilar B passam a Desejáveis e o piloto encurta."
3. `## Aviso educativo` — as duas versões canônicas e a regra: "Toda tela inicial dos apps, o texto legal e toda página de entrada da documentação exibem uma das duas versões."
4. `## Público-alvo` — comunidade; agentes participantes (estudantes do PET-Saúde sob supervisão de preceptor, P-03); preceptores e coordenação do PET-Saúde; desenvolvedores e pesquisadores que reutilizam o código.
5. `## Dentro do escopo` — conteúdo educativo offline com fontes citadas; autoavaliação educativa com as três saídas; lembretes locais; uso sem cadastro do pilar A; pilar B; backoffice para a equipe do projeto; implantação replicável (compose + APK em GitHub Releases).
6. `## Fora do escopo` — serviço de emergência; diagnóstico e classificação de risco clínico; integração com e-SUS, CNES, CNS/CADSUS, RNDS, Gov.br, SAMU, UBS ou Secretaria; dados ou infraestrutura de unidades de saúde; ACS em exercício da função como agente do piloto; CPF e SMS no piloto; Play Store. Cada item remete a `spec/trabalhos_futuros.md`.
7. `## Papéis no piloto` — `patient` → participante da comunidade; `acs` → agente participante (estudante do PET-Saúde sob supervisão; **não** ACS em exercício); `coordinator` → preceptor/coordenação do piloto; `admin` → administração técnica (equipe do PRISM). `ubs` no modelo = grupo do piloto até C-06.
8. `## Pendências` — fonte viva; o registro de 2026-11-01 é a origem. Colunas: `ID | Pendência | Decisão proposta | Ainda depende de | Bloqueia o piloto? | Status`. Copiar P-01–P-11 do registro §4 (decisão proposta resumida em uma frase, "Ainda depende de" e "Bloqueia" literais, Status "Proposta"). Abaixo da tabela: "Status possíveis: Proposta, Aprovada, Rejeitada, Substituída. Só a equipe muda o status."

- [ ] **Step 2: Verificar**

Run: `grep -c '^| P-' spec/escopo_projeto.md; grep -c '| Proposta |' spec/escopo_projeto.md; grep -cF 'O SinalACS não é um serviço de emergência: em caso de risco de vida, ligue 192 (SAMU).' spec/escopo_projeto.md; grep -ci manchester spec/escopo_projeto.md`
Expected: 11; 11; 1; 0.

- [ ] **Step 3: Commit**

```bash
git add spec/escopo_projeto.md
git commit -m "docs(escopo): natureza, pilares, aviso educativo, papéis e pendências"
```

---

### Task 3: Requisitos priorizados (`spec/requisitos_piloto.md`)

**Files:**
- Create: `spec/requisitos_piloto.md`

**Interfaces:**
- Consumes: âncoras e P-NN da Task 2.
- Produces: tabela `ID | Requisito | Pilar | Prioridade no piloto | Depende de instituição ou serviço pago? | Observação`. RF20–RF24 e RNF07–RNF10 são citados pelas Tasks 4, 5, 7 e 9.

- [ ] **Step 0: Parágrafo de dependência no topo do documento**

Texto obrigatório logo abaixo do título: "As prioridades abaixo assumem que as decisões propostas P-09, P-10 e P-11 (`spec/escopo_projeto.md#pendencias`) serão aprovadas. Se alguma for rejeitada:
- **P-09 rejeitada:** RF03 volta ao texto original do PRD **e passa a Futuro** no piloto. Rejeitar P-09 **nunca** significa manter o alerta com rótulo de urgência no piloto: sem a reformulação como pedido de contato, a função simplesmente não entra.
- **P-10 rejeitada:** RF24 sai do piloto e RF01 volta a Desejável, com a forma de login escolhida pela equipe. Se a escolha incluir CPF, **RNF09 é revisto** (deixa de dizer "sem CPF no piloto" e passa a exigir justificativa registrada da coleta) e C-05 é refeito para essa forma de login.
- **P-11 rejeitada:** RF04 passa a **Futuro** até haver parecer jurídico — não Desejável, porque Desejável ainda permitiria levar ao piloto a autoavaliação com cores e classificação de risco, que é o que gera o risco de enquadramento como software dispositivo médico. C-08 sai do portão, e **C-04 é revisto**: sem as três saídas não existe a saída 'Ligar 192', então o caminho que não envia nada perde a definição; o botão 'Ligar 192' permanece como ação fixa antes de qualquer pedido de contato."

- [ ] **Step 1: Tabela de RF**

| ID | Pilar | Prioridade | Observação obrigatória |
|---|---|---|---|
| RF01 login CPF+OTP | — | Futuro | Sem CPF e sem SMS no piloto (P-10); substituído por RF24. |
| RF02 convite por QR | B | Essencial | Emitido pelo agente participante; base do RF24. |
| RF03 alerta | B | Desejável | No piloto: **pedido de contato com o agente participante**, sem rótulo de urgência. Maior gravidade na autoavaliação → só "Ligar 192", sem envio (P-09, C-04). INV-03 vale para o pedido (ver Step 2b). |
| RF04 triagem | A | Essencial **somente** com as três saídas de P-11; caso contrário Desejável | Orientação educativa; nunca "classificação de risco". |
| RF05 status | B | Desejável | Estados descritivos do pedido de contato; sem "Atendido" como promessa. |
| RF06 lembretes locais | A | Essencial | Sem servidor. |
| RF07 login do agente | B | Essencial | Identificador emitido pela equipe do projeto. |
| RF08–RF11 | B | Essencial | Território do grupo; fila; visita offline. |
| RF12 geofencing | — | Futuro | Política de localização em segundo plano. |
| RF13 SAMU/UBS | — | Futuro | Fica só a discagem local para 192 (não é integração). |
| RF14 push | B | Desejável | FCM sem custo; o app funciona sem push. |
| RF15 sync | B | Essencial | — |
| RF16 motor determinístico | A | Essencial | "Motor de autoavaliação determinístico por árvore de decisão fechada"; sem "Manchester" (M-05); validação clínica é Futuro. |
| RF17 auditoria | B | Essencial | — |
| RF18 modo escuro | — | Desejável | — |
| RF19 escalonamento | B | Desejável | Para a coordenação do piloto, não para UBS. |
| **RF20** conteúdo educativo offline | A | Essencial | Fontes: materiais públicos do Ministério da Saúde e da BVS, sempre citados; revisão por preceptores do PET-Saúde antes de cada versão (P-07). |
| **RF21** aviso educativo na primeira abertura, em "Sobre" e no texto legal | A | Essencial | Texto canônico (M-08). |
| **RF22** uso sem cadastro (conteúdo e lembretes) | A | Essencial | — |
| **RF23** questionários do piloto (pré/pós, SUS, reconhecimento do aviso) | — | Desejável | Pode ser formulário externo sem dado de saúde; nesse caso o serviço é **operador de dados pessoais** e precisa constar no TCLE (P-04) e na §0 de `spec/lgpd_design.md`. Serviço `[A DEFINIR]`. |
| **RF24** acesso do participante ao acompanhamento por convite QR + PIN local, identificador pseudônimo, e-mail opcional, sem CPF/SMS | B | Essencial | P-10, C-05. |

- [ ] **Step 2: Tabela de RNF**

RNF01 MQTT Desejável; RNF02 offline Essencial; RNF03 cifra Essencial; RNF04 TLS Essencial (Let's Encrypt pelo Traefik, sem cert-manager); RNF05 acessibilidade Essencial; RNF06 RBAC Essencial. Novos: **RNF07** implantável por terceiros com um `docker compose` **e** APK assinado publicado em GitHub Releases (M-03), custo mensal ≤ teto de P-08 (Essencial); **RNF08** nenhum componente Essencial depende de serviço pago sem alternativa gratuita — SMS e Play Store incluídos (Essencial); **RNF09** coleta mínima: nenhum dado pessoal para o pilar A; sem CPF no piloto (Essencial); **RNF10** documentação em pt-BR e licença MIT (Essencial).

- [ ] **Step 2b: Seção `## INV-03 no piloto`**

Texto com estes três pontos, nesta ordem:
1. "INV-03 vale para todo pedido de contato com o agente participante: um pedido enviado nunca é descartado em silêncio (entrega com ACK, reserva HTTP, escalonamento RF19)."
2. "A saída 'Ligar 192' da autoavaliação **não gera pedido de contato** — é uma mudança de comportamento do sistema (C-04), não só de apresentação. Ela não é descarte silencioso porque: (a) a orientação 'Ligar 192', com o botão de discagem, é exibida ao participante antes de qualquer outra ação e não pode ser fechada sem uma escolha explícita; (b) a exibição fica registrada localmente na trilha de auditoria do aparelho (evento com data, hora e versão do motor; sem respostas em texto claro)." Logo abaixo: "Esse evento é **dado de saúde** (revela que a pessoa recebeu a orientação de maior gravidade), mesmo sem as respostas. Fica só no aparelho, cifrado, é apagado automaticamente após **30 dias** (prazo proposto pelo plano, ajustável no TCLE, P-04) e pode ser apagado a qualquer momento pela opção 'Apagar meus dados' (C-10)."
3. "Se o participante, depois de ver a orientação, quiser também falar com o agente, o pedido de contato é um ato separado e volta a estar sob INV-03."

- [ ] **Step 3: Nenhum ID existente mudou de significado**

Run: `for id in RF01 RF03 RF07 RF13 RF16 RNF04 RNF06; do printf '%s | PRD: ' $id; grep -m1 -oE "\*\*$id\*\* \| [^|]+" spec/PRD_system.md; printf '     | novo: '; grep -m1 -oE "^\| \*?\*?$id[^|]*\| [^|]+" spec/requisitos_piloto.md; done`
Expected: mesma função para cada par (RF03 continua sendo o envio do paciente ao agente, agora reenquadrado).

- [ ] **Step 4: Essencial não depende de instituição nem de serviço pago**

Run: `grep -E '\| Essencial' spec/requisitos_piloto.md | grep -E '\| Sim'`
Expected: nenhuma linha.

- [ ] **Step 5: Commit**

```bash
git add spec/requisitos_piloto.md
git commit -m "docs(requisitos): prioridade do piloto, pilares e RF20–RF24, RNF07–RNF10"
```

---

### Task 4: Plano de piloto (`spec/plano_piloto.md`)

**Files:**
- Create: `spec/plano_piloto.md`
- Create (esqueleto): `docs/escopo/mudancas-de-codigo-recomendadas.md`

**Interfaces:**
- Consumes: P-02–P-11; RF/RNF da Task 3.
- Produces: IDs C-01–C-10 fixados no esqueleto (título de uma linha cada, nível do portão). A Task 9 preenche as colunas, sem mudar IDs nem níveis.

- [ ] **Step 0: Esqueleto de `docs/escopo/mudancas-de-codigo-recomendadas.md`**

Cabeçalho "Mudanças de código recomendadas — não implementadas neste plano". Seções `## Portão do piloto — segurança e legal` (C-01 texto legal; C-02 aviso na primeira abertura; C-04 pedido de contato e saída 192; C-05 acesso sem CPF/SMS; C-06 "UBS" nos textos; C-08 autoavaliação com três saídas; C-10 "Apagar meus dados" e retenção local), `## Portão do piloto — funcional` (C-03 biblioteca educativa, obrigatória se o pilar A estiver no piloto) e `## Demais` (C-07 discagem só 192; C-09 "Manchester" em código). Uma linha por ID, no formato `- C-NN — título`, sem detalhes (a Task 9 troca as listas por tabelas mantendo IDs e seções).

- [ ] **Step 1: Escrever as seções**

1. `## Objetivo` — avaliar se o SinalACS (a) apoia educação em saúde na comunidade, (b) é usável por pessoas com baixo letramento digital, (c) funciona offline sem perda de dados, (d) é implantável por terceiros com baixo custo.
2. `## Participantes` — proposta (P-05): 2 a 3 agentes participantes (estudantes do PET-Saúde sob supervisão de preceptor, P-03) e 15 a 30 participantes da comunidade; território `[A DEFINIR]`. Inclusão: 18+ anos, Android 7.0+ (API 24), TCLE assinado. Exclusão: menores; ACS em exercício da função no papel de agente.
3. `## Duração` — 8 semanas (1 preparação, 6 uso, 1 encerramento). A data de início depende do parecer do CEP (P-04).
4. `## Pré-requisitos de código` (M-01), em dois níveis, remetendo a `docs/escopo/mudancas-de-codigo-recomendadas.md`:
   - **Segurança e legal — nenhuma coleta com participantes antes de:** C-01 (controlador, encarregado e aviso no texto legal), C-02 (aviso na primeira abertura), C-04 (pedido de contato sem urgência; "Ligar 192" antes de qualquer pedido), C-05 (acesso sem CPF/SMS, RF24), C-06 ("UBS" aparece hoje a participantes — app do paciente, texto legal, app do agente — logo entra no portão) e C-08 (autoavaliação com três saídas, P-11) e C-10 ("Apagar meus dados" no app do paciente e retenção local de 30 dias dos eventos de auditoria do aparelho).
   - **Funcional — obrigatório se o pilar A estiver no piloto:** C-03 (biblioteca de conteúdo educativo). Sem ele não há como medir o objetivo (a) nem o ganho de conhecimento.
5. `## Pré-requisitos não técnicos` — P-02 (confirmação jurídica e encarregado), P-03, P-04 (submissão na Plataforma Brasil iniciada em paralelo à documentação), P-05 (território), P-07 (temas e revisores), P-11 (parecer jurídico).
6. `## Dados` — só sintéticos até P-02 e P-04; depois, o mínimo (RNF09); nenhum dado de unidade de saúde; distribuição do app por APK em GitHub Releases.
7. `## Métricas` — tabela métrica × fonte × meta: SUS ≥ 68; primeiro uso sem ajuda ≥ 80% (H2); sincronização offline ≥ 99,5% (H4, `telemetry_events`); ganho de conhecimento pré/pós (instrumento `[A DEFINIR]`, P-07); custo mensal ≤ R$ 50 (teto proposto em P-08); sessões sem falha ≥ 99%; reconhecimento do aviso ≥ 90%.
8. `## Critérios de sucesso e de parada` — sucesso: metas de usabilidade, sincronização e reconhecimento do aviso atingidas **e** nenhum incidente de segurança ou de expectativa de socorro. **Parada (M-09):** se menos de 90% reconhecerem o aviso na primeira semana, o piloto pausa e a tela é corrigida antes de retomar; qualquer relato de participante que esperou socorro do app também pausa.
9. `## Ética, LGPD e encerramento` — controlador, encarregado e base legal conforme decisão proposta P-02 (art. 11, II, "c", com TCLE), status Proposta. Se RF23 usar formulário externo, o serviço consta como operador no TCLE. **Encerramento (M-04):** após o fim do uso, exportar o necessário à pesquisa já anonimizado — com amostra de 15 a 30 pessoas num território pequeno o risco de reidentificação é real, então o critério mínimo proposto é retirar o território e qualquer geolocalização, agregar idade em faixas e não exportar texto livre; o critério final é `[A DEFINIR]` no TCLE (P-04) —, apagar os dados identificáveis do servidor e dos aparelhos dos agentes (wipe remoto existente, #81). **O pilar A não é alcançado pelo wipe** — o uso é sem cadastro e os aparelhos não estão registrados —, então a eliminação dos dados locais do participante depende de C-10: a opção "Apagar meus dados" (comunicada a todos no encerramento, junto com a orientação de que desinstalar o app também apaga) e a expiração automática dos eventos locais em 30 dias e registrar a eliminação na trilha de auditoria; prazo `[A DEFINIR]` (fixado no TCLE, P-04).
10. `## Riscos` — participante tratar o pedido de contato como emergência (RF21, "Ligar 192", critério de parada); enquadramento como software como dispositivo médico (P-11); perda de aparelho; custo acima do teto; atraso do CEP.

- [ ] **Step 2: Verificar**

Run: `grep -cE '^## ' spec/plano_piloto.md; grep -oE 'C-(0[1-68]|10)' spec/plano_piloto.md | sort -u | wc -l; grep -ci 'pausa' spec/plano_piloto.md; grep -ci manchester spec/plano_piloto.md`
Expected: 10; 8; ≥ 1; 0.

Run: `grep -ni 'urgência' spec/plano_piloto.md`
Expected: só linhas que negam o rótulo ("sem rótulo de urgência"); conferir à mão.

Run: `grep -cE '^- C-(0[1-9]|10)' docs/escopo/mudancas-de-codigo-recomendadas.md; [ -e docs/escopo/mudancas-de-codigo-recomendadas.md ] && echo link-ok`
Expected: 10; `link-ok`.

- [ ] **Step 3: Commit**

```bash
git add spec/plano_piloto.md docs/escopo/mudancas-de-codigo-recomendadas.md
git commit -m "docs(piloto): portão de código em dois níveis, métricas, parada e encerramento"
```

---

### Task 5: PRD alinhado ao escopo

**Files:**
- Modify: `spec/PRD_system.md` (topo; §1.1; §1.2; §1.3; §2.1 diagrama; §2.2; §3.2; §6; §7 T5; §8 A1 e A3)

**Interfaces:**
- Consumes: `spec/escopo_projeto.md`, `spec/requisitos_piloto.md`, `spec/plano_piloto.md`, `spec/trabalhos_futuros.md` (Task 8 — único link ainda pendente; a Task 10 confere).

- [ ] **Step 1: Bloco de escopo abaixo do título**

`> **Escopo atual (2026-11-01):**` + aviso canônico longo + "Este PRD foi escrito para operação dentro da Atenção Primária. Pilares, prioridades e piloto: `spec/escopo_projeto.md`, `spec/requisitos_piloto.md`, `spec/plano_piloto.md`; o que depende de unidade de saúde: `spec/trabalhos_futuros.md`."

- [ ] **Step 2: §1.1**

Novo parágrafo "Problema no escopo educativo" (pilares A e B) antes do "Problema Central", que passa a "Contexto de origem". JTBD novo "Aprender sobre um tema de saúde sem cadastro" (RF20). e-SUS APS deixa de ser concorrente: "sistemas oficiais de registro (fora do escopo; ver trabalhos futuros)". Item 1 da proposta de valor: "Motor de autoavaliação determinístico por árvore de decisão fechada, sem IA" (sem Manchester).

- [ ] **Step 3: §1.2 e §1.3**

H1 e H3 → "Futuro (exige operação em serviço de saúde)"; H2, H4 mantidas; remissão ao plano de piloto. TMRAV → "métrica técnica de latência de entrega do pedido de contato, sem compromisso de atendimento"; aderência à classificação e ≥ 8 visitas/ACS/dia → Futuro.

- [ ] **Step 4: Promessa de socorro e rótulo de urgência**

Run: `git --no-pager grep -nE 'chega ao ACS em|será atendid|garant[ei].*atendimento|botão de pânico|[Aa]lerta de [Uu]rgência' -- spec/PRD_system.md`
Para cada linha: acrescentar "(no piloto: pedido de contato com o agente participante, sem rótulo de urgência; o SinalACS não é serviço de emergência — ligue 192)". Rodar de novo.
Expected na segunda execução: toda linha contém `192`.

- [ ] **Step 5: Manchester, tabela §2.2 e seções finais**

Substituir as 4 ocorrências de "Manchester" (linhas ~29, ~117, ~151, ~451) por "árvore de decisão fechada". §2.2: nota no cabeçalho remetendo prioridades a `spec/requisitos_piloto.md` (tabela original fica). RF01: "Futuro no piloto (P-10)". RF03: "no piloto, pedido de contato (P-09)". RF07: "Identificador emitido pela equipe do projeto". RF13: "Futuro — ver trabalhos futuros". §6: "Roadmap original; o piloto segue `spec/plano_piloto.md`". T5 e §8 A1/A3: "Futuro / referência — não é pré-requisito do piloto".

- [ ] **Step 6: Verificar**

Run: `grep -ci manchester spec/PRD_system.md; grep -c 'spec/requisitos_piloto.md' spec/PRD_system.md; grep -E '\*\*RF13\*\*' spec/PRD_system.md | grep -c Futuro`
Expected: 0; ≥ 3; 1.

- [ ] **Step 7: Commit**

```bash
git add spec/PRD_system.md
git commit -m "docs(prd): escopo educativo, pedido de contato e remoção de marca registrada"
```

---

### Task 6: Arquitetura, hospedagem e distribuição independentes

**Files:**
- Modify: `spec/stack.md` (nova §0; §1 Manchester; §2 IaC), `backend/DEPLOY.md` (cabeçalho)
- Modify (só comentários): `.env.example`, `backend/sinalacs_server/config/production.yaml`

- [ ] **Step 1: `spec/stack.md` §0 "Hospedagem e distribuição independentes e de baixo custo"**

(a) Princípio: qualquer pessoa replica com o repositório, um `docker compose` e o APK publicado. (b) Perfis: **Local/demonstração** (custo zero), **Piloto** (um host Docker em camada gratuita ou VPS mínima, Postgres no mesmo host, Let's Encrypt pelo Traefik, `backend/DEPLOY.md`), **Futuro** (Pulumi, redes privadas, PKI de produção #118). (c) Tabela componente × obrigatório no piloto × alternativa gratuita: Postgres (sim), Traefik (sim), Mosquitto (só pilar B com RF03), Gorush+FCM (não), gateway SMS (não usado — P-10), Play Store (não — Futuro). (d) **Distribuição (M-03):** APK assinado publicado em GitHub Releases; Play Store exige conta paga e é Futuro; a chave de assinatura de release é pendência já registrada no `CLAUDE.md`. (e) Custo: teto proposto de R$ 50/mês (P-08, status Proposta), revisto na data da contratação; nenhum preço de provedor fixado. (f) Nenhum componente em infraestrutura de unidade de saúde.

- [ ] **Step 2: `spec/stack.md` §1 e §2**

§1: "inspirado no Protocolo de Manchester" → "árvore de decisão fechada". §2: Pulumi "(Futuro — o piloto não usa IaC; ver §0)".

- [ ] **Step 3: `backend/DEPLOY.md`**

Primeiro parágrafo: "caminho recomendado para o piloto educativo (RNF07/RNF08)". Retirar "autenticação institucional real" da lista do que este caminho não substitui; remeter o restante a `spec/trabalhos_futuros.md`. Manter "Não use com dados reais de pacientes" e acrescentar "dados de participantes só depois dos pré-requisitos de `spec/plano_piloto.md`".

- [ ] **Step 4: Comentários de configuração**

`.env.example`, junto de `SMS_GATEWAY`: "Não usado no piloto (P-10 em spec/escopo_projeto.md: sem CPF e sem SMS). Fora de development, o login por OTP fica indisponível sem gateway." `production.yaml`, no topo: "Perfil de produção institucional — Futuro; o piloto segue backend/DEPLOY.md."

- [ ] **Step 5: Só comentários mudaram nos arquivos de configuração**

Run: `git diff -U0 .env.example backend/sinalacs_server/config/production.yaml | grep -E '^[+-][^+-]' | grep -vE '^[+-]\s*#'`
Expected: nenhuma linha.

- [ ] **Step 6: Commit**

```bash
git add spec/stack.md backend/DEPLOY.md .env.example backend/sinalacs_server/config/production.yaml
git commit -m "docs(stack): hospedagem de baixo custo e distribuição por APK no GitHub Releases"
```

---

### Task 7: Privacidade e LGPD

**Files:**
- Modify: `spec/lgpd_design.md` (nova §0; §LGPD-RF06; §LGPD-RF17; §3.6; glossário; linha ~436 Manchester), `spec/lgpd_data_audit.md` (aviso no topo)

- [ ] **Step 1: §0 "Escopo do piloto educativo"**

Decisão proposta P-02 (status Proposta): controlador UFRR, por meio do projeto, com o líder do PRISM como pesquisador responsável; encarregado é o encarregado institucional da UFRR (nome e contato `[A DEFINIR]`); base legal art. 11, II, "c" (estudo por órgão de pesquisa), com TCLE; confirmação jurídica `[A DEFINIR]`. Coleta mínima (RNF09): pilar A sem cadastro e dados locais; pilar B por identificador pseudônimo, sem CPF, e-mail opcional (P-10). Dado de saúde é sensível sempre, inclusive respostas da autoavaliação. Nenhum compartilhamento com terceiros de saúde no piloto. Operadores: se RF23 usar formulário externo, esse serviço é operador de dados pessoais (nome `[A DEFINIR]`), listado aqui e no TCLE. Dados locais do pilar A (eventos de auditoria do aparelho, lembretes, respostas da autoavaliação): ficam só no aparelho, retenção de 30 dias para os eventos, eliminação pelo participante em "Apagar meus dados" (C-10) — o wipe remoto não alcança aparelhos sem cadastro. Encerramento e critério de anonimização conforme `spec/plano_piloto.md` (M-04).

- [ ] **Step 2: Ajustes pontuais**

LGPD-RF06, LGPD-RF17, §3.6: "(Futuro — sem compartilhamento no piloto; ver `spec/trabalhos_futuros.md`)". Glossário: exemplo de controlador "Secretaria de Saúde" → "no piloto, a UFRR (decisão proposta P-02)". Linha ~436: remover "Manchester" se houver.

- [ ] **Step 3: `spec/lgpd_data_audit.md`**

Aviso no topo: classificação continua válida; `ubs`/coordenação = grupos e preceptores do piloto; `users.cpfHash` não é preenchido no piloto (P-10) — a coluna existe até a mudança C-05.

- [ ] **Step 4: Verificar**

Run: `grep -nE 'Secretaria de Saúde' spec/lgpd_design.md | grep -vE 'Futuro|origem'; grep -niE 'controlador.{0,40}UFRR|UFRR.{0,40}controlador' spec/lgpd_design.md | grep -vi 'propost'`
Expected: nenhuma linha nas duas (toda menção à UFRR como controladora vem marcada como proposta; outras menções, como a do encarregado institucional, não são afetadas).

- [ ] **Step 5: Commit**

```bash
git add spec/lgpd_design.md spec/lgpd_data_audit.md
git commit -m "docs(lgpd): escopo do piloto, papéis propostos e coleta mínima"
```

---

### Task 8: Trabalhos futuros, documentos de origem e remoção de "Manchester"

**Files:**
- Create: `spec/trabalhos_futuros.md`
- Modify: `spec/idea.md`, `spec/security_assessment.md`, `spec/sys_flow.md`, `spec/test_plan.md`, `docs/telas-acs.md`, `docs/telas-admin.md`, `docs/telas-paciente.md`, `docs/showcase/slides.md`, `docs/roteiro-video-sponsor.md`, `docs/publicacao-google-play.md`

- [ ] **Step 1: `spec/trabalhos_futuros.md`**

Abertura: "Nada aqui é pré-requisito do piloto." Seções: `## Integrações com serviços de saúde` (e-SUS APS, CNES, CNS/CADSUS, RNDS, Gov.br, SAMU, UBS/Secretaria — o que faria, pré-condição institucional, requisito relacionado); `## Funções que dependem de operação em serviço` (RF01 com CPF/SMS, RF12, RF13, H1, H3, visitas por ACS/dia, coordenação por UBS, validação clínica do motor); `## Distribuição e infraestrutura de produção` (Play Store, Pulumi, PKI de produção #118, chave no TEE #116, separação de papéis do banco #96, iOS); `## Próximos planos` (não são integrações, mas ficam registrados aqui para não se perderem): (1) **material para o CEP** — minuta de TCLE e projeto para a Plataforma Brasil, a pendência de maior prazo (P-04), com conteúdo institucional `[A DEFINIR]`; (2) implementação do portão de código C-01–C-08 e C-10.

- [ ] **Step 2: Avisos nos documentos de origem**

`spec/idea.md`: bloco "Documento de concepção original; escopo atual em `spec/escopo_projeto.md`"; "(Futuro)" nos itens 1 e 5 e na seção do piloto em UBS. `spec/security_assessment.md`: IdP "e-SUS APS/CNS" → "(Futuro; no piloto, identidade própria do projeto)". `docs/telas-*.md`: aviso curto no topo; em `telas-acs.md`, "matrícula/CNS" → "identificador do agente participante"; "coordenação da UBS" ganha "(no piloto: preceptor/coordenação do piloto)"; "Ligar para a UBS" ganha "(C-07: será substituído por 192)". `docs/publicacao-google-play.md`: aviso "Futuro — no piloto o app é distribuído por APK em GitHub Releases (RNF07)".

- [ ] **Step 3: Remover "Manchester" do texto de produto (M-05)**

Run: `git --no-pager grep -nIi manchester -- 'spec/*.md' 'docs/*.md' 'docs/showcase/*' 'README.md'`
Para cada linha, trocar a expressão por "árvore de decisão fechada" (ou suprimir "inspirado no Protocolo de Manchester"). Em `docs/showcase/preview.html`, `spec/ui_acs/acs_3_dashboard_priorizacao.html` e `spec/ui_paciente/paciente_3_triagem.html`, mesmo tratamento só no texto visível. Código (`apps/`, `backend/`) e `video/` ficam fora: todas as ocorrências do inventário vão para C-09. Rodar de novo.
Expected na segunda execução: nenhuma linha.

- [ ] **Step 4: Verificar integrações institucionais**

Run: `git --no-pager grep -nIiE 'e-SUS|CNES|Gov\.br|CADSUS|RNDS' -- 'spec/*.md' 'docs/telas-*.md' 'README.md' | grep -viE 'futuro|trabalhos_futuros|fora do escopo|origem'`
Expected: nenhuma linha.

- [ ] **Step 5: Commit**

```bash
git add spec/trabalhos_futuros.md spec/idea.md spec/security_assessment.md spec/sys_flow.md spec/test_plan.md \
  spec/ui_acs/acs_3_dashboard_priorizacao.html spec/ui_paciente/paciente_3_triagem.html \
  docs/telas-acs.md docs/telas-admin.md docs/telas-paciente.md docs/showcase/slides.md docs/showcase/preview.html \
  docs/roteiro-video-sponsor.md docs/publicacao-google-play.md
git status --short   # conferir: nada fora da lista acima ficou staged
git commit -m "docs(escopo): trabalhos futuros e remoção de marca registrada do texto de produto"
```

---

### Task 9: Entrada do repositório, licença, contato e mudanças de código recomendadas

**Files:**
- Modify: `README.md`, `CONTRIBUTING.md`, `CLAUDE.md`, `AGENTS.md`, `backend/CLAUDE.md`, `.github/SECURITY.md`, `PROGRESS.md`
- Modify (preencher o esqueleto da Task 4): `docs/escopo/mudancas-de-codigo-recomendadas.md`
- Condicional: `LICENSE`
- Não modificar: `.github/CODE_OF_CONDUCT.draft.md`

- [ ] **Step 1: README**

Primeiro parágrafo: plataforma aberta de **educação social em saúde** (pilar A), com apoio ao acompanhamento comunitário (pilar B); autoria PRISM/UFRR + PET-Saúde; responsável Prof. Herbert Oliveira Rocha. Aviso canônico longo logo abaixo; links para os quatro documentos novos. Seção `## Instalação do app`: APK em GitHub Releases. Seção `## Licença`: "MIT (ver `LICENSE`)."

- [ ] **Step 2: CONTRIBUTING, CLAUDE.md, AGENTS.md, backend/CLAUDE.md**

Parágrafo "Natureza do projeto": aviso curto; regra "nenhuma contribuição pode tornar um requisito Essencial dependente de unidade de saúde, sistema oficial ou serviço pago sem alternativa gratuita (RNF07/RNF08)"; "não usar a marca Manchester em texto de produto"; dados só sintéticos. `CLAUDE.md` (regra de triagem) e `AGENTS.md:94`: "determinística, por árvore de decisão fechada, nunca alterável manualmente" — sem Manchester. `backend/CLAUDE.md:105`: mesma troca. `CLAUDE.md` "Required reading": `spec/escopo_projeto.md` e `spec/requisitos_piloto.md` em primeiro lugar.

- [ ] **Step 3: Contato público (P-06)**

`.github/SECURITY.md` já usa Private Vulnerability Reporting: acrescentar "Dúvidas gerais e conduta: GitHub Discussions. E-mail institucional: `[A DEFINIR]`." Registrar em `spec/escopo_projeto.md` (P-06) o passo manual do mantenedor: ativar Private Vulnerability Reporting e Discussions nas configurações do repositório — **o agente não altera configurações do GitHub**. O código de conduta continua rascunho até o contato existir.

- [ ] **Step 4: LICENSE (P-01, condicional)**

Run: `grep -E '^\| P-01 ' spec/escopo_projeto.md | grep -c '| Aprovada |'`
Se `1`: trocar a linha de copyright por `Copyright (c) 2026 Herbert Oliveira Rocha e contribuidores do SinalACS (Grupo de Pesquisa PRISM/UFRR)`. Se `0`: não tocar no `LICENSE`.

- [ ] **Step 5: `docs/escopo/mudancas-de-codigo-recomendadas.md`**

Preencher as três seções do esqueleto (IDs e níveis já fixados na Task 4) como tabelas `ID | Arquivo | Mudança | Motivo | Bloqueado por`:

**Portão do piloto — segurança e legal (M-01)** — nenhuma coleta antes destas:
- C-01 `apps/patient/lib/core/legal/legal_documents.dart` — controlador/encarregado conforme P-02; retirar "da Secretaria" e "sua UBS"; **incluir o aviso canônico longo (M-08)**; nova `LegalVersion` e `consentPolicyVersion` (o próprio arquivo exige). D6. Bloqueado por P-02.
- C-02 apps paciente e ACS — tela de primeira abertura e "Sobre" com o aviso (RF21).
- C-04 app paciente e backend — **mudança de comportamento, não só de texto**: alerta vira pedido de contato sem rótulo de urgência; "Ligar 192" antes de qualquer pedido; a saída "Ligar 192" da autoavaliação não gera pedido, exige escolha explícita do participante para fechar a orientação e grava um evento local na trilha de auditoria do aparelho; status sem "Atendido" como promessa. RF03/RF05, P-09. Como INV-03 continua valendo: `spec/requisitos_piloto.md` §INV-03 no piloto. Testes exigidos: pedido enviado nunca some (os de INV-03 existentes seguem verdes); saída 192 grava o evento local e não chama `alerts.createRedAlert`.
- C-05 backend e app paciente — RF24: convite QR + PIN local, identificador pseudônimo, sem CPF/SMS, e-mail opcional (`config/app_config.dart` deixa de exigir `SMS_GATEWAY` no perfil do piloto). P-10.
- C-06 textos "UBS"/"coordenação da UBS" nos três apps (ex.: `apps/patient/lib/app/app.dart:1966,2035`, `apps/acs/lib/app/device_wiped_screen.dart:46`, `apps/admin/lib/app/app.dart:341,716`) → grupo/coordenação do piloto; renomear `ubs.spy.yaml` fica como dívida técnica separada (migração). Essencial porque "UBS" aparece a participantes (registro §5).
- C-08 app paciente — autoavaliação com três saídas ("Cuidar-se em casa", "Procurar atendimento", "Ligar 192"), sem cor ou rótulo de risco clínico ao participante. O cálculo do motor determinístico (`TriageEngine`) não muda: mesma entrada, mesmo resultado, nunca alterável manualmente (INV-02). O que muda é o texto exibido **e**, para a saída "Ligar 192", o envio — essa parte do comportamento é a de C-04, da qual C-08 depende. P-11, RF04/RF16.
- C-10 app paciente — opção "Apagar meus dados" em "Sobre"/configurações, disponível sem cadastro, que apaga banco local, lembretes e eventos de auditoria do aparelho (e, se houver sessão do pilar B, encerra a sessão e pede ao servidor o pedido de eliminação já existente); expiração automática dos eventos locais de auditoria em 30 dias. Motivo: dados de saúde locais do pilar A sem caminho de eliminação; o wipe (#81) só alcança aparelhos de agentes. RNF09, LGPD-RF07. Testes exigidos: após "Apagar meus dados" nenhum evento local resta; evento com mais de 30 dias some na próxima abertura.

**Portão do piloto — funcional** — obrigatório se o pilar A estiver no piloto:
- C-03 app paciente — biblioteca de conteúdo educativo offline sem login (RF20/RF22). Bloqueado por P-07. Sem ela não se mede o objetivo (a) nem o ganho de conhecimento.

**Demais:**
- C-07 `apps/acs/lib/app/app.dart:4017,4051` e `apps/acs/lib/core/services/emergency_dialer.dart` — só discagem 192; retirar "Ligar para a UBS". RF13 Futuro.
- C-09 **toda ocorrência de "Manchester" em código encontrada no inventário da Task 1** (`apps/**`, `backend/**`), listada arquivo:linha — no levantamento de 2026-11-01: `backend/sinalacs_server/lib/src/endpoints/triage_endpoint.dart:7` (que gera `backend/sinalacs_client/lib/src/protocol/client.dart:1291`) — mais `video/roteiro.timing.json`. Remover a marca. M-05.

- [ ] **Step 6: PROGRESS.md**

Seção "Escopo educativo e aberto (2026-11-01)": uma frase de resumo, link para `spec/escopo_projeto.md#pendencias` (sem copiar a tabela), link para o portão (segurança e legal: C-01/C-02/C-04/C-05/C-06/C-08/C-10; funcional: C-03) e para o registro de decisões.

- [ ] **Step 7: Nada de código alterado**

Run: `git diff --name-only develop -- apps backend/sinalacs_server/lib backend/sinalacs_client .github/CODE_OF_CONDUCT.draft.md video`
Expected: nenhuma linha.

- [ ] **Step 8: Commit**

```bash
git add README.md CONTRIBUTING.md CLAUDE.md AGENTS.md backend/CLAUDE.md .github/SECURITY.md PROGRESS.md spec/escopo_projeto.md docs/escopo/mudancas-de-codigo-recomendadas.md
git add LICENSE 2>/dev/null || true
git commit -m "docs: natureza do projeto na entrada, contato público e portão de código do piloto"
```

---

### Task 10: Verificação final de coerência

**Files:** nenhum novo; correções inline nos arquivos das Tasks 2–9.

- [ ] **Step 1: Só documentação e comentários mudaram**

Run: `git diff --name-only develop | grep -vE '\.md$|\.html$|^\.env\.example$|config/production\.yaml$|^LICENSE$'`
Expected: nenhuma linha. Para `.html`, conferir com `git diff develop -- '*.html'` que só texto visível mudou.

- [ ] **Step 2: Nenhuma promessa de socorro nem rótulo de urgência sem ressalva**

Run: `git --no-pager grep -nIiE 'botão de pânico|será atendid|chega ao ACS em|garant[ei].{0,20}atendimento|alerta de urgência' -- 'spec/escopo_projeto.md' 'spec/requisitos_piloto.md' 'spec/plano_piloto.md' 'spec/PRD_system.md' 'README.md' 'docs/telas-*.md' | grep -vE '192|Futuro|origem'`
Expected: nenhuma linha.

- [ ] **Step 2b: INV-03 explicada para a saída "Ligar 192"**

Run: `sed -n '/^## INV-03 no piloto/,/^## /p' spec/requisitos_piloto.md | grep -oE 'não é descarte silencioso|trilha de auditoria|ato separado' | sort -u | wc -l; grep -n 'só de apresentação\|apenas de apresentação' docs/escopo/mudancas-de-codigo-recomendadas.md`
Expected: 3; nenhuma linha.

- [ ] **Step 3: Nada inventado e nada proposto apresentado como aprovado**

Run: `git diff develop -- '*.md' | grep '^+' | grep -iE 'CNPJ|CAAE|parecer (n|favor)|aprovad[oa] pel|@ufrr|@[a-z]+\.(br|com)'; git diff develop -- '*.md' | grep '^+' | grep -iE 'controlador.{0,40}UFRR|UFRR.{0,40}controlador' | grep -viE 'propost'`
Expected: nenhuma linha nas duas.

- [ ] **Step 4: Nenhum "Manchester" em texto de produto**

Run: `git --no-pager grep -nIi manchester -- ':!PROGRESS.md' ':!docs/superpowers/**' ':!docs/auditoria-prd/**' ':!docs/ci-audit/**' ':!graphify-out/**' ':!docs/escopo/decisoes-2026-11-01.md' ':!docs/escopo/inventario-vinculo-institucional.md' ':!docs/escopo/mudancas-de-codigo-recomendadas.md' ':!apps/**' ':!backend/sinalacs_server/lib/**' ':!backend/sinalacs_client/lib/**' ':!video/**'`
Expected: nenhuma linha. Conferir também que toda ocorrência excluída está em C-09: `git --no-pager grep -lIi manchester -- 'apps/**' 'backend/*/lib/**' 'video/**' | while read -r f; do grep -qF "$f" docs/escopo/mudancas-de-codigo-recomendadas.md || echo "fora de C-09: $f"; done` → nenhuma linha.

- [ ] **Step 5: Aviso canônico idêntico**

Run: `for f in spec/escopo_projeto.md spec/PRD_system.md README.md; do printf '%s ' $f; grep -cF 'O SinalACS não é um serviço de emergência: em caso de risco de vida, ligue 192 (SAMU).' $f; done; for f in docs/telas-acs.md docs/telas-admin.md docs/telas-paciente.md CONTRIBUTING.md; do printf '%s ' $f; grep -cF 'Conteúdo educativo. Não substitui atendimento profissional. Emergência: ligue 192.' $f; done`
Expected: todos ≥ 1.

- [ ] **Step 6: Links relativos válidos**

Run: `for f in $(git diff --name-only develop -- '*.md'); do grep -oE '\]\(([^)#]+\.md)' "$f" | sed 's/](//' | while read -r l; do [ -e "$(dirname "$f")/$l" ] || echo "$f -> $l"; done; done`
Expected: nenhuma linha.

- [ ] **Step 7: Pendências consistentes**

Run: `git --no-pager grep -ohE 'P-[0-9]{2}' -- '*.md' ':!PROGRESS.md' ':!docs/superpowers/**' | sort -u > "$SCRATCH/usadas"; grep -oE '^\| P-[0-9]{2}' spec/escopo_projeto.md | tr -d '| ' | sort -u > "$SCRATCH/definidas"; comm -23 "$SCRATCH/usadas" "$SCRATCH/definidas"`
Expected: nenhuma linha.

- [ ] **Step 8: Atualizar o grafo (opcional) e commitar correções**

Se `graphify` estiver instalado: `graphify update .`. Se houve correções: `git commit -am "docs(escopo): correções da verificação final"`.

- [ ] **Step 9: Abrir PR para `develop`**

`gh pr create --base develop --title "docs: escopo educativo e aberto do SinalACS" --body` com D1–D12 e a solução adotada, a tabela de pendências (status Proposta), o portão de código em dois níveis (segurança e legal: C-01/C-02/C-04/C-05/C-06/C-08/C-10; funcional: C-03) e os demais C-07/C-09, e a remissão ao material do CEP como próximo plano, sem atribuição de IA.
