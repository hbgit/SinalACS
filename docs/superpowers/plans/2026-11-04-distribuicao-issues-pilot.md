# Distribuição das issues do milestone "Pilot": plano

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`). **Nenhuma tarefa da Parte B roda antes de o dono do projeto (hbgit) aprovar a Tabela de atribuição da Parte A.**

**Objetivo:** distribuir as 35 issues abertas do milestone "Pilot" (hbgit/SinalACS) entre os colaboradores, de forma equilibrada e coerente com a área de cada um, para fechar os apps na versão Pilot.

**Abordagem:** a Parte A traz o levantamento já feito (somente leitura, em 2026-11-04), a classificação, o caminho crítico e a tabela proposta. A Parte B aplica a tabela com `gh`, só depois da aprovação, e confere o resultado.

**Ferramentas:** `gh` CLI autenticado como `hbgit` (admin do repositório).

**Fontes:** [`spec/requisitos_piloto.md`](../../../spec/requisitos_piloto.md) (prioridade de cada RF/RNF), [`spec/escopo_projeto.md`](../../../spec/escopo_projeto.md) (P-02…P-14), [`docs/escopo/mudancas-de-codigo-recomendadas.md`](../../escopo/mudancas-de-codigo-recomendadas.md) (C-01…C-12).

## Restrições globais

- Nenhuma issue é alterada (responsável, milestone, comentário, estado) antes da aprovação da Tabela de atribuição.
- Toda issue de **deploy/infraestrutura** e de **regulamentação** (LGPD, termos, política de privacidade, CEP, parecer jurídico, custódia de chave, publicação) fica com `hbgit`.
- Onde faltou informação para decidir, a issue vai para a lista de **Pendências**, sem suposição.
- Comentários e textos nas issues em pt-BR, sem atribuição de IA.
- Regra do projeto (RNF07/RNF08): nenhuma atribuição pode tornar um requisito Essencial dependente de unidade de saúde, sistema oficial ou serviço pago.

## Foco de revisão

1. **Login com caixa diferente:** o login do GitHub é `Rosialdo` (os commits aparecem também como `rosialdo`). Usar exatamente os logins da API de colaboradores; `gh` aceita sem distinção de caixa, mas a conferência da Task B5 compara pelo login canônico.
2. **Comentário duplicado ao reexecutar:** a Task B4 confere se o comentário de responsabilidade já existe antes de postar.
3. **Fechar issue entregue sem conferir o aceite:** #81/#83/#90/#94 só fecham depois de a Task B2 ler cada critério de aceite contra o `PROGRESS.md`.
4. **Atribuir antes da decisão do pilar B (#149):** as issues marcadas "B" na tabela mudam de milestone se a P-14 sair "não". A Task B3 só atribui essas issues se a #149 estiver decidida por "sim", ou se o dono aprovar atribuí-las mesmo assim.
5. **Conflito de arquivos entre issues paralelas:** #124 e #129 tocam textos com "UBS"; #124 e #125 copiam o mesmo aviso canônico. A Task B4 deixa registrado nas issues quem toca qual arquivo.

---

# Parte A: levantamento, análise e proposta (pronta para revisão)

## A1. Colaboradores e área de atuação

Fonte: `gh api repos/hbgit/SinalACS/collaborators`, `git log` desde 2026-01-01 e PRs de autores externos.

| Login | Papel | Commits | Onde atua (evidência) | Área inferida |
|---|---|---|---|---|
| `hbgit` | admin | ~1030 | todo o repositório | dono, deploy, regulamentação |
| `vinimartinsufrr` | write | 22 | `apps/admin` (35 arquivos), `apps/acs`, `apps/patient`, CI (PRs #5, #11, #26, #27) | **Flutter/mobile + CI** |
| `GuilhermeAlmeidadaLuz` | write | 9 | `backend/sinalacs_server` (38), `spec/lgpd_data_audit.md` (PRs #7, #53: cifra AES-GCM, HMAC, expurgo) | **backend Dart + LGPD/cifra** |
| `sarahw3b` | write | 4 | `spec/ux_accessibility_assessment.md`, `spec/ux_ui_test_plan.md`, guia da Google Play (PRs #6, #12, #29) | **UX/acessibilidade + testes de UX** (sem commit de código) |
| `Rosialdo` | write | 9 | `spec/security_assessment.md` (NIST CSF), `docs/showcase`, `video/showcase` (PRs #10, #35) | **segurança (análise) + conteúdo/apresentação** (1 arquivo em cada app) |

## A2. Issues abertas e classificação

Esforço: **P** (≤ 1 dia), **M** (2 a 5 dias), **G** (> 1 semana). Prioridade: **Alta** (bloqueia requisito Essencial ou o início do piloto), **Média** (Essencial sem bloquear outra issue, ou Desejável no caminho crítico), **Baixa** (Desejável/P3). Pilar: **A** (conteúdo e lembretes, sem login), **B** (acompanhamento pelo agente, depende da #149), **—** (ambos).

| Issue | Título curto | Tipo | Pilar | Esforço | Prioridade | Bloqueada por |
|---|---|---|---|---|---|---|
| #141 | P-02 encarregado da UFRR | regulamentação | — | P | Alta | — |
| #142 | P-03 PET-Saúde: agentes, preceptor | regulamentação | B | P | Alta | — |
| #143 | P-04 Plataforma Brasil (CEP) | regulamentação | — | G | **Alta (crítica)** | #141, #142, #144, #147 |
| #144 | P-05 território | regulamentação | — | P | Alta | — |
| #145 | P-07 temas e revisores | regulamentação/conteúdo | A | P | Alta | — |
| #146 | P-11 parecer da Procuradoria | regulamentação | A | P (+ espera) | Alta | — |
| #147 | P-12 instrumentos dos questionários | regulamentação | — | M | Alta | — |
| #148 | P-13 custódia do repo e da chave | regulamentação/deploy | — | P | **Alta (crítica)** | — |
| #149 | P-14 pilar B no piloto? | regulamentação (escopo) | B | P | **Alta (crítica)** | — |
| #124 | C-01 texto legal do paciente | regulamentação | — | P | Alta | #141 |
| #134 | APK assinado no GitHub Releases | deploy | — | M | **Alta (crítica)** | #148 |
| #135 | compose do piloto + Let's Encrypt | deploy | — | M | Alta | #148 (custódia da CA) |
| #136 | RNF03 cifra local do paciente (Fase 2: PIN) | funcionalidade/segurança | B | M | Alta | #128 (Fase 2) |
| #125 | C-02 aviso educativo (1ª abertura + Sobre) | UI/conteúdo | A | P | Alta | — |
| #126 | C-03 biblioteca de conteúdo offline | funcionalidade/conteúdo | A | M | Alta | #145 |
| #127 | C-04 pedido de contato + "Ligar 192" | funcionalidade | — | G | Alta (bloqueia #130, #131) | #136 Fase 1 (entregue no PR #150) |
| #128 | C-05 acesso sem CPF/SMS/e-mail | funcionalidade | B | G | Alta | #149 |
| #129 | C-06 trocar "UBS" nos textos | UI/conteúdo | — | M | Média | — |
| #130 | C-08 três saídas, sem risco | UI/UX | A | M | Alta | #127, #146 (se P-11 for rejeitada, RF04 vira Futuro) |
| #131 | C-10 "Apagar meus dados" + 30 dias | funcionalidade/LGPD | A | M | Alta | #127; prazo final pelo TCLE (#143) |
| #132 | C-11 autoavaliação local + paridade 64 | funcionalidade/testes | A | M | Alta | — |
| #133 | C-12 recuperação de acesso | funcionalidade/segurança | B | M | Alta | #128 |
| #137 | RNF05 WCAG AA no paciente | UI/UX + testes | — | G | Alta (fecha o caminho) | #125, #126, #127, #128, #130, #131 (telas existirem) |
| #151 | ACS `open_failed` ambíguo | correção | B | M | Alta (perda de visitas, RNF02) | — |
| #152 | ACS `dataExtractionRules` | correção/segurança | B | P | Média | — |
| #153 | paciente preso no diálogo de notificação | correção | — | P | **Alta** (tela de urgência não abre) | — |
| #114 | `acs_full_e2e.sh` 5/6 (SnackBar) | testes | B | P | Média | — |
| #111 | aviso "outro ACS já confirmou" | funcionalidade | B | M | Baixa | — |
| #117 | ACK com identidade do aparelho | segurança | B | M | Média | — |
| #100 | descartes de telemetria pelo teto local | funcionalidade | B | M | Baixa (P3) | — |
| #101 | reemitir eventos de telemetria perdidos | funcionalidade | B | M | Baixa (P3) | — |
| #81 | remote wipe (R3) | — | B | — | já entregue | — |
| #83 | telemetria §1.3 | — | B | — | já entregue | — |
| #90 | mTLS Traefik ↔ backend | — | — | — | já entregue | — |
| #94 | certificado MQTT por aparelho | — | B | — | já entregue | — |

Por tipo: regulamentação 10 (#124, #141–#149), deploy/infra 2 (#134, #135), funcionalidade 11, UI/UX/conteúdo 4, correção 3, testes 1, já entregues 4.

## A3. Caminho crítico

Três trilhas correm em paralelo. O piloto começa quando as três terminam.

1. **Ética (a mais longa, externa):** #141 + #142 + #144 + #147 → **#143** (submissão e parecer do CEP). O parecer também fixa o prazo de retenção da #131 (30 dias propostos).
2. **Entrega do APK:** **#148** (custódia da chave) → **#134** (release assinado) e #135 (compose com a CA fora do repositório).
3. **Código:**
   - Pilar A: #127 → #130 e #131; #125, #126 (depois da #145) e #132 em paralelo; #153 antes de tudo, porque impede a tela de urgência de abrir na primeira execução.
   - Pilar B (se a #149 disser "sim"): #128 → #133 e a Fase 2 da #136.
   - Fechamento: **#137** (WCAG), depois que as telas novas existirem.

A **#149** decide o tamanho da trilha 3: se o pilar B sair, #128, #133, a Fase 2 da #136, #111, #114, #117, #151 e #152 passam para v1.0.

## A4. Duplicadas, vagas ou fora do milestone

| Issue | Situação | Proposta |
|---|---|---|
| #81, #83, #90, #94 | Entregues e em `main` (PRs #93, #98, #113 e #119 em `develop`, levados a `main` pelo PR #120). Seguem abertas porque o PR mirou `develop` e não fechou a issue. As partes restantes já têm issue própria (#116, #117, #118, #100, #101). | Conferir o aceite (Task B2) e **fechar**. |
| #100, #101 | P3. A própria #83 recomenda fazer a #100 só se o piloto mostrar aparelhos no teto. | **Mover para v1.0.** |
| #111 | Melhoria de UX (Desejável), depende do pilar B. | **Mover para v1.0** (ver Pendência 4). |
| #117 | Lacuna de segurança, não é regressão; com 2 ou 3 agentes o risco é pequeno. | **Decisão do dono** (Pendência 4). |
| #134 × #148, #135 × #148 | Não são duplicadas, mas o primeiro critério da #134 e o último da #135 são a própria #148. | Manter; registrar na #134 e na #135 que esses critérios fecham com a #148. |
| #124 × #125 × #129 | Sobrepõem texto: o aviso canônico (em #124 e #125) e a palavra "UBS" (em #124 e #129). | Manter; a #129 não toca `legal_documents.dart` (fica com a #124), e a #125 reaproveita o mesmo texto canônico. |
| #144, #145, #146 | Têm um critério só ("registrado"), sem dizer onde registrar. | Vaga, mas aceitável para uma ação. Ao fechar, registrar na tabela de pendências de `spec/escopo_projeto.md`. |

## A5. Tabela de atribuição proposta (para aprovação)

Carga em pontos (P=1, M=2, G=3), sem as issues propostas para v1.0 ou para fechamento.

| Issue | Tipo | Esforço | Prioridade | Responsável sugerido | Justificativa |
|---|---|---|---|---|---|
| #141 | regulamentação | P | Alta | `hbgit` | Regra: regulamentação (LGPD, encarregado). |
| #142 | regulamentação | P | Alta | `hbgit` | Regra: regulamentação (acordo com o PET-Saúde). |
| #143 | regulamentação | G | Alta | `hbgit` | Regra: regulamentação (CEP); pesquisador responsável é o líder do PRISM (P-02). |
| #144 | regulamentação | P | Alta | `hbgit` | Regra: regulamentação (território, entra no TCLE). |
| #145 | regulamentação | P | Alta | `hbgit` | Regra: regulamentação (licença CC BY 4.0, revisores institucionais). |
| #146 | regulamentação | P | Alta | `hbgit` | Regra: regulamentação (parecer jurídico). |
| #147 | regulamentação | M | Alta | `hbgit` | Regra: regulamentação (instrumentos do CEP, operador de dados). |
| #148 | regulamentação/deploy | P | Alta | `hbgit` | Regra: custódia da chave e do repositório. |
| #149 | regulamentação (escopo) | P | Alta | `hbgit` | Regra: decisão de escopo junto ao CEP/PET-Saúde. |
| #124 | regulamentação | P | Alta | `hbgit` | Regra: termos e política de privacidade. |
| #134 | deploy | M | Alta | `hbgit` | Regra: publicação do APK. |
| #135 | deploy | M | Alta | `hbgit` | Regra: deploy/infraestrutura. |
| #136 | funcionalidade/segurança | M | Alta | `hbgit` (mantém) | Já atribuída; Fase 1 entregue no PR #150 pelo próprio dono. |
| #127 | funcionalidade | G | Alta | `vinimartinsufrr` | Maior histórico em `apps/patient`; é a peça que destrava #130 e #131. |
| #132 | funcionalidade/testes | M | Alta | `vinimartinsufrr` | Paridade das 64 combinações no CI; único colaborador com PRs de CI (#26, #27). |
| #151 | correção | M | Alta | `vinimartinsufrr` | Código do `apps/acs`, onde já atuou; segue a solução D2d da #136. |
| #153 | correção | P | Alta | `vinimartinsufrr` | `main.dart` do paciente; correção pequena e urgente, junto da #127. |
| #128 | funcionalidade | G | Alta | `GuilhermeAlmeidadaLuz` | Backend de autenticação + identificador pseudônimo (LGPD); fez cifra e HMAC no PR #53. |
| #133 | funcionalidade/segurança | M | Alta | `GuilhermeAlmeidadaLuz` | Continua a #128 (invalidação da credencial no servidor); sequencial, sem troca de contexto. |
| #131 | funcionalidade/LGPD | M | Alta | `GuilhermeAlmeidadaLuz` | Expurgo e retenção, como a rotina LGPD-RF07 que ele entregou; usa `PatientLocalDatabase.deleteEverything()`. |
| #137 | UI/UX + testes | G | Alta | `sarahw3b` (mantém) | Já atribuída; autora da avaliação WCAG (`spec/ux_accessibility_assessment.md`). |
| #130 | UI/UX | M | Alta | `sarahw3b` | Copy e apresentação das três saídas sem cor clínica: decisão de UX que ela já registra no plano de testes. **Ver Pendência 2.** |
| #114 | testes | P | Média | `sarahw3b` | Teste de interface no emulador (SnackBar sobre o botão); afinidade com o plano de testes de UX. **Ver Pendência 2.** |
| #125 | UI/conteúdo | P | Alta | `Rosialdo` | Texto canônico + tela simples, reaproveitando `LocalProtectionNotice`; boa porta de entrada no código. **Ver Pendência 2.** |
| #126 | funcionalidade/conteúdo | M | Alta | `Rosialdo` | Conteúdo com fontes e licença CC BY 4.0; experiência com produção de conteúdo (`docs/showcase`). **Ver Pendência 2.** |
| #129 | UI/conteúdo | M | Média | `Rosialdo` | Troca de texto nos três apps + testes de widget; tocou os três apps no PR #35. |
| #152 | correção/segurança | P | Média | `Rosialdo` | Espelha arquivos já prontos do paciente (#136); autor da análise de segurança NIST. |
| #81, #83, #90, #94 | — | — | — | `hbgit` (fechar) | Entregues; só o admin confere e fecha. |
| #100, #101, #111 | — | — | Baixa | — (mover para v1.0) | Ver A4. |
| #117 | segurança | M | Média | **Pendência 4** | Se ficar no Pilot: `GuilhermeAlmeidadaLuz` (backend/ACL), depois da #133. |

**Carga resultante:** `vinimartinsufrr` 8 · `GuilhermeAlmeidadaLuz` 7 · `sarahw3b` 6 · `Rosialdo` 6 · `hbgit` 12 de regulamentação/deploy + #136.

## A6. Pendências (decidir antes de aprovar)

1. **Disponibilidade de cada colaborador.** O equilíbrio acima supõe a mesma dedicação semanal para todos. Se alguém tiver menos horas, a carga muda.
2. **Experiência em Flutter de `sarahw3b` e `Rosialdo`.** O histórico dos dois tem só documentação, análise e apresentação. Se não programarem em Flutter, #130 e #114 (Sarah) e #125, #126 e #129 (Rosialdo) passam para `vinimartinsufrr`. Os dois ficariam então com a parte de conteúdo e revisão: textos da #126 e #130 e revisão manual com leitor de tela da #137.
3. **Decisão da #149 (pilar B).** Se for "não", #128, #133, #151, #152 e #114 saem do Pilot. A carga de `GuilhermeAlmeidadaLuz` cai para 2, e ele pode assumir a #132 ou a #130.
4. **#111 e #117:** confirmar se vão para v1.0. A tabela propõe v1.0 para a #111 e deixa a #117 em aberto.
5. **Fechamento de #81, #83, #90 e #94:** confirmar se o dono quer fechá-las agora ou no próximo `develop` → `main`.

**Aprovação (2026-11-04).** O dono aprovou a Tabela A5 como proposta. Leitura aplicada às pendências:
- Resolvida em 2026-11-04 (1 e 2): a tabela é aplicada como está; a troca para `vinimartinsufrr` fica para quando a disponibilidade ou a experiência em Flutter mostrarem a necessidade.
- Resolvida em 2026-11-04 (3): as issues do pilar B são atribuídas já; se a #149 sair "não", elas mudam de milestone e a atribuição é revista.
- Resolvida em 2026-11-04 (4): #100, #101 e #111 vão para v1.0; a #117 fica no Pilot, sem responsável, até decisão do dono.
- Resolvida em 2026-11-04 (5): #81, #83, #90 e #94 fecham agora, depois da conferência da Task B2.

---

# Parte B: aplicação (somente após a aprovação)

### Task B1: registrar a aprovação

**Arquivos:** modificar `docs/superpowers/plans/2026-11-04-distribuicao-issues-pilot.md` (Tabela A5 e Pendências A6).

- [ ] **Passo 1:** aplicar à Tabela A5 as respostas do dono às Pendências 1 a 5. Cada pendência resolvida vira uma linha `Resolvida em <data>: <decisão>`.
- [ ] **Passo 2:** commit.

```bash
git add docs/superpowers/plans/2026-11-04-distribuicao-issues-pilot.md
git commit -m "docs(plano): tabela de atribuição do Pilot aprovada"
```

### Task B2: fechar as entregues e mover as adiadas

- [ ] **Passo 1:** para #81, #83, #90 e #94, ler os critérios (`gh issue view <n>`) e localizar cada um na seção correspondente do `PROGRESS.md`. Critério sem evidência = não fechar; listar.
- [ ] **Passo 2:** fechar as conferidas.

```bash
for n in 81 83 90 94; do
  gh issue close "$n" --repo hbgit/SinalACS --reason completed \
    --comment "Entregue e levado a main pelo PR #120. As partes restantes seguem nas issues próprias (#100, #101, #116, #117, #118)."
