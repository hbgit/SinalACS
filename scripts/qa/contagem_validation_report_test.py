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

    def test_status_sem_negrito_e_erro(self):
        with self.assertRaises(ValueError):
            contar("| RF05 | X | parcial | x |\n")

    def test_linha_de_rf_malformada_e_erro(self):
        with self.assertRaises(ValueError):
            contar("| RF05 | X |\n")

    def test_sem_linha_de_contagem_e_erro(self):
        with self.assertRaises(ValueError):
            conferir("| RF01 | A | **backend** | x |\n")


if __name__ == "__main__":
    unittest.main()
