import 'dart:io';

import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_engine.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Papel do usuário autenticado não permite registrar a própria triagem.
///
/// Tipo dedicado, e não [StateError]: o bloco `try` de [TriageEndpoint] agora
/// também envolve a gravação no Postgres (FIX 2), então um `StateError`
/// vindo do driver não pode mais ser confundido com uma recusa de permissão
/// — o paciente veria "sem permissão" para uma falha de banco.
class TriageAuthorizationException implements Exception {
  const TriageAuthorizationException(this.message);

  final String message;

  @override
  String toString() => message;
}

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

  /// Classifica e registra a triagem do próprio paciente autenticado.
  ///
  /// O `patientId` vem SEMPRE de [AuthenticatedUser.id], nunca de um parâmetro:
  /// aceitar um id do cliente permitiria gravar triagem em nome de outra
  /// pessoa (INV-05).
  ///
  /// Uma falha ao gravar a sessão NÃO nega a classificação: o motor já
  /// calculou o risco antes da gravação, e um Postgres fora do ar não pode
  /// custar a um paciente com dor no peito ouvir "tente de novo" em vez de
  /// "Vermelho". O preço desse trade-off deliberado é que o prontuário desta
  /// triagem pode ficar sem registro — a perda é reportada no stderr do
  /// processo, nomeando só o id do paciente, nunca os sintomas.
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
      throw const TriageAuthorizationException(
        'Somente o paciente pode registrar a própria triagem.',
      );
    }

    final risk = _engine.evaluate(
      chestPain: chestPain,
      difficultyBreathing: difficultyBreathing,
      fever: fever,
      persistentVomiting: persistentVomiting,
      bleeding: bleeding,
      severeWeakness: severeWeakness,
    );

    // Pergunta e resposta ligadas neste único lugar — nunca por índice em
    // listas paralelas. Duas listas zipadas por posição podiam ser
    // reordenadas independentemente uma da outra e gravar a resposta certa
    // sob o nome errado, sem exceção nenhuma e sem teste que percebesse.
    //
    // As chaves são deliberadamente os nomes dos campos do motor, e **não** o
    // texto exibido na tela: a cópia de UI muda com redesign, e um
    // prontuário cujas perguntas mudam de identidade a cada release não é
    // auditável.
    final respostas = <String, bool>{
      'chestPain': chestPain,
      'difficultyBreathing': difficultyBreathing,
      'fever': fever,
      'persistentVomiting': persistentVomiting,
      'bleeding': bleeding,
      'severeWeakness': severeWeakness,
    };

    UuidValue? sessionId;
    try {
      final gravada = await _store.insert(TriageSession(
        patientId: UuidValue.fromString(user.id),
        answers: [
          for (final resposta in respostas.entries)
            TriageAnswer(
              question: resposta.key,
              answer: resposta.value ? 'sim' : 'não',
            ),
        ],
        resultRisk: risk,
        resultDisplay: _displayFor(risk),
        createdAt: _clock(),
        deviceId: user.deviceId,
      ));
      sessionId = gravada.id;
    } catch (error) {
      stderr.writeln(
        'Falha ao gravar a sessão de triagem do paciente ${user.id}: $error.',
      );
    }

    // Best-effort, igual ao diretório de pacientes: uma trilha fora do ar não
    // pode impedir uma triagem clínica de acontecer. Quando a gravação acima
    // falhou não existe `sessionId`, então o evento ainda é registrado, só
    // que sem `resourceId`.
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'triage_session',
      resourceId: sessionId?.uuid,
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
