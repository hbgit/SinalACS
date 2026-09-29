import 'package:flutter/widgets.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

/// Aparelho apto a receber push: o token do provedor e a plataforma.
class PushDevice {
  const PushDevice({required this.token, required this.platform});

  final String token;

  /// `android` ou `ios`, o mesmo vocabulário que o servidor valida.
  final String platform;
}

/// De onde o app tira o token de push. A implementação real (FCM) entra quando
/// existir um projeto Firebase (decisão §3.2 do documento de decisões de
/// produto); até lá [NoPushTokenSource] mantém o registro inerte, e servidor e
/// telas já estão prontos para a troca.
abstract interface class PushTokenSource {
  /// `null` quando o aparelho não tem token (sem provedor, sem permissão).
  Future<PushDevice?> currentDevice();
}

class NoPushTokenSource implements PushTokenSource {
  const NoPushTokenSource();

  @override
  Future<PushDevice?> currentDevice() async => null;
}

/// Registra o aparelho para avisos (RF14). Silencioso de propósito: o paciente
/// não pediu isto na tela, e uma recusa (consentimento desligado), uma falha de
/// rede ou um provedor sem token nunca podem atrasar a home nem o botão de
/// urgência. Tenta de novo no próximo login ou ao conceder o consentimento.
Future<void> registerPushDevice(PatientBackend backend, PushTokenSource source) async {
  try {
    final device = await source.currentDevice();
    if (device == null) return;
    await backend.registerPushToken(token: device.token, platform: device.platform);
  } catch (_) {
    // Intencionalmente silencioso — ver acima.
  }
}

/// Disponibiliza o [PushTokenSource] para a árvore de widgets, no mesmo padrão
/// de `QrScannerScope`: a tela não fala com o provedor, o que permite um duplo
/// em teste hermético.
class PushTokenScope extends InheritedWidget {
  const PushTokenScope({required this.source, required super.child, super.key});

  final PushTokenSource source;

  static PushTokenSource of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PushTokenScope>();
    assert(scope != null, 'Nenhum PushTokenScope acima deste widget.');
    return scope!.source;
  }

  @override
  bool updateShouldNotify(PushTokenScope oldWidget) => source != oldWidget.source;
}
