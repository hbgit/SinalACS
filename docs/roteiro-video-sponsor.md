# Roteiro de vídeo — apresentação do SinalACS ao sponsor

**Público:** investidor / banca de edital de fomento
**Duração alvo:** 180 segundos (3 min)
**Orçamento de locução:** 419 palavras a ~145 palavras/min ≈ **173 s**, deixando ~7 s de folga para pausas e respiração
**Captura:** app Flutter real rodando em **celular Android físico** via `adb screenrecord`, em retrato 1080×2400, mais um plano de terminal para o bloco 5
**Entrega:** 1920×1080 (16:9) — a filmagem em retrato entra centralizada sobre `#030712`, com as legendas ao lado do aparelho, nunca sobre a UI
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
| 0:56 | `TriageScreen` passo 3 | **Apenas entrar no passo 3** — não tocar em nada ainda | `Passo 3 de 3` e, abaixo do botão, **`Risco: Vermelho`** já visível |
| 1:01 | `TriageScreen` passo 3 | Marcar **"Dor no peito ou sangramento"** → "Concluir triagem" | O risco continua vermelho; o toque encerra o beat |
| 1:05 | `StatusScreen` | — | `Triagem Vermelha` + linha do tempo `Enviado → Visualizado → Em análise → Agendado` |

**Nota de captura/edição:** o beat mais importante do vídeo é 0:56–1:05, e o momento exato importa. `Risco: Vermelho` é renderizado sob a condição `if (_step == 2)` (`app.dart:279`) — ou seja, **aparece assim que a tela do passo 3 monta**, antes de marcar a terceira resposta e antes de tocar "Concluir triagem". E tocar "Concluir triagem" chama `onComplete` (`app.dart:273`), que substitui a `TriageScreen` pela `StatusScreen`: **o texto some**. Portanto **congelar o quadro por 1,5 s e aplicar zoom suave na entrada do passo 3**, nunca depois de concluir. A regra que produz esse resultado está em `_risk` (`app.dart:251`) — a resposta "falta de ar" leva a vermelho sempre, independentemente das outras duas respostas, o que torna a demo repetível em qualquer tomada.

**Continuidade:** a `StatusScreen` rotula a solicitação como `Triagem Vermelha` (`app.dart:383`), mantendo o caso da Maria coerente no corte para o bloco 4. Até 2026-09-10 esse rótulo dizia "Triagem Amarela" e contradizia em tela o vermelho do passo anterior; foi corrigido junto com esta revisão do roteiro.

**Tela opcional, se sobrar tempo:** `EmergencyScreen` — botão circular `EMERGÊNCIA` → diálogo de confirmação → o estado muda para **"Alerta enfileirado localmente"**. Só incluir com a locução dizendo "enfileirado", nunca "enviado ao agente" (ver guardrails).

---

## Bloco 4 — Demo do app do ACS · 1:15 – 2:05

> **Locução:**
> Do lado do agente, o mesmo caso reaparece. Ao entrar, ele carrega só a própria microárea: 142 pacientes, em cache local. Nenhum agente enxerga o território de outro — é uma invariante do sistema, não uma configuração. E a fila já vem ordenada. Maria Oliveira no topo, em vermelho. João Pereira, glicemia descompensada, em amarelo. Ana Costa, dúvida de rotina, em verde. A cor aqui nunca é decoração: ela significa gravidade. Terminada a visita, o registro é feito na porta da casa, com ou sem sinal. O agente salva, e o app enfileira localmente para sincronizar sozinho quando a rede voltar. Em zona rural, isso é a diferença entre ter o dado e perder o dia.

**Em tela — sequência exata a gravar** (`apps/acs/lib/app/app.dart`):

| Tempo | Tela | Ação | O que aparece |
|-------|------|------|---------------|
| 1:15 | `TerritorializationScreen` | Após o login, **tocar a aba "Área"** (ver nota de navegação) e apenas exibir — **não tocar no botão** | `Microárea 12 - Zona Rural`; e, em duas linhas de label/valor, `Pacientes sincronizados` → `142 cadastrados` e `Cache local` → `Atualizado há 10 min` |
| 1:26 | `DashboardScreen` | Tocar a aba "Fila", exibir e rolar devagar | Três cards com borda esquerda vermelha / amarela / verde; `Maria Oliveira, 72a` no topo |
| 1:45 | `VisitRegistrationScreen` | Escolher status, digitar uma observação curta, tocar **"Salvar e enfileirar sincronização"** | `SnackBar`: "Visita salva e enfileirada localmente para sincronização." |

