# Roteiro de vídeo — apresentação do SinalACS ao sponsor

**Público:** investidor / banca de edital de fomento
**Duração alvo:** 180 segundos (3 min)
**Orçamento de locução:** 419 palavras a ~145 palavras/min ≈ **173 s**, deixando ~7 s de folga para pausas e respiração
**Captura:** app Flutter real rodando em emulador Android (`sdk gphone64 x86 64`), gravação de tela em retrato 1080×2400, mais um plano de terminal para o bloco 5
**Dados:** exclusivamente sintéticos (Maria Oliveira, João Pereira, Ana Costa), conforme a invariante de privacidade do projeto

---

## Tabela mestre de cenas

| # | Bloco | Timecode | Palavras | Tela / plano principal |
|---|-------|----------|----------|------------------------|
| 1 | O problema | 0:00 – 0:20 | 48 | Sem UI — cartela de texto ou imagem de território |
| 2 | A solução e o moat | 0:20 – 0:35 | 34 | Cartela com os três nomes: e-SUS APS · WhatsApp · SinalACS |
| 3 | Demo — paciente | 0:35 – 1:15 | 96 | App paciente: login → triagem (3 passos) → status |
| 4 | Demo — ACS | 1:15 – 2:05 | 116 | App ACS: territorialização → fila priorizada → registro de visita |
| 5 | A prova técnica | 2:05 – 2:25 | 46 | Terminal: `docker compose` + ciclo de alerta vermelho + CI verde |
| 6 | Escala e roadmap | 2:25 – 2:45 | 44 | Cartela: números de capacidade e barra de fases |
| 7 | O pedido | 2:45 – 3:00 | 35 | Cartela final com o pedido de piloto |

**Fio condutor:** o mesmo caso clínico — **Maria Oliveira, 72 anos, falta de ar aguda** — atravessa os blocos 3 e 4. O corte do `Risco: Vermelho` na tela do paciente para o card vermelho no topo da fila do ACS é o momento em que a proposta de valor inteira aparece em dois planos. Não separe esse par.

---

## Bloco 1 — O problema · 0:00 – 0:20

> **Locução:**
> Hoje, o Agente Comunitário de Saúde visita as casas na ordem do mapa. Rua por rua, sempre igual. O problema é que a doença não segue o mapa. O idoso com falta de ar pode ser a última visita do dia, simplesmente porque mora no fim da rua.

**Em tela:** nenhuma interface ainda. Cartela sobre fundo escuro (`#030712`, o mesmo dos apps) com a frase-chave em texto grande: **"A doença não segue o mapa."** Se houver imagem de território disponível, usar como fundo com forte escurecimento.

**Nota de captura/edição:** abrir em silêncio, sem trilha, e entrar com a locução em 0:02. Não usar vermelho nesta cartela — a cor vermelha só entra em cena no bloco 3, quando passa a significar gravidade.

---

## Bloco 2 — A solução e o moat · 0:20 – 0:35

> **Locução:**
> O SinalACS troca o roteiro geográfico por uma fila ordenada por risco clínico. O e-SUS APS registra o que já aconteceu. O WhatsApp desorganiza. O SinalACS prioriza — com regra determinística, sem inteligência artificial.

**Em tela:** três colunas que entram uma por vez, sincronizadas com a locução: `e-SUS APS → registra` · `WhatsApp → desorganiza` · `SinalACS → prioriza`. A terceira coluna fica destacada.

**Nota de captura/edição:** "sem inteligência artificial" é um argumento de venda para edital público, não uma limitação — sustentar essa frase em tela por 2 s antes do corte. Classificação clínica auditável e reproduzível é requisito, não simplificação.

---

## Bloco 3 — Demo do app do paciente · 0:35 – 1:15

