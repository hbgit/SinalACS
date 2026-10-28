import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/devices/device_wipe_service.dart';
import 'package:sinalacs_server/src/application/devices/device_certificate_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_admin_account_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_device_wipe_store.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_session_kicker.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/fake_mqtt_broker.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Desativar ou mudar de microárea um ACS revoga os certificados dos aparelhos
/// dele na mesma transação da conta, publica a CRL e derruba a sessão MQTT
/// aberta de cada aparelho (#94, lacuna 1 / decisão 5); a limpeza remota faz o
/// mesmo para o aparelho limpo. Postgres real, broker
/// falso do projeto em TCP real e o `MqttSessionKicker` real, pelo serviço que
/// o `AlertRuntime` monta. Dados sintéticos; ids próprios (`...c5xx`).
const _ubs = '00000000-0000-4000-8000-00000000c501';
const _ma1 = '00000000-0000-4000-8000-00000000c502';
const _ma2 = '00000000-0000-4000-8000-00000000c503';
const _acs = '00000000-0000-4000-8000-00000000c504';
const _admin = '00000000-0000-4000-8000-00000000c505';
const _dev1 = 'aparelho-rev-1';
const _dev2 = 'aparelho-rev-2';

const _operador = AuthenticatedUser(
  id: _admin,
  role: UserRole.admin,
  microAreaId: null,
  deviceId: 'sem-aparelho',
);

/// Trilha fora do ar: toda gravação pós-commit do serviço falha (fail-closed).
class _TrilhaQuebrada extends AuditTrail {
  @override
  Future<void> record(AuditEvent event) async =>
      throw StateError('trilha fora do ar');
}

class _CrlContada implements CrlPublication {
  int chamadas = 0;

  @override
  Future<String?> publish({DateTime? now}) async {
    chamadas++;
    return 'f' * 64;
  }
}

