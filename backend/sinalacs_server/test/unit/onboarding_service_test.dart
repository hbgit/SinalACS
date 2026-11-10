import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/device_credential_service.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

// `AuthenticatedUser`/`UserRole` vêm de `development_auth_service.dart` e
// `generated/protocol.dart` — o import acima de `development_auth_service`
// segue necessário só por `AuthenticatedUser`, não por `DevelopmentAuthService`
// (removido de `OnboardingService` no fix round 1: era uma dependência morta,
// nunca lida dentro da classe).

class FakeOnboardingStore implements OnboardingStore {
  FakeOnboardingStore();

  final Map<String, StoredEnrollmentToken> tokens = {};
  final List<ConsentLogEntry> consentLogs = [];
  String? patientMicroAreaOf(String patientId) => _patientAreas[patientId];
  final Map<String, String> _patientAreas = {};

  void seedPatient(String patientId, String microAreaId) => _patientAreas[patientId] = microAreaId;

  @override
  Future<void> saveToken(StoredEnrollmentToken token) async => tokens[token.tokenHash] = token;

  @override
  Future<StoredEnrollmentToken?> consumeIfValid(String tokenHash, DateTime now) async {
    final stored = tokens[tokenHash];
    if (stored == null) return null;
    if (stored.consumedAt != null) return null;
    if (!stored.expiresAt.isAfter(now)) return null;
    final consumed = stored.copyWith(consumedAt: now);
    tokens[tokenHash] = consumed;
    return consumed;
  }

  @override
  Future<String?> microAreaOfPatient(String patientId) async => _patientAreas[patientId];

  @override
  Future<void> recordConsent(ConsentLogEntry entry) async => consentLogs.add(entry);
}

class FakeDeviceCredentialStore implements DeviceCredentialStore {
  final Map<String, StoredPatientDeviceCredential> byDeviceId = {};
  final List<StoredPatientDeviceCredential> created = [];

  @override
  Future<StoredPatientDeviceCredential?> findByDeviceId(String deviceId) async =>
      byDeviceId[deviceId];

  @override
  Future<void> create(StoredPatientDeviceCredential credential) async {
    created.add(credential);
    byDeviceId[credential.deviceId] = credential;
  }

  @override
  Future<void> touchLastUsed(String deviceId, DateTime at) async {
    final existing = byDeviceId[deviceId];
    if (existing != null) {
      byDeviceId[deviceId] = existing.copyWith(lastUsedAt: at);
    }
  }
}

