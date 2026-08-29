class MicroAreaEntity {
  const MicroAreaEntity({
    required this.id,
    required this.name,
    required this.ubsId,
    required this.geoJsonBoundary,
  });

  final String id;
  final String name;
  final String ubsId;
  final Map<String, dynamic> geoJsonBoundary;
}
