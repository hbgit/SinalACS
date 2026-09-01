import 'dart:convert';

class AlertDelivery {
  const AlertDelivery({
    required this.alertId,
    required this.patientId,
    required this.microAreaId,
    required this.riskLevel,
    required this.locationHash,
    required this.triggeredAt,
  });

  static const topicPrefix = 'sinalacs/v1/microareas';

  final String alertId;
  final String patientId;
  final String microAreaId;
  final String riskLevel;
  final String locationHash;
  final DateTime triggeredAt;

  String get topic => '$topicPrefix/$microAreaId/alerts';

  String toJson() => jsonEncode({
        'version': 1,
        'alert_id': alertId,
        'patient_id': patientId,
        'micro_area_id': microAreaId,
        'risk_level': riskLevel,
        'location_hash': locationHash,
        'triggered_at': triggeredAt.toUtc().toIso8601String(),
      });
}

class AlertDeliveryAck {
  const AlertDeliveryAck({
    required this.alertId,
    required this.acsId,
    required this.microAreaId,
    required this.acknowledgedAt,
  });

  final String alertId;
  final String acsId;
  final String microAreaId;
  final DateTime acknowledgedAt;

  String get topic => 'sinalacs/v1/alerts/$alertId/acks';

  String toJson() => jsonEncode({
        'version': 1,
        'alert_id': alertId,
        'acs_id': acsId,
        'micro_area_id': microAreaId,
        'acknowledged_at': acknowledgedAt.toUtc().toIso8601String(),
      });

  static AlertDeliveryAck? tryParse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['version'] != 1) return null;

      final acknowledgedAtRaw = json['acknowledged_at'] as String?;
      if (acknowledgedAtRaw == null) return null;

      return AlertDeliveryAck(
        alertId: json['alert_id'] as String,
        acsId: json['acs_id'] as String,
        microAreaId: json['micro_area_id'] as String,
        acknowledgedAt: DateTime.parse(acknowledgedAtRaw),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}