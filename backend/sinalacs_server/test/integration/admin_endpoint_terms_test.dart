import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// `admin.termsVersions` / `draftTermsVersion` / `markTermsReviewed` /
/// `publishTermsVersion` (#46)
/// pelo endpoint, com tokens reais e Postgres real. Dados sintéticos.
const _admin = '00000000-0000-4000-8000-0000000046d1';
const _coordA = '00000000-0000-4000-8000-0000000046d2';
const _acs = '00000000-0000-4000-8000-0000000046d3';
const _paciente = '00000000-0000-4000-8000-0000000046d4';
final _t = DateTime.utc(2026, 1, 1);

AppConfig _config() => AppConfig(
  mqttBroker: 'localhost:1883',
  jwtSecret: 'test-secret',
  auditChainSecret: 'test-audit-chain-secret',
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

String _token(String id, UserRole role) => AlertRuntime.instance.auth.issueToken(
  AuthenticatedUser(id: id, role: role, microAreaId: null, deviceId: 'dev'),
);

Future<void> _seed(Session s) async {
  await User.db.insert(s, [
    for (final (id, role) in [
      (_admin, UserRole.admin),
      (_coordA, UserRole.coordinator),
      (_acs, UserRole.acs),
      (_paciente, UserRole.patient),
    ])
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'sintetico-$id',
        name: 'Sintético $id',
        birthDate: DateTime.utc(1980),
        role: role,
        createdAt: _t,
        updatedAt: _t,
      ),
  ]);
}

