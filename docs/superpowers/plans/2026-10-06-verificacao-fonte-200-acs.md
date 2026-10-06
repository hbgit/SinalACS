# Verificação das três lacunas da fonte a 200% no ACS — Plano de Implementação

> **Para quem executa:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** Para cada uma das três lacunas, decidir com evidência se ela segue em aberto e, se sim, fechá-la com um teste que falha quando o defeito existe.

**Arquitetura:** Primeiro uma tarefa de verificação (grafo + código) que classifica cada ponto como ABERTO, FECHADO ou PARCIAL, sem mudar código. Depois uma tarefa de teste por ponto aberto, todas em `apps/acs/test/text_scale_test.dart` e reutilizando `test/support/layout_harness.dart`. Só se um teste novo falhar contra o código atual é que se corrige `apps/acs/lib/app/app.dart`.

**Stack:** Flutter, `flutter_test` (widget tests), `SemanticsHandle` / `tester.getSemantics`.

**Spec:** `spec/ux_accessibility_assessment.md` (WCAG 1.4.4, 2.5.8, 4.1.2) e `RNF05` em `spec/PRD_system.md`.

## Global Constraints

- Textos, rótulos e mensagens de teste em português.
- Nada de `MediaQuery.withClampedTextScaling`: o layout aguenta a escala (comentário de `text_scale_test.dart`).
- Alvo de toque mínimo de 48 dp; o `save_visit` declara `minimumSize: Size(48, 52)`.
- Sem dados reais de paciente: só `FakeAcsBackend` e `testAlert` de `test/support/fakes.dart`.
- Commits sem linha de atribuição de IA nem `Co-Authored-By` (regra do `CLAUDE.md` do projeto).
- Antes de `grep` cru, rodar `graphify query "<pergunta>"` (hook do repositório); depois de mudar código, `graphify update .`.

## Review Focus

- Janela de **320 dp** com 200%: é a combinação mais apertada, e só existe um teste dela (`app_lock_gate_test.dart:413`, 320x480, só a cobertura de bloqueio). O painel inteiro nunca foi varrido ali.
- **Paisagem** (800x360, altura menor que a largura): o `AppBar` cresce com a fonte (`acsHeaderHeight`) e a área rolável encolhe; o risco é o corpo ficar sem altura útil.
- `save_visit` **desabilitado** (`onPressed: null` sem paciente ou sem chegada confirmada) não pode contar como "alcançável": o teste precisa deixá-lo habilitado antes de afirmar.
- Chip `broker_status` com `maxLines: 1` e `ellipsis`: o texto visual é cortado, mas o rótulo semântico tem de continuar o texto inteiro, nos três estados (`null`, `true`, `false`).
- Fonte a **1.3** e a **2.0** em 320 dp: a 1.3 também precisa passar, porque é o ajuste mais comum.

---

### Task 1: Classificar cada lacuna (somente leitura)

**Files:**
- Read: `apps/acs/test/text_scale_test.dart`, `apps/acs/test/support/layout_harness.dart`, `apps/acs/test/visit_owner_flow_test.dart`, `apps/acs/test/app_lock_gate_test.dart`
- Read: `apps/acs/lib/app/app.dart` (cabeçalho `~3570-3612`, formulário de visita `~3085-3125`)
- Create: `docs/superpowers/plans/2026-10-06-verificacao-fonte-200-acs-resultado.md`

**Interfaces:**
- Produces: tabela com as linhas L1 (320dp/paisagem), L2 (`save_visit` alcançável), L3 (rótulo acessível do chip), cada uma ABERTO, FECHADO ou PARCIAL, com `arquivo:linha` como evidência. As Tarefas 2 a 4 só rodam para linhas ABERTO ou PARCIAL.

- [ ] **Step 1: Orientar-se pelo grafo**

Run:
```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
graphify query "teste de fonte 200% layout_harness text_scale_test" --budget 1500
graphify explain "layout_harness.dart"
graphify query "broker_status chip cabeçalho Semantics"
graphify query "save_visit aba Visita"
```
Expected: nós de `text_scale_test.dart`, `layout_harness.dart` e `app.dart`. Se o grafo vier vago, seguir com `grep` direcionado nesses arquivos.

