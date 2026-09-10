# Vídeo de apresentação ao sponsor

Pipeline reprodutível que transforma [`docs/roteiro-video-sponsor.md`](../docs/roteiro-video-sponsor.md)
em `out/sinalacs-sponsor.mp4` — 1920×1080, 30 fps, 180 s.

**Sem locução:** o vídeo usa legendas em tela e leito musical. As 419 palavras
do roteiro foram condensadas para 327 em [`roteiro.timing.json`](roteiro.timing.json),
concentrando o corte nos blocos 3 e 4, onde o espectador precisa olhar a UI do
celular e não consegue ler texto longo ao mesmo tempo.

## Estrutura

| Caminho | O quê |
|---|---|
| `roteiro.timing.json` | **Fonte única de verdade de tempo.** Blocos, timecodes e legendas por frame. Cartelas, legendas e montagem leem daqui — nenhum timecode é digitado duas vezes. |
| `remotion/` | Cartelas (blocos 1, 2, 6, 7) e a camada de legendas com alfa. |
| `capture/` | Scripts `adb` para gravar os blocos 3 e 4 no celular. |
| `build/assemble.sh` | Montagem ffmpeg: normaliza, concatena em cortes secos, sobrepõe legendas, aplica a música. |
| `assets/` | Faixa musical (gitignored) + `LICENSES.md` com a procedência e o comando para rebaixar. |
| `out/` | Saídas (gitignored). |

## Ordem de execução

### 1. Cartelas e legendas (não precisa de celular)

```bash
cd remotion
npm install
npm run studio            # preview interativo
npm run render:cards      # out/cards/block{1,2,6,7}.mp4
npm run render:subtitles  # out/subtitles.webm (alfa, 5400 frames)
npm run render:preview    # out/preview.mp4 — os 180 s com marcadores no lugar das tomadas
```

`Preview` serve para conferir ritmo e legibilidade **antes** de gravar qualquer
coisa. Os blocos 3, 4 e 5 aparecem como marcadores.

### 2. Tomadas no celular (blocos 3 e 4)

`adb` não está no `PATH` — os scripts o buscam em `~/Android/Sdk/platform-tools/`.
Ligue o aparelho, ative a depuração USB e aceite o diálogo de autorização.

```bash
cd ../apps/patient && flutter build apk --debug && flutter install
cd ../acs        && flutter build apk --debug && flutter install

cd ../../video/capture
./discover.sh patient-login     # despeja a hierarquia de UI + captura
./discover.sh acs-login         # repita para cada tela do percurso
# preencha as coordenadas em coords.env — os scripts abortam com placeholders

./capture-patient.sh            # out/takes/patient.mp4
./capture-acs.sh                # out/takes/acs.mp4  (liga o modo avião na cena do registro)
./fix-screenshots.sh            # reconserta docs/screenshots/acs/01-login.png
```

Os scripts só forçam a geometria se o aparelho já não estiver em 1080×2400,
ligam **Não Perturbe** e o modo demo da barra de status, e **restauram tudo por
`trap EXIT`** — deixar o celular do usuário reconfigurado seria um estrago
silencioso.

> **Não Perturbe não é opcional.** O modo demo esconde os *ícones* da barra de
> status, mas não impede um banner heads-up de aparecer por cima do app. Numa
> gravação de 2026-09-10 uma notificação pessoal do WhatsApp entrou em quadro,
> com nome de contato e trecho da mensagem. `device_prepare` agora liga o DND
> antes de qualquer tomada; ainda assim, **audite o topo da tela** de cada
> tomada antes de montar.

> **Modo avião exige CABO USB.** A cena 1:45 do bloco 4 grava o registro de
> visita com o aparelho sem rede. Sobre **adb sem fio isso é impossível**:
> ligar o modo avião derruba a própria conexão que controla o aparelho — a
> gravação morre no meio e o celular fica em modo avião, exigindo que alguém
> desligue na mão. `capture-acs.sh` detecta transporte sem fio e **pula** o
> modo avião, avisando em tela. Para ter a prova visual de "sem rede", conecte
> por cabo e regrave.

### 3. Bloco 5 — o ciclo RPC no terminal

O backend é **Serverpod RPC, não REST**: `alerts.createRedAlert` e
`alerts.acknowledge`. Não há URL para filmar.

```bash
cd ..                                  # raiz do repo
docker compose up --build              # ENABLE_DEV_LOGIN=true já está no compose
# aguarde o serviço database-seed concluir — sem o seed, createRedAlert falha
# por chave estrangeira em alerts.patientId
```

Grave em **dois painéis lado a lado**:

```bash
# painel esquerdo — deixe rodando
video/rpc_demo/watch_mqtt.sh

# painel direito
cd video/rpc_demo && dart run bin/red_alert_cycle.dart
```

