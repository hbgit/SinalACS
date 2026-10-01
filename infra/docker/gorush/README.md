# Gorush (RF14)

Relé de push open-source que mantém as conexões com o FCM (Android) e o APNs
(iOS). O backend entrega a lista de tokens e o Gorush faz o envio; a segmentação
é feita no PostgreSQL, nunca aqui.

Só sobe com o perfil `push`: `docker compose --profile push up`.

## O que a organização precisa fornecer

O Gorush é um relé, **não substitui** as credenciais dos provedores. Coloque em
`GORUSH_CREDENTIALS_DIR` (fora do repositório):

- `fcm-service-account.json` — conta de serviço do FCM (Android);
- `apns-key.p8` — chave de autenticação do APNs (iOS), com `GORUSH_IOS_KEY_ID` e
  `GORUSH_IOS_TEAM_ID` no `.env`.

Nada disso é versionado nem gerado por `bootstrap_env.sh` (a decisão §3.2 falava em
"padrão `bootstrap_env.sh`" para o que for segredo aleatório; credenciais de provedor
não são aleatórias, são emitidas por ele).

## O que foi verificado contra o Gorush 1.22.0 e o FCM reais (2026-09-30)

Com a chave real do projeto `sinal-acs` e um token **falso** (nada é entregue a ninguém;
`scripts/qa/gorush_smoke.sh`):

- **A chave e a API FCM V1 funcionam:** o FCM respondeu com um erro de *token* (`The
  registration token is not a valid FCM registration token`), não de autenticação.
- **Forma da resposta:** HTTP 200, `{"counts": 1, "logs": [{"type": "failed-push",
  "platform": "android", "token": …, "message": "(message redacted)", "error": …}],
  "success": "ok"}`. **`counts` conta notificações enfileiradas, não entregas** (vale `1`
  mesmo com a falha): o backend calcula "aceitos" como alvos menos falhas.
- **`log.hide_token` (padrão `true`) mascara o token na resposta** (`***…xx`): com isso a
  poda de tokens inválidos nunca casaria com `push_tokens.token`. O `config.yml` define
  `hide_token: false`; o custo é o token de aparelho aparecer no log do Gorush. O backend
  só apaga um token que ele mesmo enviou.
- **`ios.enabled: true` sem `apns-key.p8` faz o Gorush encerrar no boot com código 1**, e
  `log.access_log`/`error_log` com `"-"` faz o Gorush não escrever log nenhum (o erro do
  boot fica invisível): o `config.yml` usa `ios.enabled: false` e `stdout`/`stderr`.
- **Imagem:** fixada em `appleboy/gorush:1.22.0`, que já traz `HEALTHCHECK`
  (`/bin/gorush --ping`) e roda como `gorush` (uid 1000). A chave deve ter modo `600` e ser
  legível por esse uid; se o uid do dono da chave for outro, use `chown`/grupo, não `644`.

## Entrega real, observada no emulador Android (2026-09-30)

`scripts/qa/push_e2e.sh --negativos` (precisa da chave e do emulador; não roda na CI):

- Um aviso do ACS chega à **bandeja** do aparelho com o título e o texto enviados; o FCM
  devolve `NotRegistered` para o token de um app desinstalado (já na lista de erros
  reconhecidos), e o token é podado.
- Token falso (150 caracteres) é podado; uma linha `ios` com `ios.enabled: false` **não é
  apagada** e **não derruba** o Android. `accepted` **superconta** tokens `ios` nessa
  situação (o Gorush os descarta sem log).
- Gorush parado: o nome `gorush` não resolve e a conexão fica pendurada; o backend agora
  tem tempo de conexão próprio (2 s) e responde "inacessível, tente de novo" em ~3 s, sem
  apagar token algum. Um estouro **depois** de o pedido sair continua sendo "resultado
  desconhecido".
- Sem a permissão `POST_NOTIFICATIONS` (Android 13+) o token registra mas o aviso não
  aparece; com o app em primeiro plano o FCM não mostra a mensagem de notificação.
- **Cuidado com `GORUSH_CREDENTIALS_DIR`:** precisa ser um **diretório**. O ambiente do shell
  prevalece sobre o `.env`; um valor apontando para um arquivo monta esse arquivo como
  `/credentials` e o Gorush cai no boot.
- **`hide_token: false` imprime tokens de aparelho em `docker logs`.** Restrinja o acesso ao
  log do Gorush.

## O que ainda não foi verificado

- iOS/APNs: sem app iOS e sem chave APNs (`ios.enabled: false`).
- Aparelho físico, celular bloqueado, economia de bateria e aparelho sem Play Services.
- Renovação do token (`onNewToken`) e abrir uma tela ao tocar na notificação.
- A string de erro de outros casos do FCM (cota, mensagem malformada) além do token inválido.
- Gorush hospedado fora do Compose local.

## Na CI (GitHub Actions)

O job `android-e2e` usa dois secrets, cada um o arquivo em base64 (`base64 -w0 arquivo`):

| Secret | Arquivo | Onde vai no runner |
|---|---|---|
| `FCM_CREDENTIALS_BASE64` | `fcm-service-account.json` | arquivo `0600` em `$RUNNER_TEMP`; `GOOGLE_APPLICATION_CREDENTIALS` aponta para ele; `ci_push_e2e.sh` o instala em `infra/docker/gorush/credentials/` (o que o Gorush monta) |
| `GOOGLE_SERVICES_JSON_BASE64` | `google-services.json` | `apps/patient/android/app/` (o build do paciente o procura ali) |

Com os dois, o job roda o `push_e2e.sh` (caminho feliz) depois do smoke: o aviso do ACS chega
à bandeja do emulador pelo Gorush e FCM reais. Sem eles (PR de fork, secret apagado) os passos
só avisam e o job roda como antes. O emulador do CI usa a imagem `google_apis` (Play Services):
a imagem padrão da action é AOSP e o FCM não entrega token nela.

Os arquivos são apagados por um passo `if: always()`; `scripts/ci/decode_secret_file.sh` nunca
imprime o conteúdo e não sobrescreve nem apaga arquivos de um desenvolvedor fora do CI.

**Dono da chave no runner.** A chave precisa ser `0600` (o `push_e2e.sh` exige) e a imagem do
Gorush roda como uid 1000, mas no runner o dono é o usuário `runner` (uid 1001): o Gorush cairia
com `cannot read credentials file … permission denied`. Por isso o serviço `gorush` do
`docker-compose.yml` roda com `user: ${GORUSH_UID:-1000}:${GORUSH_GID:-1000}` e o
`ci_push_e2e.sh` exporta o uid/gid de quem instalou a chave. Fora do CI o padrão 1000 é o da imagem.

