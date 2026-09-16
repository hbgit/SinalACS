import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_engine.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Persistência da sessão de triagem.
///
/// Mesmo padrão de `AlertStore`/`VisitStore`/`PatientDirectoryStore`: interface
/// aqui, implementação ORM em `infrastructure/`, para o serviço ser testável
/// sem Postgres.
abstract interface class TriageSessionStore {
  /// Devolve a sessão gravada, já com o `id` atribuído pelo banco.
  Future<TriageSession> insert(TriageSession session);
}

/// Registra a triagem estruturada do paciente.
///
/// Existe porque `TriageEndpoint` era uma função pura: calculava o risco e o
/// descartava. `triage_sessions` estava modelada e migrada desde a base, sem
/// nenhum escritor — não havia histórico clínico, nem vínculo entre a triagem
/// e o paciente, e a auditoria da LGPD (RF17) não cobria a triagem.
///
/// O cálculo continua no [TriageEngine], inalterado: este serviço não decide
/// risco, só persiste o que o motor determinou (INV-02).
class TriageSessionService {
  TriageSessionService({
    required TriageSessionStore store,
    required AuditTrail audit,
    TriageEngine engine = const TriageEngine(),
    DateTime Function()? clock,
  })  : _store = store,
        _audit = audit,
        _engine = engine,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final TriageSessionStore _store;
  final AuditTrail _audit;
  final TriageEngine _engine;
  final DateTime Function() _clock;

  /// Chaves estáveis das perguntas.
  ///
  /// Deliberadamente os nomes dos campos do motor, e **não** o texto exibido na
  /// tela: a cópia de UI muda com redesign, e um prontuário cujas perguntas
  /// mudam de identidade a cada release não é auditável.
  static const _questionKeys = <String>[
    'chestPain',
    'difficultyBreathing',
    'fever',
    'persistentVomiting',
    'bleeding',
    'severeWeakness',
  ];

  /// Classifica e registra a triagem do próprio paciente autenticado.
  ///
  /// O `patientId` vem SEMPRE de [AuthenticatedUser.id], nunca de um parâmetro:
  /// aceitar um id do cliente permitiria gravar triagem em nome de outra
  /// pessoa (INV-05).
  Future<RiskLevel> evaluateAndRecord({
    required AuthenticatedUser user,
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async {
    if (user.role != UserRole.patient) {
      throw StateError('Somente o paciente pode registrar a própria triagem.');
    }

    final risk = _engine.evaluate(
      chestPain: chestPain,
      difficultyBreathing: difficultyBreathing,
      fever: fever,
      persistentVomiting: persistentVomiting,
      bleeding: bleeding,
      severeWeakness: severeWeakness,
    );

    final respostas = <bool>[
      chestPain,
      difficultyBreathing,
      fever,
      persistentVomiting,
      bleeding,
      severeWeakness,
    ];

    final gravada = await _store.insert(TriageSession(
      patientId: UuidValue.fromString(user.id),
      answers: [
        for (var i = 0; i < _questionKeys.length; i++)
          TriageAnswer(
            question: _questionKeys[i],
            answer: respostas[i] ? 'sim' : 'não',
          ),
      ],
      resultRisk: risk,
      resultDisplay: _displayFor(risk),
      createdAt: _clock(),
      deviceId: user.deviceId,
    ));

    // Best-effort, igual ao diretório de pacientes: uma trilha fora do ar não
    // pode impedir uma triagem clínica de acontecer.
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'triage_session',
      resourceId: gravada.id?.uuid,
      result: 'granted',
    ));

    return risk;
  }

  static String _displayFor(RiskLevel risk) => switch (risk) {
        RiskLevel.red => 'Vermelho',
        RiskLevel.yellow => 'Amarelo',
        RiskLevel.green => 'Verde',
      };
}
