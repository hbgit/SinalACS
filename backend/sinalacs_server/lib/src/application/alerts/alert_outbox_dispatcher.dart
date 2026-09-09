import 'dart:io';
import 'dart:math';

import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';

/// Publica no broker as entregas que o outbox acumulou.
///
/// Roda em dois momentos: logo depois do commit da transação que criou o
/// alerta, para não custar latência no caminho feliz, e periodicamente, como
/// rede de segurança para o que ficou para trás — broker fora do ar, queda do
/// processo entre o commit e a publicação, ou falha de rede.
///
/// Uma falha de publicação nunca propaga: é registrada na entrada com backoff,
/// e a próxima varredura tenta de novo. Um alerta vermelho não pode ser
/// descartado por causa de um broker temporariamente indisponível (INV-03).
class AlertOutboxDispatcher {
  AlertOutboxDispatcher({
    required AlertOutbox outbox,
    required AlertPublisher publisher,
    DateTime Function()? clock,
  })  : _outbox = outbox,
        _publisher = publisher,
        _clock = clock ?? DateTime.now;

  /// Mesma escala do backoff de reconexão do MqttAlertDispatcher.
  static const initialBackoff = Duration(seconds: 2);
  static const maxBackoff = Duration(seconds: 60);
  static const defaultBatchSize = 32;

  final AlertOutbox _outbox;
  final AlertPublisher _publisher;
  final DateTime Function() _clock;

  /// Drena uma rodada e devolve quantas entregas foram publicadas.
  Future<int> drainOnce({int limit = defaultBatchSize}) async {
    final pending = await _outbox.claimDue(limit: limit);
    var published = 0;
    for (final entry in pending) {
      if (await _publishOne(entry)) published++;
    }
    return published;
  }

  /// Tenta publicar uma entrega específica, usada logo após o commit.
  ///
  /// Devolve `false` sem lançar quando o broker está indisponível — o alerta
  /// já está gravado e a varredura periódica assume a entrega.
  Future<bool> publishNow(String alertId) async {
    final pending = await _outbox.claimDue(limit: defaultBatchSize);
    var publishedTarget = false;
    for (final entry in pending) {
      final ok = await _publishOne(entry);
      if (ok && entry.delivery.alertId == alertId) publishedTarget = true;
    }
    return publishedTarget;
  }

  Future<bool> _publishOne(PendingDelivery entry) async {
    try {
      _publisher.publish(entry.delivery);
      await _outbox.markPublished(entry.entryId);
      return true;
    } catch (error) {
      await _outbox.markFailed(
        entry.entryId,
        error.toString(),
        _nextAttemptAt(entry.attempts),
      );
      stderr.writeln(
        'Entrega do alerta ${entry.delivery.alertId} adiada '
        '(tentativa ${entry.attempts}): $error',
      );
      return false;
    }
  }

  DateTime _nextAttemptAt(int attempts) {
    final seconds = min(
      initialBackoff.inSeconds * pow(2, max(0, attempts - 1)).toInt(),
      maxBackoff.inSeconds,
    );
    return _clock().toUtc().add(Duration(seconds: seconds));
  }
}