**Nota de navegação:** o login do ACS faz `pushReplacement` para o shell cujo destino inicial é `AcsDestination.queue` (`app.dart:55`) — o app **abre direto no `DashboardScreen`**, não na territorialização. Para gravar o bloco na ordem acima é preciso um toque extra na aba **"Área"** logo depois do login. Alternativa igualmente válida: inverter o bloco e começar pela fila, que é a ordem natural do app. Os campos de login vêm pré-preenchidos (`ACS-001` / senha), então o login em si é um toque só.

**Nota sobre os textos em tela:** `Pacientes sincronizados` e `Cache local` são renderizados por `_InfoRow` (`app.dart:107`), que põe o label à esquerda e o valor em negrito à direita, **sem dois-pontos**. Não escrever legenda com `Pacientes sincronizados: 142` — não é o que aparece em quadro.

**Nota de captura/edição:** a cena 1:45 é a **única ação de interface do app ACS que executa lógica de domínio de verdade** — chama `OfflineVisitQueue.add` com um `OfflineVisitRecord`. Filmar o toque e o `SnackBar` em plano contínuo, sem corte, porque é a prova visual de que o offline-first não é slide. Se possível, **ativar o modo avião do aparelho antes desta cena** e deixar o indicador de "sem rede" visível na barra de status: o argumento fica muito mais forte.

**Limite honesto desta cena (ver guardrails):** `OfflineVisitQueue` **não é singleton** (`offline_visit_queue.dart:46`) — `OfflineVisitQueue()` cria uma instância nova, adiciona o registro em memória e a descarta ao fim do callback. Além disso o `outcome` do dropdown e as observações digitadas **não são gravados** no registro (o `risk` é fixo em `'VERMELHO'`). A cena demonstra a lógica da fila; ela **não** demonstra persistência que sobreviva ao app. A legenda pode dizer "o app enfileira localmente"; não pode dizer "o dado fica guardado até a rede voltar".

Para o corte de entrada do bloco, usar transição direta do `Risco: Vermelho` do paciente para o card vermelho do dashboard. Sem transição elaborada — um corte seco vende melhor a continuidade do dado.

---

## Bloco 5 — A prova técnica · 2:05 – 2:25

> **Locução:**
> Isto não é maquete. O ciclo crítico já roda ponta a ponta: o alerta vermelho entra pela API, é gravado em transação, publicado no broker MQTT no tópico da microárea, e volta com confirmação de recebimento. Alerta vermelho não se perde em silêncio. Integração contínua verde nos quatro trilhos.

**Em tela:** plano de terminal em close, fonte grande, cinco momentos encadeados:

1. `docker compose up` com a stack de pé (PostgreSQL, Mosquitto, backend Serverpod, Traefik), e o serviço `database-seed` concluindo.
2. `alerts.createRedAlert(accessToken, idempotencyKey, locationHash)` → `RedAlertResult{alertId, status: pending, published: true}`.
3. Painel lateral: `mosquitto_sub` sobre TLS recebendo a mensagem em `sinalacs/v1/microareas/<uuid>/alerts`. **O dispatcher não imprime log de publicação** — a evidência é o campo `published: true` e a mensagem chegando no tópico, não uma linha de log. O assinante usa o usuário `backend`: o `aclfile` concede leitura a `acs-area-12` num tópico com o literal `area-12`, que não corresponde ao UUID de microárea que o dispatcher publica, então hoje nenhum assinante com escopo de ACS receberia nada. **Este bloco prova publicação e confirmação, não isolamento territorial.**
4. A **mesma** `idempotencyKey` reenviada → **mesmo `alertId`**, sem alerta duplicado. Seguido de `alerts.acknowledge(...)` → `acknowledged: true, status: acknowledged`.
5. Corte rápido para os quatro jobs verdes do GitHub Actions (`.github/workflows/ci.yml`).

**Nota de arquitetura — leia antes de gravar:** o backend **não é REST**. Versões anteriores deste roteiro mandavam gravar `POST /v1/alerts/red` com cabeçalho `Idempotency-Key` respondendo `201`, e `POST /v1/alerts/{id}/ack`. Esses endpoints **não existem mais**: o servidor `dart:io` foi substituído por Serverpod (RPC) e o próprio `alerts_endpoint.dart` documenta as três consequências — a chave de idempotência virou **parâmetro do método** (não header), o mapeamento de exceção para status (`400`/`403`/`503`) virou **exceção tipada** serializada até o cliente, e o `404` do ACK sem correspondência virou o campo **`acknowledged: false`**. Não há URL para filmar; o que se filma é a chamada de método e o resultado tipado.

