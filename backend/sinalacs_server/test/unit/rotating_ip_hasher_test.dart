import 'package:sinalacs_server/src/infrastructure/crypto/rotating_ip_hasher.dart';
import 'package:test/test.dart';

void main() {
  group('RotatingIpHasher', () {
    test('o mesmo IP no mesmo dia produz o mesmo hash (correlação da janela)', () {
      final hasher = RotatingIpHasher(
        secret: 'segredo-de-teste',
        clock: () => DateTime.utc(2026, 10, 7, 14, 0, 0),
      );

      expect(hasher.hash('203.0.113.7'), hasher.hash('203.0.113.7'));
    });

    test('a chave roda entre dias: o mesmo IP muda de hash no dia seguinte', () {
      final dia7 = RotatingIpHasher(
        secret: 'segredo-de-teste',
        clock: () => DateTime.utc(2026, 10, 7, 23, 59, 59),
      );
      final dia8 = RotatingIpHasher(
        secret: 'segredo-de-teste',
        clock: () => DateTime.utc(2026, 10, 8, 0, 0, 0),
      );

      expect(dia7.hash('203.0.113.7'), isNot(dia8.hash('203.0.113.7')));
    });

    test('a derivação é determinística: voltar ao dia anterior reencontra o hash', () {
      final dia7DeManha = RotatingIpHasher(
        secret: 'segredo-de-teste',
        clock: () => DateTime.utc(2026, 10, 7, 8, 0, 0),
      );
      final dia8 = RotatingIpHasher(
        secret: 'segredo-de-teste',
        clock: () => DateTime.utc(2026, 10, 8, 12, 0, 0),
      );
      final dia7DeNoite = RotatingIpHasher(
        secret: 'segredo-de-teste',
        clock: () => DateTime.utc(2026, 10, 7, 20, 0, 0),
      );

      final hashNoDia7 = dia7DeManha.hash('203.0.113.7');
      dia8.hash('203.0.113.7'); // roda a chave para o dia 8
      expect(dia7DeNoite.hash('203.0.113.7'), hashNoDia7);
    });

    test('IPs diferentes produzem hashes diferentes', () {
      final hasher = RotatingIpHasher(
        secret: 'segredo-de-teste',
        clock: () => DateTime.utc(2026, 10, 7),
      );

      expect(hasher.hash('203.0.113.7'), isNot(hasher.hash('198.51.100.9')));
    });

    test('o resultado tem 64 caracteres hexadecimais', () {
      final hasher = RotatingIpHasher(
        secret: 'segredo-de-teste',
        clock: () => DateTime.utc(2026, 10, 7),
      );

      expect(hasher.hash('203.0.113.7'), matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('um segredo diferente produz um hash diferente', () {
      final a = RotatingIpHasher(
        secret: 'segredo-a',
        clock: () => DateTime.utc(2026, 10, 7),
      );
      final b = RotatingIpHasher(
        secret: 'segredo-b',
        clock: () => DateTime.utc(2026, 10, 7),
      );

      expect(a.hash('203.0.113.7'), isNot(b.hash('203.0.113.7')));
    });

    test('segredo vazio é recusado em vez de produzir hash sem chave', () {
      expect(() => RotatingIpHasher(secret: ''), throwsA(isA<ArgumentError>()));
      expect(
        () => RotatingIpHasher(secret: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
