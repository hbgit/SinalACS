# ISSUE #103: notificação FCM fora da bandeja no `android-e2e`. Plano de investigação e correção

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** descobrir por que o aviso aceito pelo FCM (`recipients=1 accepted=1 rc=0`) às vezes não aparece em `dumpsys notification` no emulador da CI e corrigir a causa, sem mascarar o sintoma.

**Architecture:** a investigação é guiada por hipóteses e segue o custo. Primeiro vem o que se resolve lendo logs e código (Fase 0). Depois, o emulador local com a mesma imagem da CI, usado também para registrar a "assinatura" de cada desfecho em logcat/dumpsys (Fase 1). Em seguida, uma coleta de diagnóstico com redação de segredos, testada em `scripts/qa/ci_push_e2e_test.sh` (Fase 2), e execuções na CI até capturar falhas (Fase 3). A causa confirmada escolhe um ramo da árvore de decisão (Fase 4), e cada correção é feita em TDD e validada pelo critério de aceite (Fase 5).

**Tech Stack:** bash (`scripts/qa/*.sh`), adb/`dumpsys`/`logcat`, Gorush 1.22.0 (`appleboy/gorush`), FCM HTTP v1, `firebase-messaging:25.1.3` sem `FirebaseMessagingService` próprio, `reactivecircus/android-emulator-runner@v2` (API 36, `google_apis`, x86_64, pixel_7, `-gpu swiftshader_indirect`), GitHub Actions (`gh`).

**Spec:** issue #103 (`gh issue view 103 --comments`). O comentário de 26/10 registra que o `develop` 377efc3 (execução 40275396602) passou **com** o passo de push, ou seja, a falha é intermitente.

## Global Constraints

- Nenhuma espera maior em `na_bandeja`, nenhum reenvio e nenhuma retentativa antes de a causa estar registrada na issue. Se a causa justificar alguma delas, a justificativa fica em comentário no script **e** na issue.
- `android-e2e` continua informativo e fora de `CHECKS_OBRIGATORIOS` (`scripts/qa/ci_invariants.sh`), salvo decisão explícita registrada na #103.
- Os artefatos da CI são públicos. Nenhum token FCM, chave de conta de serviço, `private_key`, `project_id` ou `project_number` pode aparecer neles, e a coleta é *fail-closed*: um arquivo em que a verificação pós-redação ainda ache um segredo é apagado, não publicado.
- Nada de logs do Gorush nos artefatos, porque o access log do 1.22.0 pode trazer os tokens.
- `scripts/qa/ci_invariants.sh` e `scripts/qa/ci_invariants_test.sh` continuam verdes: `actions/upload-artifact@v7`, `runs-on: ubuntu-24.04`, chave do AVD contendo `google_apis` e terminando em `-ubuntu-24.04`, passos de decodificação imediatamente antes do E2E, limpeza `if: always()`.
- Toda mudança em `scripts/qa/push_e2e.sh`, `scripts/qa/ci_push_e2e.sh` ou nos novos `scripts/qa/lib_push_diag.sh` é coberta em `scripts/qa/ci_push_e2e_test.sh`.
- Commits, comentários e textos em português, no formato `tipo(escopo): descrição (#103)`, sem atribuição de IA (CLAUDE.md do projeto).
- Branch de trabalho: `fix/issue-103-push-bandeja`, criada a partir de `develop`.

## Review Focus

1. **Token ou segredo vazando no artefato público.** Um logcat do GMS ou a saída do `flutter test` com o token, e o `project_id` vindo de `google-services.json`, têm de sair redigidos. Teste: `diag_redigir` com token fictício, literal e regex (Task 4).
2. **A coleta derrubar o resultado do script.** Um `adb` travado ou um emulador morto na coleta não pode trocar o exit 1 por outro código nem pendurar o job até o timeout de 60 min. Teste: `diag_coletar` com `adb` stub que falha ou demora preserva o exit (Task 5).
3. **Observação tardia transformada em sucesso.** A observação de até 180 s após a falha serve só para diagnóstico: se o texto aparecer, o script sai com 1 do mesmo jeito. Teste na Task 5.
4. **Classificação errada por bloco de outro pacote.** Um título igual em notificação de outro `pkg`, ou o `pkg=` do app seguido do bloco de outra notificação, não pode contar como "exibida". Teste: `diag_bloco_do_app` com dump de dois pacotes (Task 4).
5. **Coleta rodando no caminho verde.** No verde ela não gera artefato nem custa tempo. O upload no workflow fica sob `if: failure()`, e o teste confere que o caminho feliz não chama `diag_coletar` (Task 5).

---

## Hipóteses

Cada hipótese aponta para um dos três desfechos observáveis que a coleta da Fase 2 separa: **A** = não chegou ao aparelho, **B** = chegou mas não foi exibida, **C** = foi exibida mas o script não encontrou.

