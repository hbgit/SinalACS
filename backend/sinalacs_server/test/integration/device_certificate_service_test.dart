import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/devices/device_certificate_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_device_certificate_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_refresh_token_store.dart';
import 'package:sinalacs_server/src/infrastructure/pki/device_crl_publisher.dart';
import 'package:sinalacs_server/src/infrastructure/pki/openssl_device_ca.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/device_ca_fixture.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Emissão do certificado de cliente MQTT do aparelho (#94) contra Postgres
/// real e o `openssl` real, com uma CA descartável em `Directory.systemTemp`.
/// Dados sintéticos; ids próprios (`...c3xx`).
const _ubs = '00000000-0000-4000-8000-00000000c301';
const _ma = '00000000-0000-4000-8000-00000000c302';
const _acs = '00000000-0000-4000-8000-00000000c303';
const _admin = '00000000-0000-4000-8000-00000000c304';
const _ma2 = '00000000-0000-4000-8000-00000000c305';
// UUID minúsculo, como o app gera: a emissão recusa qualquer outro formato (C1).
const _aparelho = '00000000-0000-4000-8000-00000000c3d1';

Future<void> _seed(Session s) async {
  await Ubs.db.insertRow(
    s,
    Ubs(
      id: UuidValue.fromString(_ubs),
      name: 'UBS Cert',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  for (final ma in [_ma, _ma2]) {
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(ma),
        name: 'Microárea Cert $ma',
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
        cpfHash: 'cert-$id',
        name: 'Usuário sintético',
        birthDate: DateTime.utc(1980),
        role: role,
        microAreaId: UuidValue.fromString(_ma),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  // A emissão relê a conta (C2): sem linha em `acs`, ninguém é ACS.
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acs),
      enrollmentId: 'ACS-CERT-C3',
      ubsId: UuidValue.fromString(_ubs),
      active: true,
    ),
  );
}

AuthenticatedUser _acsUser({
  UserRole role = UserRole.acs,
  String? microAreaId = _ma,
  String deviceId = _aparelho,
}) => AuthenticatedUser(
  id: _acs,
  role: role,
  microAreaId: microAreaId,
  deviceId: deviceId,
);

/// Hex como o `openssl` imprime a serial: maiúsculo, número par de dígitos.
String _serialOpenssl(String serialHex) {
  final h = BigInt.parse(serialHex, radix: 16).toRadixString(16).toUpperCase();
  return h.length.isOdd ? '0$h' : h;
}

