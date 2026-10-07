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

    def test_le_o_segundo_acs_pela_chave_acsB(self):
        import json, tempfile
        from otp_relay import acs_do_manifesto
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"acs": {"matricula": "E2E-1", "password": "a"},
                       "acsB": {"matricula": "E2E-2", "password": "b"}}, f)
        self.assertEqual(acs_do_manifesto(f.name, "acsB"), {"matricula": "E2E-2", "senha": "b"})
        self.assertEqual(acs_do_manifesto(f.name), {"matricula": "E2E-1", "senha": "a"})

    def test_staff_devolve_tambem_o_codigo_de_ativacao(self):
        import json, tempfile
        from otp_relay import acs_do_manifesto
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"staff": {"matricula": "E2E-ADM-1", "password": "u", "activationCode": "ABCD-EFGH"},
                       "acs": {"matricula": "E2E-1", "password": "a", "activationCode": "NAO-DEVE-SAIR-NO-ACS"}}, f)
        self.assertEqual(acs_do_manifesto(f.name, "staff"),
                         {"matricula": "E2E-ADM-1", "senha": "u", "activationCode": "ABCD-EFGH"})
        # só o staff tem código de ativação: a resposta do ACS não muda de formato
        self.assertEqual(acs_do_manifesto(f.name, "acs"), {"matricula": "E2E-1", "senha": "a"})

    def test_sem_arquivo_nao_serve_nada(self):
        from otp_relay import acs_do_manifesto
        self.assertIsNone(acs_do_manifesto(None))
        self.assertIsNone(acs_do_manifesto("/nao/existe.json"))

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
        json.dump({"acs": {"matricula": "E2E-1", "password": "s"},
                   "acsB": {"matricula": "E2E-2", "password": "t"},
                   "staff": {"matricula": "E2E-ADM-1", "password": "u"}}, arquivo)
        arquivo.close()
        self.caminho = arquivo.name
        os.environ["E2E_FIXTURES_FILE"] = self.caminho
        otp_relay.Handler.acs_entregue = False
        otp_relay.Handler.acs_b_entregue = False
        otp_relay.Handler.admin_entregue = False
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
        self.otp_relay.Handler.acs_b_entregue = False
        self.otp_relay.Handler.admin_entregue = False

    def _get(self, rota="/acs"):
        import urllib.error
        import urllib.request

        url = f"http://127.0.0.1:{self.servidor.server_address[1]}{rota}"
        try:
            with urllib.request.urlopen(url) as resposta:
                return resposta.status
        except urllib.error.HTTPError as erro:
            return erro.code

    def test_serve_uma_vez_e_depois_404(self):
        self.assertEqual(self._get(), 200)
        self.assertEqual(self._get(), 404)

    def test_segundo_acs_tambem_uma_vez_e_independente_do_primeiro(self):
        self.assertEqual(self._get("/acs-b"), 200)
        self.assertEqual(self._get("/acs-b"), 404)
        self.assertEqual(self._get(), 200)

    def test_admin_serve_uma_vez_e_independe_dos_acs(self):
        self.assertEqual(self._get("/admin"), 200)
        self.assertEqual(self._get("/admin"), 404)
        self.assertEqual(self._get("/acs"), 200)

    def test_admin_sem_bloco_staff_no_manifesto_e_404(self):
        import json
        with open(self.caminho, "w") as f:
            json.dump({"acs": {"matricula": "E2E-1", "password": "s"}}, f)
        self.assertEqual(self._get("/admin"), 404)


if __name__ == "__main__":
    unittest.main()
