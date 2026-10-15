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
/// Existe por um motivo específico: a renovação de sessão do ACS (RF07) não é
/// observável de outro jeito. O [BackendClient] monta o `Client` gerado por
/// dentro e não aceita um cliente injetado, então a única forma de exercitar o
/// código de verdade — em vez de um mock do próprio objeto sob teste — é dar a
/// ele um servidor que responda no protocolo que ele espera. O protocolo é
/// pequeno: o corpo é o JSON dos argumentos mais `method`, a resposta é o JSON
/// do modelo, e uma recusa é `{"className": ..., "data": {...}}` com status
/// diferente de 200.
///
/// Não é um servidor de verdade: não tem TLS, não autentica ninguém e só
/// conhece os métodos que os testes pedem. Nenhuma credencial real passa por
/// aqui.
class FakeRpcServer {
  FakeRpcServer._(this._server);

  final HttpServer _server;

  /// Tudo o que chegou, na ordem. É o que os testes inspecionam.
  final List<RpcRequest> requests = <RpcRequest>[];

  /// Vida útil do token emitido. Negativa produz uma sessão **já vencida**, que
  /// é como se testa a renovação sem esperar os 15 minutos.
  Duration tokenLifetime = const Duration(minutes: 15);

  /// UUIDs sintéticos do seed, como no resto dos testes.
  String userId = '00000000-0000-4000-8000-000000000002';
  String microAreaId = '00000000-0000-4000-8000-000000000003';

  /// Definida, faz `loginInstitutional` recusar com esta mensagem, no mesmo
  /// formato que o backend real usa (`AuthenticationFailedException`).
  String? rejectWith;

  /// Simula um ACS com MFA ativa: `loginInstitutional` sem `totpCode` recusa
  /// com `MfaRequiredException`, como o backend real.
  bool mfaRequired = false;

  /// Faz `generateEnrollmentToken` recusar como o backend recusa paciente de
  /// outra microárea (`AlertPermissionException`, INV-01).
  bool rejectInviteWithPermission = false;

  /// Contador do refresh token rotativo: cada renovação emite o próximo
  /// `refresh-<n>`; um login zera o contador.
  int _refreshSeq = 0;

  /// Refresh tokens emitidos pelos logins, na ordem. O primeiro login emite
  /// `refresh-0` (os testes antigos dependem do nome); os seguintes emitem
  /// `login-<n>`, distintos entre si — é o que deixa um teste saber se o token
  /// guardado é o do login novo ou o de uma renovação da conta anterior.
  final List<String> loginTokens = <String>[];

  String _nextLoginToken() {
    _refreshSeq = 0;
    final n = loginTokens.length;
    final token = n == 0 ? 'refresh-0' : 'login-$n';
    loginTokens.add(token);
    return token;
  }

  /// Faz `refreshSession` recusar com `SessionExpiredException`.
  bool rejectRefresh = false;

  /// Atraso antes de responder `refreshSession` (provoca concorrência).
  Duration refreshDelay = Duration.zero;

  /// Derruba a conexão na próxima `refreshSession` (resposta perdida): o
  /// servidor processa o pedido, mas o cliente não recebe nada.
  bool failRefreshOnce = false;

  /// Faz o login responder sem `refreshToken` (cliente sem deviceId).
  bool omitRefreshToken = false;

  /// Tokens de envio diferido emitidos pelos logins, na ordem (D7). Só com
  /// `deviceId` real — nem em branco, nem o sentinela do servidor.
  final List<String> uploadTokensIssued = <String>[];

  /// Faz o login responder sem `uploadToken`.
  bool omitUploadToken = false;

  /// Tokens de envio que `syncDeferred` recusa com `SessionExpiredException`.
  final Set<String> refusedUploadTokens = <String>{};

  /// Tokens que `revokeUploadToken` recebeu.
  final List<String> revokedUploadTokens = <String>[];

  String? _nextUploadToken(Map<String, dynamic> decoded) {
    final deviceId = (decoded['deviceId'] as String?)?.trim() ?? '';
    if (omitUploadToken || deviceId.isEmpty || deviceId == 'nao-aplicavel-login-institucional') return null;
    final token = 'upload-${uploadTokensIssued.length}';
    uploadTokensIssued.add(token);
    return token;
  }

  /// `refreshToken` recebido em cada `refreshSession`, na ordem.
  List<String> get refreshTokensSeen => requests
      .where((r) => r.method == 'refreshSession')
      .map((r) => r.args['refreshToken'] as String)
      .toList();

  /// Faz `refreshSession` devolver um accessToken ilegível.
  bool garbageAccessToken = false;

