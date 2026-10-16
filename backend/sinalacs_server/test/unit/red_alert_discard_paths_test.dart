import 'dart:io';

import 'package:sinalacs_server/src/application/alerts/alert_outbox_dispatcher.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Inventário das rotas que podem escrever, apagar ou reclassificar um alerta
/// vermelho (#44, Task 3). O invariante provado: nenhum caminho descarta,
/// silencia ou reclassifica um alerta vermelho sem deixar registro de
/// auditoria.
///
/// Este arquivo é hermético (fakes em memória). As rotas que dependem de
/// Postgres (ACK com auditoria, ACK por MQTT, retenção, anonimização, outbox
/// real) estão em `test/integration/red_alert_discard_paths_db_test.dart`.
///
/// Os buracos reais que a Task 3 provou (ACK sem auditoria, expurgo de
/// vermelho pending) foram fechados na Task 4: todos os itens estão ativos.

// ---------------------------------------------------------------------------
// Varredura do fonte: quem pode escrever em `alerts`.
// ---------------------------------------------------------------------------

/// Mutações da tabela `alerts`: SQL cru (qualquer caixa, aspas opcionais,
/// quebra de linha entre UPDATE/DELETE/INSERT e o nome) e escrita do ORM
/// (`Alert.db.update*/delete*/insert*` e `db.update<Alert>(…)` etc.).
///
/// Escopo: SÓ `alerts`. `alert_deliveries`, `alert_outbox` e
/// `alert_idempotency_keys` ficam de fora de propósito (o brief fala do alerta
/// em si; o ACK também insere em `alert_deliveries`, o que não descarta nem
/// reclassifica alerta). `DTO status: AlertStatus.` também fica de fora: não
/// escreve em tabela; qualquer escrita de status passa por `Alert.db.update*`
/// ou SQL, já cobertos.
final _mutationPattern = RegExp(
  r'(UPDATE|DELETE\s+FROM|INSERT\s+INTO)\s+"?alerts"?(?![\w])'
  r'|\bAlert\.db\.(update|delete|insert)\w*'
  r'|\.(update|delete|insert)\w*<Alert>',
  caseSensitive: false,
  multiLine: true,
);

/// Arquivos autorizados a casar com [_mutationPattern]: só escritores reais,
/// cada um com o motivo. Arquivos que apenas montam DTO ou leem não entram.
/// `escalate` (Task 6) entra como `orm_alert_escalation_store.dart`; enquanto o
/// arquivo não existe, a varredura exige só que todo escritor ENCONTRADO esteja
/// aqui (subconjunto).
const _allowedWriters = <String, String>{
  'infrastructure/database/orm_alert_store.dart':
      'save() insere o alerta como pending; acknowledge() leva a acknowledged '
      '(e preserva resolved); resolve() leva acknowledged → resolved, sob '
      'trava e auditado na mesma transação (#76)',
  'infrastructure/database/orm_retention_store.dart':
      'expurgo LGPD: DELETE FROM alerts por triggeredAt — hoje SEM guarda de '
      'status/risco (buraco, corrigido na Task 4)',
  'infrastructure/database/orm_alert_escalation_store.dart':
      'Task 6: UPDATE só de escalatedAt/colunas de escalonamento, nunca status',
};

Map<String, List<String>> _grepSources(RegExp pattern) {
  final root = Directory('lib/src');
  final found = <String, List<String>>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relative = entity.path.substring('lib/src/'.length);
    if (relative.startsWith('generated/')) continue;
    // Texto inteiro (SQL pode quebrar linha), sem as linhas de comentário.
    final code = entity
        .readAsLinesSync()
        .map((l) => l.trimLeft().startsWith('//') ? '' : l)
        .join('\n');
    final hits = pattern
        .allMatches(code)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'\s+'), ' '))
        .toList();
    if (hits.isNotEmpty) found[relative] = hits;
  }
  return found;
}

// ---------------------------------------------------------------------------
// Fakes.
// ---------------------------------------------------------------------------

class _MemoryStore implements AlertStore {
  final Map<String, AlertDelivery> alerts = {};
  final Map<String, String> status = {};
  final Map<String, RedAlertRecord> keys = {};
  var saveCalls = 0;
  final List<AuditEvent> audits = [];

  @override
  Future<void> save(AlertDelivery alert, {required String deviceId}) async {
    saveCalls++;
    alerts[alert.alertId] = alert;
    status[alert.alertId] = 'pending';
  }

  @override
  Future<bool> acknowledge({
    required String alertId,
    required String acsId,
    required String microAreaId,
    required AuditEvent audit,
  }) async {
    audits.add(audit);
    status[alertId] = 'acknowledged';
    return true;
  }

