import 'package:sinalacs_server/src/application/admin/alert_escalation_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Regras do escalonamento de alerta vermelho (#44) sem banco: prazo, estado,
/// papel/escopo, idempotência e auditoria fail-closed. Dados sintéticos.
const _ubsA = 'ubs-a';
const _alerta = '00000000-0000-4000-8000-00000000a001';
final _agora = DateTime.utc(2026, 10, 11, 12, 0, 0);
const _limite = Duration(seconds: 300);

class _Registro {
  _Registro({
    required this.ubsId,
    required this.triggeredAt,
    this.risk = RiskLevel.red,
    this.status = AlertStatus.pending,
  });
  final String ubsId;
  final DateTime triggeredAt;
  final RiskLevel risk;
  AlertStatus status;
  DateTime? escalatedAt;
  String? escalatedBy;
  EscalationReason? reason;
  int efeitos = 0;
}

/// Cumpre a mesma regra que o SQL do store real cumprirá: vencido é
/// `now - triggeredAt > threshold`, estritamente; futuro nunca vence.
class _Store implements AlertEscalationStore {
  final registros = <String, _Registro>{};
  final ubs = <String, String?>{'coord-a': _ubsA, 'coord-b': 'ubs-b'};
  int chamadas = 0;

  @override
  Future<String?> ubsOf(String staffId) async => ubs[staffId];

  @override
  Future<EscalationAttempt> escalate(
    AdminScope scope, {
    required String alertId,
    required String actorId,
    required EscalationReason reason,
    required DateTime now,
    required Duration threshold,
    required AuditEvent Function(EscalationOutcome) auditFor,
  }) async {
    chamadas++;
    final r = registros[alertId];
    if (r == null || (scope.ubsId != null && scope.ubsId != r.ubsId)) {
      return const EscalationAttempt(EscalationOutcome.notFound);
    }
    if (r.risk != RiskLevel.red) {
      return const EscalationAttempt(EscalationOutcome.notRed);
    }
    if (r.status != AlertStatus.pending) {
      return const EscalationAttempt(EscalationOutcome.notPending);
    }
    if (r.escalatedAt != null) {
      // Auditoria antes da escrita: se falhar, nada muda (aqui, nada muda).
      await audit.record(auditFor(EscalationOutcome.alreadyEscalated));
      return EscalationAttempt(
        EscalationOutcome.alreadyEscalated,
        escalatedAt: r.escalatedAt,
      );
    }
    final decorrido = now.difference(r.triggeredAt);
    if (!(decorrido > threshold)) {
      return const EscalationAttempt(EscalationOutcome.notDue);
    }
    // Mesma "transação": a linha de auditoria primeiro; se lançar, não escreve.
    await audit.record(auditFor(EscalationOutcome.escalated));
    r
      ..escalatedAt = now
      ..escalatedBy = actorId
      ..reason = reason;
    r.efeitos++;
    return EscalationAttempt(EscalationOutcome.escalated, escalatedAt: now);
  }

  late _Audit audit;
}

class _Audit extends AuditTrail {
  final events = <AuditEvent>[];
  bool falhar = false;

  @override
  Future<void> record(AuditEvent event) async {
    if (falhar) throw StateError('auditoria indisponível');
    events.add(event);
  }
}

AuthenticatedUser _u(String id, UserRole role) => AuthenticatedUser(
  id: id,
  role: role,
  microAreaId: null,
  deviceId: 'sem-aparelho',
);

