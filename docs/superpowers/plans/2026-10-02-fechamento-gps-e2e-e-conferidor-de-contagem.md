# Fechamento do e2e de GPS do ACS e do conferidor de contagem — Plano de Implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Goal:** Fechar os 7 achados da revisão de `scripts/qa/acs_gps_e2e.sh`, `integration_test/geofence_gps_e2e.dart` e `scripts/qa/contagem_validation_report.py`.

**Architecture:** A prova de "permissão fixada" passa a ser um estado lido do próprio Geolocator (`checkPermission()` depois de abrir o painel); a contagem de toques do tocador fica como trava complementar, agora exercitada pelo teste hermético (adb falso que mostra o diálogo). O script ganha ordem de limpeza correta, `dart-define` só onde tem efeito e comentários que dizem só o que é conferido. O conferidor de contagem passa a recusar linha de RF cujo status não esteja em negrito.

**Tech Stack:** bash, Python 3 (`unittest`), Flutter `integration_test`, `geolocator`, adb.

**Spec:** achados do pedido do usuário (7 itens, 2026-10-02); contexto em `docs/superpowers/plans/2026-10-01-minors-da-revisao-do-app-acs.md`.

## Global Constraints

- Português em comentários, mensagens e nomes, como o resto de `scripts/qa/`.
- Commits sem atribuição de IA, sem "Co-Authored-By", sem "Generated with Claude Code" (regra do `CLAUDE.md` do projeto). Ficam na branch `fix/app_acs`, sem push.
- Nada de dado real de paciente em teste/log.
- O script nunca apaga um app já instalado sem `--reinstalar` (exit 3) — não mexer nessa guarda.
- Testes herméticos não precisam de emulador, Docker nem `.env`.

## Review Focus

- Script interrompido (SIGTERM/Ctrl-C) com o tocador vivo: arquivos temporários não podem sobrar. → Task 2, caso `interrompido`.
- Mais de 2 toques do tocador deve reprovar a rodada e exatamente 2 deve passar. → Task 2, casos `toques_demais` e `toques_ok`.
- Linha de RF com status sem negrito (`| RF05 | X | parcial | ... |`) não pode ser contada como "nada". → Task 1.
- `--sem-permissao`: o `EXPECT_PERMISSION` só vale no build; o drive não pode repeti-lo. → Task 2, caso `sem_permissao`.

## Mapa de arquivos

- Modificar `scripts/qa/contagem_validation_report.py` + `contagem_validation_report_test.py` (item 7).
- Modificar `scripts/qa/acs_gps_e2e.sh` (itens 3, 4, 5) e `scripts/qa/acs_gps_e2e_test.sh` (itens 4, 5, 6).
- Modificar `apps/acs/integration_test/geofence_gps_e2e.dart` (itens 1, 2, 3).

---

### Task 1: Conferidor de contagem recusa status sem negrito (item 7)

**Files:**
- Modify: `scripts/qa/contagem_validation_report.py`
- Test: `scripts/qa/contagem_validation_report_test.py`

**Interfaces:**
- Consumes: —
- Produces: `contar(texto) -> dict` passa a levantar `ValueError` também para linha `| RFnn |` sem status em negrito. `conferir`/CLI inalterados (o erro vira exit 2).

- [ ] **Step 1: Teste que falha** — acrescentar em `ContagemTest`:

```python
    def test_status_sem_negrito_e_erro(self):
        with self.assertRaises(ValueError):
            contar("| RF05 | X | parcial | x |\n")

    def test_linha_de_rf_malformada_e_erro(self):
        with self.assertRaises(ValueError):
            contar("| RF05 | X |\n")
```

- [ ] **Step 2: Ver falhar**

Run: `cd scripts/qa && python3 -m unittest contagem_validation_report_test -v`
Expected: os 2 testes novos FALHAM (`AssertionError: ValueError not raised`), os 4 antigos passam.

- [ ] **Step 3: Implementar** — em `contagem_validation_report.py`, trocar `contar` e adicionar a regex de qualquer linha de RF:

```python
LINHA_QUALQUER_RF = re.compile(r"^\| RF\d+ \|.*$", re.M)
```

```python
def contar(texto):
    contagem = {chave: 0 for chave in ORDEM}
    for linha in LINHA_QUALQUER_RF.findall(texto):
        achado = LINHA_RF.match(linha)
        if achado is None:
            raise ValueError(f"linha de RF sem status em negrito: {linha[:60]!r}")
        status = achado.group(1)
        if status not in contagem:
            raise ValueError(f"status desconhecido na tabela de RF: {status!r}")
        contagem[status] += 1
    return contagem
```

