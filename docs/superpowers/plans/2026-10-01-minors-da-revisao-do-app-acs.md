# Minors da revisão do app ACS — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar os 7 achados Minor adiados na revisão final do branch `fix/app_acs`, sem alterar o comportamento do app ACS: só scripts de QA, um teste de integração, o relé de OTP e um número num relatório.

**Architecture:** Cada achado vira uma correção pequena com verificação que falha antes. Os scripts de shell ganham testes herméticos (adb/flutter falsos no `PATH`, no molde de `scripts/qa/ci_push_e2e_test.sh`); o relé ganha teste Python; a asserção de microárea passa a ser conferida também no servidor; a contagem do relatório ganha um conferidor.

**Tech Stack:** bash, Python 3 (`unittest`), `adb`/`uiautomator`, Flutter `integration_test`/`flutter drive`, Docker Compose (`e2e_stack.sh`).

**Spec:** `docs/superpowers/plans/2026-10-01-finalizacao-app-acs.md` (seção "Desvios da execução" e Tasks 3–4, que criaram o que aqui se corrige). A revisão que originou os 7 itens não está em disco; a tabela abaixo a resume.

## Os 7 itens e onde são fechados

| # | Achado da revisão | Task |
|---|---|---|
| 1 | `spec/validation_report.md:96` diz "3 `parcial` · 5 `ausente`"; a tabela tem 4 · 4 | 1 |
| 2 | A permissão negada não simula `deniedForever` (caso comum em campo) | 6 |
| 3 | `acs_gps_e2e.sh` desinstala o app do ACS sem avisar (apaga fila SQLCipher e Keystore de dev) | 5 |
| 4 | `acs_gps_e2e.sh` esconde o erro do `flutter build` (`>/dev/null`) | 5 |
| 5 | A asserção RNF06 do e2e depende de não haver filtro padrão no seletor | 4 |
| 6 | A senha sintética de `/acs` é legível por qualquer app do emulador durante a execução (≤ 45 min) | 3 |
| 7 | A checagem da porta 8765 só enxerga `127.0.0.1` | 2 |

## Estado verificado em 2026-10-01

- `adb`, `flutter` e `emulator` não estão no `PATH`: `export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$HOME/flutter/bin"`.
- **`pm set-permission-flags` não existe** no AVD `Medium_Phone` (Android 16): `adb shell pm help` não o lista. A sugestão do revisor para o item 2 não funciona como escrita; a Task 6 recusa o diálogo do sistema de verdade e **mede** antes de depender disso.
- `Geolocator.checkPermission()` devolve `denied` (não `deniedForever`) num app que nunca pediu a permissão; só `requestPermission()` devolve `deniedForever` sem abrir diálogo quando a permissão está `USER_FIXED`. A Task 6 asserta sobre `requestPermission()`.
- Tabela de RF de `spec/validation_report.md`: 18 linhas (`RF01`–`RF18`); contadas por `grep`: 4 `parcial`, 4 `ausente` (o texto diz 3 · 5).
- O emulador pode ainda ter o APK de teste do ACS de execuções anteriores instalado. Depois da Task 5, a primeira rodada do script de GPS exige `--reinstalar` (é o comportamento novo, não um defeito).
- Os mesmos 3 scripts repetem a checagem `ss -ltn 2>/dev/null | grep -q '127.0.0.1:8765 '`: `acs_full_e2e.sh:31`, `patient_full_e2e.sh:41`, `push_e2e.sh:93`.

## Fora deste plano

| Item | Motivo |
|---|---|
| Ligar os novos testes de shell/Python à CI | Exigiria mexer em `.github/workflows/ci.yml`, vigiado por `ci_invariants.sh`. Decisão à parte. |
| `iniciar_rele()` de `push_e2e.sh` | O revisor apontou que parece chamar a si mesma (defeito anterior ao branch). A Task 2 só troca a linha da checagem de porta; confira com `sed -n 90,102p scripts/qa/push_e2e.sh` e, se for mesmo recursiva, abra issue em vez de corrigir aqui. |
| Provar a chegada de um fix de GPS | Segue impossível neste AVD (ver o plano anterior). |

## Global Constraints

- Nenhum dado real de paciente em teste, log ou captura; só fixtures sintéticas.
- **Commits sem qualquer atribuição de IA** (`Co-Authored-By`, "Generated with Claude Code") — regra do `CLAUDE.md` da raiz. Textos, comentários e commits em português. Sem push nem merge.
- `ACCESS_BACKGROUND_LOCATION` continua proibida (não tocar o manifesto).
- A senha do ACS nunca vai para o argv do `flutter` nem para o APK (já vale; não regredir).
- `flutter analyze` em `apps/acs` sem problemas e `flutter test` em 208 (só pode crescer) antes de cada commit que toque Dart.
- `acs_full_e2e.sh` substitui a stack de desenvolvimento pela de e2e: ao final, `docker compose up -d` e conferir `sinalacs-serverpod ... (healthy)`.

## Review Focus

Falhas que o plano implica e nenhuma tarefa exercitaria sozinha; cada linha tem o teste dono:

1. **App já instalado, sem `--reinstalar`:** o script aborta (exit 3) **antes** do build e sem nenhum `adb uninstall`. → Task 5, caso `guarda`.
2. **Falha no meio da execução** (build ok, `flutter drive` falha): o app de teste instalado pelo script é removido ao sair, para a próxima rodada não esbarrar na guarda. → Task 5, caso `drive_falha`.
3. **Porta 8765 ocupada em `0.0.0.0`/`[::]`** (não só `127.0.0.1`) é detectada. → Task 2.
4. **Segundo `GET /acs`** no mesmo relé devolve 404 (a senha sai uma vez só). → Task 3.
5. **Linha nova na tabela de RF com status fora da lista** (ex.: `**quase**`) faz o conferidor da contagem falhar, em vez de ser ignorada e deixar a contagem errada de novo. → Task 1.

---

### Task 1: Conferidor da contagem do `validation_report.md`

**Files:**
- Create: `scripts/qa/contagem_validation_report.py`
- Create: `scripts/qa/contagem_validation_report_test.py`
- Modify: `spec/validation_report.md:96`

