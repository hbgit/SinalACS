import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_server/src/infrastructure/push/gorush_client.dart';
import 'package:test/test.dart';

/// Gorush de mentira: um `HttpServer` local que grava o que recebe e responde o
/// que o teste mandar. É o que dá para provar sem credenciais FCM/APNs.
class FakeGorush {
  FakeGorush._(this._server, this.status, this.response, this.hang, this.rawBody) {
    _server.listen((request) async {
      requests++;
      final raw = await utf8.decoder.bind(request).join();
      lastPath = request.uri.path;
      lastBody = raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
      if (hang) return;
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(rawBody ?? jsonEncode(response));
      await request.response.close();
    });
  }

  static Future<FakeGorush> start({
    int status = 200,
    Map<String, dynamic> response = const {},
    bool hang = false,
    String? rawBody,
  }) async =>
      FakeGorush._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        status,
        response,
        hang,
        rawBody,
      );

  final HttpServer _server;
  final int status;
  final Map<String, dynamic> response;
  final bool hang;

  /// Se presente, é escrito no corpo no lugar do JSON de [response].
  final String? rawBody;
  int requests = 0;
  String lastPath = '';
  Map<String, dynamic> lastBody = {};

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);
}

const _msg = PushMessage(title: 't', body: 'b');

void main() {
  test('agrupa por plataforma e usa os códigos do Gorush (1 iOS, 2 Android)', () async {
    final gw = await FakeGorush.start(response: {'counts': 3, 'logs': []});
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));

    final report = await client.send(
      const PushMessage(title: 'Vacina', body: 'Amanhã, na UBS.', data: {'screen': 'notices'}),
      const [
        PushTarget(token: 'a1', platform: 'android'),
        PushTarget(token: 'a2', platform: 'android'),
        PushTarget(token: 'i1', platform: 'ios'),
      ],
    );

    expect(gw.lastPath, '/api/push');
    final sent = gw.lastBody['notifications'] as List;
    expect(sent, hasLength(2));
    expect(sent.firstWhere((n) => n['platform'] == 2)['tokens'], ['a1', 'a2']);
    expect(sent.firstWhere((n) => n['platform'] == 1)['tokens'], ['i1']);
    expect(sent.first['title'], 'Vacina');
    expect(sent.first['message'], 'Amanhã, na UBS.');
    expect(sent.first['data'], {'screen': 'notices'});
    expect(report.accepted, 3);
    expect(report.invalidTokens, isEmpty);
  });

  test('tokens que o provedor recusa como inválidos voltam em invalidTokens', () async {
    final gw = await FakeGorush.start(response: {
      'counts': 1,
      'logs': [
        {'type': 'failed-push', 'platform': 'android', 'token': 'a2', 'error': 'NotRegistered'},
        {'type': 'failed-push', 'platform': 'ios', 'token': 'i1', 'error': 'BadDeviceToken'},
        {'type': 'failed-push', 'platform': 'ios', 'token': 'i2', 'error': 'ServiceUnavailable'},
      ],
    });
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));

    final report = await client.send(_msg, const [
      PushTarget(token: 'a2', platform: 'android'),
      PushTarget(token: 'i1', platform: 'ios'),
      PushTarget(token: 'i2', platform: 'ios'),
    ]);

    expect(report.invalidTokens.toSet(), {'a2', 'i1'}); // erro transitório não apaga token
  });

  test('"counts" não é confiável: aceitos = alvos menos as falhas dos logs', () async {
    final gw = await FakeGorush.start(response: {
      'counts': 3,
      'logs': [
        {'type': 'failed-push', 'token': 'a2', 'error': 'ServiceUnavailable'},
      ],
    });
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
    final report = await client.send(_msg, const [
      PushTarget(token: 'a1', platform: 'android'),
      PushTarget(token: 'a2', platform: 'android'),
      PushTarget(token: 'a3', platform: 'android'),
    ]);
    expect(report.accepted, 2);
  });

  test('MismatchSenderId é erro de configuração do servidor e não apaga token', () async {
    final gw = await FakeGorush.start(response: {
      'logs': [
        {'type': 'failed-push', 'token': 'a1', 'error': 'MismatchSenderId'},
        {'type': 'failed-push', 'token': 'a2', 'error': 'Requested entity was not found.'},
      ],
    });
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
    final report = await client.send(_msg, const [
      PushTarget(token: 'a1', platform: 'android'),
      PushTarget(token: 'a2', platform: 'android'),
    ]);
    expect(report.invalidTokens, ['a2']);
  });

  test('status 5xx vira PushGatewayException', () async {
    final gw = await FakeGorush.start(status: 503);
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
    await expectLater(
      client.send(_msg, const [PushTarget(token: 'a', platform: 'android')]),
      throwsA(isA<PushGatewayException>().having((e) => e.outcomeUnknown, 'outcomeUnknown', isFalse)),
    );
  });

  test('servidor que não responde estoura o tempo limite com resultado desconhecido', () async {
    final gw = await FakeGorush.start(hang: true);
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(milliseconds: 300));
    await expectLater(
      client.send(_msg, const [PushTarget(token: 'a', platform: 'android')]),
      throwsA(isA<PushGatewayException>().having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)),
    );
  });

  test('servidor fora do ar vira PushGatewayException sem vazar o token', () async {
    final gw = await FakeGorush.start();
    final url = gw.url;
    await gw.close();
    final client = GorushClient(baseUrl: url, timeout: const Duration(seconds: 1));
    try {
      await client.send(_msg, const [PushTarget(token: 'segredo-do-aparelho', platform: 'android')]);
      fail('deveria lançar');
    } on PushGatewayException catch (e) {
      expect(e.message.contains('segredo-do-aparelho'), isFalse);
    }
  });

  test('sem "counts" na resposta, aceitos = alvos menos as falhas', () async {
    final gw = await FakeGorush.start(response: {
      'logs': [
        {'type': 'failed-push', 'token': 'a2', 'error': 'ServiceUnavailable'},
      ],
    });
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
    final report = await client.send(_msg, const [
      PushTarget(token: 'a1', platform: 'android'),
      PushTarget(token: 'a2', platform: 'android'),
    ]);
    expect(report.accepted, 1);
  });

  test('corpo 2xx ilegível: resultado desconhecido, nunca "tente de novo"', () async {
    for (final raw in ['isto não é json', '[1,2,3]']) {
      final gw = await FakeGorush.start(rawBody: raw);
      addTearDown(gw.close);
      final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
      await expectLater(
        client.send(_msg, const [PushTarget(token: 'a', platform: 'android')]),
        throwsA(isA<PushGatewayException>().having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)),
        reason: raw,
      );
    }
  });

  test('"logs" que não é lista é tolerado: sem falhas relatadas', () async {
    final gw = await FakeGorush.start(rawBody: '{"logs":"não-é-lista"}');
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
    final report = await client.send(_msg, const [PushTarget(token: 'a', platform: 'android')]);
    expect(report.accepted, 1);
    expect(report.invalidTokens, isEmpty);
  });

  test('depois de close(), send falha com PushGatewayException e não com StateError', () async {
    final gw = await FakeGorush.start(response: {});
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2))..close();
    await expectLater(
      client.send(_msg, const [PushTarget(token: 'a', platform: 'android')]),
      throwsA(isA<PushGatewayException>()),
    );
  });

  test('lista vazia não chama o Gorush', () async {
    final gw = await FakeGorush.start();
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
    final report = await client.send(_msg, const []);
    expect(report.accepted, 0);
    expect(gw.requests, 0);
  });
}
