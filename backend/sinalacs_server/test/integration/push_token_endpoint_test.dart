import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/push_token_service.dart'
    show PushRegistration, PushRegistrationResult, maxPushTokensPerUser;
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show ConsentLogEntry, consentPolicyVersion;
import 'package:sinalacs_server/src/infrastructure/database/orm_data_subject_rights_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_push_token_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, o registro do token de push (RF14): só com o
/// consentimento `segmentedPush` vigente, sem duplicar, e apagado na revogação.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
// Ids do grupo de corrida (sem rollback): distintos dos `8000` dos outros
// arquivos de integração, que rodam em paralelo contra o mesmo banco.
const _raceUbsId = '00000000-0000-4000-9200-000000000004';
const _raceMicroAreaId = '00000000-0000-4000-9200-000000000003';
const _racePatientId = '00000000-0000-4000-9200-000000000001';
const _raceAcsId = '00000000-0000-4000-9200-000000000002';
const _chainSecret = 'test-audit-chain-secret';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: _chainSecret,
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      smsGateway: 'log',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: true,
    );

Future<void> _seed(
  Session session, {
  String ubsId = _ubsId,
  String microAreaId = _microAreaId,
  String patientId = _patientId,
  String acsId = _acsId,
  String enrollmentId = 'ACS-001',
}) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(ubsId),
      name: 'UBS Desenvolvimento',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  await User.db.insert(session, [
    User(
      id: UuidValue.fromString(patientId),
      cpfHash: 'development-patient-$patientId',
      name: 'Paciente de desenvolvimento',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(acsId),
      cpfHash: 'development-acs-$acsId',
      name: 'ACS de desenvolvimento',
      birthDate: DateTime.utc(1980, 1, 1),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  ]);
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(acsId),
      enrollmentId: enrollmentId,
      ubsId: UuidValue.fromString(ubsId),
      active: true,
    ),
  );
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: patientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
      chronicConditions: const [],
    ),
  );
}