**Interfaces:**
- Consumes: nada.
- Produces: `contar(texto) -> dict[str,int]`, `conferir(texto) -> tuple[str,str]` (declarada, esperada) e o CLI `python3 scripts/qa/contagem_validation_report.py [arquivo]` (exit 0 confere; 1 diverge; 2 erro de formato).

- [ ] **Step 1: Escrever o teste que falha**

Criar `scripts/qa/contagem_validation_report_test.py`:

```python
import unittest

from contagem_validation_report import conferir, contar

TABELA = """\
| RF01 | A | **backend** | x |
| RF02 | B | **parcial** | x |
| RF03 | C | **ausente** | x |
| RNF01 | D | **parcial** | x |

**Contagem:** {linha}.
"""


class ContagemTest(unittest.TestCase):
    def test_ignora_rnf_e_confere(self):
        declarada, esperada = conferir(TABELA.format(linha="1 `backend` · 1 `parcial` · 1 `ausente`"))
        self.assertEqual(declarada, esperada)

    def test_detecta_divergencia(self):
        declarada, esperada = conferir(TABELA.format(linha="1 `backend` · 2 `parcial` · 1 `ausente`"))
        self.assertNotEqual(declarada, esperada)

    def test_status_desconhecido_e_erro(self):
        with self.assertRaises(ValueError):
            contar("| RF09 | Z | **quase** | x |\n")

    def test_sem_linha_de_contagem_e_erro(self):
        with self.assertRaises(ValueError):
            conferir("| RF01 | A | **backend** | x |\n")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd scripts/qa && python3 contagem_validation_report_test.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'contagem_validation_report'`.

- [ ] **Step 3: Implementação mínima**

Criar `scripts/qa/contagem_validation_report.py` (`chmod +x`):

```python
#!/usr/bin/env python3
"""Confere a linha "**Contagem:**" de spec/validation_report.md contra a tabela de RF.

A linha foi escrita à mão e ficou para trás quando RF13 mudou de status; este
conferidor recalcula a partir das linhas `| RFnn | ... | **status** | ... |`.
Status fora da lista conhecida é erro (exit 2), não linha ignorada: ignorar
deixaria a contagem errada de novo, em silêncio.
"""
import pathlib
import re
import sys

ORDEM = ["backend", "backend + app", "app-only", "parcial", "ausente"]
LINHA_RF = re.compile(r"^\| RF\d+ \|[^|]*\| \*\*([^*]+)\*\* \|", re.M)
LINHA_CONTAGEM = re.compile(r"^\*\*Contagem:\*\* (.+)\.$", re.M)


def contar(texto):
    contagem = {chave: 0 for chave in ORDEM}
    for status in LINHA_RF.findall(texto):
        if status not in contagem:
            raise ValueError(f"status desconhecido na tabela de RF: {status!r}")
        contagem[status] += 1
    return contagem


def esperada(contagem):
    return " · ".join(f"{contagem[chave]} `{chave}`" for chave in ORDEM if contagem[chave])


def conferir(texto):
    declarada = LINHA_CONTAGEM.search(texto)
    if declarada is None:
        raise ValueError("sem linha '**Contagem:**'")
    return declarada.group(1), esperada(contar(texto))


if __name__ == "__main__":
    caminho = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "spec/validation_report.md")
    try:
        declarada_, esperada_ = conferir(caminho.read_text(encoding="utf-8"))
    except ValueError as erro:
        print(f"erro: {erro}", file=sys.stderr)
        sys.exit(2)
    if declarada_ != esperada_:
        print(
            f"erro: contagem desatualizada em {caminho}\n  declarada: {declarada_}\n  da tabela: {esperada_}",
            file=sys.stderr,
        )
        sys.exit(1)
    print("ok: contagem do validation_report confere")
```

- [ ] **Step 4: Rodar o teste e ver passar; rodar o conferidor e ver o defeito real**

Run: `cd scripts/qa && python3 contagem_validation_report_test.py && cd ../.. && python3 scripts/qa/contagem_validation_report.py`
Expected: `OK` (4 testes) e o conferidor **falha** (exit 1) mostrando `declarada: 7 \`backend\` · 2 \`backend + app\` · 1 \`app-only\` · 3 \`parcial\` · 5 \`ausente\`` e `da tabela: …· 4 \`parcial\` · 4 \`ausente\``. Se algum dos três primeiros números da linha "da tabela" divergir de 7 · 2 · 1, **investigue a tabela antes de editar** — não aceite o valor às cegas.

- [ ] **Step 5: Corrigir o relatório**

Em `spec/validation_report.md:96`, trocar `3 \`parcial\` · 5 \`ausente\`` por `4 \`parcial\` · 4 \`ausente\``.

Run: `python3 scripts/qa/contagem_validation_report.py`
Expected: `ok: contagem do validation_report confere`.

- [ ] **Step 6: Commit**

```bash
git add scripts/qa/contagem_validation_report.py scripts/qa/contagem_validation_report_test.py spec/validation_report.md
git commit -m "docs: corrige a contagem do validation_report e adiciona conferidor"
```

---

### Task 2: Checagem de porta 8765 em qualquer endereço

**Files:**
- Create: `scripts/qa/lib_rele.sh`
- Create: `scripts/qa/lib_rele_test.sh`
- Modify: `scripts/qa/acs_full_e2e.sh:31`, `scripts/qa/patient_full_e2e.sh:41`, `scripts/qa/push_e2e.sh:93`

**Interfaces:**
- Consumes: nada.
- Produces: `porta_ocupada <porta>` (função bash; exit 0 se alguém escuta na porta TCP em **qualquer** endereço).

- [ ] **Step 1: Escrever o teste que falha**

