import 'package:flutter_test/flutter_test.dart';

import 'support/e2e_config.dart';
import 'support/e2e_login_core.dart';
import 'support/fake_patient_backend.dart';

Map<String, Object?> _manifesto() => {
      'microAreaId': 'm',
      'acs': {'id': 'c', 'matricula': 'E2E-1', 'password': 'senha-secreta-xyz'},
      'patients': [
        {
          'role': 'main',
          'cpf': '52998224725',
          'birthDate': '1990-01-01',
          'id': 'a',
          'name': 'Nome Um',
          'chronic': false,
          'microAreaId': 'm',
          'inviteTokens': ['convite-um', 'convite-dois'],
        },
        {
          'role': 'outsider',
          'cpf': '11144477735',
          'birthDate': '1970-02-02',
          'id': 'b',
          'name': 'Nome Dois',
          'chronic': false,
          'microAreaId': 'n',
          'inviteTokens': ['convite-tres'],
        },
      ],
    };

void main() {
  test('sem manifesto, não há configuração e vale o fallback de desenvolvimento', () async {
    expect(E2eConfig.fromMap(const {}), isNull);

    final backend = FakePatientBackend();
    await loginPatientWith(backend, null);

    expect(backend.developmentLoginCount, 1);
    expect(backend.enrollmentCalls, isEmpty);
  });

  test('o manifesto escolhe o paciente pelo papel', () {
    final config = E2eConfig.fromMap(_manifesto())!;

    expect(config.patient('outsider').birthDate, DateTime(1970, 2, 2));
    expect(config.microAreaId, 'm');
    expect(() => config.patient('inexistente'), throwsStateError);
  });

  test('o manifesto do aparelho não traz a senha do ACS e mesmo assim é lido', () {
    final semAcs = _manifesto()..remove('acs');

    final config = E2eConfig.fromMap(semAcs)!;

    expect(config.patient('main').birthDate, DateTime(1990, 1, 1));
    expect(config.acsPassword, isEmpty);
  });

  test('toString nunca mostra CPF nem senha do ACS', () {
    final config = E2eConfig.fromMap(_manifesto())!;
    final texto = '$config ${config.patient('main')}';

    expect(texto.contains('52998224725'), isFalse);
    expect(texto.contains(config.acsPassword), isFalse);
  });

  test('com manifesto: consome um convite e conclui o onboarding com credencial sorteada',
      () async {
    final backend = FakePatientBackend();

    final session = await loginPatientWith(
      backend,
      E2eConfig.fromMap(_manifesto()),
      role: 'outsider',
    );

    expect(session.role, 'patient');
    expect(backend.developmentLoginCount, 0,
        reason: 'com manifesto nunca usa o login de desenvolvimento');
    final chamada = backend.enrollmentCalls.single;
    expect(chamada['token'], 'convite-tres');
    expect(chamada['healthDataConsent'], true);
    expect(chamada['termsAccepted'], true);
    // A credencial é sorteada a cada execução — nunca um par fixo.
    expect((chamada['deviceId'] as String).length, 36);
    expect((chamada['deviceSecret'] as String).length, 43);
  });

  test('cada chamada consome um convite diferente do mesmo paciente', () async {
    final config = E2eConfig.fromMap(_manifesto())!;
    final backend = FakePatientBackend();

    await loginPatientWith(backend, config);
    await loginPatientWith(backend, config);

    final tokens = [for (final c in backend.enrollmentCalls) c['token']];
    expect(tokens, ['convite-um', 'convite-dois']);
  });

  test('sem convites restantes no manifesto, falha alto em vez de reusar', () async {
    final config = E2eConfig.fromMap(_manifesto())!;
    final backend = FakePatientBackend();

    await loginPatientWith(backend, config, role: 'outsider');

    await expectLater(
      loginPatientWith(backend, config, role: 'outsider'),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('sem convites restantes'))),
    );
    expect(backend.enrollmentCalls, hasLength(1));
  });
}
