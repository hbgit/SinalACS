import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart';
import 'package:sinalacs_patient/core/consent/consent_decisions.dart';

PatientConsentRecord _record(String purpose, String action, DateTime at) =>
    PatientConsentRecord(purpose: purpose, action: action, version: '2026.1', timestamp: at);

void main() {
  test('histórico vazio não tem decisão nenhuma — "nunca decidiu" não vira recusa', () {
    expect(currentConsentDecisions(const []), isEmpty);
  });

  test('vale o registro mais recente, qualquer que seja a ordem da lista', () {
    final decisions = currentConsentDecisions([
      _record('localReminders', 'denied', DateTime.utc(2026, 2, 1)),
      _record('localReminders', 'granted', DateTime.utc(2026, 1, 1)),
    ]);

    expect(decisions, {ConsentPurpose.localReminders: false});
  });

  test('empate de horário: vale o último da lista', () {
    final at = DateTime.utc(2026, 1, 1);
    final decisions = currentConsentDecisions([
      _record('segmentedPush', 'granted', at),
      _record('segmentedPush', 'denied', at),
    ]);

    expect(decisions[ConsentPurpose.segmentedPush], isFalse);
  });

  test('as três finalidades do onboarding saem independentes', () {
    final at = DateTime.utc(2026, 1, 1);
    final decisions = currentConsentDecisions([
      _record('healthDataProcessing', 'granted', at),
      _record('localReminders', 'granted', at),
      _record('segmentedPush', 'denied', at),
    ]);

    expect(decisions, {
      ConsentPurpose.healthDataProcessing: true,
      ConsentPurpose.localReminders: true,
      ConsentPurpose.segmentedPush: false,
    });
  });

  test('finalidade que o app não conhece é ignorada', () {
    final decisions = currentConsentDecisions([
      _record('finalidadeFutura', 'granted', DateTime.utc(2026, 1, 1)),
    ]);

    expect(decisions, isEmpty);
  });

  test('rótulo de registro cai no nome cru só para finalidade desconhecida', () {
    expect(consentRecordLabel('localReminders'), 'Lembretes neste aparelho');
    expect(consentRecordLabel('finalidadeFutura'), 'finalidadeFutura');
  });
}