Criar `scripts/qa/lib_rele_test.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
# Teste hermético de scripts/qa/lib_rele.sh (porta_ocupada) e de que os três
# runners do relé a usam. Não precisa de emulador nem de Docker.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
# shellcheck disable=SC1091
source scripts/qa/lib_rele.sh
falhas=0
confere() { "$@" || { echo "FALHOU: $*"; falhas=$((falhas + 1)); }; }
nega() { if "$@"; then echo "FALHOU (esperava falso): $*"; falhas=$((falhas + 1)); fi; }

porta="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
nega porta_ocupada "$porta"

for endereco in 127.0.0.1 0.0.0.0 ::; do
  python3 -c '
import socket, sys, time
familia = socket.AF_INET6 if ":" in sys.argv[1] else socket.AF_INET
s = socket.socket(familia)
s.bind((sys.argv[1], int(sys.argv[2])))
s.listen()
time.sleep(30)' "$endereco" "$porta" 2>/dev/null &
  pid=$!
  for _ in $(seq 1 20); do porta_ocupada "$porta" && break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then
    confere porta_ocupada "$porta"
  else
    echo "pulado: este host não consegue escutar em $endereco"
  fi
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  for _ in $(seq 1 20); do porta_ocupada "$porta" || break; sleep 0.1; done
done

for f in acs_full_e2e.sh patient_full_e2e.sh push_e2e.sh; do
  nega grep -qF "grep -q '127.0.0.1:8765 '" "scripts/qa/$f"
  confere grep -q "porta_ocupada 8765" "scripts/qa/$f"
done

[[ "$falhas" -eq 0 ]] && echo "ok: lib_rele" || { echo "$falhas falha(s)"; exit 1; }
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./scripts/qa/lib_rele_test.sh`
Expected: FAIL — `source: scripts/qa/lib_rele.sh: No such file or directory` (e, sem `set -e`, as asserções seguintes também falham).

- [ ] **Step 3: Implementação mínima**

Criar `scripts/qa/lib_rele.sh`:

```bash
# Funções compartilhadas pelos runners que sobem o relé do OTP (otp_relay.py).
# Uso: source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"

# Sucesso (0) se ALGUM processo escuta na porta TCP $1, em qualquer endereço
# (127.0.0.1, 0.0.0.0, [::] ou o IP da rede). Um relé antigo esquecido num
# deles responderia com código velho; olhar só 127.0.0.1 deixava passar os
# outros e o erro só aparecia no bind do relé novo, sem dizer o motivo.
porta_ocupada() {
  ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN
}
```

Trocar nos três scripts, com um passo único (cada arquivo tem exatamente uma ocorrência):

```bash
python3 - <<'EOF'
import pathlib
for nome in ("acs_full_e2e.sh", "patient_full_e2e.sh", "push_e2e.sh"):
    p = pathlib.Path("scripts/qa") / nome
    s = p.read_text()
    antigo = "if ss -ltn 2>/dev/null | grep -q '127.0.0.1:8765 '; then"
    assert s.count(antigo) == 1, f"{nome}: esperava 1 ocorrência"
    s = s.replace(antigo, "if porta_ocupada 8765; then")
    marca = "set -euo pipefail\n"
    assert marca in s, f"{nome}: sem 'set -euo pipefail'"
    s = s.replace(marca, marca + 'source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"\n', 1)
    p.write_text(s)
EOF
```

- [ ] **Step 4: Rodar e ver passar**

Run: `./scripts/qa/lib_rele_test.sh && for f in acs_full_e2e patient_full_e2e push_e2e; do bash -n scripts/qa/$f.sh && echo "sintaxe ok: $f"; done`
Expected: `ok: lib_rele` (linhas "pulado" são aceitáveis) e três `sintaxe ok`.

- [ ] **Step 5: Commit**

```bash
git add scripts/qa/lib_rele.sh scripts/qa/lib_rele_test.sh scripts/qa/acs_full_e2e.sh scripts/qa/patient_full_e2e.sh scripts/qa/push_e2e.sh
git commit -m "fix(qa): checagem da porta 8765 enxerga qualquer endereço, não só 127.0.0.1"
```

---

### Task 3: Senha do ACS servida uma única vez pelo relé

**Files:**
- Modify: `scripts/qa/otp_relay.py` (cabeçalho, `Handler`, rota `/acs`)
- Modify: `scripts/qa/otp_relay_test.py`

**Interfaces:**
- Consumes: `acs_do_manifesto(caminho)` e `Handler` de `otp_relay.py` (Task 4 do plano anterior).
- Produces: `Handler.acs_entregue: bool` (atributo de classe; `GET /acs` responde 200 uma vez por processo e 404 depois).

- [ ] **Step 1: Escrever o teste que falha**

Acrescentar a `scripts/qa/otp_relay_test.py`, antes do `if __name__ == "__main__":`:

```python
class AcsEntregaUnicaTest(unittest.TestCase):
    """Qualquer app do emulador alcança localhost:8765 (adb reverse): a senha
    sintética do ACS só pode sair uma vez por execução do relé."""

    def setUp(self):
        import json
        import os
        import tempfile
        import threading
        from http.server import HTTPServer

        import otp_relay

        self.otp_relay = otp_relay
        arquivo = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        json.dump({"acs": {"matricula": "E2E-1", "password": "s"}}, arquivo)
        arquivo.close()
        self.caminho = arquivo.name
        os.environ["E2E_FIXTURES_FILE"] = self.caminho
        otp_relay.Handler.acs_entregue = False
        self.servidor = HTTPServer(("127.0.0.1", 0), otp_relay.Handler)
        otp_relay.Handler.porta = self.servidor.server_address[1]
        threading.Thread(target=self.servidor.serve_forever, daemon=True).start()

    def tearDown(self):
        import os

        self.servidor.shutdown()
        self.servidor.server_close()
        os.environ.pop("E2E_FIXTURES_FILE", None)
        os.unlink(self.caminho)
        self.otp_relay.Handler.porta = 8765
        self.otp_relay.Handler.acs_entregue = False

    def _get(self):
        import urllib.error
        import urllib.request

        url = f"http://127.0.0.1:{self.servidor.server_address[1]}/acs"
        try:
            with urllib.request.urlopen(url) as resposta:
                return resposta.status
        except urllib.error.HTTPError as erro:
            return erro.code

    def test_serve_uma_vez_e_depois_404(self):
        self.assertEqual(self._get(), 200)
        self.assertEqual(self._get(), 404)
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd scripts/qa && python3 otp_relay_test.py AcsEntregaUnicaTest`
Expected: FAIL — `AssertionError: 200 != 404` (o segundo pedido ainda recebe a senha).

- [ ] **Step 3: Implementação mínima**

Em `scripts/qa/otp_relay.py`:

1. No docstring do módulo, acrescentar o parágrafo:

