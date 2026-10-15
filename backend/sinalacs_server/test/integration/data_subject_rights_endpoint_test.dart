import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart' show ConsentLogEntry, consentPolicyVersion;
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart'
    show ConsentRecordSnapshot, DataSubjectRequestSnapshot;
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_data_subject_rights_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, os direitos do titular exercidos pelo app
/// (LGPD-RF05/RF08): a linha assinada em `consent_logs`, o pedido cifrado em
/// `data_subject_requests` e o reflexo de ambos em `patients.myData`.
/// `data_subject_rights_service_test.dart` prova as regras com fakes.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
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

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Desenvolvimento',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  await User.db.insert(session, [
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'development-patient',
      name: 'Paciente de desenvolvimento',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-acs',
      name: 'ACS de desenvolvimento',
      birthDate: DateTime.utc(1980, 1, 1),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  ]);
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'ACS-001',
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
      chronicConditions: const [],
    ),
  );
}

// Grupo de corrida (sem rollback): ids próprios, distintos dos `8000` do grupo
// principal e dos fixos de `auth.developmentLogin`, para poder ser limpo à mão.
const _raceUbsId = '00000000-0000-4000-9100-000000000001';
const _raceMicroAreaId = '00000000-0000-4000-9100-000000000002';
const _racePatientId = '00000000-0000-4000-9100-000000000003';

Future<void> _seedRace(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_raceUbsId),
      name: 'UBS Desenvolvimento (corrida exclusão)',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_raceMicroAreaId),
      name: 'Microárea de corrida',
      ubsId: UuidValue.fromString(_raceUbsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_racePatientId),
      cpfHash: 'development-patient-corrida-exclusao',
      name: 'Paciente de corrida',
      birthDate: DateTime.utc(1975, 3, 10),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_raceMicroAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  );
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: _racePatientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
    ),
  );
}

/// Desfaz à mão o que [_seedRace] e o teste gravam: esse grupo roda com
/// `RollbackDatabase.disabled`. Filhos antes dos pais.
Future<void> _cleanupRace(Session session) async {
  await ConsentLog.db.deleteWhere(
    session,
    where: (t) => t.userId.equals(UuidValue.fromString(_racePatientId)),
  );
  await DataSubjectRequest.db.deleteWhere(
    session,
    where: (t) => t.userId.equals(UuidValue.fromString(_racePatientId)),
  );
  await Patient.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_racePatientId)),
  );
  await User.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_racePatientId)),
  );
  await MicroArea.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_raceMicroAreaId)),
  );
  await Ubs.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_raceUbsId)),
  );
}

