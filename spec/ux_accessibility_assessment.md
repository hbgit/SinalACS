# Relatório de Avaliação de UI/UX e Acessibilidade

**Aplicativos Avaliados:** `apps/patient`, `apps/acs` e `apps/admin`
**Referência Baseline:** PRD de Sistemas (Seção 4.3 — WCAG 2.1 Nível AA), `spec/ui_design.md`
**Metodologia e Ferramentas:** Matriz de contraste determinística (`apps/*/test/contrast_tokens_test.dart`,
implementando a fórmula de luminância relativa WCAG 1.4.3 contra a superfície REAL de
renderização de cada token — ver §2.1), matchers nativos do Flutter no CI
(`meetsGuideline(textContrastGuideline/androidTapTargetGuideline/labeledTapTargetGuideline)`
em `login_flow_test.dart` e `patient_app_mvp_test.dart`), Auditoria Estática de Código (Dart
AST/grep), Validação em dispositivo real (`apps/acs/integration_test/`, incluindo o teste que lê o
arquivo do banco criptografado) e Verificação Prática no emulador Android (`emulator-5554`) contra
o backend e o broker reais, cobrindo os dois apps em conjunto (paciente envia alerta → ACS recebe
pelo MQTT/TLS real).

> **Nota de revisão:** a versão anterior deste relatório mediu contraste manualmente no WebAIM
> Contrast Checker contra o fundo do `Scaffold`, mas texto de risco e de status é renderizado
> dentro de `Card`/`AppBar`, com uma cor de superfície diferente. Isso produziu um falso positivo
> (§3, achado A) e deixou passar duas falhas piores (§3, achados B e C). Esta revisão substitui a
> medição manual por um teste determinístico que roda no CI — ver `apps/acs/test/contrast_tokens_test.dart`
> e `apps/patient/test/contrast_tokens_test.dart`.

---

## 1. Comparativo com a Baseline WCAG 2.1 AA (Seção 4.3 do PRD)

| Critério WCAG 2.1 | Descrição do Critério | Requisito do PRD / Issue | Status | Resumo do Diagnóstico |
| :--- | :--- | :--- | :---: | :--- |
| **1.4.1 Color Use** | A cor não deve ser o único indicador visual de estado/risco | Duplo canal (Texto/Ícone + Cor) em sinais clínicos de risco | **Conforme** | Rótulos explícitos `'Risco: Vermelho'`, `'Risco: Amarelo'`, `'Risco: Verde'` acompanhados de ícone, nos dois apps. |
| **1.4.3 Contrast (Minimum)** | Razão de contraste min. de 4.5:1 (texto normal) e 3:1 (texto grande/UI) | ≥ 4.5:1 para texto sobre fundo escuro nos temas | **Conforme (corrigido)** | Cinco pares de token/superfície falhavam quando medidos corretamente (§2.1); corrigidos separando token de PREENCHIMENTO de token de TEXTO (`redOnSurface`/`accentOnSurface` no ACS, `dangerOnSurface`/`accentOnSurface` no paciente, `redOnSurface`/`accentOnSurface` no admin). Guardado por teste determinístico. |
| **2.4.7 Focus Visible** | Indicador claro de foco visual ao navegar por campos interativos | Foco visível em todos os elementos selecionáveis | **Conforme** | Indicador de foco nativo do Android acompanha todos os alvos tocáveis, sem truncamento. |
| **2.5.5 Target Size** | Alvo de toque adequado para interatividade | ≥ 48x48 dp (padrão), ≥ 60x60 dp (botão de emergência/pânico) | **Conforme (corrigido)** | Botão de pânico do paciente: `208x208 dp`. "Ligar para o SAMU (192)" no ACS não tinha `minimumSize` (default M3 de 40dp de altura visual) — corrigido para `64x60 dp`. Quatro outros botões de ação primária no ACS também não tinham `minimumSize` explícito; padronizados em `48x52 dp`. |
| **4.1.2 Name, Role, Value** | Árvore semântica exposta para leitores de tela nativos | Rótulos e papeis em 100% dos fluxos críticos | **Conforme** | Árvore semântica nativa do Flutter expõe abas (**Área, Fila, Mapa, Visita, Mais**) e formulários com clareza; o cartão de alerta da fila passou a ser lido como uma frase única (§3, achado antigo de prioridade Baixa). |
| **4.1.3 Status Messages** | Uma mudança de status deve ser anunciada por tecnologia assistiva sem exigir foco | (ausente da avaliação anterior) | **Conforme (corrigido)** | Critério não coberto pelo relatório original. Sete pontos de status dinâmico (erro de login nos dois apps, confirmação de alerta de emergência, banners de falha de broker/armazenamento, erro do diretório de pacientes, contador de visitas recusadas) não eram anunciados; corrigidos com `Semantics(liveRegion: true)`. |