void main() {
  withServerpod('Dado os endpoints de termos do admin (#46)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;

    setUp(() async {
      session = sessionBuilder.build();
      AlertRuntime.instance.overrideConfig(_config());
      await _seed(session);
    });
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    final admin = () => _token(_admin, UserRole.admin);
    DateTime inDays(int d) => DateTime.now().toUtc().add(Duration(days: d));

    Future<TermsVersionEntry> rascunho(String v, DateTime eff) =>
        endpoints.admin.draftTermsVersion(
          sessionBuilder,
          accessToken: admin(),
          version: v,
          summary: '[TEXTO PLACEHOLDER]',
          effectiveFrom: eff,
        );

    Future<List<AuditLog>> audit(String result) => AuditLog.db.find(
      session,
      where: (t) =>
          t.resourceType.equals('terms_version') & t.result.equals(result),
    );

    test('token inválido: falha de autenticação nos quatro métodos', () async {
      for (final call in <Future<Object?> Function()>[
        () => endpoints.admin.termsVersions(sessionBuilder, accessToken: 'lixo'),
        () => endpoints.admin.draftTermsVersion(
          sessionBuilder,
          accessToken: 'lixo',
          version: '2099.1',
          summary: '[TEXTO PLACEHOLDER]',
          effectiveFrom: inDays(20),
        ),
        () => endpoints.admin.markTermsReviewed(sessionBuilder, accessToken: 'lixo', id: _admin),
        () => endpoints.admin.publishTermsVersion(sessionBuilder, accessToken: 'lixo', id: _admin),
      ]) {
        await expectLater(call(), throwsA(isA<AlertPermissionException>()));
      }
    });

    test('paciente, ACS e coordenador: AlertPermissionException e denied_role', () async {
      final papeis = [
        (_paciente, UserRole.patient),
        (_acs, UserRole.acs),
        (_coordA, UserRole.coordinator),
      ];
      for (final (id, role) in papeis) {
        final t = _token(id, role);
        await expectLater(
          endpoints.admin.termsVersions(sessionBuilder, accessToken: t),
          throwsA(isA<AlertPermissionException>()),
        );
        await expectLater(
          endpoints.admin.draftTermsVersion(
            sessionBuilder,
            accessToken: t,
            version: '2099.1',
            summary: '[TEXTO PLACEHOLDER]',
            effectiveFrom: inDays(20),
          ),
          throwsA(isA<AlertPermissionException>()),
        );
        await expectLater(
          endpoints.admin.markTermsReviewed(sessionBuilder, accessToken: t, id: _admin),
          throwsA(isA<AlertPermissionException>()),
        );
        await expectLater(
          endpoints.admin.publishTermsVersion(sessionBuilder, accessToken: t, id: _admin),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      final negadas = await audit('denied_role');
      expect(negadas, hasLength(12));
      expect(
        negadas.map((l) => l.userId).toSet(),
        {for (final (id, _) in papeis) UuidValue.fromString(id)},
      );
    });

    test('admin rascunha, revisa e publica; o paciente passa a ver o aviso', () async {
      final eff = inDays(20);
      final t = _token(_paciente, UserRole.patient);
      expect(
        await endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: t),
        isNull,
      );

      final r = await rascunho('2099.1', eff);
      expect(r.legallyReviewedAt, isNull);
      expect(r.publishedAt, isNull);
      expect(r.summary, '[TEXTO PLACEHOLDER]');

      final rev = await endpoints.admin.markTermsReviewed(
        sessionBuilder, accessToken: admin(), id: r.id);
      expect(rev.legallyReviewedAt, isNotNull);

      final pub = await endpoints.admin.publishTermsVersion(
        sessionBuilder, accessToken: admin(), id: r.id);
      expect(pub.publishedAt, isNotNull);

      final aviso = await endpoints.patients.termsChangeNotice(
        sessionBuilder, accessToken: t);
      expect(aviso, isNotNull);
      expect(aviso!.version, '2099.1');
      expect(aviso.summary, '[TEXTO PLACEHOLDER]');
      expect(aviso.effectiveFrom.toUtc().difference(eff).abs(),
          lessThan(const Duration(seconds: 1)));
    });

    test('publicar sem revisão: AdminInvalidRequestException e denied_not_reviewed', () async {
      final r = await rascunho('2099.2', inDays(20));
      await expectLater(
        endpoints.admin.publishTermsVersion(sessionBuilder, accessToken: admin(), id: r.id),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      expect(await audit('denied_not_reviewed'), hasLength(1));
    });

    test('vigência a 14 dias: recusada na publicação e denied_notice_period', () async {
      final r = await rascunho('2099.3', inDays(14));
      await endpoints.admin.markTermsReviewed(sessionBuilder, accessToken: admin(), id: r.id);
      await expectLater(
        endpoints.admin.publishTermsVersion(sessionBuilder, accessToken: admin(), id: r.id),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      expect(await audit('denied_notice_period'), hasLength(1));
    });

    test('vigência exatamente 15 dias depois da publicação: aceita', () async {
      final agora = DateTime.utc(2099, 1, 1, 12);
      final svc = AlertRuntime.instance.termsPublicationServiceFor(
        session,
        clock: () => agora,
      );
      final user = AuthenticatedUser(
        id: _admin, role: UserRole.admin, microAreaId: null, deviceId: 'dev');
      final r = await svc.draft(
        user,
        version: '2099.4',
        summary: '[TEXTO PLACEHOLDER]',
        effectiveFrom: agora.add(const Duration(days: 15)),
      );
      await svc.markReviewed(user, r.id);
      final pub = await svc.publish(user, r.id);
      expect(pub.publishedAt, isNotNull);
    });

    test('listagem ordenada por createdAt decrescente', () async {
      final a = await rascunho('2099.5', inDays(20));
      final b = await rascunho('2099.6', inDays(21));
      final lista = await endpoints.admin.termsVersions(
        sessionBuilder, accessToken: admin());
      expect(lista.map((e) => e.id).toList(), [b.id, a.id]);
    });

    test('o resumo nunca aparece em audit_logs', () async {
      final r = await endpoints.admin.draftTermsVersion(
        sessionBuilder,
        accessToken: admin(),
        version: '2099.7',
        summary: 'RESUMO-SECRETO-DOS-TERMOS',
        effectiveFrom: inDays(20),
      );
      await endpoints.admin.markTermsReviewed(sessionBuilder, accessToken: admin(), id: r.id);
      await endpoints.admin.publishTermsVersion(sessionBuilder, accessToken: admin(), id: r.id);
      await endpoints.admin.termsVersions(sessionBuilder, accessToken: admin());
      final logs = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('terms_version'),
      );
      expect(logs, isNotEmpty);
      expect(logs.map((l) => l.toString()).join(), isNot(contains('RESUMO-SECRETO')));
    });
  });
}
