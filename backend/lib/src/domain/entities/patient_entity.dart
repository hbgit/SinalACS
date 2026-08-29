import '../enums/risk_level.dart';

class PatientEntity {
  const PatientEntity({
    required this.userId,
    required this.emergencyContact,
    required this.isChronic,
    required this.chronicConditions,
    required this.lastLocationHash,
    required this.lastTriageAt,
    this.lastRiskLevel,
  });

  final String userId;
  final String emergencyContact;
  final bool isChronic;
  final List<String> chronicConditions;
  final String lastLocationHash;
  final DateTime? lastTriageAt;
  final RiskLevel? lastRiskLevel;
}
