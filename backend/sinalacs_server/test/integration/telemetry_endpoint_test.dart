import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// `telemetry.ingest` (#83) pelo endpoint, com tokens reais e Postgres real:
/// idempotência do reenvio e nenhuma linha com o UUID cru do paciente.
/// Dados sintéticos; o ACS e a microárea só existem no token.
const _acs = '00000000-0000-4000-8000-0000000000e1';
const _ma = '00000000-0000-4000-8000-0000000000e2';
const _paciente = '00000000-0000-4000-8000-0000000000e3';
const _localId = '00000000-0000-4000-8000-0000000000e4';

String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

String _token(UserRole role) => AlertRuntime.instance.auth.issueToken(
  AuthenticatedUser(
    id: _acs,
    role: role,
    microAreaId: role == UserRole.acs ? _ma : null,
    deviceId: 'aparelho-sintetico',
  ),
);

// Instante com milissegundos, em UTC: o teste confere que o store o grava e o
// relê no mesmo instante, qualquer que seja o fuso da máquina.
final _sentAt = DateTime.now().toUtc();
final _occurredAt = DateTime.utc(2026, 10, 25, 9, 30, 15, 250);

List<TelemetryEventInput> _lote() => [
  TelemetryEventInput(
    eventId: _id(1),
    eventName: 'visit_registered',
    occurredAt: _occurredAt,
    appVersion: '1.0.0',
    payloadJson: jsonEncode({
      'local_id': _localId,
      'patient_id': _paciente,
      'visit_type': 'routine',
      'offline_flag': true,
      'network_type': 'none',
      'sync_status': 'queued',
    }),
  ),
  TelemetryEventInput(
    eventId: _id(2),
    eventName: 'sync_attempt',
    occurredAt: _occurredAt,
    appVersion: '1.0.0',
    payloadJson: jsonEncode({
      'records_count': 1,
      'network_type': 'wifi',
      'channel': 'sync',
    }),
  ),
  TelemetryEventInput(
    eventId: _id(3),
    eventName: 'sync_attempt',
    occurredAt: _occurredAt,
    appVersion: '1.0.0',
    payloadJson: jsonEncode({'notes': 'Joana Sintética'}),
  ),
];

void main() {
  withServerpod('Dado o endpoint telemetry.ingest (#83)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    setUp(() => session = sessionBuilder.build());

    Future<int> linhas() async {
      final r = await session.db.unsafeQuery(
        'SELECT count(*) AS c FROM telemetry_events',
      );
      return r.single.toColumnMap()['c']! as int;
    }

    Future<TelemetryIngestResult> ingest(String token) =>
        endpoints.telemetry.ingest(
          sessionBuilder,
          accessToken: token,
          deviceId: 'instalacao-sintetica',
          sentAt: _sentAt,
          events: _lote(),
        );

    test(
      'ingest repetido devolve os mesmos ids aceitos e não duplica',
      () async {
        final t = _token(UserRole.acs);
        final a = await ingest(t);
        expect(a.acceptedEventIds, [_id(1), _id(2)]);
        expect(a.rejectedEventIds, [_id(3)]);
        expect(await linhas(), 2);

        final b = await ingest(t);
        expect(b.acceptedEventIds, a.acceptedEventIds);
        expect(b.rejectedEventIds, a.rejectedEventIds);
        expect(await linhas(), 2);

        // Pendência da Task 4: `occurredAt` relido é o mesmo instante.
        final rows = await TelemetryEvent.db.find(session);
        for (final row in rows) {
          expect(row.occurredAt.toUtc(), _occurredAt);
          expect(row.actorId?.toString(), _acs);
          expect(row.source, TelemetrySource.acsApp);
        }
        final visita = rows.singleWhere(
          (r) => r.eventName == 'visit_registered',
        );
        expect(visita.patientPseudonym, hasLength(64));
      },
    );

    test('nenhuma linha guarda o UUID do paciente', () async {
      await ingest(_token(UserRole.acs));
      final r = await session.db.unsafeQuery(
        "SELECT count(*) AS c FROM telemetry_events "
        "WHERE payload LIKE '%' || @uuid || '%' "
        'OR "patientPseudonym" = @uuid OR "devicePseudonym" = @dev',
        parameters: QueryParameters.named({
          'uuid': _paciente,
          'dev': 'instalacao-sintetica',
        }),
      );
      expect(r.single.toColumnMap()['c'], 0);
      expect(await linhas(), 2);
    });

    test('ACS sem token recebe a recusa padrão', () async {
      await expectLater(
        ingest('token-invalido'),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(await linhas(), 0);
    });

    test('paciente recebe AlertPermissionException', () async {
      await expectLater(
        ingest(_token(UserRole.patient)),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(await linhas(), 0);
    });

    test('lote acima do teto vira AlertValidationException', () async {
      await expectLater(
        endpoints.telemetry.ingest(
          sessionBuilder,
          accessToken: _token(UserRole.acs),
          deviceId: 'instalacao-sintetica',
          sentAt: _sentAt,
          events: [for (var i = 0; i < 201; i++) ..._lote().take(1)],
        ),
        throwsA(isA<AlertValidationException>()),
      );
      expect(await linhas(), 0);
    });
  });
}
