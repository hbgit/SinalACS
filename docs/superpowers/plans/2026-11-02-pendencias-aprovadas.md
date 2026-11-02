# Pendências aprovadas — plano de atualização da tabela e dos documentos dependentes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Registrar em `spec/escopo_projeto.md#pendencias` as decisões da equipe de 2026-11-02 (P-02 a P-11 aprovadas, P-01 revista, P-12 e P-13 novas) e alinhar todos os documentos que afirmam o conteúdo dessas decisões.

**Architecture:** Só documentação. A tabela de pendências continua sendo a fonte viva. Texto que afirma o conteúdo de uma decisão usa uma fórmula fixa conforme o status; remissões só com o ID ficam como estão. Antes de editar, um levantamento lista todas as linhas que afirmam decisões; depois, uma verificação confere cada citação contra a tabela.

**Tech Stack:** Markdown em pt-BR; `git grep`, `awk`, `comm`.

**Spec:** as duas mensagens da equipe de 2026-11-02 (decisões e revisão do plano), consolidadas em "Decisões a registrar" abaixo. Origem das pendências: `docs/escopo/decisoes-2026-11-01.md` (registro histórico; **não editar**).

## Decisões a registrar

1. Abaixo da tabela, este parágrafo (texto literal): "'Aprovada' significa que a equipe adotou a decisão. O que ainda depende de terceiros permanece na coluna 'Ainda depende de' e, se marcado, continua bloqueando o piloto."
2. Status "Aprovada", sem mudança no texto da decisão: P-04, P-05, P-06, P-08, P-09, P-11.
   - P-11, coluna "Ainda depende de": "Parecer jurídico (Procuradoria Federal junto à UFRR): `[A DEFINIR]`".
   - P-09: no topo de `spec/requisitos_piloto.md`, a frase "Rejeitar P-09 retira o RF03 do piloto; nunca reintroduz o rótulo de urgência."
3. Status "Aprovada", com texto da decisão alterado:
   - P-02: base legal "art. 11, II, "c" da LGPD; TCLE como exigência ética (Res. CNS 466/2012 e 510/2016), não como base legal". Também na §0 de `spec/lgpd_design.md`.
   - P-03: acrescentar "com capacitação prévia sobre o app, o aviso educativo e a conduta diante de relato de risco; preceptor profissional de saúde vinculado ao PET-Saúde".
   - P-07: acrescentar "conteúdo autoral sob CC BY 4.0; trechos de terceiros só com licença compatível ou em paráfrase com citação". Licença do conteúdo no README, separada da MIT do código, e no C-03 (aviso junto ao conteúdo e tela "Sobre").
   - P-10: trocar "e-mail opcional" por "sem e-mail; recuperação de acesso por novo convite QR do agente participante". Ajustar RF24, RNF09, §0 de `spec/lgpd_design.md` e C-05, com as duas regras de recuperação do item 8.
4. P-01 continua "Proposta", com a decisão proposta trocada por: "Copyright (c) 2026 Universidade Federal de Roraima (UFRR) e contribuidores do SinalACS, sob confirmação do NIT (Lei 9.609/1998, art. 4º)". `LICENSE` não muda.
5. Novas, status "Proposta":
   - `| P-12 | Instrumentos e serviço dos questionários (RF23) | Questionário de conhecimento pré/pós, SUS e pergunta de reconhecimento do aviso; serviço de aplicação como operador de dados | Instrumento e serviço: [A DEFINIR] | Sim (alimenta P-04) | Proposta |`
   - `| P-13 | Custódia institucional do repositório e da chave de assinatura do APK | Repositório em organização do PRISM no GitHub; responsável e backup da chave definidos | Responsável: [A DEFINIR] | Não | Proposta |`
