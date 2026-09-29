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
  const PushGatewayException(this.message);

  final String message;

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

  /// Códigos de plataforma do Gorush.
  static const _ios = 1;
  static const _android = 2;

  static const _invalidTokenErrors = [
    'notregistered',
    'unregistered',
    'invalidregistration',
    'baddevicetoken',
    'devicetokennotfortopic',
    'mismatchsenderid',
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
      return await _post(body, targets.length).timeout(_timeout);
    } on PushGatewayException {
      rethrow;
    } on TimeoutException {
      throw const PushGatewayException('O Gorush não respondeu a tempo.');
    } on SocketException {
      throw const PushGatewayException('O Gorush está inacessível.');
    } on HttpException {
      throw const PushGatewayException('Falha de HTTP ao falar com o Gorush.');
    } on FormatException {
      throw const PushGatewayException('O Gorush respondeu algo ilegível.');
    }
  }

  Future<PushSendReport> _post(String body, int total) async {
    final request = await _http.postUrl(Uri.parse('$_baseUrl/api/push'));
    request.headers.contentType = ContentType.json;
    request.write(body);
    final response = await request.close();
    final raw = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PushGatewayException('O Gorush respondeu com status ${response.statusCode}.');
    }
    final json = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    final logs = (json['logs'] as List?) ?? const [];
    final invalid = <String>[];
    var failed = 0;
    for (final log in logs.whereType<Map<String, dynamic>>()) {
      if (log['type'] != 'failed-push') continue;
      failed++;
      final error = '${log['error']}'.toLowerCase();
      final token = log['token'];
      if (token is String && _invalidTokenErrors.any(error.contains)) invalid.add(token);
    }
    final counts = json['counts'];
    return PushSendReport(accepted: counts is int ? counts : (total - failed).clamp(0, total), invalidTokens: invalid);
  }
}
