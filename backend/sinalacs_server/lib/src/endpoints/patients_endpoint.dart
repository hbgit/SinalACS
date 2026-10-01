import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Diretório de pacientes da microárea do ACS.
///
/// Existe para a visita de rotina: o único produtor de alertas
/// (`alerts.createRedAlert`) publica só `riskLevel: 'red'` — emergência com
/// SAMU —, e sem esta lista não havia como o ACS escolher um paciente para
/// visitar fora do caminho reativo.
///
/// Serve também o próprio paciente: "Perfil clínico", "Meus Dados" e os
/// direitos do titular (LGPD-RF05/RF08) — sempre escopados pelo id do token.
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
        requests: [for (final r in snapshot.requests) _requestRecord(r)],
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Concede ou revoga, pelo próprio titular, uma finalidade opcional de
  /// consentimento (LGPD-RF05): uma linha nova em `consent_logs`, nunca a
  /// edição da anterior. `healthDataProcessing` volta como
  /// [DataRightsException] — retirá-lo passa pelo pedido de exclusão.
  Future<PatientConsentRecord> updateConsent(
    Session session, {
    required String accessToken,
    required ConsentPurpose purpose,
    required bool granted,
  }) async {
    final user = authenticate(accessToken);

    try {
      final record = await AlertRuntime.instance
          .dataSubjectRightsServiceFor(session)
          .updateConsent(user, purpose: purpose, granted: granted);
      return PatientConsentRecord(
        purpose: record.purpose,
        action: record.action,
        version: record.version,
        timestamp: record.timestamp,
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Aceite do Termo de Uso e da Política de Privacidade vigentes (LGPD-RF18)
  /// por quem entrou por OTP sem passar pelo onboarding, ou aceitou uma versão
  /// anterior. Só paciente; grava uma linha assinada em `consent_logs` só se a
  /// versão vigente ainda não foi aceita — repetir devolve a existente.
  Future<PatientConsentRecord> acceptTermsOfUse(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      final record = await AlertRuntime.instance
          .dataSubjectRightsServiceFor(session)
          .acceptTermsOfUse(user);
      return PatientConsentRecord(
        purpose: record.purpose,
        action: record.action,
        version: record.version,
        timestamp: record.timestamp,
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Se o paciente já aceitou o Termo de Uso e a Política de Privacidade da
  /// versão vigente (LGPD-RF18). O app consulta depois do login por OTP para
  /// decidir se mostra o convite ao aceite — um `bool`, sem ler o painel
  /// "Meus Dados". Não grava auditoria: devolve ao próprio titular um fato
  /// sobre o consentimento dele.
  Future<bool> hasAcceptedCurrentTerms(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      return await AlertRuntime.instance
          .dataSubjectRightsServiceFor(session)
          .hasAcceptedCurrentTerms(user);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Se a decisão mais recente do titular para [purpose] é `granted` — um
  /// `bool`, sem ler o painel "Meus Dados" e sem linha de auditoria de leitura.
  /// O app pergunta isto a cada login antes de pedir o token ao provedor de
  /// push (RF14).
  Future<bool> hasGrantedConsent(
    Session session, {
    required String accessToken,
    required ConsentPurpose purpose,
  }) async {
    final user = authenticate(accessToken);

    try {
      return await AlertRuntime.instance
          .dataSubjectRightsServiceFor(session)
          .hasGrantedConsent(user, purpose);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Aviso de mudança dos termos ativo agora (LGPD-RF18, 15 dias de antecedência),
  /// ou `null`. Só paciente. Sem leitura de banco e sem linha de auditoria: a
  /// agenda é uma constante do repositório e nada do titular é lido nem gravado.
  Future<TermsChangeNotice?> termsChangeNotice(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      final notice =
          AlertRuntime.instance.dataSubjectRightsServiceFor(session).termsChangeNotice(user);
      return notice == null
          ? null
          : TermsChangeNotice(
              version: notice.version,
              effectiveFrom: notice.effectiveFrom,
              summary: notice.summary,
            );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Pedido de exclusão/anonimização dos próprios dados (LGPD-RF08).
  /// Idempotente enquanto houver um pedido de exclusão em aberto.
  Future<PatientDataSubjectRequestRecord> requestDataDeletion(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      return _requestRecord(
        await AlertRuntime.instance.dataSubjectRightsServiceFor(session).requestDeletion(user),
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Pedido de correção de um dado (LGPD-RF08). [details] é texto livre do
  /// titular, gravado cifrado; vazio ou acima de 500 caracteres volta como
  /// [DataRightsException].
  Future<PatientDataSubjectRequestRecord> requestDataCorrection(
    Session session, {
    required String accessToken,
    required String details,
  }) async {
    final user = authenticate(accessToken);

    try {
      return _requestRecord(
        await AlertRuntime.instance
            .dataSubjectRightsServiceFor(session)
            .requestCorrection(user, details: details),
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  static PatientDataSubjectRequestRecord _requestRecord(DataSubjectRequestSnapshot r) =>
      PatientDataSubjectRequestRecord(
        type: r.type,
        status: r.status,
        details: r.details,
        createdAt: r.createdAt,
        dueAt: r.dueAt,
      );
}
