import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_terms_version_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Agenda de mudança dos termos (#46) com o store ORM real: rascunho, revisão e
/// publicação por `OrmTermsVersionStore`, e o cartão lido pelo endpoint do
/// paciente. O relógio do endpoint é o real, então as datas são relativas a ele.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _adminId = '00000000-0000-4000-8000-0000000000c1';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      telemetryPseudonymKey: AppConfig.developmentTelemetryPseudonymKey,
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
      name: 'UBS sintética',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea sintética',
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
      id: UuidValue.fromString(_adminId),
      cpfHash: 'development-admin-termos',
      name: 'Admin sintético',
      birthDate: DateTime.utc(1980, 1, 1),
      role: UserRole.admin,
      createdAt: now,
      updatedAt: now,
    ),
  ]);
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

void main() {
  withServerpod('Dada a agenda de termos publicada no Postgres (#46)', (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    late Session session;
    late OrmTermsVersionStore store;
    late String token;

    Future<String> rascunho(String version, {int vigenciaEmDias = 20, String summary = 'Resumo.'}) =>
        store.insertDraft(
          version: version,
          summary: summary,
          effectiveFrom: DateTime.now().toUtc().add(Duration(days: vigenciaEmDias)),
          createdBy: _adminId,
          createdAt: DateTime.now().toUtc(),
        );

    Future<void> publica(String id, {Duration publicadaHa = const Duration(hours: 1)}) async {
      final at = DateTime.now().toUtc().subtract(publicadaHa);
      expect(await store.markReviewed(id, reviewedBy: _adminId, at: at), isTrue);
      expect(await store.markPublished(id, publishedBy: _adminId, at: at), isTrue);
    }

    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      store = OrmTermsVersionStore(session: () => session);
      token = (await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient')).accessToken;
    });

    test('rascunho e revisada-não-publicada não aparecem; publicada aparece', () async {
      final id = await rascunho('2099.1', summary: 'Novo canal de dúvidas.');
      expect(await endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: token), isNull);

      expect(await store.markReviewed(id, reviewedBy: _adminId, at: DateTime.now().toUtc()), isTrue);
      expect(await endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: token), isNull);

      expect(await store.markPublished(id, publishedBy: _adminId, at: DateTime.now().toUtc()), isTrue);
      final notice = (await endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: token))!;
      expect(notice.version, '2099.1');
      expect(notice.summary, 'Novo canal de dúvidas.');
      expect(notice.effectiveFrom.isAfter(DateTime.now().toUtc()), isTrue);
    });

    test('a segunda publicação, enquanto a primeira não vigora, é a servida', () async {
      await publica(await rascunho('2099.1'), publicadaHa: const Duration(hours: 2));
      await publica(await rascunho('2099.2'), publicadaHa: const Duration(hours: 1));
      final notice = (await endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: token))!;
      expect(notice.version, '2099.2');
    });

    test('linha inconsistente (menos de 15 dias) não derruba o cartão: devolve null', () async {
      await publica(await rascunho('2099.3', vigenciaEmDias: 3));
      expect(await endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: token), isNull);
    });

    test('vigência já passada não é aviso', () async {
      final id = await rascunho('2099.4', vigenciaEmDias: 1);
      await publica(id);
      await session.db.unsafeQuery(
        'UPDATE terms_versions SET "effectiveFrom" = @e WHERE "id" = @id::uuid',
        parameters: QueryParameters.named({
          'e': DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          'id': id,
        }),
      );
      expect(await endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: token), isNull);
    });

    test('markPublished sem revisão devolve false e não publica', () async {
      final id = await rascunho('2099.5');
      expect(await store.markPublished(id, publishedBy: _adminId, at: DateTime.now().toUtc()), isFalse);
      expect((await store.findById(id))!.publishedAt, isNull);
    });

    test('markReviewed duas vezes: a segunda devolve false; depois de publicada também', () async {
      final id = await rascunho('2099.6');
      final at = DateTime.now().toUtc();
      expect(await store.markReviewed(id, reviewedBy: _adminId, at: at), isTrue);
      expect(await store.markReviewed(id, reviewedBy: _adminId, at: at), isFalse);
      expect(await store.markPublished(id, publishedBy: _adminId, at: at), isTrue);
      expect(await store.markPublished(id, publishedBy: _adminId, at: at), isFalse);
      expect(await store.markReviewed(id, reviewedBy: _adminId, at: at), isFalse);
    });

    test('id que não é UUID devolve null/false em vez de estourar', () async {
      expect(await store.findById('nao-e-uuid'), isNull);
      expect(await store.markReviewed('nao-e-uuid', reviewedBy: _adminId, at: DateTime.now().toUtc()), isFalse);
      expect(await store.markPublished('nao-e-uuid', publishedBy: _adminId, at: DateTime.now().toUtc()), isFalse);
    });

    test('versionExists e list enxergam as linhas, com datas em UTC', () async {
      final id = await rascunho('2099.7');
      expect(await store.versionExists('2099.7'), isTrue);
      expect(await store.versionExists('2099.8'), isFalse);
      final todas = await store.list();
      expect(todas.map((e) => e.id), contains(id));
      expect(todas.every((e) => e.effectiveFrom.isUtc && e.createdAt.isUtc), isTrue);
    });
  });
}
