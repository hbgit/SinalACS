import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/push/gorush_client.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, a segmentação de `notices.sendSegmented` (RF14):
/// microárea do ACS, consentimento MAIS RECENTE de `segmentedPush`, filtro de
/// crônicos e poda de token inválido. O Gorush é um duplo: sem credenciais
/// FCM/APNs não há como falar com um de verdade aqui.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _otherMicroAreaId = '00000000-0000-4000-8000-000000000013';
const _revokedId = '00000000-0000-4000-8000-000000000021';
const _outsiderId = '00000000-0000-4000-8000-000000000022';
const _plainId = '00000000-0000-4000-8000-000000000023';
const _noClinicalId = '00000000-0000-4000-8000-000000000024';
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

class _RecordingSender implements PushSender {
  List<PushTarget> lastTargets = const [];
  PushSendReport report = const PushSendReport(accepted: 1, invalidTokens: []);
  int calls = 0;

  @override
  Future<PushSendReport> send(PushMessage message, List<PushTarget> targets) async {
    calls++;
    lastTargets = targets;
    return report;
  }
}

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



Future<void> _addPatient(
  Session session, {
  required String id,
  required String microAreaId,
  required bool chronic,
  bool withPatientRow = true,
}) async {
  final now = DateTime.now().toUtc();
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(id),
      cpfHash: 'development-notice-$id',
      name: 'Paciente de teste',
      birthDate: DateTime.utc(1985, 5, 5),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  );
  if (!withPatientRow) return;
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: id,
      emergencyContact: 'Contato de teste',
      isChronic: chronic,
      chronicConditions: const [],
    ),
  );
}

Future<void> _consent(Session session, String userId, String action, DateTime at) =>
    ConsentLog.db.insertRow(
      session,
      ConsentLog(
        userId: UuidValue.fromString(userId),
        purpose: ConsentPurpose.segmentedPush.name,
        action: action,
        version: '2026.1',
        timestamp: at,
        ipHash: 'nao-aplicavel-teste',
        userAgent: 'nao-aplicavel-teste',
        signature: 'assinatura-de-teste',
      ),
    );

