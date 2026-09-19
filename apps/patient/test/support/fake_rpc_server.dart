import 'dart:convert';
import 'dart:io';

/// Uma requisição RPC que o servidor falso recebeu.
class RpcRequest {
  RpcRequest({required this.endpoint, required this.method, required this.args});

  /// Primeiro segmento do caminho: `auth`, `patients`, ...
  final String endpoint;

  /// O `method` que veio no corpo.
  final String method;

  /// Corpo já decodificado — inclui os argumentos e, quando houver, o
  /// `accessToken` que o cliente anexou.
  final Map<String, dynamic> args;

  @override
  String toString() => '$endpoint.$method($args)';
}

/// Servidor RPC mínimo, no formato que o cliente Serverpod fala.
///
/// Mesmo padrão do irmão `apps/acs/test/support/fake_rpc_server.dart`, e pelo
/// mesmo motivo: o [BackendClient] monta o `Client` gerado por dentro e não
/// aceita um cliente injetado, então a única forma de exercitar o código de
/// verdade — em vez de um mock do próprio objeto sob teste — é dar a ele um
/// servidor que responda no protocolo que ele espera.
///
/// Aqui ele existe pelo caminho do OTP (RF01), que nenhum teste durável
/// atravessava: sem ele, apagar o `on OtpRequestException` do `_guard` deixaria
/// o paciente vendo "Sem conexão com o servidor" no lugar de *"Código inválido
/// ou expirado. Peça um novo."*, e nada ficava vermelho.
///
/// Não é um servidor de verdade: não tem TLS, não autentica ninguém e só
/// conhece os métodos que os testes pedem. Nenhum código OTP nem CPF real passa
/// por aqui — o corpo dos pedidos é inspecionado, nunca ecoado no token.
class FakeRpcServer {
  FakeRpcServer._(this._server);

  final HttpServer _server;

  /// Tudo o que chegou, na ordem. É o que os testes inspecionam.
  final List<RpcRequest> requests = <RpcRequest>[];

  /// Vida útil do token emitido por `verifyOtp`. É o valor que o app lê do
  /// `exp` do token — e é por isso que ele é configurável: com dois valores
  /// diferentes, um teste distingue "o app leu o token" de "o app supôs 1
  /// hora". Negativa produz uma sessão **já vencida**, sem esperar.
  Duration tokenLifetime = const Duration(hours: 1);

  /// UUIDs sintéticos do seed, como no resto dos testes.
  String userId = '00000000-0000-4000-8000-000000000001';
  String microAreaId = '00000000-0000-4000-8000-000000000003';

  /// Definida, faz `requestOtp` recusar com esta mensagem, no mesmo formato que
  /// o backend real usa (`OtpRequestException`).
  String? rejectOtpWith;

  /// Idem para `verifyOtp`.
  String? rejectVerifyWith;

  /// Endereço para passar a `BackendClient(host: ...)`. Porta efêmera do SO:
  /// dois testes em paralelo não brigam por porta.
  String get host => 'http://127.0.0.1:${_server.port}/';

  int get otpRequests =>
      requests.where((r) => r.method == 'requestOtp').length;

  static Future<FakeRpcServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeRpcServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final method = decoded['method'] as String? ?? '';
    final segments = request.uri.pathSegments;

    requests.add(RpcRequest(
      endpoint: segments.isEmpty ? '' : segments.first,
      method: method,
      args: decoded,
    ));

    final recusa = switch (method) {
      'requestOtp' => rejectOtpWith,
      'verifyOtp' => rejectVerifyWith,
      _ => null,
    };
    if (recusa != null) {
      await _respond(request, HttpStatus.badRequest, {
        'className': 'OtpRequestException',
        'data': {'__className__': 'OtpRequestException', 'message': recusa},
      });
      return;
    }

    final payload = switch (method) {
      // `requestOtp` devolve `void`. Aqui o corpo é `{}`, e o servidor real
      // devolve `null` — a diferença é inócua e conhecida: o cliente gerado
      // chama `callServerEndpoint<void>`, que para `void` **não passa pelo
      // `parseData`** e descarta o corpo inteiro
      // (`serverpod_client_shared.dart:568-572`, na versão 3.4.13 deste
      // workspace). Quem estender este fake para um método com retorno de
      // verdade precisa do corpo real, não deste.
      'requestOtp' => const <String, Object?>{},
      'verifyOtp' => <String, Object?>{
          'accessToken': _token(),
          'tokenType': 'Bearer',
        },
      _ => null,
    };

    await _respond(
      request,
      payload == null ? HttpStatus.notFound : HttpStatus.ok,
      payload,
    );
  }

  Future<void> _respond(HttpRequest request, int status, Object? payload) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    if (payload != null) request.response.write(jsonEncode(payload));
    await request.response.close();
  }

  /// Token no formato que `AuthSession.tryParse` lê.
  ///
  /// A assinatura é de mentira, de propósito: quem verifica é o servidor, e o
  /// app não tem — nem deve ter — o segredo HMAC. O que o app lê do payload é
  /// `sub`, `role`, `micro_area_id` e `exp`.
  String _token() {
    final exp = DateTime.now()
        .toUtc()
        .add(tokenLifetime)
        .millisecondsSinceEpoch
        ~/ 1000;
    final payload = jsonEncode({
      'sub': userId,
      'role': 'patient',
      'micro_area_id': microAreaId,
      'exp': exp,
    });
    final encoded = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
    return 'header.$encoded.signature';
  }
}
