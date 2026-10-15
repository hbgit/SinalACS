import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show ConsentPurpose;
import 'package:sinalacs_patient/core/network/backend_client.dart';

/// Aparelho apto a receber push: o token do provedor e a plataforma.
class PushDevice {
  const PushDevice({required this.token, required this.platform});

  final String token;

  /// `android` ou `ios`, o mesmo vocabulário que o servidor valida.
  final String platform;
}

/// De onde o app tira o token de push. A implementação real,
/// `NativePushTokenSource` (canal `sinalacs/push_token`), lê o token do FCM no
/// Android e, no futuro, do APNs no iOS, e o backend o entrega depois ao Gorush
/// (decisão §3.2 do documento de decisões de produto). O lado nativo existe só
/// no Android, e só com `google-services.json` no build; onde o canal não
/// responde, o registro fica inerte.
abstract interface class PushTokenSource {
  /// `null` quando o aparelho não tem token (sem provedor, sem permissão).
  Future<PushDevice?> currentDevice();
}

class NoPushTokenSource implements PushTokenSource {
  const NoPushTokenSource();

  @override
  Future<PushDevice?> currentDevice() async => null;
}

const _consentLookupTimeout = Duration(seconds: 3);

/// Registra o aparelho para avisos (RF14). Silencioso de propósito: o paciente
/// não pediu isto na tela, e uma recusa (consentimento desligado), uma falha de
/// rede ou um provedor sem token nunca podem atrasar a home nem o botão de
/// urgência. Tenta de novo no próximo login ou ao conceder o consentimento.
///
/// Com [consentKnownGranted] falso, pergunta ao servidor (`hasGrantedConsent`,
/// teto de 3 s) antes de falar com o provedor; quem acabou de gravar a concessão
/// passa `true` e dispensa a ida.
Future<void> registerPushDevice(
  PatientBackend backend,
  PushTokenSource source, {
  bool consentKnownGranted = false,
}) async {
  // Sem fonte de token não há o que perguntar ao provedor: poupa a ida ao
  // servidor.
  if (source is NoPushTokenSource) return;
  try {
    // LGPD: o aparelho só fala com o provedor (Google/Apple) depois de o
    // servidor confirmar o consentimento vigente de avisos. Na dúvida (falha,
    // teto estourado, nunca decidiu) não pergunta: fecha, não abre.
    if (!consentKnownGranted) {
      final granted = await backend
          .hasGrantedConsent(ConsentPurpose.segmentedPush)
          .timeout(_consentLookupTimeout);
      if (!granted) return;
    }
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

  /// Como [of], mas sem escopo cai em [NoPushTokenSource]: o registro de push é
  /// acessório, e uma tela montada fora do `SinalAcsApp` não pode quebrar o login.
  static PushTokenSource maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PushTokenScope>()?.source ??
      const NoPushTokenSource();

  @override
  bool updateShouldNotify(PushTokenScope oldWidget) => source != oldWidget.source;
}