---

## 2. Evidências Técnicas e Achados por Critério

### 2.1 Contraste e Uso de Cor (WCAG 1.4.3 e 1.4.1)

Cada app declara cores de PREENCHIMENTO (fundo de botão, badge) que também eram reaproveitadas
como cor de TEXTO/ícone sobre `Card`. Um preenchimento e um texto têm requisitos diferentes — um
botão vermelho com texto branco por cima só precisa de 3:1 (texto grande/UI), mas o mesmo
vermelho usado como cor de um `Text` precisa de 4.5:1. A tabela abaixo mede cada par contra a
superfície onde ele é **de fato** renderizado, com composição de alfa quando aplicável
(`Colors.white54` etc.):

#### Tabela de Razão de Contraste Renderizado

| App | Token | Papel | Superfície real | Razão (WCAG) | Exigência | Status |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: |
| Ambos | Branco `#FFFFFF` | texto | Scaffold `#030712` | 20.13:1 | 4.5:1 | Conforme |
| Ambos | Branco `#FFFFFF` | texto | Card (`#1F2937`/`#1E293B`) | 14.68:1 / 14.63:1 | 4.5:1 | Conforme |
| ACS | `AcsColors.yellow #F59E0B` | texto | Card `#1F2937` | 6.83:1 | 4.5:1 | Conforme |
| ACS | `AcsColors.green #10B981` | texto | Card `#1F2937` | 5.79:1 | 4.5:1 | Conforme |
| ACS | `AcsColors.red #DC2626` | **texto** | Card `#1F2937` | **3.04:1** | 4.5:1 | **Falha** (achado B) |
| ACS | `AcsColors.accent #2563EB` | **texto** | Card `#1F2937` | **2.84:1** | 4.5:1 | **Falha** (achado C, não detectado antes) |
| ACS | branco | texto do botão | fill `AcsColors.red` | 4.83:1 | 3:1 (UI) | Conforme — fill não muda |
| Admin | `AdminColors.yellow #F59E0B` | texto | Card `#1F2937` | 6.83:1 | 4.5:1 | Conforme |
| Admin | `AdminColors.green #10B981` | texto | Card `#1F2937` | 5.79:1 | 4.5:1 | Conforme |
| Admin | `AdminColors.red #DC2626` | **texto** | Card `#1F2937` | **3.04:1** | 4.5:1 | **Falha** (mesmo achado do ACS — `red` é idêntico nos dois apps) |
| Admin | `AdminColors.accent #4F46E5` | **texto** | Card `#1F2937` | **2.33:1** | 4.5:1 | **Falha** |
| Admin | `AdminColors.accent #4F46E5` | **ícone** | Card `#1F2937` | **2.33:1** | 3:1 (1.4.11) | **Falha** (ícone do banner "Ambiente de desenvolvimento") |
| Admin | `AdminColors.accent #4F46E5` | **texto** | AppBar `#111827` | **2.82:1** | 4.5:1 | **Falha** (eyebrow do cabeçalho) |
| Admin | branco | texto do botão | fill `AdminColors.red` | 4.83:1 | 3:1 (UI) | Conforme — fill não muda |
| Paciente | `Colors.white54` | texto | Card `#1E293B` | **5.36:1** | 4.5:1 | **Conforme** — achado A do relatório anterior era falso positivo (media 3.2:1 contra o Scaffold) |
| Paciente | amarelo `#E0A800` | texto | Card `#1E293B` | 6.81:1 | 4.5:1 | Conforme |
| Paciente | `PatientColors.accent #0D9488` | **texto** | Card `#1E293B` | **3.91:1** | 4.5:1 | **Falha** (achado D, relatado antes como conforme por medir no Scaffold) |
| Paciente | `PatientColors.danger #DC2626` | **texto** | Card `#1E293B` | **3.03:1** | 4.5:1 | **Falha** |
| Paciente | `PatientColors.danger #DC2626` | **texto** | Scaffold `#030712` | **4.17:1** | 4.5:1 | **Falha** — este é o par que o relatório original mediu (4.16:1) e classificou "Média"; a correção sugerida (`#EF4444`) foi avaliada e descartada (linha abaixo) |
| Paciente | branco | texto do botão | fill `PatientColors.danger` | 4.83:1 | 3:1 (UI) | Conforme — fill não muda |
| — | `#EF4444` (correção sugerida pelo relatório anterior) | texto | Card `#1F2937` | **3.90:1** | 4.5:1 | **Ainda falha** — não adotada |

