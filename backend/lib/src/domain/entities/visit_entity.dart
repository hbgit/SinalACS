import '../enums/risk_level.dart';
import '../enums/sync_status.dart';

class VisitEntity {
  const VisitEntity({
    required this.id,
    required this.patientId,
    required this.acsId,
    required this.scheduledAt,
    this.startedAt,
    this.completedAt,
    required this.status,
    required this.riskLevelBefore,
    this.riskLevelAfter,
    required this.notes,
    required this.syncStatus,
    required this.localId,
    required this.syncAt,
    required this.version,
  });

  final String id;
  final String patientId;
  final String acsId;
  final DateTime scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String status;
  final RiskLevel riskLevelBefore;
  final RiskLevel? riskLevelAfter;
  final Map<String, dynamic> notes;
  final SyncStatus syncStatus;
  final String localId;
  final DateTime? syncAt;
  final int version;
}
