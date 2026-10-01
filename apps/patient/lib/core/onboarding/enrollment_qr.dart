/// Formato do convite que `OnboardingService._newToken` gera no servidor:
/// 32 bytes aleatórios em base64url, sem `=` de padding — 43 caracteres.
final _enrollmentToken = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// O token contido num QR Code lido pela câmera, ou `null` se o QR não for um
/// convite do SinalACS (link, Pix, QR de outro app).
///
/// Só a leitura da câmera passa por aqui: o campo digitado à mão continua
/// indo ao servidor como está, e é o servidor quem diz se o convite vale.
/// Aqui o objetivo é outro — não sobrescrever o campo com o conteúdo de um QR
/// qualquer que a câmera tenha pegado.
String? parseEnrollmentQr(String raw) {
  final value = raw.trim();
  return _enrollmentToken.hasMatch(value) ? value : null;
}