- [ ] **Step 2: Confirmar L1 (tamanhos varridos)**

Run:
```bash
cd apps/acs
grep -rnE "Size\((320|800, *360|360|411)" test integration_test
grep -rniE "paisagem|landscape" test integration_test
```
Esperado hoje: `Size(360, 800)` em `text_scale_test.dart`, `Size(320, 480)` só em `app_lock_gate_test.dart:413`, nenhuma ocorrência de paisagem. Se aparecer um teste que varre o painel em 320 ou em paisagem, marcar L1 como FECHADO ou PARCIAL e citar a linha.

- [ ] **Step 3: Confirmar L2 (alcance do `save_visit`)**

Run:
```bash
grep -nE "save_visit" test/*.dart integration_test/*.dart
grep -nE "hitTestable" test/text_scale_test.dart test/visit_owner_flow_test.dart
```
Esperado hoje: `save_visit` aparece em `visit_owner_flow_test.dart` com `ensureVisible`, mas em escala 1.0; `text_scale_test.dart` não o cita. Marcar L2 ABERTO se nenhum teste combina fonte a 2.0, `ensureVisible` e `hitTestable` no `save_visit`.

- [ ] **Step 4: Confirmar L3 (rótulo do chip)**

Run:
```bash
grep -rnE "broker_status" test integration_test
```
Esperado hoje: nenhuma ocorrência. No código, o `Chip` tem `label: Text(..., overflow: ellipsis, maxLines: 1)` e nenhum `Semantics` próprio. Marcar L3 ABERTO se nenhum teste lê o rótulo semântico.

- [ ] **Step 5: Gravar o resultado**

Escrever a tabela L1/L2/L3 em `2026-10-06-verificacao-fonte-200-acs-resultado.md`, com a evidência de cada linha. Se alguma linha der FECHADO, dizer isso e pular a tarefa correspondente.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-10-06-verificacao-fonte-200-acs-resultado.md
git commit -m "docs: resultado da verificação das lacunas da fonte a 200% no ACS"
```

---

### Task 2: L1 — varrer o painel em 320 dp e em paisagem

**Files:**
- Modify: `apps/acs/test/text_scale_test.dart:14-20`
- Test: `apps/acs/test/text_scale_test.dart`

**Interfaces:**
- Consumes: `abrirPainel(tester, tamanho:, escalaDeFonte:)` e `percorrerPainelInteiro(tester, contexto)` de `test/support/layout_harness.dart`.
- Produces: testes `não estoura o layout com fonte a N% em WxH`.

- [ ] **Step 1: Escrever o teste que varre os três tamanhos**

Trocar o laço atual (que só cobre 360x800) por:

```dart
  const janelas = {
    '360x800': Size(360, 800),
    '320x640': Size(320, 640),
    '800x360 (paisagem)': Size(800, 360),
  };
  for (final janela in janelas.entries) {
    for (final escala in const [1.3, 2.0]) {
      final rotulo = '${(escala * 100).toInt()}%';
      testWidgets('não estoura o layout com fonte a $rotulo em ${janela.key}', (tester) async {
        await abrirPainel(tester, tamanho: janela.value, escalaDeFonte: escala);
        await percorrerPainelInteiro(tester, 'fonte a $rotulo em ${janela.key}');
      });
    }
  }