```
`/acs` (só com E2E_FIXTURES_FILE) entrega a matrícula e a senha SINTÉTICAS do ACS
da execução, **uma única vez por processo**: qualquer app do emulador que alcance
localhost:8765 (adb reverse) poderia lê-las, então depois do primeiro pedido bem
sucedido — o do teste, no começo — a rota responde 404. O relé é por execução.
```

2. Em `class Handler`, junto de `porta` e `container`:

```python
    acs_entregue = False
```

3. Na rota `/acs`, trocar a condição e marcar a entrega:

```python
        if url.path == "/acs":
            credencial = acs_do_manifesto(os.environ.get("E2E_FIXTURES_FILE"))
            if credencial is None or Handler.acs_entregue:
                self.send_error(404); return
            Handler.acs_entregue = True
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
            self.wfile.write(json.dumps(credencial).encode())
            return
```

- [ ] **Step 4: Rodar e ver passar (suíte inteira do relé)**

Run: `cd scripts/qa && python3 otp_relay_test.py`
Expected: `OK` (os 9 testes anteriores + 1 novo = 10).

- [ ] **Step 5: Commit**

```bash
git add scripts/qa/otp_relay.py scripts/qa/otp_relay_test.py
git commit -m "fix(qa): relé serve a senha sintética do ACS uma única vez por execução"
```

---

### Task 4: Asserção de microárea (RNF06) conferida também no servidor

**Files:**
- Modify: `apps/acs/integration_test/full_journey_e2e.dart` (seletor e checagem final)

**Interfaces:**
- Consumes: `acsCredentialFromRelay()`, `e2ePatient(role)` de `support/e2e_acs.dart`; `acsClient` (cliente separado, já criado no fim do teste); `api.Client.patients.listMicroArea({required String accessToken}) → Future<List<MicroAreaPatient>>`; Task 3 (o `acs_full_e2e.sh` lê `/acs` uma vez só).
- Produces: nada além do teste.

A UI esconde o paciente de fora por filtro de tela *e* por regra do servidor; a regra é do servidor. A asserção passa a olhar o servidor (e a tela passa a provar que o filtro de busca está vazio, para o `findsOneWidget` do paciente da microárea não ser enganado por um filtro).

- [ ] **Step 1: Escrever a asserção (invertida) e ver que o teste a pega**

Em `apps/acs/integration_test/full_journey_e2e.dart`, logo depois do `final acs = await acsClient.auth.loginInstitutional(...)`, acrescentar:

```dart
    // RNF06 no servidor: a lista da microárea nunca traz o paciente de fora.
    // Quem garante é o backend, não o filtro do seletor.
    final daMicroarea = await acsClient.patients.listMicroArea(accessToken: acs.accessToken);
    expect(daMicroarea.any((p) => p.patientId == main.id), isTrue);
    expect(daMicroarea.any((p) => p.patientId == outsider.id), isTrue, reason: 'MUTAÇÃO TEMPORÁRIA: deve falhar');
```

(`isTrue` em `outsider` é **de propósito**: prova que a asserção morde.)

Run: `./scripts/qa/acs_full_e2e.sh`
Expected: FAIL com `MUTAÇÃO TEMPORÁRIA: deve falhar` (e o manifesto `.e2e/fixtures.json` apagado pelo `cleanup`).

- [ ] **Step 2: Corrigir a asserção e provar o filtro vazio na tela**

Trocar a linha mutada por:

```dart
    expect(daMicroarea.any((p) => p.patientId == outsider.id), isFalse, reason: 'outra microárea');
```

E, no trecho do seletor (logo depois de `expect(find.byKey(Key('patient_${main.id}')), findsOneWidget);`), acrescentar:

```dart
    // O seletor não pode estar filtrado: sem isto, "o de fora não aparece"
    // poderia ser só um filtro por nome escondendo tudo o que não casa.
    final busca = tester.widget<TextField>(find.byKey(const Key('patient_search')));
    expect(busca.controller!.text, isEmpty, reason: 'o seletor deve abrir sem filtro de busca');
```

- [ ] **Step 3: Rodar e ver passar**

Run: `cd apps/acs && flutter analyze integration_test/full_journey_e2e.dart; cd ../.. && ./scripts/qa/acs_full_e2e.sh`
Expected: `No issues found!` e `OK — jornada completa do ACS contra o banco de teste`. Esta execução também exercita as Tasks 2 e 3 (porta e `/acs` de uso único).

- [ ] **Step 3b: Devolver a stack de desenvolvimento**

Run: `docker compose up -d && docker compose ps --format '{{.Name}} {{.Status}}' | grep serverpod`
Expected: `sinalacs-serverpod … (healthy)`; `ls .e2e/fixtures.json` → `No such file`.

- [ ] **Step 4: Commit**

```bash
git add apps/acs/integration_test/full_journey_e2e.dart
git commit -m "test(acs): confere RNF06 também no servidor e exige seletor sem filtro"
```

---

### Task 5: Script de GPS — guarda de reinstalação, erro do build visível, limpeza ao sair

**Files:**
- Create: `scripts/qa/acs_gps_e2e_test.sh`
- Modify: `scripts/qa/acs_gps_e2e.sh` (reescrita do corpo; cabeçalho mantido e ampliado)

**Interfaces:**
- Consumes: `integration_test/geofence_gps_e2e.dart` e `test_driver/integration_test.dart` (já existem).
- Produces: `acs_gps_e2e.sh [--sem-permissao] [--reinstalar]` com exit 0 = ok, 2 = argumento inválido, 3 = app já instalado sem `--reinstalar`, 4 = sem emulador, 1 = build/teste falhou; `MQTT_ACS_PASSWORD` pode vir do ambiente (o `.env` passa a ser opcional). O script **remove o app de teste ao sair** se foi ele quem o instalou.

- [ ] **Step 1: Escrever o teste hermético que falha**