Reprodução: `flutter test test/contrast_tokens_test.dart` em cada um dos três apps.

#### Correção aplicada: separar token de preenchimento de token de texto

Clarear o token único (a sugestão original, `#EF4444`) resolvia a leitura sobre o `Scaffold` mas
continuava falhando sobre `Card` (3.90:1) — não bastava. A correção adotada foi acrescentar uma
variante de TEXTO a cada token de preenchimento que falhava como texto, mantendo o preenchimento
original intacto (ele já cumpre 3:1 com texto branco por cima):

| App | Novo token | Valor | Sobre `surfaceRaised` | Substitui, como texto |
| :--- | :--- | :--- | :---: | :--- |
| ACS | `AcsColors.redOnSurface` | `#F87171` | 5.31:1 | `AcsColors.red` |
| ACS | `AcsColors.accentOnSurface` | `#60A5FA` | 5.77:1 | `AcsColors.accent` |
| Admin | `AdminColors.redOnSurface` | `#F87171` | 5.31:1 | `AdminColors.red` |
| Admin | `AdminColors.accentOnSurface` | `#818CF8` | 4.92:1 | `AdminColors.accent` |
| Paciente | `PatientColors.dangerOnSurface` | `#F87171` | 5.29:1 | `PatientColors.danger` |
| Paciente | `PatientColors.accentOnSurface` | `#2DD4BF` | 7.86:1 | `PatientColors.accent` |

O admin não reaproveita o `#60A5FA` do ACS para `accentOnSurface`: o accent do backoffice é
indigo `#4F46E5`, não o azul `#2563EB` do ACS — copiar o valor literal passaria no contraste
(4.5:1+) mas trocaria o matiz, deixando indigo e azul lado a lado no mesmo banner, onde
`AdminColors.accent` continua como borda. `#818CF8` é o passo -400 da mesma cor do fill -600,
a mesma relação usada pelos outros dois apps.

`AcsColors.red`/`AcsColors.accent`, `PatientColors.danger`/`PatientColors.accent` e
`AdminColors.red`/`AdminColors.accent` continuam sendo a cor de PREENCHIMENTO do botão de
pânico, do botão "Ligar para o SAMU", do botão "Confirmar recebimento" e da faixa lateral de
risco do admin — nenhum desses mudou de cor. Um helper único (`acsOnSurface()` no ACS,
`adminOnSurface()` no admin) converte a cor de preenchimento na variante de texto no ponto em
que um `switch` de risco alimenta tanto um `backgroundColor`/borda quanto um `TextStyle`, para
nunca haver dois pontos de verdade sobre qual vermelho usar onde.

#### Validação de Duplo Canal (WCAG 1.4.1)

`_TriageResult` (paciente) e `_AlertCard`/`_riskLabelPt` (ACS) usam rótulos de texto explícitos
concatenados ao sinal visual: `'Risco: Vermelho'`, `'Risco: Amarelo'`, `'Risco: Verde'`. Um
defeito adjacente foi corrigido nesta revisão: `GeofencingScreen` e `EscalationScreen` exibiam a
string crua vinda do servidor (`"red"`) em vez do rótulo traduzido — único ponto do app que não
passava pelo mapeamento, confirmado e corrigido junto com a auditoria de contraste.

---

### 2.2 Alvos de Toque (WCAG 2.5.5)

