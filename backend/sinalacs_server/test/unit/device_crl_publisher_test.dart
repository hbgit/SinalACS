import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/devices/device_certificate_service.dart';
import 'package:sinalacs_server/src/config/device_ca_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/pki/device_crl_publisher.dart';
import 'package:sinalacs_server/src/infrastructure/pki/openssl_device_ca.dart';
import 'package:test/test.dart';

import '../support/device_ca_fixture.dart';

/// Publicador da CRL dos aparelhos (#94): grava atômica e validada contra a CA,
/// single-flight e, na falha, nova tentativa com recuo exponencial até
/// conseguir. A parte de arquivo roda o `openssl` de verdade contra uma CA
/// descartável; a do recuo usa relógio e timers falsos (`fake_async`) com o
/// `openssl` e o disco substituídos.
const _microArea = '00000000-0000-4000-8000-000000000003';
final _agora = DateTime.utc(2026, 10, 27, 12);

DeviceCertificate _cert(String serialHex, {required DateTime notAfter}) =>
    DeviceCertificate(
      userId: UuidValue.fromString('00000000-0000-4000-8000-00000000c001'),
      deviceId: 'aparelho-$serialHex',
      microAreaId: UuidValue.fromString(_microArea),
      serial: serialHex,
      fingerprintSha256: 'f' * 64,
      notBefore: _agora.subtract(const Duration(days: 1)),
      notAfter: notAfter,
      issuedAt: _agora.subtract(const Duration(days: 1)),
      revokedAt: _agora.subtract(const Duration(hours: 1)),
      revocationReason: DeviceCertRevocationReason.renewed,
    );

/// Loja em memória: revogadas (o filtro "não vencidas" é o da loja real) e o
/// contador da CRL, que começa em 1000 como no banco.
class _Fonte implements DeviceCrlSource {
  final revogadas = <DeviceCertificate>[];
  var _numero = BigInt.from(999);

  @override
  Future<List<DeviceCertificate>> revokedUnexpired(DateTime now) async => [
    for (final c in revogadas)
      if (c.notAfter.isAfter(now)) c,
  ];

  @override
  Future<BigInt> nextCrlNumber() async => _numero += BigInt.one;
}

