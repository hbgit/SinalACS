class AcsEntity {
  const AcsEntity({
    required this.userId,
    required this.enrollmentId,
    required this.ubsId,
    required this.active,
    required this.lastSyncAt,
  });

  final String userId;
  final String enrollmentId;
  final String ubsId;
  final bool active;
  final DateTime? lastSyncAt;
}
