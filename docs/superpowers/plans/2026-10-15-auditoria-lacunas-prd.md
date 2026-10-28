# Auditoria de lacunas do PRD — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produzir um relatório verificado, item a item, de tudo que o `spec/PRD_system.md` pede e que ainda não está implementado (ou não está provado), com evidência medida hoje no código, e um backlog priorizado do que falta.

**Architecture:** Um relatório versionado em `docs/auditoria-prd/2026-10-15-lacunas-prd.md` com uma linha por ID do PRD (66 IDs: RF01–RF19, RNF01–RNF06, INV-01–05, LGPD-RF01/02/07/08/09/11, M1.1–M3.5, H1–H4, R1–R8), mais seções sem ID para SLOs (§4.1), STRIDE (§4.2.1), criptografia (§4.2.3), telemetria (§1.3) e módulos do backoffice (§2.1). Um conferidor determinístico (`scripts/qa/cobertura_prd.py`, no mesmo molde de `scripts/qa/contagem_validation_report.py`) falha se algum ID do PRD ficar sem linha, se houver ID inventado, status desconhecido ou — no modo `--final` — linha sem evidência ou sem "o que falta". As tarefas de verificação preenchem o relatório por grupo de requisitos; a última consolida o backlog.

**Tech Stack:** Python 3 (`unittest`, só biblioteca padrão) para o conferidor; `grep`/`graphify`, `dart test`, `flutter test` e os scripts de `scripts/qa/` para coletar evidência.

**Spec:** `spec/PRD_system.md` (fonte). Contexto obrigatório: `PROGRESS.md`, `CLAUDE.md` (raiz), `backend/CLAUDE.md`, `apps/CLAUDE.md`, `spec/lgpd_design.md`, `spec/ux_accessibility_assessment.md`.

## Global Constraints