  @override
  Future<RedAlertRecord?> findByIdempotencyKey(String k) async => keys[k];

  @override
  Future<void> rememberIdempotencyKey(RedAlertRecord r) async =>
      keys[r.idempotencyKey] = r;

  @override
  Future<AlertStatusSnapshot?> latestForPatient(String patientId) async => null;

  @override
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  }) async {
    if (status[alertId] != 'acknowledged') {
      return const AlertResolveAttempt(AlertResolveOutcome.notAcknowledged);
    }
    audits.add(auditFor(AlertResolveOutcome.resolved));
    status[alertId] = 'resolved';
    return AlertResolveAttempt(AlertResolveOutcome.resolved, resolvedAt: now);
  }
}

class _MemoryOutbox implements AlertOutbox {
  final List<AlertDelivery> enqueued = [];
  final Set<String> publishedIds = {};
  final Map<String, int> attempts = {};
  final Map<String, String> errors = {};

  @override
  Future<void> enqueue(AlertDelivery alert) async => enqueued.add(alert);

  @override
  Future<List<PendingDelivery>> claimDue({int limit = 32}) async => [
    for (final a in enqueued)
      if (!publishedIds.contains('entry-${a.alertId}'))
        PendingDelivery(
          entryId: 'entry-${a.alertId}',
          delivery: a,
          attempts: attempts.update(
            'entry-${a.alertId}',
            (v) => v + 1,
            ifAbsent: () => 1,
          ),
        ),
  ];

  @override
  Future<void> markPublished(String entryId) async => publishedIds.add(entryId);

  @override
  Future<void> markFailed(String entryId, String error, DateTime next) async =>
      errors[entryId] = error;
}

class _DeadPublisher implements AlertPublisher {
  @override
  Future<void> publish(AlertDelivery alert) async =>
      throw Exception('broker indisponível');
}

