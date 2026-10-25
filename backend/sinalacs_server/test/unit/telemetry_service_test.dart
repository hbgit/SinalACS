import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/telemetry/telemetry_pseudonymizer.dart';
import 'package:sinalacs_server/src/application/telemetry/telemetry_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// Ingestão dos eventos do aparelho (#83) com um store falso. Dados sintéticos.
const _acsId = '00000000-0000-4000-8000-0000000000a1';
const _ma = '00000000-0000-4000-8000-0000000000a2';
const _paciente = '3F2B8C1E-5A4D-4E6F-9B0A-1C2D3E4F5A6B';
const _local = '7a1d2c3b-4e5f-4a6b-8c9d-0e1f2a3b4c5d';
const _chave = 'chave-de-teste-do-pseudonimo';

String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final _sentAt = DateTime.utc(2026, 10, 25, 12);
final _receivedAt = DateTime.utc(2026, 10, 25, 12, 0, 3);

class _ThrowingStore implements TelemetryStore {
  @override
  Future<Set<String>> insertIgnoringDuplicates(
    List<TelemetryRecord> records,
  ) async => throw StateError('segredo-do-banco $_paciente');
}

class _FakeStore implements TelemetryStore {
  final calls = <List<TelemetryRecord>>[];

  @override
  Future<Set<String>> insertIgnoringDuplicates(
    List<TelemetryRecord> records,
  ) async {
    calls.add(records);
    return {for (final r in records) r.eventId};
  }

  List<TelemetryRecord> get all => [for (final c in calls) ...c];
}

AuthenticatedUser _user(UserRole role, {String? ma = _ma}) => AuthenticatedUser(
  id: _acsId,
  role: role,
  microAreaId: ma,
  deviceId: 'aparelho-do-token',
);

TelemetryEventInput _attempt(String id, {DateTime? occurredAt}) =>
    TelemetryEventInput(
      eventId: id,
      eventName: 'sync_attempt',
      occurredAt: occurredAt ?? _sentAt.subtract(const Duration(minutes: 1)),
      appVersion: '1.2.3',
      payloadJson: jsonEncode({
        'records_count': 3,
        'network_type': 'wifi',
        'channel': 'sync',
      }),
    );

TelemetryEventInput _visit(
  String id, {
  Map<String, Object?> extra = const {},
}) => TelemetryEventInput(
  eventId: id,
  eventName: 'visit_registered',
  occurredAt: _sentAt.subtract(const Duration(minutes: 2)),
  appVersion: '1.2.3',
  payloadJson: jsonEncode({
    'local_id': _local,
    'patient_id': _paciente,
    'visit_type': 'routine',
    'offline_flag': true,
    'network_type': 'none',
    'sync_status': 'queued',
    ...extra,
  }),
);

