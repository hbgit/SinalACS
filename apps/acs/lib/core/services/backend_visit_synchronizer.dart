import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

/// Leva as visitas da fila offline ao endpoint `visits.sync`.
///
/// Fica entre a fila (que não conhece o contrato do servidor) e o
/// [AcsBackend] (que não conhece a fila) — é a tradução entre os dois, no mesmo
/// espírito das implementações de `infrastructure/` no backend.
class BackendVisitSynchronizer implements VisitSynchronizer {
  BackendVisitSynchronizer({required this.backend, required this.patientIdFor});

  final AcsBackend backend;

  /// Resolve o UUID do paciente de uma visita.
  ///
  /// A fila guarda um rótulo de exibição, não o identificador; quem registrou a
  /// visita sabe a qual alerta ela pertence.
  final String Function(OfflineVisitRecord visit) patientIdFor;

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    final results = await backend.syncVisits([
      for (final visit in visits)
        VisitSyncEntry(
          localId: visit.localId,
          patientId: patientIdFor(visit),
          scheduledAt: visit.createdAt.toUtc(),
          completedAt: visit.createdAt.toUtc(),
          status: visit.outcome.isEmpty ? visit.status : visit.outcome,
          riskLevelBefore: _riskLevel(visit.risk),
          notes: const <String, String>{},
          version: visit.version,
        ),
    ]);

    return [
      for (final result in results)
        VisitSyncOutcome(
          localId: result.localId,
          status: result.syncStatus.name,
          serverVersion: result.serverVersion,
        ),
    ];
  }

  /// Risco é sinal clínico: um valor desconhecido vira `green` só para caber no
  /// enum, nunca para *rebaixar* um caso — o risco que vale é o do servidor, e
  /// esta visita já foi realizada.
  RiskLevel _riskLevel(String value) => switch (value.toLowerCase()) {
        'red' || 'vermelho' => RiskLevel.red,
        'yellow' || 'amarelo' => RiskLevel.yellow,
        _ => RiskLevel.green,
      };
}
