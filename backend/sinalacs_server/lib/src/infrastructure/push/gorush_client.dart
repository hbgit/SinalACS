import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Um aparelho a notificar: o token do provedor e a plataforma.
class PushTarget {
  const PushTarget({required this.token, required this.platform});

  final String token;

  /// `android` ou `ios`, o mesmo vocabulário de `push_tokens.platform`.
  final String platform;
}

/// O que vai na notificação. Nunca carrega dado de paciente: só texto do aviso e
/// a tela que o app deve abrir (minimização, decisão §3.2).
class PushMessage {
  const PushMessage({required this.title, required this.body, this.data = const {}});

  final String title;
  final String body;
  final Map<String, String> data;
}

/// Desfecho de um envio: quantas notificações o Gorush aceitou e quais tokens o
/// provedor declarou inválidos (candidatos a apagar).
class PushSendReport {
  const PushSendReport({required this.accepted, required this.invalidTokens});

  final int accepted;
  final List<String> invalidTokens;
}

/// O relé de push não respondeu como esperado (fora do ar, lento, 5xx). A
/// mensagem nunca inclui tokens nem o corpo enviado.
class PushGatewayException implements Exception {
  const PushGatewayException(this.message, {this.outcomeUnknown = false});

  final String message;

  /// `true` quando o pedido saiu mas a resposta não voltou a tempo: o Gorush
  /// pode ter entregue o aviso a parte dos aparelhos. Reenviar às cegas duplica
  /// o aviso; quem chama deve dizer isso à pessoa.
  final bool outcomeUnknown;

  @override
  String toString() => 'PushGatewayException: $message';
}

abstract interface class PushSender {
  Future<PushSendReport> send(PushMessage message, List<PushTarget> targets);
}

/// Cliente HTTP do Gorush (`POST /api/push`). Usa `dart:io`: o backend não tem o
/// pacote `http`, e uma chamada só não justifica a dependência.
class GorushClient implements PushSender {
  GorushClient({required String baseUrl, required Duration timeout, HttpClient? httpClient})
      : _baseUrl = baseUrl,
        _timeout = timeout,
        _http = httpClient ?? HttpClient();

  final String _baseUrl;
  final Duration _timeout;
  final HttpClient _http;

  /// Encerra as conexões. Um `send` depois disso falha com [PushGatewayException].
  void close() => _http.close(force: true);

  /// Códigos de plataforma do Gorush.
  static const _ios = 1;
  static const _android = 2;

  /// Erros que dizem que o TOKEN morreu. `MismatchSenderId` fica de fora de
  /// propósito: é a conta de serviço do servidor errada, e apagar por causa dele
  /// esvaziaria `push_tokens` da microárea inteira num único envio.
  static const _invalidTokenErrors = [
    'notregistered',
    'unregistered',
    'invalidregistration',
    'requested entity was not found', // FCM v1: UNREGISTERED
    // FCM v1: INVALID_ARGUMENT sobre o token (texto medido contra o FCM real)
    'not a valid fcm registration token',
    'baddevicetoken',
    'devicetokennotfortopic',
  ];

  @override
  Future<PushSendReport> send(PushMessage message, List<PushTarget> targets) async {
    if (targets.isEmpty) return const PushSendReport(accepted: 0, invalidTokens: []);

    final byPlatform = <int, List<String>>{};
    for (final t in targets) {
      byPlatform.putIfAbsent(t.platform == 'ios' ? _ios : _android, () => []).add(t.token);
    }
    final body = jsonEncode({
      'notifications': [
        for (final entry in byPlatform.entries)
          {
            'tokens': entry.value,
            'platform': entry.key,
            'title': message.title,
            'message': message.body,
            'data': message.data,
          },
      ],
    });

    try {
      return await _post(body, targets.length, {for (final t in targets) t.token}).timeout(_timeout);
    } on PushGatewayException {
      rethrow;
    } on TimeoutException {
      throw const PushGatewayException(
        'O Gorush não respondeu a tempo.',
        outcomeUnknown: true,
      );
    } on SocketException {
      throw const PushGatewayException('O Gorush está inacessível.');
    } on HttpException {
      throw const PushGatewayException('Falha de HTTP ao falar com o Gorush.');
    } on FormatException {
      // A resposta era 2xx: o Gorush pode ter entregue. Não é "tente de novo".
      throw const PushGatewayException(
        'O Gorush respondeu algo ilegível.',
        outcomeUnknown: true,
      );
    } on StateError {
      throw const PushGatewayException('O cliente do Gorush foi encerrado.');
    }
  }

  Future<PushSendReport> _post(String body, int total, Set<String> sent) async {
    final request = await _http.postUrl(Uri.parse('$_baseUrl/api/push'));
    request.headers.contentType = ContentType.json;
    request.write(body);
    final response = await request.close();
    final raw = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PushGatewayException('O Gorush respondeu com status ${response.statusCode}.');
    }
    final decoded = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const PushGatewayException(
        'O Gorush respondeu algo ilegível.',
        outcomeUnknown: true,
      );
    }
    final json = decoded;
    final logs = json['logs'] is List ? json['logs'] as List : const [];
    final invalid = <String>[];
    var failed = 0;
    for (final log in logs.whereType<Map<String, dynamic>>()) {
      if (log['type'] != 'failed-push') continue;
      failed++;
      final error = '${log['error']}'.toLowerCase();
      final token = log['token'];
      // Só devolve para a poda um token que NÓS enviamos: com `log.hide_token` do
      // Gorush ligado ele volta mascarado (`***…xx`), e apagar por um valor que não
      // reconhecemos seria apagar às cegas.
      if (token is String && sent.contains(token) && _invalidTokenErrors.any(error.contains)) {
        invalid.add(token);
      }
    }
    // `counts` do Gorush não é confiável como "aceitos" (conta notificações
    // enfileiradas, não entregas): o número que vai para o ACS é o total menos as
    // falhas que o próprio Gorush relatou.
    return PushSendReport(
      accepted: (total - failed).clamp(0, total),
      invalidTokens: invalid,
    );
  }
}
