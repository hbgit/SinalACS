import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [AlertOutbox] sobre o ORM do Serverpod.
///
/// Segue a forma do `OrmAlertStore`: a `Session` chega como thunk, e uma
/// `Transaction` opcional permite que o enfileiramento participe da transação
/// que grava o alerta.
class OrmAlertOutbox implements AlertOutbox {
  OrmAlertOutbox({
    required Session Function() session,
    Transaction? transaction,
    DateTime Function()? clock,
  })  : _session = session,
        _transaction = transaction,
        _clock = clock ?? DateTime.now;

  final Session Function() _session;
  final Transaction? _transaction;
  final DateTime Function() _clock;

  @override
  Future<void> enqueue(AlertDelivery alert) async {
    final now = _clock().toUtc();
    await AlertOutboxEntry.db.insertRow(
      _session(),
      AlertOutboxEntry(
        alertId: UuidValue.fromString(alert.alertId),
        topic: alert.topic,
        payload: alert.toJson(),
        createdAt: now,
        attempts: 0,
        // Elegível imediatamente: a tentativa após o commit deve pegá-la.
        nextAttemptAt: now,
      ),
      transaction: _transaction,
    );
  }

  @override
  Future<List<PendingDelivery>> claimDue({int limit = 32}) async {
    final session = _session();
    final now = _clock().toUtc();

    // SKIP LOCKED impede que duas instâncias publiquem a mesma entrada. O ORM
    // não expressa isso, daí o SQL direto. Reclamar e incrementar a tentativa
    // na mesma instrução evita que uma falha de processo deixe a entrada presa.
    final rows = await session.db.unsafeQuery(
      '''
      UPDATE alert_outbox AS o
         SET attempts = o.attempts + 1
       WHERE o.id IN (
             SELECT c.id
               FROM alert_outbox AS c
              WHERE c."publishedAt" IS NULL
                AND c."nextAttemptAt" <= @now
              ORDER BY c."createdAt"
              LIMIT @limit
                FOR UPDATE SKIP LOCKED
       )
   RETURNING o.id, o.payload, o.attempts;
      ''',
      parameters: QueryParameters.named({'now': now, 'limit': limit}),
      transaction: _transaction,
    );

    final claimed = <PendingDelivery>[];
    for (final row in rows) {
      final entryId = row[0].toString();
      final delivery = AlertDelivery.tryParse(row[1] as String);
      if (delivery == null) {
        // Entrada corrompida não pode travar a fila inteira: é marcada como
        // falha permanente e a varredura segue.
        await markFailed(
          entryId,
          'payload malformado, não reidratável',
          now.add(const Duration(days: 365)),
        );
        continue;
      }
      claimed.add(PendingDelivery(
        entryId: entryId,
        delivery: delivery,
        attempts: row[2] as int,
      ));
    }
    return claimed;
  }

  @override
  Future<void> markPublished(String entryId) async {
    await _session().db.unsafeExecute(
      'UPDATE alert_outbox SET "publishedAt" = @now, "lastError" = NULL '
      'WHERE id = @id::uuid;',
      parameters: QueryParameters.named({
        'now': _clock().toUtc(),
        'id': entryId,
      }),
      transaction: _transaction,
    );
  }

  @override
  Future<void> markFailed(
    String entryId,
    String error,
    DateTime nextAttemptAt,
  ) async {
    await _session().db.unsafeExecute(
      'UPDATE alert_outbox SET "nextAttemptAt" = @next, "lastError" = @error '
      'WHERE id = @id::uuid;',
      parameters: QueryParameters.named({
        'next': nextAttemptAt.toUtc(),
        'error': error,
        'id': entryId,
      }),
      transaction: _transaction,
    );
  }
}