Future<void> _token(Session session, String userId, String token, String microAreaId) {
  final now = DateTime.now().toUtc();
  return PushToken.db.insertRow(
    session,
    PushToken(
      userId: UuidValue.fromString(userId),
      microAreaId: UuidValue.fromString(microAreaId),
      token: token,
      platform: 'android',
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void main() {
  withServerpod('Dado o aviso comunitário do ACS (RF14)', (sessionBuilder, endpoints) {
    late _RecordingSender sender;

    setUp(() {
      AlertRuntime.instance.overrideConfig(_config());
      sender = _RecordingSender();
      AlertRuntime.instance.overrideNoticeSender(() => sender);
    });
    tearDown(() {
      AlertRuntime.instance.overrideNoticeSender(null);
      AlertRuntime.instance.overrideConfig(null);
    });

    Future<String> tokenOf(String role) async =>
        (await endpoints.auth.developmentLogin(sessionBuilder, role: role)).accessToken;

    /// A microárea A tem: o paciente do dev-login (consentiu), um que revogou
    /// DEPOIS de registrar o token e um sem crônica. A B tem um que consentiu.
    Future<Session> seedAll() async {
      final session = sessionBuilder.build();
      await _seed(session);
      await MicroArea.db.insertRow(
        session,
        MicroArea(
          id: UuidValue.fromString(_otherMicroAreaId),
          name: 'Microárea 13',
          ubsId: UuidValue.fromString(_ubsId),
          geoJsonBoundary: '{}',
        ),
      );
      await _addPatient(session, id: _revokedId, microAreaId: _microAreaId, chronic: true);
      await _addPatient(session, id: _plainId, microAreaId: _microAreaId, chronic: false);
      await _addPatient(session, id: _outsiderId, microAreaId: _otherMicroAreaId, chronic: true);
      final t0 = DateTime.utc(2026, 9, 1);
      await _consent(session, _patientId, 'granted', t0);
      await _token(session, _patientId, 'tok-a1', _microAreaId);
      await _consent(session, _revokedId, 'granted', t0);
      await _consent(session, _revokedId, 'denied', t0.add(const Duration(days: 1)));
      await _token(session, _revokedId, 'tok-revogou', _microAreaId); // sobra no banco de propósito
      await _consent(session, _plainId, 'granted', t0);
      await _token(session, _plainId, 'tok-a3', _microAreaId);
      await _consent(session, _outsiderId, 'granted', t0);
      await _token(session, _outsiderId, 'tok-b1', _otherMicroAreaId);
      return session;
    }

    Future<NoticeSendResult> send(String token, {String audience = 'everyone'}) =>
        endpoints.notices.sendSegmented(
          sessionBuilder,
          accessToken: token,
          title: 'Vacinação',
          message: 'Amanhã, das 8h às 12h.',
          audience: audience,
        );

    test('só recebe quem tem consentimento vigente na microárea do ACS', () async {
      await seedAll();
      final result = await send(await tokenOf('acs'));

      expect(sender.lastTargets.map((t) => t.token).toList(), ['tok-a1', 'tok-a3']);
      expect(result.recipients, 2);
    });

    test('quem revogou depois de registrar o token não recebe, mesmo com o token no banco', () async {
      final session = await seedAll();
      expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-revogou')), 1);
      await send(await tokenOf('acs'));
      expect(sender.lastTargets.map((t) => t.token), isNot(contains('tok-revogou')));
    });

    test('o filtro de crônicos usa patients.isChronic', () async {
      final session = await seedAll();
      // torna o paciente do dev-login crônico; o "a3" continua não crônico
      final patient = await Patient.db.findById(session, UuidValue.fromString(_patientId));
      await Patient.db.updateRow(session, patient!.copyWith(isChronic: true));

      await send(await tokenOf('acs'), audience: 'chronic');

      expect(sender.lastTargets.map((t) => t.token).toList(), ['tok-a1']);
    });

    test('sem destinatário consentido: 0 e sem chamar o relé', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final result = await send(await tokenOf('acs'));
      expect((result.recipients, result.accepted), (0, 0));
      expect(sender.calls, 0);
    });

    test('token inválido devolvido pelo provedor some do banco', () async {
      final session = await seedAll();
      sender.report = const PushSendReport(accepted: 1, invalidTokens: ['tok-a1']);
      await send(await tokenOf('acs'));
      expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-a1')), 0);
      expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-a3')), 1);
    });

    test('grava uma linha community_notice só com ACS e microárea', () async {
      final session = await seedAll();
      final before = await AuditLog.db.count(session);
      await send(await tokenOf('acs'));
      final rows = await AuditLog.db.find(session, orderBy: (t) => t.timestamp, orderDescending: true, limit: 1);
      expect(await AuditLog.db.count(session), before + 1);
      expect(rows.single.resourceType, 'community_notice');
      expect(rows.single.result, 'granted');
      expect(rows.single.resourceId, UuidValue.fromString(_microAreaId));
      expect(jsonEncode(rows.single.toJson()).contains('Amanhã, das 8h'), isFalse);
    });

    test('paciente sem linha clínica recebe "para todos" e fica fora do filtro de crônicos', () async {
      final session = await seedAll();
      await _addPatient(session,
          id: _noClinicalId, microAreaId: _microAreaId, chronic: false, withPatientRow: false);
      await _consent(session, _noClinicalId, 'granted', DateTime.utc(2026, 9, 1));
      await _token(session, _noClinicalId, 'tok-sem-clinica', _microAreaId);

      await send(await tokenOf('acs'));
      expect(sender.lastTargets.map((t) => t.token), contains('tok-sem-clinica'));

      sender.lastTargets = const []; // o filtro pode não deixar ninguém: o relé nem é chamado
      await send(await tokenOf('acs'), audience: 'chronic');
      expect(sender.lastTargets.map((t) => t.token), isNot(contains('tok-sem-clinica')));
    });

    test('consentimentos com o mesmo timestamp: o de id maior decide', () async {
      final session = await seedAll();
      final at = DateTime.utc(2026, 9, 2);
      Future<void> linha(String id, String action) => ConsentLog.db.insertRow(
            session,
            ConsentLog(
              id: UuidValue.fromString(id),
              userId: UuidValue.fromString(_plainId),
              purpose: ConsentPurpose.segmentedPush.name,
              action: action,
              version: '2026.1',
              timestamp: at,
              ipHash: 'nao-aplicavel-teste',
              userAgent: 'nao-aplicavel-teste',
              signature: 'assinatura-de-teste',
            ),
          );
      // `_plainId` já tem um 'granted' de t0 em `seedAll`; estas duas linhas empatam
      // entre si e são as mais recentes. O 'granted' tem o id MENOR.
      await linha('00000000-0000-4000-8000-0000000000c1', 'granted');
      await linha('00000000-0000-4000-8000-0000000000c2', 'denied');

      await send(await tokenOf('acs'));

      expect(sender.lastTargets.map((t) => t.token), isNot(contains('tok-a3')));
    });

    test('paciente e token inválido são recusados', () async {
      await seedAll();
      await expectLater(send(await tokenOf('patient')), throwsA(isA<AlertPermissionException>()));
      await expectLater(send('lixo'), throwsA(isA<AlertPermissionException>()));
      expect(sender.calls, 0);
    });

    test('sem relé configurado, a chamada falha com NoticeDeliveryException', () async {
      await seedAll();
      AlertRuntime.instance.overrideNoticeSender(() => null);
      await expectLater(send(await tokenOf('acs')), throwsA(isA<NoticeDeliveryException>()));
    });
  });
}
