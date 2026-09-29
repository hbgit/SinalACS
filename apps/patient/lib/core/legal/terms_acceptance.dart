import 'package:sinalacs_client/sinalacs_client.dart' show PatientConsentRecord;
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

/// `true` quando o paciente ainda precisa aceitar o Termo de Uso e a Política
/// de Privacidade vigentes (LGPD-RF18).
///
/// Vale a linha **mais recente** de `termsOfUse`, pela data, e não a última da
/// lista: o histórico é append-only, mas a ordem em que o servidor o devolve
/// não é contrato. Só conta um `granted` na versão que o app exibe hoje
/// ([legalDocumentsVersion]) — é isso que faz o aviso voltar quando a versão
/// mudar.
bool needsTermsAcceptance(List<PatientConsentRecord> consents) {
  PatientConsentRecord? latest;
  for (final record in consents) {
    if (record.purpose != 'termsOfUse') continue;
    if (latest == null || record.timestamp.isAfter(latest.timestamp)) latest = record;
  }
  return latest == null ||
      latest.action != 'granted' ||
      latest.version != legalDocumentsVersion;
}
