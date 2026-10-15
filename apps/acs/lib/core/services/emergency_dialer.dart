import 'package:url_launcher/url_launcher.dart';

/// Número do SAMU. Constante de domínio (PRD, RF13), não configuração.
const samuNumber = '192';

/// Abre o discador do aparelho com o número já digitado.
///
/// **Nunca liga sozinho:** `tel:` abre o discador e a pessoa confirma a
/// chamada. É o que dispensa `CALL_PHONE` no manifesto (permissão sensível,
/// revisada pela loja) e evita uma ligação por toque acidental.
abstract interface class EmergencyDialer {
  /// `true` se o discador foi aberto; `false` se o aparelho não tem como.
  Future<bool> dial(String number);
}

class UrlLauncherEmergencyDialer implements EmergencyDialer {
  const UrlLauncherEmergencyDialer();

  @override
  Future<bool> dial(String number) async {
    try {
      return await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {
      // Qualquer falha vira "não abriu": quem chama mostra o número em texto.
      return false;
    }
  }
}
