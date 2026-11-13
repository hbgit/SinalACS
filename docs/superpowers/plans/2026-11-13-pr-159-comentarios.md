# PR #159 (#153, permissão de notificação na partida): parecer e comentários a publicar

Textos da revisão da PR #159 (`fix/issue-153-permissao-notificacao`, autor `vinimartinsufrr`, base `develop`, commit `db1b330`). Publicar só depois da aprovação do dono, com `gh pr review` (parecer) e `gh api repos/hbgit/SinalACS/pulls/159/comments` (inlines, um por chamada). Plano: `2026-11-13-prs-156-163-revisao.md`.

Veredito proposto: **Comentar (pedidos antes do merge)** (`gh pr review --comment`). Não há bloqueante: a correção da #153 está certa, provada por teste e não relaxa o INV-03. Os dois pedidos são de escopo pequeno. O mais importante é que, ao tirar o pedido da partida, os avisos da equipe (RF14, push FCM) ficaram sem nenhum caminho que peça a permissão. O outro é a frase errada sobre o manifest, que a PR edita sem corrigir.

---

## Parecer

Revisei a PR contra a issue #153 (achado da verificação da #136, PR #150), o INV-03 do piloto ("pedido enviado nunca some") e o botão "Ligar 192". Os três critérios de aceite estão atendidos e provados por teste:

| Critério da #153 | Evidência |
|---|---|
| O `runApp` não espera a resposta da permissão; o pedido acontece depois do primeiro quadro ou ao criar um lembrete | `apps/patient/lib/main.dart`: o `await ...requestNotificationsPermission()` saiu e nada mais na partida chama o plugin para isso. O único ponto de pedido agora é `ReminderScheduler.requestPermission()` (`lib/core/reminders/reminder_scheduler.dart:221`), chamado sem `await` em `lib/app/app.dart:2890` (reativar) e `:2948` (criar/editar), sempre **depois** de salvar, agendar e do `setState`. |
| Recusa ou adiamento não bloqueia nenhuma tela, em especial a de urgência | O pedido só nasce de um ato da pessoa na tela de Lembretes, nunca na partida nem sobre a aba de urgência. `requestPermission()` engole qualquer falha (`reminder_scheduler.dart:221-228`), provado por `test/reminders/reminder_scheduler_test.dart` ("requestPermission repassa ao canal e nunca lança"). O reagendamento do aquecimento (`rescheduleAll`) não pede: `test/storage/startup_warmup_test.dart` afirma `permissionRequests == 0`. |
| Teste que prova que a tela inicial é desenhada com o pedido pendente | `test/main_notification_permission_test.dart` sobe o `main()` **real**, com Android simulado e `requestNotificationsPermission` pendente para sempre, e acha `cpf_field`. Pus o `main.dart` da `develop` no lugar e o teste **reprova** com a mensagem esperada ("o main() não pode esperar o diálogo de permissão"); com o da PR, passa. |

**O que rodei em Linux** (Flutter estável, worktree limpo da branch, `apps/patient`; log em `pr159-verificacao.log`):

- `flutter test test/main_notification_permission_test.dart`: `+1: All tests passed!`
- `flutter test test/reminders/reminder_scheduler_test.dart test/storage/startup_warmup_test.dart`: `+12: All tests passed!`
- `flutter test` completo: `+336: All tests passed!` (bate com o corpo da PR).
- Prova do vermelho: o mesmo teste novo com `lib/main.dart` da `develop` reprova (exit 1, mensagem do `reason`). Restaurei o arquivo; nada foi commitado.
- `flutter analyze`: só o aviso `asset_directory_does_not_exist` de `assets/certs/`, diretório gitignorado criado por `scripts/dev/sync_dev_ca.sh`; não é desta PR.
- `bash scripts/qa/check_documentation_links.sh`: só o "link local ausente: graphify-out (AGENTS.md)", gitignorado e já assim em `develop`.
- CI: 9 de 9 verdes, inclusive `android-e2e`.
- **Emulador: não rodei.** Não havia aparelho ligado e a prova desta revisão é a mesma do autor, a de VM. O comportamento real do `GrantPermissionsActivity` no Android 13+ (diálogo só ao criar/reativar, nenhum na primeira abertura) continua sem prova em aparelho.