done
```

- [ ] **Passo 3:** mover as aprovadas para v1.0 (Pendência 4).

```bash
for n in 100 101 111; do gh issue edit "$n" --repo hbgit/SinalACS --milestone "v1.0"; done
```

- [ ] **Passo 4:** conferir. `gh issue list --repo hbgit/SinalACS --milestone Pilot --state open --json number --jq 'length'` deve devolver 35 menos as fechadas e as movidas (28 com a proposta original).

### Task B3: atribuir

- [ ] **Passo 1:** rodar as atribuições da Tabela A5 aprovada. Com a proposta original:

```bash
R=hbgit/SinalACS
for n in 141 142 143 144 145 146 147 148 149 124 134 135; do gh issue edit $n --repo $R --add-assignee hbgit; done
for n in 127 132 151 153; do gh issue edit $n --repo $R --add-assignee vinimartinsufrr; done
for n in 128 133 131;     do gh issue edit $n --repo $R --add-assignee GuilhermeAlmeidadaLuz; done
for n in 130 114;         do gh issue edit $n --repo $R --add-assignee sarahw3b; done
for n in 125 126 129 152; do gh issue edit $n --repo $R --add-assignee Rosialdo; done
# #136 (hbgit) e #137 (sarahw3b) já estão atribuídas.
```

Se a #149 ainda não estiver decidida, pular #128, #133, #151, #152 e #114, a menos que o dono tenha aprovado atribuí-las mesmo assim (Foco de revisão 4).

- [ ] **Passo 2:** conferir.

```bash
gh issue list --repo hbgit/SinalACS --milestone Pilot --state open --limit 100 \
  --json number,assignees --jq '.[] | select(.assignees|length==0) | .number'
