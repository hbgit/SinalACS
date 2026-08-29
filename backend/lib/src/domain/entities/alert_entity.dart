import '../enums/alert_status.dart';
import '../enums/risk_level.dart';

class AlertEntity {
  const AlertEntity({
    required this.id,
    required this.patientId,
    this.acsId,
    required this.triggeredAt,
    this.receivedAt,
    this.respondedAt,
    required this.riskLevel,
    required this.locationHash,
    required this.status,
    required this.mqttTopic,
    required this.deviceId,
    required this.retryCount,
  });

  final String id;
  final String patientId;
  final String? acsId;
  final DateTime triggeredAt;
  final DateTime? receivedAt;
  final DateTime? respondedAt;
  final RiskLevel riskLevel;
  final String locationHash;
  final AlertStatus status;
  final String mqttTopic;
  final String deviceId;
  final int retryCount;
}