**Nota de captura/edição:** este bloco **não sai dos apps** — hoje os apps Flutter ainda não chamam o backend, e o ciclo real vive no servidor. Gravar do terminal é o caminho honesto e, para uma banca técnica, mais convincente. O roteiro de execução é um pequeno script Dart que consome o cliente gerado `sinalacs_client`. Pré-requisitos: **`ENABLE_DEV_LOGIN=true`** (já configurado em `docker-compose.yml`; sem ele `auth.developmentLogin` lança `EndpointDisabledException`) e o seed aplicado pelo serviço `database-seed` (senão `createRedAlert` falha por chave estrangeira em `alerts.patientId`). Verificado rodando em 2026-09-10: `published: true`, mesma chave devolvendo o mesmo `alertId`, e `acknowledged: true`. Ampliar a fonte do terminal antes de gravar e destacar em amarelo, na edição, apenas `published: true`, o `alertId` repetido e a linha de ACK. Este é o ciclo que a métrica North Star (TMRAV, **alvo** < 90 s) vai medir no piloto — não citar número de latência medido, porque ainda não existe medição em campo.

**Privacidade em quadro:** o script imprime um token de acesso — ele deve aparecer **truncado**. Antes de gravar, fechar qualquer painel, aba ou editor com `config/passwords.yaml`, `JWT_SECRET`, `.env` ou string de conexão.

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
| `MapScreen` | "Traçar rota eficiente" | "Traçado de rota depende da integração de mapas." — e a própria tela imprime **"Mapa demonstrativo"** |
| `EscalationScreen` | "Ligar para o SAMU (192)" | "Discagem não está integrada neste protótipo." |
| `EscalationScreen` | "Encaminhar para UBS Central" | "Encaminhamento será integrado à UBS." |
| `GeofencingScreen` | "Abrir formulário da visita" | "Use a tela Visita para registrar o atendimento." |
| `NoticesScreen` | "Preparar aviso" | "Envio depende da integração de notificações push." |
| `TerritorializationScreen` | "Atualizar dados da microárea" | "Atualização será integrada à API central." — a tela pode aparecer, o botão não pode ser tocado |
| `DashboardScreen` | Card verde (Ana Costa), "Ver dúvida / responder" | "Canal de dúvidas demonstrativo." — o card pode aparecer na fila, o botão não pode ser tocado |
| `DashboardScreen` | Card amarelo (João Pereira), "Iniciar rota de visita" | Não emite `SnackBar`, mas **abre o formulário com o nome da Maria no topo**: `AcsDestination.visit` monta sempre `VisitRegistrationScreen(patientName: 'Maria Oliveira')` (`app.dart:63`, `:90`). Filmar isso mostra dois pacientes trocados em quadro |
| `PatientLoginScreen` (app paciente) | "Escanear QR Code do ACS" | "Leitura de QR Code será disponibilizada com o onboarding integrado." — fica logo abaixo de "Entrar sem senha" (`app.dart:86`); cuidado ao mirar o toque |

Todas as mensagens acima terminam com **ponto final** em tela — considerar isso ao escrever legendas ou asserções de teste.

### Não afirmar na locução

- **Que o alerta do paciente chega ao aparelho do ACS.** Hoje o app do paciente apenas muda um estado local. A formulação correta é "o alerta é registrado e enfileirado"; o ciclo real de entrega é mostrado no bloco 5, no backend.
- **"Mapa ao vivo", "geofencing ativo", "SAMU integrado", "push disparado".** Os quatro são stubs. Se mapa e geofencing precisarem aparecer, entram como **roadmap v1.5**, com selo em tela, nunca como capacidade atual.
- **Números de resultado como se fossem medidos.** Redução ≥ 40 % no tempo até a visita, ≥ 90 % de concordância com a avaliação médica, > 99,5 % de sincronização e TMRAV < 90 s são **hipóteses e alvos do MVP**. A locução deve dizer "é o que o piloto vai medir" e o texto em tela deve trazer a palavra **"alvo"**.

### Privacidade

Somente dados sintéticos — que é o que os apps já usam. Nenhuma tela com dado real de paciente, e nenhum arquivo `.env`, credencial, token ou string de conexão visível em quadro durante a gravação do terminal no bloco 5.

---

## Preparação antes de gravar