**Pontos que conferi no código e aprovo:**

- A escolha "no lembrete, não depois do primeiro quadro" é melhor que a alternativa da issue: um diálogo logo após o primeiro quadro ainda cobriria a aba de urgência (destino inicial `PatientDestination.emergency`) até a resposta.
- `unawaited(...)` depois do `setState` e dentro do `try`: a lista já mostra o lembrete antes do diálogo, e uma recusa não desfaz nada. Como `requestPermission()` nunca lança, o `catch` da tela não vira mensagem de erro falsa.
- Pausar e excluir não pedem; reativar pede. Os testes de `patient_app_mvp_test.dart` cobrem os quatro casos.
- Os duplos de `ReminderScheduler` em quatro arquivos de teste ganharam `requestPermission()`; o `_ThrowingReminderScheduler` não lança nele, coerente com o contrato.
- O teste do `main()` não espera o `main()` antes da asserção, de propósito: com o defeito de volta ele reprova em vez de ficar pendurado. Os mocks de canal são desfeitos no `tearDown`, e `debugPrint`/`debugDefaultTargetPlatformOverride` no `finally`.

**Pedidos (nesta PR):**

1. **Avisos da equipe (RF14) ficaram sem pedido de permissão.** O pedido da partida também servia ao push FCM: o próprio `AndroidManifest.xml` do paciente (linhas 18-21) diz que, sem `POST_NOTIFICATIONS`, "o token ainda é obtido e registrado, mas a notificação do aviso comunitário não é exibida (RF14)", e que "quem a pede em tempo de execução é `main.dart`". Com a PR, quem consente com "Avisos da equipe de saúde" e nunca cria um lembrete nunca vê o diálogo, e os avisos somem em silêncio no Android 13+. O `scripts/qa/push_e2e.sh:200` concede a permissão por `pm grant`, então a CI não pega isso. Peço pedir a permissão também quando o consentimento de push é concedido (em `_changeConsent`, junto do `registerPushDevice` de `app.dart:1964`; no cadastro, onde `_pushConsent` dispara `registerPushDevice`), sem `await`, como nos lembretes. Se preferir não fazer agora, registre o limite no `PROGRESS.md` e no comentário do manifest e abra a issue de continuação abaixo.
2. **A frase sobre o manifest continua errada.** `docs/publicacao-google-play.md` diz que "o manifest principal não declara" `POST_NOTIFICATIONS`, mas `apps/patient/android/app/src/main/AndroidManifest.xml:22` a declara desde a #136 (`ded26f3`). A PR edita as duas frases e mantém o erro; é uma linha em cada uma (inlines 1 e 2).

**Sugestões (opcionais):** atualizar o comentário do manifest (fora do diff, ver Geral); ajustar as outras menções do mesmo erro no guia.

**Registros:** quem atualiza com lembretes ativos e nunca respondeu ao diálogo só o verá ao mexer num lembrete. Está no `PROGRESS.md` e é aceitável. Junto do pedido 1, cabe na mesma issue de continuação, e não pede issue própria. A prova é só de VM.

---

## Inline 1 — docs/publicacao-google-play.md:130 — pedido