| Id | Hipótese | Desfecho | Evidência que confirma | Evidência que refuta |
|---|---|---|---|---|
| H1 | Mudança externa (FCM, imagem `google_apis` em cache, runner) | A ou B | `ro.build.fingerprint`/versão do GMS ou entrada do cache `avd-36-…` diferentes entre verdes e vermelhas | mesma imagem e mesmo GMS nas verdes e nas vermelhas (o verde de 377efc3 já enfraquece) |
| H2a | `POST_NOTIFICATIONS` não concedida no envio (`pm grant … \|\| true` engole a falha) | B | `dumpsys package` com `POST_NOTIFICATIONS: granted=false`, ou logcat do `NotificationService` recusando o pacote | `granted=true` registrado antes do envio |
| H2b | Canal/estado do GMS (canal `fcm_fallback_notification_channel` bloqueado ou ausente) | B | canal com `importance=NONE`, ou logcat "No Channel found" | canal presente e com importância > 0 |
| H2c | Renderização GL do emulador | **nenhum, sozinha** | `dumpsys notification` reflete o `NotificationManagerService` no `system_server`, que não depende da GPU. Só conta se o SystemUI ou o `system_server` morreram (logcat `FATAL`/`ANR` no intervalo) | ausência de crash no intervalo, porque aí os erros de GL são ruído |
| H3 | `grep -A30 "pkg=$app"` não alcança `android.title=` | C | título presente no bloco do app do dump completo, a mais de 30 linhas do `pkg=` | título ausente do dump completo |
| H4 | App em primeiro plano no envio: sem `FirebaseMessagingService` próprio, o SDK entrega uma mensagem *notification* a `onMessageReceived` vazio e nada vai à bandeja | B | `mResumedActivity` do app no instante do envio e logcat com a mensagem recebida | atividade em foco é o launcher |
| H5 | Payload: o Gorush 1.22.0 manda `notification` + `data` sem `android.priority`, e uma prioridade normal sujeita a adiamento atrasa a entrega | A (tardia) | entrega só depois dos 45 s na observação tardia, com o payload efetivo sem `priority: HIGH` | entrega em segundos nas falhas, ou payload já com prioridade alta |
| H6 | App parado ou em standby: o processo foi morto ou ficou em `stopped=true`, e o FCM não entrega a app parado | A | `dumpsys package` com `stopped=true`, ou `am get-standby-bucket` ≥ 40 (rare/restricted) | `stopped=false` e bucket ativo |
| H7 | O `flutter test` de segurar o app terminou antes do envio, o app foi desinstalado e o token morreu | A | `/tmp/push_e2e_hold.txt` com falha ou fim antes do envio, `pm list packages` sem o app no envio | app instalado e `PUSH_E2E_REGISTERED` sem fim até a coleta |
| H8 | A conexão do GMS com o FCM (MCS, `mtalk.google.com:5228`) não está de pé: o snapshot restaurado traz a conexão antiga, e a reconexão com *backoff* passa de 45 s. O token vem por HTTPS, então o registro funciona mesmo assim | A (tardia ou nunca) | estado da conexão FCM no `dumpsys` do GMS desconectado ou reconectando no envio, e chegada tardia logo após reconectar | conexão ativa no envio |
| H9 | `Terminated` vem do próprio `cleanup` (`parar_arvore "$hold_pid"` sob `set -m`) e não é causa | nenhum | no log, `Terminated` **depois** de `FALHOU` | `Terminated` antes do envio, o que reabre H7 |

---

## Fase 0: sem rodar nada

### Task 1: ler as execuções verdes e vermelhas

**Files:**
- Create: `docs/superpowers/plans/2026-10-26-issue-103-fase0.log` (notas e trechos, sem segredos)

- [ ] **Step 1: baixar os logs.** Rode `gh run view <id> --log > $SCRATCH/run-<id>.log` para 40231780331 (verde), 40237097203 (vermelha), 40251805400 tentativas 1 e 2 (`gh run view 40251805400 --attempt N --log`) e 40275396602 (verde).
- [ ] **Step 2: H1, cache e imagem.** Em cada log, confira se o passo "Gera o snapshot do AVD para o cache" rodou ou foi pulado (`cache-hit`), procure `Cache restored from key: avd-36-` e a linha do sdkmanager com a revisão de `system-images;android-36;google_apis;x86_64`. Rode também `gh cache list --key avd-36 --json key,createdAt,lastAccessedAt`.
  - Se H1 for verdadeira, a entrada foi recriada entre 20:39 e 21:47 de 25/10, ou a revisão difere. **Próximo passo:** priorize o ramo "imagem" da Fase 4 e mantenha a Fase 2 para confirmar.
  - Se for falsa, o cache é o mesmo e a revisão também. Isso registra que a imagem não muda entre verde e vermelho. **Próximo passo:** siga para a Task 2.
- [ ] **Step 3: H9, origem do `Terminated`.** Localize `Terminated` em relação a `FALHOU: título não está na bandeja` e ao fim do passo.
  - Se H9 for verdadeira (`Terminated` aparece depois de `FALHOU`), registre "Terminated = cleanup" e descarte essa pista.
  - Se aparecer antes do envio, H7 sobe para o topo. **Próximo passo:** Task 3, Step 5 primeiro.
