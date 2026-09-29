import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show consentPolicyVersion;

/// Antecedência mínima do aviso de mudança dos termos (LGPD-RF18): 15 dias
/// entre a publicação do aviso e a vigência da versão nova.
const Duration termsChangeNoticePeriod = Duration(days: 15);

/// Uma versão nova dos termos anunciada antes de valer.
///
/// O construtor recusa (em `assert`, que roda em desenvolvimento e nos testes) uma
/// vigência a menos de 15 dias da publicação: publicar o aviso tarde é um erro de
/// quem edita o repositório, não algo que o app deva corrigir depois. Não é
/// `const` porque `DateTime.difference` não é constante.
///
/// Para agendar uma mudança: acrescente uma `LegalVersion` no app, troque
/// [upcomingTermsChange] por uma agenda com a versão nova e só depois — na data de
/// vigência — mude `consentPolicyVersion` e `legalDocumentsVersion`.
class TermsChangeSchedule {
  TermsChangeSchedule({
    required this.version,
    required this.publishedAt,
    required this.effectiveFrom,
    required this.summary,
  })  : assert(version != consentPolicyVersion, 'a versão anunciada já é a vigente'),
        assert(
          effectiveFrom.difference(publishedAt) >= termsChangeNoticePeriod,
          'o aviso exige 15 dias entre a publicação e a vigência',
        );

  final String version;
  final DateTime publishedAt;
  final DateTime effectiveFrom;
  final String summary;

  /// Ativa de [publishedAt] (inclusive) até [effectiveFrom] (exclusive): a partir
  /// da vigência já não é aviso, é o convite ao aceite da versão nova.
  bool isActiveAt(DateTime now) => !now.isBefore(publishedAt) && now.isBefore(effectiveFrom);
}

/// Nada agendado hoje.
final TermsChangeSchedule? upcomingTermsChange = null;
