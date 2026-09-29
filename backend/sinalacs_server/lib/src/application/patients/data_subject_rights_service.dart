import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show ConsentLogEntry, consentPolicyVersion;
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart'
    show ConsentRecordSnapshot, DataSubjectRequestSnapshot;
import 'package:sinalacs_server/src/application/patients/terms_change_schedule.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Persistência das operações do titular sobre os próprios dados. Interface
/// aqui, implementação ORM em `infrastructure/`, mesmo padrão de
/// `PatientDataOverviewStore`.
abstract interface class DataSubjectRightsStore {
  /// Grava uma linha nova, assinada, em `consent_logs` — nunca edita uma
  /// anterior (append-only, LGPD-RF04).
  Future<String> recordConsent(ConsentLogEntry entry);

  /// Grava o `denied` de `segmentedPush` e apaga os tokens de push do titular na
  /// MESMA transação, sob o lock por titular do registro de token: sem consentimento,
  /// sem token, e nenhum dos dois efeitos acontece sem o outro (RF14).
  Future<String> recordConsentRevokingPush(ConsentLogEntry entry);

  /// Grava `entry` **só se** a linha mais recente do propósito ainda não for um
  /// `granted` na mesma versão, de forma atômica por titular: duas chamadas
  /// simultâneas resultam em uma linha, e a segunda recebe a da primeira em
  /// `existing`.
  Future<({String? id, ConsentRecordSnapshot? existing})> recordConsentUnlessCurrent(
    ConsentLogEntry entry,
  );

  /// A linha mais recente (por `timestamp`) daquela finalidade, ou `null`.
  Future<ConsentRecordSnapshot?> latestConsent(String userId, ConsentPurpose purpose);

  /// Cria o pedido de exclusão **só se** não houver um aberto, de forma atômica:
  /// dois chamadores simultâneos resultam em uma única linha aberta, e o segundo
  /// recebe a do primeiro com `created == false`.
  Future<({DataSubjectRequestSnapshot request, bool created})> createDeletionRequestIfNoneOpen({
    required String userId,
    required DateTime createdAt,
    required DateTime dueAt,
  });

  Future<DataSubjectRequestSnapshot> createRequest({
    required String userId,
    required DataSubjectRequestType type,
    required String? details,
    required DateTime createdAt,
    required DateTime dueAt,
  });
}

/// O aviso de mudança dos termos, como o serviço o entrega ao endpoint.
class TermsChangeNoticeSnapshot {
  const TermsChangeNoticeSnapshot({
    required this.version,
    required this.effectiveFrom,
    required this.summary,
  });

  final String version;
  final DateTime effectiveFrom;
  final String summary;
}

/// A regra do aceite vigente, num lugar só: a linha mais recente é um `granted`
/// na [version] em vigor. Usada pela consulta do login e pela gravação atômica.
bool isCurrentAcceptance(ConsentRecordSnapshot? latest, {required String version}) =>
    latest != null && latest.action == 'granted' && latest.version == version;

/// Prazo de resposta a um pedido do titular (spec/lgpd_design.md, 596-597).
const Duration dataSubjectRequestDeadline = Duration(days: 15);

/// Teto do texto de um pedido de correção, contado depois do `trim()`. O app
/// usa o mesmo número no `maxLength` do campo.
const int correctionDetailsMaxLength = 500;

/// Direitos do titular exercidos pelo próprio app (LGPD-RF05 e LGPD-RF08):
/// conceder/revogar finalidades opcionais e pedir exclusão ou correção.
///
/// `userId` vem SEMPRE de `user.id` — nunca de parâmetro —, pelo mesmo motivo
/// de INV-05 em `triage.evaluate`. `requireMicroArea: false`, mesmo motivo de
/// `PatientDataOverviewService.myData`: o escopo é o titular, não o território.
class DataSubjectRightsService {
  DataSubjectRightsService({
    required DataSubjectRightsStore store,
    required AuditTrail audit,
    DateTime Function()? clock,
    TermsChangeSchedule? termsChange,
  })  : _store = store,
        _audit = audit,
        _termsChange = termsChange ?? upcomingTermsChange,
        _clock = clock ?? DateTime.now;

  final DataSubjectRightsStore _store;
  final AuditTrail _audit;
  final DateTime Function() _clock;
  final TermsChangeSchedule? _termsChange;

  /// Concede ou revoga uma finalidade opcional. `healthDataProcessing` é
  /// recusado nas duas direções: é a base legal do app inteiro — inclusive do
  /// alerta de emergência — e retirá-lo exige a exclusão dos dados em até 15
  /// dias (LGPD-RF07), que é o que [requestDeletion] registra.
  Future<ConsentRecordSnapshot> updateConsent(
    AuthenticatedUser user, {
    required ConsentPurpose purpose,
    required bool granted,
  }) async {
    _requirePatient(user);
    if (purpose == ConsentPurpose.healthDataProcessing) {
      throw DataRightsException(
        message: 'O consentimento para dados de saúde é obrigatório para usar o app. '
            'Para retirá-lo, solicite a exclusão dos seus dados.',
      );
    }
    if (purpose == ConsentPurpose.termsOfUse) {
      throw DataRightsException(
        message: 'O aceite do Termo de Uso é feito no cadastro e não é alterado aqui. '
            'Para deixar de usar o app, solicite a exclusão dos seus dados.',
      );
    }

    // Revogar avisos apaga os tokens na mesma transação do `denied` (RF14).
    return _record(
      user,
      purpose: purpose,
      action: granted ? 'granted' : 'denied',
      revokePush: purpose == ConsentPurpose.segmentedPush && !granted,
    );
  }