void main() {
  const acs = AuthenticatedUser(
    id: 'acs-1',
    role: UserRole.acs,
    microAreaId: 'area-1',
    deviceId: 'acs-device',
  );
  const acsOutraArea = AuthenticatedUser(
    id: 'acs-2',
    role: UserRole.acs,
    microAreaId: 'area-2',
    deviceId: 'acs-device-2',
  );
  const deviceId = '00000000-0000-4000-8000-000000000123';
  const deviceSecret = 'segredo-do-aparelho-sintetico';

  late FakeOnboardingStore store;
  late FakeDeviceCredentialStore credentials;
  late OnboardingService service;

  setUp(() {
    store = FakeOnboardingStore()..seedPatient('patient-1', 'area-1');
    credentials = FakeDeviceCredentialStore();
    service = OnboardingService(
      store: store,
      deviceCredentials: credentials,
      clock: () => DateTime.utc(2026, 9, 17, 10),
    );
  });

  Future<AuthenticatedUser> complete(
    OnboardingService target,
    String token, {
    Map<ConsentPurpose, bool>? consents,
  }) =>
      target.completeEnrollment(
        token: token,
        consents: consents ??
            const {
              ConsentPurpose.healthDataProcessing: true,
              ConsentPurpose.termsOfUse: true,
            },
        deviceId: deviceId,
        deviceSecret: deviceSecret,
      );

  group('generateToken', () {
    test('ACS gera convite para paciente da própria microárea', () async {
      final result = await service.generateToken(acs, patientId: 'patient-1');
      expect(result.token, isNotEmpty);
      expect(result.expiresAt, DateTime.utc(2026, 9, 17, 10, 15));
    });

    test('recusa gerar convite para paciente de outra microárea', () async {
      expect(
        () => service.generateToken(acsOutraArea, patientId: 'patient-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('recusa quando quem chama não é ACS', () async {
      const paciente = AuthenticatedUser(
        id: 'patient-x', role: UserRole.patient, microAreaId: 'area-1', deviceId: 'd',
      );
      expect(
        () => service.generateToken(paciente, patientId: 'patient-1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('completeEnrollment', () {
    test('consome o token, grava 4 consent_logs, cria a credencial e devolve o usuário', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');

      final user = await complete(service, generated.token, consents: const {
        ConsentPurpose.healthDataProcessing: true,
        ConsentPurpose.localReminders: false,
        ConsentPurpose.segmentedPush: true,
        ConsentPurpose.termsOfUse: true,
      });

      expect(user.id, 'patient-1');
      expect(user.role, UserRole.patient);
      expect(user.microAreaId, 'area-1');
      expect(user.deviceId, deviceId);
      expect(store.consentLogs, hasLength(4));
      // Asserção por finalidade, não por Set: um Set de 4 ações colapsa
      // 'granted'/'granted'/'denied' em {'granted', 'denied'} e não prova
      // qual finalidade recebeu qual ação — checar por chave é o que de fato
      // verifica que cada consentimento foi gravado com a ação correta.
      final byPurpose = {for (final e in store.consentLogs) e.purpose: e.action};
      expect(byPurpose[ConsentPurpose.healthDataProcessing], 'granted');
      expect(byPurpose[ConsentPurpose.localReminders], 'denied');
      expect(byPurpose[ConsentPurpose.segmentedPush], 'granted');
      expect(byPurpose[ConsentPurpose.termsOfUse], 'granted');

      // A credencial nasce com o dono, o deviceId e o HASH do segredo — nunca
      // o segredo em claro (C-05).
      final credential = credentials.created.single;
      expect(credential.patientId, 'patient-1');
      expect(credential.deviceId, deviceId);
      expect(credential.credentialHash,
          DeviceCredentialService.hashSecret(deviceSecret));
      expect(credential.credentialHash, isNot(contains(deviceSecret)));
      expect(credential.revokedAt, isNull);
    });

    test('um segundo uso do mesmo token falha, não reconsome em silêncio', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');
      await complete(service, generated.token);

      expect(
        () => complete(service, generated.token),
        throwsA(isA<EnrollmentException>()),
      );
      // Só a primeira conclusão cria credencial: o segundo uso morreu antes.
      expect(credentials.created, hasLength(1));
    });

    test('recusa concluir sem consentimento obrigatório de processamento de saúde', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');

      expect(
        () => complete(service, generated.token,
            consents: const {ConsentPurpose.healthDataProcessing: false}),
        throwsA(isA<EnrollmentException>()),
      );
      // Nenhum consent_log deve ter sido gravado para uma ativação recusada.
      expect(store.consentLogs, isEmpty);
      expect(credentials.created, isEmpty);
    });

    test('token expirado falha', () async {
      final expiredClockService = OnboardingService(
        store: store,
        deviceCredentials: credentials,
        clock: () => DateTime.utc(2026, 9, 17, 10),
      );
      final generated = await expiredClockService.generateToken(acs, patientId: 'patient-1');

      final laterService = OnboardingService(
        store: store,
        deviceCredentials: credentials,
        clock: () => DateTime.utc(2026, 9, 17, 10, 20), // 20 min depois, expira em 15
      );

      expect(
        () => complete(laterService, generated.token),
        throwsA(isA<EnrollmentException>()),
      );
    });

    test('recusa concluir sem aceitar o Termo de Uso, e o convite continua válido', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');

      await expectLater(
        () => complete(service, generated.token, consents: const {
          ConsentPurpose.healthDataProcessing: true,
          ConsentPurpose.termsOfUse: false,
        }),
        throwsA(isA<EnrollmentException>().having(
          (e) => e.message,
          'message',
          'É preciso aceitar o Termo de Uso e a Política de Privacidade.',
        )),
      );
      expect(store.consentLogs, isEmpty);
      expect(credentials.created, isEmpty);

      // Mesma regra do consentimento obrigatório de saúde: a recusa não
      // consome o convite, a pessoa pode aceitar e tentar de novo.
      final user = await complete(service, generated.token);
      expect(user.id, 'patient-1');
    });

    test('o aceite do termo leva a versão vigente dos documentos', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');
      await complete(service, generated.token);
      final terms = store.consentLogs.singleWhere((e) => e.purpose == ConsentPurpose.termsOfUse);
      expect(terms.action, 'granted');
      expect(terms.version, consentPolicyVersion);
    });
  });
}