| App | Componente / Fluxo | Dimensão Renderizada | Mínimo Requerido | Status |
| :--- | :--- | :---: | :---: | :---: |
| Paciente | Botão de Emergência/Pânico (`panic_button`) | `208 x 208 dp` | 60 x 60 dp | Conforme (Amplo) |
| Paciente | Botões de Login e Envio de Triagem | `48 x 52 dp` | 48 x 48 dp | Conforme |
| ACS | Ações de Login, Confirmar Recebimento e Sincronizar | `48 x 52 dp` | 48 x 48 dp | Conforme |
| ACS | "Ligar para o SAMU (192)" | ~~`48x52 dp`~~ **sem `minimumSize` → 40dp de altura visual** | 60 x 60 dp | **Corrigido para `64x60 dp`** — a medição anterior ("48x52 dp") estava incorreta; o botão não declarava `minimumSize` e caía no default do Material 3. |
| ACS | "Salvar e enfileirar sincronização", "Descartar recusada(s)", "Encaminhar para UBS Central", "Iniciar rota de visita" (escalonamento) | sem `minimumSize` (40dp) | 48 x 48 dp | **Corrigido para `48x52 dp`**, não detectados no relatório anterior |

Reprodução: `meetsGuideline(androidTapTargetGuideline)` em ambos os apps (`login_flow_test.dart`,
`patient_app_mvp_test.dart`).

---

### 2.3 Rótulos Semânticos e Navegação por Leitor de Tela (WCAG 4.1.2)

#### Inspeção Estática de Código
* **Instâncias de `Semantics()`:** Login ACS (`app.dart`), Login Paciente, Botão de Pânico,
  banners de infraestrutura, e — nesta revisão — o cartão de alerta da fila.
* **Instâncias de `tooltip:`:** `'Enviar mensagem'`, `'Novo alarme'` no app paciente.

#### Correção: cartão de alerta lido como frase única

