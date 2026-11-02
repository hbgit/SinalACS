# Milestones "Pilot" e "v1.0" — plano de reclassificação das issues

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Organizar as issues abertas de `hbgit/SinalACS` nas milestones "Pilot" e "v1.0" (ou nos rótulos `futuro`/`a-decidir`), criar as issues que faltam para o portão do piloto e para os requisitos Essenciais, e registrar tudo num documento revisável antes de tocar no GitHub.

**Architecture:** Duas fases separadas por um portão humano. **Fase 1 (Tasks 1–2), só leitura no GitHub:** inventário em JSON fora do Git e o documento `docs/escopo/classificacao-issues.md`, com a tabela de classificação, as lacunas (issues novas propostas, com corpo completo) e as reescritas de escopo antigo. **Portão:** o usuário aprova a tabela. **Fase 2 (Tasks 3–5), escrita no GitHub:** um script gera os comandos `gh` a partir da tabela aprovada, roda em lotes pequenos com registro em `docs/escopo/log-aplicacao-issues.md`, e uma verificação final confere as invariantes.

**Tech Stack:** `gh` CLI (issues, labels, `gh api` para milestones), Python 3 (`-I`) para gerar comandos a partir do Markdown, Markdown em pt-BR.

**Spec:** a mensagem do usuário de 2026-11-02 (Contexto, Objetivo, Critérios, Conteúdo, Regras), resumida em "Critérios" abaixo; fontes do escopo: `spec/escopo_projeto.md`, `spec/requisitos_piloto.md`, `spec/plano_piloto.md`, `spec/trabalhos_futuros.md`, `docs/escopo/mudancas-de-codigo-recomendadas.md`.

## Critérios (do pedido)

- **Pilot:** tudo que precisa estar pronto antes da primeira coleta com participantes: portão de segurança e legal, portão funcional (C-03, se o pilar A estiver no piloto), requisitos **Essenciais** de `spec/requisitos_piloto.md`, e o que a distribuição exige (APK assinado em GitHub Releases, compose do piloto).
- **v1.0:** requisitos **Desejáveis**, mudanças fora do portão (C-07, C-09, renomear a tabela `ubs`), melhorias pós-piloto e correções que o piloto revelar.
- **Sem milestone, rótulo `futuro`:** tudo que `spec/trabalhos_futuros.md` lista. Não fechar; rótulo + comentário apontando para `spec/trabalhos_futuros.md`.
- **Rótulo `a-decidir`:** issue que não se encaixa, sem palpite.

## Global Constraints

