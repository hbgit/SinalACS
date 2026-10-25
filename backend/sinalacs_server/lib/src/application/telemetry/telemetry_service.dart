import 'package:sinalacs_server/src/generated/protocol.dart';

/// Um evento de telemetria já validado, pronto para gravar (#83).
///
/// `eventId`, `actorId` e `alertId` são UUIDs em texto minúsculo; o store os
/// converte para `uuid` no SQL. O `schemaVersion` não entra aqui: o store
/// grava sempre 1.
class TelemetryRecord {
  const TelemetryRecord({
    required this.eventId,
    required this.eventName,
    required this.source,
    required this.occurredAt,
    required this.receivedAt,
    required this.appVersion,
    required this.payload,
    this.clockSkewMs,
    this.actorId,
    this.devicePseudonym,
    this.patientPseudonym,
    this.alertId,
  });

  final String eventId;
  final String eventName;
  final TelemetrySource source;
  final DateTime occurredAt;
  final DateTime receivedAt;
  final int? clockSkewMs;
  final String? actorId;
  final String? devicePseudonym;
  final String? patientPseudonym;
  final String? alertId;
  final String appVersion;
  final Map<String, Object?> payload;
}

/// Porta de gravação da telemetria. Idempotente por `eventId`.
abstract interface class TelemetryStore {
  /// Grava os registros novos, ignora os que já existem e devolve os `eventId`
  /// presentes depois da escrita (novos ou já presentes).
  Future<Set<String>> insertIgnoringDuplicates(List<TelemetryRecord> records);
}