void main() {
  withServerpod('Dados os direitos do titular exercidos pelo app', (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    Future<String> patientToken() async =>
        (await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient')).accessToken;

    test('updateConsent grava linha assinada em consent_logs e myData passa a mostrá-la', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      final record = await endpoints.patients.updateConsent(
        sessionBuilder,
        accessToken: token,
        purpose: ConsentPurpose.localReminders,
        granted: false,
      );
      expect(record.action, 'denied');

      final row = (await ConsentLog.db.find(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_patientId)),
      ))
          .single;
      expect(row.purpose, 'localReminders');
      expect(row.action, 'denied');
      expect(row.ipHash, 'nao-aplicavel-painel-titular');
      expect(
        row.signature,
        ConsentSignature(secret: _chainSecret).compute(
          userId: _patientId,
          purpose: row.purpose,
          action: row.action,
          version: row.version,
          timestamp: row.timestamp,
        ),
      );

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.consents.last.purpose, 'localReminders');
      expect(overview.consents.last.action, 'denied');
    });

    test('acceptTermsOfUse grava termsOfUse assinado e myData passa a mostrá-lo', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      final record = await endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: token);
      expect(record.purpose, 'termsOfUse');
      expect(record.action, 'granted');

      final row = (await ConsentLog.db.find(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_patientId)),
      ))
          .single;
      expect(row.purpose, 'termsOfUse');
      expect(row.version, consentPolicyVersion);
      expect(
        row.signature,
        ConsentSignature(secret: _chainSecret).compute(
          userId: _patientId,
          purpose: row.purpose,
          action: row.action,
          version: row.version,
          timestamp: row.timestamp,
        ),
      );

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.consents.last.purpose, 'termsOfUse');
    });

    test('acceptTermsOfUse recusa token de ACS sem gravar nada', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final acsToken =
          (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

      await expectLater(
        endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: acsToken),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(await ConsentLog.db.count(session, where: (t) => t.userId.equals(UuidValue.fromString(_patientId))), 0);
    });

    test('hasAcceptedCurrentTerms: falso antes, verdadeiro depois de aceitar', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      expect(await endpoints.patients.hasAcceptedCurrentTerms(sessionBuilder, accessToken: token), isFalse);
      await endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: token);
      expect(await endpoints.patients.hasAcceptedCurrentTerms(sessionBuilder, accessToken: token), isTrue);
    });

    test('termsChangeNotice sem agenda devolve null e não grava auditoria', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();
      final before = await AuditLog.db.count(session);

      expect(await endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: token), isNull);
      expect(await AuditLog.db.count(session), before);
    });

    test('termsChangeNotice recusa token de ACS e token inválido', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final acsToken =
          (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;
      await expectLater(
        endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: acsToken),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: 'lixo'),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('hasAcceptedCurrentTerms recusa token de ACS', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final acsToken =
          (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

      await expectLater(
        endpoints.patients.hasAcceptedCurrentTerms(sessionBuilder, accessToken: acsToken),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('hasGrantedConsent: acompanha a decisão mais recente e não grava auditoria', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();
      Future<bool> consulta() => endpoints.patients
          .hasGrantedConsent(sessionBuilder, accessToken: token, purpose: ConsentPurpose.segmentedPush);

      expect(await consulta(), isFalse);
      await endpoints.patients
          .updateConsent(sessionBuilder, accessToken: token, purpose: ConsentPurpose.segmentedPush, granted: true);
      final auditoriaAntes = await AuditLog.db.count(session);
      expect(await consulta(), isTrue);
      expect(await AuditLog.db.count(session), auditoriaAntes);
      await endpoints.patients
          .updateConsent(sessionBuilder, accessToken: token, purpose: ConsentPurpose.segmentedPush, granted: false);
      expect(await consulta(), isFalse);
    });

    test('hasGrantedConsent recusa token de ACS', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final acsToken =
          (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

      await expectLater(
        endpoints.patients.hasGrantedConsent(
            sessionBuilder, accessToken: acsToken, purpose: ConsentPurpose.segmentedPush),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('acceptTermsOfUse duas vezes grava uma linha só', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: token);
      await endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: token);

      expect(await ConsentLog.db.count(session, where: (t) => t.userId.equals(UuidValue.fromString(_patientId))), 1);
    });

    test('updateConsent recusa a finalidade obrigatória sem gravar nada', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await expectLater(
        endpoints.patients.updateConsent(
          sessionBuilder,
          accessToken: token,
          purpose: ConsentPurpose.healthDataProcessing,
          granted: false,
        ),
        throwsA(isA<DataRightsException>()),
      );
      expect(await ConsentLog.db.count(session, where: (t) => t.userId.equals(UuidValue.fromString(_patientId))), 0);
    });

    test('requestDataDeletion repetido deixa um pedido só, com prazo de 15 dias, visível em myData', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      final first = await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);
      final second = await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);

      expect(second.createdAt, first.createdAt);
      expect(first.dueAt.difference(first.createdAt), const Duration(days: 15));
      expect(first.status, DataSubjectRequestStatus.open);
      expect(await DataSubjectRequest.db.count(session, where: (t) => t.userId.equals(UuidValue.fromString(_patientId))), 1);

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.requests.single.type, DataSubjectRequestType.deletion);
      expect(overview.requests.single.status, DataSubjectRequestStatus.open);
    });

    test('requestDataCorrection guarda o texto cifrado e myData devolve o texto decifrado', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await endpoints.patients.requestDataCorrection(
        sessionBuilder,
        accessToken: token,
        details: 'Meu contato de emergência mudou.',
      );

      final row = (await DataSubjectRequest.db.find(session, where: (t) => t.userId.equals(UuidValue.fromString(_patientId)))).single;
      expect(row.detailsEncrypted, isNot(contains('contato')));
      expect(row.detailsEncrypted, isNotEmpty);

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.requests.single.type, DataSubjectRequestType.correction);
      expect(overview.requests.single.details, 'Meu contato de emergência mudou.');
    });

    test('um ACS não chama nenhuma das três', () async {
      await _seed(sessionBuilder.build());
      final token =
          (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

      await expectLater(
        endpoints.patients.updateConsent(
          sessionBuilder,
          accessToken: token,
          purpose: ConsentPurpose.localReminders,
          granted: false,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.patients.requestDataCorrection(sessionBuilder, accessToken: token, details: 'x'),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test(
      'conta anonimizada (#42) com JWT ainda vivo não abre pedido nem mexe em consentimento',
      () async {
        final session = sessionBuilder.build();
        await _seed(session);
        final token = await patientToken();
        // O que a exclusão atendida faz em `users.cpfHash` (orm_data_subject_case_store).
        await session.db.unsafeExecute(
          'UPDATE users SET "cpfHash" = \'removed:sintetico\' WHERE id = @id::uuid',
          parameters: QueryParameters.named({'id': _patientId}),
        );

        for (final chamada in <Future<Object?> Function()>[
          () => endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token),
          () => endpoints.patients.requestDataCorrection(
                sessionBuilder,
                accessToken: token,
                details: 'texto sintético',
              ),
          () => endpoints.patients.updateConsent(
                sessionBuilder,
                accessToken: token,
                purpose: ConsentPurpose.segmentedPush,
                granted: true,
              ),
          () => endpoints.patients.updateConsent(
                sessionBuilder,
                accessToken: token,
                purpose: ConsentPurpose.localReminders,
                granted: false,
              ),
          () => endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: token),
        ]) {
          await expectLater(chamada(), throwsA(isA<AlertPermissionException>()));
        }
        expect(await DataSubjectRequest.db.count(session, where: (t) => t.userId.equals(UuidValue.fromString(_patientId))), 0);
        expect(await ConsentLog.db.count(session, where: (t) => t.userId.equals(UuidValue.fromString(_patientId))), 0);
        await expectLater(
          endpoints.devices.registerPushToken(
            sessionBuilder,
            accessToken: token,
            token: 'token-sintetico-anonimizado',
            platform: 'android',
          ),
          throwsA(isA<DataRightsException>()),
        );
        expect(await PushToken.db.count(session, where: (t) => t.userId.equals(UuidValue.fromString(_patientId))), 0);
      },
    );

    test(
      'conta anonimizada (#42) com JWT vivo não regrava condições crônicas',
      () async {
        final session = sessionBuilder.build();
        await _seed(session);
        final token = await patientToken();
        final antes = (await Patient.db.findById(session, UuidValue.fromString(_patientId)))!
            .chronicConditionsEncrypted;
        await session.db.unsafeExecute(
          'UPDATE users SET "cpfHash" = \'removed:sintetico\' WHERE id = @id::uuid',
          parameters: QueryParameters.named({'id': _patientId}),
        );

        try {
          await endpoints.patients.updateChronicConditions(
            sessionBuilder,
            accessToken: token,
            conditions: const ['hipertensão sintética'],
          );
          fail('deveria recusar');
        } on AlertPermissionException catch (e) {
          expect(e.message, 'Sessão encerrada. Entre novamente.');
        }
        final depois = (await Patient.db.findById(session, UuidValue.fromString(_patientId)))!
            .chronicConditionsEncrypted;
        expect(depois, antes);
      },
    );

    test(
      'triagem: conta normal grava a sessão; conta anonimizada (#42) recebe a '
      'mesma classificação e nada é gravado',
      () async {
        final session = sessionBuilder.build();
        await _seed(session);
        final token = await patientToken();

        Future<TriageResult> avaliar() => endpoints.triage.evaluate(
              sessionBuilder,
              accessToken: token,
              chestPain: true,
              difficultyBreathing: false,
              fever: true,
              persistentVomiting: false,
              bleeding: false,
              severeWeakness: false,
            );

        final normal = await avaliar();
        expect(await TriageSession.db.count(session, where: (t) => t.patientId.equals(UuidValue.fromString(_patientId))), 1);
        final linha = (await TriageSession.db.find(session, where: (t) => t.patientId.equals(UuidValue.fromString(_patientId)))).single;
        expect(linha.answersEncrypted, isNotEmpty);

        await session.db.unsafeExecute(
          'UPDATE users SET "cpfHash" = \'removed:sintetico\' WHERE id = @id::uuid',
          parameters: QueryParameters.named({'id': _patientId}),
        );
        final anonimizada = await avaliar();
        expect(anonimizada.risk, normal.risk);
        expect(await TriageSession.db.count(session, where: (t) => t.patientId.equals(UuidValue.fromString(_patientId))), 1,
            reason: 'nenhuma sessão nova (nem respostas) para a conta anonimizada');
      },
    );

    test('cada escrita deixa linha real em audit_logs', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await endpoints.patients.updateConsent(
        sessionBuilder,
        accessToken: token,
        purpose: ConsentPurpose.segmentedPush,
        granted: true,
      );
      await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);

      final consentRows = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('consent_log'),
      );
      final requestRows = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('data_subject_request'),
      );
      expect(consentRows, hasLength(1));
      expect(requestRows, hasLength(1));
      expect(requestRows.single.userId, UuidValue.fromString(_patientId));
    });
  });

  // Grupo separado, com rollback desligado: com o rollback ligado, todas as
  // chamadas dividem a MESMA transação externa do harness e chamadas
  // concorrentes que abrem a própria transação são recusadas. Só assim cada
  // chamada abre uma transação real do Postgres, que é o que a corrida exige.
  withServerpod(
    'Dado o pedido de exclusão, sem rollback automático (corrida)',
    (sessionBuilder, endpoints) {
      setUp(() => AlertRuntime.instance.overrideConfig(_config()));
      tearDown(() => AlertRuntime.instance.overrideConfig(null));

      test('três pedidos de exclusão simultâneos deixam um só pedido aberto', () async {
        final session = sessionBuilder.build();
        await _seedRace(session);
        try {
          // Direto no store ORM, com uma `Session` por chamada (como cada
          // requisição monta a sua): passar pelo endpoint gravaria linhas de
          // `audit_logs`, que têm FK para `users` e cadeia de hash — e a
          // limpeza manual quebraria os dois.
          Future<Object> attempt() async {
            final store = OrmDataSubjectRightsStore(
              session: () => sessionBuilder.build(),
              chainSecret: _chainSecret,
              cipher: AlertRuntime.instance.healthDataCipher,
            );
            try {
              return await store.createDeletionRequestIfNoneOpen(
                userId: _racePatientId,
                createdAt: DateTime.now().toUtc(),
                dueAt: DateTime.now().toUtc().add(const Duration(days: 15)),
              );
            } catch (error) {
              return error;
            }
          }

          final results = await Future.wait([attempt(), attempt(), attempt()]);

          final outcomes = results
              .whereType<({DataSubjectRequestSnapshot request, bool created})>()
              .toList();
          expect(outcomes, hasLength(3), reason: 'nenhuma chamada pode falhar: $results');
          expect(outcomes.where((o) => o.created), hasLength(1),
              reason: 'só uma das três cria; as outras recebem a dela');
          expect(outcomes.map((o) => o.request.id).toSet(), hasLength(1));
          final open = await DataSubjectRequest.db.find(
            session,
            where: (t) =>
                t.userId.equals(UuidValue.fromString(_racePatientId)) &
                t.requestType.equals(DataSubjectRequestType.deletion) &
                t.status.equals(DataSubjectRequestStatus.open),
          );
          expect(open, hasLength(1));
        } finally {
          await _cleanupRace(session);
        }
      });

      test('dois aceites do termo simultâneos gravam uma linha só', () async {
        final session = sessionBuilder.build();
        await _seedRace(session);
        try {
          Future<Object> attempt() async {
            final store = OrmDataSubjectRightsStore(
              session: () => sessionBuilder.build(),
              chainSecret: _chainSecret,
              cipher: AlertRuntime.instance.healthDataCipher,
            );
            try {
              return await store.recordConsentUnlessCurrent(ConsentLogEntry(
                userId: _racePatientId,
                purpose: ConsentPurpose.termsOfUse,
                action: 'granted',
                version: consentPolicyVersion,
                timestamp: DateTime.now().toUtc(),
              ));
            } catch (error) {
              return error;
            }
          }

          final results = await Future.wait([attempt(), attempt(), attempt()]);

          final outcomes =
              results.whereType<({String? id, ConsentRecordSnapshot? existing})>().toList();
          expect(outcomes, hasLength(3), reason: 'nenhuma chamada pode falhar: $results');
          expect(outcomes.where((o) => o.id != null), hasLength(1));
          final rows = await ConsentLog.db.find(
            session,
            where: (t) =>
                t.userId.equals(UuidValue.fromString(_racePatientId)) &
                t.purpose.equals(ConsentPurpose.termsOfUse.name),
          );
          expect(rows, hasLength(1));
        } finally {
          await _cleanupRace(session);
        }
      });
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}