  /// Aceite explícito do Termo de Uso e da Política de Privacidade por quem
  /// entrou por CPF + OTP sem passar pelo onboarding (LGPD-RF18) — ou que
  /// aceitou uma versão anterior. É a única via de escrita de `termsOfUse`
  /// fora do cadastro: [updateConsent] continua recusando esse propósito, para
  /// que o termo não vire uma chave liga/desliga no painel.
  Future<ConsentRecordSnapshot> acceptTermsOfUse(AuthenticatedUser user) async {
    _requirePatient(user);
    final now = _clock().toUtc();
    final result = await _store.recordConsentUnlessCurrent(ConsentLogEntry(
      userId: user.id,
      purpose: ConsentPurpose.termsOfUse,
      action: 'granted',
      version: consentPolicyVersion,
      timestamp: now,
    ));
    // Idempotente: já aceitou a versão vigente, devolve a linha existente em
    // vez de crescer o histórico e a trilha de auditoria a cada chamada.
    if (result.existing != null) return result.existing!;
    await _auditConsent(user, result.id!);
    return ConsentRecordSnapshot(
      purpose: ConsentPurpose.termsOfUse.name,
      action: 'granted',
      version: consentPolicyVersion,
      timestamp: now,
    );
  }

  /// Aviso de mudança dos termos ativo agora, ou `null` (LGPD-RF18, 15 dias de
  /// antecedência). Sem I/O: a agenda é uma constante do repositório.
  TermsChangeNoticeSnapshot? termsChangeNotice(AuthenticatedUser user) {
    _requirePatient(user);
    final schedule = _termsChange;
    if (schedule == null || !schedule.isActiveAt(_clock().toUtc())) return null;
    return TermsChangeNoticeSnapshot(
      version: schedule.version,
      effectiveFrom: schedule.effectiveFrom,
      summary: schedule.summary,
    );
  }

  /// `true` quando a linha mais recente de `termsOfUse` é um `granted` na versão
  /// vigente (LGPD-RF18). É o que o app consulta depois do login por OTP: um
  /// `bool`, em vez do painel "Meus dados" inteiro — que também gravaria uma
  /// linha de auditoria de leitura a cada login.
  Future<bool> hasAcceptedCurrentTerms(AuthenticatedUser user) async {
    _requirePatient(user);
    return isCurrentAcceptance(
      await _store.latestConsent(user.id, ConsentPurpose.termsOfUse),
      version: consentPolicyVersion,
    );
  }

  Future<ConsentRecordSnapshot> _record(
    AuthenticatedUser user, {
    required ConsentPurpose purpose,
    required String action,
    bool revokePush = false,
  }) async {
    final now = _clock().toUtc();
    final entry = ConsentLogEntry(
      userId: user.id,
      purpose: purpose,
      action: action,
      version: consentPolicyVersion,
      timestamp: now,
    );
    final id = revokePush
        ? await _store.recordConsentRevokingPush(entry)
        : await _store.recordConsent(entry);
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'consent_log',
      resourceId: id,
      result: 'granted',
    ));

    return ConsentRecordSnapshot(
      purpose: purpose.name,
      action: action,
      version: consentPolicyVersion,
      timestamp: now,
    );
  }

  Future<void> _auditConsent(AuthenticatedUser user, String id) => _audit.recordSafely(AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: 'consent_log',
        resourceId: id,
        result: 'granted',
      ));

  /// Pede a exclusão/anonimização dos próprios dados. Idempotente enquanto
  /// houver um pedido de exclusão em aberto: pedir de novo devolve o mesmo, em
  /// vez de empilhar pedidos iguais para a equipe.
  Future<DataSubjectRequestSnapshot> requestDeletion(AuthenticatedUser user) async {
    _requirePatient(user);
    final now = _clock().toUtc();
    final result = await _store.createDeletionRequestIfNoneOpen(
      userId: user.id,
      createdAt: now,
      dueAt: now.add(dataSubjectRequestDeadline),
    );
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'data_subject_request',
      resourceId: result.request.id,
      result: result.created ? 'granted' : 'repeated',
    ));
    return result.request;
  }

  /// Pede a correção de um dado. Ao contrário da exclusão, NÃO é idempotente:
  /// cada pedido carrega um texto próprio, e devolver um pedido anterior
  /// descartaria em silêncio o texto que a pessoa acabou de escrever.
  Future<DataSubjectRequestSnapshot> requestCorrection(
    AuthenticatedUser user, {
    required String details,
  }) async {
    _requirePatient(user);
    final trimmed = details.trim();
    if (trimmed.isEmpty) {
      throw DataRightsException(message: 'Descreva o que precisa ser corrigido.');
    }
    if (trimmed.length > correctionDetailsMaxLength) {
      throw DataRightsException(
        message: 'A descrição pode ter no máximo $correctionDetailsMaxLength caracteres.',
      );
    }
    return _create(user, DataSubjectRequestType.correction, trimmed);
  }

  Future<DataSubjectRequestSnapshot> _create(
    AuthenticatedUser user,
    DataSubjectRequestType type,
    String? details,
  ) async {
    final now = _clock().toUtc();
    final request = await _store.createRequest(
      userId: user.id,
      type: type,
      details: details,
      createdAt: now,
      dueAt: now.add(dataSubjectRequestDeadline),
    );
    // Só o id do pedido: o texto da correção pode citar condição de saúde e
    // não entra na trilha (ver `AuditEvent.result`).
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'data_subject_request',
      resourceId: request.id,
      result: 'granted',
    ));
    return request;
  }

  void _requirePatient(AuthenticatedUser user) => Authorization.require(
        user,
        roles: {UserRole.patient},
        onDenied: () =>
            StateError('Somente o próprio paciente pode exercer direitos sobre os seus dados.'),
        requireMicroArea: false,
      );
}