```

Esperado: nenhuma saída, ou só as issues puladas no Passo 1 e as que dependem da Pendência 4 (#117).

### Task B4: comentar nas issues de deploy e regulamentação

- [ ] **Passo 1:** comentar em cada uma, sem duplicar.

```bash
R=hbgit/SinalACS
MSG='Responsável: @hbgit (deploy e regulamentação do piloto ficam com o coordenador do projeto, conforme a distribuição do milestone Pilot em docs/superpowers/plans/2026-11-04-distribuicao-issues-pilot.md).'
for n in 141 142 143 144 145 146 147 148 149 124 134 135; do
  gh issue view $n --repo $R --json comments --jq '.comments[].body' | grep -q 'distribuição do milestone Pilot' \
    || gh issue comment $n --repo $R --body "$MSG"
done
```

- [ ] **Passo 2:** na #134 e na #135, comentar que o critério de custódia fecha junto com a #148. Na #129, comentar que `legal_documents.dart` fica com a #124 (A4).
- [ ] **Passo 3:** conferir. Em cada uma das 12 issues, o comentário de responsabilidade aparece **uma** vez:

```bash
for n in 141 142 143 144 145 146 147 148 149 124 134 135; do
  echo "$n $(gh issue view $n --repo hbgit/SinalACS --json comments --jq '[.comments[].body|select(contains("distribuição do milestone Pilot"))]|length')"
