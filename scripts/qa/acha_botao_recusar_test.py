import unittest

from acha_botao_recusar import achar

NO = '<node resource-id="com.android.permissioncontroller:id/%s" class="x" bounds="[10,20][30,60]"/>'


class AchaBotaoTest(unittest.TestCase):
    def test_acha_o_centro(self):
        self.assertEqual(achar(NO % "permission_deny_button"), (20, 40))

    def test_prefere_o_nao_perguntar_de_novo(self):
        grande = NO.replace("[10,20][30,60]", "[100,200][300,600]") % "permission_deny_and_dont_ask_again_button"
        self.assertEqual(achar(NO % "permission_deny_button" + grande), (200, 400))

    def test_sem_dialogo(self):
        self.assertIsNone(achar('<node resource-id="x" bounds="[0,0][1,1]"/>'))

    def test_dump_enorme(self):
        self.assertEqual(achar("<n/>" * 100000 + NO % "permission_deny_button"), (20, 40))


if __name__ == "__main__":
    unittest.main()
