import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

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
  Future<StoredEnrollmentToken?> findValidToken(String tokenHash, DateTime now) async {
    final stored = tokens[tokenHash];
    if (stored == null) return null;
    if (stored.consumedAt != null) return null;
    if (!stored.expiresAt.isAfter(now)) return null;
    return stored;
  }

  @override
  Future<void> consumeToken(String tokenHash, DateTime consumedAt) async {
    final stored = tokens[tokenHash]!;
    tokens[tokenHash] = stored.copyWith(consumedAt: consumedAt);
  }

  @override
  Future<String?> microAreaOfPatient(String patientId) async => _patientAreas[patientId];

  @override
  Future<void> recordConsent(ConsentLogEntry entry) async => consentLogs.add(entry);
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

  late FakeOnboardingStore store;
  late OnboardingService service;

  setUp(() {
    store = FakeOnboardingStore()..seedPatient('patient-1', 'area-1');
    service = OnboardingService(
      store: store,
      auth: DevelopmentAuthService(secret: 'test-secret'),
      clock: () => DateTime.utc(2026, 9, 17, 10),
    );
  });

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
    test('consome o token, grava 3 consent_logs e emite sessão', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');

      final user = await service.completeEnrollment(
        token: generated.token,
        consents: const {
          ConsentPurpose.healthDataProcessing: true,
          ConsentPurpose.localReminders: false,
          ConsentPurpose.segmentedPush: true,
        },
      );

      expect(user.id, 'patient-1');
      expect(user.role, UserRole.patient);
      expect(user.microAreaId, 'area-1');
      expect(store.consentLogs, hasLength(3));
      // Asserção por finalidade, não por Set: um Set de 3 ações colapsa
      // 'granted'/'granted'/'denied' em {'granted', 'denied'} e não prova
      // qual finalidade recebeu qual ação — checar por chave é o que de fato
      // verifica que cada consentimento foi gravado com a ação correta.
      final byPurpose = {for (final e in store.consentLogs) e.purpose: e.action};
      expect(byPurpose[ConsentPurpose.healthDataProcessing], 'granted');
      expect(byPurpose[ConsentPurpose.localReminders], 'denied');
      expect(byPurpose[ConsentPurpose.segmentedPush], 'granted');
    });

    test('um segundo uso do mesmo token falha, não reconsome em silêncio', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');
      await service.completeEnrollment(
        token: generated.token,
        consents: const {ConsentPurpose.healthDataProcessing: true},
      );

      expect(
        () => service.completeEnrollment(
          token: generated.token,
          consents: const {ConsentPurpose.healthDataProcessing: true},
        ),
        throwsA(isA<EnrollmentException>()),
      );
    });

    test('recusa concluir sem consentimento obrigatório de processamento de saúde', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');

      expect(
        () => service.completeEnrollment(
          token: generated.token,
          consents: const {ConsentPurpose.healthDataProcessing: false},
        ),
        throwsA(isA<EnrollmentException>()),
      );
      // Nenhum consent_log deve ter sido gravado para uma ativação recusada.
      expect(store.consentLogs, isEmpty);
    });

    test('token expirado falha', () async {
      final expiredClockService = OnboardingService(
        store: store,
        auth: DevelopmentAuthService(secret: 'test-secret'),
        clock: () => DateTime.utc(2026, 9, 17, 10),
      );
      final generated = await expiredClockService.generateToken(acs, patientId: 'patient-1');

      final laterService = OnboardingService(
        store: store,
        auth: DevelopmentAuthService(secret: 'test-secret'),
        clock: () => DateTime.utc(2026, 9, 17, 10, 20), // 20 min depois, expira em 15
      );

      expect(
        () => laterService.completeEnrollment(
          token: generated.token,
          consents: const {ConsentPurpose.healthDataProcessing: true},
        ),
        throwsA(isA<EnrollmentException>()),
      );
    });
  });
}
