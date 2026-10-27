import 'dart:async';
import 'dart:io';

import 'package:relic/relic.dart';

/// O listener do apiServer com certificado de cliente OBRIGATÓRIO (mTLS
/// Traefik → backend, RNF04, issue #90).
///
/// Este arquivo existe por três limitações medidas em 2026-10-27:
///
/// 1. `HttpServer.bindSecure` do SDK só expõe `requestClientCertificate`, e com
///    ele o handshake COMPLETA mesmo sem certificado — a aplicação só vê
///    `request.certificate == null`. A recusa no handshake exige
///    `SecureServerSocket.bind(…, requireClientCertificate: true)`, que o
///    `bindSecure` não repassa.
/// 2. `SecureServerSocket` implementa `ServerSocketBase<SecureSocket>`, não
///    `ServerSocket`, e `HttpServer.listenOn` pede um `ServerSocket`. Daí o
///    embrulho [SecureServerSocketAsServerSocket]: o `_HttpServer` só usa
///    `listen`, `address`, `port` e `close` (SDK 3.12.2), e é isso que ele
///    delega.
/// 3. O `relic_io` e o Serverpod ligam o socket sozinhos (`RelicApp.serve`),
///    então o Serverpod é consumido por um fork pinado com o gancho
///    `apiServerAdapterFactory` (`backend/patches/README.md`), e
///    [mtlsApiServerAdapter] é a fábrica que esse gancho recebe.
///
/// Sondas deste trecho: `openssl s_client` sem certificado imprime
/// `CONNECTION ESTABLISHED` / `TLSv1.3` MESMO recusado — no TLS 1.3 o cliente
/// termina o lado dele antes de o servidor validar o certificado —, então
/// nenhuma sonda pode afirmar recusa pelo texto do `s_client`; `curl` e
/// "nenhuma linha HTTP" é o critério (`test/unit/mtls_api_server_test.dart`,
/// Grupo E de `scripts/qa/tls_invariants.sh`).

/// Um `SecureServerSocket` visto como `ServerSocket`, para o
/// `HttpServer.listenOn`.
///
/// Um handshake que falha chega ao stream do socket servidor como ERRO
/// (`RawSecureServerSocket._onData` → `addError`). O `_HttpServer` do SDK já
/// ignora `HandshakeException` ali, e o relic loga o resto; este embrulho não
/// depende disso: descarta `TlsException` (inclui `HandshakeException`) e
/// `SocketException` do caminho de aceitação, conta-os em
/// [handshakesRecusados] e loga só o TIPO do erro — nunca endereço ou bytes
/// do peer (VAZ-01). Sem `cancelOnError`: um cliente sem certificado não pode
/// derrubar o listener, senão o bloqueio que a #90 pede viraria um DoS.
class SecureServerSocketAsServerSocket extends StreamView<Socket>
    implements ServerSocket {
  SecureServerSocketAsServerSocket._(this._inner, this._contador, Stream<Socket> stream)
      : super(stream);

  factory SecureServerSocketAsServerSocket(
    SecureServerSocket inner, {
    void Function(String) log = print,
  }) {
    final contador = _Contador();
    final stream = inner.handleError(
      (Object erro, StackTrace _) {
        contador.valor++;
        log('[tls] handshake recusado: ${erro.runtimeType}');
      },
      test: (erro) => erro is TlsException || erro is SocketException,
    );
    return SecureServerSocketAsServerSocket._(inner, contador, stream);
  }

  final SecureServerSocket _inner;
  final _Contador _contador;

  /// Handshakes recusados (sem certificado, de outra CA, TLS 1.2, lixo no TCP)
  /// desde o bind. Só para observação e teste.
  int get handshakesRecusados => _contador.valor;

  @override
  InternetAddress get address => _inner.address;

  @override
  int get port => _inner.port;

  @override
  Future<ServerSocket> close() async {
    await _inner.close();
    return this;
  }
}

class _Contador {
  int valor = 0;
}

/// Liga o socket seguro exigindo certificado de cliente e o devolve já
/// embrulhado. [context] vem de `ApiTlsConfig.toSecurityContext()` (folha do
/// backend, CA de cliente confiada, mínimo TLS 1.3).
Future<SecureServerSocketAsServerSocket> bindRequiringClientCertificateSocket(
  InternetAddress address,
  int port,
  SecurityContext context, {
  void Function(String) log = print,
}) async {
  final secure = await SecureServerSocket.bind(
    address,
    port,
    context,
    requireClientCertificate: true,
  );
  return SecureServerSocketAsServerSocket(secure, log: log);
}

/// O `HttpServer` do apiServer sobre o socket de
/// [bindRequiringClientCertificateSocket].
Future<HttpServer> bindRequiringClientCertificate(
  InternetAddress address,
  int port,
  SecurityContext context, {
  void Function(String) log = print,
}) async =>
    HttpServer.listenOn(
      await bindRequiringClientCertificateSocket(address, port, context, log: log),
    );

/// `IOAdapter` cujo `close` fecha também o socket seguro.
///
/// `HttpServer.listenOn` cria o servidor com `_closeServer = false` (SDK
/// 3.12.2, `_http/http_impl.dart`): `HttpServer.close` NÃO fecha o
/// `ServerSocket` que recebeu. Sem isto, o shutdown do Serverpod
/// (`RelicServer.close` → `HttpServer.close`) deixaria a 8080 aceitando
/// handshakes de um servidor morto e a porta ocupada (achado 1 da revisão do
/// checkpoint da #90; `close do adapter libera a porta` em
/// `test/unit/mtls_api_server_test.dart`).
class _MtlsIOAdapter extends IOAdapter {
  _MtlsIOAdapter(super.server, this._socket);

  final SecureServerSocketAsServerSocket _socket;

  @override
  Future<void> close({bool force = false}) async {
    await super.close(force: force);
    await _socket.close();
  }
}

/// A `ApiServerAdapterFactory` passada ao `Serverpod(…)` em `lib/server.dart`
/// quando `API_TLS_*` está definido. Sem contexto não há o que exigir: falha
/// fechada em vez de cair em HTTP por este caminho.
Future<Adapter> mtlsApiServerAdapter(
  InternetAddress address,
  int port,
  SecurityContext? securityContext,
) async {
  if (securityContext == null) {
    throw StateError(
      'mtlsApiServerAdapter exige SecurityContext: sem API_TLS_* o apiServer '
      'sobe em HTTP pelo caminho padrão do Serverpod, não por esta fábrica.',
    );
  }
  final socket = await bindRequiringClientCertificateSocket(
    address, port, securityContext,
  );
  return _MtlsIOAdapter(HttpServer.listenOn(socket), socket);
}