1. **Card do dashboard do ACS.** `apps/acs/lib/app/app.dart` passava `'Maria Souza'` como segundo nome, sem rótulo, no card de Maria Oliveira — em tela liam-se dois nomes diferentes no mesmo paciente, justamente no plano mais importante do vídeo. **Verificado em 2026-09-10: corrigido na UI**; o nome só sobrevive como fixture de teste em `apps/acs/test/login_flow_test.dart:36`, que não aparece em tela. Pode filmar.
2. **Captura do login do ACS.** `docs/screenshots/acs/01-login.png` e `docs/screenshots/patient/01-emergencia.png` são byte-idênticos (md5 `2d6f1cef705bb806fd7cff4672a558fc`), e o conteúdo real das duas é a **tela de alerta de urgência do paciente** ("SINALACS PACIENTE / Alerta de urgência"). Ou seja, `patient/01-emergencia.png` está correto e é `acs/01-login.png` que guarda a imagem errada — não existe captura do login institucional do ACS. A tela **existe em código** (`apps/acs/lib/app/app.dart:16-49`: "Matrícula / CNS", "Senha de acesso", "Entrar com credenciais"); falta só a captura. Recapturar com `adb exec-out screencap -p` e conferir `docs/telas-acs.md`, que descreve essa imagem como a tela de entrada com matrícula e senha.
3. **Banco preparado para o bloco 5.** Não há mais passo manual de `psql`: `SERVERPOD_APPLY_MIGRATIONS` aplica as migrações no boot e o serviço `database-seed` do `docker-compose.yml` aplica `seeds/development.sql` depois que o servidor fica saudável (ver `CLAUDE.md`). O que **é** preciso garantir: que `database-seed` tenha concluído — sem o seed, `alerts.createRedAlert` falha por violação de chave estrangeira em `alerts.patientId` e o bloco técnico não grava.
4. **`ENABLE_DEV_LOGIN=true`** no ambiente do serviço `serverpod`. O padrão é `false`, e com ele `auth.developmentLogin` lança `EndpointDisabledException` — o script do bloco 5 não consegue nem obter o token.
5. **Aparelho preparado.** `adb` não está no `PATH` (fica em `~/Android/Sdk/platform-tools/`). Forçar o alvo do roteiro com `adb shell wm size 1080x2400` e `adb shell wm density 420`, e restaurar com `wm size reset` / `wm density reset` ao terminar. O modo demo da barra de status (`settings put global sysui_demo_allowed 1`) fixa relógio e bateria e esconde notificações — menos ruído em quadro.

---

## Checklist de verificação do roteiro

- [ ] Contagem de palavras da locução entre 400 e 420 (atual: **419**, medido bloco a bloco).
- [ ] Leitura em voz alta cronometrada; cada bloco fecha no seu timecode com ±3 s.
- [ ] Percurso das telas conferido nos dois apps (`flutter run`), sem acionar nenhum controle da tabela de "não filmar".
- [ ] Ciclo `alerts.createRedAlert` → `alerts.acknowledge` devolvendo `published: true` e `acknowledged: true` antes de gravar o terminal, com a reexecução idempotente devolvendo o mesmo `alertId`.
- [ ] Revisão de honestidade: nenhum verbo no presente descrevendo capacidade que hoje é stub; nenhum número de meta sem a palavra "alvo" ou "hipótese".
- [ ] Revisão de privacidade quadro a quadro do bloco 5: nenhum token inteiro, credencial, `.env` ou string de conexão em quadro.

> **Nota de adaptação para a versão sem locução.** Se o vídeo for entregue com legendas em vez de voz, as 419 palavras **não** podem ir para a tela como estão: nos blocos 3 e 4 o espectador precisa olhar a UI do celular e não consegue ler 212 palavras ao mesmo tempo. Condensar esses blocos para cerca de metade, preservando os argumentos inegociáveis ("a classificação sai pronta", "não existe campo para editar", "é uma invariante, não uma configuração", "a cor significa gravidade", "com ou sem sinal"). Os blocos de cartela (1, 2, 6 e 7) não competem com UI e podem manter o texto quase integral. Regra de legenda: no máximo 2 linhas, ~42 caracteres por linha, mínimo 2,5 s em tela.

## Referências

- [Telas do app ACS](telas-acs.md) · [Telas do app paciente](telas-paciente.md)
- [PRD do sistema](../spec/PRD_system.md) — hipóteses H1–H4, invariantes INV-01–05, métricas e milestones
- [Estado dos milestones](../PROGRESS.md)
- Protótipos visuais de referência: [`spec/ui_acs/`](../spec/ui_acs) e [`spec/ui_paciente/`](../spec/ui_paciente)
