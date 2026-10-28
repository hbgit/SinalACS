import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/devices/device_certificate_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/device_ca_fixture.dart';
import 'test_tools/serverpod_test_tools.dart';

/// `devices.issueCertificate` (#94) pelo endpoint, com tokens reais, Postgres
/// real e o `openssl` real contra uma CA descartável. Dados sintéticos; ids
/// próprios (`...c4xx`). A CRL do processo é trocada por um contador: quem
/// prova a publicação é `device_certificate_service_test.dart`.
const _ubs = '00000000-0000-4000-8000-00000000c401';
const _ma = '00000000-0000-4000-8000-00000000c402';
const _acs = '00000000-0000-4000-8000-00000000c403';
const _aparelho = 'aparelho-cert-ep';

class _CrlContada implements CrlPublication {
  int chamadas = 0;

  @override
  Future<void> publish({DateTime? now}) async => chamadas++;
}

Future<void> _seed(Session s) async {
  await Ubs.db.insertRow(
    s,
    Ubs(
      id: UuidValue.fromString(_ubs),
      name: 'UBS Cert EP',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    s,
    MicroArea(
      id: UuidValue.fromString(_ma),
      name: 'Microárea Cert EP',
      ubsId: UuidValue.fromString(_ubs),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  await User.db.insertRow(
    s,
    User(
      id: UuidValue.fromString(_acs),
      cpfHash: 'cert-ep-$_acs',
      name: 'Usuário sintético',
      birthDate: DateTime.utc(1980),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_ma),
      createdAt: now,
      updatedAt: now,
    ),
  );
}

String _token({UserRole role = UserRole.acs}) =>
    AlertRuntime.instance.auth.issueToken(
      AuthenticatedUser(
        id: _acs,
        role: role,
        microAreaId: _ma,
        deviceId: _aparelho,
      ),
    );

void main() {
  late DeviceCaFixture ca;
  setUpAll(() async => ca = await DeviceCaFixture.create());
  tearDownAll(() => ca.dispose());

  withServerpod('Dado o endpoint de emissão do certificado do aparelho (#94)', (
    sessionBuilder,
    endpoints,
  ) {
    late _CrlContada crl;

    setUp(() async {
      await _seed(sessionBuilder.build());
      crl = _CrlContada();
      AlertRuntime.instance
        ..overrideDeviceCa(ca.config())
        ..overrideDeviceCrlPublication(crl);
    });
    tearDown(() {
      AlertRuntime.instance
        ..resetDeviceCa()
        ..overrideDeviceCrlPublication(null);
    });

    test('devolve certificatePem verificável contra a CA e serverNow', () async {
      final antes = DateTime.now().toUtc();
      final r = await endpoints.devices.issueCertificate(
        sessionBuilder,
        accessToken: _token(),
        csrPem: await ca.csr(cn: _ma),
      );
      expect((await ca.verify(r.certificatePem)).exitCode, 0);
      expect(
        await ca.x509Text(r.certificatePem),
        contains('URI:urn:sinalacs:device:$_aparelho'),
      );
      expect(r.serverNow.isBefore(antes.subtract(const Duration(seconds: 2))), isFalse);
      expect(r.notAfter.isAfter(r.serverNow), isTrue);
      expect(crl.chamadas, 1);
    });

    test('StateError vira AlertPermissionException', () async {
      await expectLater(
        endpoints.devices.issueCertificate(
          sessionBuilder,
          accessToken: _token(role: UserRole.patient),
          csrPem: await ca.csr(cn: _ma),
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('ArgumentError vira AlertValidationException', () async {
      await expectLater(
        endpoints.devices.issueCertificate(
          sessionBuilder,
          accessToken: _token(),
          csrPem: await ca.csr(cn: _ma, rsa: true),
        ),
        throwsA(isA<AlertValidationException>()),
      );
    });

    test(
      'sem DeviceCaConfig → AlertPermissionException com a mensagem fixa',
      () async {
        AlertRuntime.instance.overrideDeviceCa(null);
        await expectLater(
          endpoints.devices.issueCertificate(
            sessionBuilder,
            accessToken: _token(),
            csrPem: await ca.csr(cn: _ma),
          ),
          throwsA(
            isA<AlertPermissionException>().having(
              (e) => e.message,
              'message',
              'emissão de certificado indisponível neste ambiente',
            ),
          ),
        );
        expect(crl.chamadas, 0);
      },
    );
  });
}
