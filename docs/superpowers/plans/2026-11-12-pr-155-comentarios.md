# PR #155 (C-02, aviso educativo): parecer e comentários a publicar

Textos da revisão da PR #155 (`feat/c-02-aviso-educativo`, autor `Rosialdo`, base `develop`, commit `eb78c64`). Publicar só depois da aprovação do dono, com `gh pr review` (parecer) e `gh api repos/hbgit/SinalACS/pulls/155/comments` (inlines). Plano: `2026-11-12-pr-155-revisao-aviso-educativo.md`.

Veredito proposto: **Aprovar com observações** (`gh pr review --approve`). Não há bloqueante. Os dois pedidos são pequenos (texto do `PROGRESS.md` e mensagem do commit) e não precisam de nova rodada.

---

## Parecer

Revisei a PR contra a issue #125, o escopo (`spec/escopo_projeto.md#aviso-educativo`) e o pedido de reaproveitar o `LocalProtectionNotice`. Os três critérios de aceite estão atendidos e provados por teste:

| Critério da #125 | Evidência |
|---|---|
| Primeira abertura exibe o aviso curto e só segue após confirmação | `test/educational_notice_test.dart` nos dois apps: "mostra o aviso curto e só segue para o login depois de Entendi" afirma que o login **não** está montado antes do toque e está depois, e que a loja gravou uma vez. |
| "Sobre" exibe o aviso longo, copiado literalmente | Os testes "as duas versões são cópia literal de spec/escopo_projeto.md" leem o escopo e comparam; no ACS, "o texto é o mesmo do app do paciente" compara as duas cópias. |
| Teste de widget para as duas telas nos dois apps | 9 `testWidgets` no paciente e 8 no ACS: primeira abertura, já confirmado, leitura que falha, ida e volta para "Sobre", "Sobre" pelo login (paciente) e pelo menu "Mais", 200 % de fonte nas duas telas. |

O `LocalProtectionNotice` entra em "Sobre" do paciente pelo mesmo widget de "Lembretes" e "Meus dados", como pedido na issue; no ACS fica de fora por desenho, e concordo.

**O que rodei em Linux** (Flutter estável, worktree limpo da branch):

- `flutter test` completo: paciente 347 passam; ACS 826 passam. `test/mqtt_tls_refused_test.dart` passa aqui (7/7), o que confirma que a falha descrita na PR é só do ambiente Windows.
- `flutter analyze` nos dois apps: só o aviso `asset_directory_does_not_exist` de `assets/certs/`, que é o diretório gitignorado que `scripts/dev/sync_dev_ca.sh` cria; não é desta PR.
- `bash scripts/qa/check_documentation_links.sh`: nada novo (o único "ausente" é `graphify-out`, gitignorado, em `AGENTS.md`, já assim em `develop`).
- CI: 9 de 9 verdes, inclusive `android-e2e`.

**Pontos que conferi no código e aprovo:**

