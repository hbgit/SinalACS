import 'package:sinalacs_server/src/application/telemetry/telemetry_pseudonymizer.dart';
import 'package:test/test.dart';

void main() {
  const uuid = '3f2b8c1e-5a4d-4e6f-9b0a-1c2d3e4f5a6b';
  final pseudonymizer = TelemetryPseudonymizer('chave-de-teste');

  test('mesmo uuid em maiúsculas e minúsculas dá o mesmo pseudônimo', () {
    expect(
      pseudonymizer.patient(uuid.toUpperCase()),
      pseudonymizer.patient(uuid),
    );
    expect(pseudonymizer.patient(uuid), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('domínios patient e device não colidem para o mesmo valor', () {
    expect(pseudonymizer.patient(uuid), isNot(pseudonymizer.device(uuid)));
  });

  test('chaves diferentes dão pseudônimos diferentes', () {
    expect(
      TelemetryPseudonymizer('outra-chave').patient(uuid),
      isNot(pseudonymizer.patient(uuid)),
    );
  });

  test('saída não contém o uuid', () {
    expect(pseudonymizer.patient(uuid), isNot(contains(uuid)));
    expect(pseudonymizer.device('aparelho-1'), isNot(contains('aparelho-1')));
  });
}