Esta frase continua dizendo que o manifest principal não declara `POST_NOTIFICATIONS`, mas `apps/patient/android/app/src/main/AndroidManifest.xml:22` já a declara (entrou na #136, `ded26f3`). Como a PR já edita a frase, sugiro corrigir aqui mesmo:

> - **`POST_NOTIFICATIONS`:** o Paciente declara a permissão no manifest principal e chama `requestNotificationsPermission()` ao criar ou ativar um lembrete (desde a #153, não mais em `lib/main.dart`). Conferir no manifest mesclado.

---

## Inline 2 — docs/publicacao-google-play.md:523 — pedido

O mesmo erro do inline 1. Proposta:

> **Notificações (Paciente).** O app depende de `flutter_local_notifications`, declara `POST_NOTIFICATIONS` no manifest principal e chama `requestNotificationsPermission()` ao criar ou ativar um lembrete (#153). Com `targetSdk = 36`, em Android 13 ou superior as notificações só aparecem depois que a pessoa concede a permissão. Conferir no manifest mesclado do release (seção 2.6).

As linhas 503, 697, 805, 853, 889 e 919 repetem a premissa ("não declarada no `main`"). Estão fora do diff; se for corrigir, vale passar por elas no mesmo commit.

---

## Inline 3 — apps/patient/lib/core/reminders/reminder_scheduler.dart:25 — pedido

"Só é chamada por um ato da pessoa na tela de lembretes": hoje este é o **único** ponto que pede `POST_NOTIFICATIONS`, e a mesma permissão vale para o push dos avisos (RF14). O comentário do `AndroidManifest.xml` (linhas 18-21) ainda diz que o pedido está em `main.dart` e que, sem ele, "a notificação do aviso comunitário não é exibida". Quem dá o consentimento "Avisos da equipe de saúde" e não cria lembrete nunca vê o diálogo. Proponho chamar `unawaited(reminders.scheduler.requestPermission())` também quando `segmentedPush` é concedido (`app.dart:1964`, e no cadastro, onde `_pushConsent` dispara `registerPushDevice`). É um ato da pessoa, fora da aba de urgência. Se ficar para depois, ajuste este comentário e o do manifest para dizer que o RF14 depende do pedido feito nos lembretes.

---

## Inline 4 — apps/patient/test/main_notification_permission_test.dart:68 — registro

Conferi o vermelho: com o `lib/main.dart` da `develop` no lugar, este teste reprova com "o main() não pode esperar o diálogo de permissão"; com o da PR, passa. A tela desenhada é o login (`cpf_field`), a primeira para quem não tem sessão, o que basta para o critério "nenhuma tela presa ao diálogo". A prova continua só de VM: nem o autor nem esta revisão rodaram em emulador.

---

## Inline 5 — PROGRESS.md:1933 — registro

Concordo com o limite de quem atualiza com lembretes ativos. Se o pedido do inline 3 ficar para depois, vale acrescentar aqui o segundo limite: "quem consente com os avisos (RF14) e não cria lembrete não recebe o diálogo, e os avisos não aparecem no Android 13+ (o `push_e2e.sh` concede a permissão por `pm grant`, então não pega isso)".

---

## Geral — comentário do manifest fora do diff

`apps/patient/android/app/src/main/AndroidManifest.xml:18-21` diz "Quem a pede em tempo de execução é `main.dart`, por `requestNotificationsPermission()`". Isso deixou de ser verdade com esta PR. O arquivo não está no diff, por isso o comentário vai aqui: vale trocar para "a tela de lembretes (`ReminderScheduler.requestPermission`, #153)" e, se o pedido 1 for feito, citar também o consentimento de avisos.

## Geral — conflitos

A PR conflita com a #160 e a #157 só no `PROGRESS.md` (as duas acrescentam uma seção no mesmo ponto; basta manter as duas). A ordem de merge fica com o dono.

---

## Issues de continuação

### Issue 1 — Paciente: pedir POST_NOTIFICATIONS fora dos lembretes (avisos RF14 e quem já tem lembretes)

Só abrir se o pedido 1 da PR #159 não for feito nela.

**Objetivo**
Depois da #153, o app do paciente só pede `POST_NOTIFICATIONS` ao criar, editar ou reativar um lembrete. A mesma permissão vale para o push dos avisos da equipe (RF14, FCM). No Android 13+, quem consente com "Avisos da equipe de saúde" e nunca cria um lembrete nunca vê o diálogo, e os avisos não aparecem na bandeja. Quem atualiza o app com lembretes ativos e nunca respondeu ao diálogo também não é perguntado.

**Critério de aceite**
- [ ] Conceder o consentimento `segmentedPush` (Meus Dados e cadastro) pede a permissão sem `await`, nunca sobre a aba de urgência.
- [ ] A tela de Lembretes, com lembrete ativo e a permissão negada ou não respondida (`areNotificationsEnabled()` do plugin), mostra um aviso com ação para pedir, sem bloquear a lista.
- [ ] O comentário de `apps/patient/android/app/src/main/AndroidManifest.xml` sobre quem pede a permissão está atualizado.
- [ ] Teste de widget para os dois pontos. A prova em emulador sem `pm grant` (o `push_e2e.sh` concede a permissão hoje) fica registrada como feita ou pendente.

**Referências**
IDs: RF06, RF14, INV-03
Origem: revisão da PR #159 (#153)
Bloqueado por: —