- [ ] **Step 4: tempos.** Meça os carimbos do GitHub entre `tokens no banco`, `recipients=1` e `FALHOU`. Se o intervalo envio→`FALHOU` passar muito de 45 s, cada `dumpsys` está lento, e isso entra como fato na Task 9. Compare com as verdes o intervalo entre `== registro` e `tokens no banco` (carga do emulador).
- [ ] **Step 5: erros GL e crash.** No intervalo envio→`FALHOU` das vermelhas, procure `FATAL EXCEPTION`, `ANR in`, `system_server` e `com.android.systemui`.
  - Se nada aparecer, H2c fica descartada como causa isolada.
  - Se houver crash do SystemUI ou do `system_server`, H2c sobe. **Próximo passo:** Task 3, Step 6.
- [ ] **Step 6: registrar e commitar.** Escreva no `.log` uma linha por hipótese ("mantida/descartada/subiu", com o trecho que prova). Depois:

```bash
git add docs/superpowers/plans/2026-10-26-issue-103-fase0.log
git commit -m "docs(ci): fase 0 da investigação do push na bandeja (#103)"
```

### Task 2: payload efetivo do Gorush (H5) e o caminho da exibição (H4)

**Files:**
- Modify: `docs/superpowers/plans/2026-10-26-issue-103-fase0.log`

- [ ] **Step 1:** leia em `github.com/appleboy/gorush` v1.22.0, arquivo `notify/notification_fcm.go`, como `GetAndroidNotification` monta a mensagem v1 a partir de `title`/`message`/`data` sem `priority`. Registre se sai um bloco `notification`, um `data` ou os dois, e qual `android.priority` resulta (ausente significa o padrão do FCM).
- [ ] **Step 2:** confirme na documentação do FCM ("Set and manage Android message priority") a prioridade padrão de mensagens com `notification`. Registre a URL e a frase.
  - Se a prioridade efetiva for NORMAL, H5 continua viva. **Próximo passo:** a Task 7, Step 4, mede a chegada tardia.
  - Se for HIGH, H5 fica descartada.
- [ ] **Step 3: H4, por leitura.** Confirme que `apps/patient/android/app/src/main/AndroidManifest.xml` não declara `FirebaseMessagingService` nem `com.google.firebase.messaging.default_notification_channel_id`, e que o app não depende de `firebase_messaging` (Dart). Fato esperado: em primeiro plano, a mensagem chega ao serviço padrão do SDK, que não exibe nada. Em segundo plano, o SDK exibe no canal `fcm_fallback_notification_channel`.
- [ ] **Step 4: commit** (mesmo arquivo, `docs(ci): payload do Gorush e caminho da exibição (#103)`).

---

## Fase 1: emulador local igual ao da CI

### Task 3: AVD igual ao da CI, linha de base e assinaturas dos desfechos

O emulador local atual (`Medium_Phone`, API 36, `google_apis_playstore`, build `user`) **não** é igual ao da CI (`google_apis`, build `userdebug`). Esta tarefa cria um igual e registra como cada desfecho aparece nos logs, para que a classificação da Task 4 use assinaturas medidas e não supostas.

**Files:**
- Create: `docs/superpowers/plans/2026-10-26-issue-103-assinaturas.md` (assinaturas e linha de base; sem tokens)

- [ ] **Step 1: criar o AVD.**

```bash
sdkmanager "system-images;android-36;google_apis;x86_64"
avdmanager create avd -n sinalacs_ci36 -k "system-images;android-36;google_apis;x86_64" -d pixel_7
emulator -avd sinalacs_ci36 -no-window -no-audio -gpu swiftshader_indirect -no-boot-anim -port 5554 &
```

Antes, feche o `Medium_Phone`, porque o script exige `emulator-5554`. Registre `getprop ro.build.fingerprint`, a versão do GMS (`dumpsys package com.google.android.gms | grep versionName`) e as mesmas linhas do log da CI, da Task 1.
- [ ] **Step 2: linha de base.** Rode `./scripts/qa/push_e2e.sh` 5 vezes, com `adb logcat -G 16M` e `adb shell setprop log.tag.FirebaseMessaging VERBOSE` antes de cada rodada, e anote verde ou vermelho. Logo antes de cada envio, registre o estado de `POST_NOTIFICATIONS` (`dumpsys package br.com.prismrr.sinalacs.patient | grep POST_NOTIFICATIONS`) e os canais do app (`dumpsys notification | grep -A3 'NotificationChannel.*fcm_fallback'`). Rode também uma vez na ordem da CI (`./scripts/qa/e2e.sh --emulator --keep` seguido do push), para ter a mesma carga prévia.
  - Se algum vermelho aparecer, a falha reproduz localmente. **Próximo passo:** os Steps 3–7 classificam o caso local, e a Fase 3 vira confirmação.
  - Se tudo ficar verde, registre as diferenças que restam em relação à CI: snapshot restaurado (vs. boot frio local), rede de saída do runner (porta 5228), CPU/KVM do runner, carga do job e `-no-snapshot-save`. Essas diferenças são o alvo dos Steps 6–7 e da Fase 3.