Atualizar a docstring: "linha de RF sem status em negrito também é erro (exit 2)". (`LINHA_RF` com `re.M` e `^` continua válida em `.match` sobre a linha.)

- [ ] **Step 4: Ver passar** — mesmo comando. Expected: 6 testes OK. Depois: `python3 scripts/qa/contagem_validation_report.py` → `ok: contagem do validation_report confere` (a tabela real tem todas em negrito; se falhar, a falha é um achado real: corrigir a linha em `spec/validation_report.md`).

- [ ] **Step 5: Commit**

```bash
git add scripts/qa/contagem_validation_report.py scripts/qa/contagem_validation_report_test.py
git commit -m "fix(qa): conferidor de contagem recusa linha de RF sem status em negrito"
```

---

### Task 2: Script de GPS — limpeza, dart-define e toques, com testes herméticos (itens 4, 5, 6)

**Files:**
- Modify: `scripts/qa/acs_gps_e2e_test.sh`
- Modify: `scripts/qa/acs_gps_e2e.sh`

**Interfaces:**
- Produces: variável de ambiente `GPS_E2E_INTERVALO` (segundos entre amostras/toques, padrão `1`); constante `max_toques=2` no script.

- [ ] **Step 1: Estender o teste hermético (falha primeiro)**

(a) No `adb` falso, acrescentar antes do `esac`:

```bash
  *uiautomator*)
    if [[ "${FAKE_DIALOGO_TOQUES:-0}" == 1 ]]; then
      n="$(cat "$FAKE_LOG.dumps" 2>/dev/null || echo 0)"
      if [[ -z "${FAKE_DIALOGO_LIMITE:-}" || "$n" -lt "$FAKE_DIALOGO_LIMITE" ]]; then
        echo $((n + 1)) >"$FAKE_LOG.dumps"
        echo '<node resource-id="com.android.permissioncontroller:id/permission_deny_button" bounds="[0,0][10,10]" />'
      fi
    fi ;;
```

(b) No `flutter` falso, trocar a linha do `drive` por:

```bash
  drive) [[ "${FAKE_DRIVE_FALHA:-0}" == 1 ]] && exit 1
         [[ "${FAKE_DRIVE_TRAVA:-0}" == 1 ]] && sleep 30
         [[ -n "${FAKE_DRIVE_DEMORA:-}" ]] && sleep "$FAKE_DRIVE_DEMORA" ;;
```

(c) Em `caso()`, isolar o TMPDIR por caso e zerar o contador de dumps:

```bash
  rm -rf "$tmp/t" "$FAKE_LOG.dumps"; mkdir "$tmp/t"
  saida="$(env PATH="$tmp/bin:$PATH" TMPDIR="$tmp/t" GPS_E2E_INTERVALO=0.1 MQTT_ACS_PASSWORD=x "${envs[@]}" ./scripts/qa/acs_gps_e2e.sh "$@" 2>&1)"; codigo=$?
```

(d) Trocar o `verifica` do caso `sem_permissao` e acrescentar os novos casos (antes da linha final `[[ "$falhas" ...`):

```bash
caso sem_permissao --  --sem-permissao
verifica '[[ $codigo -eq 0 ]]'
verifica '[[ $(conta "pm revoke") -eq 2 ]]'
verifica 'grep -q "^flutter build .*EXPECT_PERMISSION=denied_forever" "$FAKE_LOG"'   # o define vale só no build
verifica '! grep "^flutter drive" "$FAKE_LOG" | grep -q EXPECT_PERMISSION'          # o drive não o repete
verifica '[[ $(conta "^flutter drive") -eq 1 ]]'   # uma rodada só: o teste fixa a negação sozinho
verifica '[[ -z "$(ls -A "$tmp/t")" ]]'            # nenhum temporário sobra

caso toques_ok FAKE_DIALOGO_TOQUES=1 FAKE_DIALOGO_LIMITE=2 FAKE_DRIVE_DEMORA=2 -- --sem-permissao
verifica '[[ $codigo -eq 0 ]]'
verifica '[[ $(conta "input tap") -eq 2 ]]'        # exatamente o teto: passa

caso toques_demais FAKE_DIALOGO_TOQUES=1 FAKE_DRIVE_DEMORA=2 -- --sem-permissao
verifica '[[ $codigo -eq 1 ]]'
verifica '[[ $(conta "input tap") -gt 2 ]]'        # o caminho de >2 foi exercitado de verdade
verifica 'grep -q "mais de 2 vezes" <<<"$saida"'
verifica '[[ -z "$(ls -A "$tmp/t")" ]]'

caso interrompido FAKE_DIALOGO_TOQUES=1 FAKE_DRIVE_DEMORA=5 -- --sem-permissao
```

