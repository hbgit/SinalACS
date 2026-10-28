import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/devices/device_certificate_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/pki/crl_reload_watcher.dart';
import 'package:test/test.dart';

/// A derrubada da sessão MQTT do aparelho revogado só depois de o broker
/// recarregar a CRL (#94, Task 7a).
///
/// A CRL só vale no PRÓXIMO handshake: derrubar antes da recarga deixa o
/// `mqtt_client` do app reconectar em milissegundos com o certificado revogado
/// (medido no e2e). O sidecar do broker grava `crl.loaded` com o sha256 da
/// `crl.pem` que acabou de sinalizar; `afterCommit` espera esse marcador bater
/// com o sha256 que a publicação devolveu. Relógio e timers falsos
/// (`fake_async`); o marcador é um arquivo de verdade num temporário.
const _acs = '00000000-0000-4000-8000-00000000c001';
const _serial = '0a1b2c3d';
final _agora = DateTime.utc(2026, 10, 28, 12);

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

DeviceCertificate _revogado() => DeviceCertificate(
  userId: UuidValue.fromString(_acs),
  deviceId: 'aparelho-a',
  microAreaId: UuidValue.fromString('00000000-0000-4000-8000-000000000003'),
  serial: _serial,
  fingerprintSha256: 'f' * 64,
  notBefore: _agora.subtract(const Duration(days: 1)),
  notAfter: _agora.add(const Duration(days: 29)),
  issuedAt: _agora.subtract(const Duration(days: 1)),
  revokedAt: _agora,
  revocationReason: DeviceCertRevocationReason.wipe,
);

/// Só `revokedWith` importa aqui; o resto da loja não é chamado.
class _Loja implements DeviceCertificateStore {
  @override
  Future<List<DeviceCertificate>> revokedWith({
    required DeviceCertRevocationReason reason,
    required DateTime at,
    String? userId,
    String? deviceId,
  }) async => [_revogado()];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Publicação que devolve [sha] (`null` = falhou e está em recuo).
class _Crl implements CrlPublication {
  _Crl(this.sha);
  final String? sha;
  int chamadas = 0;

  @override
  Future<String?> publish({DateTime? now}) async {
    chamadas++;
    return sha;
  }
}

class _Kicker implements SessionKicker {
  _Kicker(this.async);
  final FakeAsync async;
  final derrubadas = <(String, Duration)>[];

  @override
  Future<void> kick(String clientId, {Duration? timeout}) async =>
      derrubadas.add((clientId, async.elapsed));
}

void main() {
  late Directory dir;
  late String crlPath;
  late File marcador;
  late List<String> logs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('crl-reload-');
    crlPath = '${dir.path}/crl.pem';
    marcador = File('${dir.path}/crl.loaded');
    logs = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final idA = deviceMqttClientId(acsId: _acs, deviceId: 'aparelho-a');

  DeviceRevocationEffects efeitos(_Crl crl, _Kicker kicker) =>
      DeviceRevocationEffects(
        store: _Loja(),
        crl: crl,
        kicker: kicker,
        crlReload: CrlReloadWatcher(crlPath: crlPath),
        log: logs.add,
      );

  void revogar(DeviceRevocationEffects e) => unawaited(
    e.afterCommit(reason: DeviceCertRevocationReason.wipe, at: _agora),
  );

  test('afterCommit espera o marcador bater antes do kick', () {
    fakeAsync((async) {
      final kicker = _Kicker(async);
      // A recarga anterior: o marcador ainda aponta para a CRL velha.
      marcador.writeAsStringSync('${_sha('CRL velha')}\n');
      revogar(efeitos(_Crl(_sha('CRL nova')), kicker));

      async.elapse(const Duration(seconds: 2));
      expect(kicker.derrubadas, isEmpty, reason: 'o broker ainda não recarregou');

      marcador.writeAsStringSync('${_sha('CRL nova')}\n');
      async.elapse(const Duration(milliseconds: 250));
      expect(kicker.derrubadas, [(idA, const Duration(milliseconds: 2250))]);
      expect(logs, isEmpty);
    });
  });

  test('marcador atrasado 3 s → kick depois de 3 s', () {
    fakeAsync((async) {
      final kicker = _Kicker(async);
      revogar(efeitos(_Crl(_sha('CRL nova')), kicker));
      Timer(const Duration(seconds: 3), () {
        marcador.writeAsStringSync(_sha('CRL nova'));
      });

      async.elapse(const Duration(milliseconds: 2999));
      expect(kicker.derrubadas, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(kicker.derrubadas, hasLength(1));
      final quando = kicker.derrubadas.single.$2;
      expect(quando, greaterThanOrEqualTo(const Duration(seconds: 3)));
      expect(quando, lessThanOrEqualTo(const Duration(milliseconds: 3250)));
    });
  });

  test('marcador nunca bate → kick após 15 s com aviso', () {
    fakeAsync((async) {
      final kicker = _Kicker(async);
      marcador.writeAsStringSync(_sha('CRL velha'));
      revogar(efeitos(_Crl(_sha('CRL nova')), kicker));

      async.elapse(const Duration(milliseconds: 14999));
      expect(kicker.derrubadas, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(kicker.derrubadas, [(idA, const Duration(seconds: 15))]);
      expect(logs, hasLength(1));
      expect(logs.single, contains('15 s'));
      // Só o tipo do evento: nem serial nem client id.
      expect(logs.single, isNot(contains(_serial)));
      expect(logs.single, isNot(contains(_acs)));
    });
  });

  test('publish em recuo → kick imediato', () {
    fakeAsync((async) {
      final kicker = _Kicker(async);
      final crl = _Crl(null);
      revogar(efeitos(crl, kicker));
      async.flushMicrotasks();

      expect(crl.chamadas, 1);
      expect(kicker.derrubadas, [(idA, Duration.zero)]);
      expect(logs, hasLength(1));
      expect(logs.single, isNot(contains(_serial)));
      expect(logs.single, isNot(contains(_acs)));
    });
  });

  test(
    'uma publicação mais nova já recarregada também vale (ela contém a serial)',
    () {
      fakeAsync((async) {
        final kicker = _Kicker(async);
        // Outra revogação regravou a crl.pem depois da nossa, e o sidecar só
        // viu a mais nova: o marcador nunca terá o nosso sha256.
        File(crlPath).writeAsStringSync('CRL mais nova');
        marcador.writeAsStringSync(_sha('CRL mais nova'));
        revogar(efeitos(_Crl(_sha('CRL nova')), kicker));
        async.flushMicrotasks();

        expect(kicker.derrubadas, [(idA, Duration.zero)]);
        expect(logs, isEmpty);
      });
    },
  );

  test('sem o observador da recarga (CA sem sidecar no teste), derruba na hora', () {
    fakeAsync((async) {
      final kicker = _Kicker(async);
      unawaited(
        DeviceRevocationEffects(
          store: _Loja(),
          crl: _Crl(_sha('CRL nova')),
          kicker: kicker,
          log: logs.add,
        ).afterCommit(reason: DeviceCertRevocationReason.wipe, at: _agora),
      );
      async.flushMicrotasks();
      expect(kicker.derrubadas, [(idA, Duration.zero)]);
      expect(logs, isEmpty);
    });
  });
}
