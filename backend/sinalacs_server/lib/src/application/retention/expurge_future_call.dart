import 'dart:io';

import 'package:serverpod/protocol.dart' show FutureCallEntry;
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/retention/expurge_service.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_retention_store.dart';

/// Nome registrado no boot via `pod.registerFutureCall`.
const retentionExpurgeFutureCallName = 'retentionExpurge';

/// Identificador fixo do agendamento diário: um novo boot (ou uma nova
/// execução) remove qualquer pendente com este identificador antes de agendar,
/// então restarts não empilham execuções.
const retentionExpurgeScheduleIdentifier = 'retention-expurge-diario';

/// Rotina diária de expurgo (LGPD-RF07), registrada como
/// `retentionExpurge`.
///
/// O tipo de argumento é [SerializableModel] (o próprio limite da superclasse)
/// porque este call não recebe parâmetro: a entrada agendada grava
/// `serializedObject` nulo e nada é desserializado.
///
/// O registro do resultado é a decisão C1 — log operacional (stdout +
/// `session.log`), fora da cadeia de `audit_logs`: um job agendado não tem
/// usuário, e a evolução para a cadeia (ator de sistema) está planejada em
/// spec/lgpd_data_audit_action.md §4.
class ExpurgeFutureCall extends FutureCall<SerializableModel> {
  ExpurgeFutureCall({required RetentionPolicy policy}) : _policy = policy;

  final RetentionPolicy _policy;

  @override
  Future<void> invoke(Session session, SerializableModel? object) async {
    // Agenda a próxima janela ANTES de purgar: uma queda no meio da execução
    // não pode custar o agendamento de amanhã.
    await ensureRetentionExpurgeScheduled(session);

    final service = ExpurgeService(
      store: OrmRetentionStore(session: () => session),
      policy: _policy,
    );
    try {
      final result = await service.run();
      stdout.writeln('Expurgo LGPD-RF07 concluído: ${result.describe()}.');
      session.log('retention_expurge: ${result.describe()}');
    } catch (error) {
      // VAZ-01: só o tipo da falha, nunca o objeto bruto.
      stderr.writeln('Falha no expurgo LGPD-RF07 (${error.runtimeType}).');
    }
  }
}

/// Agenda (idempotente) a próxima execução para o próximo 03:00 UTC.
Future<void> ensureRetentionExpurgeScheduled(
  Session session, {
  DateTime Function()? clock,
}) async {
  final next = nextDailyRun((clock ?? DateTime.now)().toUtc());
  await FutureCallEntry.db.deleteWhere(
    session,
    where: (row) => row.identifier.equals(retentionExpurgeScheduleIdentifier),
  );
  await FutureCallEntry.db.insertRow(
    session,
    FutureCallEntry(
      name: retentionExpurgeFutureCallName,
      serializedObject: null,
      time: next,
      serverId: 'default',
      identifier: retentionExpurgeScheduleIdentifier,
    ),
  );
}
