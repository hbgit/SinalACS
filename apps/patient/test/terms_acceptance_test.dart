import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show PatientConsentRecord;
import 'package:sinalacs_patient/core/legal/legal_documents.dart';
import 'package:sinalacs_patient/core/legal/terms_acceptance.dart';

PatientConsentRecord linha(String action, String version, int minuto, {String purpose = 'termsOfUse'}) =>
    PatientConsentRecord(
      purpose: purpose,
      action: action,
      version: version,
      timestamp: DateTime.utc(2026, 9, 29, 12, minuto),
    );

void main() {
  test('sem nenhuma linha de termsOfUse, precisa aceitar', () {
    expect(needsTermsAcceptance(const []), isTrue);
    expect(
      needsTermsAcceptance([linha('granted', '2026.1', 0, purpose: 'localReminders')]),
      isTrue,
    );
  });

  test('aceite da versão vigente dispensa o aviso', () {
    expect(needsTermsAcceptance([linha('granted', legalDocumentsVersion, 0)]), isFalse);
  });

  test('aceite de versão anterior pede de novo', () {
    expect(needsTermsAcceptance([linha('granted', '2025.9', 0)]), isTrue);
  });

  test('vale a linha mais recente, seja qual for a ordem da lista', () {
    final velha = linha('granted', '2025.9', 0);
    final nova = linha('granted', legalDocumentsVersion, 5);
    expect(needsTermsAcceptance([nova, velha]), isFalse);
    expect(needsTermsAcceptance([velha, nova]), isFalse);
  });

  test('linha mais recente que não é "granted" pede de novo', () {
    expect(
      needsTermsAcceptance([
        linha('granted', legalDocumentsVersion, 0),
        linha('denied', legalDocumentsVersion, 5),
      ]),
      isTrue,
    );
  });
}