> **Locução:**
> Do lado do cidadão: acesso sem senha, com CPF e data de nascimento. Maria, 72 anos, abre a triagem. São três perguntas, com uma resposta por vez. Ela marca "falta de ar ou cansaço intenso". E aqui está o ponto: a classificação sai pronta. Risco vermelho. Não existe campo para editar, nem para o paciente, nem para o agente. A mesma resposta gera sempre a mesma cor, porque a regra é fechada e auditável — inspirada no Protocolo de Manchester. O paciente então acompanha o chamado como quem rastreia uma encomenda: enviado, visualizado, em análise, agendado.

**Em tela — sequência exata a gravar** (`apps/patient/lib/app/app.dart`):

| Tempo | Tela | Ação | O que aparece |
|-------|------|------|---------------|
| 0:35 | `PatientLoginScreen` | Preencher CPF e data de nascimento, tocar **"Entrar sem senha"** | Avança para a triagem |
| 0:42 | `TriageScreen` passo 1 | Marcar **"Falta de ar ou cansaço intenso"** → "Próxima pergunta" | `Passo 1 de 3` + barra de progresso |
| 0:50 | `TriageScreen` passo 2 | Marcar **"Sim, começou de repente"** → "Próxima pergunta" | `Passo 2 de 3` |
| 0:56 | `TriageScreen` passo 3 | Marcar **"Dor no peito ou sangramento"** → "Concluir triagem" | `Passo 3 de 3` e, abaixo do botão, **`Risco: Vermelho`** |
| 1:05 | `StatusScreen` | — | Linha do tempo `Enviado → Visualizado → Em análise → Agendado` |

**Nota de captura/edição:** o beat mais importante do vídeo é 0:56–1:05. Quando `Risco: Vermelho` aparecer, **congelar o quadro por 1,5 s e aplicar zoom suave** no texto. A locução "a classificação sai pronta" tem que cair exatamente sobre esse frame. A regra que produz esse resultado está em `_risk` (`app.dart:251`) — a resposta "falta de ar" leva a vermelho sempre, o que torna a demo repetível em qualquer tomada.

**Tela opcional, se sobrar tempo:** `EmergencyScreen` — botão circular `EMERGÊNCIA` → diálogo de confirmação → o estado muda para **"Alerta enfileirado localmente"**. Só incluir com a locução dizendo "enfileirado", nunca "enviado ao agente" (ver guardrails).

---

## Bloco 4 — Demo do app do ACS · 1:15 – 2:05

> **Locução:**
> Do lado do agente, o mesmo caso reaparece. Ao entrar, ele carrega só a própria microárea: 142 pacientes, em cache local. Nenhum agente enxerga o território de outro — é uma invariante do sistema, não uma configuração. E a fila já vem ordenada. Maria Oliveira no topo, em vermelho. João Pereira, glicemia descompensada, em amarelo. Ana Costa, dúvida de rotina, em verde. A cor aqui nunca é decoração: ela significa gravidade. Terminada a visita, o registro é feito na porta da casa, com ou sem sinal. O agente salva, e o app enfileira localmente para sincronizar sozinho quando a rede voltar. Em zona rural, isso é a diferença entre ter o dado e perder o dia.

**Em tela — sequência exata a gravar** (`apps/acs/lib/app/app.dart`):

| Tempo | Tela | Ação | O que aparece |
|-------|------|------|---------------|
| 1:15 | `TerritorializationScreen` | Apenas exibir — **não tocar no botão** | `Microárea 12 - Zona Rural` · `Pacientes sincronizados: 142 cadastrados` · `Cache local: Atualizado há 10 min` |
| 1:26 | `DashboardScreen` | Exibir e rolar devagar | Três cards com borda esquerda vermelha / amarela / verde; Maria Oliveira no topo |
| 1:45 | `VisitRegistrationScreen` | Escolher status, digitar uma observação curta, tocar **"Salvar e enfileirar sincronização"** | `SnackBar`: "Visita salva e enfileirada localmente para sincronização" |

**Nota de captura/edição:** a cena 1:45 é a **única ação de interface do app ACS que executa lógica real** — grava de fato na `OfflineVisitQueue`. Filmar o toque e o `SnackBar` em plano contínuo, sem corte, porque é a prova visual de que o offline-first não é slide. Se possível, **ativar o modo avião do emulador antes desta cena** e deixar o indicador de "sem rede" visível na barra de status: o argumento fica muito mais forte.

