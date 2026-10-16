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

    def test_celula_de_id_fora_do_formato_e_erro(self):
        for linha in (
            "| RF01  | Login | **ausente** | | x |\n",
            "|RF01| Login | **ausente** | | x |\n",
            "| **RF01** | Login | **ausente** | | x |\n",
        ):
            with self.subTest(linha=linha), self.assertRaises(Malformado):
                linhas_do_relatorio(RELATORIO_OK + linha)

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