6. Pilar B passa a incluir o RF17 (auditoria).
7. Rodar de novo as verificações da Task 10 (Steps 3 e 7) do plano `2026-11-01-escopo-educativo-aberto` e mostrar o diff.
8. **Recuperação de acesso (P-10), duas regras:** "o novo convite é vinculado ao mesmo identificador pseudônimo, após confirmação presencial pelo agente participante, e invalida a sessão do aparelho anterior". **Verificado em 2026-11-02:** o wipe remoto (#81) existe só no app do agente (`pendingWipe`/`confirmWipe` e `device_wiped_screen` só em `apps/acs`), e a sessão do paciente é um JWT de 1 h sem refresh token nem lista de revogação. Logo, a invalidação da sessão anterior do participante **não existe hoje**. Também conferido: o app do paciente não guarda credencial de longa duração (nenhum `refreshToken` em `apps/patient/lib`; hoje a renovação é um novo OTP). A credencial de dispositivo do RF24 (convite QR + PIN) é nova e nasce em C-05; a revogação dela na recuperação é a mudança nova **C-12** (C-10 e C-11 já estão em uso).
9. **Ações disparadas pelas decisões** (lista abaixo da tabela, responsável `[A DEFINIR]` em cada): consulta ao NIT (P-01); contato com o encarregado da UFRR (P-02); confirmação com a coordenação do PET-Saúde (P-03); submissão na Plataforma Brasil (P-04); definição do território com o PET-Saúde (P-05); ativação do Private Vulnerability Reporting e das Discussions (P-06, passo manual); lista de temas e revisores do conteúdo (P-07); pedido de parecer à Procuradoria Federal junto à UFRR (P-11); instrumentos dos questionários e serviço de aplicação (P-12); implementar C-04 (P-09); implementar C-05 e C-12 (P-10). Regra: toda pendência com "Sim" em "Bloqueia o piloto?" aparece em pelo menos uma ação.

10. **C-12 — revogação da credencial de dispositivo na recuperação de acesso** (nova, portão de segurança e legal): "a reemissão do convite invalida no servidor a credencial de dispositivo anterior vinculada ao identificador; revogar o JWT é opcional, dado o prazo de 1 h". Limite registrado: um aparelho perdido que nunca mais se conecta não é alcançado pela limpeza local; nele, o que protege os dados é a cifra local (RNF03) com o PIN. C-05 fica só com o login sem CPF/SMS/e-mail e a criação da credencial de dispositivo; os dois podem ser concluídos e testados separadamente.

## Global Constraints

- Documentação em pt-BR. Nenhum arquivo fora de `*.md` muda; `LICENSE` e `docs/escopo/decisoes-2026-11-01.md` não mudam.
- Textos entre aspas em "Decisões a registrar" são copiados literalmente. `[A DEFINIR]` vai entre crases, como no restante da tabela.
- **Aspas da alínea:** sempre `"c"` (aspas duplas), na tabela e na §0 de `lgpd_design.md`, como já está nos documentos.
- **Fórmulas de citação.** Quando o texto **afirma o conteúdo** de uma decisão fora da tabela, ele usa:
  - status Aprovada → "decisão aprovada P-NN";
  - status Proposta → "decisão proposta P-NN (status: Proposta)".
  Remissões só com o ID — "(P-09, C-04)", "Bloqueado por P-02", "ver P-12" — continuam válidas e **não** são reescritas.
- Não escrever "aprovado/aprovada pel…" (a Task 10, Step 3 do plano anterior trata isso como possível invenção de aprovação externa); escrever "adotada pela equipe" quando precisar do sujeito.
- **"Aprovada" não é desbloqueio.** Nenhum texto pode chamar uma pendência de "resolvida", "desbloqueada" ou "liberada"; quem bloqueia é a coluna "Ainda depende de". Ao enumerar bloqueios, citar todos os que têm "Sim" na coluna "Bloqueia o piloto?" ou remeter à coluna.
- **P-10 tira o e-mail do login, não todo dado de contato.** O pilar B (RF08–RF11) continua precisando de microárea e de endereço ou ponto de referência para a visita; essa coleta segue a minimização própria dos RF09/RF10 e não é alterada por este plano.
- Nomes e normas novos permitidos são só os fornecidos pela equipe: Procuradoria Federal junto à UFRR, Res. CNS 466/2012 e 510/2016, Lei 9.609/1998 art. 4º, CC BY 4.0, organização do PRISM no GitHub, NIT, Plataforma Brasil. Nada além disso.
- Os parágrafos condicionais "se P-NN for rejeitada" em `spec/requisitos_piloto.md` permanecem: decisões aprovadas ainda podem ser revistas.
- IDs RF/RNF/C/P nunca são renumerados.
- Commits sem atribuição de IA (`CLAUDE.md` do projeto).

## Review Focus

1. **Citação desatualizada de status** — documento ainda afirma "decisão proposta P-02" depois de P-02 aprovada (ou "aprovada P-01"). Pinado na Task 2, Step 0 (levantamento) e Task 3, Step 1 (verificação).
2. **"Aprovada" lida como desbloqueio** — texto que trate P-04/P-11 (ou outra com "Sim") como resolvida, ou lista de bloqueios incompleta. Pinado na Task 1, Step 3 e Task 3, Step 2.
3. **C-05 removendo dado necessário ao pilar B** — "o app não guarda contato" lido como proibir endereço da visita. Pinado na Task 2, Step 6.
4. **Recuperação por QR sem as duas regras, ou C-05/C-12 afirmando que a invalidação já existe, ou revogando só o JWT** (mesmo identificador; sessão anterior invalidada) em RF24 ou C-05. Pinado na Task 2, Step 6.
5. **TCLE como base legal ou licença do conteúdo confundida com a do código.** Pinado na Task 2, Step 6.

---

## Estrutura de arquivos

| Arquivo | Ação |
|---|---|
| `spec/escopo_projeto.md` | Tabela P-01–P-13, parágrafo de significado, lista de ações externas, pilar B com RF17, menção de P-03 em "Público-alvo" |
| `spec/requisitos_piloto.md` | Topo (frase de P-09, fórmula), RF20, RF23, RF24, RNF09 |
| `spec/lgpd_design.md` | §0 (P-02, P-10, P-12) e glossário |
| `spec/lgpd_data_audit.md` | Aviso do topo (P-10) |
| `spec/plano_piloto.md` | Intro, Participantes, Pré-requisitos não técnicos, Métricas, Ética |
| `spec/stack.md` | §0 Custo (P-08) e Distribuição (P-13) |
| `spec/trabalhos_futuros.md` | "Próximos planos": faixa do portão com C-12 |
| `docs/escopo/mudancas-de-codigo-recomendadas.md` | C-03 (licenças), C-05 (login e credencial de dispositivo), C-12 nova (revogação na recuperação) e toda linha do levantamento da Task 2, Step 0 (ex.: C-01, C-04, C-08) |
| `README.md` | Seção Licença: código MIT, conteúdo educativo CC BY 4.0 |
| `PROGRESS.md` | Uma frase na seção "Escopo educativo e aberto" |
| demais `*.md` | Só as linhas que o levantamento da Task 2, Step 0 apontar |

---

### Task 1: Tabela de pendências, ações externas e pilares

**Files:**
- Modify: `spec/escopo_projeto.md` (seções Pilares, Público-alvo, Pendências)

**Interfaces:**
- Produces: tabela com P-01–P-13 e status final (Aprovada: P-02–P-11; Proposta: P-01, P-12, P-13); âncora nova `#acoes`. A Task 2 usa os status para escolher a fórmula; a Task 3 lê a tabela para conferir.

- [ ] **Step 1: Branch**

Run: `git switch develop && git pull --ff-only && git switch -c docs/pendencias-aprovadas`
Expected: `Switched to a new branch 'docs/pendencias-aprovadas'`

- [ ] **Step 2: Editar a tabela**

Aplicar os itens 2–5 de "Decisões a registrar". Linhas alteradas:
- P-02, coluna Decisão: "base legal: art. 11, II, "c" da LGPD, com TCLE" → "base legal: art. 11, II, "c" da LGPD; TCLE como exigência ética (Res. CNS 466/2012 e 510/2016), não como base legal".
- P-03: acrescentar ao fim da decisão "; com capacitação prévia sobre o app, o aviso educativo e a conduta diante de relato de risco; preceptor profissional de saúde vinculado ao PET-Saúde".
- P-07: acrescentar "; conteúdo autoral sob CC BY 4.0; trechos de terceiros só com licença compatível ou em paráfrase com citação".
- P-10: "e-mail opcional" → "sem e-mail; recuperação de acesso por novo convite QR do agente participante, vinculado ao mesmo identificador pseudônimo, após confirmação presencial pelo agente, invalidando a sessão do aparelho anterior".
- P-11: coluna "Ainda depende de" → "Parecer jurídico (Procuradoria Federal junto à UFRR): `[A DEFINIR]`".
- P-01: decisão → o texto do item 4; status fica Proposta.
- Status: P-02 a P-11 → `Aprovada`. A coluna "Bloqueia o piloto?" **não muda** em nenhuma linha existente.
- P-12 e P-13 ao fim, exatamente como no item 5 (com `[A DEFINIR]` entre crases).
- Abaixo da tabela, antes de "Status possíveis", o parágrafo do item 1.

- [ ] **Step 3: Lista de ações**

Depois da legenda "Status possíveis…" (que fica colada à tabela, logo após o parágrafo do item 1), nova subseção com âncora `<a id="acoes"></a>` e título `### Ações disparadas pelas decisões`: tabela `Ação | Pendência | Responsável | Situação`, uma linha por ação do item 9, Responsável `[A DEFINIR]`, Situação "A iniciar". Frase de abertura: "Aprovar uma decisão não basta: cada ação abaixo precisa de responsável para a pendência não ficar parada. Toda pendência que bloqueia o piloto aparece aqui."

- [ ] **Step 4: Verificar a tabela**

Run:
```bash
f=spec/escopo_projeto.md
grep -c '^| P-' $f                                                      # 13
grep -E '^\| P-(0[2-9]|1[01]) ' $f | grep -vc '| Aprovada |'            # 0
grep -E '^\| P-(01|12|13) ' $f | grep -vc '| Proposta |'                # 0
grep -E '^\| P-(02|03|04|05|07|09|10|11|12) ' $f | grep -vcE '\| (\*\*)?Sim'   # 0 — bloqueios preservados
grep -E '^\| P-(01|06|08|13) ' $f | grep -vc '| Não |'                  # 0 — "Não" preservados
grep -cF "'Aprovada' significa que a equipe adotou a decisão." $f       # 1
grep -c 'e-mail opcional' $f                                            # 0
acoes=$(sed -n '/id="acoes"/,/^## /p' $f)
grep -E '^\| P-[0-9][0-9] ' $f | grep -E '\| (\*\*)?Sim' | grep -oE '^\| P-[0-9][0-9]' | tr -d '| ' |
  while read -r id; do echo "$acoes" | grep -qE "^\|.*\| $id " || echo "sem ação: $id"; done           # nenhuma linha
awk '/^\| P-13 /{t=NR} /^Status possíveis/{l=NR} /id="acoes"/{a=NR} END{print (t<l && l<a)?"ordem-ok":"ordem-errada"}' $f   # ordem-ok
```
Expected: 13; 0; 0; 0; 0; 1; 0; nenhuma linha; `ordem-ok`.

- [ ] **Step 5: Pilar B e Público-alvo**

Pilar B: depois de "e sincronização (RF15)" acrescentar ", com auditoria (RF17)". Público-alvo: "(decisão proposta P-03, status: Proposta)" → "(decisão aprovada P-03), com capacitação prévia e supervisão de preceptor profissional de saúde vinculado ao PET-Saúde".

Run: `sed -n '/^\*\*Pilar B/,/^$/p' spec/escopo_projeto.md | grep -c RF17`
Expected: 1.

- [ ] **Step 6: Commit**

```bash
git add spec/escopo_projeto.md
git commit -m "docs(escopo): decisões de 2026-11-02 na tabela de pendências; ações externas; P-12, P-13; RF17 no pilar B"
```

---

### Task 2: Documentos dependentes

**Files:**
- Modify: `spec/requisitos_piloto.md`, `spec/lgpd_design.md`, `spec/lgpd_data_audit.md`, `spec/plano_piloto.md`, `spec/stack.md`, `docs/escopo/mudancas-de-codigo-recomendadas.md`, `README.md`, `PROGRESS.md`, e qualquer outro `*.md` que o Step 0 listar

**Interfaces:**
- Consumes: status da Task 1.

- [ ] **Step 0: Levantar toda afirmação de decisão antes de editar**

Run:
```bash
AF="$(git rev-parse --git-dir)/afirmacoes.txt"
git --no-pager grep -nE 'decis(ão|ões) (propostas?|aprovadas?) P-|status: Proposta|decisões propostas' -- '*.md' ':!docs/superpowers/**' ':!docs/escopo/decisoes-2026-11-01.md' ':!spec/escopo_projeto.md' > "$AF"; cat "$AF"
```
O arquivo fica dentro de `.git/`: sobrevive entre sessões e nunca entra em commit. Cada linha listada é tratada nesta task: reescrever com a fórmula do status atual (Aprovada para P-02–P-11). Linhas de `docs/escopo/mudancas-de-codigo-recomendadas.md` (ex.: C-01/P-02, C-04/P-09, C-08/P-11) entram aqui; remissões só com o ID não aparecem no grep e ficam como estão.

Expected: a lista inclui pelo menos `spec/lgpd_design.md`, `spec/plano_piloto.md`, `spec/requisitos_piloto.md`, `spec/stack.md`, `spec/lgpd_data_audit.md`. Copiar a lista para o ledger.

- [ ] **Step 1: `spec/requisitos_piloto.md`**

- Primeira frase do topo: "As prioridades abaixo assumem que as decisões propostas P-09, P-10 e P-11 (…) serão aprovadas. Se alguma for rejeitada:" → "As prioridades abaixo seguem as decisões aprovadas P-09, P-10 e P-11 (…). Se alguma for revista e rejeitada:".
- No item "**P-09 rejeitada:**", acrescentar ao fim a frase literal "Rejeitar P-09 retira o RF03 do piloto; nunca reintroduz o rótulo de urgência."
- RF20, observação: depois de "antes de cada versão (P-07)" acrescentar "; conteúdo autoral sob CC BY 4.0, trechos de terceiros só com licença compatível ou em paráfrase com citação".
- RF23, observação: "Serviço `[A DEFINIR]`." → "Instrumentos e serviço: decisão proposta P-12 (status: Proposta)."
- RF24, texto do requisito: "e-mail opcional, sem CPF e sem SMS" → "sem e-mail, sem CPF e sem SMS no login; recuperação de acesso por novo convite QR do agente participante, vinculado ao mesmo identificador pseudônimo, após confirmação presencial pelo agente, invalidando a sessão do aparelho anterior (C-12)".
- RNF09: "Coleta mínima: nenhum dado pessoal para o pilar A; sem CPF no piloto" → "Coleta mínima: nenhum dado pessoal para o pilar A; sem CPF e sem e-mail no piloto; dados da visita (microárea, endereço ou ponto de referência) só o necessário, conforme RF09/RF10".

- [ ] **Step 2: `spec/lgpd_design.md`**

- §0, item P-02: "decisão proposta P-02 (status: Proposta)" → "decisão aprovada P-02"; "base legal art. 11, II, "c" da LGPD (estudo por órgão de pesquisa), com TCLE" → "base legal art. 11, II, "c" da LGPD (estudo por órgão de pesquisa); o TCLE é exigência ética (Res. CNS 466/2012 e 510/2016), não base legal". Manter "Confirmação jurídica: `[A DEFINIR]`".
- §0, Coleta mínima: "sem CPF e sem SMS, com e-mail opcional (decisão proposta P-10)" → "sem CPF, sem SMS e sem e-mail no login; recuperação de acesso por novo convite QR do agente participante, vinculado ao mesmo identificador e invalidando a sessão anterior (decisão aprovada P-10). Os dados da visita (microárea, endereço ou ponto de referência) seguem a minimização dos RF09/RF10".
- §0, Operadores: acrescentar "(instrumentos e serviço: decisão proposta P-12, status: Proposta)".
- Glossário, linha Controlador: "decisão proposta P-02" → "decisão aprovada P-02".

- [ ] **Step 3: `spec/lgpd_data_audit.md`, `spec/stack.md`, C-03, C-05**

- `lgpd_data_audit.md` topo: "(decisão proposta P-10)" → "(decisão aprovada P-10)".
- `stack.md` §0 Custo: "Teto mensal proposto de R$ 50 (decisão proposta P-08, status: Proposta)" → "Teto mensal de R$ 50 (decisão aprovada P-08)". Distribuição: acrescentar "Custódia do repositório e da chave de assinatura: decisão proposta P-13 (status: Proposta)."
- C-05, coluna Mudança: "sem CPF e sem SMS, e-mail opcional" → "sem CPF, sem SMS e sem e-mail (o login não usa e-mail, CPF nem telefone); cria a credencial de dispositivo do participante, vinculada ao identificador pseudônimo e liberada pelo PIN local (hoje o app do paciente não tem credencial de longa duração: a renovação é um novo OTP). Recuperação de acesso: ver C-12. Endereço ou ponto de referência da visita segue RF09/RF10, fora desta mudança".
- **C-12 (nova linha, seção "Portão do piloto — segurança e legal", logo após C-11):** Arquivo: backend (`auth`/`onboarding`) e app do paciente. Mudança: "Recuperação de acesso por novo convite QR do agente participante, **vinculado ao mesmo identificador pseudônimo** após confirmação presencial pelo agente. A reemissão do convite **invalida no servidor a credencial de dispositivo anterior** vinculada ao identificador; revogar o JWT é opcional, dado o prazo de 1 h. Essa invalidação **não existe hoje** no app do paciente; o wipe remoto (#81) cobre só o app do agente e serve de referência de desenho. Limpeza local quando o aparelho antigo voltar a falar com o servidor. **Limite:** um aparelho perdido que nunca mais se conecta não é alcançado; nele, o que protege os dados é a cifra local (RNF03) com o PIN". Testes exigidos: novo convite reusa o identificador e o histórico; a credencial do aparelho anterior é recusada pelo servidor logo após a reemissão. Motivo: RF24, P-10. Bloqueado por: C-05.
- C-03, coluna Mudança: acrescentar "A pasta do conteúdo educativo inclui um aviso de licença CC BY 4.0 com a atribuição, e a tela 'Sobre' indica as duas licenças (código MIT, conteúdo CC BY 4.0)."
- Demais linhas de C-NN listadas no Step 0: aplicar a fórmula do status atual.

- [ ] **Step 4: `spec/plano_piloto.md`**

- Intro: "As decisões P-NN citadas aqui são **propostas** (status: Proposta) até a equipe mudar o status em …" → "Cada decisão P-NN citada aqui traz o status registrado em [`escopo_projeto.md#pendencias`](escopo_projeto.md#pendencias). 'Aprovada' não remove bloqueios: o que bloqueia o piloto é a coluna 'Ainda depende de' das linhas marcadas em 'Bloqueia o piloto?'."
- Participantes: "Decisão proposta P-05 (status: Proposta):" → "Decisão aprovada P-05:"; "(decisão proposta P-03)" → "(decisão aprovada P-03), com capacitação prévia sobre o app, o aviso educativo e a conduta diante de relato de risco, e preceptor profissional de saúde vinculado ao PET-Saúde".
- `spec/trabalhos_futuros.md`, "Próximos planos": "C-01–C-06, C-08, C-10 e C-11" → "C-01–C-06, C-08 e C-10–C-12".
- Pré-requisitos de código, nível segurança e legal: acrescentar "- **C-12:** recuperação de acesso que invalida no servidor a credencial do aparelho anterior."
- Pré-requisitos não técnicos: acrescentar "- **P-12:** instrumentos dos questionários e serviço de aplicação (alimenta a submissão ao CEP, P-04)."; em P-03 acrescentar "capacitação dos agentes concluída"; ao fim, "Ações e responsáveis: [`escopo_projeto.md#acoes`](escopo_projeto.md#acoes)."
- Métricas, "Ganho de conhecimento": "instrumento `[A DEFINIR]` (P-07)" → "instrumento: decisão proposta P-12 (status: Proposta)". Custo: "teto proposto em P-08" → "teto da decisão aprovada P-08".
- Ética: "seguem a decisão proposta P-02 (status: Proposta): … base legal art. 11, II, "c" da LGPD, com TCLE." → "seguem a decisão aprovada P-02: … base legal art. 11, II, "c" da LGPD; o TCLE é exigência ética (Res. CNS 466/2012 e 510/2016), não base legal."

- [ ] **Step 5: README e PROGRESS**

README, seção `## Licença`, substituir o corpo por:
```markdown
- **Código:** MIT — ver [LICENSE](LICENSE). Titular dos direitos: decisão proposta P-01 (status: Proposta), em [spec/escopo_projeto.md](spec/escopo_projeto.md#pendencias).
- **Conteúdo educativo autoral:** [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.pt-br). Trechos de terceiros só entram com licença compatível ou em paráfrase com citação (decisão aprovada P-07).
```
PROGRESS, seção "Escopo educativo e aberto (2026-11-01)", acrescentar: "Em 2026-11-02 a equipe aprovou P-02 a P-11 e abriu P-12 e P-13; P-01 segue proposta. P-02, P-03, P-04, P-05, P-07, P-11 e P-12, além de P-09 e P-10 (via C-04 e C-05/C-12), continuam bloqueando o piloto até as dependências da coluna 'Ainda depende de'. O portão de segurança e legal passa a incluir C-12. Ações e responsáveis: [spec/escopo_projeto.md#acoes](spec/escopo_projeto.md#acoes)."

- [ ] **Step 6: Verificar Review Focus 3–5**

Run:
```bash
git --no-pager grep -nIE 'mecanismo existente' -- docs/escopo/mudancas-de-codigo-recomendadas.md          # nenhuma linha
git --no-pager grep -nIi 'e-mail opcional' -- spec docs/escopo ':!docs/escopo/decisoes-2026-11-01.md'      # nenhuma linha
git --no-pager grep -nIiE 'não guarda nem pede contato|sem dado de contato' -- spec docs/escopo           # nenhuma linha
grep -c "^| C-12 |" docs/escopo/mudancas-de-codigo-recomendadas.md                                       # 1
grep -c "credencial de dispositivo anterior" docs/escopo/mudancas-de-codigo-recomendadas.md                # ≥ 1
grep -c 'mesmo identificador pseudônimo' spec/requisitos_piloto.md docs/escopo/mudancas-de-codigo-recomendadas.md   # ≥ 1 em cada
grep -c 'sessão do aparelho anterior' spec/requisitos_piloto.md                                           # ≥ 1
grep -nE '^\| C-12 \|.*(revogar o JWT é opcional)' docs/escopo/mudancas-de-codigo-recomendadas.md | wc -l      # 1 — não revoga só o JWT
grep -nE '^\| C-12 \|.*cifra local \(RNF03\)' docs/escopo/mudancas-de-codigo-recomendadas.md | wc -l        # 1 — limite registrado
git --no-pager grep -nIE 'com TCLE' -- spec README.md                                                     # nenhuma linha
sed -n '/^## Licença/,/^## /p' README.md | grep -cE 'MIT.*LICENSE|CC BY 4.0'                             # 2
grep -c 'CC BY 4.0' docs/escopo/mudancas-de-codigo-recomendadas.md                                       # ≥ 1
grep -c 'nunca reintroduz o rótulo de urgência' spec/requisitos_piloto.md                                 # 1
git --no-pager grep -nF "II, 'c'" -- spec                                                                     # nenhuma linha
```
Expected: como nos comentários.

- [ ] **Step 7: Commit**

```bash
git add -u spec docs/escopo README.md PROGRESS.md
cut -d: -f1 "$(git rev-parse --git-dir)/afirmacoes.txt" | sort -u | xargs -r git add
git status --short   # conferir: nada modificado fora do stage
git commit -m "docs(escopo): documentos dependentes alinhados às decisões de 2026-11-02"
```

---

### Task 3: Verificações e diff

**Files:** nenhum novo; correções inline se algo falhar.

Esta task não depende de arquivos da Task 2: recria tudo o que usa.

- [ ] **Step 1: Consistência das citações com a tabela (Review Focus 1)**

Run:
```bash
SCRATCH=${SCRATCH:-$(mktemp -d)}
f=spec/escopo_projeto.md
awk -F'|' '/^\| P-[0-9][0-9] /{gsub(/ /,"",$2); gsub(/^ +| +$/,"",$7); print $2, $7}' $f > "$SCRATCH/status"
git --no-pager grep -ohE 'decisão (aprovada|proposta) P-[0-9][0-9]' -- '*.md' ':!docs/superpowers/**' ':!docs/escopo/decisoes-2026-11-01.md' | sort -u |
while read -r _ kind id; do st=$(awk -v i="$id" '$1==i{print $2}' "$SCRATCH/status");
  { [ "$kind" = aprovada ] && [ "$st" = Aprovada ]; } || { [ "$kind" = proposta ] && [ "$st" = Proposta ]; } || echo "divergente: $kind $id (tabela: $st)"; done
git --no-pager grep -nE 'decisões propostas|status: Proposta' -- '*.md' ':!docs/superpowers/**' ':!docs/escopo/decisoes-2026-11-01.md' | grep -vE 'P-(01|12|13)'
```
Expected: nenhuma linha nos dois.

- [ ] **Step 2: Nada chamado de resolvido ou desbloqueado (Review Focus 2)**

Run: `git diff develop -- '*.md' ':!docs/superpowers/**' | grep '^+' | grep -iE 'resolvid|desbloque|liberad'`
Expected: nenhuma linha.

- [ ] **Step 3: Task 10, Step 3 do plano anterior (nada inventado)**

A segunda metade aceita "propost" **ou** "aprovad", porque P-02 agora é aprovada.
Run:
```bash
git diff develop -- '*.md' ':!docs/superpowers/**' | grep '^+' | grep -iE 'CNPJ|CAAE|parecer (n|favor)|aprovad[oa] pel|@ufrr|@[a-z]+\.(br|com)'
git diff develop -- '*.md' ':!docs/superpowers/**' | grep '^+' | grep -iE 'controlador.{0,40}UFRR|UFRR.{0,40}controlador' | grep -viE 'propost|aprovad'
```
Expected: nenhuma linha nos dois.

- [ ] **Step 4: Task 10, Step 7 do plano anterior (pendências consistentes)**

Sem `\b` (não é portável em todo `git grep -E`); a fronteira é explícita, o que também evita casar "P-256" (curva EC) como "P-25".
Run:
```bash
SCRATCH=${SCRATCH:-$(mktemp -d)}
git --no-pager grep -ohE '(^|[^0-9A-Za-z])P-[0-9][0-9]([^0-9]|$)' -- '*.md' ':!PROGRESS.md' ':!docs/superpowers/**' | grep -oE 'P-[0-9][0-9]' | sort -u > "$SCRATCH/usadas"
grep -oE '^\| P-[0-9][0-9]' spec/escopo_projeto.md | tr -d '| ' | sort -u > "$SCRATCH/definidas"
comm -23 "$SCRATCH/usadas" "$SCRATCH/definidas"
```
Expected: nenhuma linha (P-12 e P-13 agora estão definidas).

- [ ] **Step 5: Só Markdown mudou; LICENSE e registro intocados**

Run: `git diff --name-only develop | grep -vE '\.md$'; git diff --name-only develop -- LICENSE docs/escopo/decisoes-2026-11-01.md`
Expected: nenhuma linha nos dois.

- [ ] **Step 6: Mostrar o diff**

Run: `git --no-pager diff --stat develop && git --no-pager diff develop -- spec/escopo_projeto.md`
Mostrar ao usuário o `--stat` completo e o diff da tabela; os demais ficam disponíveis por `git diff develop -- <arquivo>`.

- [ ] **Step 7: Commit de correções (se houver)**

`git commit -am "docs(escopo): correções da verificação das pendências"` — só se os Steps 1–5 exigiram ajuste.
