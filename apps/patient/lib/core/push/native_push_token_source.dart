import 'package:flutter/services.dart';
import 'package:sinalacs_patient/core/push/push_token_source.dart';

/// Token de push do aparelho, pedido ao lado nativo por um `MethodChannel`
/// (FCM no Android, APNs no iOS — RF14, decisão §3.2).
///
/// O contrato do canal `sinalacs/push_token`: o método `getToken` devolve
/// `{'token': String, 'platform': 'android' | 'ios'}`. O lado nativo (Kotlin e
/// Swift) ainda não existe — depende das credenciais FCM/APNs que a organização
/// vai fornecer —, então hoje o canal não responde e [currentDevice] devolve
/// `null`: o app degrada para "sem push" sem erro para a pessoa.
class NativePushTokenSource implements PushTokenSource {
  const NativePushTokenSource();

  static const MethodChannel _channel = MethodChannel('sinalacs/push_token');

  @override
  Future<PushDevice?> currentDevice() async {
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>('getToken');
      final token = answer?['token'];
      final platform = answer?['platform'];
      if (token is! String || token.trim().isEmpty) return null;
      if (platform != 'android' && platform != 'ios') return null;
      return PushDevice(token: token.trim(), platform: platform as String);
    } catch (_) {
      // Canal ausente, permissão negada ou resposta ilegível: sem token.
      return null;
    }
  }
}
