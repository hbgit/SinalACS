import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Colunas de escalonamento de `alerts` (#44): aditivas e anuláveis. Dados
/// sintéticos; ids próprios.
const _paciente = '00000000-0000-4000-8000-0000000000a1';
final _t = DateTime.utc(2026, 10, 11, 12);

Future<Alert> _alerta(Session s, {Alert? base}) => Alert.db.insertRow(
  s,
  base ??
      Alert(
        patientId: UuidValue.fromString(_paciente),
        triggeredAt: _t,
        riskLevel: RiskLevel.red,
        locationHash: 'hash-sintetico',
        status: AlertStatus.pending,
        mqttTopic: 'sinalacs/v1/microareas/x/alerts',
        deviceId: 'device-sintetico',
        retryCount: 0,
        version: 0,
      ),
);

void main() {
  withServerpod('Dado as colunas de escalonamento de alerts (#44)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    setUp(() async {
      session = sessionBuilder.build();
      await User.db.insertRow(
        session,
        User(
          id: UuidValue.fromString(_paciente),
          cpfHash: 'alert-escalation-paciente',
          name: 'Paciente Sintético',
          birthDate: DateTime.utc(1980),
          role: UserRole.patient,
          createdAt: _t,
          updatedAt: _t,
        ),
      );
      await Patient.db.insertRow(
        session,
        await encryptedPatient(
          id: _paciente,
          emergencyContact: 'x',
          isChronic: false,
        ),
      );
    });

    test('um alerta novo nasce sem escalonamento', () async {
      final criado = await _alerta(session);
      final lido = await Alert.db.findById(session, criado.id!);
      expect(lido!.escalatedAt, isNull);
      expect(lido.escalatedBy, isNull);
      expect(lido.escalationReason, isNull);
    });

    test('o escalonamento persiste data, autor e motivo fechado', () async {
      final autor = UuidValue.fromString(_paciente);
      final criado = await _alerta(session);
      await Alert.db.updateRow(
        session,
        criado.copyWith(
          escalatedAt: _t,
          escalatedBy: autor,
          escalationReason: EscalationReason.noAckTimeout,
        ),
      );
      final lido = await Alert.db.findById(session, criado.id!);
      expect(lido!.escalatedAt, _t);
      expect(lido.escalatedBy, autor);
      expect(lido.escalationReason, EscalationReason.noAckTimeout);
    });
  });
}
