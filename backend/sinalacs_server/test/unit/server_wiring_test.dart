import 'dart:io';

import 'package:test/test.dart';

/// O TLS do apiServer e a exigência do certificado de cliente são ligados
/// JUNTOS em `lib/server.dart` (#90): o `SecurityContextConfig` e o
/// `apiServerAdapterFactory` saem do mesmo `apiTls`. Separá-los é o defeito que
/// este teste acusa — um `SecurityContextConfig` sem a fábrica subiria em TLS
/// sem exigir o certificado do Traefik, com todas as sondas de "está cifrado"
/// verdes. Lê o texto-fonte, como `endpoint_auth_posture_test.dart`.
void main() {
  test('Serverpod recebe SecurityContextConfig e mtlsApiServerAdapter do mesmo apiTls', () {
    final fonte = File('lib/server.dart').readAsStringSync();
    final construtor = RegExp(r'Serverpod\(\s*args,[\s\S]*?\);').firstMatch(fonte);
    expect(construtor, isNotNull, reason: 'construção do Serverpod não encontrada');
    final bloco = construtor!.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      bloco,
      contains('SecurityContextConfig(apiServer: apiTls.toSecurityContext())'),
    );
    expect(
      bloco,
      contains('apiServerAdapterFactory: apiTls == null ? null : mtlsApiServerAdapter'),
    );
  });
}
