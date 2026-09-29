import 'package:sinalacs_client/sinalacs_client.dart';

/// Decisão vigente de cada finalidade, a partir do histórico de
/// `consent_logs` que `patients.myData` devolve.
///
/// O histórico é append-only (LGPD-RF04): revogar grava uma linha nova, nunca
/// apaga a anterior, então vale o registro mais recente de cada finalidade.
/// Empate de horário resolve pela ordem da lista, que o servidor entrega da
/// mais antiga para a mais nova. Finalidade que o app não conhece é ignorada, e
/// finalidade sem registro fica fora do mapa — quem lê distingue "nunca
/// decidiu" de "recusou", mesmo cuidado de `ConsentPreferences`.
Map<ConsentPurpose, bool> currentConsentDecisions(List<PatientConsentRecord> history) {
  final known = ConsentPurpose.values.asNameMap();
  final latest = <ConsentPurpose, PatientConsentRecord>{};
  for (final record in history) {
    final purpose = known[record.purpose];
    if (purpose == null) continue;
    final previous = latest[purpose];
    if (previous == null || !record.timestamp.isBefore(previous.timestamp)) {
      latest[purpose] = record;
    }
  }
  return {for (final entry in latest.entries) entry.key: entry.value.action == 'granted'};
}

/// Nome de cada finalidade para a pessoa ler.
String consentPurposeLabel(ConsentPurpose purpose) => switch (purpose) {
      ConsentPurpose.healthDataProcessing => 'Tratamento de dados de saúde',
      ConsentPurpose.localReminders => 'Lembretes neste aparelho',
      ConsentPurpose.segmentedPush => 'Avisos da equipe de saúde',
    };

/// Rótulo de um registro do histórico, que carrega a finalidade como texto.
/// Uma finalidade desconhecida aparece crua, em vez de sumir do histórico.
String consentRecordLabel(String purpose) {
  final known = ConsentPurpose.values.asNameMap()[purpose];
  return known == null ? purpose : consentPurposeLabel(known);
}
