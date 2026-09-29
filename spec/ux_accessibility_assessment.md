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
| **2.5.3 Label in Name** | O nome acessível de um controle com rótulo visível deve **conter** esse texto | (ausente da avaliação anterior) | **Parcial (corrigido em parte)** | Critério não coberto pelo relatório original — a baseline declarada é 2.1 AA e 2.5.3 é **nível A**. O padrão `Semantics(button: true)` em volta de um `FilledButton` produz **os dois** defeitos ao mesmo tempo: nome que não contém o texto visível (2.5.3) e um nó inerte (4.1.2). Quatro sítios medidos corrigidos (login do paciente, login do ACS, botão de EMERGÊNCIA, 'Concluir cadastro' do onboarding — medido e corrigido em 2026-09-21, ver §2.6); **um está em aberto com dono** (login do admin). Ver §2.6 e §3. |
| **2.5.5 Target Size** | Alvo de toque adequado para interatividade | ≥ 48x48 dp (padrão), ≥ 60x60 dp (botão de emergência/pânico) | **Conforme (corrigido)** | Botão de pânico do paciente: `208x208 dp`. "Ligar para o SAMU (192)" no ACS não tinha `minimumSize` (default M3 de 40dp de altura visual) — corrigido para `64x60 dp`. Quatro outros botões de ação primária no ACS também não tinham `minimumSize` explícito; padronizados em `48x52 dp`. |
| **4.1.2 Name, Role, Value** | Árvore semântica exposta para leitores de tela nativos | Rótulos e papeis em 100% dos fluxos críticos | **Parcial (ver §2.6)** | Árvore semântica nativa do Flutter expõe abas (**Área, Fila, Mapa, Visita, Mais**) e formulários com clareza; o cartão de alerta da fila passou a ser lido como uma frase única (§3, achado antigo de prioridade Baixa). **Ressalva (2026-09-19):** o critério volta a **parcial** pelo nó inerte do §2.6 — o mesmo `Semantics` em volta de um botão que viola o 2.5.3 cria um nó anunciado como botão **sem ação de toque**. 'Concluir cadastro' foi medido e corrigido em 2026-09-21 (era defeito de verdade, não só "não medido" — ver §2.6); resta um sítio em aberto, com dono (login do admin). |
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
* **Instâncias de `Semantics()`:** a lista anterior — "Login ACS (`app.dart`), Login Paciente,
  Botão de Pânico, banners de infraestrutura, e — nesta revisão — o cartão de alerta da fila" —
  era um inventário de *onde existem* instâncias, e ficou desatualizada **nos dois sentidos**:
  o rótulo saiu dos dois logins e o botão de pânico ganhou `MergeSemantics`. Cada sítio hoje diz
  o que faz: **login do paciente** e **login do ACS** não têm `Semantics` nenhum em volta (o
  `Text` do botão é o nome acessível); **botão de EMERGÊNCIA**, `MergeSemantics` em volta do
  `Semantics(label: ...)` — um nó só, com a frase descritiva dentro do nome. Os demais —
  **banners de infraestrutura**, **cartão de alerta da fila** e os `liveRegion` do §2.5 —
  continuam como estavam: têm outra forma (região viva ou rótulo sobre um bloco de texto, não
  `button: true`) e **não foram medidos** como nós de botão. Não os leia como defeito sem medir
  — a regra que separa as duas formas está no §2.6.
* **Um sítio a mais, e esse foi medido:** o botão de atualizar a microárea do ACS
  (`Key('pull_visits')`, em `apps/acs/lib/app/app.dart:850`, tela `TerritorializationScreen`, aba
  **Área**) tem a **forma** do defeito do §2.6 — um `Semantics(label: 'Sincronizando com a
  central' ...)` em volta de um `FilledButton` —, mas a medição da árvore semântica mostra que
  **aqui ela é benigna**: o rótulo não funde com o botão (sobe para o nó do painel acima), então o
  nome acessível do botão continua sendo exatamente o texto visível `'Atualizar dados da microárea'`,
  com `isButton` e ação de toque nos dois estados, e nenhum nó inerte aparece. Com `pulling == true`
  o botão aparece **desabilitado** (`isEnabled: Tristate.isFalse`, sem ação de toque) e o rótulo
  `'Sincronizando com a central'` fica no painel — o anúncio que se queria, e um estado legítimo,
  não o nó inerte. **Como foi medido, e por que isso importa:** por uma varredura ad hoc da aba Área
  nos dois estados (teste temporário, não versionado) — a `expectNenhumBotaoInerte` do §2.6 **não
  cobre esta aba**, porque as duas chamadas dela no app ACS rodam na aba **Fila**, e o corpo do
  shell é um `switch (destination)` que só constrói a aba selecionada. Ou seja: o veredicto é
  medido, e **não** tem guarda — uma chamada da varredura logo depois de trocar para a aba Área
  fecharia isso, e é a primeira coisa a acrescentar quando alguém tocar nesta tela. Ver §2.6.
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