- [ ] **Step 3: assinatura do caminho verde e H3.** Numa rodada verde, salve `dumpsys notification --noredact` completo e o logcat (`FirebaseMessaging|FCM|GCM|NotificationService|<pid do app>`). Meça quantas linhas separam `pkg=br.com.prismrr.sinalacs.patient` de `android.title=` no `NotificationRecord`. Registre a linha de logcat que marca "mensagem recebida pelo app" e a que marca "notificação postada"; elas serão `DIAG_MARCA_RECEBIDA` e `DIAG_MARCA_POSTADA`.
  - Se a distância passar de 30 linhas, H3 está confirmada só por medição, e a Fase 4 C se aplica independentemente da causa da intermitência.
  - Se ficar abaixo de 30 linhas, registre a margem. H3 continua possível apenas se o bloco variar (por exemplo, com mais *extras*).
- [ ] **Step 4: assinatura de H4 (primeiro plano).** Reproduza à mão os passos de `push_e2e.sh` (registro com hold, depois o envio por `apps/acs/tool/send_notice.dart`), mas com `adb shell monkey -p br.com.prismrr.sinalacs.patient 1` no lugar do `KEYCODE_HOME`. Registre `dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity'`, o logcat e o dump.
  - Se H4 for o mecanismo, a mensagem é recebida e nada é postado. Isso vira a assinatura "B-primeiro plano".
  - Se for postada mesmo assim, H4 fica descartada.
- [ ] **Step 5: assinatura de H2a e H7.** Faça uma rodada manual com `adb shell pm revoke … POST_NOTIFICATIONS` depois do registro (o *revoke* mata o processo, e o FCM tem de acordá-lo) e registre a linha do `NotificationService`. Faça outra rodada com o `flutter test` de hold morto antes do envio (`parar_arvore`) e registre o que o FCM e o logcat mostram (app desinstalado).
- [ ] **Step 6: assinatura de H8 (rede/MCS).** Descubra qual `dumpsys` mostra o estado da conexão FCM nesta imagem. Candidatos, nesta ordem: `dumpsys activity service com.google.android.gms/.gcm.GcmService` e `dumpsys activity service com.google.android.gms | grep -iE 'mcs|connected|heartbeat'`. Registre o comando que funciona como `DIAG_CMD_CONEXAO_FCM`. Depois corte a rede (`adb shell svc wifi disable; adb shell svc data disable`), envie, religue após 60 s e meça quando a notificação aparece.
  - Se a notificação só chegar após a reconexão, essa é a assinatura "A-tardia".
  - Se nunca chegar, essa é a assinatura "A-nunca".
- [ ] **Step 7: H8 com snapshot.** Crie um snapshot (`adb emu avd snapshot save ci`), espere ≥ 30 min, reinicie com `-snapshot ci -no-snapshot-save` (como a CI faz) e rode `push_e2e.sh` em seguida, 3 vezes.
  - Se der vermelho com a conexão FCM caída no envio, H8 está reproduzida localmente. **Próximo passo:** a Fase 3 só confirma, e a Fase 4 A-MCS se aplica.
  - Se ficar verde, H8 continua aberta, porque a rede do runner é diferente. Siga para a Fase 2.
- [ ] **Step 8: commit** do `assinaturas.md`, com as constantes `DIAG_MARCA_RECEBIDA`, `DIAG_MARCA_POSTADA` e `DIAG_CMD_CONEXAO_FCM` copiadas literalmente (`docs(ci): assinaturas dos desfechos do push no emulador (#103)`).

---

## Fase 2: coleta de diagnóstico (TDD)

### Task 4: `scripts/qa/lib_push_diag.sh`, com redação, recorte do bloco e classificação

**Files:**
- Create: `scripts/qa/lib_push_diag.sh` (biblioteca *sourced*, no padrão de `scripts/qa/lib_rele.sh`)
- Create: `scripts/qa/fixtures/push_diag/` com `dump_um_app.txt`, `dump_dois_pacotes.txt`, `dump_titulo_longe.txt` (título a 45 linhas do `pkg=`), `logcat_recebida.txt` e `logcat_vazio.txt`. São sintéticos, montados a partir das assinaturas da Task 3, com texto de teste e sem tokens reais.
- Test: `scripts/qa/ci_push_e2e_test.sh` (novo bloco `# ---- #103: diagnóstico do push ----`)

