import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Diretório de pacientes da microárea do ACS.
///
/// Existe para a visita de rotina: o único produtor de alertas
/// (`alerts.createRedAlert`) publica só `riskLevel: 'red'` — emergência com
/// SAMU —, e sem esta lista não havia como o ACS escolher um paciente para
/// visitar fora do caminho reativo.
class PatientsEndpoint extends AuthenticatedEndpoint {
  Future<List<MicroAreaPatient>> listMicroArea(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      return await AlertRuntime.instance.patientDirectoryServiceFor(session).listForAcs(user);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Condições crônicas do próprio paciente autenticado — tela "Perfil
  /// clínico" do app. Chamado pelo app do paciente, nunca pelo do ACS (esse
  /// usa [listMicroArea]).
  Future<List<String>> myChronicConditions(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      return await AlertRuntime.instance
          .patientDirectoryServiceFor(session)
          .myChronicConditions(user);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Grava a lista de condições crônicas do próprio paciente autenticado,
  /// substituindo a anterior por inteiro (não é um merge).
  Future<void> updateChronicConditions(
    Session session, {
    required String accessToken,
    required List<String> conditions,
  }) async {
    final user = authenticate(accessToken);

    try {
      await AlertRuntime.instance
          .patientDirectoryServiceFor(session)
          .updateMyChronicConditions(user, conditions: conditions);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Painel "Meus Dados" do próprio paciente autenticado (LGPD,
  /// spec/lgpd_design.md linhas 417/581-595): confirmação de existência de
  /// tratamento e acesso aos dados pessoais.
  Future<PatientDataOverview> myData(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      final snapshot =
          await AlertRuntime.instance.patientDataOverviewServiceFor(session).myData(user);
      return PatientDataOverview(
        name: snapshot.name,
        birthDate: snapshot.birthDate,
        emergencyContact: snapshot.emergencyContact,
        isChronic: snapshot.isChronic,
        chronicConditions: snapshot.chronicConditions,
        consents: [
          for (final c in snapshot.consents)
            PatientConsentRecord(
              purpose: c.purpose,
              action: c.action,
              version: c.version,
              timestamp: c.timestamp,
            ),
        ],
        riskHistory: [
          for (final r in snapshot.riskHistory)
            PatientRiskEvent(source: r.source, riskLevel: r.riskLevel, recordedAt: r.recordedAt),
        ],
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
