# PR #158 (C-06, "UBS" para grupo do piloto): parecer e comentários a publicar

Textos da revisão da PR #158 (`chore/c-06-ubs-para-grupo-piloto`, autor `Rosialdo`, base `develop`, commit `5595467`). Publicar só depois da aprovação do dono, com `gh pr review` (parecer) e `gh api repos/hbgit/SinalACS/pulls/158/comments` (inlines, um por chamada).

Veredito proposto: **Aprovar com observações** (`gh pr review --approve`). Não há bloqueante. Os pedidos são pequenos (restos de "UBS" que o participante ou o ACS ainda podem ler) e cabem nesta PR ou numa continuação.

---

## Parecer

Revisei a PR contra a issue #129 (C-06) e a linha C-06 de `docs/escopo/mudancas-de-codigo-recomendadas.md`. Todas as ocorrências citadas na linha C-06 foram trocadas, o texto novo é coerente ("grupo do piloto" no backoffice, "coordenação do piloto" para quem atende) e os testes novos prendem a ausência de "UBS" nos três apps.

| Critério da #129 | Evidência |
|---|---|
| Nenhum texto visível cita "UBS" nas linhas da C-06 | Paciente `app.dart:2020,2089` (diálogo de exclusão e consentimento de avisos); ACS `device_wiped_screen.dart:46-47`; admin `app.dart:341,716`, `admin_accounts.dart:421,507,681`, `audit_log_screen.dart:498`. Conferidos no diff. |
| Texto legal fica fora (#124) | `legal_documents.dart` não está no diff (8 ocorrências de "UBS" seguem lá, como a PR declara). |
| Testes de widget atualizados | `patient_app_mvp_test.dart` (diálogo de exclusão sem "UBS"), `escalation_ubs_test.dart` e `remote_wipe_ui_test.dart` (ACS), `admin_home_shell_test.dart` (percorre os seis destinos), `alerts_screen_test.dart`, `admin_mobile_smoke_test.dart`. |

**O que rodei em Linux** (worktree limpo do commit `5595467`):

- `flutter pub get`, `flutter analyze` e `flutter test` nos três apps. Analyze: só o aviso `asset_directory_does_not_exist` de `assets/certs/` (diretório gitignorado, não é da PR). Testes: paciente 334 passam; admin 483 passam; ACS 814 passam (8 min 29 s).
- Varredura residual nos três apps (`grep UBS|unidade de saúde|Unidade Básica`, sem `legal_documents.dart`): nenhuma string de interface restante nos apps, só comentários de código e identificadores. Ver pedido 1 para o que o ACS ainda lê por vias indiretas.
- `mqtt_tls_refused_test.dart` passa em Linux; a falha citada na PR é do ambiente Windows.
- CI: 9 de 9 verdes.

**Pontos que conferi e aprovo:**

- A troca de "enviado pela sua unidade de saúde" por "que você recebeu" na tela do código é coerente com a D4 e a PR explica o motivo.
- "Ligar para a coordenação do piloto": rótulo e mensagem de falha do contato trocados; o teste novo prende o rótulo. Botão só renomeado, a retirada fica na C-07 (declarado).
- Nome do arquivo `escalation_ubs_test.dart` e identificadores (`ubsId`, `ubsName`, `UbsContact`, `_callUbs`) não são texto visível; manter está certo, a tabela `ubs` fica para a C-06b.
- O teste novo do admin percorre Indicadores, Microáreas, Alertas, Auditoria, Pedidos do titular e Avisos com `find.textContaining('UBS')` igual a nada; é o tipo de guarda que evita regressão.
- Mock do admin "UBS Vila Nova" para "Grupo Vila Nova": dado sintético, sem efeito em produção.

**Pedidos (pequenos):** ver inlines 1 e 2.

**Sugestões:** inline 3.

**Registros (só documentam):**

- A tela do código de acesso que a PR edita (`apps/patient/lib/app/app.dart:600`) é reescrita pela #157 (C-05): a linha "Digite o código de 6 dígitos enviado pela sua unidade de saúde." some e dá lugar a "Digite o PIN deste aparelho para entrar." A #158 e a #157 conflitam nesse trecho; quem entrar depois resolve ficando com a versão da #157 (sem "unidade de saúde"). A troca desta PR nesse ponto perde efeito sem perda de cobertura.
- O nome fictício que o admin local mostra ("Grupo do piloto: UBS Desenvolvimento") vem do seed e de `ubsName`; some com a C-06b.

---

## Inline 1 — apps/acs/lib/app/app.dart:4017 — pedido

A mensagem de falha do contato foi trocada (linha 4017), mas dois caminhos ainda levam "UBS" ao ACS:

1. A linha 4008, logo acima, usa `contato.name`, que vem do servidor (hoje "UBS ..." no seed e em qualquer cadastro existente). Sugiro que o texto não dependa do nome: `'A coordenação do piloto ainda não cadastrou um telefone. Acione a coordenação.'` (o teste `escalation_ubs_test.dart:64,116` passa a procurar `A coordenação do piloto ainda não cadastrou um telefone`).
2. Quando o backend recusa, o `catch (BackendFailure)` mostra `falha.message`, e o servidor devolve `'Somente ACS consultam o contato da UBS.'` e `'UBS do ACS não encontrada.'` (`backend/sinalacs_server/lib/src/application/ubs/ubs_contact_service.dart:30,35`, repassados por `ubs_endpoint.dart:15`). São strings de backend, fora dos "três apps" da issue, mas chegam à tela. Ou entram aqui (duas linhas e o teste do backend que as compara, se houver) ou viram o item de continuação.

---

## Inline 2 — apps/acs/lib/app/device_wiped_screen.dart:46 — sugestão

O comentário de documentação da linha 12 ainda diz "com a equipe da UBS". Não é texto visível, mas descreve o texto desta tela, que a PR trocou; vale alinhar para "com a coordenação do piloto" para o próximo leitor não achar que a tela e o comentário divergem. O mesmo vale, se quiser, para os comentários `///` em `apps/acs/lib/app/app.dart:3978,3997`, `backend_client.dart:255` e `apps/admin/lib/core/data/admin_data_source.dart:696,703`. Nenhum é bloqueante.

---

## Inline 3 — apps/admin/lib/core/data/mock_admin_data_source.dart:112 — sugestão

`_ubsSintetica = 'Grupo Vila Nova'` está bem. O comentário logo acima (linha 111, "UBS sintética das linhas criadas pelo mock (nenhuma UBS real)") continua dizendo UBS; mesma observação do inline 2, só comentário.

---

## Geral — conflito com a #157 e ordem de merge

A #157 (C-05, QR + PIN) reescreve a tela de login do paciente e conflita com a #158 em `apps/patient/lib/app/app.dart`. Sugiro mergear a #158 primeiro (é pequena e sem dependência) e a #157 resolver o conflito ficando com o texto dela na tela de acesso. Nenhuma das duas depende da outra de outra forma.

## Geral — critério "nenhum texto visível" e `legal_documents.dart`

O corpo marca o critério como cumprido "exceto `legal_documents.dart`". Concordo, desde que a #124 (versão legal nova) o feche; vale a #129 só fechar quando as duas estiverem em `develop`, ou a issue declarar que fecha com a exceção.

---

## Issues de continuação

### Issue 1 — Textos de erro do backend que citam "UBS" chegam ao ACS (C-06)

Só abrir se o autor não incluir o pedido 1.2 nesta PR.

Corpo:

> **Contexto.** A C-06 (#129, PR #158) trocou "UBS" nos três apps, mas o ACS ainda lê duas mensagens do servidor: `'Somente ACS consultam o contato da UBS.'` e `'UBS do ACS não encontrada.'` (`backend/sinalacs_server/lib/src/application/ubs/ubs_contact_service.dart:30,35`), repassadas por `ubs_endpoint.dart` como `AlertPermissionException` e mostradas pelo botão "Ligar para a coordenação do piloto".
>
> **O que fazer.** Trocar por "coordenação do piloto" / "grupo do piloto", ajustar os testes do backend que comparam o texto e rodar `grep -rn "UBS" backend/sinalacs_server/lib` para listar outras strings devolvidas ao cliente. A tabela e os identificadores `ubs` ficam com a C-06b.
>
> **Critério.** Nenhuma mensagem devolvida por endpoint contém "UBS" no corpo; testes do backend verdes.