AppConfig _config(int port) => AppConfig(
  mqttBroker: '127.0.0.1:$port',
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

Future<void> _seed(Session s) async {
  await Ubs.db.insertRow(
    s,
    Ubs(
      id: UuidValue.fromString(_ubs),
      name: 'UBS Revogação',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  for (final ma in [_ma1, _ma2]) {
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(ma),
        name: 'Microárea $ma',
        ubsId: UuidValue.fromString(_ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }
  final now = DateTime.now().toUtc();
  for (final (id, role) in [(_acs, UserRole.acs), (_admin, UserRole.admin)]) {
    await User.db.insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'rev-$id',
        name: 'Usuário sintético',
        birthDate: DateTime.utc(1980),
        role: role,
        microAreaId: role == UserRole.acs ? UuidValue.fromString(_ma1) : null,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acs),
      enrollmentId: 'ACS-REV-001',
      ubsId: UuidValue.fromString(_ubs),
      active: true,
    ),
  );
  for (final (dev, serial) in [
    (_dev1, 'a1a1a1a1a1a14a1aa1a1a1a1a1a1a1a1'),
    (_dev2, 'a2a2a2a2a2a24a2aa2a2a2a2a2a2a2a2'),
  ]) {
    await DeviceCertificate.db.insertRow(
      s,
      DeviceCertificate(
        userId: UuidValue.fromString(_acs),
        deviceId: dev,
        microAreaId: UuidValue.fromString(_ma1),
        serial: serial,
        fingerprintSha256: 'f' * 64,
        notBefore: now.subtract(const Duration(hours: 1)),
        notAfter: now.add(const Duration(days: 30)),
        issuedAt: now,
      ),
    );
  }
}

/// Um "aparelho" com a assinatura viva no tópico da microárea; [caiu]
/// completa quando a sessão dele cai.
Future<({MqttServerClient client, Completer<void> caiu})> _aparelho(
  int port,
  String deviceId,
) async {
  final id = MqttSessionKicker.clientIdFor(acsId: _acs, deviceId: deviceId);
  final caiu = Completer<void>();
  final client = MqttServerClient.withPort('127.0.0.1', id, port)
    ..keepAlivePeriod = 60
    ..autoReconnect = false
    ..logging(on: false)
    ..onDisconnected = (() {
      if (!caiu.isCompleted) caiu.complete();
    })
    ..connectionMessage = MqttConnectMessage().withClientIdentifier(id).startClean();
  await client.connect();
  client.subscribe('sinalacs/v1/microareas/$_ma1/alerts', MqttQos.atLeastOnce);
  return (client: client, caiu: caiu);
}

void main() {
  withServerpod('Dada a revogação dos certificados pela gestão de contas (#94)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late FakeMqttBroker broker;
    late _CrlContada crl;
    late ({MqttServerClient client, Completer<void> caiu}) a1;
    late ({MqttServerClient client, Completer<void> caiu}) a2;

    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      broker = await FakeMqttBroker.start();
      crl = _CrlContada();
      AlertRuntime.instance
        ..overrideDeviceCrlPublication(crl)
        ..overrideSessionKicker(
          MqttSessionKicker(config: _config(broker.port), log: (_) {}),
        );
      a1 = await _aparelho(broker.port, _dev1);
      a2 = await _aparelho(broker.port, _dev2);
    });
    tearDown(() async {
      AlertRuntime.instance
        ..overrideDeviceCrlPublication(null)
        ..overrideSessionKicker(null);
      a1.client.disconnect();
      a2.client.disconnect();
      await broker.close();
    });

    Future<List<DeviceCertificate>> certificados() =>
        DeviceCertificate.db.find(session, orderBy: (t) => t.deviceId);

    Future<List<String>> revogacoesAuditadas() async => [
      for (final l in await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('device_certificate'),
      ))
        l.result,
    ];

    test(
      'setAcsActive(false) revoga todos os certificados do ACS como deactivated '
      'e derruba a sessão aberta de cada aparelho',
      () async {
        await AlertRuntime.instance
            .adminAccountServiceFor(session)
            .setAcsActive(_operador, acsId: _acs, active: false);

        final certs = await certificados();
        expect(certs.every((c) => c.revokedAt != null), isTrue);
        expect(
          certs.map((c) => c.revocationReason).toSet(),
          {DeviceCertRevocationReason.deactivated},
        );
        await Future.wait([
          a1.caiu.future,
          a2.caiu.future,
        ]).timeout(const Duration(seconds: 2));
        expect(crl.chamadas, 1);
        expect(await revogacoesAuditadas(), [
          'device_cert_revoked:deactivated',
          'device_cert_revoked:deactivated',
        ]);
      },
    );

    test(
      'setAcsMicroArea revoga como microAreaChanged e derruba a sessão aberta',
      () async {
        await AlertRuntime.instance
            .adminAccountServiceFor(session)
            .setAcsMicroArea(_operador, acsId: _acs, microAreaId: _ma2);

        final certs = await certificados();
        expect(
          certs.map((c) => c.revocationReason).toSet(),
          {DeviceCertRevocationReason.microAreaChanged},
        );
        // Uma assinatura viva com o client id do aparelho cai em ≤ 2 s.
        await Future.wait([
          a1.caiu.future,
          a2.caiu.future,
        ]).timeout(const Duration(seconds: 2));
        expect(crl.chamadas, 1);
        expect(await revogacoesAuditadas(), hasLength(2));
      },
    );

    test('setAcsActive(true) não revoga nem derruba nada', () async {
      await AlertRuntime.instance
          .adminAccountServiceFor(session)
          .setAcsActive(_operador, acsId: _acs, active: true);

      expect((await certificados()).every((c) => c.revokedAt == null), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(a1.caiu.isCompleted || a2.caiu.isCompleted, isFalse);
      expect(broker.takenOver, isEmpty);
      expect(crl.chamadas, 0);
      expect(await revogacoesAuditadas(), isEmpty);
    });

    test(
      'orderWipe revoga como wipe, publica a CRL e derruba só a sessão do aparelho',
      () async {
        final agora = DateTime.now().toUtc();
        await AcsRefreshToken.db.insertRow(
          session,
          AcsRefreshToken(
            userId: UuidValue.fromString(_acs),
            familyId: UuidValue.fromString('00000000-0000-4000-8000-00000000c5ff'),
            tokenHash: 'rev-wipe-hash',
            deviceId: _dev1,
            issuedAt: agora,
            idleExpiresAt: agora.add(const Duration(hours: 2)),
            absoluteExpiresAt: agora.add(const Duration(hours: 8)),
          ),
        );
        await AlertRuntime.instance.deviceWipeServiceFor(session).orderWipe(
          _operador,
          acsId: _acs,
          deviceId: _dev1,
          reason: DeviceWipeReason.lost,
        );

        final certs = await certificados();
        expect(certs.first.revocationReason, DeviceCertRevocationReason.wipe);
        expect(certs.last.revokedAt, isNull);
        await a1.caiu.future.timeout(const Duration(seconds: 2));
        expect(a2.caiu.isCompleted, isFalse);
        expect(crl.chamadas, 1);
        expect(await revogacoesAuditadas(), ['device_cert_revoked:wipe']);
      },
    );

    group('trilha que falha depois da revogação confirmada', () {
      DeviceRevocationEffects efeitos() =>
          AlertRuntime.instance.deviceRevocationEffectsFor(session);

      AdminAccountService contas() {
        final credenciais = OrmAcsCredentialStore(session: () => session);
        return AdminAccountService(
          store: OrmAdminAccountStore(session: () => session),
          credentials: credenciais,
          totpStore: credenciais,
          activationStore: OrmAcsCredentialStore(
            session: () => session,
            staff: true,
          ),
          hasher: const Argon2PasswordHasher(),
          audit: _TrilhaQuebrada(),
          deviceRevocations: efeitos(),
        );
      }

      test(
        'setAcsActive(false): a falha da trilha ainda publica a CRL e derruba',
        () async {
          await expectLater(
            contas().setAcsActive(_operador, acsId: _acs, active: false),
            throwsA(isA<StateError>()),
          );
          expect((await certificados()).every((c) => c.revokedAt != null), isTrue);
          await Future.wait([
            a1.caiu.future,
            a2.caiu.future,
          ]).timeout(const Duration(seconds: 2));
          expect(crl.chamadas, 1);
        },
      );

      test(
        'setAcsMicroArea: a falha da trilha ainda publica a CRL e derruba',
        () async {
          await expectLater(
            contas().setAcsMicroArea(_operador, acsId: _acs, microAreaId: _ma2),
            throwsA(isA<StateError>()),
          );
          await Future.wait([
            a1.caiu.future,
            a2.caiu.future,
          ]).timeout(const Duration(seconds: 2));
          expect(crl.chamadas, 1);
        },
      );

      test(
        'orderWipe: a falha da trilha ainda publica a CRL e derruba',
        () async {
          final agora = DateTime.now().toUtc();
          await AcsRefreshToken.db.insertRow(
            session,
            AcsRefreshToken(
              userId: UuidValue.fromString(_acs),
              familyId: UuidValue.fromString(
                '00000000-0000-4000-8000-00000000c5fe',
              ),
              tokenHash: 'rev-wipe-trilha',
              deviceId: _dev1,
              issuedAt: agora,
              idleExpiresAt: agora.add(const Duration(hours: 2)),
              absoluteExpiresAt: agora.add(const Duration(hours: 8)),
            ),
          );
          final servico = DeviceWipeService(
            // A revogação e a linha dela vão na transação do pedido (trilha
            // real); quem falha é a linha `wipe_ordered`, depois do commit.
            store: OrmDeviceWipeStore(
              session: () => session,
              appendAudit: OrmAuditTrail(
                session: () => session,
                chainSecret: AlertRuntime.instance.config.auditChainSecret,
              ).recordInTransaction,
            ),
            accounts: OrmAdminAccountStore(session: () => session),
            audit: _TrilhaQuebrada(),
            deviceRevocations: efeitos(),
          );
          await expectLater(
            servico.orderWipe(
              _operador,
              acsId: _acs,
              deviceId: _dev1,
              reason: DeviceWipeReason.lost,
            ),
            throwsA(isA<StateError>()),
          );
          expect(
            (await certificados()).first.revocationReason,
            DeviceCertRevocationReason.wipe,
          );
          await a1.caiu.future.timeout(const Duration(seconds: 2));
          expect(crl.chamadas, 1);
        },
      );
    });

    test('setAcsMicroArea para a mesma microárea não revoga', () async {
      await AlertRuntime.instance
          .adminAccountServiceFor(session)
          .setAcsMicroArea(_operador, acsId: _acs, microAreaId: _ma1);

      expect((await certificados()).every((c) => c.revokedAt == null), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(broker.takenOver, isEmpty);
      expect(crl.chamadas, 0);
    });
  });
}
