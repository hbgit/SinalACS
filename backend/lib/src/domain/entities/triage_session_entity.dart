import '../enums/risk_level.dart';

class TriageSessionEntity {
  const TriageSessionEntity({
    required this.id,
    required this.patientId,
    required this.answers,
    required this.resultRisk,
    required this.resultDisplay,
    required this.createdAt,
    required this.deviceId,
  });

  final String id;
  final String patientId;
  final List<Map<String, dynamic>> answers;
  final RiskLevel resultRisk;
  final String resultDisplay;
  final DateTime createdAt;
  final String deviceId;
}
