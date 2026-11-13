# PR #156 (C-03, biblioteca educativa): parecer e comentários a publicar

Textos da revisão da PR #156 (`feat/c-03-biblioteca-educativa`, autor `Rosialdo`, base `feat/c-02-aviso-educativo` (#155), commit `4b10e56`). Publicar só depois da aprovação do dono, com `gh pr review` (parecer) e `gh api repos/hbgit/SinalACS/pulls/156/comments` (inlines, um por chamada). Plano: `2026-11-13-prs-156-163-revisao.md`.

Veredito proposto: **Aprovar com observações** (`gh pr review --approve`). Não há bloqueante. Os três pedidos ao autor são pequenos (duas linhas do `PROGRESS.md` e um teste a 200 % de fonte, que rodei por fora e passa) e não precisam de nova rodada. O conteúdo clínico não é avaliado aqui: as afirmações listadas no comentário geral vão para a revisão dos preceptores (P-07), e os dois temas continuam `rascunho`, com selo na tela.

---

## Parecer

Revisei a PR contra a issue #126, o escopo (`docs/escopo/mudancas-de-codigo-recomendadas.md`, linha C-03; `spec/escopo_projeto.md`, P-01 e P-07) e o padrão da C-02. Os três primeiros critérios estão atendidos e provados por teste; o quarto fica aberto de propósito, e a PR usa `Refs #126` (o GitHub não lista a #126 como fechada por ela).

| Critério da #126 | Evidência |
|---|---|
| Conteúdo disponível sem conta e sem rede | `test/educational_library_test.dart` "abre pelo login, sem sessão e sem nenhuma chamada ao backend": sobe o `SinalAcsApp` com um `PatientBackend` que recusa e registra qualquer chamada, abre pelo `login_library_button` e lê o asset real pelo `rootBundle`; nenhuma chamada nova. A tela não recebe o backend (`EducationalLibraryScreen` só tem `source`). O mesmo roteiro está em `integration_test/educational_library_test.dart`. |
| Cada tema cita a fonte (MS ou BVS) | O parser recusa o arquivo inteiro (`EducationalLibraryFormatException`) se um tema não tem fonte, se o órgão não é MS/BVS, se o endereço não é `https` ou está fora dos hosts do órgão; um teste por regra no grupo "parser recusa conteúdo fora da P-07", e "temas.json é válido..." passa o asset real por ele. |
| `LICENCA.md` CC BY 4.0 com atribuição; "Sobre" com MIT e CC BY 4.0 | "a pasta traz a licença CC BY 4.0 com a atribuição" compara a `LICENCA.md` com a mesma constante `contentAttribution` que o app mostra; "\"Sobre\" indica código MIT e conteúdo CC BY 4.0". A `LICENSE` da raiz é MIT, o que bate com `codeLicenseLabel`. |
| Temas e revisores conforme a P-07 | Aberto, como a PR diz. "nenhum tema se declara revisado enquanto a P-07 não define revisores" prende os dois temas em `rascunho`; o selo aparece na lista e no tema; "revisado" sem revisores ou sem data é recusado. |

**O que rodei em Linux** (worktree limpo da branch, `4b10e56`):

- `flutter test test/educational_library_test.dart`: 17 passam.
- `flutter test` completo do paciente: todos passam.
- `flutter analyze`: só o aviso `asset_directory_does_not_exist` de `assets/certs/` (diretório gitignorado; não é desta PR).
- `bash scripts/qa/check_documentation_links.sh`: só o `graphify-out` de `AGENTS.md`, que já é assim na base.
- 200 % de fonte: como a PR não traz teste para isso, rodei uma sonda descartável (não commitada) que abre a lista, desce até o rodapé de cada um dos dois temas e até as licenças de "Sobre", em 360×640 e 320×568. Nenhum overflow.
- Não rodei `integration_test/educational_library_test.dart` (sem emulador nesta máquina). Segundo o painel da PR (`gh pr checks 156`, consultado em 2026-11-13), os 9 jobs da CI estão verdes, inclusive `android-e2e`.

