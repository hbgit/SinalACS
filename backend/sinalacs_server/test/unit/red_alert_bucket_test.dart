import 'package:sinalacs_server/src/application/admin/red_alert_bucket.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// A partição dos vermelhos por estado (#87, INV-03): todo `AlertStatus` cai
/// em exatamente um contador de `AdminIndicators`.
void main() {
  test('todo AlertStatus cai em exatamente um balde', () {
    for (final s in AlertStatus.values) {
      final baldes = RedAlertBucket.values.where((b) => b.statuses.contains(s));
      expect(baldes, hasLength(1), reason: s.name);
      expect(RedAlertBucket.of(s), baldes.single);
    }
  });

  test('escalated é aberto; acknowledged, reconhecido; resolved, concluído', () {
    expect(RedAlertBucket.of(AlertStatus.pending), RedAlertBucket.open);
    expect(RedAlertBucket.of(AlertStatus.escalated), RedAlertBucket.open);
    expect(
      RedAlertBucket.of(AlertStatus.acknowledged),
      RedAlertBucket.acknowledged,
    );
    expect(RedAlertBucket.of(AlertStatus.resolved), RedAlertBucket.resolved);
  });

  test('sqlList só tem nomes de enum entre aspas simples', () {
    expect(RedAlertBucket.open.sqlList, "'pending','escalated'");
    expect(RedAlertBucket.acknowledged.sqlList, "'acknowledged'");
    expect(RedAlertBucket.resolved.sqlList, "'resolved'");
  });
}