  /// Faz `refreshSession` devolver um refresh token vazio.
  bool emptyRefreshToken = false;

  /// Tokens que `logout` recebeu.
  final List<String> loggedOut = <String>[];

  /// Atraso antes de responder `logout` (rede lenta na saída).
  Duration logoutDelay = Duration.zero;

  /// Endereço para passar a `BackendClient(host: ...)`. Porta efêmera do SO:
  /// dois testes em paralelo não brigam por porta.
  String get host => 'http://127.0.0.1:${_server.port}/';

  int get loginCount =>
      requests.where((r) => r.method == 'loginInstitutional').length;

  int get refreshCount =>
      requests.where((r) => r.method == 'refreshSession').length;

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

    if (method == 'loginInstitutional' && rejectWith != null) {
      await _respond(request, HttpStatus.badRequest, {
        'className': 'AuthenticationFailedException',
        'data': {'message': rejectWith},
      });
      return;
    }

    if (method == 'loginInstitutional' && mfaRequired && decoded['totpCode'] == null) {
      await _respond(request, HttpStatus.badRequest, {
        'className': 'MfaRequiredException',
        'data': {'message': 'Informe o código do autenticador.'},
      });
      return;
    }

    if (method == 'refreshSession') {
      if (refreshDelay > Duration.zero) await Future<void>.delayed(refreshDelay);
      if (failRefreshOnce) {
        failRefreshOnce = false;
        _refreshSeq++; // o servidor rotacionou, mas a resposta se perdeu
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      if (rejectRefresh) {
        await _respond(request, HttpStatus.badRequest, {
          'className': 'SessionExpiredException',
          'data': {'message': 'Sessão expirada.'},
        });
        return;
      }
    }

    if (method == 'logout') {
      loggedOut.add(decoded['refreshToken'] as String? ?? '');
      if (logoutDelay > Duration.zero) await Future<void>.delayed(logoutDelay);
      await _respond(request, HttpStatus.ok, null);
      return;
    }

    if (method == 'syncDeferred' && refusedUploadTokens.contains(decoded['uploadToken'])) {
      await _respond(request, HttpStatus.badRequest, {
        'className': 'SessionExpiredException',
        'data': {'message': 'Envio não autorizado. Entre novamente.'},
      });
      return;
    }

    if (method == 'revokeUploadToken') {
      revokedUploadTokens.add(decoded['uploadToken'] as String? ?? '');
      await _respond(request, HttpStatus.ok, null);
      return;
    }

    if (method == 'generateEnrollmentToken' && rejectInviteWithPermission) {
      await _respond(request, HttpStatus.badRequest, {
        'className': 'AlertPermissionException',
        'data': {'message': 'Paciente fora da microárea do ACS.'},
      });
      return;
    }

    final payload = switch (method) {
      'loginInstitutional' => <String, Object?>{
          'accessToken': _token(),
          'tokenType': 'Bearer',
          if (!omitRefreshToken && ((decoded['deviceId'] as String?)?.trim().isNotEmpty ?? false)) 'refreshToken': _nextLoginToken(),
          if (_nextUploadToken(decoded) case final upload?) 'uploadToken': upload,
        },
      // `visits.syncLegacy`/`syncDeferred`: tudo `synced`, mesma versão.
      'syncLegacy' || 'syncDeferred' => <Object?>[
          for (final visit in (decoded['visits'] as List).cast<Map<String, dynamic>>())
            {'localId': visit['localId'], 'syncStatus': 'synced', 'serverVersion': visit['version']},
        ],
      'refreshSession' => <String, Object?>{
          'accessToken': garbageAccessToken ? 'lixo' : _token(),
          'tokenType': 'Bearer',
          'refreshToken': emptyRefreshToken ? '' : 'refresh-${++_refreshSeq}',
        },
      'developmentLogin' => <String, Object?>{
          'accessToken': _token(),
          'tokenType': 'Bearer',
        },
      // Corpo de `patients.listMicroArea`: uma lista vazia basta para o teste
      // de renovação — o que importa é que a chamada autenticada aconteceu.
      'listMicroArea' => const <Object?>[],
      // Corpo de `onboarding.generateEnrollmentToken`. Token sintético: o real
      // tem 43 caracteres base64url, mas o cliente não valida o formato.
      'generateEnrollmentToken' => <String, Object?>{
          'token': 'convite-sintetico',
          'expiresAt': '2026-09-29T10:15:00.000Z',
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
      'role': 'acs',
      'micro_area_id': microAreaId,
      'exp': exp,
    });
    final encoded = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
    return 'header.$encoded.signature';
  }
}
