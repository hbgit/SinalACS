import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/services/visit_queue_factory.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_uploader.dart';

import 'support/fakes.dart';

/// Transporte interno que só conta: aceita tudo e nunca recusa dono, para que
/// a recusa provada aqui seja a do embrulho.
class _TransporteContado implements TelemetryTransport {
  int chamadas = 0;

  @override
  Future<TelemetryIngestAck> ingestTelemetry(
    List<TelemetryEventRecord> events, {
    required String expectedUserId,
  }) async {
    chamadas++;
    return TelemetryIngestAck(accepted: {for (final e in events) e.eventId}, rejected: const {});
  }
}

/// `SessionBoundTelemetryTransport` (#83): sem sessão, ou com a sessão de
/// outro dono, o lote nunca chega ao transporte (no `BackendClient`, sem
/// sessão, isso viraria `renewSession` → `onSessionExpired`). Ids sintéticos.
void main() {
  const dono = '00000000-0000-4000-8000-0000000000a1';
  const outro = '00000000-0000-4000-8000-0000000000b1';

  AuthSession sessao(String userId) => AuthSession(
        accessToken: 'token-de-teste',
        tokenType: 'Bearer',
        userId: userId,
        role: 'acs',
        microAreaId: seedMicroAreaId,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      );

  final lote = [
    TelemetryEventRecord(
      eventId: '11111111-1111-4111-8111-111111111111',
      owner: dono,
      name: 'sync_attempt',
      occurredAt: DateTime.utc(2026, 10, 25),
      payload: const {'records_count': 1, 'network_type': 'unknown', 'channel': 'sync'},
    ),
  ];

  late FakeAcsBackend backend;
  late _TransporteContado interno;
  late SessionBoundTelemetryTransport transporte;

  setUp(() {
    backend = FakeAcsBackend();
    interno = _TransporteContado();
    transporte = SessionBoundTelemetryTransport(backend: backend, inner: interno);
  });

  test('sem sessão: recusa sem chamar o transporte', () async {
    backend.session = null;
    await expectLater(transporte.ingestTelemetry(lote, expectedUserId: dono), throwsStateError);
    expect(interno.chamadas, 0);
  });

  test('sessão de outro dono: recusa sem chamar o transporte', () async {
    backend.session = sessao(outro);
    await expectLater(transporte.ingestTelemetry(lote, expectedUserId: dono), throwsStateError);
    expect(interno.chamadas, 0);
  });

  test('sessão do próprio dono: chama o transporte uma vez', () async {
    backend.session = sessao(dono);
    final ack = await transporte.ingestTelemetry(lote, expectedUserId: dono);
    expect(interno.chamadas, 1);
    expect(ack.accepted, {lote.single.eventId});
  });
}