**Interfaces:**
- Consumes: as constantes da Task 3 (`DIAG_MARCA_RECEBIDA`, `DIAG_MARCA_POSTADA`, `DIAG_CMD_CONEXAO_FCM`).
- Produces:
  - `diag_redigir`: stdin → stdout. Troca cada literal da variável `PUSH_DIAG_SEGREDOS` (uma por linha) por `<redigido>`, e o regex `[A-Za-z0-9_-]{11,}:APA91[A-Za-z0-9_-]{30,}` por `<token-fcm>`.
  - `diag_verificar_limpo <arquivo>`: retorna 0 se o arquivo está limpo. Se ainda houver um literal de `PUSH_DIAG_SEGREDOS` ou um `APA91`, apaga o arquivo, escreve `<arquivo>.REMOVIDO` com o motivo (sem o segredo) e retorna 1.
  - `diag_bloco_do_app <dump> <pkg>`: imprime só os `NotificationRecord` cujo cabeçalho tem `pkg=<pkg>`. O bloco vai de uma linha `NotificationRecord(` até a próxima.
  - `diag_classificar <dump> <logcat> <pkg> <texto>`: imprime exatamente um destes valores: `exibida_encontrada`, `exibida_nao_encontrada`, `chegou_nao_exibida`, `nao_chegou`. Regra: se o texto estiver no bloco do app, devolve `exibida_encontrada` quando também estiver a ≤ 30 linhas do `pkg=` (o que o `grep -A30` acha) e `exibida_nao_encontrada` quando não estiver. Senão, `chegou_nao_exibida` se o logcat tiver `DIAG_MARCA_RECEBIDA`, e `nao_chegou` caso contrário.

- [ ] **Step 1: escrever os testes que falham** em `ci_push_e2e_test.sh`, com `source "$repo/scripts/qa/lib_push_diag.sh"` num subshell:
  - `"#103 redação: token fictício no formato FCM vira <token-fcm>"`: entrada `abcDEF12345:APA91` seguido de 140 caracteres; a saída não contém `APA91` e contém `<token-fcm>`.
  - `"#103 redação: literal de PUSH_DIAG_SEGREDOS (project_id) vira <redigido>"` com `proj-secreto-123`.
  - `"#103 verificação fail-closed: arquivo com APA91 é apagado e deixa .REMOVIDO sem o token"`.
  - `"#103 bloco: dump de dois pacotes devolve só o bloco do app"`: o título igual no outro pacote não aparece na saída.
  - `"#103 classificar: título a 45 linhas = exibida_nao_encontrada"` com `dump_titulo_longe.txt`.
  - `"#103 classificar: dump sem o app + logcat com a marca = chegou_nao_exibida"`.
  - `"#103 classificar: dump sem o app + logcat vazio = nao_chegou"`.
  - `"#103 classificar: título só em outro pacote não conta como exibida"`.
- [ ] **Step 2: rodar e ver falhar.** `bash scripts/qa/ci_push_e2e_test.sh`. Esperado: `FALHOU: #103 …` nos 8 casos (a biblioteca ainda não existe).
- [ ] **Step 3: implementar** `scripts/qa/lib_push_diag.sh` com as quatro funções acima, só com bash, `grep -E`, `sed` e `awk` (sem dependências novas). Para o literal, use `awk` com `index()` em vez de `sed`, porque o segredo pode ter caracteres especiais.
- [ ] **Step 4: rodar e ver passar.** `bash scripts/qa/ci_push_e2e_test.sh`. Esperado: `OK — ci_push_e2e.sh`.
- [ ] **Step 5: commit** `test(ci): diagnóstico do push com redação e classificação dos desfechos (#103)`.

### Task 5: coleta na falha, linha do tempo e observação tardia em `push_e2e.sh`

**Files:**
- Modify: `scripts/qa/lib_push_diag.sh`
- Modify: `scripts/qa/push_e2e.sh` (registro, linhas ~136-150; pré-envio, ~170-176; `na_bandeja` e falhas, ~182-192)
- Test: `scripts/qa/ci_push_e2e_test.sh`

