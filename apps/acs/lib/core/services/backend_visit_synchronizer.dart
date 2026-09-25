import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

/// Leva as visitas da fila offline ao endpoint `visits.sync`.
///
/// Fica entre a fila (que não conhece o contrato do servidor) e o
/// [AcsBackend] (que não conhece a fila) — é a tradução entre os dois, no mesmo
/// espírito das implementações de `infrastructure/` no backend.
class BackendVisitSynchronizer implements VisitSynchronizer {
  BackendVisitSynchronizer({required this.backend});

  final AcsBackend backend;

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    final results = await backend.syncVisits([
      for (final visit in visits)
        VisitSyncEntry(
          localId: visit.localId,
          patientId: visit.patientId,
          scheduledAt: visit.createdAt.toUtc(),
          completedAt: visit.createdAt.toUtc(),
          status: visit.outcome.isEmpty ? visit.status : visit.outcome,
          riskLevelBefore: _riskLevel(visit.risk),
          notes: visit.notes.trim().isEmpty
              ? const <String, String>{}
              : <String, String>{'campo': visit.notes.trim()},
          version: visit.version,
          // Contrato para geofencing futuro (RF12, decisão §4) — desenho
          // apenas. Nenhuma API nativa de geofence foi integrada nesta task,
          // nenhuma permissão de localização em primeiro/segundo plano foi
          // adicionada ao AndroidManifest.xml, e a escolha de plugin/texto de
          // divulgação seguem bloqueados por revisão de produto/jurídico. Todo
          // check-in registrado por este app hoje é manual.
          arrivalMethod: ArrivalMethod.manual,
        ),
    ]);

    return [
      for (final result in results)
        VisitSyncOutcome(
          localId: result.localId,
          status: result.syncStatus.name,
          serverVersion: result.serverVersion,
          message: result.message,
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
