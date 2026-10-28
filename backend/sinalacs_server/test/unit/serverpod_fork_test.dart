import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

/// O fork pinado do Serverpod (#90, `backend/patches/README.md`) expõe o
/// gancho que o 3.4.13 do pub.dev não tem. Se o `dependency_overrides` cair,
/// este arquivo deixa de compilar — antes de o backend subir em TLS sem exigir
/// o certificado do Traefik.
void main() {
  test('Serverpod exporta ApiServerAdapterFactory (fork pinado, #90)', () {
    ApiServerAdapterFactory? f;
    expect(f, isNull);
  });
}
