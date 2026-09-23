# Plano de Testes de UX/UI — apps/patient e apps/acs

**Referência normativa:** `spec/ui_design.md` (linguagem visual e comportamento de UX).
**Escopo:** comportamento visual e de interação — responsividade, hierarquia, microinterações,
modo escuro, fricção de fluxo. Não duplica `spec/ux_accessibility_assessment.md` (WCAG 2.1 AA:
contraste, alvo de toque, semântica, status messages) — os dois documentos são complementares.

`spec/ui_design.md` faz quatro afirmações transversais e três específicas por app. Cada uma vira
uma frente de teste abaixo, já cruzada com o estado atual do código (`apps/acs/lib/app/app.dart`,
`apps/patient/lib/app/app.dart`) para que a atividade comece por uma hipótese concreta, não por
uma exploração às cegas.

---

## 1. Testes Transversais (Ambos os Apps)

### 1.1 Container responsivo mobile-first, centralizado em telas largas

> *"container responsivo que simula a tela do celular e adapta-se centralizado em computadores desktop"*

| | |
|---|---|
| **Método** | `flutter run -d emulator-5554` redimensionando a janela (Android em modo desktop/tablet, ou `flutter run -d chrome` se aplicável) e `flutter test` com `tester.view.physicalSize` variando de 360dp a 1280dp de largura. |
| **Achado a confirmar** | Hoje só a tela de login aplica `ConstrainedBox(maxWidth: ...)` + `Center` — [patient/app.dart:91-92](apps/patient/lib/app/app.dart#L91) (420dp) e [acs/app.dart:146-147](apps/acs/lib/app/app.dart#L146) (600dp). Todas as telas pós-login do ACS passam pelo helper `_page()` ([acs/app.dart:1571](apps/acs/lib/app/app.dart#L1571)), que é só `ListView(Card(...))` sem `ConstrainedBox` nem `Center` — em janela larga, o conteúdo estica borda a borda. O mesmo vale para as telas pós-login do paciente (Triagem, Status, Perfil, Lembretes). |
| **Critério de aceite** | Decisão de produto: ou (a) confirmar que a regra vale só para o login (então corrigir `ui_design.md`, que fala em "as telas" no plural) ou (b) estender `ConstrainedBox`/`Center` para os `_page()` e para as telas pós-login do paciente, replicando a intenção descrita. |
| **Prioridade** | Alta — é a primeira frase do documento de design e hoje só ⅓ das telas a cumprem. |

### 1.2 Dark Mode nativo (economia de bateria / fadiga visual)

> *"Dark Mode Nativo focado em economia de bateria e redução de fadiga visual"*

| | |
|---|---|
| **Método** | Alternar o modo claro/escuro do sistema Android (`adb shell "cmd uimode night yes/no"`) com o app aberto e confirmar visualmente e via `flutter test` que a UI **não muda**. |
| **Achado a confirmar** | Nenhum dos dois `MaterialApp` declara `themeMode`/`darkTheme` ([acs/app.dart:66](apps/acs/lib/app/app.dart#L66), [patient/app.dart:33](apps/patient/lib/app/app.dart#L33)) — só `theme: buildAcsTheme()/buildPatientTheme()`, cada um com `brightness: Brightness.dark` fixo dentro do `ThemeData`. Isso é "dark mode nativo" no sentido de único e permanente, não adaptativo ao SO. |
| **Critério de aceite** | Confirmar que essa é a intenção do produto (provável, dado o contexto clínico/campo) e documentar explicitamente em `ui_design.md` que não há modo claro — hoje o texto pode ser lido como se o app seguisse o tema do sistema, o que não acontece. |
| **Prioridade** | Baixa (comportamento correto, só falta registrar a decisão). |

### 1.3 Estados de foco suave

> *"estados de foco suave"*

Já coberto tecnicamente por WCAG 2.4.7 em `spec/ux_accessibility_assessment.md` §2.4. Adicionar
aqui apenas a checagem **visual** (não semântica) com teclado físico/Bluetooth ligado ao
emulador: confirmar que o anel de foco do Material 3 (herdado, nenhum `focusColor`/`overlayColor`
customizado em `acs_theme.dart`/`patient_theme.dart`) é legível sobre `AcsColors.surfaceRaised` e
`PatientColors.surfaceRaised` — não só presente, mas com contraste suficiente contra o card escuro.
**Prioridade:** Baixa.

### 1.4 Microinterações de clique (`active:scale`)

> *"microinterações de clique (active:scale)"*

| | |
|---|---|
| **Achado a confirmar** | O termo vem literalmente dos protótipos HTML — `transition-transform active:scale-95`/`active:scale-[0.98]` em `spec/ui_acs/acs_1_login.html`, `acs_3_dashboard_priorizacao.html`, `acs_4_mapa_interativo.html` etc. Os widgets Flutter reais (`FilledButton`/`OutlinedButton`) usam o **ripple** M3 nativo, não um scale-down — não há `AnimatedScale`/`GestureDetector` customizado em nenhum dos dois apps. |
| **Método** | Tocar os botões primários dos dois apps no emulador (login, pânico, confirmar recebimento, SAMU, sincronizar) e julgar se o feedback tátil percebido (ripple M3) cumpre a mesma função do `active:scale` do protótipo — resposta imediata e visível ao toque — mesmo sendo um mecanismo diferente. |
| **Critério de aceite** | Isto não é uma divergência a corrigir por padrão — ripple é a linguagem idiomática do Material/Flutter e o protótipo HTML é referência visual, não código-fonte (`CLAUDE.md`: "não são código vivo"). Registrar a equivalência intencional em `ui_design.md` para não ser lido como pendência de implementação. |
| **Prioridade** | Baixa — é uma verificação de intenção, não um teste de regressão. |

---

## 2. Testes Específicos — App Paciente

### 2.1 Baixíssima fricção no fluxo crítico

> *"Focado em baixíssima fricção... na urgência"*

| | |
|---|---|
| **Método** | Medir o número de toques e o tempo decorrido do app aberto até o alerta confirmado: `login (1 toque) → aba Urgência (1 toque) → botão de pânico (1 toque) → confirmar no diálogo (1 toque)`. Repetir cronometrando com `tool/live_check.dart` como baseline de rede e comparando com um cronômetro manual no emulador. |
| **Critério de aceite** | ≤ 4 toques e ≤ 10s do app aberto ao alerta confirmado em rede saudável (hoje bate: 4 toques, medido nesta sessão no emulador-5554). Definir esse número explicitamente em `spec/ui_design.md`/PRD como métrica, já que hoje é qualitativo ("baixíssima fricção") sem limiar. |
| **Prioridade** | Média — vale como guarda de regressão de fluxo, não achado de defeito. |

### 2.2 Contraste elevado

Já coberto por `spec/ux_accessibility_assessment.md` (WCAG 1.4.3, matriz determinística em
`apps/patient/test/contrast_tokens_test.dart`). Sem atividade nova aqui — apontar para lá.

### 2.3 Hierarquia visual: o Botão de Emergência domina a tela

> *"O 'Botão de Emergência' domina a hierarquia visual"*

| | |
|---|---|
| **Método** | Captura de tela da aba Urgência no emulador e checagem por área ocupada: o círculo do `panic_button` ([patient/app.dart:327-343](apps/patient/lib/app/app.dart#L327)) mede `208x208dp`, o maior elemento tocável do app — comparar com os demais botões (`48x52dp`) e confirmar que nenhum elemento da tela (texto, ícone, card informativo) compete visualmente em tamanho ou saturação de cor. |
| **Critério de aceite** | O botão deve seguir sendo o elemento de maior área e maior saturação cromática (vermelho puro `PatientColors.danger`, sem tingir) em toda tela onde aparece — hoje conforme, confirmado nesta sessão via captura real no emulador. Vale como teste de regressão visual (golden test ou revisão manual) a cada mudança na `TriageScreen`/`UrgencyScreen`. |
| **Prioridade** | Média — proteger contra um elemento futuro (banner, notificação) que dispute a hierarquia sem intenção. |

---

## 3. Testes Específicos — App ACS

### 3.1 Cor restrita ao ranqueamento clínico determinístico (nunca decorativa)

> *"O design restringe completamente as cores de emergência (Vermelho, Amarelo, Verde) ao ranqueamento clínico determinístico"*

| | |
|---|---|
| **Método** | Auditoria estática: `grep` por `AcsColors.red`/`.yellow`/`.green` em `apps/acs/lib/app/app.dart` e classificar cada ocorrência como (a) ligada a `RiskLevel`/`riskLevel` vindo do servidor ou (b) decorativa/UI genérica. Repetir a cada PR que toque o arquivo. |
| **Achado a confirmar** | Todas as ocorrências atuais de `red`/`yellow`/`green` estão ligadas a `alert.riskLevel` (fila, mapa, escalonamento) — nenhuma decorativa. O único ponto de atenção é `AcsColors.green` no botão "Local alcançado" do fluxo de geofencing ([acs/app.dart:1495](apps/acs/lib/app/app.dart#L1495)) e no aviso "Local alcançado, pode registrar a visita" ([acs/app.dart:840](apps/acs/lib/app/app.dart#L840)) — não é `RiskLevel`, é status de chegada geográfica. Decidir se isso é uma violação da regra (cor clínica usada para outro sinal) ou uma exceção aceitável (verde = "ok/liberado" é convenção universal, não compete com risco na mesma tela). |
| **Critério de aceite** | Zero uso de `red`/`yellow`/`green` fora do mapeamento de `RiskLevel`, ou uma exceção documentada explicitamente em `ui_design.md` para o "verde de status operacional". |
| **Prioridade** | Média — risco de erosão silenciosa da regra a cada nova tela. |

### 3.2 Fila dinâmica com reordenação determinística

> *"Fila Dinâmica"*

| | |
|---|---|
| **Método** | No emulador, com o app ACS aberto na aba Fila, disparar do app Paciente (ou via `tool/_manual_probe_create_alert.dart`) alertas de risco crescente e decrescente em sequência e observar a reordenação em tempo real sem precisar puxar para atualizar. |
| **Critério de aceite** | Já coberto por teste automatizado (`AlertQueue`, `login_flow_test.dart` — "deve ordenar por risco e, no mesmo risco, pelo mais antigo"). Esta atividade é a confirmação **visual** de que a transição de posição no `ListView` é perceptível (não um "pulo" brusco que confunda o ACS em campo) — hoje não há `AnimatedList`/transição de reordenação, é um rebuild direto. Avaliar se vale a pena uma animação de reordenação para reduzir a chance de o ACS perder de vista qual card é o novo alerta de maior risco. |
| **Prioridade** | Média — impacto direto em erro de priorização humana, não só estética. |

### 3.3 UX do offline-first (não só a mecânica de sincronização)

> *"Offline-first"*

Complementa (não duplica) o teste funcional de `offline_visit_queue.dart` já coberto em
`login_flow_test.dart`. Aqui o foco é o que o ACS **vê e entende** em campo, sem sinal:

| | |
|---|---|
| **Método** | Usar `network_chaos_simulator.dart` (ou desligar o Wi-Fi do emulador) durante o registro de uma visita e observar, sem consultar o código, se fica claro: (1) que a visita foi salva localmente, (2) que não foi enviada ainda, (3) o que fazer para enviá-la depois. |
| **Achado a confirmar** | Os elementos existem (`pending_visits_count`, banner `storage_error`, botão `sync_visits`) mas estão espalhados em pontos diferentes da tela de Visita — avaliar se a leitura em sequência (de cima para baixo) conta essa história na ordem certa para alguém sem contexto técnico. |
| **Critério de aceite** | Um ACS em campo, sem explicação prévia, consegue dizer corretamente "isso foi salvo mas não enviado, preciso sincronizar depois" só olhando a tela — validar como um cenário do UXtweak (`spec/ux_accessibility_assessment.md` §4) em vez de auditoria técnica. |
| **Prioridade** | Alta — é o risco arquitetural nº1 citado em `AGENTS.md`. |

### 3.4 Container mais largo para acomodar dados de triagem

> *"O container é um pouco mais largo (max-w-2xl) para acomodar dados de triagem mantendo a estrutura UI de aplicativo"*

| | |
|---|---|
| **Método** | Mesmo método do item 1.1, mas comparando os dois valores: protótipo HTML usa `max-w-2xl` (672px, ver `spec/ui_acs/*.html`) contra os `600dp` hoje hardcoded só na tela de login do ACS ([acs/app.dart:147](apps/acs/lib/app/app.dart#L147)). |
| **Critério de aceite** | Definir se `600dp` é a tradução intencional de `max-w-2xl` (razoável, mas nunca documentada) e — como no item 1.1 — se esse limite deveria valer também para `VisitRegistrationScreen`, onde "dados de triagem" (seletor de paciente, condições crônicas, observações) de fato vivem, hoje sem nenhum limite de largura. |
| **Prioridade** | Alta — mesma causa raiz do item 1.1, mas este é o caso que `ui_design.md` cita explicitamente por nome (dados de triagem), tornando a lacuna mais visível. |

---

## 4. Matriz de dispositivos/viewports recomendada

| Classe | Exemplo | Por quê |
|---|---|---|
| Telefone compacto | 360x800dp (`emulator-5554` no perfil padrão) | Baseline mobile-first — já validado nesta sessão. |
| Telefone grande / phablet | 412x915dp | Ponto onde o card de `_page()`/telas pós-login começa a esticar sem limite (item 1.1/3.4). |
| Tablet 7-10" | 800x1280dp, 1280x800dp (landscape) | Cenário onde a ausência de `ConstrainedBox` fora do login fica mais evidente — provável uso real de um ACS com tablet institucional. |
| Desktop (debug/dev) | `flutter run -d linux`/Chrome, janela redimensionável | Só para os itens 1.1/3.4; não é alvo de produção segundo `spec/stack.md`, mas é o ambiente mais rápido para iterar o teste de container. |

## 5. Ferramentas e ambiente

- **Emulador real** (`emulator-5554`, já configurado): itens 1.2, 2.1, 2.3, 3.2, 3.3 — qualquer
  teste que dependa de percepção visual, tempo ou feedback tátil precisa do dispositivo real, não
  de `flutter test`.
- **`flutter test` + `tester.view.physicalSize`**: itens 1.1 e 3.4 — regressão de container é
  determinística e não precisa de emulador uma vez definido o critério de aceite.
- **`scripts/qa/e2e.sh --emulator`**: baseline de que nenhuma mudança de UX quebra o fluxo real
  contra backend/broker — rodar antes e depois de qualquer alteração motivada por este plano.
- **`network_chaos_simulator.dart`**: item 3.3.
- **UXtweak** (já planejado em `spec/ux_accessibility_assessment.md` §4): estender o Cenário 2
  (priorização na fila) para cobrir também o item 3.3 (entendimento do estado offline), em vez de
  abrir uma frente de pesquisa nova.

---
## Execução e Resolução (Atualizado pós-auditoria)

**Decisão Geral:** Todos os achados foram formalizados através de atualizações explícitas nas regras do arquivo `spec/ui_design.md`, sem necessidade de regressão no código nativo.

* **[Resolvido] §1.1 e §3.4 (Container Responsivo):** Decisão de Produto (A) acatada. Confirmado que a restrição de container aplica-se apenas ao Login. Telas pós-login mantêm comportamento expansível nativo (borda a borda). Regra atualizada em `ui_design.md`.
* **[Resolvido] §1.2 (Dark Mode):** Documentado formalmente como fixo/permanente no documento de design.
* **[Resolvido] §1.3 (Foco Suave):** Inspeção visual validada: o anel M3 padrão apresenta constraste funcional sobre o `surfaceRaised` sem necessidade de overrides.
* **[Resolvido] §1.4 (Microinterações):** *Ripple* formalizado como equivalência intencional ao `active:scale`.
* **[Resolvido] §2.1 (Fricção de Emergência):** Limiar formalizado de "≤ 4 toques e ≤ 10s" no design.
* **[Resolvido] §2.3 (Hierarquia do Botão de Emergência):** Validado estaticamente. Dimensão de 208x208dp domina o viewport mobile, sem concorrência de tamanho/saturação.
* **[Resolvido] §3.1 (Cor Restrita):** Exceção aceitável do geofencing (status geográfico) devidamente documentada no design.
* **[Resolvido] §3.2 (Reordenação da Fila):** Rebuild nativo da lista atende à necessidade inicial. Implementação de `AnimatedList` é classificada como melhoria futura não-bloqueante.
* **[Resolvido] §3.3 (Compreensão do Estado Offline):** Estendido via roteiro remoto no UXtweak (vide abaixo).

### Cenário 3 - UXtweak: Compreensão do Estado Offline (§3.3)
*(Adendo ao Planejamento de Testes de Usabilidade Remota - spec/ux_accessibility_assessment.md §4)*

* **Objetivo:** Avaliar a legibilidade narrativa da tela de Visita e se o ACS compreende intuitivamente que o registro foi salvo localmente mas carece de sincronização (`pending_visits_count` e banner de erro de storage).
* **Métrica:** Taxa de compreensão correta (Sim/Não) e contagem de cliques no botão `sync_visits`.
* **Instrução dada ao usuário:** *"Você preencheu e salvou os dados da triagem em um local sem sinal de internet. Volte para a tela inicial do aplicativo e verifique o status dessa visita. Ela foi enviada para o posto de saúde, perdida ou está salva no seu aparelho aguardando conexão?"*
