/// Um evento de telemetria (PRD §1.3) guardado no aparelho até subir.
///
/// Sem PII: [payload] carrega só contagens, durações e ids opacos. [owner] é o
/// id do ACS que o gerou — a fila é separada por dono, como a das visitas.
class TelemetryEventRecord {
  const TelemetryEventRecord({
    required this.eventId,
    required this.owner,
    required this.name,
    required this.occurredAt,
    required this.payload,
  });

  final String eventId;
  final String owner;
  final String name;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
}
