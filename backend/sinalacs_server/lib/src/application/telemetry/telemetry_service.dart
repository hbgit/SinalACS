import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/common/uuid_format.dart';
import 'package:sinalacs_server/src/application/telemetry/telemetry_pseudonymizer.dart';
import 'package:sinalacs_server/src/application/telemetry/telemetry_schema.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:uuid/uuid.dart';

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

/// Ingestão dos eventos que o app do ACS gerou offline (#83).
///
/// Idempotente por `eventId` (o store ignora o que já existe) e sem PII do
/// paciente: o `patient_id` de `visit_registered` vira `patientPseudonym` aqui
/// no servidor e sai do payload gravado.
class TelemetryService {
  TelemetryService({
    required TelemetryStore store,
    required TelemetryPseudonymizer pseudonymizer,
    DateTime Function()? clock,
  }) : _store = store,
       _pseudonymizer = pseudonymizer,
       _clock = clock ?? DateTime.now;

  final TelemetryStore _store;
  final TelemetryPseudonymizer _pseudonymizer;
  final DateTime Function() _clock;

  /// Namespace do UUID v5 dos eventos que nascem no backend: o mesmo alerta
  /// gera sempre o mesmo `eventId`, e o replay cai no `ON CONFLICT`.
  static const telemetryNamespace = '6f1d3c2a-9b4e-5d7f-8a1b-2c3d4e5f6a7b';

  /// Versão do servidor, gravada em `appVersion` dos eventos do backend.
  /// Espelha o `version` do `pubspec.yaml` (um teste compara os dois).
  static const backendVersion = '1.0.0';

  /// Espelho de `unknownLocationHash` em
  /// `apps/patient/lib/core/privacy/location_hash.dart`: o paciente sem GPS.
  static const unknownLocationHash = 'sem-local-00';

  /// Teto de eventos por chamada, checado antes de tocar o banco.
  static const maxIngestBatch = 200;

  /// Teto do `deviceId` do lote.
  static const maxDeviceIdLength = 128;

  /// Teto do `payloadJson` de um evento, em caracteres.
  static const maxPayloadLength = 4096;

  /// Teto do `appVersion` de um evento.
  static const maxAppVersionLength = 32;

  /// Folga aceita entre o `occurredAt` de um evento e o `sentAt` do lote.
  static const futureTolerance = Duration(minutes: 5);

  /// Chaves do payload que guardam UUID e saem normalizadas em minúsculas.
  static const _uuidPayloadKeys = ['local_id', 'alert_id', 'attempt_event_id'];

  /// Registra o `alert_triggered` (PRD §1.3) depois do commit do alerta e da
  /// tentativa imediata de publicação. Nunca lança (INV-03): a falha do store
  /// vai para o log só com o tipo do erro. A posição não é gravada, só se o
  /// aparelho informou uma (`location_known`, decisão A1).
  Future<void> alertTriggered({
    required AlertDelivery alert,
    required bool published,
  }) async {
    try {
      await _store.insertIgnoringDuplicates([
        TelemetryRecord(
          eventId: const Uuid().v5(
            telemetryNamespace,
            '${TelemetryEventNames.alertTriggered}:${alert.alertId}',
          ),
          eventName: TelemetryEventNames.alertTriggered,
          source: TelemetrySource.backend,
          occurredAt: alert.triggeredAt,
          receivedAt: _clock(),
          appVersion: backendVersion,
          patientPseudonym: _pseudonymizer.patient(alert.patientId),
          alertId: alert.alertId,
          payload: {
            'risk_level': alert.riskLevel,
            'mqtt_topic': alert.topic,
            'location_known': alert.locationHash != unknownLocationHash,
            'published': published,
          },
        ),
      ]);
    } catch (error) {
      stderr.writeln(
        'Falha ao gravar telemetria (alert_triggered, '
        'erro ${error.runtimeType}).',
      );
    }
  }