Criar `scripts/qa/acs_gps_e2e_test.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
# Teste hermético de scripts/qa/acs_gps_e2e.sh: adb e flutter FALSOS no PATH.
# Não precisa de emulador, de Docker nem do .env (a senha vai pelo ambiente).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
export FAKE_LOG="$tmp/chamadas.log"

cat >"$tmp/bin/adb" <<'EOF'
#!/usr/bin/env bash
echo "adb $*" >>"$FAKE_LOG"
case "$*" in
  *get-state*) echo device ;;
  *"pm list packages"*) [[ "${FAKE_INSTALADO:-0}" == 1 ]] && echo "package:br.com.prismrr.sinalacs.acs" ;;
  *"dumpsys window"*) [[ "${FAKE_DIALOGO:-0}" == 1 ]] && echo "mCurrentFocus=Window{1 u0 com.google.android.permissioncontroller/x.GrantPermissionsActivity}" ;;
  *"dumpsys package"*) [[ "${FAKE_FIXADA:-0}" == 1 ]] && echo "android.permission.ACCESS_FINE_LOCATION: granted=false, flags=[ USER_SET|USER_FIXED ]" ;;
esac
exit 0
EOF
cat >"$tmp/bin/flutter" <<'EOF'
#!/usr/bin/env bash
echo "flutter $*" >>"$FAKE_LOG"
case "$1" in
  build) [[ "${FAKE_BUILD_FALHA:-0}" == 1 ]] && { echo "ERRO-FALSO-DO-GRADLE: sem espaço" >&2; exit 1; } ;;
  drive) [[ "${FAKE_DRIVE_FALHA:-0}" == 1 ]] && exit 1 ;;
esac
exit 0
EOF
chmod +x "$tmp/bin/"*

falhas=0
caso() { # caso <nome> [VAR=valor ...] -- [args do script]
  nome=$1; shift
  envs=(); while [[ $# -gt 0 && $1 != -- ]]; do envs+=("$1"); shift; done; shift
  : >"$FAKE_LOG"
  saida="$(env PATH="$tmp/bin:$PATH" MQTT_ACS_PASSWORD=x "${envs[@]}" ./scripts/qa/acs_gps_e2e.sh "$@" 2>&1)"; codigo=$?
}
verifica() { eval "$1" || { echo "FALHOU [$nome]: $1"; echo "$saida" | tail -4; falhas=$((falhas + 1)); }; }
conta() { grep -c "$1" "$FAKE_LOG" || true; }

caso guarda FAKE_INSTALADO=1 --
verifica '[[ $codigo -eq 3 ]]'
verifica 'grep -q "APAGA" <<<"$saida"'
verifica '[[ $(conta uninstall) -eq 0 ]]'
verifica '[[ $(conta "^flutter build") -eq 0 ]]'

caso build_falha FAKE_BUILD_FALHA=1 --
verifica '[[ $codigo -ne 0 ]]'
verifica 'grep -q "o build do APK falhou" <<<"$saida"'
verifica 'grep -q "ERRO-FALSO-DO-GRADLE" <<<"$saida"'
verifica '[[ $(conta "install -r") -eq 0 ]]'

caso reinstalar FAKE_INSTALADO=1 -- --reinstalar
verifica '[[ $codigo -eq 0 ]]'
verifica '[[ $(conta uninstall) -eq 2 ]]'   # antes de instalar e ao sair

caso drive_falha FAKE_DRIVE_FALHA=1 --
verifica '[[ $codigo -ne 0 ]]'
verifica '[[ $(conta uninstall) -eq 1 ]]'   # o app de teste não fica para a próxima rodada

caso ok --
verifica '[[ $codigo -eq 0 ]]'
verifica 'grep -q "fix de GPS não verificado" <<<"$saida"'

caso argumento_invalido -- --nao-existe
verifica '[[ $codigo -eq 2 ]]'

[[ "$falhas" -eq 0 ]] && echo "ok: acs_gps_e2e" || { echo "$falhas falha(s)"; exit 1; }
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `./scripts/qa/acs_gps_e2e_test.sh`
Expected: FAIL em vários casos — `guarda` (o script atual desinstala sem perguntar e sai 0), `build_falha` (sem mensagem), `reinstalar`/`drive_falha` (contagem de `uninstall` errada) e `argumento_invalido`.

- [ ] **Step 3: Implementação**

Reescrever `scripts/qa/acs_gps_e2e.sh` (mantendo o cabeçalho de comentário atual e acrescentando, depois dele, o parágrafo abaixo). O corpo:

```bash
# GUARDA: se o app do ACS já estiver instalado no emulador, o script aborta
# (exit 3) — reinstalar APAGA a fila de visitas offline (SQLCipher) e a chave do
# Keystore do app de desenvolvimento. `--reinstalar` autoriza. O script é dono
# do pacote enquanto roda e o remove ao sair, para a próxima rodada não esbarrar
# na própria guarda.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${MQTT_ACS_PASSWORD:?exporte MQTT_ACS_PASSWORD ou rode ./scripts/dev/bootstrap_env.sh}"
cd apps/acs

dev=emulator-5554
pkg=br.com.prismrr.sinalacs.acs
apk=build/app/outputs/flutter-apk/app-debug.apk
expect=granted
reinstalar=0
for arg in "$@"; do
  case "$arg" in
    --sem-permissao) expect=denied ;;
    --reinstalar) reinstalar=1 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

instalado() { adb -s "$dev" shell pm list packages "$pkg" 2>/dev/null | grep -q "^package:$pkg\$"; }
if instalado && [[ "$reinstalar" -eq 0 ]]; then
  echo "erro: $pkg já está instalado em $dev." >&2
  echo "      Reinstalar APAGA a fila de visitas offline (SQLCipher) e a chave do Keystore deste aparelho." >&2
  echo "      Se for só o app de teste de uma execução anterior, rode de novo com --reinstalar." >&2
  exit 3
fi

log="$(mktemp)"
instalamos=0
limpar() {
  rm -f "$log"
  if [[ "$instalamos" -eq 1 ]]; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
}
trap limpar EXIT

if ! flutter build apk --debug --target=integration_test/geofence_gps_e2e.dart \
    --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" \
    --dart-define=EXPECT_PERMISSION="$expect" >"$log" 2>&1; then
  echo "erro: o build do APK falhou. Últimas linhas:" >&2
  tail -n 30 "$log" >&2
  exit 1
fi
if instalado; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
adb -s "$dev" install -r "$apk" >/dev/null
instalamos=1
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
  if [[ "$expect" == granted ]]; then
    adb -s "$dev" shell pm grant "$pkg" "android.permission.$p"
  else
    adb -s "$dev" shell pm revoke "$pkg" "android.permission.$p" || true
  fi