/// Semente enxuta do grupo de corrida: só o que o registro de token e o
/// consentimento exigem por chave estrangeira (UBS, microárea e usuários). Sem
/// `Patient` nem `Acs`: esse grupo COMMITA, e outros arquivos contam linhas
/// dessas tabelas inteiras; quanto menos ele deixa visível, menos interfere.
Future<void> _seedRaceLean(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_raceUbsId),
      name: 'UBS de corrida (push)',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_raceMicroAreaId),
      name: 'Microárea de corrida (push)',
      ubsId: UuidValue.fromString(_raceUbsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  for (final (id, role) in [(_racePatientId, UserRole.patient), (_raceAcsId, UserRole.patient)]) {
    await User.db.insertRow(
      session,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'development-push-race-$id',
        name: 'Titular de corrida',
        birthDate: DateTime.utc(1985, 5, 5),
        role: role,
        microAreaId: UuidValue.fromString(_raceMicroAreaId),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

void main() {
  withServerpod('Dado o registro de token de push do paciente (RF14)', (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    Future<String> patientToken() async =>
        (await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient')).accessToken;

    Future<int> countToken(Session session, String token) =>
        PushToken.db.count(session, where: (t) => t.token.equals(token));

    Future<void> setPush(String accessToken, bool granted) => endpoints.patients.updateConsent(
          sessionBuilder,
          accessToken: accessToken,
          purpose: ConsentPurpose.segmentedPush,
          granted: granted,
        );

    test('paciente com consentimento registra e repete sem duplicar', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();
      await setPush(token, true);

      for (var i = 0; i < 2; i++) {
        await endpoints.devices.registerPushToken(
          sessionBuilder,
          accessToken: token,
          token: 'tok-1',
          platform: 'android',
        );
      }

      expect(await countToken(session, 'tok-1'), 1);
    });

    test('sem consentimento a chamada falha e nada é gravado', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await expectLater(
        endpoints.devices.registerPushToken(
          sessionBuilder,
          accessToken: token,
          token: 'tok-2',
          platform: 'android',
        ),
        throwsA(isA<DataRightsException>()),
      );
      expect(await countToken(session, 'tok-2'), 0);
    });

    test('revogar segmentedPush apaga os tokens do titular', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();
      await setPush(token, true);
      await endpoints.devices.registerPushToken(
        sessionBuilder,
        accessToken: token,
        token: 'tok-3',
        platform: 'ios',
      );

      await setPush(token, false);

      expect(await countToken(session, 'tok-3'), 0);
    });

    test('conceder de novo depois de revogar volta a permitir o registro', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();
      await setPush(token, true);
      await setPush(token, false);
      await setPush(token, true);

      await endpoints.devices.registerPushToken(
        sessionBuilder,
        accessToken: token,
        token: 'tok-4',
        platform: 'android',
      );

      expect(await countToken(session, 'tok-4'), 1);
    });

    test('token de acesso inválido é recusado', () async {
      await expectLater(
        endpoints.devices.registerPushToken(
          sessionBuilder,
          accessToken: 'lixo',
          token: 'tok',
          platform: 'android',
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });
  });

  // Grupo de corrida (sem rollback): cada chamada abre a própria transação
  // real do Postgres, que é o que registrar × revogar exige.
  withServerpod(
    'Dado registrar e revogar ao mesmo tempo, sem rollback automático (corrida)',
    (sessionBuilder, endpoints) {
      setUp(() => AlertRuntime.instance.overrideConfig(_config()));
      tearDown(() => AlertRuntime.instance.overrideConfig(null));

      Future<void> cleanup(Session session) async {
        final id = UuidValue.fromString(_racePatientId);
        final other = UuidValue.fromString(_raceAcsId);
        await PushToken.db.deleteWhere(session, where: (t) => t.userId.equals(id) | t.userId.equals(other));
        await ConsentLog.db.deleteWhere(session, where: (t) => t.userId.equals(id) | t.userId.equals(other));
        await User.db.deleteWhere(
          session,
          where: (t) => t.id.equals(id) | t.id.equals(UuidValue.fromString(_raceAcsId)),
        );
        await MicroArea.db.deleteWhere(
          session,
          where: (t) => t.id.equals(UuidValue.fromString(_raceMicroAreaId)),
        );
        await Ubs.db.deleteWhere(session, where: (t) => t.id.equals(UuidValue.fromString(_raceUbsId)));
      }

      test('depois de registrar × revogar em paralelo, denied nunca convive com token', () async {
        final session = sessionBuilder.build();
        try {
          await _seedRaceLean(session);
          final consents = OrmDataSubjectRightsStore(
            session: () => sessionBuilder.build(),
            chainSecret: _chainSecret,
            cipher: AlertRuntime.instance.healthDataCipher,
          );
          final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());
          Future<void> consent(String action) async {
            await consents.recordConsent(ConsentLogEntry(
              userId: _racePatientId,
              purpose: ConsentPurpose.segmentedPush,
              action: action,
              version: consentPolicyVersion,
              timestamp: DateTime.now().toUtc(),
            ));
          }

          for (var i = 0; i < 40; i++) {
            await consent('granted');
            await Future.wait([
              tokens.registerIfConsented(
                userId: _racePatientId,
                microAreaId: _raceMicroAreaId,
                token: 'tok-corrida',
                platform: 'android',
                now: DateTime.now().toUtc(),
              ),
              consents.recordConsentRevokingPush(ConsentLogEntry(
                userId: _racePatientId,
                purpose: ConsentPurpose.segmentedPush,
                action: 'denied',
                version: consentPolicyVersion,
                timestamp: DateTime.now().toUtc(),
              )),
            ]);
            final left = await PushToken.db.count(
              session,
              where: (t) => t.userId.equals(UuidValue.fromString(_racePatientId)),
            );
            expect(left, 0, reason: 'iteração $i: consentimento revogado, token ficou');
          }
        } finally {
          await cleanup(session);
        }
      });

      test('aparelho de outro titular sem consentimento perde o vínculo do dono antigo', () async {
        final session = sessionBuilder.build();
        try {
          await _seedRaceLean(session);
          final consents = OrmDataSubjectRightsStore(
            session: () => sessionBuilder.build(),
            chainSecret: _chainSecret,
            cipher: AlertRuntime.instance.healthDataCipher,
          );
          final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());
          await consents.recordConsent(ConsentLogEntry(
            userId: _racePatientId,
            purpose: ConsentPurpose.segmentedPush,
            action: 'granted',
            version: consentPolicyVersion,
            timestamp: DateTime.now().toUtc(),
          ));
          expect(
            (await tokens.registerIfConsented(
              userId: _racePatientId,
              microAreaId: _raceMicroAreaId,
              token: 'tok-compartilhado',
              platform: 'android',
              now: DateTime.now().toUtc(),
            ))
                .outcome,
            PushRegistration.registered,
          );

          // O ACS de teste faz o papel da segunda pessoa: nunca consentiu.
          final registered = await tokens.registerIfConsented(
            userId: _raceAcsId,
            microAreaId: _raceMicroAreaId,
            token: 'tok-compartilhado',
            platform: 'android',
            now: DateTime.now().toUtc(),
          );

          expect(registered.outcome, PushRegistration.refused);
          expect(
            await PushToken.db.count(session, where: (t) => t.token.equals('tok-compartilhado')),
            0,
            reason: 'o token continuaria ligado ao titular anterior',
          );
        } finally {
          await cleanup(session);
        }
      });

      Future<void> grant(OrmDataSubjectRightsStore consents, String userId) =>
          consents.recordConsent(ConsentLogEntry(
            userId: userId,
            purpose: ConsentPurpose.segmentedPush,
            action: 'granted',
            version: consentPolicyVersion,
            timestamp: DateTime.now().toUtc(),
          ));

      OrmDataSubjectRightsStore consentStore({bool failAfterTokenDelete = false}) =>
          OrmDataSubjectRightsStore(
            session: () => sessionBuilder.build(),
            chainSecret: _chainSecret,
            cipher: AlertRuntime.instance.healthDataCipher,
            debugFailAfterTokenDelete: failAfterTokenDelete,
          );

      test('revogação atômica: falha depois de apagar os tokens desfaz tudo', () async {
        final session = sessionBuilder.build();
        try {
          await _seedRaceLean(session);
          await grant(consentStore(), _racePatientId);
          final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());
          await tokens.registerIfConsented(
            userId: _racePatientId,
            microAreaId: _raceMicroAreaId,
            token: 'tok-atomico',
            platform: 'android',
            now: DateTime.now().toUtc(),
          );

          await expectLater(
            consentStore(failAfterTokenDelete: true).recordConsentRevokingPush(ConsentLogEntry(
              userId: _racePatientId,
              purpose: ConsentPurpose.segmentedPush,
              action: 'denied',
              version: consentPolicyVersion,
              timestamp: DateTime.now().toUtc(),
            )),
            throwsA(isA<StateError>()),
          );

          expect(
            await PushToken.db.count(session, where: (t) => t.token.equals('tok-atomico')),
            1,
            reason: 'o apagamento dos tokens tinha de reverter junto',
          );
          final denied = await ConsentLog.db.count(
            session,
            where: (t) => t.userId.equals(UuidValue.fromString(_racePatientId)) & t.action.equals('denied'),
          );
          expect(denied, 0);
        } finally {
          await cleanup(session);
        }
      });

      test('passou do teto, o token mais antigo sai e o novo entra', () async {
        final session = sessionBuilder.build();
        try {
          await _seedRaceLean(session);
          await grant(consentStore(), _racePatientId);
          final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());
          final base = DateTime.now().toUtc();
          for (var i = 0; i <= maxPushTokensPerUser; i++) {
            await tokens.registerIfConsented(
              userId: _racePatientId,
              microAreaId: _raceMicroAreaId,
              token: 'tok-teto-$i',
              platform: 'android',
              now: base.add(Duration(seconds: i)),
            );
          }

          final left = await PushToken.db.find(
            session,
            where: (t) => t.userId.equals(UuidValue.fromString(_racePatientId)),
          );
          expect(left, hasLength(maxPushTokensPerUser));
          expect(left.map((t) => t.token), isNot(contains('tok-teto-0')));
          expect(left.map((t) => t.token), contains('tok-teto-$maxPushTokensPerUser'));
        } finally {
          await cleanup(session);
        }
      });

      test('troca de dono devolve ownerChanged; repetir devolve registered', () async {
        final session = sessionBuilder.build();
        try {
          await _seedRaceLean(session);
          final consents = consentStore();
          await grant(consents, _racePatientId);
          await grant(consents, _raceAcsId);
          final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());
          Future<PushRegistrationResult> register(String userId) => tokens.registerIfConsented(
                userId: userId,
                microAreaId: _raceMicroAreaId,
                token: 'tok-dono',
                platform: 'android',
                now: DateTime.now().toUtc(),
              );

          expect((await register(_racePatientId)).outcome, PushRegistration.registered);
          final trocado = await register(_raceAcsId);
          expect(trocado.outcome, PushRegistration.ownerChanged);
          expect(trocado.previousOwnerId, _racePatientId);
          expect((await register(_raceAcsId)).outcome, PushRegistration.registered);
          expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-dono')), 1);
        } finally {
          await cleanup(session);
        }
      });

      test('a poda do teto só apaga tokens do próprio titular', () async {
        final session = sessionBuilder.build();
        try {
          await _seedRaceLean(session);
          final consents = consentStore();
          await grant(consents, _racePatientId);
          await grant(consents, _raceAcsId);
          final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());
          final base = DateTime.now().toUtc();
          // B (_raceAcsId) está no teto; o token mais antigo dele é 'tok-b-0'.
          for (var i = 0; i < maxPushTokensPerUser; i++) {
            await tokens.registerIfConsented(
              userId: _raceAcsId,
              microAreaId: _raceMicroAreaId,
              token: 'tok-b-$i',
              platform: 'android',
              now: base.add(Duration(seconds: i)),
            );
          }
          // C (_racePatientId) recebe o token mais antigo de B: troca de dono.
          await tokens.registerIfConsented(
            userId: _racePatientId,
            microAreaId: _raceMicroAreaId,
            token: 'tok-b-0',
            platform: 'android',
            now: base.add(const Duration(minutes: 1)),
          );
          // B registra o 11º token: a poda dele NÃO pode levar o 'tok-b-0' que agora é de C.
          await tokens.registerIfConsented(
            userId: _raceAcsId,
            microAreaId: _raceMicroAreaId,
            token: 'tok-b-novo',
            platform: 'android',
            now: base.add(const Duration(minutes: 2)),
          );
          final dono = await PushToken.db.findFirstRow(session, where: (t) => t.token.equals('tok-b-0'));
          expect(dono?.userId, UuidValue.fromString(_racePatientId));
        } finally {
          await cleanup(session);
        }
      });

      test('relógio que voltou: o token recém-gravado nunca é o podado', () async {
        final session = sessionBuilder.build();
        try {
          await _seedRaceLean(session);
          await grant(consentStore(), _racePatientId);
          final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());
          final futuro = DateTime.now().toUtc().add(const Duration(hours: 1));
          for (var i = 0; i < maxPushTokensPerUser; i++) {
            await tokens.registerIfConsented(
              userId: _racePatientId,
              microAreaId: _raceMicroAreaId,
              token: 'tok-f-$i',
              platform: 'android',
              now: futuro,
            );
          }
          // `now` MENOR que o de todos os outros: por updatedAt ele seria o mais antigo.
          final result = await tokens.registerIfConsented(
            userId: _racePatientId,
            microAreaId: _raceMicroAreaId,
            token: 'tok-agora',
            platform: 'android',
            now: DateTime.now().toUtc(),
          );
          expect(result.outcome, PushRegistration.registered);
          expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-agora')), 1);
          expect(
            await PushToken.db.count(
              session,
              where: (t) => t.userId.equals(UuidValue.fromString(_racePatientId)),
            ),
            maxPushTokensPerUser,
          );
        } finally {
          await cleanup(session);
        }
      });

      test('consentimentos com o MESMO timestamp: o de id maior decide', () async {
        final session = sessionBuilder.build();
        try {
          await _seedRaceLean(session);
          final at = DateTime.utc(2026, 9, 1);
          Future<void> linha(String id, String action) => ConsentLog.db.insertRow(
                session,
                ConsentLog(
                  id: UuidValue.fromString(id),
                  userId: UuidValue.fromString(_racePatientId),
                  purpose: ConsentPurpose.segmentedPush.name,
                  action: action,
                  version: '2026.1',
                  timestamp: at,
                  ipHash: 'nao-aplicavel-teste',
                  userAgent: 'nao-aplicavel-teste',
                  signature: 'assinatura-de-teste',
                ),
              );
          // O 'granted' tem o id MENOR e entra primeiro; o 'denied' tem o id maior.
          await linha('00000000-0000-4000-9200-0000000000a1', 'granted');
          await linha('00000000-0000-4000-9200-0000000000a2', 'denied');
          final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());

          final result = await tokens.registerIfConsented(
            userId: _racePatientId,
            microAreaId: _raceMicroAreaId,
            token: 'tok-empate',
            platform: 'android',
            now: DateTime.now().toUtc(),
          );

          expect(result.outcome, PushRegistration.refused);
        } finally {
          await cleanup(session);
        }
      });
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}
