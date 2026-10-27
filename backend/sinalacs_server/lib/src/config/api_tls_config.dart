import 'dart:io';

/// TLS do apiServer do Serverpod: o trecho Traefik → backend (RNF04, issues
/// #78 e #90).
///
/// Lido de `API_TLS_CERT_PATH`, `API_TLS_KEY_PATH` e `API_TLS_CLIENT_CA_PATH`,
/// que vêm as três juntas ou não vêm. São opcionais porque há dois caminhos de
/// implantação com bordas diferentes: na stack local o Traefik termina o TLS do
/// cliente e abre um segundo TLS até o backend, que precisa deste certificado;
/// no Render (`backend/DEPLOY.md`) o proxy da plataforma termina o TLS e fala
/// HTTP com o container, e um listener TLS aqui só quebraria o healthcheck
/// dele. Sem as três variáveis o servidor segue em HTTP; com um subconjunto, o
/// boot falha, para um erro de digitação — ou um `.env` anterior à #90, que só
/// tem as duas primeiras — não cair em TLS sem exigir o certificado do Traefik
/// sem ninguém notar.
///
/// Desde a #90 o apiServer EXIGE certificado de cliente assinado pela CA de
/// `API_TLS_CLIENT_CA_PATH`, recusado no handshake. O contexto daqui só
/// descreve as chaves e a confiança; o bind com `requireClientCertificate`
/// está em `lib/src/runtime/mtls_api_server.dart`, porque nem o
/// `HttpServer.bindSecure` do SDK nem o `relic_io` expõem esse flag — o
/// Serverpod é consumido por um fork pinado que deixa a aplicação ligar o
/// socket (`backend/patches/README.md`).
class ApiTlsConfig {
  const ApiTlsConfig({
    required this.certificatePath,
    required this.keyPath,
    required this.clientCaPath,
  });

  final String certificatePath;
  final String keyPath;

  /// CA que assina os certificados de cliente aceitos (a CA de desenvolvimento
  /// do RPC, na stack local). É a ÚNICA raiz confiada pelo listener.
  final String clientCaPath;

  static const _variaveis = [
    'API_TLS_CERT_PATH',
    'API_TLS_KEY_PATH',
    'API_TLS_CLIENT_CA_PATH',
  ];

  static String? _blankToNull(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value;

  static ApiTlsConfig? fromMap(Map<String, String> environment) {
    final valores = [for (final v in _variaveis) _blankToNull(environment[v])];
    final presentes = valores.whereType<String>().length;
    if (presentes == 0) return null;
    if (presentes != _variaveis.length) {
      throw StateError(
        'API_TLS_CERT_PATH, API_TLS_KEY_PATH e API_TLS_CLIENT_CA_PATH devem vir '
        'juntas: o apiServer exige certificado de cliente (#90) e TLS sem essa '
        'exigência não é mais uma configuração válida.',
      );
    }
    return ApiTlsConfig(
      certificatePath: valores[0]!,
      keyPath: valores[1]!,
      clientCaPath: valores[2]!,
    );
  }

  /// O contexto do listener, com TLS 1.3 como mínimo: o padrão do `dart:io` é
  /// 1.2. `withTrustedRoots: false` + `setTrustedCertificates(clientCa)`: só a
  /// CA do RPC assina clientes aceitos — um certificado válido de qualquer
  /// outra raiz é recusado. `setClientAuthorities` é o que o servidor anuncia
  /// no pedido de certificado. Arquivo ausente ou ilegível lança aqui, no boot
  /// — falha fechada.
  SecurityContext toSecurityContext() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(certificatePath)
    ..usePrivateKey(keyPath)
    ..setTrustedCertificates(clientCaPath)
    ..setClientAuthorities(clientCaPath)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
}