done
```

Esperado: `1` em todas as linhas.

### Task B5: fechar o plano

- [ ] **Passo 1:** gerar o retrato final (`gh issue list --milestone Pilot --state open --json number,title,assignees`) e colar no fim deste arquivo, em "Resultado aplicado", com a data.
- [ ] **Passo 2:** commit em branch própria (`docs/distribuicao-pilot`) e PR contra `develop`.

---

## Resultado aplicado (2026-11-04)

- Fechadas (Task B2): #81, #83, #90, #94, cada uma com comentário que aponta a prova no `PROGRESS.md`.
- Movidas para v1.0: #100, #101, #111.
- Pilot: 28 issues abertas.
- Comentário de responsabilidade do `hbgit` nas 12 issues de deploy e regulamentação (uma vez em cada); notas de dependência na #134, #135 e #129.

| Issue | Responsável |
|---|---|
| #114 acs_full_e2e.sh: primeiro teste falha no tap em sync_visits coberto por SnackBar (regressão pós-#83) | sarahw3b |
| #117 [P2] ACK com identidade de aparelho: %c na ACL ou deviceId no payload validado contra a microárea do alerta (continuação da #94) | — (Pendência 4) |
| #124 [C-01] Texto legal do app do paciente: controlador, encarregado e aviso educativo | hbgit |
| #125 [C-02] Aviso educativo na primeira abertura e em "Sobre" | Rosialdo |
| #126 [C-03] Biblioteca de conteúdo educativo offline (pilar A) | Rosialdo |
| #127 [C-04] Pedido de contato sem rótulo de urgência e saída "Ligar 192" sem envio | vinimartinsufrr |
| #128 [C-05] Acesso do participante sem CPF, SMS ou e-mail (RF24) | GuilhermeAlmeidadaLuz |
| #129 [C-06] Trocar "UBS" nos textos dos apps por grupo e coordenação do piloto | Rosialdo |
| #130 [C-08] Autoavaliação com três saídas, sem classificação de risco | sarahw3b |
| #131 [C-10] "Apagar meus dados" e retenção local de 30 dias | GuilhermeAlmeidadaLuz |
| #132 [C-11] Autoavaliação local no pilar A, sem sessão nem registro no servidor | vinimartinsufrr |
| #133 [C-12] Recuperação de acesso que invalida a credencial do aparelho anterior | GuilhermeAlmeidadaLuz |
| #134 [RNF07] APK assinado publicado em GitHub Releases | hbgit |
| #135 [RNF07] Compose do piloto: um host, Let's Encrypt e documentação única | hbgit |
| #136 [RNF03] Cifra local dos dados do app do paciente com PIN | hbgit |
| #137 [RNF05] Acessibilidade WCAG AA dos fluxos do piloto no app do paciente | sarahw3b |
| #141 [Ação P-02] Contato com o encarregado de dados da UFRR | hbgit |
| #142 [Ação P-03] Confirmação com a coordenação do PET-Saúde | hbgit |
| #143 [Ação P-04] Submissão na Plataforma Brasil | hbgit |
| #144 [Ação P-05] Definição do território com o PET-Saúde | hbgit |
| #145 [Ação P-07] Lista de temas e revisores do conteúdo educativo | hbgit |
| #146 [Ação P-11] Pedido de parecer à Procuradoria Federal junto à UFRR | hbgit |
| #147 [Ação P-12] Instrumentos dos questionários e serviço de aplicação | hbgit |
| #148 [Ação P-13] Custódia do repositório e da chave de assinatura do APK | hbgit |
| #149 [Ação P-14] Decidir se o pilar B entra no piloto | hbgit |
| #151 [ACS] open_failed ambíguo pode tornar ilegíveis visitas não enviadas | vinimartinsufrr |
| #152 [ACS] Excluir dados da transferência entre aparelhos (dataExtractionRules) | Rosialdo |
| #153 [Paciente] Primeira abertura presa ao diálogo de permissão de notificações | vinimartinsufrr |