(`interrompido` precisa de SIGTERM no meio; como `caso` é síncrono, escrever este bloco à mão em vez de `caso`:)

```bash
nome=interrompido; : >"$FAKE_LOG"; rm -rf "$tmp/t" "$FAKE_LOG.dumps"; mkdir "$tmp/t"
env PATH="$tmp/bin:$PATH" TMPDIR="$tmp/t" GPS_E2E_INTERVALO=0.1 MQTT_ACS_PASSWORD=x \
  FAKE_DIALOGO_TOQUES=1 FAKE_DRIVE_DEMORA=5 ./scripts/qa/acs_gps_e2e.sh --sem-permissao >/dev/null 2>&1 &
pid=$!; sleep 2; kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; saida=""
verifica '[[ -z "$(ls -A "$tmp/t")" ]]'            # item 5: nem o arquivo de toques vaza
verifica '[[ $(conta uninstall) -ge 1 ]]'          # e o app de teste é removido
```

(Remover a linha `caso interrompido ...` e deixar só o bloco manual.)

- [ ] **Step 2: Ver falhar**

Run: `bash scripts/qa/acs_gps_e2e_test.sh`
Expected: FALHAM `sem_permissao` (o drive hoje leva `EXPECT_PERMISSION`), `toques_demais` ou `interrompido` (vazamento/sem intervalo configurável; `GPS_E2E_INTERVALO` ainda não existe, então `toques_ok` fica com 0–1 toque). Anotar quais falharam.

- [ ] **Step 3: Implementar no script**

(a) Intervalo configurável e teto nomeado, junto de `limite=`/antes do amostrador:

```bash
intervalo="${GPS_E2E_INTERVALO:-1}"
max_toques=2   # as duas recusas que fixam a negação; um 3º toque = a permissão não ficou fixada
```
Trocar os dois `sleep 1` dos laços `( while true; ... )` por `sleep "$intervalo"`, e `-gt 2` por `-gt "$max_toques"` (mensagem: `"... mais de $max_toques vezes ..."` — o teste casa em "mais de 2 vezes", que continua verdadeiro).

(b) `limpar()` — matar e esperar o tocador ANTES de apagar o arquivo de toques (o laço recria o arquivo com `>>`), e tratar sinais:

```bash
limpar() {
  if [[ -n "$amostrador" ]]; then
    kill "$amostrador" 2>/dev/null || true
    wait "$amostrador" 2>/dev/null || true
  fi
  rm -f "$log" "$amostras" "$toques"
  if [[ "$instalamos" -eq 1 ]]; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
}
trap limpar EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
```
(Os `trap` de INT/TERM garantem que o EXIT trap rode mesmo com o `flutter drive` em primeiro plano. Se o caso `interrompido` ainda falhar, o árbitro é o teste: ajustar até passar, sem enfraquecê-lo.)

No fluxo normal, trocar `kill "$amostrador" 2>/dev/null || true; amostrador=""` por `kill "$amostrador" 2>/dev/null || true; wait "$amostrador" 2>/dev/null || true; amostrador=""` para que a contagem de toques seja lida depois da morte do tocador.

(c) `dart-define` do drive: remover a linha `--dart-define=EXPECT_PERMISSION="$expect"` do `flutter drive` (com `--use-application-binary` o valor já está embutido no APK construído; repeti-lo no drive sugere que ele vale ali). Deixar o comentário no ponto do build:

```bash
# O EXPECT_PERMISSION é fixado AQUI, no build: o `flutter drive` abaixo usa o APK pronto
# (--use-application-binary) e não recompila, então um dart-define no drive não teria efeito.
```

- [ ] **Step 4: Ver passar**

Run: `bash scripts/qa/acs_gps_e2e_test.sh` (repetir 3x: toques dependem de tempo)
Expected: `ok: acs_gps_e2e` nas 3 rodadas.

- [ ] **Step 5: Commit**

```bash
git add scripts/qa/acs_gps_e2e.sh scripts/qa/acs_gps_e2e_test.sh
git commit -m "fix(qa): gps e2e limpa o tocador antes dos temporários, sem define morto no drive e com caso hermético de >2 toques"
```

---

### Task 3: Teste Dart prova o estado, não a contagem; comentários honestos (itens 1, 2, 3)

**Files:**
- Modify: `apps/acs/integration_test/geofence_gps_e2e.dart`
- Modify: `scripts/qa/acs_gps_e2e.sh` (só comentários do cabeçalho e do bloco do tocador)