**Pontos que conferi no código e aprovo:**

- Offline por construção: `AssetEducationalLibrarySource` só chama `rootBundle.loadString`; a lista e o tema não pegam `BackendScope` nem sessão. O botão do login fica antes de qualquer sessão (pilar A, RF22).
- Falha não derruba o app: uma exceção do parser ou da leitura cai no `FutureBuilder` e vira `_LibraryError` ("Não foi possível abrir a biblioteca neste aparelho.", com `liveRegion`) e "Tentar de novo", que lê de novo (teste com `_FailingSource`). O `..ignore()` em `_load()` só cala o erro não tratado; o `FutureBuilder` continua a recebê-lo.
- A lista e o tema mostram `educationalNoticeShort` pela constante da C-02, sem cópia do texto (RF21).
- `pubspec.yaml` registra só a pasta `assets/conteudo_educativo/`.
- Chaves e testes: `login_library_button` (login) e `more_library` (menu "Mais") têm `Key` e teste cada um.
- Conteúdo, no que cabe ao revisor de código: português simples; nenhuma orientação que dispense atendimento ("procure um serviço de saúde", "procure atendimento de urgência na hora"); "ligue 192 (SAMU)" nos dois temas; nenhum "UBS" (D4) nem marca de protocolo (M-05), com teste; fontes `https` em `www.gov.br` e `bvsms.saude.gov.br`, com data de consulta; a `LICENCA.md` diz que os textos são paráfrases com citação e que a CC BY 4.0 não cobre o material original.
- Acessibilidade: só `onSurface`/`onSurfaceVariant`/`outline` como cor (nenhum fill clínico), seções com `Semantics(header: true)`, alvos de 48×52, selo com ícone e texto.
- A mensagem do commit está completa (o "…" na lista da PR é só o corte do título pelo GitHub). Esse pedido da #155 não se repete aqui.