void main() {
  late _Store store;
  late _Audit audit;
  late AlertEscalationService service;
  var agora = _agora;

  void semear({
    Duration idade = const Duration(seconds: 301),
    RiskLevel risk = RiskLevel.red,
    AlertStatus status = AlertStatus.pending,
    String ubs = _ubsA,
  }) {
    store.registros[_alerta] = _Registro(
      ubsId: ubs,
      triggeredAt: _agora.subtract(idade),
      risk: risk,
      status: status,
    );
  }

  setUp(() {
    agora = _agora;
    store = _Store();
    audit = _Audit();
    store.audit = audit;
    service = AlertEscalationService(
      store: store,
      audit: audit,
      threshold: _limite,
      clock: () => agora,
    );
  });

  Future<AdminEscalationResult> escalar({
    String id = _alerta,
    String quem = 'coord-a',
    UserRole papel = UserRole.coordinator,
    EscalationReason motivo = EscalationReason.noAckTimeout,
  }) => service.escalate(_u(quem, papel), alertId: id, reason: motivo);

  test('antes do prazo: recusa, audita denied_not_due, não escreve', () async {
    semear(idade: const Duration(seconds: 299));
    await expectLater(escalar(), throwsA(isA<AdminInvalidRequestException>()));
    expect(store.registros[_alerta]!.escalatedAt, isNull);
    expect(store.registros[_alerta]!.efeitos, 0);
    expect(audit.events.single.result, 'denied_not_due');
    expect(audit.events.single.actionType, 'write');
    expect(audit.events.single.resourceType, 'admin_alert');
    expect(audit.events.single.resourceId, _alerta);
  });

  test('exatamente no prazo (300 s) ainda não vence: estritamente maior', () async {
    semear(idade: const Duration(seconds: 300));
    await expectLater(escalar(), throwsA(isA<AdminInvalidRequestException>()));
    expect(audit.events.single.result, 'denied_not_due');
  });

  test('depois do prazo: escalona e audita escalated:no_ack_timeout', () async {
    semear();
    final r = await escalar();
    expect(r.alertId, _alerta);
    expect(r.alreadyEscalated, isFalse);
    expect(r.escalatedAt, _agora);
    final reg = store.registros[_alerta]!;
    expect(reg.escalatedBy, 'coord-a');
    expect(reg.reason, EscalationReason.noAckTimeout);
    expect(reg.status, AlertStatus.pending, reason: 'D3: segue pendente');
    final e = audit.events.single;
    expect(e.userId, 'coord-a');
    expect(e.actionType, 'write');
    expect(e.resourceType, 'admin_alert');
    expect(e.resourceId, _alerta);
    expect(e.result, 'escalated:no_ack_timeout');
  });

  test('motivos em snake_case na auditoria', () async {
    semear();
    await escalar(motivo: EscalationReason.acsUnreachable);
    expect(audit.events.single.result, 'escalated:acs_unreachable');
    semear();
    audit.events.clear();
    await escalar(motivo: EscalationReason.patientRecontact);
    expect(audit.events.single.result, 'escalated:patient_recontact');
  });

  test('segunda chamada: alreadyEscalated=true, escalatedAt inalterado, 1 efeito',
      () async {
    semear();
    final primeira = await escalar();
    agora = _agora.add(const Duration(minutes: 10));
    final segunda = await escalar(motivo: EscalationReason.acsUnreachable);
    expect(segunda.alreadyEscalated, isTrue);
    expect(segunda.escalatedAt, primeira.escalatedAt);
    final reg = store.registros[_alerta]!;
    expect(reg.efeitos, 1);
    expect(reg.reason, EscalationReason.noAckTimeout);
    expect(audit.events.last.result, 'already_escalated:acs_unreachable');
  });

  test('alerta já reconhecido: recusa, status inalterado', () async {
    semear(status: AlertStatus.acknowledged);
    await expectLater(
      escalar(),
      throwsA(
        isA<AdminInvalidRequestException>().having(
          (e) => e.message,
          'message',
          'Alerta já confirmado.',
        ),
      ),
    );
    expect(store.registros[_alerta]!.status, AlertStatus.acknowledged);
    expect(store.registros[_alerta]!.escalatedAt, isNull);
    expect(audit.events.single.result, 'denied_not_pending');
  });

  test('alerta amarelo/verde: recusa', () async {
    for (final risk in [RiskLevel.yellow, RiskLevel.green]) {
      audit.events.clear();
      semear(risk: risk);
      await expectLater(escalar(), throwsA(isA<AdminInvalidRequestException>()));
      expect(store.registros[_alerta]!.escalatedAt, isNull);
      expect(audit.events.single.result, 'denied_not_red');
    }
  });

  test('triggeredAt no futuro nunca é vencido', () async {
    semear(idade: const Duration(hours: -2));
    await expectLater(escalar(), throwsA(isA<AdminInvalidRequestException>()));
    expect(store.registros[_alerta]!.escalatedAt, isNull);
    expect(audit.events.single.result, 'denied_not_due');
  });

  test('acs e patient: AlertPermissionException + denied auditado', () async {
    semear();
    for (final papel in [UserRole.acs, UserRole.patient]) {
      audit.events.clear();
      await expectLater(
        escalar(quem: 'u-1', papel: papel),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(audit.events.single.result, 'denied');
      expect(audit.events.single.actionType, 'write');
    }
    expect(store.chamadas, 0);
    expect(store.registros[_alerta]!.escalatedAt, isNull);
  });

  test('coordenador de outra UBS: mesma mensagem de não encontrado', () async {
    semear();
    String? msg(Object? e) => (e as AdminInvalidRequestException).message;
    String? outraUbs;
    String? inexistente;
    try {
      await escalar(quem: 'coord-b');
    } catch (e) {
      outraUbs = msg(e);
    }
    try {
      await escalar(id: '00000000-0000-4000-8000-00000000ffff');
    } catch (e) {
      inexistente = msg(e);
    }
    expect(outraUbs, 'Alerta não encontrado.');
    expect(inexistente, outraUbs);
    expect(audit.events.map((e) => e.result), [
      'denied_not_found',
      'denied_not_found',
    ]);
    expect(store.registros[_alerta]!.escalatedAt, isNull);
  });

  test('administrador escala em qualquer UBS', () async {
    semear(ubs: 'ubs-z');
    final r = await escalar(quem: 'adm-1', papel: UserRole.admin);
    expect(r.alreadyEscalated, isFalse);
  });

  test('id que não é UUID: recusa sem tocar o store', () async {
    await expectLater(
      escalar(id: "x'; DROP TABLE alerts;--"),
      throwsA(isA<AdminInvalidRequestException>()),
    );
    expect(store.chamadas, 0);
    expect(audit.events.single.result, 'denied_invalid_id');
    expect(audit.events.single.resourceId, isNull);
  });

  test('se a auditoria falha, nada é escrito', () async {
    semear();
    audit.falhar = true;
    await expectLater(escalar(), throwsA(isA<StateError>()));
    expect(store.registros[_alerta]!.escalatedAt, isNull);
    expect(store.registros[_alerta]!.efeitos, 0);
  });

  test('se a auditoria da recusa falha, a exceção da trilha sobe', () async {
    semear(idade: const Duration(seconds: 10));
    audit.falhar = true;
    await expectLater(escalar(), throwsA(isA<StateError>()));
  });
}