- **Nenhuma escrita no GitHub antes da aprovação explícita do usuário da tabela** (portão no fim da Task 2). Escrita = criar/editar issue, comentário, rótulo, milestone.
- Não fechar, apagar ou transferir issues. Não alterar configurações do repositório (proteção de branch, Discussions, Vulnerability Reporting).
- Não implementar código; não inventar informação institucional (`[A DEFINIR]` onde faltar).
- Toda issue nova ou editada cita os IDs (RF, RNF, C, P) de que trata e traz o link para o documento de escopo no formato `https://github.com/hbgit/SinalACS/blob/develop/<caminho>`.
- Texto em pt-BR, sem atribuição de IA em issue, comentário, commit ou PR.
- **Portão de segurança e legal = C-01, C-02, C-04, C-05, C-06, C-08, C-10, C-11, C-12.** O pedido lista C-01–C-10, mas `spec/plano_piloto.md` já inclui C-11 (autoavaliação local, merged na #121) e C-12 (revogação na recuperação, na #122). Vale o plano do piloto; a divergência é registrada no documento de classificação.
- **Precedência quando dois critérios batem:** `futuro` (está em `trabalhos_futuros.md`) > Pilot > v1.0, **exceto** controle de segurança ou integridade sobre dados reais de participantes que também atende requisito Essencial: esse conflito vira `a-decidir`, com as duas justificativas lado a lado, sem palpite (caso conhecido: #96, separação de papéis do Postgres × RF17). Issue já entregue em `develop` mas aberta (fecha no merge `develop → main`) recebe a milestone pelo requisito que atende, e a coluna "Situação" diz "entregue em develop (PR #NN)".
- **Edição de issue com escopo antigo não apaga o original:** o corpo recebe um bloco no topo (`> **Escopo revisto (2026-11-02):** …`) e o texto antigo fica abaixo, intacto; o comentário registra o que mudou e por quê. Título só muda se contiver termo de escopo antigo.
- **Comentários idempotentes:** todo comentário postado por este plano começa com o marcador oculto `<!-- escopo-2026-11-02 -->`; o gerador omite o comando quando a issue já tem um comentário com esse marcador.
- **Aprovação amarrada ao conteúdo:** o gerador recebe o hash aprovado (`git hash-object docs/escopo/classificacao-issues.md`, registrado no ledger) e se recusa a rodar se o arquivo atual tiver outro hash.
- **Comparação de corpos:** toda comparação de corpo de issue (guarda `--conferir-corpo`, checagem "já reescrita", verificação da Task 4) normaliza `\r\n` → `\n` e ignora espaços no fim, nos dois lados.
- **Corpo atual × inventário:** antes de reescrever uma issue, o corpo atual no GitHub é comparado com o do inventário; se diferirem, o lote para naquela issue (alguém a editou depois do inventário) e a reescrita é refeita sobre o corpo atual, com nova aprovação daquela linha.
- **Fonte única das ações da equipe:** com as issues `[P-NN]` criadas, a issue passa a ser a fonte da situação; a tabela `escopo_projeto.md#acoes` troca a coluna "Situação" pela coluna "Issue" (número). Essa edição de documento é feita na Task 4, depois da criação.
- Títulos das issues novas começam pelo ID principal: `[C-05] …`, `[RNF07] …`, `[P-04] …`.
- Rótulos novos: só `futuro`, `a-decidir` e `acao-equipe` (este para as issues `[P-NN]`, ações da equipe que não são código). Rótulos existentes usados nas issues novas são conferidos contra `gh label list` (Task 2, Step 5). Milestones novas: só `Pilot` e `v1.0`, **sem `due_on`**, descrição com link para `spec/plano_piloto.md` (Pilot: "data depende do parecer do CEP, P-04").

## Review Focus

1. **Escrita antes da aprovação** — qualquer `gh issue edit/create/comment`, `gh label create` ou `gh api -X POST` na Fase 1. Pinado: a Task 1 e a Task 2 só usam `gh issue list`/`gh api` GET; Task 3, Step 1 exige a frase de aprovação registrada.
2. **Issue fechada ou transferida por engano** — o script gerado não pode conter `close`, `delete`, `transfer`, `lock`. Pinado na Task 3, Step 3.
3. **Portão ou Essencial sem cobertura** — algum C-NN do portão sem issue em Pilot, ou RF/RNF Essencial sem "implementado", issue ou lacuna. Pinado na Task 2, Step 5 e Task 5, Step 2.
4. **Corpo original perdido** — edição que substitui o corpo em vez de prefixar. Pinado na Task 4, Step 2 (o corpo novo termina com o corpo antigo, byte a byte).
5. **Lote repetido duplica efeito ou grava sobre edição alheia** — issue nova criada duas vezes, comentário repetido, corpo editado por alguém depois do inventário sobrescrito. Pinado na Task 3, Step 2 (título exato, marcador de comentário, comparação do corpo atual) e Task 4, Step 2.

---

## Classificação inicial proposta (a Task 2 confere e completa)

Inventário de 2026-11-02: 20 issues abertas, nenhuma milestone, nenhum rótulo `futuro`/`a-decidir`.

| # | Título (resumo) | Proposta | Justificativa | Ação | Situação |
|---|---|---|---|---|---|
| 118 | PKI de produção da CA de aparelhos | `futuro` | `trabalhos_futuros.md` § Distribuição e infraestrutura de produção (#118) | rotular + comentar; corpo cita "UBS" → bloco de escopo | aberta |
| 117 | ACK com identidade de aparelho | v1.0 | RF03 Desejável, INV-03 | manter | aberta |
| 116 | Chave do certificado no TEE | `futuro` | `trabalhos_futuros.md` (#116) | rotular + comentar | aberta |
| 114 | `acs_full_e2e.sh` falha no tap (regressão) | Pilot | RF08/RF11 Essenciais: e2e do fluxo do agente | manter | aberta |
| 111 | ACK de um segundo ACS | v1.0 | RF03 Desejável | manter | aberta |
| 103 | android-e2e: FCM não chega à bandeja | v1.0 | RF14 Desejável | manter | correção em develop (#105/#106), aceite pendente |
| 102 | Métricas §1.3 no backoffice | v1.0 | melhoria pós-piloto; métricas do piloto vêm de `telemetry_events` e questionários | bloco de escopo (corpo cita "papel/UBS") | aberta |
| 101 | Reemitir eventos perdidos | v1.0 | INV-03, telemetria | manter | aberta |
| 100 | Sinalizar eventos descartados | v1.0 | RNF02 (telemetria), melhoria | manter | aberta |
| 99 | Evento de onboarding sem assistência (H2) | v1.0 | H2 é medida por observação no piloto (`plano_piloto.md` § Métricas) | manter | aberta |
| 96 | Separar papéis do Postgres | `a-decidir` | conflito: está em `trabalhos_futuros.md` (#96) **e** protege a integridade da auditoria (RF17, Essencial) com dados reais de participantes | rotular a-decidir + comentar com as duas justificativas | aberta |
| 94 | Certificado MQTT por aparelho | Pilot | RNF04 Essencial | manter | entregue em develop (PR #119) |
| 90 | mTLS Traefik ↔ backend | Pilot | RNF04 Essencial | manter | entregue em develop (PR #113) |
| 88 | ACK repetido reescreve o ACS | v1.0 | RF03 Desejável, INV-03 | manter | entregue em develop (PR #112) |
| 87 | Contador "Concluídos" | v1.0 | RF05 Desejável | bloco de escopo (corpo cita "UBS") | entregue em develop (PRs #108–#110) |
| 86 | ACK de alerta concluído | v1.0 | RF05 Desejável | manter | entregue em develop (PR #104) |
| 83 | Telemetria do §1.3 | Pilot | fonte da métrica de sincronização (H4) em `plano_piloto.md` | manter | entregue em develop (PR #98) |
| 81 | Remote wipe e certificado por aparelho | Pilot | encerramento do piloto apaga aparelhos dos agentes (M-04) | manter | entregue em develop (PR #93) |
| 77 | Envio do OTP por SMS real (RF01) | `futuro` | `trabalhos_futuros.md` "RF01 com CPF e SMS"; P-10 aprovada | rotular + comentar; bloco de escopo apontando RF24/C-05 | aberta |
| 15 | Guia de publicação na Google Play | `futuro` | `trabalhos_futuros.md` (Play Store) | rotular + comentar | aberta |

## Lacunas propostas (issues novas)

| Título | Milestone | Rótulos | IDs |
|---|---|---|---|
| `[C-01] Texto legal do app do paciente: controlador, encarregado e aviso educativo` | Pilot | `privacy` | C-01, RF21, P-02 |
| `[C-02] Aviso educativo na primeira abertura e em "Sobre"` | Pilot | `enhancement` | C-02, RF21 |
| `[C-04] Pedido de contato sem rótulo de urgência e saída "Ligar 192" sem envio` | Pilot | `enhancement` | C-04, RF03, RF05, P-09, INV-03 |
| `[C-05] Acesso do participante sem CPF, SMS ou e-mail (RF24)` | Pilot | `privacy` | C-05, RF24, RNF08, RNF09, P-10 |
| `[C-06] Trocar "UBS" nos textos dos apps por grupo/coordenação do piloto` | Pilot | `enhancement` | C-06 |
| `[C-08] Autoavaliação com três saídas, sem classificação de risco` | Pilot | `enhancement` | C-08, RF04, RF16, P-11 |
| `[C-10] "Apagar meus dados" e retenção local de 30 dias` | Pilot | `privacy` | C-10, RNF09 |
| `[C-11] Autoavaliação local no pilar A, sem sessão nem registro no servidor` | Pilot | `privacy` | C-11, RF04, RF22, RNF09 |
| `[C-12] Recuperação de acesso que invalida a credencial do aparelho anterior` | Pilot | `security` | C-12, RF24, P-10 |
| `[C-03] Biblioteca de conteúdo educativo offline (pilar A)` | Pilot | `enhancement` | C-03, RF20, RF22, P-07 |
| `[RNF07] APK assinado publicado em GitHub Releases` | Pilot | `enhancement` | RNF07, RNF08, P-13 |
| `[RNF07] Compose do piloto: um host, Let's Encrypt, documentação única` | Pilot | `documentation` | RNF07, RNF04, P-08 (resolve a divergência `stack.md` §0 × `backend/DEPLOY.md`) |
| `[C-07] Discagem só para 192 no app do agente` | v1.0 | `enhancement` | C-07, RF13 |
| `[C-09] Remover "Manchester" do código e do vídeo` | v1.0 | `documentation` | C-09 |
| `[C-06b] Renomear a tabela ubs (migração)` | v1.0 | `enhancement` | C-06 (dívida técnica) |
| `[P-02] Contato com o encarregado de dados da UFRR` … uma por ação bloqueante de `escopo_projeto.md#acoes` (P-02, P-03, P-04, P-05, P-07, P-11, P-12) | Pilot | `acao-equipe` | P-NN |
| Lacunas da seção "Cobertura dos Essenciais" (Task 2, Step 3b) — ex.: `[RNF05] Acessibilidade dos fluxos do piloto no app do paciente`, `[RNF03] Cifra local dos dados do app do paciente com PIN`, se a cobertura não achar implementação | Pilot | conforme o caso | RF/RNF |

As issues `[P-NN]` são ações da equipe, não de código. A Task 2 as lista numa seção própria para o usuário aprovar ou recusar em bloco.

---

## Estrutura de arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `.git/issues-inventario.json` | Criar (fora do Git) | Snapshot do inventário; usado pelas Tasks 2–5 |
| `docs/escopo/classificacao-issues.md` | Criar | Tabela para revisão, lacunas com corpo completo, reescritas, divergências |
| `scripts/escopo/gerar_comandos_issues.py` | Criar | Lê a tabela aprovada e imprime os lotes de comandos `gh` (dry-run por padrão) |
| `docs/escopo/log-aplicacao-issues.md` | Criar na Fase 2 | Registro de cada comando aplicado e do resultado |
| `spec/escopo_projeto.md` | Modificar na Task 4 | Tabela `#acoes`: coluna "Situação" → "Issue" |

---

### Task 1: Pré-condições e inventário (só leitura)

**Files:** Create: `.git/issues-inventario.json`

- [ ] **Step 1: Pré-condições**

Run:
```bash
gh pr view 122 --json state -q .state
git switch develop && git pull --ff-only && git switch -c docs/classificacao-issues
grep -c '^| C-12 |' docs/escopo/mudancas-de-codigo-recomendadas.md
```
Expected: `MERGED`; branch criada; `1`. Se a #122 não estiver merged, parar e avisar: C-12 e os status de P-NN ainda não estão em `develop`.

- [ ] **Step 2: Inventário**

Run:
```bash
INV="$(git rev-parse --git-dir)/issues-inventario.json"
gh issue list --state open --limit 500 --json number,title,labels,milestone,body > "$INV"
python3 -I -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$INV"
gh api 'repos/hbgit/SinalACS/milestones?state=all' -q '.[].title'
gh label list --limit 200 --json name -q '.[].name' > "$(git rev-parse --git-dir)/rotulos.txt"
grep -cxE 'privacy|security|enhancement|documentation|accessibility' "$(git rev-parse --git-dir)/rotulos.txt"
```
Expected: número de issues (20 em 2026-11-02; se diferente, as novas entram na Task 2); nenhuma milestone listada. Se "Pilot" ou "v1.0" já existir, a Task 3 reaproveita em vez de criar. A contagem de rótulos é `5` (todos existiam em 2026-11-02); se menor, a Task 2 só usa os que existem.

- [ ] **Step 3: Mapeamento e termos de escopo antigo**

Para cada issue, extrair IDs citados (`RF\d\d|RNF\d\d|C-\d\d|P-\d\d|INV-0\d`) e termos de escopo antigo (`UBS|CPF|SMS|Manchester|urgência|pânico|e-SUS|Gov\.br|Play Store|Google Play|iOS|Pulumi`), e a situação (PR merged que a referencia: `gh pr list --state merged --search "#NN"`). Saída vai direto para a Task 2.

---

### Task 2: Documento de classificação (só leitura no GitHub)

**Files:** Create: `docs/escopo/classificacao-issues.md`

**Interfaces:**
- Produces: seção `## Tabela` com colunas exatamente `| # | Título | Milestone | Rótulos a adicionar | Justificativa | Ação | Situação |`; valores de Milestone ∈ {`Pilot`, `v1.0`, `—`}; Rótulos a adicionar ∈ {`futuro`, `a-decidir`, rótulos existentes, `—`}; Ação ∈ {`manter`, `editar título`, `bloco de escopo`, `rotular futuro`, `a decidir`}. Seção `## Issues novas` com uma subseção `### N1 — <título>` por issue: linhas `Milestone:`, `Rótulos:`, e o corpo entre `<!-- corpo -->` e `<!-- /corpo -->`. Seção `## Reescritas de escopo` com, por issue, `Título novo:` (ou `—`), o bloco de escopo entre `<!-- bloco -->`/`<!-- /bloco -->` e o comentário entre `<!-- comentario -->`/`<!-- /comentario -->`. Seção `## Cobertura dos Essenciais` com colunas `| ID | Requisito | Situação | Evidência |`, Situação ∈ {`implementado`, `issue`, `lacuna`}; Evidência = PR merged ou caminho de teste (implementado), `#NN` (issue) ou `N<k>` (issue nova). A Task 3 lê exatamente esses marcadores.

- [ ] **Step 1: Cabeçalho e divergências**

Topo do documento: propósito, data, link para os cinco documentos de escopo, a frase "Nada aqui foi aplicado no GitHub; aplicar exige aprovação explícita desta tabela", e a seção `## Divergências` registrando: (a) o pedido cita C-01–C-10, o portão em `plano_piloto.md` tem também C-11 e C-12; (b) `futuro` vence quando a issue está em `trabalhos_futuros.md` mesmo atendendo requisito Essencial (caso #96, RF17).

- [ ] **Step 2: Tabela**

Partir da "Classificação inicial proposta" deste plano, conferir cada linha contra o inventário (Task 1, Step 3) e os documentos de escopo, e corrigir onde a evidência divergir; cada correção vira uma linha em `## Divergências`. Issue que não se encaixa: Milestone `—`, Rótulos `a-decidir`, Ação `a decidir`, Justificativa explica o motivo **sem** sugerir destino. O conflito futuro × Essencial de segurança (Global Constraints) também vai para `a-decidir`, com as duas justificativas. Coluna "Situação": "entregue em develop (PR #NN)" só com PR merged em `develop` que referencia a issue.

- [ ] **Step 3: Issues novas**

Para cada linha de "Lacunas propostas", um corpo com quatro partes fixas:
```markdown
## Objetivo
<uma ou duas frases a partir da linha correspondente de mudancas-de-codigo-recomendadas.md ou requisitos_piloto.md>

## Critério de aceite
- [ ] <itens verificáveis; para C-NN, incluir os "Testes exigidos" do documento de mudanças>

## Referências
IDs: <RF/RNF/C/P>
Escopo: https://github.com/hbgit/SinalACS/blob/develop/<arquivo>#<âncora>
Bloqueado por: <P-NN ou C-NN, ou —>
```
Issues `[P-NN]` usam "Objetivo" = a ação de `escopo_projeto.md#acoes`, "Critério de aceite" = a coluna "Ainda depende de" resolvida, e "Responsável: `[A DEFINIR]`". Nada institucional além do que já está nos documentos.

- [ ] **Step 3b: Cobertura dos Essenciais**

Uma linha por RF/RNF com prioridade Essencial em `spec/requisitos_piloto.md` (`grep -E '\| Essencial' spec/requisitos_piloto.md`). Para cada um: `implementado` só com evidência concreta (PR merged, arquivo de teste ou e2e que exercita o fluxo; citar o caminho); `issue` com o número; `lacuna` com a issue nova correspondente (acrescentada em `## Issues novas`, milestone Pilot). Atenção explícita ao RNF05 (acessibilidade; público de baixo letramento digital) e ao RNF03 (cifra local; única proteção do aparelho perdido depois do C-12): se a evidência não cobrir o app do paciente nos fluxos do piloto, é `lacuna`.

- [ ] **Step 4: Reescritas de escopo**

Para cada issue com Ação `bloco de escopo` ou `editar título`: bloco no formato `> **Escopo revisto (2026-11-02):** <o que vale agora, com IDs e link>.` e um comentário de 3–6 linhas dizendo o que mudou, por quê (decisão/requisito) e que o texto original foi mantido abaixo. Todo comentário começa com `<!-- escopo-2026-11-02 -->` na primeira linha. Issues `rotular futuro` recebem só o comentário padrão: "Classificada como **futuro**: depende de <motivo> e está em [`spec/trabalhos_futuros.md`](https://github.com/hbgit/SinalACS/blob/develop/spec/trabalhos_futuros.md). Não é pré-requisito do piloto; a issue segue aberta."

- [ ] **Step 5: Verificar o documento**

Salvar o verificador abaixo em `scripts/escopo/verificar_classificacao.py` (vai junto no commit) e rodar:
`python3 -I scripts/escopo/verificar_classificacao.py docs/escopo/classificacao-issues.md "$(git rev-parse --git-dir)/issues-inventario.json" "$(git rev-parse --git-dir)/rotulos.txt"`

O verificador imprime, uma por linha: `faltam`, `sobram`, `sem destino`, `portão sem issue`, `corpos sem link`, `comentarios sem marcador`, `rotulos inexistentes`, `essenciais sem situação`, `evidencia vazia` — cada um seguido da lista de casos — e sai com código 1 se alguma lista não for vazia. Regras:
- `faltam`/`sobram`: números do inventário × linhas `| <n> |` da Tabela.
- `sem destino`: linha da Tabela sem `Pilot`/`v1.0` e sem `futuro`/`a-decidir`.
- `portão sem issue`: C-01, C-02, C-03, C-04, C-05, C-06, C-08, C-10, C-11, C-12 sem `### N<k> — [C-NN]`.
- `corpos sem link`: corpo entre `<!-- corpo -->`/`<!-- /corpo -->` sem `https://github.com/hbgit/SinalACS/blob/develop/`.
- `comentarios sem marcador`: comentário entre `<!-- comentario -->`/`<!-- /comentario -->` cuja primeira linha não seja `<!-- escopo-2026-11-02 -->`.
- `rotulos inexistentes`: rótulos citados (coluna "Rótulos a adicionar" e linhas `Rótulos:`) fora de `rotulos.txt` ∪ {`futuro`, `a-decidir`, `acao-equipe`}.
- `essenciais sem situação`: ID com "Essencial" em `spec/requisitos_piloto.md` sem linha `| ID | … | implementado|issue|lacuna |` na Cobertura.
- `evidencia vazia`: linha da Cobertura com a coluna Evidência vazia ou `—`; e, se a Situação for `implementado`, Evidência sem caminho de arquivo (`[\w./-]+\.(dart|sh|md|yaml|sql)`) nem número de PR (`#\d+`). Se `issue`, exige `#\d+`; se `lacuna`, exige `N\d+`.

Depois:
```bash
f=docs/escopo/classificacao-issues.md
grep -nE '\b(close|transfer)\b' "$f"
for pr in $(grep -oE 'entregue em develop \(PRs? #[0-9]+' "$f" | grep -oE '[0-9]+$' | sort -u); do
  gh pr view "$pr" --json state,baseRefName -q "\"$pr \\(.state) \\(.baseRefName)\""; done | grep -v 'MERGED develop'
```
Expected: verificador com todas as listas vazias e código 0; nenhuma linha nos dois comandos (o primeiro tolera frases que dizem "não fechar"; o segundo confirma que toda "entregue em develop" cita PR merged em `develop`).

- [ ] **Step 6: Commit, PR e PORTÃO**

```bash
git add docs/escopo/classificacao-issues.md docs/superpowers/plans/2026-11-02-milestones-issues.md scripts/escopo/verificar_classificacao.py
git commit -m "docs(escopo): classificação das issues para as milestones Pilot e v1.0"
git push -u origin docs/classificacao-issues
gh pr create --base develop --title "docs(escopo): classificação das issues (Pilot, v1.0, futuro)" --body "<resumo, sem atribuição de IA>"
```
**Parar aqui.** Mostrar ao usuário o link do PR e a tabela; esperar uma aprovação explícita ("aprovo a tabela", com ou sem ajustes). Ajustes pedidos são feitos no documento e commitados; só então a Fase 2 começa. Registrar no ledger a linha `Aprovação da tabela: <frase> — hash <git hash-object docs/escopo/classificacao-issues.md>`.

---

### Task 3: Gerador de comandos (dry-run)

**Files:** Create: `scripts/escopo/gerar_comandos_issues.py`

**Interfaces:**
- Consumes: `docs/escopo/classificacao-issues.md` (marcadores da Task 2) e `.git/issues-inventario.json`.
- Produces: `python3 -I scripts/escopo/gerar_comandos_issues.py <doc> --hash <aprovado> --lote {rotulos,milestones,existentes,reescritas,novas}` imprime um comando `gh` por linha para o lote; nunca executa nada. Sai com erro se `git hash-object <doc>` ≠ `--hash`. Também `--conferir-corpo N`: sai com erro se o corpo atual da issue N (`gh issue view N --json body`) ≠ corpo do inventário. Idempotência: `novas` compara o **título exato** com `gh issue list --state all --limit 1000 --json title` (sem `--search`, que é aproximado); comentários são omitidos quando a issue já tem um com `<!-- escopo-2026-11-02 -->` (`gh issue view N --json comments`); reescritas são omitidas quando o corpo já começa com `> **Escopo revisto (2026-11-02):**`.

- [ ] **Step 1: Pré-condição**

Run:
```bash
L="$(git rev-parse --show-toplevel)/.superpowers/sdd/2026-11-02-milestones-issues/progress.md"
grep -oE 'Aprovação da tabela: .* — hash [0-9a-f]{40}' "$L" | tail -1 | grep -oE '[0-9a-f]{40}$'
git hash-object docs/escopo/classificacao-issues.md
```
Expected: os dois hashes iguais. Sem aprovação registrada ou com hash diferente, parar.

- [ ] **Step 2: Escrever o gerador**

Comandos por lote:
- `rotulos`: `gh label create futuro --color BFD4F2 --description "Trabalho futuro (spec/trabalhos_futuros.md)"`, `gh label create a-decidir --color FBCA04 --description "Classificação a decidir pela equipe"` e `gh label create acao-equipe --color C5DEF5 --description "Ação da equipe do projeto (não é código)"`, só se ainda não existirem.
- `milestones`: `gh api -X POST repos/hbgit/SinalACS/milestones -f title=Pilot -f description=…` e idem `v1.0`, sem `due_on`, só se ainda não existirem.
- `existentes`: `gh issue edit N --milestone X` e/ou `--add-label L`, um comando por issue; `gh issue comment N --body-file <tmp>` para `rotular futuro`.
- `reescritas`, por issue, nesta ordem: (1) se o corpo atual já começa com `> **Escopo revisto (2026-11-02):**`, omitir a edição (já reescrita) — esta checagem vem **antes** da guarda, para que rodar de novo um lote interrompido não acuse conflito falso nas issues já reescritas; (2) senão, emitir `python3 -I scripts/escopo/gerar_comandos_issues.py --conferir-corpo N && gh issue edit N --body-file <tmp> [--title …]`, com corpo novo = bloco + linha em branco + corpo do inventário (igual ao atual, garantido pela guarda); (3) o comentário, se ainda não houver marcador.
- `novas`: `gh issue create --title … --body-file <tmp> --milestone X [--label L]`.
Arquivos temporários em `mktemp -d`; o gerador imprime o caminho junto do comando.

- [ ] **Step 3: Dry-run e checagem do que sai**

Run:
```bash
H=$(git hash-object docs/escopo/classificacao-issues.md)
for l in rotulos milestones existentes reescritas novas; do python3 -I scripts/escopo/gerar_comandos_issues.py docs/escopo/classificacao-issues.md --hash "$H" --lote $l; done > "$(git rev-parse --git-dir)/comandos.txt"
grep -cE '^gh ' "$(git rev-parse --git-dir)/comandos.txt"
grep -nE '\b(close|delete|transfer|lock|reopen)\b|due_on|repos/hbgit/SinalACS/(branches|settings)|-X (PATCH|DELETE)' "$(git rev-parse --git-dir)/comandos.txt"
```
Expected: número igual à soma esperada (3 rótulos + 2 milestones + linhas da tabela com destino + reescritas×2 + issues novas); nenhuma linha no segundo `grep`. Mostrar os comandos ao usuário antes da Task 4. Conferir também a recusa por hash: `python3 -I scripts/escopo/gerar_comandos_issues.py docs/escopo/classificacao-issues.md --hash 0000000000000000000000000000000000000000 --lote rotulos; echo $?` → mensagem de recusa e código ≠ 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/escopo/gerar_comandos_issues.py
git commit -m "chore(escopo): gerador de comandos gh a partir da classificação aprovada"
```

---

### Task 4: Aplicação em lotes com log

**Files:** Create: `docs/escopo/log-aplicacao-issues.md`

- [ ] **Step 1: Lotes, nesta ordem, um por vez**

Gerar os comandos de cada lote **imediatamente antes** de executá-lo (as guardas consultam o estado atual), na ordem `rotulos` → `milestones` → `existentes` → `reescritas` → `novas` (as novas em lotes de até 5). Uma guarda `--conferir-corpo` que falhar para o lote naquela issue e segue este caminho de reaprovação: (1) atualizar a entrada daquela issue em `.git/issues-inventario.json` com o corpo atual (`gh issue view N --json number,title,labels,milestone,body`), senão a reescrita volta a usar o corpo antigo ou a guarda falha para sempre; (2) ajustar no documento o bloco/comentário daquela issue, se o novo corpo pedir, e commitar; (3) pedir ao usuário a aprovação do documento — qualquer ajuste muda o hash, então é uma nova aprovação do documento inteiro — e registrar uma **nova** linha `Aprovação da tabela: … — hash …` no ledger (a Task 3, Step 1 lê a mais recente com `tail -1`). Só então retomar o lote. Para cada comando: executar, anexar ao log uma linha `| data-hora | lote | comando (sem corpo) | resultado (URL ou erro) |`. Em erro, parar o lote, registrar e não seguir para o próximo sem decidir (ledger).

- [ ] **Step 2: Conferir reescritas**

Run (para cada issue reescrita N):
```bash
gh issue view N --json body -q .body > "$(git rev-parse --git-dir)/corpo-N.txt"
python3 -I -c "
import json,sys
norm=lambda t:'\n'.join(l.rstrip() for l in t.replace('\r\n','\n').split('\n')).strip()
inv={i['number']:i['body'] for i in json.load(open(sys.argv[1]))}
print(norm(open(sys.argv[3],encoding='utf-8').read()).endswith(norm(inv[int(sys.argv[2])])))
" "$(git rev-parse --git-dir)/issues-inventario.json" N "$(git rev-parse --git-dir)/corpo-N.txt"
```
Expected: `True` para todas (o corpo original está intacto no fim, com quebras de linha normalizadas).

- [ ] **Step 2b: Idempotência real**

Gerar de novo os lotes `existentes`, `reescritas` e `novas` com o mesmo hash.
Expected: nenhum comando `gh issue create`, `gh issue comment` ou `gh issue edit … --body-file` (só, no máximo, `--milestone`/`--add-label` já aplicados, que são inócuos).

- [ ] **Step 2c: Fonte única das ações da equipe**

Em `spec/escopo_projeto.md#acoes`, trocar a coluna "Situação" pela coluna "Issue", preenchida com `#NN` de cada `[P-NN]` criada; ações sem issue `[P-NN]` própria (P-01, P-06, P-09, P-10) recebem a issue do C-NN correspondente ou `—`. Abaixo da tabela: "A situação de cada ação é acompanhada na issue."

Run: `sed -n '/id="acoes"/,/^## /p' spec/escopo_projeto.md | grep -c 'Situação'; sed -n '/id="acoes"/,/^## /p' spec/escopo_projeto.md | grep -cE '\| #[0-9]+ \|'`
Expected: `0`; ≥ 7.

- [ ] **Step 3: Commit do log**

```bash
git add docs/escopo/log-aplicacao-issues.md spec/escopo_projeto.md
git commit -m "docs(escopo): log da aplicação da classificação das issues"
```

---

### Task 5: Verificação final

- [ ] **Step 1: Toda issue aberta tem destino**

Run:
```bash
gh issue list --state open --limit 500 --json number,milestone,labels | python3 -I -c "
import json,sys; d=json.load(sys.stdin)
print([i['number'] for i in d if not i['milestone'] and not {'futuro','a-decidir'} & {l['name'] for l in i['labels']}])"
```
Expected: `[]`.

- [ ] **Step 2: Todo C-NN do portão tem issue em Pilot**

Run:
```bash
gh issue list --state open --milestone Pilot --limit 500 --json title -q '.[].title' | grep -oE '^\[C-[0-9]{2}\]' | sort -u | tr -d '[]' | tr '\n' ' '
```
Expected: contém C-01 C-02 C-03 C-04 C-05 C-06 C-08 C-10 C-11 C-12. E toda linha `lacuna` da Cobertura dos Essenciais tem issue em Pilot: cada `N<k>` citado nessas linhas aparece no log com URL criada.

- [ ] **Step 3: Nenhuma issue fechada**

Run:
```bash
E=" $(grep -E '^\| [0-9]+ \|.*entregue em develop' docs/escopo/classificacao-issues.md | grep -oE '^\| [0-9]+' | tr -d '| ' | tr '\n' ' ') "
gh issue list --state closed --limit 100 --json number,closedAt -q '.[] | select(.closedAt > "2026-11-02") | .number' |
  while read -r n; do case "$E" in *" $n "*) ;; *) echo "fechada: #$n";; esac; done
```
Expected: nenhuma linha. Issues marcadas "entregue em develop" fechadas pelo merge `develop → main` são esperadas e não contam.

- [ ] **Step 4: Milestones sem data**

Run: `gh api 'repos/hbgit/SinalACS/milestones?state=all' -q '.[] | "\(.title) \(.due_on)"'`
Expected: `Pilot null` e `v1.0 null`.

- [ ] **Step 5: PR**

Atualizar o PR da Task 2 com o log e o resultado desta task. O corpo do PR ganha a seção `## Para a equipe decidir`, com cada issue `a-decidir` (ao menos a #96): número, título, as duas justificativas da Tabela lado a lado e a pergunta a responder ("Pilot, v1.0 ou futuro?"), com responsável `[A DEFINIR]`. Gerar a lista a partir da Tabela:
```bash
grep -E '^\| [0-9]+ \|.*a-decidir' docs/escopo/classificacao-issues.md
```
Expected: ao menos a linha da #96; todas aparecem na seção do PR. Pedir ao usuário merge ou revisão.
