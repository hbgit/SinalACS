import unittest
from otp_relay import parse_latest_code, host_permitido, count_codes

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

class ContagemTest(unittest.TestCase):
    L = "[SMS-GATEWAY=log] código de acesso: %s (gateway de desenvolvimento — nenhum SMS foi enviado)\n"

    def test_sem_linhas(self):
        self.assertEqual(count_codes("nada\n"), 0)

    def test_conta_uma_por_pedido_e_ignora_ruido(self):
        self.assertEqual(count_codes(self.L % "111111" + "ruído 222222\n" + self.L % "333333"), 2)

class HostTest(unittest.TestCase):
    def test_aceita_so_o_proprio_relé_em_loopback(self):
        for h in ("localhost:8765", "127.0.0.1:8765", "LOCALHOST:8765"):
            self.assertTrue(host_permitido(h, 8765), h)

    def test_recusa_outro_host_contra_dns_rebinding(self):
        for h in (None, "", "evil.example:8765", "localhost:9999", "127.0.0.1", "localhost.evil.example:8765"):
            self.assertFalse(host_permitido(h, 8765), h)

class AcsTest(unittest.TestCase):
    def test_le_matricula_e_senha_do_manifesto(self):
        import json, tempfile
        from otp_relay import acs_do_manifesto
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"acs": {"matricula": "E2E-1234", "password": "s3nha"}}, f)
        self.assertEqual(acs_do_manifesto(f.name), {"matricula": "E2E-1234", "senha": "s3nha"})

    def test_sem_arquivo_nao_serve_nada(self):
        from otp_relay import acs_do_manifesto
        self.assertIsNone(acs_do_manifesto(None))
        self.assertIsNone(acs_do_manifesto("/nao/existe.json"))

if __name__ == "__main__":
    unittest.main()