- Portão no `home` do `MaterialApp`: no ACS, depois de `_WipeHold` (a limpeza remota da #81 não espera o aviso) e antes de `_loginScreen()`; o `AppLockGate` fica no `builder`, acima, e a recriação do gate por `_gateGeneration` não desmonta o `EducationalNoticeGate`, então a confirmação em memória sobrevive.
- Semântica de falha: leitura que falha mostra o aviso; gravação que falha não prende a pessoa (o estado muda antes do `await`). As duas metades têm teste (`_FailingStore`).
- O seam `educationalNoticeStoreFactory` só é atribuído na declaração e nos quatro `flutter_test_config.dart`; o teste "nada em lib/ a troca" prende o lado de produção. `geofence_gps_e2e.dart` é mesmo o único que roda por `flutter drive`.
- Backup Android: `sharedpref` continua excluído de cloud-backup e device-transfer; a confirmação some num aparelho novo, coerente com a #136.
- Acessibilidade: alvos 48×52/48×48, `Semantics(header: true)` nos títulos, só `onSurface`/`onSurfaceVariant` como cor de texto (nenhum fill clínico como texto).
- Duas cópias de `educational_notice.dart` sem pacote comum, travadas por teste: aceito, como `totp.dart`.

**Pedidos (pequenos, nesta PR):** ver os comentários inline em `PROGRESS.md` e o comentário sobre a mensagem do commit.

**Sugestões (opcionais):** prender `educationalNoticeVersion` ao texto; link "Sobre" no login do ACS.

**Registros (só documentam):** o portão de um toque antes da aba de urgência é decisão consciente que vale registrar; a regra do escopo "toda tela inicial" fica para a issue de continuação que abro ao aprovar.

---

## Inline 1 — PROGRESS.md:1936 — pedido

O `CONTRIBUTING.md` pede para não gravar contagens de testes nos documentos ("elas envelhecem a cada PR"). Sugiro deixar esta linha assim, e manter as contagens só no corpo da PR:

> - `flutter analyze` limpo e suítes verdes nos dois apps em Windows e em Linux (a diferença do Windows em `test/mqtt_tls_refused_test.dart` é do ambiente: a recusa TLS chega como `NoConnectionException`; a C-02 não toca no MQTT).

Rodei a suíte do ACS em Linux e `mqtt_tls_refused_test.dart` passa (7/7).

---

## Inline 2 — apps/patient/lib/core/legal/educational_notice.dart:31 — sugestão

`educationalNoticeVersion` é mantida à mão. O teste do escopo pega um texto divergente, mas não um *bump* esquecido: quem trocar o texto e não a versão deixa quem já confirmou sem ver o texto novo. Uma forma barata de prender as duas, sem mudar a API, é um teste em cada app que falhe quando o texto mudar sem a versão:

```dart
// `package:crypto` já é dependência dos dois apps.
test('trocar o texto exige trocar a versão', () {
  // Atualize os dois valores juntos quando o escopo mudar.
  expect(educationalNoticeVersion, '2026-11-01');
  final digest = sha256.convert(utf8.encode(educationalNoticeLong + educationalNoticeShort)).toString();
  expect(digest.substring(0, 12), '<valor atual>');
});
```

Alternativa: derivar a versão de um hash curto do texto em tempo de compilação. Opcional; pode ficar para depois.

---

## Inline 3 — apps/patient/lib/app/educational_notice_screens.dart:5 — registro

Só para deixar escrito: a aceitação dos termos foi feita como *prompt*, não portão, para o alerta de emergência nunca esperar. Aqui o portão vem antes de tudo, inclusive da aba de urgência, e acho que está certo: a #125 pede "só segue após confirmação", é um toque, e o texto curto já traz "Emergência: ligue 192". Vale uma frase no bloco do `PROGRESS.md` registrando essa decisão, para quem ler a #153/#137 não a tomar por descuido.

---

## Inline 4 — apps/acs/lib/app/app.dart:1040 — registro

Conferi a ordem: `_WipeHold` → `EducationalNoticeGate` → `_loginScreen()`, com o `AppLockGate` no `builder`, acima do Navigator. A recriação do gate por `ValueKey(_gateGeneration)` não toca no `home`, então o `State` do portão (e a confirmação em memória) sobrevive a "Entrar com senha". Nada a mudar.

---

## Geral — pedido e sugestão

**Pedido: mensagem do commit.** O corpo do commit `eb78c64` está truncado ("A confir..."). Antes do merge, um `git commit --amend` com o texto completo (pode ser o resumo da PR) e `push --force-with-lease`; ou, se preferir, faço o merge por *squash* com o corpo da PR como mensagem.

**Sugestão (opcional): "Sobre" no login do ACS.** O paciente tem o link no login (pilar A, sem sessão); no ACS, "Sobre" só aparece depois do login. A C-02 não exige, mas um `TextButton` igual ao do paciente deixaria o aviso longo alcançável antes de entrar.

**Registro (UX, sem pedido):** no paciente, a primeira abertura encadeia o diálogo de permissão de notificação (#153) e depois o aviso. Nada quebra; fica como nota para a #137.

---

## Issues de continuação

### Issue 1 — Aviso curto em toda tela inicial dos apps (RF21, regra do escopo)

## Objetivo
`spec/escopo_projeto.md#aviso-educativo` diz: "toda tela inicial dos apps, o texto legal e toda página de entrada da documentação exibem uma das duas versões, copiada literalmente". A C-02 (#125, PR #155) cobre a primeira abertura e "Sobre"; a tela de login dos apps do paciente e do agente segue sem o aviso nas aberturas seguintes.

## Critério de aceite
- [ ] A tela de login do paciente e a do agente mostram `educationalNoticeShort` (rodapé), copiado literalmente da constante já existente em `lib/core/legal/educational_notice.dart`.
- [ ] Teste de widget em cada app: o texto está no login e não estoura a 200 % de fonte.
- [ ] Pilar A: no paciente, visível sem sessão.

## Referências
IDs: RF21, C-02 (continuação)
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/escopo_projeto.md#aviso-educativo
Origem: revisão da PR #155
Bloqueado por: merge da #155

### Issue 2 — (só se o dono pedir) Versão do aviso presa ao texto

Transformar a sugestão do Inline 2 em pedido: teste em cada app que falha quando `educationalNoticeLong`/`Short` mudam sem `educationalNoticeVersion`. Sem corpo até o dono decidir.