done

flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/geofence_gps_e2e.dart -d "$dev" \
  --use-application-binary="$apk" \
  --dart-define=EXPECT_PERMISSION="$expect"
echo "OK — permissão de localização em runtime ($expect); fix de GPS não verificado"
```

Também atualizar a linha de uso do cabeçalho: `#   ./scripts/qa/acs_gps_e2e.sh [--sem-permissao] [--reinstalar]`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash -n scripts/qa/acs_gps_e2e.sh && ./scripts/qa/acs_gps_e2e_test.sh`
Expected: `ok: acs_gps_e2e`.

- [ ] **Step 5: Provar no emulador (concedida) e ver a guarda real**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
./scripts/qa/acs_gps_e2e.sh; echo "exit=$?"      # há APK de teste de rodadas anteriores: deve abortar com 3
./scripts/qa/acs_gps_e2e.sh --reinstalar; echo "exit=$?"
adb -s emulator-5554 shell pm list packages br.com.prismrr.sinalacs.acs | wc -l
```
Expected: primeiro `exit=3` com a mensagem "APAGA…" (se o emulador estiver sem o app, `exit=0` — então rode só o segundo); depois `OK — permissão de localização em runtime (granted); fix de GPS não verificado`, `exit=0`, e o último comando imprime `0` (app removido ao sair).

- [ ] **Step 6: Commit**

```bash
git add scripts/qa/acs_gps_e2e.sh scripts/qa/acs_gps_e2e_test.sh
git commit -m "fix(qa): script de GPS avisa antes de apagar o app, mostra o erro do build e limpa ao sair"
```

---

### Task 6: Permissão "negada de vez" (`deniedForever`) no e2e de GPS

**Files:**
- Modify: `scripts/qa/acs_gps_e2e.sh` (negar de vez, amostrador de diálogo)
- Modify: `scripts/qa/acs_gps_e2e_test.sh` (casos novos)
- Modify: `apps/acs/integration_test/geofence_gps_e2e.dart` (modos `denied_forever` e `prime`)

**Interfaces:**
- Consumes: Task 5 (estrutura do script, `limpar`, `instalado`, `FAKE_*` do teste).
- Produces: `--sem-permissao` passa a significar "negada de vez" (`USER_FIXED`), o estado de um ACS que já recusou duas vezes; `EXPECT_PERMISSION` ∈ `granted | denied_forever | prime`; exit 5 = não foi possível levar a permissão a `USER_FIXED`; o script falha (exit 1) se o diálogo de permissão do sistema aparecer por cima do app.

**Por que não `pm set-permission-flags`:** não existe neste Android (ver "Estado verificado"). O caminho é recusar o diálogo do sistema duas vezes com `uiautomator` + `input tap` (no Android 11+, dois "Não permitir" tornam a negação permanente), e **conferir** o resultado em `dumpsys package` (`granted=false` com `USER_FIXED`). O cenário antigo (revogada mas ainda pedível) é descartado: deixava o diálogo aberto por cima do app, e o teste de widget do Flutter nem percebia.

- [ ] **Step 1: Medir os ids reais dos botões do diálogo**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
./scripts/qa/acs_gps_e2e.sh --sem-permissao --reinstalar > /tmp/claude-1000/gps_med.log 2>&1 &
sleep 40   # (medição manual, uma vez) — com o diálogo na tela:
adb -s emulator-5554 exec-out uiautomator dump /dev/tty | grep -o 'resource-id="com.android.permissioncontroller[^"]*"' | sort -u
```
Expected: uma lista contendo `permission_deny_button` e/ou `permission_deny_and_dont_ask_again_button`. Se os ids forem **outros**, troque os dois nomes em `tocar_recusar` (Step 3) pelos medidos, e registre no commit. Se o diálogo não aparecer (nenhum `resource-id` do `permissioncontroller`), vá para **Step 8 (fallback)**.

- [ ] **Step 2: Escrever os testes herméticos que falham**

Em `scripts/qa/acs_gps_e2e_test.sh`, antes da linha `[[ "$falhas" -eq 0 ]] && …`, acrescentar:

```bash
caso dialogo FAKE_DIALOGO=1 --
verifica '[[ $codigo -ne 0 ]]'
verifica 'grep -q "diálogo de permissão" <<<"$saida"'

caso sem_permissao FAKE_FIXADA=1 -- --sem-permissao
verifica '[[ $codigo -eq 0 ]]'
verifica '[[ $(conta "pm revoke") -eq 2 ]]'
verifica 'grep -q "EXPECT_PERMISSION=denied_forever" "$FAKE_LOG"'
verifica '[[ $(conta "EXPECT_PERMISSION=prime") -eq 0 ]]'   # já fixada: não precisa recusar de novo

caso nao_fixa FAKE_FIXADA=0 -- --sem-permissao
verifica '[[ $codigo -eq 5 ]]'
verifica 'grep -q "USER_FIXED" <<<"$saida"'
verifica '[[ $(conta "EXPECT_PERMISSION=prime") -eq 3 ]]'
```

Run: `./scripts/qa/acs_gps_e2e_test.sh`
Expected: FAIL nos três casos novos (o script ainda não tem amostrador, nem `denied_forever`, nem exit 5).

- [ ] **Step 3: Implementar no script**

Em `scripts/qa/acs_gps_e2e.sh`:

1. `--sem-permissao) expect=denied_forever ;;`.

2. Antes do bloco `for p in ACCESS_FINE_LOCATION …`, definir as funções:

```bash
# "Negada de vez" = granted=false com USER_FIXED (o app não consegue mais abrir o diálogo).
negada_de_vez() {
  adb -s "$dev" shell dumpsys package "$pkg" | grep -Eq 'ACCESS_FINE_LOCATION: granted=false, flags=\[[^]]*USER_FIXED'
}

# Toca em "Não permitir" no diálogo de permissão do sistema, se ele estiver na tela.
tocar_recusar() {
  local xml xy
  xml="$(adb -s "$dev" exec-out uiautomator dump /dev/tty 2>/dev/null || true)"
  xy="$(python3 - "$xml" <<'PY'
import re, sys
xml = sys.argv[1]
for rid in ("permission_deny_and_dont_ask_again_button", "permission_deny_button"):
    m = re.search(r'resource-id="com\.android\.permissioncontroller:id/%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' % rid, xml)
    if m:
        x1, y1, x2, y2 = map(int, m.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
)"
  if [[ -n "$xy" ]]; then adb -s "$dev" shell input tap $xy; fi
  return 0
}

# Não há `pm set-permission-flags` neste Android (medido): a única forma de chegar a
# USER_FIXED é recusar o diálogo do sistema de verdade. Roda o teste em modo `prime`
# (ele só abre o painel e deixa o app pedir a permissão) com um tocador recusando.
negar_de_vez() {
  local tentativa tocador
  for tentativa in 1 2 3; do
    if negada_de_vez; then return 0; fi
    ( while true; do tocar_recusar; sleep 1; done ) &
    tocador=$!
    flutter drive --driver=test_driver/integration_test.dart \
      --target=integration_test/geofence_gps_e2e.dart -d "$dev" \
      --use-application-binary="$apk" --dart-define=EXPECT_PERMISSION=prime || true
    kill "$tocador" 2>/dev/null || true
  done
  negada_de_vez
}
```

3. O bloco de permissões passa a ser:

```bash
if [[ "$expect" == granted ]]; then
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
    adb -s "$dev" shell pm grant "$pkg" "android.permission.$p"
  done
else
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
    adb -s "$dev" shell pm revoke "$pkg" "android.permission.$p" || true
  done
  negar_de_vez || { echo "erro: não consegui levar a permissão a USER_FIXED (negada de vez) em 3 tentativas." >&2; exit 5; }
fi
```

4. Amostrador do diálogo e o `drive` final (substituindo o `flutter drive` e o `echo` finais). Declarar `amostras=""` e `amostrador=""` junto de `instalamos=0`, e estender `limpar()`:

```bash
limpar() {
  rm -f "$log" "$amostras"
  if [[ -n "$amostrador" ]]; then kill "$amostrador" 2>/dev/null || true; fi
  if [[ "$instalamos" -eq 1 ]]; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
}
```

e no fim do script:

```bash
# O teste de widget do Flutter injeta toques no próprio Flutter e NÃO percebe um diálogo
# do sistema aberto por cima do app. Quem percebe é o foco da janela, amostrado durante a execução.
amostras="$(mktemp)"
amostrar() { adb -s "$dev" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus >>"$amostras" || true; }
( while true; do amostrar; sleep 1; done ) &
amostrador=$!

drive_rc=0
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/geofence_gps_e2e.dart -d "$dev" \
  --use-application-binary="$apk" \
  --dart-define=EXPECT_PERMISSION="$expect" || drive_rc=$?
amostrar   # uma leitura final garante ao menos uma amostra mesmo num teste curto
kill "$amostrador" 2>/dev/null || true; amostrador=""
if grep -q permissioncontroller "$amostras"; then
  echo "erro: o diálogo de permissão do sistema apareceu por cima do app durante o teste." >&2
  exit 1
fi
if [[ "$drive_rc" -ne 0 ]]; then exit "$drive_rc"; fi
echo "OK — permissão de localização em runtime ($expect); fix de GPS não verificado"
```

(Ajustar `limpar` do Task 5: o `amostras="$(mktemp)"` fica antes do `trap`, no mesmo ponto em que `log` é criado, para o `rm -f` funcionar mesmo em saída antecipada: declarar `amostras=""`/`amostrador=""` no topo e atribuir `amostras` ao chegar nesse bloco.)

- [ ] **Step 4: Rodar os testes herméticos**

Run: `bash -n scripts/qa/acs_gps_e2e.sh && ./scripts/qa/acs_gps_e2e_test.sh`
Expected: `ok: acs_gps_e2e` (os casos da Task 5 continuam verdes; o caso `nao_fixa` leva ~3 s por causa do `sleep 1` do tocador).

- [ ] **Step 5: Ajustar o teste Dart aos modos novos**

Em `apps/acs/integration_test/geofence_gps_e2e.dart`:

1. Atualizar o comentário da constante e o bloco da permissão. Trocar o `if (_expect == 'granted') {…} else {…}` inicial por:

```dart
    final permission = await Geolocator.checkPermission();
    if (_expect == 'granted') {
      expect(permission, anyOf(LocationPermission.whileInUse, LocationPermission.always),
          reason: 'o manifesto precisa declarar ACCESS_FINE_LOCATION para a permissão existir');
    } else if (_expect == 'denied_forever') {
      // Negada de vez (USER_FIXED): o `requestPermission` volta na hora, sem diálogo.
      // (`checkPermission` sozinho devolve `denied`: só o pedido distingue o "de vez".)
      expect(permission, isNot(anyOf(LocationPermission.whileInUse, LocationPermission.always)));
      expect(await Geolocator.requestPermission(), LocationPermission.deniedForever);
    }
    // `prime`: não asserta nada sobre a permissão; só deixa o app pedi-la para o script
    // do emulador recusar o diálogo (ver scripts/qa/acs_gps_e2e.sh, `negar_de_vez`).
```

2. Trocar `if (_expect == 'denied') {` (mais abaixo) por `if (_expect == 'denied_forever') {`.

3. No comentário do cabeçalho, trocar "concede ou revoga a permissão por `pm`" por "concede por `pm` ou leva a permissão a negada-de-vez recusando o diálogo".

Run: `cd apps/acs && flutter analyze integration_test/geofence_gps_e2e.dart`
Expected: `No issues found!`.

