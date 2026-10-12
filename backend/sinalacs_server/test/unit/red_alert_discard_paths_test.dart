import 'dart:io';

import 'package:sinalacs_server/src/application/alerts/alert_outbox_dispatcher.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
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
/// Itens marcados `skip: 'Task 4'` FALHAM hoje por um buraco real no código de
/// produção; a Task 4 corrige e tira o skip.

// ---------------------------------------------------------------------------
// Varredura do fonte: quem pode escrever em `alerts`.
// ---------------------------------------------------------------------------

/// Escritas em `alerts`: SQL cru, chamadas de escrita do ORM e atribuição de
/// `status: AlertStatus.…` (inclusive DTOs de leitura/resposta, que entram
/// aqui de propósito para cada uso ter uma justificativa por escrito).
final _writePattern = RegExp(
  r'UPDATE\s+"?alerts"?\b|DELETE\s+FROM\s+"?alerts"?\b|INSERT\s+INTO\s+"?alerts"?\b'
  r'|Alert\.db\.(updateRow|deleteRow|delete|update|insertRow|insert)\b'
  r'|status:\s*AlertStatus\.',
);

/// Subconjunto estrito: operações que de fato alteram a tabela `alerts`.
final _mutationPattern = RegExp(
  r'UPDATE\s+"?alerts"?\b|DELETE\s+FROM\s+"?alerts"?\b|INSERT\s+INTO\s+"?alerts"?\b'
  r'|Alert\.db\.(updateRow|deleteRow|delete|update|insertRow|insert)\b',
);

/// Arquivos autorizados a casar com [_writePattern], cada um com o motivo.
/// `escalate` (Task 6) entra como `orm_alert_escalation_store.dart`; enquanto
/// o arquivo não existe, a varredura exige só que todo escritor ENCONTRADO
/// esteja aqui (subconjunto), não que todos existam.
const _allowedWriters = <String, String>{
  'infrastructure/database/orm_alert_store.dart':
      'save() insere o alerta como pending; acknowledge() leva a acknowledged '
      '(única transição de status hoje)',
  'infrastructure/database/orm_retention_store.dart':
      'expurgo LGPD: DELETE FROM alerts por triggeredAt — hoje SEM guarda de '
      'status/risco (buraco, corrigido na Task 4)',
  'infrastructure/database/orm_alert_escalation_store.dart':
      'Task 6: UPDATE só de escalatedAt/colunas de escalonamento, nunca status',
  'endpoints/alerts_endpoint.dart':
      'só monta o DTO de resposta (RedAlertResult/AlertAckResult.status); '
      'não escreve na tabela',
  'infrastructure/database/orm_admin_read_store.dart':
      'só LÊ a linha para o DTO do backoffice (AlertStatus.fromJson); '
      'não escreve na tabela',
};

Map<String, List<String>> _grepSources(RegExp pattern) {
  final root = Directory('lib/src');
  final found = <String, List<String>>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relative = entity.path.substring('lib/src/'.length);
    if (relative.startsWith('generated/')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimLeft();
      if (line.startsWith('//') || line.startsWith('///')) continue;
      if (pattern.hasMatch(lines[i])) {
        found
            .putIfAbsent(relative, () => [])
            .add('${i + 1}: ${lines[i].trim()}');
      }
    }
    // SQL partido em várias linhas ("UPDATE\n alerts").
    final whole = entity.readAsStringSync();
    if (!found.containsKey(relative) && pattern.hasMatch(whole)) {
      found[relative] = ['(multilinha)'];
    }
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
  }) async {
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
  void publish(AlertDelivery alert) => throw Exception('broker indisponível');
}

void main() {
  final patient = AuthenticatedUser(
    id: 'patient-001',
    role: UserRole.patient,
    microAreaId: 'area-12',
    deviceId: 'device-001',
  );

  group('varredura do fonte', () {
    test(
      'só os escritores conhecidos tocam alerts (subconjunto da allowlist)',
      () {
        final writers = _grepSources(_writePattern);
        final unexpected = writers.keys
            .where((file) => !_allowedWriters.containsKey(file))
            .toList();
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
      final writers = _grepSources(_mutationPattern);
      final adminWriters = writers.keys.where(
        (f) =>
            f == 'endpoints/admin_endpoint.dart' ||
            f.startsWith('application/admin/') ||
            f == 'infrastructure/database/orm_admin_read_store.dart' ||
            f == 'infrastructure/database/orm_data_subject_case_store.dart',
      );
      expect(adminWriters, isEmpty);
    });

    test(
      'a allowlist não aceita escritor de mutação fora dos três esperados',
      () {
        final writers = _grepSources(_mutationPattern).keys.toSet();
        expect(
          writers.difference({
            'infrastructure/database/orm_alert_store.dart',
            'infrastructure/database/orm_retention_store.dart',
            'infrastructure/database/orm_alert_escalation_store.dart',
          }),
          isEmpty,
        );
      },
    );
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
