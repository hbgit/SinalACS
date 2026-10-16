import 'dart:io';

/// TLS do apiServer do Serverpod: o trecho Traefik → backend (RNF04, issue #78).
///
/// Lido de `API_TLS_CERT_PATH` e `API_TLS_KEY_PATH`, que vêm juntos ou não vêm.
/// São opcionais porque há dois caminhos de implantação com bordas diferentes:
/// na stack local o Traefik termina o TLS do cliente e abre um segundo TLS até
/// o backend, que precisa deste certificado; no Render (`backend/DEPLOY.md`) o
/// proxy da plataforma termina o TLS e fala HTTP com o container, e um listener
/// TLS aqui só quebraria o healthcheck dele. Sem as duas variáveis o servidor
/// segue em HTTP; com só uma, o boot falha, para um erro de digitação não cair
/// em texto claro sem ninguém notar.
///
/// É TLS de mão única, de propósito (decisão de 2026-10-16): o Serverpod 3.4.13
/// sobe o socket pelo `relic_io`, que chama `HttpServer.bindSecure` sem
/// `requestClientCertificate`, então o processo não tem como exigir o
/// certificado do Traefik. O mTLS interno fica aberto no `PROGRESS.md`.
class ApiTlsConfig {
  const ApiTlsConfig({required this.certificatePath, required this.keyPath});

  final String certificatePath;
  final String keyPath;

  static String? _blankToNull(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value;

  static ApiTlsConfig? fromMap(Map<String, String> environment) {
    final cert = _blankToNull(environment['API_TLS_CERT_PATH']);
    final key = _blankToNull(environment['API_TLS_KEY_PATH']);
    if ((cert == null) != (key == null)) {
      throw StateError('API_TLS_CERT_PATH e API_TLS_KEY_PATH devem vir juntos.');
    }
    if (cert == null || key == null) return null;
    return ApiTlsConfig(certificatePath: cert, keyPath: key);
  }

  /// O contexto do listener, com TLS 1.3 como mínimo: o padrão do `dart:io` é
  /// 1.2. Arquivo ausente ou ilegível lança aqui, no boot — falha fechada.
  SecurityContext toSecurityContext() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(certificatePath)
    ..usePrivateKey(keyPath)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
}