- [ ] **Step 6: Provar no emulador — negada de vez**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
./scripts/qa/acs_gps_e2e.sh --sem-permissao --reinstalar; echo "exit=$?"
```
Expected: `OK — permissão de localização em runtime (denied_forever); fix de GPS não verificado`, `exit=0`. Se sair `exit=5`, o tocador não recusou o diálogo: volte ao Step 1 (ids) ou ao Step 8.

Prova contrária (RED real do cenário antigo): antes de implementar o Step 3, rodar a versão da Task 5 com `--sem-permissao --reinstalar` **mais o amostrador** mostra `erro: o diálogo de permissão do sistema apareceu…` (o cenário antigo deixava o diálogo aberto); depois do Step 3 o amostrador não vê o diálogo.

- [ ] **Step 7: Confirmar a concedida e commitar**

```bash
./scripts/qa/acs_gps_e2e.sh --reinstalar; echo "exit=$?"
git add scripts/qa/acs_gps_e2e.sh scripts/qa/acs_gps_e2e_test.sh apps/acs/integration_test/geofence_gps_e2e.dart
git commit -m "test(acs): permissão negada de vez e checagem de diálogo do sistema no e2e de GPS"
```
Expected: `OK — … (granted) …`, `exit=0`.

- [ ] **Step 8: Fallback (só se o Step 1 ou o Step 6 mostrarem que recusar o diálogo não funciona neste AVD)**

Não é "pular o item": registre a decisão. Reverter `negar_de_vez`/`tocar_recusar`/`prime` (`git checkout -- scripts/qa/acs_gps_e2e.sh apps/acs/integration_test/geofence_gps_e2e.dart`), **manter** o amostrador de diálogo e os casos `dialogo` do teste, voltar `--sem-permissao` ao `pm revoke` e documentar no cabeçalho de `geofence_gps_e2e.dart` e no `PROGRESS.md`: "o caso `deniedForever` não é simulável neste AVD: `pm set-permission-flags` não existe e o diálogo não pôde ser recusado por `uiautomator` (medido em AAAA-MM-DD, motivo: …); coberto apenas por revisão". Commit: `docs(acs): registra o limite do cenário deniedForever no AVD`.

---

### Task 7: Documentação e barra final

**Files:**
- Modify: `PROGRESS.md` (seção "Finalização do app ACS (2026-10-01)")
- Modify: `apps/CLAUDE.md` (parágrafo "ACS: permissões, SAMU e e2e")

**Interfaces:** consome as Tasks 1–6.

- [ ] **Step 1: Atualizar os textos**

- `PROGRESS.md`, na seção "Finalização do app ACS (2026-10-01)", acrescentar um item "**Minors da revisão — fechados:**" listando os 7 (contagem do relatório com conferidor `scripts/qa/contagem_validation_report.py`; `deniedForever` simulado por recusa real do diálogo — ou o fallback, se foi o caso —; o script de GPS aborta se o app já está instalado e exige `--reinstalar`, mostra o erro do build e remove o app de teste ao sair; RNF06 conferido também por `patients.listMicroArea` e com seletor sem filtro; `/acs` servido uma vez por execução; checagem de porta em qualquer endereço via `scripts/qa/lib_rele.sh`).
- `apps/CLAUDE.md`, no parágrafo "ACS: permissões, SAMU e e2e", trocar a frase de `acs_gps_e2e.sh` por: "`scripts/qa/acs_gps_e2e.sh [--sem-permissao] [--reinstalar]` prova a permissão em runtime — concedida, ou negada de vez (`USER_FIXED`), sempre com checagem de que o diálogo do sistema não aparece — e aborta se o app já estiver instalado (reinstalar apaga a fila SQLCipher e o Keystore; `--reinstalar` autoriza); não prova a chegada de um fix". Acrescentar: "O relé de OTP serve `/acs` (senha sintética do ACS, opt-in por `E2E_FIXTURES_FILE`) **uma única vez** por execução."

- [ ] **Step 2: Barra final**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
python3 scripts/qa/contagem_validation_report.py
(cd scripts/qa && python3 contagem_validation_report_test.py && python3 otp_relay_test.py)
./scripts/qa/lib_rele_test.sh && ./scripts/qa/acs_gps_e2e_test.sh
(cd apps/acs && flutter analyze && flutter test)
./scripts/qa/ci_invariants.sh && ./scripts/qa/check_documentation_links.sh
./scripts/qa/acs_gps_e2e.sh --reinstalar && ./scripts/qa/acs_gps_e2e.sh --sem-permissao --reinstalar
./scripts/qa/acs_full_e2e.sh; docker compose up -d
```
Expected: todos verdes: conferidor `ok`; Python `OK` (4 + 10 testes); `ok: lib_rele` e `ok: acs_gps_e2e`; `flutter analyze` sem problemas e `flutter test` ≥ 208; `ci_invariants` `ok: 9 grupos`; links sem erro; os dois GPS `OK`; jornada `OK`; `sinalacs-serverpod … (healthy)` e `ls .e2e/fixtures.json` → inexistente.

- [ ] **Step 3: Estado do repositório e commit**

```bash
git status --short && git log --oneline -9 && git log -9 --format=%B | grep -ci "co-authored\|generated with"
git add PROGRESS.md apps/CLAUDE.md
git commit -m "docs: registra o fechamento dos minors da revisão do app ACS"
```
Expected: árvore limpa depois do commit; `0` na contagem de atribuições de IA; sem push.

---

## Self-review

**Cobertura:** item 1 → Task 1; 2 → Task 6 (com medição e fallback explícito); 3 e 4 → Task 5; 5 → Task 4; 6 → Task 3; 7 → Task 2; documentação e barra → Task 7.

**Placeholders:** não há "TBD". Dois pontos dependem de medir no emulador e têm as duas saídas escritas: os ids dos botões do diálogo (Task 6, Step 1) e se recusar o diálogo chega a `USER_FIXED` (Task 6, Step 6 → Step 8 de fallback). O Step 6 também descreve a "prova contrária" em prosa, não como comando.

**Consistência de nomes:** `porta_ocupada` (Task 2) usado só nos 3 runners; `Handler.acs_entregue` (Task 3) só no relé; `instalado`, `limpar`, `instalamos`, `amostras`, `amostrador` definidos na Task 5/6 e usados no mesmo script; `EXPECT_PERMISSION` ∈ `granted|denied_forever|prime` coerente entre o `.sh`, o teste hermético (`grep "EXPECT_PERMISSION=denied_forever"`) e o Dart; exit codes 2/3/4/5/1 batem entre o script e o teste.

**Review Focus:** as 5 linhas têm teste dono (Task 5 `guarda` e `drive_falha`; Task 2; Task 3; Task 1).

**Riscos que só a execução resolve:** (1) o `uiautomator` achar e tocar o botão no Android 16 (Task 6 tem medição e fallback); (2) `ss -ltn "sport = :N"` em hosts sem IPv6 (o teste pula o endereço `::`); (3) o caso `nao_fixa` leva ~3 s por causa do tocador em loop.