**Interfaces:**
- Consumes: `Geolocator.checkPermission()` / `requestPermission()`; os cenários `granted|denied_forever` da Task 2.
- Produces: —

- [ ] **Step 1: Escrever a mudança do teste** (não há como falhar sem emulador; a prova é o passo 3)

Em `geofence_gps_e2e.dart`, trocar o bloco `else` por no máximo 2 pedidos (1ª recusa + 2ª, que fixa):

```dart
      expect(permission, isNot(anyOf(LocationPermission.whileInUse, LocationPermission.always)));
      // No máximo 2 pedidos: o script do emulador recusa o 1º diálogo e o 2º, e a 2ª recusa
      // faz o Android parar de perguntar. Um 3º pedido seria só um pedido que já volta na hora.
      var resposta = await Geolocator.requestPermission();
      if (resposta != LocationPermission.deniedForever) {
        resposta = await Geolocator.requestPermission();
      }
      expect(resposta, LocationPermission.deniedForever);
```

E, dentro do `if (_expect == 'denied_forever')` depois de abrir o painel, ANTES dos `expect` de texto:

```dart
      // A prova de "nada pergunta de novo": com a negação fixada, o painel de Geofencing não
      // pode ter reaberto o fluxo de permissão. O estado lido de volta continua deniedForever.
      expect(await Geolocator.checkPermission(), LocationPermission.deniedForever,
          reason: 'abrir o painel não pode alterar nem reabrir a permissão já fixada');
```

Corrigir o comentário do arquivo: no cabeçalho, onde se lê "negada-de-vez"/"USER_FIXED" não deve haver afirmação sobre a flag do Android — dizer "negada de vez (o Geolocator reporta `deniedForever`)".

- [ ] **Step 2: Corrigir os comentários do script**

Em `acs_gps_e2e.sh`: na linha 6, trocar `negada DE VEZ (USER_FIXED)` por `negada DE VEZ (o Geolocator reporta deniedForever)`. No comentário do bloco do tocador, reescrever as 3 linhas para:

```bash
# No cenário `denied_forever` o diálogo é ESPERADO: o tocador abaixo o recusa. A prova principal de
# que a negação ficou fixada é do próprio teste (checkPermission() == deniedForever depois de abrir
# o painel). A contagem de toques é só uma trava complementar: no máximo $max_toques (as duas
# recusas); um 3º toque indica que o diálogo continuou aparecendo. Ela NÃO confere a flag USER_FIXED.
```

- [ ] **Step 3: Verificar**

Run: `cd apps/acs && dart analyze integration_test/geofence_gps_e2e.dart` → `No issues found!`
Run: `bash scripts/qa/acs_gps_e2e_test.sh` → `ok: acs_gps_e2e`
Run (se houver o emulador-5554 livre do app): `./scripts/qa/acs_gps_e2e.sh --sem-permissao` e `./scripts/qa/acs_gps_e2e.sh`
Expected: `OK — permissão de localização em runtime (denied_forever)` e `(granted)`. Se o `checkPermission()` não vier `deniedForever` no emulador, NÃO afrouxar o `expect`: investigar (é exatamente o falso positivo que o item 1 queria expor). Sem emulador, dizer isso explicitamente ao reportar — a verificação em aparelho fica pendente.

- [ ] **Step 4: Commit**

```bash
git add apps/acs/integration_test/geofence_gps_e2e.dart scripts/qa/acs_gps_e2e.sh
git commit -m "test(acs): gps e2e confere deniedForever após abrir o painel, no máximo 2 pedidos e comentários sem USER_FIXED"
```

---

## Auto-revisão

- **Cobertura:** 1 → Task 3; 2 → Task 3 (loop vira ≤2 pedidos, igual ao comentário e ao `max_toques`); 3 → Task 3 (comentários dos dois arquivos); 4 → Task 2 (define só no build, greps ancorados `^flutter build`/`^flutter drive`); 5 → Task 2 (`wait` antes do `rm`, traps, casos `sem_permissao`/`interrompido`); 6 → Task 2 (`toques_demais`, `toques_ok`); 7 → Task 1.
- **Placeholders:** nenhum; a única incerteza declarada é o comportamento de SIGTERM do bash, com o teste como árbitro.
- **Consistência:** `GPS_E2E_INTERVALO`, `max_toques`, `FAKE_DIALOGO_TOQUES/LIMITE`, `FAKE_DRIVE_DEMORA` usados com os mesmos nomes nas Tasks 2 e 3.
- **Risco aberto:** a prova em aparelho (Task 3, passo 3) depende do emulador-5554; sem ele, só a parte hermética e a análise estática são verificadas.
