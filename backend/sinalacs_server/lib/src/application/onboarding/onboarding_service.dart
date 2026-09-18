import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart'
    show AuthenticatedUser;
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Um convite de onboarding, do jeito que a store enxerga.
class StoredEnrollmentToken {
  const StoredEnrollmentToken({
    required this.tokenHash,
    required this.patientId,
    required this.microAreaId,
    required this.createdByAcsId,
    required this.expiresAt,
    this.consumedAt,
  });

  final String tokenHash;
  final String patientId;
  final String microAreaId;
  final String createdByAcsId;
  final DateTime expiresAt;
  final DateTime? consumedAt;

  StoredEnrollmentToken copyWith({DateTime? consumedAt}) => StoredEnrollmentToken(
        tokenHash: tokenHash,
        patientId: patientId,
        microAreaId: microAreaId,
        createdByAcsId: createdByAcsId,
        expiresAt: expiresAt,
        consumedAt: consumedAt ?? this.consumedAt,
      );
}

/// Uma linha de consentimento pronta para gravação — a store traduz para
/// `ConsentLog`, sem `application/` conhecer o ORM.
class ConsentLogEntry {
  const ConsentLogEntry({
    required this.userId,
    required this.purpose,
    required this.action,
    required this.version,
    required this.timestamp,
  });

  final String userId;
  final ConsentPurpose purpose;

  /// `'granted'` ou `'denied'` — ambos são gravados, nunca só o aceite.
  final String action;
  final String version;
  final DateTime timestamp;
}

/// Persistência do onboarding. Interface aqui, implementação ORM em
/// `infrastructure/`, mesmo padrão de `AlertStore`/`VisitStore`.
abstract interface class OnboardingStore {
  Future<void> saveToken(StoredEnrollmentToken token);

  /// Consome o convite atomicamente: uma única operação que só têm efeito se
  /// o token ainda não tiver sido consumido e não estiver expirado — duas
  /// chamadas concorrentes com o mesmo token nunca podem ambas "vencer"
  /// (fix round 1: `findValidToken`+`consumeToken` como dois passos
  /// separados abria essa janela de corrida).
  ///
  /// `null` se o token não existir, já expirou ou já foi consumido — o
  /// serviço não distingue os três casos na mensagem ao cliente, para não
  /// ajudar a enumerar convites válidos por tentativa e erro.
  Future<StoredEnrollmentToken?> consumeIfValid(String tokenHash, DateTime now);

  Future<String?> microAreaOfPatient(String patientId);

  Future<void> recordConsent(ConsentLogEntry entry);
}

/// Versão do texto de política vigente. Mesmo padrão que
/// `spec/lgpd_design.md` define para a política de privacidade — trocar
/// exige nova versão publicada, não incrementar este literal sem mudança de
/// texto real.
const String consentPolicyVersion = '2026.1';

const _tokenLifetime = Duration(minutes: 15);
final _tokenRandom = Random.secure();

class OnboardingService {
  OnboardingService({
    required OnboardingStore store,
    DateTime Function()? clock,
  })  : _store = store,
        _clock = clock ?? DateTime.now;

  final OnboardingStore _store;
  final DateTime Function() _clock;

  /// Gera um convite de uso único para um paciente já cadastrado na
  /// microárea do ACS. Não cria paciente novo — RF01/RF07 (identidade
  /// institucional) seguem como decisão separada.
  Future<EnrollmentTokenResult> generateToken(
    AuthenticatedUser acs, {
    required String patientId,
  }) async {
    Authorization.require(
      acs,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem gerar convites.'),
    );

    final patientArea = await _store.microAreaOfPatient(patientId);
    if (patientArea == null || patientArea != acs.microAreaId) {
      // Território é invariante (INV-01): mesma barreira de
      // `PatientDirectoryService.listForAcs`.
      throw StateError('Paciente fora da microárea do ACS.');
    }

    final token = _newToken();
    final now = _clock();
    final expiresAt = now.add(_tokenLifetime);

    await _store.saveToken(StoredEnrollmentToken(
      tokenHash: _hash(token),
      patientId: patientId,
      microAreaId: acs.microAreaId!,
      createdByAcsId: acs.id,
      expiresAt: expiresAt,
    ));

    return EnrollmentTokenResult(token: token, expiresAt: expiresAt);
  }

  /// Consome o convite, exige o consentimento obrigatório, grava as 3
  /// finalidades em `consent_logs` (aceite ou recusa) e emite a sessão do
  /// paciente. Tudo ou nada: se o consentimento obrigatório for recusado,
  /// o token permanece válido (a pessoa pode tentar de novo lendo o mesmo
  /// QR) e nenhuma linha é gravada.
  Future<AuthenticatedUser> completeEnrollment({
    required String token,
    required Map<ConsentPurpose, bool> consents,
  }) async {
    final mandatory = consents[ConsentPurpose.healthDataProcessing];
    if (mandatory != true) {
      throw EnrollmentException(
        message: 'O consentimento para processamento de dados de saúde é obrigatório.',
      );
    }

    final now = _clock();
    final tokenHash = _hash(token);
    // Consumo atômico: `consumeIfValid` é uma única operação que só afeta o
    // token se ele ainda estiver válido, então duas chamadas concorrentes
    // com o mesmo token nunca conseguem as duas passar daqui — a store
    // (implementação ORM) garante isso com um UPDATE condicional, não o
    // serviço com duas chamadas separadas.
    final stored = await _store.consumeIfValid(tokenHash, now);
    if (stored == null) {
      throw EnrollmentException(message: 'Convite inválido, expirado ou já utilizado.');
    }

    for (final purpose in ConsentPurpose.values) {
      final granted = consents[purpose] ?? false;
      await _store.recordConsent(ConsentLogEntry(
        userId: stored.patientId,
        purpose: purpose,
        action: granted ? 'granted' : 'denied',
        version: consentPolicyVersion,
        timestamp: now,
      ));
    }

    return AuthenticatedUser(
      id: stored.patientId,
      role: UserRole.patient,
      microAreaId: stored.microAreaId,
      deviceId: 'onboarding-${stored.patientId}',
    );
  }

  String _newToken() {
    final bytes = List<int>.generate(32, (_) => _tokenRandom.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _hash(String token) => sha256.convert(utf8.encode(token)).toString();
}