void main() {
  final patient = AuthenticatedUser(
    id: 'patient-001',
    role: UserRole.patient,
    microAreaId: 'area-12',
    deviceId: 'device-001',
  );

  group('varredura do fonte', () {
    test('o padrão de mutação pega os escritores realistas e só eles', () {
      const mustMatch = [
        'Alert.db.updateRow(s, a)',
        'Alert.db.updateWhere(s, where: w)',
        'Alert.db.updateColumn(s, id)',
        'Alert.db.deleteRow(s, a)',
        'Alert.db.deleteWhere(s, where: w)',
        'Alert.db.insertRow(s, a)',
        'session.db.update<Alert>(rows)',
        'db.delete<Alert>(rows)',
        'db.insert<Alert>(rows)',
        'DELETE FROM alerts WHERE x',
        'delete from alerts',
        'UPDATE\n  "alerts" SET status = 1',
        'INSERT INTO alerts (id)',
      ];
      const mustNotMatch = [
        'Alert.db.findById(s, id)',
        'Alert.db.find(s)',
        'Alert.db.count(s)',
        // Fora de escopo de propósito (ver comentário do padrão).
        'AlertDeliveryRecord.db.insertRow(s, r)',
        'AlertOutboxEntry.db.updateRow(s, r)',
        'UPDATE alert_outbox SET attempts = 1',
        'DELETE FROM alert_deliveries WHERE x',
        'INSERT INTO alert_idempotency_keys (k)',
        'status: AlertStatus.pending,',
      ];
      for (final sample in mustMatch) {
        expect(_mutationPattern.hasMatch(sample), isTrue, reason: sample);
      }
      for (final sample in mustNotMatch) {
        expect(_mutationPattern.hasMatch(sample), isFalse, reason: sample);
      }
    });

    test(
      'só os escritores conhecidos mutam alerts (subconjunto da allowlist)',
      () {
        final unexpected = _grepSources(
          _mutationPattern,
        ).keys.where((file) => !_allowedWriters.containsKey(file)).toList();
        expect(
          unexpected,
          isEmpty,
          reason:
              'Escritor novo em alerts: $unexpected. Decida por escrito '
              'em _allowedWriters se ele pode alterar/apagar alerta vermelho, '
              'e como a auditoria cobre.',
        );
      },
    );

    test('admin.* não escreve em alerts (só o futuro escalateAlert pode)', () {
      final adminWriters = _grepSources(_mutationPattern).keys.where(
        (f) =>
            f == 'endpoints/admin_endpoint.dart' ||
            f.startsWith('application/admin/') ||
            f == 'infrastructure/database/orm_admin_read_store.dart' ||
            f == 'infrastructure/database/orm_data_subject_case_store.dart',
      );
      expect(adminWriters, isEmpty);
    });

    test('INV-04 (#75): todo alerta gravado é vermelho — é o que justifica '
        'alerts.riskLevel em claro (spec/lgpd_data_audit.md §2.3)', () {
      // `(?<!\w)Alert\(` pega o construtor do modelo de tabela e deixa de fora
      // AdminAlert/AlertStatusSnapshot; `copyWith` pega uma reclassificação.
      final pattern = RegExp(
        r'(?:(?<!\w)Alert\(|\.copyWith\()[^;]*?riskLevel:\s*([\w.]+)',
        dotAll: true,
      );
      final valores = <String>{};
      for (final entry in _grepSources(pattern).entries) {
        for (final hit in entry.value) {
          valores.add(pattern.firstMatch(hit)!.group(1)!);
        }
      }
      expect(valores, isNotEmpty, reason: 'a varredura precisa achar o save() do OrmAlertStore');
      expect(
        valores,
        {'RiskLevel.red'},
        reason: 'Se um alerta amarelo/verde passou a ser gravado, alerts.riskLevel '
            'deixou de ser igual à existência da linha: cifre a coluna ou '
            'revise a decisão da #75 antes de mudar este teste.',
      );
    });
  });

  group('alerts.createRedAlert repetido (idempotência)', () {
    test('a mesma chave não substitui nem apaga o alerta original', () async {
      final store = _MemoryStore();
      final outbox = _MemoryOutbox();
      final service = RedAlertService(store: store, outbox: outbox);

      final first = await service.create(
        user: patient,
        idempotencyKey: 'k1',
        locationHash: 'hash',
      );
      final second = await service.create(
        user: patient,
        idempotencyKey: 'k1',
        locationHash: 'hash',
      );

      expect(second.delivery.alertId, first.delivery.alertId);
      expect(store.saveCalls, 1, reason: 'a repetição não regrava o alerta');
      expect(store.alerts.keys, [first.delivery.alertId]);
      expect(store.status[first.delivery.alertId], 'pending');
      expect(outbox.enqueued, hasLength(1));
    });

    test(
      'mesma chave com outra localização é recusada e não toca o original',
      () async {
        final store = _MemoryStore();
        final service = RedAlertService(store: store, outbox: _MemoryOutbox());
        final first = await service.create(
          user: patient,
          idempotencyKey: 'k1',
          locationHash: 'hash',
        );

        await expectLater(
          service.create(
            user: patient,
            idempotencyKey: 'k1',
            locationHash: 'outro',
          ),
          throwsStateError,
        );
        expect(store.alerts[first.delivery.alertId]!.locationHash, 'hash');
        expect(store.status[first.delivery.alertId], 'pending');
      },
    );
  });

  group('alerts.acknowledge (serviço)', () {
    test('o ACK por MQTT entrega ao store o evento de auditoria do alerta, '
        'marcado acknowledged_mqtt (não autenticado, F3)', () async {
      final store = _MemoryStore();
      final service = RedAlertService(store: store, outbox: _MemoryOutbox());

      final ok = await service.acknowledge(
        user: const AuthenticatedUser(
          id: 'acs-1',
          role: UserRole.acs,
          microAreaId: 'area-1',
          deviceId: 'mqtt',
        ),
        alertId: 'alerta-1',
      );

      expect(ok, isTrue);
      expect(store.status['alerta-1'], 'acknowledged');
      final e = store.audits.single;
      expect(e.actionType, 'write');
      expect(e.resourceType, 'alert');
      expect(e.resourceId, 'alerta-1');
      expect(e.result, 'acknowledged_mqtt');
      expect(e.userId, 'acs-1');
    });
  });

  group('outbox esgotando tentativas', () {
    test(
      'falhas repetidas nunca removem o alerta nem o marcam entregue',
      () async {
        final store = _MemoryStore();
        final outbox = _MemoryOutbox();
        final service = RedAlertService(store: store, outbox: outbox);
        final record = await service.create(
          user: patient,
          idempotencyKey: 'k1',
          locationHash: 'hash',
        );
        final dispatcher = AlertOutboxDispatcher(
          outbox: outbox,
          publisher: _DeadPublisher(),
          clock: () => DateTime.utc(2026, 10, 11),
        );

        for (var i = 0; i < 50; i++) {
          expect(await dispatcher.drainOnce(), 0);
        }

        final id = record.delivery.alertId;
        expect(outbox.publishedIds, isEmpty, reason: 'nunca marcado entregue');
        expect(outbox.errors['entry-$id'], contains('broker indisponível'));
        expect(outbox.attempts['entry-$id'], 50);
        // A entrega segue na fila (reclamável) e o alerta segue pending.
        expect(await outbox.claimDue(), hasLength(1));
        expect(store.alerts.containsKey(id), isTrue);
        expect(store.status[id], 'pending');
      },
    );
  });
}