```

- [ ] **Step 2: Rodar e ver o resultado**

Run: `cd apps/acs && flutter test test/text_scale_test.dart --plain-name "não estoura o layout com fonte"`
Expected: se algum tamanho estourar, FAIL com `estouro de layout em fonte a 200% em 320x640 / <destino> (...)`. Se passar tudo, a lacuna era só de cobertura: o teste fica como prova e não há correção.

- [ ] **Step 3: Corrigir só o que falhar**

Para cada falha, abrir o widget citado na mensagem em `apps/acs/lib/app/app.dart` e trocar a largura ou altura fixa por `Flexible`/`Expanded`/`Wrap`, ou envolver em `SingleChildScrollView`. Não usar `withClampedTextScaling`. Um caso por vez, rodando de novo o Step 2.

- [ ] **Step 4: Rodar a suíte inteira do arquivo**

Run: `cd apps/acs && flutter test test/text_scale_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/acs/test/text_scale_test.dart apps/acs/lib/app/app.dart
git commit -m "test(acs): painel varrido a 130% e 200% em 320 dp e em paisagem"
```

---

### Task 3: L2 — afirmar que `save_visit` fica alcançável a 200%

**Files:**
- Modify: `apps/acs/test/text_scale_test.dart` (novo `testWidgets` antes do bloco da MFA)
- Read: `apps/acs/test/visit_owner_flow_test.dart:60-130` (como chegar a um formulário com paciente e chegada confirmada)

**Interfaces:**
- Consumes: `abrirPainel`, `irParaDaBarra`, `assentar`, `esperarSemEstouro`.
- Produces: teste `save_visit fica alcançável a 200% em <janela>`.

- [ ] **Step 1: Ver como o teste existente habilita o botão**

Run: `cd apps/acs && sed -n 60,130p test/visit_owner_flow_test.dart`
Anotar os passos que selecionam um paciente (chave `patient_search`, linha 188) e marcam `arrival_confirmation`. O botão só habilita com `hasPatient && _arrivalConfirmed` (`app.dart:3111`).

- [ ] **Step 2: Escrever o teste**

Substituir `<passos de seleção>` pelos passos anotados no Step 1 (copiados, não resumidos):

```dart
  for (final janela in const {'360x800': Size(360, 800), '320x640': Size(320, 640), '800x360': Size(800, 360)}.entries) {
    testWidgets('save_visit fica alcançável a 200% em ${janela.key}', (tester) async {
      await abrirPainel(tester, tamanho: janela.value, escalaDeFonte: 2.0);
      await irParaDaBarra(tester, 'Visita');
      // <passos de seleção>: escolher o paciente e marcar `arrival_confirmation`.
      await assentar(tester);

      final salvar = find.byKey(const Key('save_visit'));
      await tester.ensureVisible(salvar);
      await assentar(tester);
      expect(tester.widget<FilledButton>(salvar).onPressed, isNotNull,
          reason: 'desabilitado não prova alcance');
      expect(salvar.hitTestable(), findsOneWidget);
      expect(tester.getSize(salvar).height, greaterThanOrEqualTo(48));
      esperarSemEstouro(tester, 'botão Salvar a 200% em ${janela.key}');
    });
  }
```

- [ ] **Step 3: Rodar**

Run: `cd apps/acs && flutter test test/text_scale_test.dart --plain-name "save_visit fica alcançável"`
Expected: PASS se o botão já é alcançável. FAIL em `hitTestable` (botão coberto pelo `NavigationBar` ou fora da rolagem) é o defeito real; nesse caso, ajustar o padding inferior ou a rolagem da aba em `app.dart` e rodar de novo.

- [ ] **Step 4: Provar que o teste pega o defeito**

Trocar temporariamente `key: const Key('save_visit')` por outra chave em `app.dart:3110`, rodar o teste, ver FAIL, desfazer. Isso confirma que o `find` não passa em vazio.

- [ ] **Step 5: Commit**

```bash
git add apps/acs/test/text_scale_test.dart apps/acs/lib/app/app.dart
git commit -m "test(acs): save_visit alcançável e habilitado com fonte a 200%"
```

---

### Task 4: L3 — testar o rótulo acessível do chip de conexão

**Files:**
- Modify: `apps/acs/test/text_scale_test.dart`
- Possivelmente modify: `apps/acs/lib/app/app.dart:3590-3612` (cabeçalho)

**Interfaces:**
- Consumes: `abrirPainel`, `assentar`; chave `broker_status`.
- Produces: teste `chip de conexão mantém o rótulo semântico completo a 200%`.

- [ ] **Step 1: Escrever o teste do estado `true` e do truncamento**

```dart
  testWidgets('chip de conexão mantém o rótulo semântico completo a 200% em 360x800', (tester) async {
    final semantica = tester.ensureSemantics();
    addTearDown(semantica.dispose);
    await abrirPainel(tester, tamanho: const Size(360, 800), escalaDeFonte: 2.0);

    final chip = find.byKey(const Key('broker_status'));
    expect(chip, findsOneWidget);
    // O texto visual é cortado por `maxLines: 1`; o rótulo semântico não pode ser.
    final rotulo = tester.getSemantics(chip).label;
    expect(rotulo, contains('Alertas em tempo real'));
    esperarSemEstouro(tester, 'chip de conexão a 200%');
  });
