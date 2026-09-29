import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show consentPolicyVersion;
import 'package:sinalacs_server/src/application/patients/terms_change_schedule.dart';
import 'package:test/test.dart';

final _pub = DateTime.utc(2026, 10, 1);

TermsChangeSchedule agenda({DateTime? vigencia, String versao = '2026.2'}) => TermsChangeSchedule(
      version: versao,
      publishedAt: _pub,
      effectiveFrom: vigencia ?? _pub.add(const Duration(days: 15)),
      summary: 'Resumo.',
    );

void main() {
  test('vigência com menos de 15 dias da publicação não existe', () {
    expect(
      () => agenda(vigencia: _pub.add(const Duration(days: 14, hours: 23))),
      throwsA(isA<AssertionError>()),
    );
  });

  test('exatamente 15 dias é aceito', () {
    expect(agenda().effectiveFrom, _pub.add(const Duration(days: 15)));
  });

  test('a versão anunciada não pode ser a vigente', () {
    expect(() => agenda(versao: consentPolicyVersion), throwsA(isA<AssertionError>()));
  });

  test('ativa na publicação, inativa na vigência', () {
    final a = agenda();
    expect(a.isActiveAt(_pub.subtract(const Duration(seconds: 1))), isFalse);
    expect(a.isActiveAt(_pub), isTrue);
    expect(a.isActiveAt(a.effectiveFrom.subtract(const Duration(seconds: 1))), isTrue);
    expect(a.isActiveAt(a.effectiveFrom), isFalse);
  });

  test('a agenda real do repositório respeita a regra (vazia hoje)', () {
    final real = upcomingTermsChange;
    if (real != null) {
      expect(real.effectiveFrom.difference(real.publishedAt) >= termsChangeNoticePeriod, isTrue);
    }
  });
}