O ciclo imprime cinco passos: saúde da stack, login, `createRedAlert`
(`published: true`), reenvio com a **mesma** chave devolvendo o **mesmo**
`alertId`, e `acknowledge` confirmado. O painel esquerdo mostra a mensagem
real chegando em `sinalacs/v1/microareas/<uuid>/alerts`.

> **O que este bloco NÃO demonstra.** O assinante é o usuário `backend`, que tem
> `readwrite` em `sinalacs/v1/#`. O `aclfile` concede leitura ao usuário
> `acs-area-12` no tópico `sinalacs/v1/microareas/**area-12**/alerts`, mas o
> dispatcher publica em `sinalacs/v1/microareas/**<uuid>**/alerts` — os dois não
> se encontram, então nenhum assinante com escopo de ACS receberia a mensagem
> hoje. O bloco prova **publicação e confirmação**, não isolamento territorial.
> Não afirme o segundo na locução.

Depois de rodar o ciclo, capture a saída e gere o bloco:

```bash
# na raiz do repo, com a stack de pé
mkdir -p video/rpc_demo/captured
(cd video/rpc_demo && dart run bin/red_alert_cycle.dart 2>&1 \
   | sed 's/\x1b\[[0-9;]*m//g') > video/rpc_demo/captured/cycle.txt
# e, em paralelo, o watch_mqtt.sh gravando em captured/mqtt.txt

python3 video/rpc_demo/captured/gen_block5_data.py   # → remotion/src/block5Data.ts
cd video/remotion && npm run render:block5           # → out/takes/backend.mp4
```

> **O bloco 5 é uma renderização, não uma captura de tela.** O texto em quadro é
> a saída **real** de uma execução contra a stack, versionada em
> `video/rpc_demo/captured/*.txt`; o `gen_block5_data.py` a converte em
> `block5Data.ts`, então a cartela não pode divergir do que de fato aconteceu. A
> correspondência auditável está visível em quadro: o **mesmo `alertId`** aparece
> na saída do ciclo e no payload MQTT, porque vieram da mesma corrida. Se a banca
> preferir uma gravação de tela genuína, grave os dois painéis com OBS (captura
> PipeWire — `ffmpeg -f x11grab` não funciona no Wayland) e salve por cima de
> `video/out/takes/backend.mp4`; o resto do pipeline não muda.

**Privacidade:** o token de acesso é impresso truncado pelo próprio script. Antes
de qualquer gravação de tela, feche painéis com `config/passwords.yaml`,
`JWT_SECRET`, `.env` ou string de conexão.

### 4. Montagem

```bash
cd video && ./build/assemble.sh
```

Aborta com uma dica específica se faltar qualquer insumo.

## Verificação obrigatória antes de entregar

Automática (o `assemble.sh` faz): duração 180 ±3 s, 5400 frames.

Manual — nenhuma destas o script consegue checar:

Gere as folhas de contato e olhe uma a uma:

```bash
ffmpeg -i out/sinalacs-sponsor.mp4 -vf "fps=1/2,scale=480:-1" out/audit/a%03d.png
magick montage out/audit/a0{01..30}.png -tile 6x5 -geometry 300x169+2+2 out/audit/sheet1.png
```

- [ ] **Guardrails:** nenhum dos controles da tabela "não filmar" do roteiro aparece sendo tocado; nenhum `SnackBar` de "não integrado" em quadro.
- [ ] **Notificações pessoais:** nenhum banner heads-up em quadro (varra a faixa superior: `-vf "fps=2,crop=1080:340:0:0"`).
- [ ] **Privacidade (LGPD):** só dados sintéticos; nenhuma credencial, token, `.env` ou string de conexão visível no bloco 5.
- [ ] **Honestidade:** nenhuma legenda no presente descrevendo capacidade que hoje é stub (mapa, geofencing, SAMU, push); todo número de meta com a palavra "alvo"; nenhuma afirmação de que o alerta do paciente chega ao aparelho do ACS.
- [x] **Licença:** `assets/LICENSES.md` preenchido — *Cosmic Waves*, HoliznaCC0, CC0 1.0.
- [ ] **Envelope de áudio:** blocos 1 e 7 em silêncio; cama de 0:20 a 2:45 (`ffmpeg -ss T -t D -i ... -af volumedetect -f null -`).

## Invariante visual

Vermelho, amarelo e verde são **sinal clínico**, nunca decoração — só podem
aparecer representando `RiskLevel`. O bloco 1 não usa vermelho de forma alguma:
a cor só passa a significar gravidade no bloco 3, quando a triagem da Maria lhe
dá esse significado. Ver [`spec/ui_design.md`](../spec/ui_design.md).
