# ISSUE #103: assinaturas dos desfechos do push no emulador (Task 3)

Medido em 2026-10-26 no AVD local `sinalacs_ci36`. É o mesmo da CI: `system-images;android-36;google_apis;x86_64` r7, `pixel_7`, emulador 37.2.12.0, build `google/sdk_gphone64_x86_64/emu64xa:16/BE2A.250530.026.F3/13894323:userdebug/dev-keys`, GMS `25.26.35 (260800-783060121)`. Diferenças em relação à CI:

- `-gpu swangle_indirect` em vez de `swiftshader_indirect`, porque este dá SIGSEGV nesta máquina;
- `disk.dataPartition.size=4G`;
- `hw.sdCard=no`.

O relógio do aparelho está 4 h à frente do host, por causa do fuso.

## Constantes para a coleta (Tasks 4/5)

| Constante | Valor | Por quê |
|---|---|---|
| `DIAG_MARCA_RECEBIDA` | `FirebaseMessaging: Logging to scion event=_nr` | Sai em toda mensagem *notification* recebida pelo app, em primeiro plano (exp. A) ou em segundo plano (exp. C), e só na mensagem. **Não** use `service received new intent via bind strategy`, que aparece também no `onNewToken` do registro (`lc-snap1`). |
| `DIAG_MARCA_POSTADA` | `NotificationListener: received notification posted event - br.com.prismrr.sinalacs.patient` | Confirma que o sistema aceitou a notificação. `FirebaseMessaging: Showing notification` **não** basta: aparece também sem `POST_NOTIFICATIONS` (exp. B), caso em que nada é postado. |
| `DIAG_CMD_CONEXAO_FCM` | `dumpsys activity service com.google.android.gms/.gcm.GcmService` | Linhas úteis: `Is client connected:`, `connectTime=`, `Heartbeat: alarm(`, `Reconnect Scheduler Alarm:` e o histórico `net=N: Connecting using McsConnection`. |

## Linha de base

| Rodada | Boot | Resultado |
|---|---|---|
| run1 | boot a frio | ✅ `OK — o aviso chegou` (75 s) |
| snap1 | `-snapshot ci103 -no-snapshot-save`, 5 min depois do save | ❌ `FALHOU: título não está na bandeja` |
| snap2 | idem (controle) | ❌ `FALHOU: título não está na bandeja` |
| snap3 | idem, com `svc wifi/data disable` + `enable` antes do script (`connectTime=00:01`) | ✅ `OK — o aviso chegou` |

## Assinaturas por hipótese

- **Verde** (exp. C, segundo plano e permissão concedida): `_nr`, depois `Showing notification`, depois `NotificationListener … posted` em cerca de 0,2 s. A notificação aparece no `dumpsys` com `tag=FCM-Notification:*`, `importance=3`, no canal padrão do SDK.
- **H3 (janela do grep):** no `NotificationRecord`, `pkg=` fica na linha do cabeçalho, `android.title=` está **25** linhas abaixo e `android.text=` **30** linhas abaixo. O título cabe no `grep -A30`, mas o texto está **exatamente no limite**, com margem 0. Não é a causa das falhas observadas, que falham no título. É uma fragilidade latente: qualquer extra a mais no registro faz o 2º `na_bandeja` falhar.
- **H4 (primeiro plano, exp. A):** `_nf`, `_nr` e nenhum `Showing notification`, e nada no `dumpsys`. Assinatura: `chegou_nao_exibida`, com `topResumedActivity` do app.
- **H2a (sem `POST_NOTIFICATIONS`, exp. B):** `_nr` e `Showing notification`, mas **sem** `NotificationListener … posted`, e nada no `dumpsys`. Assinatura: `chegou_nao_exibida`, com `granted=false`. O `pm grant` do script funciona (`granted=true` depois dele).
- **H7 (app desinstalado):** `ActivityManager: Force stopping … deletePackageX` e `NotificationListener: received notification removed event`. Esse é o fim normal do `flutter test`. Detalhe: o teste tem `timeout` de 6 min, então `PUSH_HOLD_SECONDS` > ~330 s desinstala o app antes da hora. O script usa 240 s, o que está ok.
- **H8, rede caída (exp. D):** `Is client connected: false`. O envio é aceito (`accepted=1`), e a notificação chega 2 s depois de a rede voltar. Assinatura "A-tardia" com o GMS **sabendo** que está desconectado.
- **H8, snapshot (exp. E, `lc-snap2`), CONFIRMADA LOCALMENTE:**
  - Depois de `-snapshot ci103`, o GMS informa `Is client connected: true`, `connectTime` contando desde **antes** do save e `Heartbeat: alarm(09:27 initial: 600s)`.
  - Envio às 15:27:08: nenhum `_nr`. Às 15:33:13 dispara `GCM_HB_ALARM`, e às 15:33:14 vêm `_nr` e `Showing notification`.
  - A restauração foi às 15:23:46, e 15:23:46 + 09:27 = 15:33:13: a entrega ocorre **no segundo exato do heartbeat**.
  - Interpretação: a conexão MCS gravada no snapshot está morta do lado do host (o NAT do processo anterior do emulador não existe mais), mas o GMS só descobre isso no próximo heartbeat. Até lá o FCM aceita e enfileira, e nada chega.
  - Assinatura "A-zumbi": conectado segundo o GMS, `connectTime` maior que o tempo desde o boot, nenhum `_nr` e entrega no heartbeat.

## Relação com a CI

Nas 5 execuções analisadas na Fase 0, o passo E2E carrega o snapshot `default_boot` gravado minutos antes pelo passo "Gera o snapshot do AVD para o cache" (`Successfully loaded snapshot 'default_boot'`). Tempo do load do snapshot até `== envio do ACS`:

| Execução | load → envio | Resultado |
|---|---|---|
| 40231780331 | 589 s | ✅ |
| 40237097203 | 599 s | ❌ |
| 40251805400 a1 | 574 s | ❌ |
| 40251805400 a2 | 582 s | ❌ |
| 40275396602 | 569 s | ✅ |

O envio cai sempre perto dos 600 s do heartbeat inicial. O que decide o desfecho é o tempo de heartbeat que **restava** no momento do save, e isso o log da CI não mostra:

- se o heartbeat dispara antes do envio, a conexão é refeita e o resultado é verde;
- se dispara depois, o resultado é vermelho e a entrega só viria fora dos 45 s.

O load → envio sozinho não ordena os resultados, o que é coerente com esse mecanismo. A coleta da Fase 2 registra `connectTime`, `Heartbeat: alarm(` e a chegada tardia, para confirmar isso na CI.