### 2.6 Nome Acessível e Nós Inertes (WCAG 2.5.3 e 4.1.2) — critério novo

Ausente da avaliação anterior: **zero ocorrências de `2.5.3` ou "Label in Name"** neste
documento. A baseline declarada é 2.1 AA, e 2.5.3 (Label in Name) é **nível A** do 2.1 — estava
no escopo e simplesmente não foi avaliado. A §2.3 cita "Login Paciente" como *sítio* de
`Semantics()`, sem avaliar o valor.

**A regra que o caso ensina.** Um `Semantics` em volta de um controle **ou funde com ele**
(mesmo nó, com a ação — `MergeSemantics`, ou `excludeSemantics: true` + `onTap` explícito) **ou
cria um nó próprio**, anunciado com papel de botão e **sem ação de toque**. A segunda forma é a
que engana: o nome acessível parece certo — é até mais descritivo que o texto do botão —, mas o
leitor de tela encontra primeiro um "botão" que não faz nada, e só depois o botão real. São dois
critérios violados de uma vez: o nome não contém o texto visível (**2.5.3**) e o nó é inerte
(**4.1.2**). Note que **a correção não é reescrever o texto**: um rótulo igual ao texto visível
deixaria dois nós com o mesmo nome, o primeiro deles inerte — some-se o wrapper, ou use-se
`excludeSemantics: true` com `onTap` explícito.

| Sítio | O que foi medido | Situação |
| :--- | :--- | :--- |
| `apps/patient/lib/app/app.dart` — **botão de EMERGÊNCIA**, `label: 'Enviar alerta de emergência'` sobre o texto visível `'EMERGÊNCIA'` | `#47 isButton / "Enviar alerta de emergência" / sem actions` + filho `#48 tap / "EMERGÊNCIA"`, com o nó inerte cobrindo `Rect.fromLTRB(0, 0, 752, 208)` — a largura toda do `ListView`. **2.5.3 e 4.1.2 no controle mais crítico do app** | **Corrigido** com `MergeSemantics` em volta do `Semantics`: um nó só, `rect=(0,0,208,208)`, rótulo `"Enviar alerta de emergência\nEMERGÊNCIA"` e ação de toque. Adiar não se sustentou: nenhum teste prendia aquele rótulo, e fundir não exige escolher texto novo — a frase descritiva continua no nome acessível, que é o motivo de não se remover o wrapper aqui. |
| `apps/patient/lib/app/app.dart` — **login** (`enter_button`, texto visível `'Entrar sem senha'`) | mesmo par de nós; o `Semantics` chamava-se `'Entrar na triagem do paciente'` | **Corrigido** — o wrapper saiu; o nome acessível é o `Text` do próprio botão. Prendido por `find.bySemanticsLabel('Entrar sem senha')` (igualdade exata, não *contains*) e pela ausência do rótulo antigo. |
| `apps/acs/lib/app/app.dart` — **login do ACS** (`login_button`, texto visível `'Entrar com credenciais'`) | mesmo par de nós | **Corrigido** — wrapper removido, pelo mesmo motivo. |
| `apps/admin/lib/app/app.dart:119` — **login do backoffice** | `#10 "Entrar no backoffice administrativo"` sem actions + `#11 tap / "Entrar"` | **Em aberto, com dono: o app admin.** Não é dívida do RF01; fica com a próxima rodada do backoffice. |
| `apps/acs/lib/app/app.dart:850` — **botão de atualizar a microárea** (`Key('pull_visits')`, aba Área), `Semantics(label: 'Sincronizando com a central' ...)` em volta de um `FilledButton` | **Medido nos dois estados, por varredura ad hoc da aba Área** (a `expectNenhumBotaoInerte` versionada roda na aba Fila e não vê esta tela). Com `pulling == false` o botão é `isButton` com o nome `'Atualizar dados da microárea'` (o texto visível) e ação de toque; com `pulling == true`, o mesmo nome e `isEnabled: Tristate.isFalse` sem ação de toque (desabilitado, estado legítimo), com `'Sincronizando com a central'` no nó do painel acima — o rótulo **não** desce para o botão. Nenhum nó inerte nos dois estados | **Medido — não é defeito.** É o único sítio com a forma do §2.6 que foi medido e passa; o rótulo extra chega ao anúncio pelo painel, não por um nó inerte. **Sem guarda:** nenhuma varredura versionada passa por esta aba — quem tocar nesta tela deve acrescentar a chamada (ver §2.3). |
| `apps/patient/lib/app/app.dart:684` (era `:672`) — **'Concluir cadastro'** (onboarding) | **Medido em 2026-09-21**, rolando o `ListView` até o botão antes da varredura (`test/onboarding_flow_test.dart`): era o mesmo defeito dos três sítios já corrigidos — nó `isButton` sem `SemanticsAction.tap`, `rect=Rect.fromLTRB(0.0, 0.0, 324.0, 52.0)` | **Corrigido** — `MergeSemantics` em volta do `Semantics(button: true)`, mesma correção do botão de EMERGÊNCIA. `expectNenhumBotaoInerte` passa; guardado por teste versionado (não era só "não medido" como este relatório dizia antes — era defeito de verdade). |