**Pedidos (pequenos, nesta PR):** tirar as contagens de testes do `PROGRESS.md` (o mesmo pedido da #155); corrigir o nome do campo na instrução de publicação da revisão; um teste a 200 % de fonte nas duas telas, como a C-02 fez.

**Pedido aos preceptores (P-07, não ao autor):** as afirmações listadas no comentário geral.

**Sugestões (opcionais):** restringir o caminho das URLs do MS a `/saude/`; validar `consultadoEm` e `revisao.data` como datas; mostrar a data da revisão no mesmo formato da data de consulta.

**Registros:** o botão no login fica na mesma região que a #161 e a #157 mexem; quem mesclar depois resolve o conflito.

---

## Inline 1 — PROGRESS.md:1952 — pedido

O mesmo pedido da #155: o `CONTRIBUTING.md` pede para não gravar contagens de testes nos documentos ("elas envelhecem a cada PR"). Esta linha e a linha 1949 ("tem 17 casos") têm contagens. Sugiro:

> - Rodado em 2026-11-08 no Windows: `flutter analyze` limpo; suíte do paciente verde; `integration_test/educational_library_test.dart` passou no `emulator-5554` (API 37).

e, na 1949, "`test/educational_library_test.dart` cobre o asset real (...)", sem o número. As contagens podem ficar no corpo da PR.

---

## Inline 2 — PROGRESS.md:1954 — pedido

O campo está trocado: `revisao` é o objeto, e quem muda é `revisao.situacao`. O corpo da PR já diz certo. Sugiro:

> Para publicar a revisão, trocar `"situacao": "rascunho"` por `"revisado"` em `revisao`, com `revisores` e `data`, e atualizar o teste "nenhum tema se declara revisado".

---

## Inline 3 — apps/patient/test/educational_library_test.dart:298 — pedido

Falta um teste a 200 % de fonte para a lista e o tema, como a C-02 fez em `test/educational_notice_test.dart` ("a 200% de fonte, \"Sobre\" não estoura"). Rodei uma sonda por fora em 360×640 e 320×568 e nada estoura, então é só prender isso. Esboço, no padrão da C-02 e com o asset lido do disco para não depender do tempo do `rootBundle`:

```dart
testWidgets('a 200% de fonte, a lista e os temas não estouram', (tester) async {
  tester.view.physicalSize = const Size(360, 640) * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final library = parseEducationalLibrary(_assetText('temas.json'));
  await tester.pumpWidget(MaterialApp(home: EducationalLibraryScreen(source: _FixedSource(library))));
  await tester.pumpAndSettle();
  final list = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(find.byKey(const Key('library_short_notice')), 200, scrollable: list);
  for (final topic in library.topics) {
    await tester.scrollUntilVisible(find.byKey(Key('library_topic_${topic.id}')), 200, scrollable: list);
    await tester.tap(find.byKey(Key('library_topic_${topic.id}')));
    await tester.pumpAndSettle();
    final scroll = find.descendant(of: find.byType(EducationalTopicScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('library_license')), 300, scrollable: scroll);
    await tester.pageBack();
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
});
```

Atenção ao detalhe: a 200 % numa tela de 320×568, o `library_short_notice` fica abaixo da área construída pelo `ListView`; um `expect(find.byKey(...), findsOneWidget)` sem rolar falha mesmo sem estouro.

---

## Inline 4 — apps/patient/lib/core/education/educational_library.dart:25 — sugestão

`www.gov.br` e `gov.br` cobrem todo o governo federal: uma fonte marcada "Ministério da Saúde" com `https://www.gov.br/<outro órgão>/...` passa no parser. Para a regra da P-07 ficar presa ao órgão, dá para exigir também o prefixo de caminho `/saude/` quando o host é `www.gov.br`/`gov.br` (e um teste com `https://www.gov.br/anvisa/...` recusado). Opcional; com dois temas, quem edita vê.

---

## Inline 5 — apps/patient/lib/core/education/educational_library.dart:186 — sugestão

`consultadoEm` e `revisao.data` aceitam qualquer texto não vazio; `_dataBr` deixa passar um formato diferente "como veio". Como a data de consulta é parte da citação, dá para recusar o que não for `AAAA-MM-DD` válido (`DateTime.tryParse` mais a regex que `_dataBr` já tem), com um teste. Opcional.

---

## Inline 6 — apps/patient/lib/app/educational_library_screens.dart:144 — sugestão

A data da revisão aparece em ISO ("Revisado por ... em 2026-12-01."), e a data de consulta logo abaixo em `dd/mm/aaaa` ("Consultado em 08/11/2026."). Passar `topic.review.date` por `_dataBr` deixa as duas iguais; o teste da linha 263 muda junto.

---

## Inline 7 — apps/patient/lib/app/app.dart:661 — registro

Nota para quem mesclar: este botão entra logo abaixo de "Escanear QR Code do ACS". A #161 acrescenta "Autoavaliação (sem cadastro)" na mesma região e a #157 reescreve a tela de login inteira. Quem mesclar por último precisa manter o `login_library_button` (e o teste que o usa) na tela nova. Nada a mudar nesta PR.

---

## Inline 8 — apps/patient/assets/conteudo_educativo/temas.json:47 — registro

**Para os preceptores (P-07), não para o autor:** o tema diz "O risco é maior entre outubro e maio." O piloto é em Boa Vista. Pergunta ao preceptor: esse período vale para Roraima? A frase fica como está, ganha uma versão regional ou sai?

---

## Inline 9 — apps/patient/assets/conteudo_educativo/temas.json:61 — registro

**Para os preceptores (P-07), não para o autor:** A segunda fonte do tema Dengue é um *Dicas em Saúde* da BVS de novembro de 2007. Perguntas ao preceptor: uma página de 2007 serve como fonte deste tema? Alguma afirmação do tema se apoia só nela, e não também na página atual do MS? Se for preciso trocar ou retirar essa fonte, o autor ajusta o `temas.json` depois da resposta.

---

## Geral — pedido aos preceptores (P-07)

Não avaliei o conteúdo clínico (P-07 dá essa revisão aos preceptores do PET-Saúde). Os dois temas estão `rascunho`, com selo na tela, e as fontes são oficiais. Não afirmo nada sobre a correção dos trechos abaixo; só aponto o que peço ao preceptor confirmar antes de trocar `rascunho` por `revisado`, além das duas perguntas dos inlines 8 e 9:

- `temas.json:12`: o preceptor confirma que "Ela não passa de uma pessoa para outra pelo contato, nem pela água ou pelos alimentos." é adequado como está escrito?
- `temas.json:19` e `:26`: o preceptor confirma "febre alta, de 39 °C a 40 °C, que começa de repente, junto com pelo menos dois destes sinais" e a lista de sinais de alarme? A lista está completa para o propósito educativo, e a linguagem serve a leigos?
- `temas.json:33`: o preceptor confirma os grupos de "Quem precisa de mais atenção" ("bebês e crianças de até 2 anos", "pessoas com mais de 65 anos")?
- `temas.json:39–40`: o preceptor confirma "O cuidado é repouso e beber bastante líquido" e o aviso sobre AAS e anti-inflamatórios? O texto deve dizer mais sobre o que tomar, ou fica só em "conforme a orientação do profissional de saúde"?
- `temas.json:48`: o preceptor confirma "A vacina contra a dengue foi incorporada ao SUS em dezembro de 2023" e a orientação de perguntar quem pode tomar?
- `temas.json:80`: o preceptor confirma o valor "140/90 mmHg (14 por 9) ou mais"?
- `temas.json:87–88`: depois dos sintomas de "Quando a pressão sobe muito", o texto traz só "Em caso de risco de vida, ligue 192 (SAMU)." O preceptor acha que cabe também "procure atendimento de urgência", como no tema Dengue?
- `temas.json:94`: o preceptor confirma a frequência de medição ("A partir dos 20 anos, meça pelo menos uma vez por ano. Se há casos de pressão alta na família, meça pelo menos duas vezes por ano.")?
- `temas.json:100`: o preceptor confirma a frase sobre remédios gratuitos e o programa Farmácia Popular "com receita dentro da validade"?
- `temas.json:106`: o preceptor confirma a orientação "beba álcool com moderação"?

Nenhuma dessas é bloqueante para o merge: o texto está marcado como rascunho e a issue continua aberta. Fica como entrada para a issue de continuação abaixo.

---

## Issues de continuação

### Issue 1 — Revisão dos temas Dengue e Pressão alta pelos preceptores (P-07)

**Objetivo**
A C-03 (#126, PR #156) entregou a biblioteca de saúde do app do paciente com dois temas em `rascunho` (Dengue e Pressão alta), parafraseados de páginas do Ministério da Saúde e da BVS. Pela P-07, cada versão do conteúdo passa pela revisão dos preceptores do PET-Saúde antes de ser publicada. Esta issue registra a revisão desses dois temas e as afirmações que a revisão de código separou para o preceptor.

**Critério de aceite**
- [ ] Lista de revisores definida na P-07 (`spec/escopo_projeto.md`).
- [ ] Cada afirmação listada no comentário geral da revisão da PR #156 conferida pelo preceptor (inclusive as perguntas sobre o período "entre outubro e maio" em Roraima e sobre a fonte da BVS de 2007).
- [ ] Temas revisados com `"situacao": "revisado"`, `revisores` e `data` em `apps/patient/assets/conteudo_educativo/temas.json`, e o teste "nenhum tema se declara revisado" atualizado.
- [ ] Nenhuma versão do app com tema em `rascunho` chega a participantes do piloto sem decisão registrada do dono.

**Referências**
IDs: C-03, RF20, P-07
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md
Origem: revisão da PR #156
Bloqueado por: P-07 (lista de temas e revisores)