void main() {
  late DeviceCaFixture ca;
  setUpAll(() async => ca = await DeviceCaFixture.create());
  tearDownAll(() => ca.dispose());

  withServerpod('Dada a emissão do certificado do aparelho (#94)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmDeviceCertificateStore store;
    late DeviceCrlPublisher crl;
    late DeviceCertificateService servico;

    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      store = OrmDeviceCertificateStore(
        session: () => session,
        appendAudit: OrmAuditTrail(
          session: () => session,
          chainSecret: AlertRuntime.instance.config.auditChainSecret,
        ).recordInTransaction,
      );
      crl = DeviceCrlPublisher(
        config: ca.config(),
        source: store,
        log: (_) {},
      );
      servico = DeviceCertificateService(
        store: store,
        ca: OpensslDeviceCa(ca.config()),
        certDays: 30,
        ensureDeviceNotMarked: AlertRuntime.instance
            .deviceWipeServiceFor(session)
            .ensureDeviceNotMarked,
        findAccount: OrmRefreshTokenStore(session: () => session).findAccount,
        crl: crl,
      );
    });
    tearDown(() => crl.close());

    test(
      'emite para ACS com microárea e grava a linha com o deviceId da sessão',
      () async {
        final antes = DateTime.now().toUtc();
        final r = await servico.issue(_acsUser(), await ca.csr(cn: _ma));

        expect((await ca.verify(r.certificatePem)).exitCode, 0);
        final txt = await ca.x509Text(r.certificatePem);
        expect(txt, contains('CN = $_ma'));
        expect(txt, contains('URI:urn:sinalacs:device:$_aparelho'));
        expect(txt, contains('URI:urn:sinalacs:acs:$_acs'));
        expect(txt, contains('serial=${_serialOpenssl(r.serial)}'));
        expect(r.serial, matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(r.notAfter.difference(r.serverNow), const Duration(days: 30));
        expect(r.serverNow.isBefore(antes.subtract(const Duration(seconds: 2))), isFalse);

        final linha = (await DeviceCertificate.db.find(session)).single;
        expect(linha.deviceId, _aparelho);
        expect(linha.userId.toString(), _acs);
        expect(linha.microAreaId.toString(), _ma);
        expect(linha.serial, r.serial);
        expect(linha.fingerprintSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(linha.notBefore, r.serverNow.subtract(const Duration(hours: 1)));
        expect(linha.revokedAt, isNull);
        expect((await store.activeFor(_aparelho)).single.serial, r.serial);
      },
    );

    test(
      'segunda emissão revoga a anterior como renewed e a CRL publicada contém a serial antiga',
      () async {
        final primeira = await servico.issue(_acsUser(), await ca.csr(cn: _ma));
        final segunda = await servico.issue(_acsUser(), await ca.csr(cn: _ma));

        final linhas = await DeviceCertificate.db.find(session);
        final antiga = linhas.firstWhere((c) => c.serial == primeira.serial);
        final nova = linhas.firstWhere((c) => c.serial == segunda.serial);
        expect(antiga.revokedAt, isNotNull);
        expect(antiga.revocationReason, DeviceCertRevocationReason.renewed);
        expect(nova.revokedAt, isNull);

        expect(crl.pendingSince, isNull);
        expect(await ca.crlVerifies(ca.crlPath), isTrue);
        final texto = await ca.crlText(ca.crlPath);
        expect(texto, contains(_serialOpenssl(primeira.serial)));
        expect(texto, isNot(contains(_serialOpenssl(segunda.serial))));
      },
    );

    test('recusa papel patient', () async {
      await expectLater(
        servico.issue(_acsUser(role: UserRole.patient), await ca.csr(cn: _ma)),
        throwsA(isA<StateError>()),
      );
      expect(await DeviceCertificate.db.count(session), 0);
    });

    test('recusa ACS sem microárea', () async {
      await expectLater(
        servico.issue(_acsUser(microAreaId: null), await ca.csr(cn: _ma)),
        throwsA(isA<StateError>()),
      );
    });

    test('recusa deviceIdAbsent', () async {
      await expectLater(
        servico.issue(
          _acsUser(deviceId: InstitutionalAuthService.deviceIdAbsent),
          await ca.csr(cn: _ma),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('recusa aparelho com pedido de wipe pendente com a exceção tipada (I2)', () async {
      await DeviceWipeOrder.db.insertRow(
        session,
        DeviceWipeOrder(
          deviceId: _aparelho,
          targetUserId: UuidValue.fromString(_acs),
          requestedBy: UuidValue.fromString(_admin),
          reason: DeviceWipeReason.lost,
          requestedAt: DateTime.now().toUtc(),
        ),
      );
      await expectLater(
        servico.issue(_acsUser(), await ca.csr(cn: _ma)),
        throwsA(isA<DeviceWipeRequiredException>()),
      );
      expect(await DeviceCertificate.db.count(session), 0);
    });

    test('recusa CN diferente da microárea da sessão', () async {
      await expectLater(
        servico.issue(
          _acsUser(),
          await ca.csr(cn: '00000000-0000-4000-8000-00000000c3ff'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('recusa RSA', () async {
      await expectLater(
        servico.issue(_acsUser(), await ca.csr(cn: _ma, rsa: true)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('recusa CSR malformado', () async {
      await expectLater(
        servico.issue(_acsUser(), 'não é um CSR'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('sexta emissão na mesma hora é recusada como limite, não como pedido inválido (I1)', () async {
      for (var i = 0; i < 5; i++) {
        await servico.issue(_acsUser(), await ca.csr(cn: _ma));
      }
      await expectLater(
        servico.issue(_acsUser(), await ca.csr(cn: _ma)),
        throwsA(isA<DeviceCertificateRateLimited>()),
      );
      expect(await DeviceCertificate.db.count(session), 5);
    });

    group('C1: deviceId e id do ACS vão ao SAN, só no formato UUID', () {
      for (final malicioso in [
        r'${ENV::JWT_SECRET}',
        r'$HOME',
        'aparelho#x',
        'aparelho-cert-c3',
        '00000000-0000-4000-8000-00000000C3D1',
      ]) {
        test('deviceId "$malicioso" → ArgumentError, sem linha gravada', () async {
          await expectLater(
            servico.issue(_acsUser(deviceId: malicioso), await ca.csr(cn: _ma)),
            throwsA(isA<ArgumentError>()),
          );
          expect(await DeviceCertificate.db.count(session), 0);
        });
      }

      test('id do ACS fora do formato → ArgumentError', () async {
        await expectLater(
          servico.issue(
            const AuthenticatedUser(
              id: r'${ENV::JWT_SECRET}',
              role: UserRole.acs,
              microAreaId: _ma,
              deviceId: _aparelho,
            ),
            await ca.csr(cn: _ma),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('C2: a emissão relê a conta no banco, não confia só no JWT', () {
      test('desativar → emitir com o token anterior é recusado', () async {
        final acs = (await Acs.db.findById(session, UuidValue.fromString(_acs)))!;
        await Acs.db.updateRow(session, acs.copyWith(active: false));

        await expectLater(
          servico.issue(_acsUser(), await ca.csr(cn: _ma)),
          throwsA(isA<StateError>()),
        );
        expect(await DeviceCertificate.db.count(session), 0);
      });

      test('trocar a microárea → emitir com o token anterior (CN antigo) é recusado '
          'pedindo renovação da sessão', () async {
        final u = (await User.db.findById(session, UuidValue.fromString(_acs)))!;
        await User.db.updateRow(
          session,
          u.copyWith(microAreaId: UuidValue.fromString(_ma2)),
        );

        await expectLater(
          servico.issue(_acsUser(), await ca.csr(cn: _ma)),
          throwsA(
            isA<DeviceCertificateSessionStale>()
                .having((e) => e, 'é ArgumentError', isA<ArgumentError>())
                .having((e) => '${e.message}', 'message', contains('renovada')),
          ),
        );
        expect(await DeviceCertificate.db.count(session), 0);
      });

      test('token com a microárea nova e CSR com o CN novo → emite com o CN do banco',
          () async {
        final u = (await User.db.findById(session, UuidValue.fromString(_acs)))!;
        await User.db.updateRow(
          session,
          u.copyWith(microAreaId: UuidValue.fromString(_ma2)),
        );

        final r = await servico.issue(
          _acsUser(microAreaId: _ma2),
          await ca.csr(cn: _ma2),
        );
        expect(await ca.x509Text(r.certificatePem), contains('CN = $_ma2'));
        final linha = (await DeviceCertificate.db.find(session)).single;
        expect(linha.microAreaId.toString(), _ma2);
      });

      test('token com a microárea nova mas CSR com o CN antigo → ArgumentError', () async {
        final u = (await User.db.findById(session, UuidValue.fromString(_acs)))!;
        await User.db.updateRow(
          session,
          u.copyWith(microAreaId: UuidValue.fromString(_ma2)),
        );
        await expectLater(
          servico.issue(_acsUser(microAreaId: _ma2), await ca.csr(cn: _ma)),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e,
              'não é a recusa de sessão',
              isNot(isA<DeviceCertificateSessionStale>()),
            ),
          ),
        );
      });

      test('usuário sem linha em acs (papel acs só no token) é recusado', () async {
        await expectLater(
          servico.issue(
            const AuthenticatedUser(
              id: _admin,
              role: UserRole.acs,
              microAreaId: _ma,
              deviceId: _aparelho,
            ),
            await ca.csr(cn: _ma),
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    test('auditoria device_cert_issued com a serial', () async {
      final primeira = await servico.issue(_acsUser(), await ca.csr(cn: _ma));
      await servico.issue(_acsUser(), await ca.csr(cn: _ma));

      final linhas = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('device_certificate'),
        orderBy: (t) => t.sequence,
      );
      expect(linhas.map((l) => l.result), [
        'device_cert_issued',
        'device_cert_revoked:renewed',
        'device_cert_issued',
      ]);
      expect(linhas.every((l) => l.userId.toString() == _acs), isTrue);
      expect(
        linhas.first.resourceId.toString(),
        DeviceCertificateService.serialAsResourceId(primeira.serial),
      );
      expect(
        linhas[1].resourceId.toString(),
        DeviceCertificateService.serialAsResourceId(primeira.serial),
      );
    });
  });
}
