import 'package:flutter_test/flutter_test.dart';

import '../tool/schedule_notice.dart';

void main() {
  const manifesto = '{"microAreaId":"00000000-0000-4000-8000-000000000003",'
      '"staff":{"id":"x","matricula":"ADM-E2E-1","password":"segredo-sintetico",'
      '"activationCode":"COD-SINTETICO"}}';

  test('lê matrícula, senha, código de ativação e microárea do manifesto', () {
    final s = lerManifesto(manifesto);
    expect(s.matricula, 'ADM-E2E-1');
    expect(s.senha, 'segredo-sintetico');
    expect(s.codigoAtivacao, 'COD-SINTETICO');
    expect(s.microAreaId, '00000000-0000-4000-8000-000000000003');
  });

  test('manifesto sem staff ou sem microárea: FormatException que não vaza valores', () {
    for (final ruim in [
      '{"microAreaId":"m"}',
      '{"staff":{"matricula":"a","password":"segredo-sintetico","activationCode":"c"}}',
      '{"microAreaId":"m","staff":{"matricula":"a","password":"segredo-sintetico"}}',
    ]) {
      expect(
        () => lerManifesto(ruim),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', isNot(contains('segredo')))),
      );
    }
  });

  test('passoTotp muda a cada 30 s (o login espera o passo seguinte ao da ativação)', () {
    final t0 = DateTime.utc(2026, 10, 14, 12, 0, 0);
    expect(passoTotp(t0.add(const Duration(seconds: 29))), passoTotp(t0));
    expect(passoTotp(t0.add(const Duration(seconds: 30))), passoTotp(t0) + 1);
  });
}