**Interfaces:**
- Consumes: Task 4.
- Produces:
  - `diag_marca <evento>`: acrescenta `<epoch.ns> <evento>` a `$PUSH_DIAG_DIR/linha_do_tempo.txt`.
  - `diag_iniciar_logcat`: roda `adb logcat -G 16M`, `setprop log.tag.FirebaseMessaging VERBOSE` e `adb logcat -v threadtime` em segundo plano para `$PUSH_DIAG_DIR/.logcat_bruto` (removido ao fim). Guarda o PID em `diag_logcat_pid`.
  - `diag_estado_pre_envio`: grava em `estado_pre_envio.txt`:
    - `POST_NOTIFICATIONS` (`dumpsys package $app | grep POST_NOTIFICATIONS`);
    - `stopped=`;
    - `am get-standby-bucket $app`;
    - a atividade em foco;
    - `pm list packages $app`;
    - `dumpsys deviceidle | grep mState`;
    - a saída de `DIAG_CMD_CONEXAO_FCM`, filtrada pelas linhas de estado;
    - `ro.build.fingerprint`;
    - a versão do GMS;
    - `AVD_CACHE_KEY` e `AVD_CACHE_HIT` do ambiente.
  - `diag_coletar <texto>`: salva em `$PUSH_DIAG_DIR`:
    - `dumpsys notification --noredact` completo;
    - `cmd notification list`;
    - os canais do app (`dumpsys notification` filtrado por `pkg=$app` e `NotificationChannel`);
    - o logcat filtrado por `FirebaseMessaging|FCM|GCM|gms|NotificationService|$app|<pid do app>`;
    - a cauda de 200 linhas de `/tmp/push_e2e_hold.txt`;
    - `classificacao.txt`, com o valor de `diag_classificar`.

    Cada arquivo passa por `diag_redigir` e depois por `diag_verificar_limpo`. Cada chamada `adb` usa `timeout 20`, e a função inteira nunca altera `$?` de quem a chamou.
  - `diag_observar_tardia <texto> <segundos>`: faz o *poll* de `na_bandeja` por até `<segundos>` e grava `chegada_tardia=<s após o envio>` ou `chegada_tardia=nunca`. **Só diagnóstico.**
  - Em `push_e2e.sh`: `PUSH_DIAG_DIR="${PUSH_DIAG_DIR:-build/qa/push-diag}"`. `PUSH_DIAG_SEGREDOS` é montado na hora, com o token do banco (`psql_q 'select token from push_tokens'`), o `project_id` e o `project_number` de `google-services.json`, e nunca é impresso. O helper `falhar_push <mensagem>` faz, nesta ordem: `diag_coletar`, `diag_observar_tardia "$texto" 180`, de novo `diag_coletar` (para o estado final), `echo "FALHOU: <mensagem>"` e `exit 1`.

- [ ] **Step 1: escrever os testes que falham.** Use um `adb` stub no `PATH` que responde de fixtures, como o stub de `docker` do bloco M3.
  - `"#103 falhar_push sai com 1 mesmo quando a observação tardia acha o texto"`: o stub de `dumpsys` passa a conter o título na segunda chamada.
  - `"#103 coleta com adb que falha (exit 1) preserva o exit 1 e não pendura"`: o stub sai com 1, e o teste roda com `timeout 120`.
  - `"#103 coleta com adb que pendura respeita o timeout por chamada"`: o stub faz `sleep 300`; o `timeout` por chamada deve ser sobrescrevível por `DIAG_TIMEOUT_ADB=1` no teste.
  - `"#103 caminho feliz não chama diag_coletar nem cria PUSH_DIAG_DIR"`: verificação estática com `sed -n` de que `diag_coletar` só aparece dentro de `falhar_push`, mais a execução do helper `na_bandeja` verde com o stub.
  - `"#103 nenhum arquivo de PUSH_DIAG_DIR contém o token do stub nem APA91"`: o stub de logcat imprime um token fictício.
  - `"#103 push_e2e.sh não imprime PUSH_DIAG_SEGREDOS"`: `grep` estático de que nenhum `echo` ou `printf` referencia a variável.
- [ ] **Step 2: rodar e ver falhar.** `bash scripts/qa/ci_push_e2e_test.sh`. Esperado: `FALHOU: #103 …` nos 6 casos novos.
- [ ] **Step 3: implementar.** No `push_e2e.sh`:
  - `diag_iniciar_logcat` antes de `== registro do token FCM real`;
  - `diag_marca registro_ok` depois de `tokens no banco`;
  - `diag_estado_pre_envio` e `diag_marca envio` logo antes de `send`;
  - `falhar_push` no lugar dos `echo 'FALHOU: …'; exit 1` dos passos que esperam a bandeja (caminho feliz, aviso agendado, `Mistura real falso ios`);
  - parar o logcat em `cleanup`.

  `na_bandeja`, os 45 s e o `grep -A30` **não mudam** nesta tarefa.
- [ ] **Step 4: rodar e ver passar.** Rode `bash scripts/qa/ci_push_e2e_test.sh` e depois `./scripts/qa/push_e2e.sh` uma vez no `sinalacs_ci36`. Esperado: verde, sem `build/qa/push-diag/`.
- [ ] **Step 5: provar a coleta de verdade.** Rode `./scripts/qa/push_e2e.sh` com a assinatura de H4 forçada à mão: num segundo terminal, `adb shell monkey -p br.com.prismrr.sinalacs.patient 1` logo após `== envio do ACS`. Esperado: exit 1, `classificacao.txt` igual a `chegou_nao_exibida` e, em `grep -rE 'APA91|<project_id>' build/qa/push-diag`, nenhuma linha.
- [ ] **Step 6: commit** `feat(ci): coleta de diagnóstico quando o aviso não chega à bandeja (#103)`.

### Task 6: artefato da coleta no workflow

**Files:**
- Modify: `.github/workflows/ci.yml` (job `android-e2e`)
- Test: `scripts/qa/ci_invariants.sh` e `scripts/qa/ci_invariants_test.sh` (só rodar, salvo se o guarda reclamar)