- Idioma: relatório, mensagens do conferidor e commits em português.
- Este plano **não implementa** requisito nenhum: só mede e registra. Corrigir uma lacuna achada vira item do backlog (Task 9), não commit desta branch.
- Evidência é medida **hoje** no código (`caminho:linha`, nome de teste + comando rodado, ou script de `scripts/qa/` com data). `PROGRESS.md` e o próprio PRD servem de hipótese, nunca de prova: `spec/validation_report.md` está desatualizado nos dois sentidos (ver `CLAUDE.md`), e o PRD também tem trechos velhos (ex.: §4.2.2 ainda diz que nenhum endpoint de dados exercita `coordinator`/`admin`, o que a #40 fechou).
- Status permitidos, exatamente estes: `entregue`, `parcial`, `ausente`, `fora-do-mvp`, `externo`, `a-verificar` (este último proibido no modo `--final`).
- Regra de status:
  - `entregue` — código existe **e** há teste automatizado ou prova registrada (e2e com data) que exercita o critério de aceite do PRD.
  - `parcial` — código existe, mas o critério de aceite do PRD não é atingido ou não está provado (ex.: só Android, só emulador, só stack local, métrica não medida).
  - `ausente` — não há código para o requisito.
  - `fora-do-mvp` — `ausente` **e** listado em "Fora do Escopo MVP (v1.5+)" do §6.1. Requisito fora do MVP que já tem código recebe `entregue`/`parcial` normalmente.
  - `externo` — o lado do código está feito e o que falta depende de terceiro (DPO, jurídico, teste de campo, loja, provisionamento de conta).
- Formato de linha do relatório, sem `|` dentro das células: `| <ID> | <requisito curto> | **<status>** | <evidência> | <o que falta> |`.
- Nunca dado real de paciente em evidência, captura ou log (invariante do repo).
- Commits sem atribuição de IA (`CLAUDE.md` do repo prevalece sobre o padrão do harness).
- Depois de mudar código (só o conferidor), rodar `graphify update .`.

## Review Focus

- **ID do PRD com sufixo ou negrito diferente** (`| **RF19 (PRD)** *(proposto…)* |`, `| **R1 (Colisão)** |`): o conferidor precisa extrair `RF19` e `R1`, não ignorar a linha — teste `test_extrai_ids_com_sufixo_e_negrito` (Task 1).
- **`LGPD-RF19` citado em prosa** ("não confundir com LGPD-RF19") não pode virar ID obrigatório: só conta ID na primeira célula de uma linha de tabela — teste `test_ignora_id_citado_fora_da_primeira_celula` (Task 1).
- **Mesmo ID em duas tabelas do PRD** (R1–R8 aparecem na matriz de riscos e nos planos de contingência): uma linha no relatório basta; duas linhas no relatório são erro — testes `test_id_repetido_no_prd_conta_uma_vez` e `test_linha_duplicada_no_relatorio_e_erro` (Task 1).
- **Célula com `|` dentro ou coluna faltando** desalinha status e evidência em silêncio: o conferidor sai com 2, não aceita a linha — teste `test_coluna_a_mais_ou_a_menos_e_erro` (Task 1).
- **Status certo pelo motivo errado** — marcar `entregue` porque o `PROGRESS.md` diz: cada task de verificação exige o comando que produziu a evidência no passo "Registrar"; a Task 9 refaz por amostragem três linhas `entregue` escolhidas ao acaso e rebaixa a linha se a evidência não se reproduzir.

---

## Estrutura de arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `scripts/qa/cobertura_prd.py` | Criar | Extrai IDs do PRD, lê as linhas do relatório, aponta lacunas/IDs inventados/linhas malformadas. |
| `scripts/qa/cobertura_prd_test.py` | Criar | Testes herméticos do conferidor (fixtures inline). |
| `docs/auditoria-prd/2026-10-15-lacunas-prd.md` | Criar | O relatório: tabela por grupo + seções sem ID + backlog. |
| `PROGRESS.md` | Modificar (Task 9) | Uma seção curta apontando para o relatório. |

---

### Task 1: Conferidor de cobertura do PRD

**Files:**
- Create: `scripts/qa/cobertura_prd.py`
- Test: `scripts/qa/cobertura_prd_test.py`

**Interfaces:**
- Produces:
  - `STATUS: list[str]` — os seis status permitidos.
  - `ids_do_prd(texto: str) -> set[str]`
  - `linhas_do_relatorio(texto: str) -> dict[str, tuple[str, str, str]]` — `id -> (status, evidência, o_que_falta)`; levanta `Malformado`.
  - `conferir(prd: str, relatorio: str, final: bool = False) -> list[str]` — lista de erros, vazia se ok.
  - CLI: `python3 scripts/qa/cobertura_prd.py [--final]` → exit 0 ok, 1 lacuna, 2 malformado/uso errado.

- [ ] **Step 1: Escrever os testes que falham**

`scripts/qa/cobertura_prd_test.py`:

```python
import unittest

from cobertura_prd import Malformado, conferir, ids_do_prd, linhas_do_relatorio

PRD = """\
| ID | Requisito |
|----|-----------|
| **RF01** | Login |
| **RF19 (PRD)** *(proposto; não confundir com LGPD-RF19)* | Escalonar |
| **INV-01** | Microárea |
| LGPD-RF02 | Consentimento |
| M1.1 | Compose |
| H1 | Hipótese |
| **R1: Colisão** | Risco |
| **R1 (Colisão)** | Contingência |

Texto corrido citando RF02 e LGPD-RF19 não conta.
"""

RELATORIO_OK = """\
| ID | Requisito | Status | Evidência | O que falta |
|----|-----------|--------|-----------|-------------|
| RF01 | Login | **entregue** | `a.dart:1` | |
| RF19 | Escalonar | **parcial** | `b.dart:2` | prova em aparelho |
| INV-01 | Microárea | **entregue** | `c_test.dart` | |
| LGPD-RF02 | Consentimento | **externo** | `d.dart:3` | revisão do DPO |
| M1.1 | Compose | **entregue** | `docker-compose.yml` | |
| H1 | Hipótese | **externo** | — | teste de campo |
| R1 | Colisão | **ausente** | | UI de resolução |
"""


class IdsDoPrdTest(unittest.TestCase):
    def test_extrai_ids_com_sufixo_e_negrito(self):
        self.assertEqual(
            ids_do_prd(PRD),
            {"RF01", "RF19", "INV-01", "LGPD-RF02", "M1.1", "H1", "R1"},
        )

    def test_ignora_id_citado_fora_da_primeira_celula(self):
        ids = ids_do_prd(PRD)
        self.assertNotIn("LGPD-RF19", ids)
        self.assertNotIn("RF02", ids)

    def test_id_repetido_no_prd_conta_uma_vez(self):
        self.assertEqual(conferir(PRD, RELATORIO_OK), [])


class LinhasDoRelatorioTest(unittest.TestCase):
    def test_le_status_evidencia_e_falta(self):
        linhas = linhas_do_relatorio(RELATORIO_OK)
        self.assertEqual(linhas["RF19"], ("parcial", "`b.dart:2`", "prova em aparelho"))

    def test_status_desconhecido_e_erro(self):
        with self.assertRaises(Malformado):
            linhas_do_relatorio("| RF01 | Login | **pronto** | x | |\n")

    def test_status_sem_negrito_e_erro(self):
        with self.assertRaises(Malformado):
            linhas_do_relatorio("| RF01 | Login | entregue | x | |\n")

    def test_coluna_a_mais_ou_a_menos_e_erro(self):
        with self.assertRaises(Malformado):
            linhas_do_relatorio("| RF01 | Login | **entregue** | a | b | c |\n")
        with self.assertRaises(Malformado):
            linhas_do_relatorio("| RF01 | Login | **entregue** | a |\n")

    def test_linha_duplicada_no_relatorio_e_erro(self):
        with self.assertRaises(Malformado):
            linhas_do_relatorio(RELATORIO_OK + "| RF01 | Login | **entregue** | x | |\n")


class ConferirTest(unittest.TestCase):
    def test_id_do_prd_sem_linha_e_lacuna(self):
        relatorio = RELATORIO_OK.replace("| H1 | Hipótese | **externo** | — | teste de campo |\n", "")
        self.assertEqual(conferir(PRD, relatorio), ["H1: está no PRD e falta no relatório"])

    def test_id_inventado_e_erro(self):
        relatorio = RELATORIO_OK + "| RF20 | Inexistente | **ausente** | | tudo |\n"
        self.assertEqual(conferir(PRD, relatorio), ["RF20: está no relatório e não existe no PRD"])

    def test_a_verificar_passa_sem_final_e_falha_com_final(self):
        relatorio = RELATORIO_OK.replace("**entregue** | `a.dart:1`", "**a-verificar** | `a.dart:1`")
        self.assertEqual(conferir(PRD, relatorio), [])
        self.assertEqual(conferir(PRD, relatorio, final=True), ["RF01: ainda a-verificar"])

    def test_final_exige_evidencia_e_o_que_falta(self):
        relatorio = RELATORIO_OK.replace("**parcial** | `b.dart:2` | prova em aparelho", "**parcial** | | ")
        self.assertEqual(
            conferir(PRD, relatorio, final=True),
            ["RF19: parcial sem evidência", "RF19: parcial sem o que falta"],
        )

    def test_ausente_pode_ficar_sem_evidencia(self):
        self.assertEqual(conferir(PRD, RELATORIO_OK, final=True), [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `python3 -m unittest discover -s scripts/qa -p 'cobertura_prd_test.py' -v`
Expected: FAIL com `ModuleNotFoundError: No module named 'cobertura_prd'`.

- [ ] **Step 3: Implementar o conferidor**

`scripts/qa/cobertura_prd.py`:

```python
#!/usr/bin/env python3
"""Confere o relatório de lacunas do PRD contra os IDs de spec/PRD_system.md.

Todo ID que aparece na primeira célula de uma tabela do PRD (RFnn, RNFnn,
INV-nn, LGPD-RFnn, Mn.n, Hn, Rn) precisa de exatamente uma linha no
relatório. ID citado em prosa não conta: "não confundir com LGPD-RF19" não
cria requisito. Linha malformada (coluna a mais ou a menos, status sem
negrito ou fora da lista, ID duplicado) é exit 2, não linha ignorada:
ignorar tiraria o requisito da conta sem ninguém perceber.

Com --final, a-verificar é erro, entregue/parcial exigem evidência e
parcial/ausente/externo exigem "o que falta".
"""
import pathlib
import re
import sys

RELATORIO = "docs/auditoria-prd/2026-10-15-lacunas-prd.md"
STATUS = ["entregue", "parcial", "ausente", "fora-do-mvp", "externo", "a-verificar"]
ID = r"(?:RF\d{2}|RNF\d{2}|INV-\d{2}|LGPD-RF\d{2}|M\d\.\d|H\d|R\d)"
ID_NO_PRD = re.compile(rf"^\| \*{{0,2}}({ID})\b", re.M)
LINHA_RELATORIO = re.compile(rf"^\| ({ID}) \|(.*)$", re.M)
STATUS_NEGRITO = re.compile(r"\*\*([^*]+)\*\*")


class Malformado(Exception):
    pass


def ids_do_prd(texto):
    return set(ID_NO_PRD.findall(texto))


def linhas_do_relatorio(texto):
    linhas = {}
    for m in LINHA_RELATORIO.finditer(texto):
        ident = m.group(1)
        corpo = m.group(2).rstrip()
        if not corpo.endswith("|"):
            raise Malformado(f"{ident}: linha não termina em '|'")
        celulas = [c.strip() for c in corpo[:-1].split("|")]
        if len(celulas) != 4:
            raise Malformado(f"{ident}: esperava 5 colunas, achei {len(celulas) + 1}")
        _, status, evidencia, falta = celulas
        negrito = STATUS_NEGRITO.fullmatch(status)
        if not negrito:
            raise Malformado(f"{ident}: status sem negrito: {status!r}")
        if negrito.group(1) not in STATUS:
            raise Malformado(f"{ident}: status desconhecido: {negrito.group(1)!r}")
        if ident in linhas:
            raise Malformado(f"{ident}: linha duplicada")
        linhas[ident] = (negrito.group(1), evidencia, falta)
    return linhas


def conferir(prd, relatorio, final=False):
    ids = ids_do_prd(prd)
    linhas = linhas_do_relatorio(relatorio)
    erros = [f"{i}: está no PRD e falta no relatório" for i in sorted(ids - linhas.keys())]
    erros += [f"{i}: está no relatório e não existe no PRD" for i in sorted(linhas.keys() - ids)]
    if final:
        for ident, (status, evidencia, falta) in sorted(linhas.items()):
            if status == "a-verificar":
                erros.append(f"{ident}: ainda a-verificar")
            if status in ("entregue", "parcial") and not evidencia:
                erros.append(f"{ident}: {status} sem evidência")
            if status in ("parcial", "ausente", "externo") and not falta:
                erros.append(f"{ident}: {status} sem o que falta")
    return erros


def main(argv):
    final = "--final" in argv
    if [a for a in argv if a != "--final"]:
        print("uso: cobertura_prd.py [--final]", file=sys.stderr)
        return 2
    raiz = pathlib.Path(__file__).resolve().parents[2]
    prd = (raiz / "spec/PRD_system.md").read_text(encoding="utf-8")
    relatorio = (raiz / RELATORIO).read_text(encoding="utf-8")
    try:
        erros = conferir(prd, relatorio, final)
    except Malformado as erro:
        print(f"relatório malformado: {erro}", file=sys.stderr)
        return 2
    for erro in erros:
        print(erro, file=sys.stderr)
    if erros:
        return 1
    print(f"cobertura do PRD: {len(ids_do_prd(prd))} IDs, ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

Note on `test_ausente_pode_ficar_sem_evidencia`: em `RELATORIO_OK`, `R1` é `ausente` sem evidência e com "o que falta", e `H1` é `externo` com evidência `—` — os dois passam no `--final`.

- [ ] **Step 4: Rodar e ver passar**

Run: `python3 -m unittest discover -s scripts/qa -p 'cobertura_prd_test.py' -v`
Expected: 13 testes, `OK`.

- [ ] **Step 5: Conferir a extração contra o PRD real**

Run:
```bash
python3 - <<'EOF'
import sys; sys.path.insert(0, "scripts/qa")
import pathlib, cobertura_prd as c
ids = c.ids_do_prd(pathlib.Path("spec/PRD_system.md").read_text())
print(len(ids), sorted(ids))
EOF
```
Expected: `66` IDs — H1–H4, INV-01–05, LGPD-RF01/02/07/08/09/11, M1.1–M1.5, M2.1–M2.6, M3.1–M3.5, R1–R8, RF01–RF19, RNF01–RNF06. Se o número for outro, o PRD mudou desde 2026-10-15: registre a diferença no topo do relatório (Task 2) em vez de ajustar a regex para bater.

- [ ] **Step 6: Commit**

```bash
chmod +x scripts/qa/cobertura_prd.py
git add scripts/qa/cobertura_prd.py scripts/qa/cobertura_prd_test.py
git commit -m "test(qa): conferidor de cobertura do relatório de lacunas do PRD"
graphify update .
```

---

### Task 2: Esqueleto do relatório e linha de base dos testes

**Files:**
- Create: `docs/auditoria-prd/2026-10-15-lacunas-prd.md`

**Interfaces:**
- Consumes: `python3 scripts/qa/cobertura_prd.py` (Task 1).
- Produces: o relatório com os 66 IDs em `**a-verificar**`, agrupados nas seções que as Tasks 3–8 preenchem: `## Paciente`, `## ACS`, `## Núcleo, auditoria e backoffice`, `## Invariantes e segurança`, `## Não funcionais`, `## LGPD e dados`, `## Roadmap, hipóteses e riscos`, `## Backlog priorizado`. Cada task mexe só na sua seção.

- [ ] **Step 1: Medir a linha de base dos testes (uma vez, reutilizada pelas tasks seguintes)**

```bash
docker compose --profile test up -d postgres-test
(cd backend/sinalacs_server && dart test 2>&1 | tail -3)
(cd backend/sinalacs_server && dart test test/unit 2>&1 | tail -3)
for app in patient acs admin; do (cd apps/$app && flutter test 2>&1 | tail -2); done
python3 -m unittest discover -s scripts/qa -p '*_test.py' 2>&1 | tail -3
git rev-parse --short HEAD
```

Anote contagem de testes, falhas e o SHA. Se algum suíte falhar, **não conserte**: registre a falha no topo do relatório; qualquer linha cuja evidência dependa de um teste que falha não pode ser `entregue`.

- [ ] **Step 2: Escrever o esqueleto**

Cabeçalho do arquivo:

```markdown
# Lacunas do PRD — auditoria de 2026-10-15

Fonte: `spec/PRD_system.md` no commit `<SHA>`. Cada linha foi medida no código neste commit;
`PROGRESS.md` serviu de hipótese, não de prova. Conferência: `python3 scripts/qa/cobertura_prd.py --final`.

**Linha de base dos testes:** backend `<n>` (`<falhas>`), ACS `<n>`, paciente `<n>`, admin `<n>`, scripts/qa `<n>`.

**Legenda de status:** `entregue` (código + prova do critério do PRD) · `parcial` (código sem o critério provado)
· `ausente` · `fora-do-mvp` (ausente e listado em v1.5+ no §6.1) · `externo` (falta só ação de terceiro).
```

Em seguida, uma tabela por seção com o cabeçalho `| ID | Requisito | Status | Evidência | O que falta |` e as linhas abaixo, todas `**a-verificar**` com evidência e "o que falta" vazios:

- `## Paciente`: RF01, RF02, RF03, RF04, RF05, RF06, RF18
- `## ACS`: RF07, RF08, RF09, RF10, RF11, RF12, RF13, RF14, RF15
- `## Núcleo, auditoria e backoffice`: RF16, RF17, RF19, RNF06 + subseção sem ID `### Módulos do backoffice (§2.1)` com linhas `MOD-UBS`, `MOD-ACS`, `MOD-RELATORIOS`, `MOD-AUDITORIA`, `MOD-CONFIG`
- `## Invariantes e segurança`: INV-01 a INV-05 + subseções sem ID `### STRIDE (§4.2.1)` (`STRIDE-S`, `-T`, `-R`, `-I`, `-D`, `-E`) e `### Criptografia (§4.2.3)` (`CRIPTO-APP-LOCAL`, `CRIPTO-APP-CACHE`, `CRIPTO-APP-TRAEFIK`, `CRIPTO-TRAEFIK-BACKEND`, `CRIPTO-POSTGRES`, `CRIPTO-AUDITORIA`)
- `## Não funcionais`: RNF01 a RNF05 + `### SLOs (§4.1)` (`SLO-LOGIN`, `SLO-ALERTA`, `SLO-DASHBOARD`, `SLO-VISITA`, `SLO-SYNC`, `SLO-MAPA`, `SLO-TRIAGEM`) e `### Acessibilidade (§4.3)` (`A11Y-1.4.3`, `A11Y-1.4.11`, `A11Y-2.5.1`, `A11Y-2.5.6`, `A11Y-2.4.7`, `A11Y-3.3.2`, `A11Y-LCP`, `A11Y-FID`, `A11Y-CLS`)
- `## LGPD e dados`: LGPD-RF01, LGPD-RF02, LGPD-RF07, LGPD-RF08, LGPD-RF09, LGPD-RF11 + `### Modelo de dados e telemetria (§1.3, §3)` (`DADOS-TIMESCALE`, `DADOS-VERSION-OTIMISTA`, `DADOS-SYNC-TOKEN`, `DADOS-MIGRACAO-ROLLBACK`, `EVT-alert_triggered`, `EVT-alert_received_acs`, `EVT-sync_attempt`, `EVT-sync_result`, `EVT-visit_registered`)
- `## Roadmap, hipóteses e riscos`: M1.1–M1.5, M2.1–M2.6, M3.1–M3.5, `### MVP (§6.1)` (`MVP-LOGIN-60S`, `MVP-ALERTA-2S`, `MVP-TRIAGEM-3P`, `MVP-STATUS`, `MVP-LOGIN-ACS`, `MVP-TERRITORIO-30S`, `MVP-FILA-ORDEM`, `MVP-VISITA-OFFLINE`, `MVP-MQTT-100`, `MVP-MIGRACOES-LOGS`), H1–H4, R1–R8
- `## Backlog priorizado`: vazio (Task 9).

As linhas sem ID do PRD (prefixos `MOD-`, `STRIDE-`, `CRIPTO-`, `SLO-`, `A11Y-`, `DADOS-`, `EVT-`, `MVP-`) não casam a regex do conferidor e por isso não são exigidas por ele — a completude delas é responsabilidade da task dona.

- [ ] **Step 3: Conferir**

Run: `python3 scripts/qa/cobertura_prd.py; echo "exit=$?"`
Expected: `cobertura do PRD: 66 IDs, ok`, `exit=0`.
Run: `python3 scripts/qa/cobertura_prd.py --final; echo "exit=$?"`
Expected: 66 linhas `…: ainda a-verificar`, `exit=1` (prova de que o modo final morde).

- [ ] **Step 4: Commit**

```bash
git add docs/auditoria-prd/2026-10-15-lacunas-prd.md
git commit -m "docs(auditoria-prd): esqueleto do relatório de lacunas e linha de base dos testes"
```

---

> **Método comum às Tasks 3–8** (repetido aqui porque cada task pode ser lida isolada):
> 1. Para cada linha, leia o trecho do PRD que define o critério de aceite (a matriz §2.2, o §6.1 para itens do MVP, a tabela própria do item).
> 2. Oriente-se com `graphify query "<requisito>"` antes de `grep`; depois abra o arquivo e anote `caminho:linha`.
> 3. Ache o teste que exercita o **critério** (não só o código): `grep -rn "<símbolo>" backend/sinalacs_server/test apps/*/test apps/*/integration_test scripts/qa`.
> 4. Rode esse teste isolado (`dart test <arquivo>` / `flutter test <arquivo>`) e anote `PASS`/`FAIL`. Teste de emulador ou e2e que exige stack não precisa ser rodado de novo se o `PROGRESS.md` registrar a prova com data **e** o código envolvido não mudou desde então (`git log --since=<data> -- <arquivos>` vazio); anote isso na evidência.
> 5. Aplique a regra de status dos Global Constraints e escreva em "O que falta" uma frase acionável (o que construir ou provar, onde).
> 6. Ao final da seção: `python3 scripts/qa/cobertura_prd.py` (exit 0) e commit só do relatório.

### Task 3: Verificar o app Paciente (RF01–RF06, RF18)

**Files:**
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (seção `## Paciente`)

**Interfaces:**
- Consumes: esqueleto da Task 2.
- Produces: 7 linhas sem `a-verificar`.

- [ ] **Step 1: RF01 — passwordless (CPF + nascimento + OTP).** Hipóteses: `auth.requestOtp`/`verifyOtp` em `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart`; e2e em `scripts/qa/patient_full_e2e.sh`. Critério do PRD: dependência "SMS Gateway" — verifique se existe envio real de SMS ou só relé de desenvolvimento (`scripts/qa/otp_relay.py`): `grep -rni "sms" backend/sinalacs_server/lib | head`. Sem gateway real → `parcial` com "O que falta: integração com gateway de SMS". Critério do MVP "10 pacientes logam em < 60 s" sem medição → `MVP-LOGIN-60S` fica `parcial` (Task 8).
- [ ] **Step 2: RF02 — onboarding por QR.** Hipótese: entregue com câmera (memória de 2026-09-29). Confirme `mobile_scanner` em `apps/patient/pubspec.yaml`, `qr_flutter` em `apps/acs/pubspec.yaml`, endpoint `onboarding_endpoint.dart`, e o teste que consome o convite de uso único.
- [ ] **Step 3: RF03 — botão de urgência (MQTT, GPS).** Confirme publicação via backend (`alerts.createRedAlert`) e o uso de GPS: `grep -rn "geolocator\|Geolocator" apps/patient/lib`. Sem localização no alerta → `parcial`. Botão ≥ 60×60 dp é critério de §4.3 (registre em `A11Y-2.5.6`, Task 6).
- [ ] **Step 4: RF04 — triagem estruturada.** Confirme a árvore de decisão e o "3 perguntas" do §6.1 (`MVP-TRIAGEM-3P`): conte as perguntas no código do formulário e cite o teste.
- [ ] **Step 5: RF05 — painel de status "Enviado → Visualizado → Atendido".** Confirme `alerts.statusFor` e que os três estados aparecem na UI do paciente (`grep -rn "Visualizado\|Atendido" apps/patient/lib`).
- [ ] **Step 6: RF06 — lembretes locais.** Confirme `flutter_local_notifications` e `apps/patient/lib/core/reminders/`. Decisão §2.2.1: local, sem endpoint — ausência de endpoint **não** é lacuna.
- [ ] **Step 7: RF18 — modo escuro nativo.** Para **cada** app: `grep -n "darkTheme\|themeMode" apps/{patient,acs,admin}/lib -r`. Entregue só se os três apps seguem o tema do sistema e há teste (ou captura em `docs/telas-*.md`) do tema escuro; senão `parcial` listando o app que falta. Lembre que contraste em tema escuro precisa dos tokens `*OnSurface` (ver `apps/CLAUDE.md`).
- [ ] **Step 8: Conferir e commit**

```bash
python3 scripts/qa/cobertura_prd.py
git add docs/auditoria-prd/2026-10-15-lacunas-prd.md
git commit -m "docs(auditoria-prd): verifica requisitos do app paciente"
```

---

### Task 4: Verificar o app ACS (RF07–RF15)

**Files:**
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (seção `## ACS`)

**Interfaces:**
- Consumes: esqueleto da Task 2.
- Produces: 9 linhas sem `a-verificar`.

- [ ] **Step 1: RF07 — login institucional.** Hipótese: entregue (Argon2id, TOTP, refresh token preso ao Keystore). Evidência: `auth.loginInstitutional` + `scripts/qa/acs_keystore_bound_e2e.sh` (prova só em API 36). Registre em "O que falta" os abertos que o `CLAUDE.md` nomeia e que tocam o login: invalidação da chave por digital nova em API 30+, prova em API 24–29, troca de senha pelo próprio ACS. Esses não derrubam o critério do PRD ("ACS loga com matrícula e senha") — status `entregue` com a nota.
- [ ] **Step 2: RF08 — territorialização.** Confirme o cache da microárea (72 h por dono) e o critério do MVP "< 30 s" (`MVP-TERRITORIO-30S`): procure medição (`grep -rn "30" scripts/qa/measure_latency.dart`); sem medição → `MVP-TERRITORIO-30S` `parcial`.
- [ ] **Step 3: RF09 — fila priorizada.** Confirme ordenação Vermelho → Amarelo → Verde e o teste que a fixa (`grep -rn "sort\|compare" apps/acs/lib/core/services | grep -i risk`). Paginação de 20 itens é SLO (Task 6).
- [ ] **Step 4: RF10 — mapa.** `google_maps_flutter` tem 7 ocorrências no repo. Confirme que é tela usada (não só dependência), a geocélula arredondada da decisão §2.2.1 (§1) e a clusterização acima de 50 pacientes (`SLO-MAPA`). Requer chave de API do Google para rodar em aparelho — se só roda com chave ausente, anote.
- [ ] **Step 5: RF11 — visita offline-first.** Confirme `apps/acs/lib/core/services/offline_visit_queue.dart` (schema v7) e o teste de fila. Registre como "O que falta" o upload em segundo plano pelo SO (WorkManager fora de `spec/stack.md`) e o desbloqueio de fila com token de 7 dias expirado.
- [ ] **Step 6: RF12 — geofencing (check-in passivo).** `geofenc` tem 16 ocorrências. Confirme o geofence atrelado à visita ativa (§2.2.1 §4) e `scripts/qa/acs_gps_e2e.sh`. PRD marca "submissão à loja pendente" → se o código está pronto, status `externo`.
- [ ] **Step 7: RF13 — escalonar para SAMU/UBS.** Confirme `url_launcher`, botão do SAMU (192) e botão da UBS; o PRD fora do MVP fala em "integração SAMU (escalonamento automático)" — se só há discagem manual, `entregue` para RF13 e anote a integração automática como `fora-do-mvp` no backlog.
- [ ] **Step 8: RF14 — avisos push.** Hipótese: `parcial` (Android/FCM provado em emulador 2026-09-30; faltam iOS/APNs, aparelho físico e Gorush hospedado). Confirme `notices_endpoint.dart`, `scripts/qa/push_e2e.sh`, `ci_push_e2e.sh`.
- [ ] **Step 9: RF15 — sync bidirecional.** Confirme `visits.sync`/`pull` por cursor e a FSM (`backend/sinalacs_server/lib/src/**/sync_fsm.dart`). A coluna "Dependência" do PRD diz "ainda não conectado ao cliente" — verifique se isso está velho (o consumo no ACS e no paciente foi feito em 2026-09-18) e, se estiver, anote em "O que falta" a correção da linha do PRD.
- [ ] **Step 10: Conferir e commit**

```bash
python3 scripts/qa/cobertura_prd.py
git add docs/auditoria-prd/2026-10-15-lacunas-prd.md
git commit -m "docs(auditoria-prd): verifica requisitos do app ACS"
```

---

### Task 5: Núcleo, auditoria e backoffice (RF16, RF17, RF19, RNF06, módulos §2.1)

**Files:**
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (seção `## Núcleo, auditoria e backoffice`)

**Interfaces:**
- Consumes: esqueleto da Task 2.
- Produces: 4 linhas com ID + 5 linhas `MOD-*`.

- [ ] **Step 1: RF16 — motor de triagem determinístico.** Critério M1.3: "cobertura 100% MCDC; classifica 50 cenários". Ache o motor (`graphify query "triage engine"`) e conte os cenários do teste: `grep -c "test(" <arquivo de teste do motor>`. Rode `./scripts/qa/measure_coverage.sh` (ou o comando de cobertura do `backend/CLAUDE.md`) para o arquivo do motor. MCDC não é medido por ferramenta Dart padrão: se só há cobertura de linha, RF16 é `entregue` (determinismo provado) e M1.3 é `parcial` com "O que falta: medição MCDC".
- [ ] **Step 2: RF17 — auditoria.** Hipótese: `parcial` — cadeia HMAC detecta adulteração mas não impede (sem trigger/`REVOKE` append-only), exportação CSV vai pela área de transferência. Confirme `audit_chain_check` e `scripts/qa/admin_auditoria_e2e.sh`.
- [ ] **Step 3: RF19 — escalonamento de alerta vermelho.** Hipótese: `entregue` (#44, e2e 2026-10-12). Confirme `admin.escalateAlert`, `RED_ALERT_ESCALATION_SECONDS` com faixa 30–3600 s e teste de idempotência.
- [ ] **Step 4: RNF06 — RBAC.** Confirme `Authorization.require` e os testes de negação por papel/UBS nos endpoints `admin`. O texto do PRD ("RBAC dos endpoints de dados do staff segue aberto, issue #40") provavelmente está velho; se estiver, anote "corrigir RNF06 no PRD". Regra de matriz §4.2.2 a verificar linha a linha: "Dados de outras microáreas — Coordenador R (justificado)" — existe registro de justificativa? Se não, `parcial`.
- [ ] **Step 5: Módulos do backoffice (§2.1).** `MOD-UBS` (cadastro de UBS, incluindo telefone — aberto conhecido), `MOD-ACS` (#43), `MOD-RELATORIOS` (Indicadores), `MOD-AUDITORIA` (#45), `MOD-CONFIG` ("Configurações de sistema R/W" do admin, §4.2.2). Para cada um: `ls apps/admin/lib -R | grep -i <tema>` e o endpoint em `admin_endpoint.dart`. Anote também o aberto do `CLAUDE.md`: criar coordenador e definir `ubsId` pela UI.
- [ ] **Step 6: Conferir e commit**

```bash
python3 scripts/qa/cobertura_prd.py
git add docs/auditoria-prd/2026-10-15-lacunas-prd.md
git commit -m "docs(auditoria-prd): verifica núcleo, auditoria e backoffice"
```

---

### Task 6: Invariantes, segurança e não funcionais (INV-01–05, RNF01–RNF05, STRIDE, criptografia, SLOs, acessibilidade)

**Files:**
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (seções `## Invariantes e segurança` e `## Não funcionais`)

**Interfaces:**
- Consumes: esqueleto da Task 2; linha de base dos testes da Task 2.
- Produces: 10 linhas com ID + linhas `STRIDE-*`, `CRIPTO-*`, `SLO-*`, `A11Y-*`.

- [ ] **Step 1: INV-01 e INV-05 (segregação).** Para cada endpoint em `backend/sinalacs_server/lib/src/endpoints/*.dart` que devolve dado de paciente, ache o teste que tenta ler fora da microárea (INV-01) e de outro paciente (INV-05) e espera recusa. Liste endpoint por endpoint na evidência; um endpoint sem teste de recusa → `parcial` nomeando o endpoint.
- [ ] **Step 2: INV-02, INV-03, INV-04.** INV-02: confirme que nenhum endpoint/tela aceita risco vindo do cliente (`grep -rn "riskLevel" backend/sinalacs_server/lib/src/endpoints`). INV-03: ACK + retry + outbox; cite `scripts/qa/mqtt_resiliencia_e2e.sh`. INV-04: colunas `*Encrypted` no Postgres e SQLCipher nos apps; procure coluna clínica ainda em texto plano no `definition.sql` da última migração (`ls -d backend/sinalacs_server/migrations/*/ | tail -1`) cruzando com `spec/lgpd_data_audit.md`.
- [ ] **Step 3: STRIDE.** Uma linha por letra. Pontos de atenção que o PRD pede e podem faltar: S — certificado de cliente por aparelho em produção (só stack local hoje); T — "assinatura digital dos dados de triagem no dispositivo"; R — "logs append-only" (só detecção); D — rate limiting no Mosquitto (`grep -n "max_\|rate" infra/docker/mosquitto/*`).
- [ ] **Step 4: Criptografia (§4.2.3).** Compare a tabela do PRD com o real: chave do SQLCipher "derivada do PIN/biometria (PBKDF2)" vs o que `apps/*/lib/core/database/encrypted_database.dart` faz; "chave rotativa"; TLS 1.3 em Traefik (`scripts/qa/tls_invariants.sh`); mTLS Traefik↔backend; "pgcrypto + Vault" vs AES-256-GCM na aplicação (decisão §2.2.1 §6 — divergência decidida não é lacuna, anote como tal). Rode `./scripts/qa/tls_invariants.sh` e `./scripts/qa/mtls_invariants.sh` com a stack de pé se ainda não houver prova datada.
- [ ] **Step 5: RNF01–RNF04.** RNF01 (latência MQTT < 500 ms p95) e `SLO-ALERTA`: rode ou localize resultado de `dart run scripts/qa/measure_latency.dart` — sem p95 medido → `parcial`. RNF02 (> 99,5 % de sync): procure medição; sem métrica coletada → `parcial` ("falta telemetria `sync_result`"). RNF03/RNF04: derivam dos passos 2 e 4.
- [ ] **Step 6: SLOs (§4.1).** Para cada `SLO-*`, registre "medido (valor, comando)" ou "não medido". Não medido é `parcial`, nunca `entregue`.
- [ ] **Step 7: RNF05 e acessibilidade (§4.3).** Fonte: `spec/ux_accessibility_assessment.md` e `apps/*/test/contrast_tokens_test.dart`. Rode `flutter test test/contrast_tokens_test.dart` em cada app. Atenção: o PRD pede WCAG 2.1 AA; a avaliação usa 2.2 AA (superconjunto — ok). Admin (`apps/admin`) tem teste de contraste? Se não, `parcial`. `A11Y-LCP/FID/CLS` sem medição → `parcial`. `A11Y-2.4.7` (foco visível com `FocusNode`) é mais relevante no admin web/desktop.
- [ ] **Step 8: Conferir e commit**

```bash
python3 scripts/qa/cobertura_prd.py
git add docs/auditoria-prd/2026-10-15-lacunas-prd.md
git commit -m "docs(auditoria-prd): verifica invariantes, segurança e não funcionais"
```

---

### Task 7: LGPD, modelo de dados e telemetria

**Files:**
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (seção `## LGPD e dados`)

**Interfaces:**
- Consumes: esqueleto da Task 2.
- Produces: 6 linhas com ID + linhas `DADOS-*`, `EVT-*`.

- [ ] **Step 1: LGPD-RF01, 02, 09, 11.** Coleta mínima: existe o "checklist de dados por funcionalidade"? (`spec/lgpd_data_audit.md` conta como tal se cobre todas as tabelas da última migração — conte as tabelas no `definition.sql` e compare.) Consentimento granular: `patients.updateConsent`, `consent_logs`. 09 e 11 derivam de INV-04 e RNF06.
- [ ] **Step 2: LGPD-RF07 — retenção e "job de expurgo".** `grep -rni "expurgo\|purge\|retention\|retencao" backend/sinalacs_server/lib`. O `CLAUDE.md` lista como aberto o expurgo de dono que nunca volta (fila do ACS). Sem job periódico de expurgo no servidor → `ausente` ou `parcial`.
- [ ] **Step 3: LGPD-RF08 — "Meus Dados" + exportação JSON.** Confirme `patients.myData` e o painel; procure a **exportação em JSON** pelo titular (`grep -rni "json" apps/patient/lib | grep -i "export\|baixar\|compartilh"`). Sem exportação → `parcial`. Atendimento de pedidos (#42) entregue; validação das regras de anonimização com o DPO é `externo` no backlog.
- [ ] **Step 4: Modelo de dados (§3) e telemetria (§1.3).** `DADOS-TIMESCALE` (0 ocorrências de `timescale` no repo em 2026-10-15 → provável `ausente`); `DADOS-VERSION-OTIMISTA` (campo `version` e 409 em `visits`); `DADOS-SYNC-TOKEN` ("servidor rejeita tokens menores que o último processado"); `DADOS-MIGRACAO-ROLLBACK` (o PRD pede `rollback/*.sql`; o Serverpod gera migrações — veja se há rollback). Cada `EVT-*`: `grep -rn "<nome_do_evento>" backend apps` — evento não emitido → `ausente`; sem eles, as métricas North Star (§1.3) não são mensuráveis, anote isso uma vez em `EVT-sync_result`.
- [ ] **Step 5: Conferir e commit**

```bash
python3 scripts/qa/cobertura_prd.py
git add docs/auditoria-prd/2026-10-15-lacunas-prd.md
git commit -m "docs(auditoria-prd): verifica LGPD, modelo de dados e telemetria"
```

---

### Task 8: Roadmap, MVP, hipóteses e riscos (M1.1–M3.5, MVP-*, H1–H4, R1–R8)

**Files:**
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (seção `## Roadmap, hipóteses e riscos`)

**Interfaces:**
- Consumes: linhas já preenchidas pelas Tasks 3–7 (cite-as por ID em vez de repetir a evidência).
- Produces: 34 linhas com ID + 10 linhas `MVP-*`.

- [ ] **Step 1: Fase 1 e 2 (M1.x, M2.x).** O `PROGRESS.md` marca todos como implementados; confira o critério de aceite de cada um contra o PRD, não o rótulo. Pontos que provavelmente não batem: M1.3 (MCDC, ver Task 5), M2.3 ("WSS" — o broker só expõe MQTT/TLS em 8883; WebSockets 9001 não é publicado: decisão consciente → anote), M2.4 ("100 registros sincronizam em < 5 s" — há medição?), M2.5 ("Toxiproxy" — 0 ocorrências; existe `network_chaos_simulator.dart` em processo, não proxy de rede → `parcial`), M2.6 ("5 ACS e 10 pacientes testam em campo" → `externo`).
- [ ] **Step 2: Fase 3 (M3.x).** M3.1 Pulumi/VPS (0 ocorrências de `pulumi`; `backend/DEPLOY.md` é só demo free-tier → `ausente`). M3.2 OpenTelemetry/Prometheus/Grafana (0 ocorrências → `ausente`). M3.3 carga 100 ACS / 500 alertas/h (procure script de carga → provável `ausente`). M3.4 LGPD (documentação existe; revisão do DPO → `externo`). M3.5 piloto em UBS → `externo`.
- [ ] **Step 3: MVP (§6.1).** Cada `MVP-*` aponta para a linha RF correspondente e diz se o **número** do critério (60 s, 2 s, 30 s, 100 dispositivos, < 500 ms) foi medido. `MVP-MIGRACOES-LOGS`: migrações versionadas sim; "logs estruturados" — procure logger JSON no backend.
- [ ] **Step 4: Hipóteses H1–H4.** Todas dependem de piloto/campo; status `externo`, mas registre em "O que falta" se a **instrumentação** para medi-las existe (H1 precisa de `alert_received_acs` e início de visita; H4 de `sync_result`) — sem instrumentação, a hipótese é inmedível mesmo com piloto, e isso vira item de código no backlog.
- [ ] **Step 5: Riscos R1–R8.** Status do **plano de contingência** em código: R1 (UI de resolução de conflito lado a lado — procure no ACS), R2 (fallback REST quando MQTT cai — `POST /v1/alerts/red`?), R3 (remote wipe via API — o `CLAUDE.md` diz que não há wipe forçado pelo supervisor → `ausente`), R5 (índices/particionamento por microárea), R6 (fallback do SMS), R8 (failover do Traefik → infra, `ausente`). R4 e R7 são de processo → `externo`.
- [ ] **Step 6: Conferir e commit**

```bash
python3 scripts/qa/cobertura_prd.py
git add docs/auditoria-prd/2026-10-15-lacunas-prd.md
git commit -m "docs(auditoria-prd): verifica roadmap, MVP, hipóteses e riscos"
```

---

### Task 9: Amostragem, backlog priorizado e fechamento

**Files:**
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (seção `## Backlog priorizado` e linhas rebaixadas)
- Modify: `PROGRESS.md` (seção nova ao final)

**Interfaces:**
- Consumes: relatório completo das Tasks 3–8; `python3 scripts/qa/cobertura_prd.py --final`.

- [ ] **Step 1: Amostragem das linhas `entregue`**

```bash
grep -E '^\| (RF|RNF|INV|LGPD|M[0-9])[^|]* \|[^|]*\| \*\*entregue\*\*' docs/auditoria-prd/2026-10-15-lacunas-prd.md | shuf -n 3
```

Para cada uma das três, refaça a evidência do zero (abra o `caminho:linha`, rode o teste citado). Se não se reproduzir, rebaixe para `parcial` e registre no topo do relatório "amostragem: X de 3 reproduzidas".

- [ ] **Step 2: Escrever o backlog priorizado**

Na seção `## Backlog priorizado`, uma tabela `| # | Lacuna | IDs | Tipo | Prioridade | Justificativa |`, uma linha por lacuna (agrupe IDs que se resolvem com o mesmo trabalho, ex.: `EVT-*` + RNF02 + H4). Tipo: `código`, `prova` (código existe, falta medição/e2e), `infra`, `externo`, `correção do PRD`. Prioridade, nesta ordem de critério:
  1. **P0** — toca invariante (INV-01..05) ou item do núcleo do MVP (§6.1) sem critério atingido.
  2. **P1** — requisito com risco **Crítico** na matriz §2.2 (RF03, RF11, RF15, RF16, RF19, RNF02–RNF04) ou risco de impacto 5 (R1, R2, R3, R7, R8).
  3. **P2** — demais RF/RNF e itens da Fase 3.
  4. **P3** — `fora-do-mvp`, correções de texto do PRD.
  Itens `externo` entram com o dono (DPO, jurídico, UBS piloto, loja) e sem prioridade de engenharia.

- [ ] **Step 3: Conferência final**

Run: `python3 scripts/qa/cobertura_prd.py --final; echo "exit=$?"`
Expected: `cobertura do PRD: 66 IDs, ok`, `exit=0`.
Run também: `grep -c 'a-verificar' docs/auditoria-prd/2026-10-15-lacunas-prd.md` → `0` (pega as linhas sem ID do PRD, que o conferidor não vê).
Run: `./scripts/qa/check_documentation_links.sh` → sem link quebrado.

- [ ] **Step 4: Apontar no `PROGRESS.md`**

Acrescente ao final:

```markdown
## Auditoria de lacunas do PRD (2026-10-15)

Relatório item a item de `spec/PRD_system.md` contra o código, com evidência medida no commit `<SHA>`:
[docs/auditoria-prd/2026-10-15-lacunas-prd.md](docs/auditoria-prd/2026-10-15-lacunas-prd.md).
Contagem: `<n>` entregue, `<n>` parcial, `<n>` ausente, `<n>` fora-do-mvp, `<n>` externo.
Backlog priorizado na seção final do relatório; conferência por `python3 scripts/qa/cobertura_prd.py --final`.
```

Gere a contagem com:

```bash
grep -oE '\*\*(entregue|parcial|ausente|fora-do-mvp|externo)\*\*' docs/auditoria-prd/2026-10-15-lacunas-prd.md | sort | uniq -c
```

- [ ] **Step 5: Commit**

```bash
git add docs/auditoria-prd/2026-10-15-lacunas-prd.md PROGRESS.md
git commit -m "docs(auditoria-prd): backlog priorizado e fechamento da auditoria do PRD"
```

- [ ] **Step 6: (Opcional, só com aprovação do dono) abrir issues**

Para cada item P0/P1 do backlog, **mostre a lista ao dono antes** e só então:

```bash
gh issue create --title "<lacuna>" --body "IDs do PRD: <IDs>. Evidência e o que falta: docs/auditoria-prd/2026-10-15-lacunas-prd.md (linha <ID>)."
```