void main() {
  group('com o openssl e o disco de verdade', () {
    late DeviceCaFixture ca;
    late _Fonte fonte;
    late List<String> logs;

    setUp(() async {
      ca = await DeviceCaFixture.create();
      fonte = _Fonte();
      logs = [];
    });
    tearDown(() => ca.dispose());

    DeviceCrlPublisher publicador({
      BuildCrl? buildCrl,
    }) => DeviceCrlPublisher(
      config: ca.config(),
      source: fonte,
      buildCrl: buildCrl,
      log: logs.add,
      clock: () => _agora,
    );

    List<String> temporarios() => [
      for (final f in ca.dir.listSync())
        if (f.path.contains('crl.pem.tmp-')) f.path,
    ];

    test(
      'publica CRL válida com as revogadas não vencidas e número crescente',
      () async {
        fonte.revogadas
          ..add(_cert('0a1b', notAfter: _agora.add(const Duration(days: 10))))
          ..add(_cert('0c0d', notAfter: _agora.subtract(const Duration(days: 1))));
        final p = publicador();
        await p.publish();
        expect(p.pendingSince, isNull);
        expect(await ca.crlVerifies(ca.crlPath), isTrue);
        final primeira = await ca.crlText(ca.crlPath);
        expect(primeira, contains('0A1B'));
        expect(primeira, isNot(contains('0C0D')), reason: 'a vencida sai da CRL');
        expect(primeira, contains('1000'));

        await p.publish();
        final segunda = await ca.crlText(ca.crlPath);
        expect(segunda, contains('1001'));
        // Só contagem e número no log; nunca serial.
        expect(logs.join('\n'), isNot(contains('0a1b')));
        await p.close();
      },
    );

    test('duas chamadas concorrentes resultam em uma CRL final válida', () async {
      fonte.revogadas.add(
        _cert('0a1b', notAfter: _agora.add(const Duration(days: 10))),
      );
      final p = publicador();
      await Future.wait([p.publish(), p.publish(), p.publish()]);
      expect(p.pendingSince, isNull);
      expect(await ca.crlVerifies(ca.crlPath), isTrue);
      expect(temporarios(), isEmpty);
      await p.close();
    });

    test('falha do openssl não deixa temporário nem corrompe a anterior', () async {
      final p = publicador();
      await p.publish();
      final anterior = await File(ca.crlPath).readAsString();

      // openssl que "sai com 1" na geração.
      final quebrado = publicador(
        buildCrl: ({required revoked, required crlNumber, required now, required days}) =>
            throw StateError('openssl ca saiu com 1: segredo-no-stderr'),
      );
      await quebrado.publish();
      expect(quebrado.pendingSince, isNotNull);
      expect(await File(ca.crlPath).readAsString(), anterior);
      expect(temporarios(), isEmpty);
      expect(logs.join('\n'), isNot(contains('segredo-no-stderr')));
      expect(logs.join('\n'), contains('StateError'));
      await quebrado.close();

      // openssl que devolve lixo: a validação recusa antes do `rename`.
      final lixo = publicador(
        buildCrl: ({required revoked, required crlNumber, required now, required days}) async =>
            '-----BEGIN X509 CRL-----\nnao-e-crl\n-----END X509 CRL-----\n',
      );
      await lixo.publish();
      expect(lixo.pendingSince, isNotNull);
      expect(await File(ca.crlPath).readAsString(), anterior);
      expect(temporarios(), isEmpty);
      await lixo.close();
      await p.close();
    });

    test(
      'CRL assinada por outra CA é recusada na validação (não substitui a anterior)',
      () async {
        final p = publicador();
        await p.publish();
        final anterior = await File(ca.crlPath).readAsString();

        final outra = await DeviceCaFixture.create(cn: 'outra-ca');
        addTearDown(outra.dispose);
        final daOutra = OpensslDeviceCa(outra.config());
        final intrusa = publicador(buildCrl: daOutra.buildCrl);
        await intrusa.publish();
        expect(intrusa.pendingSince, isNotNull);
        expect(await File(ca.crlPath).readAsString(), anterior);
        expect(await ca.crlVerifies(ca.crlPath), isTrue);
        expect(temporarios(), isEmpty);
        await intrusa.close();
        await p.close();
      },
    );
  });

  group('recuo depois da falha (relógio e timers falsos)', () {
    late _Fonte fonte;
    late List<Duration> tentativas;
    late List<String> gravadas;
    late List<String> logs;

    setUp(() {
      fonte = _Fonte();
      tentativas = [];
      gravadas = [];
      logs = [];
    });

    /// Publicador cujo `openssl` falha nas primeiras [falhas] tentativas.
    DeviceCrlPublisher publicador(FakeAsync async, {required int falhas}) {
      var restantes = falhas;
      return DeviceCrlPublisher(
        config: _semDisco,
        source: fonte,
        buildCrl: ({required revoked, required crlNumber, required now, required days}) async {
          tentativas.add(async.elapsed);
          if (restantes-- > 0) throw StateError('openssl saiu com 1');
          return 'PEM';
        },
        writeCrl: (path, pem) async => gravadas.add(pem),
        log: logs.add,
        clock: () => _agora.add(async.elapsed),
      );
    }

    test(
      'falha no publish → republica sozinho depois: 2 s, 4 s, e pendingSince volta a null',
      () {
        fakeAsync((async) {
          final p = publicador(async, falhas: 2);
          p.publish();
          async.flushMicrotasks();
          expect(p.pendingSince, _agora);
          expect(tentativas, [Duration.zero]);

          async.elapse(const Duration(seconds: 2));
          expect(tentativas, [Duration.zero, const Duration(seconds: 2)]);
          expect(p.pendingSince, _agora, reason: 'marca a primeira falha');
          expect(gravadas, isEmpty);

          async.elapse(const Duration(seconds: 4));
          expect(tentativas, [
            Duration.zero,
            const Duration(seconds: 2),
            const Duration(seconds: 6),
          ]);
          expect(gravadas, ['PEM']);
          expect(p.pendingSince, isNull);

          // Depois do sucesso, nada mais é agendado.
          async.elapse(const Duration(hours: 1));
          expect(tentativas, hasLength(3));
          p.close();
        });
      },
    );

    test('recuo nunca passa de 5 min', () {
      fakeAsync((async) {
        final p = publicador(async, falhas: 1 << 30);
        p.publish();
        async.elapse(const Duration(hours: 2));
        final intervalos = [
          for (var i = 1; i < tentativas.length; i++)
            tentativas[i] - tentativas[i - 1],
        ];
        expect(intervalos.take(4), [
          const Duration(seconds: 2),
          const Duration(seconds: 4),
          const Duration(seconds: 8),
          const Duration(seconds: 16),
        ]);
        expect(
          intervalos.every((d) => d <= const Duration(minutes: 5)),
          isTrue,
        );
        expect(intervalos.last, const Duration(minutes: 5));
        expect(p.pendingSince, _agora, reason: 'sem teto de tentativas');
        p.close();
      });
    });

    test('publish() durante a espera tenta na hora e zera o recuo', () {
      fakeAsync((async) {
        final p = publicador(async, falhas: 3);
        p.publish();
        async.elapse(const Duration(seconds: 2)); // 2ª falha; próxima em 4 s
        async.elapse(const Duration(seconds: 1));
        p.publish(); // t = 3 s: tenta na hora, falha; próxima em 2 s, não 8
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(tentativas, [
          Duration.zero,
          const Duration(seconds: 2),
          const Duration(seconds: 3),
          const Duration(seconds: 5),
        ]);
        expect(gravadas, ['PEM']);
        expect(p.pendingSince, isNull);
        p.close();
      });
    });

    test('publish durante uma tentativa que falha deixa um único timer pendente', () {
      fakeAsync((async) {
        // openssl lento (1 s) e sempre falhando: o segundo publish() chega
        // durante a primeira tentativa e fica enfileirado.
        final p = DeviceCrlPublisher(
          config: _semDisco,
          source: fonte,
          buildCrl: ({required revoked, required crlNumber, required now, required days}) async {
            tentativas.add(async.elapsed);
            await Future<void>.delayed(const Duration(seconds: 1));
            throw StateError('openssl saiu com 1');
          },
          writeCrl: (path, pem) async => gravadas.add(pem),
          log: logs.add,
          clock: () => _agora.add(async.elapsed),
        );
        p.publish();
        async.elapse(const Duration(milliseconds: 500));
        p.publish();
        // t = 1 s: a 1ª falha; a enfileirada roda e falha em t = 2 s.
        async.elapse(const Duration(milliseconds: 1500));
        expect(tentativas, [Duration.zero, const Duration(seconds: 1)]);
        expect(async.pendingTimers, hasLength(1));

        // Uma só cadeia de recuo: a próxima em 2 s (t = 4), depois 4 s.
        async.elapse(const Duration(seconds: 3));
        expect(tentativas.last, const Duration(seconds: 4));
        expect(async.pendingTimers, hasLength(1));
        async.elapse(const Duration(seconds: 1)); // falha em t = 5
        async.elapse(const Duration(seconds: 4)); // próxima em t = 9
        expect(tentativas, [
          Duration.zero,
          const Duration(seconds: 1),
          const Duration(seconds: 4),
          const Duration(seconds: 9),
        ]);

        p.close();
        async.elapse(const Duration(seconds: 1)); // a tentativa em voo termina
        expect(async.pendingTimers, isEmpty);
        expect(gravadas, isEmpty);
      });
    });

    test('close() cancela a tentativa pendente', () {
      fakeAsync((async) {
        final p = publicador(async, falhas: 1);
        p.publish();
        async.flushMicrotasks();
        p.close();
        async.elapse(const Duration(minutes: 10));
        expect(tentativas, [Duration.zero]);
        expect(gravadas, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}

/// Configuração para os testes que não tocam o disco (`writeCrl` falso).
const _semDisco = DeviceCaConfig(
  caCertPath: '/nao-usado/ca.crt',
  caKeyPath: '/nao-usado/ca.key',
  crlPath: '/nao-usado/crl.pem',
  certDays: 30,
  crlDays: 30,
);
