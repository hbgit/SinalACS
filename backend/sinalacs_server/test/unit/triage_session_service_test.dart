import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// UUIDs sintéticos do seed de desenvolvimento.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';

const _patient = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

const _acs = AuthenticatedUser(
  id: _acsId,
  role: UserRole.acs,
  microAreaId: _microAreaId,
  deviceId: 'acs-device-001',
);

class FakeTriageSessionStore implements TriageSessionStore {
  final List<TriageSession> saved = <TriageSession>[];

  @override
  Future<TriageSession> insert(TriageSession session) async {
    final stored = session.copyWith(
      id: UuidValue.fromString('00000000-0000-4000-8000-0000000000aa'),
    );
    saved.add(stored);
    return stored;
  }
}

/// Mesmo molde de `patient_directory_service_test.dart`.
class FakeAuditTrail extends AuditTrail {
  FakeAuditTrail({this.failOnRecord = false});

  final bool failOnRecord;
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async {
    if (failOnRecord) throw StateError('trilha de auditoria fora do ar');
    events.add(event);
  }
}

void main() {
  late FakeTriageSessionStore store;
  late FakeAuditTrail audit;
  late TriageSessionService service;

  final relogio = DateTime.utc(2026, 9, 16, 12, 0, 0);

  setUp(() {
    store = FakeTriageSessionStore();
    audit = FakeAuditTrail();
    service = TriageSessionService(
      store: store,
      audit: audit,
      clock: () => relogio,
    );
  });

  Future<RiskLevel> avaliar({
    AuthenticatedUser user = _patient,
    bool chestPain = false,
    bool difficultyBreathing = false,
    bool fever = false,
    bool persistentVomiting = false,
    bool bleeding = false,
    bool severeWeakness = false,
  }) =>
      service.evaluateAndRecord(
        user: user,
        chestPain: chestPain,
        difficultyBreathing: difficultyBreathing,
        fever: fever,
        persistentVomiting: persistentVomiting,
        bleeding: bleeding,
        severeWeakness: severeWeakness,
      );

  test('o risco continua vindo do motor determinístico', () async {
    expect(await avaliar(chestPain: true), RiskLevel.red);
    expect(await avaliar(fever: true), RiskLevel.yellow);
    expect(await avaliar(), RiskLevel.green);
  });

  test('grava a sessão com o patientId do token, nunca de parâmetro', () async {
    await avaliar(chestPain: true);

    expect(store.saved, hasLength(1));
    final sessao = store.saved.single;
    expect(sessao.patientId, UuidValue.fromString(_patientId));
    expect(sessao.deviceId, 'patient-device-001');
    expect(sessao.createdAt, relogio);
  });

  test('o risco gravado é o mesmo que o motor devolveu (INV-02)', () async {
    final risco = await avaliar(bleeding: true);

    expect(risco, RiskLevel.red);
    expect(store.saved.single.resultRisk, RiskLevel.red);
    expect(store.saved.single.resultDisplay, 'Vermelho');
  });

  test('grava as seis respostas com chave estável, não com texto de UI', () async {
    await avaliar(chestPain: true, fever: true);

    final respostas = store.saved.single.answers;
    expect(respostas, hasLength(6));
    expect(
      respostas.map((r) => r.question),
      [
        'chestPain',
        'difficultyBreathing',
        'fever',
        'persistentVomiting',
        'bleeding',
        'severeWeakness',
      ],
    );
    expect(respostas.map((r) => r.answer), ['sim', 'não', 'sim', 'não', 'não', 'não']);
  });

  test('recusa quem não é paciente', () async {
    expect(
      () => avaliar(user: _acs),
      throwsA(isA<StateError>()),
    );
  });

  test('não grava nada quando o papel é recusado', () async {
    await expectLater(() => avaliar(user: _acs), throwsA(isA<StateError>()));

    expect(store.saved, isEmpty);
    expect(audit.events, isEmpty);
  });

  test('a gravação deixa linha de auditoria apontando a sessão', () async {
    await avaliar(chestPain: true);

    expect(audit.events, hasLength(1));
    final evento = audit.events.single;
    expect(evento.actionType, 'write');
    expect(evento.resourceType, 'triage_session');
    expect(evento.result, 'granted');
    expect(evento.userId, _patientId);
    // Diferente do diretório de pacientes, aqui o evento é sobre UM recurso
    // específico, então `resourceId` é preenchido — e é o id da sessão, nunca
    // o conteúdo clínico.
    expect(evento.resourceId, '00000000-0000-4000-8000-0000000000aa');
  });

  test('uma trilha de auditoria fora do ar não impede a triagem', () async {
    audit = FakeAuditTrail(failOnRecord: true);
    service = TriageSessionService(store: store, audit: audit, clock: () => relogio);

    expect(await avaliar(chestPain: true), RiskLevel.red);
    expect(store.saved, hasLength(1));
  });
}
