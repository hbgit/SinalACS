import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

/// Leva as visitas da fila offline ao endpoint `visits.sync`.
///
/// Fica entre a fila (que não conhece o contrato do servidor) e o
/// [AcsBackend] (que não conhece a fila) — é a tradução entre os dois, no mesmo
/// espírito das implementações de `infrastructure/` no backend.
///
/// Um sincronizador pertence a UM dono ([ownerId], o `userId` do ACS que
/// registrou as visitas). `visits.sync` atribui a visita ao ACS do token, então
/// enviar o lote de A com a sessão de B daria a B um trabalho que não é dele:
/// [push] confere a sessão NO MOMENTO do envio (não só na construção) e, se ela
/// não é do dono, recusa sem tocar na rede; o backend confere de novo depois
/// de resolver o token ([AcsBackend.syncVisits] com `expectedUserId`). A
/// recusa é recuperável — a fila converte a exceção em
/// `SyncOutcomeKind.error` e o lote continua pendente, esperando o dono
/// entrar de novo.
class BackendVisitSynchronizer implements VisitSynchronizer {
  BackendVisitSynchronizer({required this.backend, required String ownerId})
      : ownerId = requireOwnerId(ownerId);

  final AcsBackend backend;

  /// `userId` do ACS dono das visitas que este sincronizador envia.
  final String ownerId;

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    // Checagem cedo (sem sessão do dono, nem monta o lote) e de novo dentro
    // do backend, depois de o token ser resolvido: uma renovação pode esperar
    // o login de outro ACS e voltar com a sessão DELE.
    if (backend.session?.userId != ownerId) throw sessionOwnerMismatch;
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
    ], expectedUserId: ownerId);

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