- [ ] **Step 1:** no passo "E2E no emulador Android", acrescente ao `env:` do passo `AVD_CACHE_KEY: avd-36-google_apis-x86_64-pixel_7-ubuntu-24.04` e `AVD_CACHE_HIT: ${{ steps.avd-cache.outputs.cache-hit }}`, sem secrets.
- [ ] **Step 2:** depois da limpeza de credenciais, adicione `actions/upload-artifact@v7` com `if: failure()`, `name: android-e2e-push-diag`, `path: build/qa/push-diag`, `retention-days: 7` e `if-no-files-found: ignore`.
- [ ] **Step 3:** rode `./scripts/qa/ci_invariants.sh && bash scripts/qa/ci_invariants_test.sh && actionlint`. Esperado: tudo verde. Se o guarda reclamar da posição do passo, ajuste a posição, não o guarda.
- [ ] **Step 4: commit** `ci(android-e2e): publica o diagnóstico do push na falha (#103)`.

---

## Fase 3: execuções na CI

### Task 7: capturar falhas instrumentadas

- [ ] **Step 1:** faça o push da branch e abra o PR para `develop` com o título `ci: diagnóstico do push na bandeja (#103)`. O PR já conta como uma execução.
- [ ] **Step 2:** dispare até 6 execuções extras com `gh workflow run CI --ref fix/issue-103-push-bandeja`, uma de cada vez por causa do grupo de concorrência. Pare ao ter **2 falhas** do passo de push. Com a taxa observada (3 vermelhas em 5), a chance de 7 execuções sem nenhuma falha fica perto de 2%.
- [ ] **Step 3:** em cada falha, rode `gh run download <id> -n android-e2e-push-diag -D $SCRATCH/diag-<id>` e depois `grep -rE 'APA91|<project_id>' $SCRATCH/diag-<id>`. Esperado: nada. Se aparecer algo, apague o artefato (`gh api -X DELETE repos/hbgit/SinalACS/actions/artifacts/<id>`), volte à Task 4 e corrija antes de seguir.
- [ ] **Step 4:** monte uma tabela por falha com a classificação, `chegada_tardia`, o estado pré-envio (permissão, foco, stopped, bucket, conexão FCM), o fingerprint e o `AVD_CACHE_HIT`. Inclua também as verdes, a partir do `linha_do_tempo` do log.
  - Se nenhuma falha ocorrer em 7 execuções, registre a queda da taxa na issue, faça o merge da instrumentação (ela só age na falha) e espere a próxima falha natural antes de qualquer correção. A Fase 4 não começa sem evidência.

---

## Fase 4: árvore de decisão e correção

### Task 8: decidir o ramo

| Desfecho medido | Sub-evidência | Hipótese confirmada | Correção |
|---|---|---|---|
| `exibida_nao_encontrada` | título no bloco, a > 30 linhas | H3 | **C**: busca por bloco |
| `chegou_nao_exibida` | app em foco no envio | H4 | **B-foco**: garantir segundo plano antes do envio |
| `chegou_nao_exibida` | `POST_NOTIFICATIONS: granted=false` | H2a | **B-permissão**: conceder e verificar, falhando cedo |
| `chegou_nao_exibida` | canal bloqueado ou ausente | H2b | **B-canal**: canal padrão declarado no app (mudança de produto, registrar decisão na issue) |
| `chegou_nao_exibida` | crash do SystemUI ou do `system_server` no intervalo | H2c | **B-emulador**: reportar e avaliar `-gpu` diferente. Sem espera nem reenvio |
| `nao_chegou`, `chegada_tardia=N` | conexão FCM caída no envio | H8 | **A-MCS**: precondição "conexão FCM ativa" antes do envio |
| `nao_chegou`, `chegada_tardia=N` | conexão ativa, prioridade normal | H5 | **A-prioridade**: `priority: high` no payload de avisos |
| `nao_chegou` | app ausente ou `stopped=true`, ou hold encerrado | H6/H7 | **A-app**: corrigir o ciclo de vida do hold |
| `nao_chegou`, `chegada_tardia=nunca` | tudo normal no aparelho | H1 (lado FCM) | nenhuma correção no repo: registrar, abrir chamado no Firebase se reproduzível, manter a coleta |
| qualquer | fingerprint ou GMS diferente entre verdes e vermelhas | H1 (imagem) | **Imagem**: chave do AVD com a revisão da imagem |

- [ ] **Step 1:** escolha o(s) ramo(s) pela tabela, comente na #103 com a tabela da Task 7 e a linha da árvore, e só então siga para a Task 9. Mais de um ramo confirmado gera uma tarefa por ramo.

### Task 9: correção do ramo confirmado (TDD)

Execute só a subtarefa do ramo confirmado. Todas seguem: teste em `ci_push_e2e_test.sh` → ver falhar → implementar → ver passar → commit `fix(ci): … (#103)`.