Para o corte de entrada do bloco, usar transição direta do `Risco: Vermelho` do paciente para o card vermelho do dashboard. Sem transição elaborada — um corte seco vende melhor a continuidade do dado.

---

## Bloco 5 — A prova técnica · 2:05 – 2:25

> **Locução:**
> Isto não é maquete. O ciclo crítico já roda ponta a ponta: o alerta vermelho entra na API, é publicado no broker MQTT no tópico da microárea, e volta com confirmação de recebimento. Alerta vermelho não se perde em silêncio. Integração contínua verde nos quatro trilhos.

**Em tela:** plano de terminal em close, fonte grande, quatro momentos encadeados:

1. `docker compose up` com a stack de pé (PostgreSQL, Mosquitto, backend, Traefik).
2. `POST /v1/alerts/red` com cabeçalho `Idempotency-Key` → resposta **201**.
3. Log do dispatcher publicando no tópico da microárea, seguido de `POST /v1/alerts/{id}/ack` → confirmação.
4. Corte rápido para os quatro jobs verdes do GitHub Actions (`.github/workflows/ci.yml`).

**Nota de captura/edição:** este bloco **não sai dos apps** — hoje os apps Flutter ainda não chamam o backend, e o ciclo real vive no servidor. Gravar do terminal é o caminho honesto e, para uma banca técnica, mais convincente. Ampliar a fonte do terminal antes de gravar e destacar em amarelo, na edição, apenas o `201` e a linha de ACK. Este é o ciclo que a métrica North Star (TMRAV, **alvo** < 90 s) vai medir no piloto — não citar número de latência medido, porque ainda não existe medição em campo.

---

## Bloco 6 — Escala e roadmap · 2:25 – 2:45

> **Locução:**
> Cada duas Unidades Básicas comportam cinco mil pacientes e cem agentes. As fases de prova de conceito e de alfa estão concluídas e versionadas. O que falta é a fase três: deploy monitorado, teste de carga e a auditoria de conformidade com a LGPD.

**Em tela:** cartela com os números de capacidade (`5.000 pacientes` · `100 ACS` · `2 UBS`) e, abaixo, uma barra de três fases com as duas primeiras preenchidas e a terceira vazia: `Fase 1 — Prova de conceito ✓` · `Fase 2 — Alfa/Beta ✓` · `Fase 3 — Disponibilidade geral`.

**Nota de captura/edição:** os números de capacidade são planejamento dimensionado no PRD, não usuários existentes. Rotular a cartela como **"Capacidade projetada por 2 UBS"** para que ninguém leia como base instalada.

---

## Bloco 7 — O pedido · 2:45 – 3:00

> **Locução:**
> O pedido é um piloto: uma Unidade Básica, duas microáreas, cinquenta pacientes. É o que precisamos para medir a única métrica que importa — quanto tempo leva, hoje, até alguém chegar em quem está pior.

**Em tela:** cartela final, fundo escuro, três números grandes: **1 UBS · 2 microáreas · 50 pacientes**. Abaixo, em corpo menor, o nome do projeto e o contato.

**Nota de captura/edição:** o pedido corresponde exatamente ao critério de aceite M3.5 já registrado no PRD — se a banca perguntar de onde veio o número, a resposta está documentada. Terminar em silêncio, sem música de encerramento subindo: a última frase é a tese do projeto e deve ficar sozinha no ar por 2 s.

---

## Guardrails de veracidade

Regras de gravação. Valem para qualquer tomada.

### Não filmar estes controles

Todos disparam um `SnackBar` de "não integrado" e queimam a demonstração na frente do sponsor:

| Tela | Controle | Mensagem que aparece |
|------|----------|----------------------|
| `MapScreen` | "Traçar rota eficiente" | "Traçado de rota depende da integração de mapas" — e a própria tela imprime **"Mapa demonstrativo"** |
| `EscalationScreen` | "Ligar para o SAMU (192)" | "Discagem não está integrada neste protótipo" |
| `GeofencingScreen` | "Abrir formulário da visita" | "Use a tela Visita para registrar o atendimento" |
| `NoticesScreen` | "Preparar aviso" | "Envio depende da integração de notificações push" |
| `TerritorializationScreen` | "Atualizar dados da microárea" | "Atualização será integrada à API central" — a tela pode aparecer, o botão não pode ser tocado |
| `DashboardScreen` | Card verde (Ana Costa) | "Canal de dúvidas demonstrativo" — o card pode aparecer na fila, o botão não pode ser tocado |

### Não afirmar na locução

- **Que o alerta do paciente chega ao aparelho do ACS.** Hoje o app do paciente apenas muda um estado local. A formulação correta é "o alerta é registrado e enfileirado"; o ciclo real de entrega é mostrado no bloco 5, no backend.
- **"Mapa ao vivo", "geofencing ativo", "SAMU integrado", "push disparado".** Os quatro são stubs. Se mapa e geofencing precisarem aparecer, entram como **roadmap v1.5**, com selo em tela, nunca como capacidade atual.
- **Números de resultado como se fossem medidos.** Redução ≥ 40 % no tempo até a visita, ≥ 90 % de concordância com a avaliação médica, > 99,5 % de sincronização e TMRAV < 90 s são **hipóteses e alvos do MVP**. A locução deve dizer "é o que o piloto vai medir" e o texto em tela deve trazer a palavra **"alvo"**.

### Privacidade

Somente dados sintéticos — que é o que os apps já usam. Nenhuma tela com dado real de paciente, e nenhum arquivo `.env`, credencial, token ou string de conexão visível em quadro durante a gravação do terminal no bloco 5.

---

## Preparação antes de gravar

1. **Card do dashboard do ACS.** `apps/acs/lib/app/app.dart` passava `'Maria Souza'` como segundo nome, sem rótulo, no card de Maria Oliveira — em tela liam-se dois nomes diferentes no mesmo paciente, justamente no plano mais importante do vídeo. Já corrigido; confirmar visualmente antes de filmar.
2. **Captura da tela de emergência do paciente.** `docs/screenshots/patient/01-emergencia.png` é byte-idêntico a `docs/screenshots/acs/01-login.png` — é o login do ACS salvo no lugar errado. Recapturar no emulador, já que `docs/telas-paciente.md` referencia essa imagem.
3. **Banco preparado para o bloco 5.** Aplicar as três migrações em ordem e depois `seeds/development.sql` (ver `CLAUDE.md`). Sem o seed, o `POST /v1/alerts/red` falha por violação de chave estrangeira em `alerts.patient_id` e o bloco técnico não grava.

---

## Checklist de verificação do roteiro

- [ ] Contagem de palavras da locução entre 400 e 420 (atual: **419**, medido bloco a bloco).
- [ ] Leitura em voz alta cronometrada; cada bloco fecha no seu timecode com ±3 s.
- [ ] Percurso das telas conferido nos dois apps (`flutter run`), sem acionar nenhum controle da tabela de "não filmar".
- [ ] Ciclo `POST /v1/alerts/red` → `POST /v1/alerts/{id}/ack` respondendo 201 + ACK antes de gravar o terminal.
- [ ] Revisão de honestidade: nenhum verbo no presente descrevendo capacidade que hoje é stub; nenhum número de meta sem a palavra "alvo" ou "hipótese".

## Referências

- [Telas do app ACS](telas-acs.md) · [Telas do app paciente](telas-paciente.md)
- [PRD do sistema](../spec/PRD_system.md) — hipóteses H1–H4, invariantes INV-01–05, métricas e milestones
- [Estado dos milestones](../PROGRESS.md)
- Protótipos visuais de referência: [`spec/ui_acs/`](../spec/ui_acs) e [`spec/ui_paciente/`](../spec/ui_paciente)