Os demais `Semantics(...)` — os `liveRegion` do §2.5, o rótulo do cartão de alerta da fila, os
banners de infraestrutura — têm outra forma e **não** foram medidos como nós de botão: não os
declare defeito sem medir. Um sítio tem a forma do defeito e **foi** medido sem achá-lo: o botão
de atualizar a microárea do ACS (`apps/acs/lib/app/app.dart:850`, `Key('pull_visits')`) — o
rótulo sobe para o painel e o botão conserva o nome visível e a ação de toque. Ele está na tabela
acima; a forma do código é a mesma dos três sítios corrigidos, e o que muda o veredicto é o
resultado da medição, não a forma.

Reprodução: `expectNenhumBotaoInerte(tester)` (`test/support/semantics_scan.dart`, nos dois apps)
roda na árvore inteira das telas tocadas — login e tela de emergência no app do paciente, login
e painel com alerta na fila no ACS — e é ela, não as asserções de rótulo (verdes nos dois
estados), quem separa o defeito da correção. O nó mesclado no pai (`MergeSemantics`) não é
contado: o que a plataforma anuncia é a fronteira da fusão, e é isso que a varredura mede.

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
| (não avaliado) | **2.5.3** | `Semantics(button: true)` em volta de um botão de verdade — login do paciente, login do ACS, botão de EMERGÊNCIA, login do admin e 'Concluir cadastro' | **Critério ausente da baseline anterior (nível A do 2.1), incorporado nesta revisão.** Medição e regra no §2.6. Quatro sítios corrigidos (login do paciente, login do ACS, botão de EMERGÊNCIA, 'Concluir cadastro' — medido e corrigido em 2026-09-21); **um em aberto**: login do admin (**dono: o app admin**). |

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
| Varredura de nós "botão" sem ação de toque (WCAG 4.1.2 e 2.5.3) | `test/support/semantics_scan.dart` (`expectNenhumBotaoInerte`), usado em `login_flow_test.dart` e `patient_app_mvp_test.dart` | Um `Semantics` em volta de um botão voltar a anunciar um "botão" que não responde ao toque. A varredura olha a árvore inteira, não um sítio — prender por sítio passaria com o defeito, porque o nó que carrega o nome é justamente o inerte. Tem testes de sanidade (`acusa o "botão" sem ação de toque`, `não acusa controle legitimamente desabilitado`, `não passa em silêncio quando não há o que medir`). |
| 14 testes de integração em dispositivo | `apps/acs/integration_test/` | Regressão de fluxo real (criptografia, MQTT/TLS, mapa, escalonamento) |

Este conjunto roda no CI (`serverpod-backend`, `patient-app`, `acs-app` — ver `.github/workflows/ci.yml`
para os dois primeiros grupos; o de integração em dispositivo é manual via `scripts/qa/e2e.sh --emulator`)
e é a evidência que substitui as capturas de tela do WebAIM desta revisão em diante.
