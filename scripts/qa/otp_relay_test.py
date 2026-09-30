import unittest
from otp_relay import parse_latest_code

class T(unittest.TestCase):
    def test_sem_linha(self):
        self.assertIsNone(parse_latest_code("nada aqui\n"))
    def test_pega_a_mais_recente(self):
        log = ("[SMS-GATEWAY=log] código de acesso: 111111 (gateway de desenvolvimento — nenhum SMS foi enviado)\n"
               "ruído\n"
               "[SMS-GATEWAY=log] código de acesso: 222222 (gateway de desenvolvimento — nenhum SMS foi enviado)\n")
        self.assertEqual(parse_latest_code(log), "222222")
    def test_ignora_seis_digitos_fora_da_linha_do_gateway(self):
        self.assertIsNone(parse_latest_code("pedido 123456 recebido\n"))

if __name__ == "__main__":
    unittest.main()