Achado de prioridade "Baixa" do relatório anterior, agora corrigido: o `_AlertCard` do ACS era
lido pelo TalkBack como quatro nós soltos ("Paciente 3f2a1b8c" / "Risco: Vermelho" / "Recebido
às..." / botão), sem ligação entre as informações. `Semantics(label: ..., excludeSemantics: true)`
envolve o bloco de identificação (paciente, risco, confirmação, horário) numa frase única; os
botões de ação continuam como nós próprios, fora do bloco. Coberto por teste
(`login_flow_test.dart`, "o cartão de alerta é lido como uma frase única pelo leitor de tela") e
confirmado em dispositivo real no emulador.

#### Teste Prático em Dispositivo (emulador Android + integração real)

* **Fluxo completo ponta a ponta:** app Paciente disparou um alerta de emergência real contra o
  backend rodando em Docker Compose; o app ACS recebeu o alerta pelo broker MQTT/TLS real,
  exibiu-o na fila com o novo `redOnSurface`, e o fluxo de escalonamento mostrou o botão do SAMU
  no novo tamanho e o risco traduzido (`_riskLabelPt`).
* **14 testes de integração em dispositivo** (`apps/acs/integration_test/`, incluindo
  `encrypted_storage_test.dart`, que lê o arquivo do banco e confirma que não é SQLite em texto
  plano) passam sobre o código revisado — a única forma de provar criptografia real, e a mesma
  suíte que exercita as telas de mapa e escalonamento tocadas por esta revisão.

---

### 2.4 Indicador de Foco Visível (WCAG 2.4.7)

Sem alteração nesta revisão: o indicador de foco nativo do sistema acompanha os alvos tocáveis
sem truncamento, confirmado durante a navegação manual no emulador.

---

### 2.5 Status Messages (WCAG 4.1.3) — critério novo

Ausente da avaliação anterior. Um leitor de tela só percebe uma mudança de conteúdo que não move
o foco se o nó semântico correspondente estiver marcado como região viva
(`Semantics(liveRegion: true)`). Sete pontos de status dinâmico foram auditados e não tinham essa
marcação:

| App | Local | O que muda |
| :--- | :--- | :--- |
| Paciente | `login_error` | Falha de autenticação |
| Paciente | `_state` do alerta de emergência | Confirmação de que o alerta chegou à equipe — o ponto mais crítico do app |
| Paciente | `triage_error` | Falha ao enviar a triagem |
| ACS | `login_error` | Falha de autenticação |
| ACS | `feed_error` / `storage_error` (`_InfraBanner`) | Broker ou armazenamento local caindo |
| ACS | `visit_storage_error` | Persistência falhando durante o registro da visita |
| ACS | `patient_directory_error` | Falha ao carregar pacientes da microárea |
| ACS | `rejected_visits_count` | Servidor recusou uma visita em definitivo |

Todos corrigidos com `Semantics(liveRegion: true)`. Cobertos por teste
(`SemanticsFlags.isLiveRegion`, em `login_flow_test.dart` e `patient_app_mvp_test.dart`) e
confirmados em dispositivo: o texto "Alerta recebido pela equipe" do fluxo de emergência real
chegou marcado como região viva.

---

## 3. Matriz de Achados — Situação Após Esta Revisão

| Prioridade original | Critério | Localização | Situação nesta revisão |
| :---: | :---: | :--- | :--- |
| Alta | 1.4.3 | `patient/app.dart` (`Colors.white54`) | **Refutado.** 5.36:1 sobre `Card` — a medição original comparava contra o Scaffold. Nenhuma ação necessária. |
| Média | 1.4.3 | `acs_theme.dart`/`patient_theme.dart` (vermelho como texto) | **Corrigido**, mas o remédio proposto (`#EF4444`) foi descartado por insuficiência (3.90:1 sobre card); adotada a separação fill/texto (§2.1). |
| (não detectado) | 1.4.3 | `AcsColors.accent`/`PatientColors.accent` como texto sobre card | **Corrigido** (achados C e D) — pior que o item "Média" do relatório anterior e não constava nele. |
| Média | 2.5.5 | Botão do SAMU | **Corrigido** para `64x60 dp`; a medição original ("48x52 dp") estava incorreta — o botão não tinha `minimumSize`. |
| Baixa | 4.1.2 | Cartões de alerta do ACS | **Corrigido** — cartão agora é uma frase semântica única. |
| (não avaliado) | 4.1.3 | Sete pontos de status dinâmico | **Critério ausente da baseline anterior, incorporado e corrigido nesta revisão.** |

---

## 4. Planejamento de Testes de Usabilidade Remota (UXtweak)

Sem alteração — planejamento de teste com usuários reais, independente dos achados técnicos
corrigidos acima.

### Cenário 1: Disparo de Alerta de Urgência (App Paciente)
* **Objetivo:** Avaliar o tempo de reação e a taxa de sucesso no acionamento do botão de pânico.
* **Métrica:** Tempo até o primeiro clique (*First-Click*) e taxa de conclusão sem erros.
* **Instrução dada ao usuário:** *"Você está se sentindo mal e precisa acionar o atendimento de emergência imediatamente. Qual botão você pressiona?"*

### Cenário 2: Priorização na Fila de Atendimento (App ACS)
* **Objetivo:** Avaliar a clareza da visualização dos sinais de risco em ambiente com baixo ruído visual.
* **Métrica:** Taxa de cliques corretos no paciente de maior risco da lista.
* **Instrução dada ao usuário:** *"No seu painel de atendimento, identifique o paciente que exige visita prioritária imediata e acesse os detalhes dele."*

---

## 5. Cobertura Automatizada (substitui a auditoria manual)

| Verificação | Onde roda | O que impede de regredir |
| :--- | :--- | :--- |
| Matriz de contraste WCAG 1.4.3 | `apps/{acs,patient}/test/contrast_tokens_test.dart` | Qualquer token de tema cair abaixo de 4.5:1/3:1 na superfície real |
| `meetsGuideline` (contraste + alvo de toque) | `login_flow_test.dart`, `patient_app_mvp_test.dart` | Regressão de contraste ou alvo de toque nas telas de login |
| `SemanticsFlags.isLiveRegion` | idem | Status dinâmico deixar de ser anunciado |
| Rótulo semântico do cartão de alerta | `login_flow_test.dart` | Cartão voltar a ser lido como nós soltos |
| 14 testes de integração em dispositivo | `apps/acs/integration_test/` | Regressão de fluxo real (criptografia, MQTT/TLS, mapa, escalonamento) |

Este conjunto roda no CI (`serverpod-backend`, `patient-app`, `acs-app` — ver `.github/workflows/ci.yml`
para os dois primeiros grupos; o de integração em dispositivo é manual via `scripts/qa/e2e.sh --emulator`)
e é a evidência que substitui as capturas de tela do WebAIM desta revisão em diante.