```

- [ ] **Step 2: Rodar**

Run: `cd apps/acs && flutter test test/text_scale_test.dart --plain-name "chip de conexão"`
Expected: PASS se o `Text` do `Chip` propaga o rótulo inteiro. Se falhar porque o `label` vem vazio ou cortado, ir ao Step 3.

- [ ] **Step 3: Cobrir os outros dois estados (`false` e `null`)**

Descobrir como o `FakeAcsBackend` ou o `feedBuilder` de `fakes.dart` controla `connected`:
```bash
cd apps/acs && grep -nE "connected|brokerConnected|connectionStream" test/support/fakes.dart lib/app/app.dart | head -20
```
Escrever um teste por estado, afirmando `'Sem central'` e `'Offline ready'` no rótulo semântico do `broker_status`. Se o estado não puder ser forçado pelos fakes, registrar isso no arquivo de resultado em vez de inventar um acoplamento novo.

- [ ] **Step 4: Corrigir só se o rótulo semântico falhar**

Em `app.dart`, envolver o `Chip` em `Semantics(label: <texto do estado>, liveRegion: true, excludeSemantics: true, child: ...)`, no mesmo padrão de `app.dart:2325-2330`, e extrair o texto do `switch` para uma variável usada pelos dois lugares (texto visual e `Semantics`). `liveRegion` faz o leitor de tela anunciar a perda da central, o que combina com o texto do cabeçalho: "um ACS precisa saber, sem procurar, que parou de receber alertas".

- [ ] **Step 5: Rodar a suíte do ACS**

Run: `cd apps/acs && flutter test`
Expected: PASS, sem regressão em `semantics_scan` (o `Semantics` novo não pode virar botão inerte).

- [ ] **Step 6: Commit**

```bash
git add apps/acs/test/text_scale_test.dart apps/acs/lib/app/app.dart
git commit -m "test(acs): rótulo semântico do chip de conexão a 200%"
```

---

### Task 5: Fechar o ciclo

**Files:**
- Modify: `spec/ux_accessibility_assessment.md` e `PROGRESS.md`, só nas linhas que citam essas três lacunas (achar com `grep -nE "360x800|paisagem|save_visit|elipse" spec/ux_accessibility_assessment.md PROGRESS.md`).

- [ ] **Step 1: Atualizar o grafo e os testes**

Run:
```bash
cd /home/rock/Documents/Dev/APPs/SinalACS && graphify update .
cd apps/acs && flutter analyze && flutter test
```
Expected: sem avisos novos; todos os testes passam.

- [ ] **Step 2: Atualizar a documentação**

Para cada lacuna fechada, trocar a frase de "não coberto" pela evidência (nome do teste). Para a que seguir aberta, dizer por quê. Não tocar em outras linhas do documento.

- [ ] **Step 3: Commit**

```bash
git add spec/ux_accessibility_assessment.md PROGRESS.md
git commit -m "docs: lacunas da fonte a 200% no ACS atualizadas com a evidência dos testes"
```

---

## Autorrevisão

- **Cobertura:** L1 na Tarefa 2, L2 na Tarefa 3, L3 na Tarefa 4; a Tarefa 1 decide se cada uma ainda está em aberto, que era o pedido.
- **Placeholders:** o único marcador é `<passos de seleção>` na Tarefa 3. É deliberado: os passos dependem de `visit_owner_flow_test.dart`, e o Step 1 manda copiá-los de lá.
- **Consistência:** chaves usadas (`save_visit`, `broker_status`, `arrival_confirmation`, `patient_search`) existem em `app.dart`; helpers (`abrirPainel`, `irParaDaBarra`, `assentar`, `esperarSemEstouro`) existem em `layout_harness.dart`.