- **C: `na_bandeja` por bloco.**
  - Arquivo: `scripts/qa/push_e2e.sh`.
  - `na_bandeja` passa a usar `diag_bloco_do_app "$dump" "$app" | grep -qF "$1"` (dump via arquivo temporário).
  - Testes: `"#103 na_bandeja acha título a 45 linhas do pkg="` e `"#103 na_bandeja ignora título igual em outro pacote"`, com as fixtures da Task 4 e o stub de `adb`.
- **B-foco: `garantir_segundo_plano`.**
  - Arquivo: `scripts/qa/push_e2e.sh`.
  - Envia `KEYCODE_HOME` e confirma, por até 10 polls de 1 s, que a atividade em foco não é do app. Se continuar sendo, `falhar_push 'o app continua em primeiro plano'`. Isso é uma precondição verificada, não uma espera às cegas.
  - Testes: `"#103 envio só acontece com o app fora de foco"` e `"#103 app preso em foco falha antes do envio, com mensagem própria"`.
- **B-permissão: `garantir_permissao`.**
  - Arquivo: `scripts/qa/push_e2e.sh`.
  - `pm grant` sem `|| true`, seguido da leitura de `dumpsys package` exigindo `POST_NOTIFICATIONS: granted=true`. Senão, `falhar_push`.
  - Testes: `"#103 pm grant que falha interrompe antes do envio"` e `"#103 granted=false após o grant interrompe antes do envio"`.
- **A-MCS: `esperar_conexao_fcm <max_s>`.**
  - Arquivo: `scripts/qa/push_e2e.sh`.
  - *Poll* de `DIAG_CMD_CONEXAO_FCM` até o estado "conectado" medido na Task 3 (máximo de 120 s, justificado pelo tempo de reconexão medido). Se não conectar, `falhar_push 'GMS sem conexão com o FCM'`, o que separa a falha de ambiente da falha de entrega.
  - Testes: `"#103 envio espera a conexão FCM ficar ativa"` e `"#103 conexão que não sobe falha com mensagem própria antes do envio"`.
  - Registre na issue e em comentário que esta é uma espera por **precondição medida**, não um aumento de `na_bandeja`.
- **A-prioridade.**
  - Arquivo: `backend/sinalacs_server/lib/src/infrastructure/push/gorush_client.dart`.
  - Acrescentar `'priority': 'high'` ao item da notificação Android. O Gorush 1.22.0 mapeia esse campo para `android.priority`; confirme isso na Task 2.
  - Teste Dart em `backend/sinalacs_server/test/` junto aos testes existentes do `GorushClient`: `"o envio Android pede prioridade alta"`.
  - Registre na issue que isso muda o comportamento em produção (avisos comunitários com prioridade alta) e confira o PRD (RF14) antes.
- **A-app: ciclo de vida do hold.**
  - Corrigir o que a Task 7 mostrar (fim antecipado do `flutter test`).
  - Teste: `"#103 o hold continua vivo até o fim da espera da bandeja"`, por verificação do `PUSH_HOLD_SECONDS` em relação ao pior caso da linha do tempo.
- **Imagem: chave com a revisão.**
  - Arquivos: `.github/workflows/ci.yml` e `scripts/qa/ci_invariants.sh`.
  - Um passo antes do cache lê a revisão do pacote `system-images;android-36;google_apis;x86_64` e a põe na chave, que ainda termina em `-ubuntu-24.04` e contém `google_apis`.
  - Teste em `scripts/qa/ci_invariants_test.sh` com fixture positiva e negativa, se o guarda passar a exigir a revisão.

---

## Fase 5: validação e aceite

### Task 10: execuções e registro

- [ ] **Step 1:** com a correção na branch, faça 6 disparos `gh workflow run CI --ref fix/issue-103-push-bandeja`. Esperado: 6/6 verdes, cada log com `== envio do ACS` e `OK — o aviso chegou ao emulador`, e nenhum `push e2e pulado`. Somados aos 4 verdes do critério, são 10 verdes seguidos, e a chance de isso acontecer por sorte com a taxa anterior fica abaixo de 0,1%. Uma falha devolve a investigação à Task 8, com o artefato novo.
- [ ] **Step 2:** faça o merge do PR em `develop`. Esperado: `android-e2e` verde no push de `develop`, conferido com `gh run list --branch develop --workflow CI -L 1`.
- [ ] **Step 3:** acompanhe os 3 PRs seguintes. Para cada um, rode `gh run view <id> --log | grep -E '== envio do ACS|OK — o aviso chegou'` e anote o id na issue.
- [ ] **Step 4:** comente na #103 com a causa, a evidência (ids das execuções, `classificacao.txt` e linhas do estado pré-envio), a correção e as execuções do aceite. Marque os três itens do critério de aceite.
- [ ] **Step 5:** atualize a seção do CI em `PROGRESS.md` (causa e aceite) e a frase sobre o `android-e2e` em `CLAUDE.md`, se a correção mudar o que ela afirma. Rode `graphify update .` e faça o commit `docs: causa e aceite da #103 (#103)`.