  /// Valida e grava um lote de eventos do aparelho.
  ///
  /// Recusa o **lote** (sem tocar o store): papel diferente de `acs` ou token
  /// sem microárea → [StateError]; mais de [maxIngestBatch] eventos ou
  /// `deviceId` em branco ou acima de [maxDeviceIdLength] → [ArgumentError].
  ///
  /// Recusa **o evento**, que volta em `rejectedEventIds`, quando: o `eventId`
  /// não é UUID (volta com o texto original, para o app poder apagar a linha);
  /// `appVersion` está vazio ou passa de [maxAppVersionLength]; `payloadJson`
  /// passa de [maxPayloadLength], é ilegível ou não é objeto JSON; o nome não
  /// é emitível pelo aparelho; o payload foge do esquema fechado; ou
  /// `occurredAt` passa de `sentAt` + [futureTolerance].
  ///
  /// O `eventId` e os UUIDs do payload (`local_id`, `alert_id`,
  /// `attempt_event_id`) são normalizados para minúsculas antes de gravar, e
  /// os ids devolvidos em `acceptedEventIds`/`rejectedEventIds` (exceto o
  /// `eventId` que não é UUID) saem assim. Um id repetido no mesmo lote conta
  /// uma vez só: vale a primeira ocorrência.
  ///
  /// O `actorId` vem de [user] e nunca do cliente. Não grava linha em
  /// `audit_logs`: é métrica operacional e não acesso a dado de titular, o app
  /// chama a cada sincronização e o paciente só aparece pseudonimizado.
  Future<TelemetryIngestResult> ingestFromDevice({
    required AuthenticatedUser user,
    required String deviceId,
    required DateTime sentAt,
    required List<TelemetryEventInput> events,
  }) async {
    Authorization.require(
      user,
      roles: const {UserRole.acs},
      onDenied: () => StateError('só o ACS envia telemetria do aparelho'),
    );
    if (events.length > maxIngestBatch) {
      throw ArgumentError(
        'lote de telemetria acima de $maxIngestBatch eventos',
      );
    }
    if (deviceId.trim().isEmpty || deviceId.length > maxDeviceIdLength) {
      throw ArgumentError('deviceId inválido');
    }

    final receivedAt = _clock().toUtc();
    final clockSkewMs = receivedAt.difference(sentAt).inMilliseconds;
    final devicePseudonym = _pseudonymizer.device(deviceId);
    final limit = sentAt.add(futureTolerance);

    final seen = <String>{};
    final rejected = <String>[];
    final records = <TelemetryRecord>[];
    for (final event in events) {
      final valid = isUuidFormat(event.eventId);
      final id = valid ? event.eventId.toLowerCase() : event.eventId;
      if (!seen.add(id)) continue;

      final record = valid
          ? _toRecord(
              event,
              eventId: id,
              user: user,
              receivedAt: receivedAt,
              clockSkewMs: clockSkewMs,
              devicePseudonym: devicePseudonym,
              limit: limit,
            )
          : null;
      if (record == null) {
        rejected.add(id);
      } else {
        records.add(record);
      }
    }

    final present = records.isEmpty
        ? const <String>{}
        : await _store.insertIgnoringDuplicates(records);
    // Um aceito que o store não confirmou fica fora das duas listas: o app o
    // mantém e reenvia, em vez de apagar um evento que não foi gravado.
    return TelemetryIngestResult(
      acceptedEventIds: [
        for (final r in records)
          if (present.contains(r.eventId)) r.eventId,
      ],
      rejectedEventIds: rejected,
    );
  }

  TelemetryRecord? _toRecord(
    TelemetryEventInput event, {
    required String eventId,
    required AuthenticatedUser user,
    required DateTime receivedAt,
    required int clockSkewMs,
    required String devicePseudonym,
    required DateTime limit,
  }) {
    if (event.appVersion.isEmpty ||
        event.appVersion.length > maxAppVersionLength) {
      return null;
    }
    if (event.payloadJson.length > maxPayloadLength) return null;
    if (event.occurredAt.isAfter(limit)) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(event.payloadJson);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final payload = validateDevicePayload(
      event.eventName,
      Map<String, Object?>.from(decoded),
    );
    if (payload == null) return null;

    for (final key in _uuidPayloadKeys) {
      final value = payload[key];
      if (value is String) payload[key] = value.toLowerCase();
    }

    String? patientPseudonym;
    String? alertId;
    if (event.eventName == TelemetryEventNames.visitRegistered) {
      patientPseudonym = _pseudonymizer.patient(
        payload.remove('patient_id')! as String,
      );
      alertId = payload['alert_id'] as String?;
    }

    return TelemetryRecord(
      eventId: eventId,
      eventName: event.eventName,
      source: TelemetrySource.acsApp,
      occurredAt: event.occurredAt.toUtc(),
      receivedAt: receivedAt,
      clockSkewMs: clockSkewMs,
      actorId: user.id,
      devicePseudonym: devicePseudonym,
      patientPseudonym: patientPseudonym,
      alertId: alertId,
      appVersion: event.appVersion,
      payload: payload,
    );
  }
}