void main() {
  late _FakeStore store;
  late TelemetryService service;
  final pseudonymizer = TelemetryPseudonymizer(_chave);

  setUp(() {
    store = _FakeStore();
    service = TelemetryService(
      store: store,
      pseudonymizer: pseudonymizer,
      clock: () => _receivedAt,
    );
  });

  Future<TelemetryIngestResult> ingest(
    List<TelemetryEventInput> events, {
    AuthenticatedUser? user,
    String deviceId = 'instalacao-1',
  }) => service.ingestFromDevice(
    user: user ?? _user(UserRole.acs),
    deviceId: deviceId,
    sentAt: _sentAt,
    events: events,
  );

  test('paciente e coordenador recebem StateError', () async {
    for (final role in [
      UserRole.patient,
      UserRole.coordinator,
      UserRole.admin,
    ]) {
      await expectLater(
        ingest([_attempt(_id(1))], user: _user(role)),
        throwsA(isA<StateError>()),
      );
    }
    expect(store.calls, isEmpty);
  });

  test('ACS sem microárea no token recebe StateError', () async {
    await expectLater(
      ingest([_attempt(_id(1))], user: _user(UserRole.acs, ma: null)),
      throwsA(isA<StateError>()),
    );
  });

  test('lote de 201 é recusado antes do store', () async {
    expect(TelemetryService.maxIngestBatch, 200);
    final lote = [for (var i = 0; i < 201; i++) _attempt(_id(i))];
    await expectLater(ingest(lote), throwsA(isA<ArgumentError>()));
    expect(store.calls, isEmpty);

    final cheio = [for (var i = 0; i < 200; i++) _attempt(_id(i))];
    expect((await ingest(cheio)).acceptedEventIds, hasLength(200));
  });

  test('deviceId em branco ou longo demais recusa o lote', () async {
    for (final d in ['', '   ', 'x' * 129]) {
      await expectLater(
        ingest([_attempt(_id(1))], deviceId: d),
        throwsA(isA<ArgumentError>()),
      );
    }
    expect(store.calls, isEmpty);
  });

  test('evento inválido volta em rejected e não vai ao store', () async {
    final ruins = [
      _attempt('nao-e-uuid'),
      TelemetryEventInput(
        eventId: _id(2),
        eventName: 'sync_attempt',
        occurredAt: _sentAt,
        appVersion: '1.2.3',
        payloadJson: '{ilegível',
      ),
      TelemetryEventInput(
        eventId: _id(3),
        eventName: 'sync_attempt',
        occurredAt: _sentAt,
        appVersion: '1.2.3',
        payloadJson: '[1, 2]',
      ),
      TelemetryEventInput(
        eventId: _id(4),
        eventName: 'alert_triggered',
        occurredAt: _sentAt,
        appVersion: '1.2.3',
        payloadJson: jsonEncode({
          'risk_level': 'red',
          'mqtt_topic': 't',
          'location_known': true,
          'published': true,
        }),
      ),
      _visit(_id(5), extra: {'notes': 'Joana Sintética'}),
      TelemetryEventInput(
        eventId: _id(6),
        eventName: 'sync_attempt',
        occurredAt: _sentAt,
        appVersion: '',
        payloadJson: _attempt(_id(6)).payloadJson,
      ),
      TelemetryEventInput(
        eventId: _id(7),
        eventName: 'sync_attempt',
        occurredAt: _sentAt,
        appVersion: '1' * 33,
        payloadJson: _attempt(_id(7)).payloadJson,
      ),
      TelemetryEventInput(
        eventId: _id(8),
        eventName: 'sync_attempt',
        occurredAt: _sentAt,
        appVersion: '1.2.3',
        payloadJson: ' ' * 4097,
      ),
    ];
    final r = await ingest([...ruins, _attempt(_id(9))]);

    expect(r.rejectedEventIds, [
      'nao-e-uuid',
      for (var i = 2; i <= 8; i++) _id(i),
    ]);
    expect(r.acceptedEventIds, [_id(9)]);
    expect(store.all.map((e) => e.eventId), [_id(9)]);
  });

  test('actorId vem do token, não do payload', () async {
    final r = await ingest([
      TelemetryEventInput(
        eventId: _id(1),
        eventName: 'sync_attempt',
        occurredAt: _sentAt,
        appVersion: '1.2.3',
        payloadJson: jsonEncode({
          'records_count': 3,
          'network_type': 'wifi',
          'channel': 'sync',
          'acs_id': '00000000-0000-4000-8000-0000000000ff',
        }),
      ),
      _attempt(_id(2)),
    ]);
    expect(r.rejectedEventIds, [_id(1)]);

    final gravado = store.all.single;
    expect(gravado.actorId, _acsId);
    expect(gravado.devicePseudonym, pseudonymizer.device('instalacao-1'));
    expect(gravado.source, TelemetrySource.acsApp);
    expect(gravado.appVersion, '1.2.3');
    expect(gravado.patientPseudonym, isNull);
    expect(gravado.receivedAt, _receivedAt);
  });

  test('patient_id sai do payload e vira patientPseudonym', () async {
    const alerta = 'ABCDEF01-2345-4678-89AB-CDEF01234567';
    await ingest([
      _visit(_id(1)),
      _visit(_id(2), extra: {'visit_type': 'alert', 'alert_id': alerta}),
    ]);

    final [rotina, comAlerta] = store.all;
    expect(rotina.patientPseudonym, pseudonymizer.patient(_paciente));
    expect(rotina.payload.containsKey('patient_id'), isFalse);
    expect(rotina.alertId, isNull);
    expect(
      jsonEncode(rotina.payload).toLowerCase(),
      isNot(contains(_paciente.toLowerCase())),
    );

    expect(comAlerta.alertId, alerta.toLowerCase());
    expect(comAlerta.payload['alert_id'], alerta.toLowerCase());
    expect(comAlerta.payload.containsKey('patient_id'), isFalse);
  });

  test('ids e UUIDs do payload saem em minúsculas', () async {
    const maiusculo = 'AAAAAAAA-0000-4000-8000-00000000000B';
    final r = await ingest([
      _visit(maiusculo, extra: {'local_id': _local.toUpperCase()}),
    ]);
    expect(r.acceptedEventIds, [maiusculo.toLowerCase()]);
    expect(store.all.single.eventId, maiusculo.toLowerCase());
    expect(store.all.single.payload['local_id'], _local);
  });

  test('ids duplicados dentro do mesmo lote contam uma vez só', () async {
    const maiusculo = 'AAAAAAAA-0000-4000-8000-00000000000C';
    final r = await ingest([
      _attempt(maiusculo),
      _attempt(maiusculo.toLowerCase()),
      _attempt('ruim'),
      _attempt('ruim'),
    ]);
    expect(r.acceptedEventIds, [maiusculo.toLowerCase()]);
    expect(r.rejectedEventIds, ['ruim']);
    expect(store.all, hasLength(1));
  });

  test('occurredAt no futuro além de 5 min é recusado', () async {
    final r = await ingest([
      _attempt(_id(1), occurredAt: _sentAt.add(const Duration(minutes: 5))),
      _attempt(
        _id(2),
        occurredAt: _sentAt.add(const Duration(minutes: 5, milliseconds: 1)),
      ),
    ]);
    expect(r.acceptedEventIds, [_id(1)]);
    expect(r.rejectedEventIds, [_id(2)]);
  });

  test('clockSkewMs = receivedAt − sentAt', () async {
    await ingest([_attempt(_id(1))]);
    expect(store.all.single.clockSkewMs, 3000);
  });

  test('lote só de recusados não chama o store', () async {
    final r = await ingest([_attempt('ruim')]);
    expect(r.acceptedEventIds, isEmpty);
    expect(store.calls, isEmpty);
  });

  group('alert_triggered (#83)', () {
    final alert = AlertDelivery(
      alertId: '00000000-0000-4000-8000-0000000000b1',
      patientId: _paciente,
      microAreaId: _ma,
      riskLevel: 'red',
      locationHash: 'hash-sintetico-de-teste',
      triggeredAt: DateTime.utc(2026, 10, 25, 11, 59),
    );

    test('tem id determinístico e não carrega locationHash', () async {
      await service.alertTriggered(alert: alert, published: true);
      await service.alertTriggered(alert: alert, published: true);

      expect(store.all, hasLength(2));
      final r = store.all.first;
      expect(r.eventId, store.all.last.eventId);
      expect(
        r.eventId,
        const Uuid().v5(
          TelemetryService.telemetryNamespace,
          'alert_triggered:${alert.alertId}',
        ),
      );
      expect(r.eventName, 'alert_triggered');
      expect(r.source, TelemetrySource.backend);
      expect(r.occurredAt, alert.triggeredAt);
      expect(r.receivedAt, _receivedAt);
      expect(r.alertId, alert.alertId);
      expect(r.actorId, isNull);
      expect(r.appVersion, TelemetryService.backendVersion);
      expect(r.patientPseudonym, pseudonymizer.patient(_paciente));
      expect(r.payload, {
        'risk_level': 'red',
        'mqtt_topic': alert.topic,
        'location_known': true,
        'published': true,
      });
      expect(jsonEncode(r.payload), isNot(contains(alert.locationHash)));
      expect(jsonEncode(r.payload), isNot(contains(_paciente)));
    });

    test('local desconhecido vira location_known false', () async {
      await service.alertTriggered(
        alert: AlertDelivery(
          alertId: alert.alertId,
          patientId: _paciente,
          microAreaId: _ma,
          riskLevel: 'red',
          locationHash: TelemetryService.unknownLocationHash,
          triggeredAt: alert.triggeredAt,
        ),
        published: false,
      );

      expect(store.all.single.payload['location_known'], isFalse);
      expect(store.all.single.payload['published'], isFalse);
    });

    test('store lançando não propaga', () async {
      final quebrado = TelemetryService(
        store: _ThrowingStore(),
        pseudonymizer: pseudonymizer,
        clock: () => _receivedAt,
      );

      await quebrado.alertTriggered(alert: alert, published: true);
    });

    test('unknownLocationHash espelha o app do paciente', () {
      final fonte = File(
        '../../apps/patient/lib/core/privacy/location_hash.dart',
      ).readAsStringSync();
      final m = RegExp(
        r"const String unknownLocationHash = '([^']+)';",
      ).firstMatch(fonte);

      expect(m, isNotNull);
      expect(TelemetryService.unknownLocationHash, m!.group(1));
    });

    test('backendVersion espelha a versão do pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^#?\s*version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(m, isNotNull);
      expect(TelemetryService.backendVersion, m!.group(1));
    });
  });
}
