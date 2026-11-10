/// Política do PIN local do participante (C-05, RF24).
///
/// Requisitos definidos na decisão D3 do plano da #136
/// (`docs/superpowers/plans/2026-11-03-issue-136-cifra-local-paciente.md`) e
/// no comentário da issue #128:
///
/// - **Tamanho:** 6 dígitos ou mais.
/// - **Lista de PINs proibidos:** um só dígito repetido (`000000`, `111111`,
///   …), sequências crescentes e decrescentes (`123456`, `987654`, …) e
///   alternância de dois dígitos (`121212`, …).
///
/// É defesa em profundidade, não segurança por si: com o aparelho em mãos **e
/// root** o atacante lê o envelope e força o PIN fora do aparelho, onde o
/// bloqueio por tentativas não alcança — um PIN de 6 dígitos encarece o ataque
/// (horas), não o impede. Residual aceito pelo dono em 2026-11-04
/// (`spec/lgpd_design.md` §0). Evolução registrada:
/// `setUserAuthenticationRequired` quando o aparelho tiver bloqueio de tela.
library;

/// Devolve o motivo (texto pronto para a tela) pelo qual [pin] é fraco, ou
/// `null` se ele atende a política. Nunca valida nada além do texto do PIN:
/// os dígitos não saem desta biblioteca.
String? pinWeakness(String pin) {
  final digits = pin.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^\d+$').hasMatch(digits)) {
    return 'O PIN usa só números.';
  }
  if (digits.length < 6) {
    return 'O PIN precisa de pelo menos 6 números.';
  }
  if (_singleDigitRepeated(digits)) {
    return 'Não repita o mesmo número em todos os dígitos.';
  }
  if (_ascendingRun(digits) || _descendingRun(digits)) {
    return 'Evite sequências seguidas, como 123456 ou 987654.';
  }
  if (_twoDigitAlternation(digits)) {
    return 'Evite alternar só dois números, como 121212.';
  }
  return null;
}

/// `true` quando o PIN atende a política — equivalente a [pinWeakness] nulo.
bool isValidPin(String pin) => pinWeakness(pin) == null;

/// Um só dígito repetido: `000000`, `111111`, …
bool _singleDigitRepeated(String digits) {
  final first = digits.codeUnitAt(0);
  for (var index = 1; index < digits.length; index++) {
    if (digits.codeUnitAt(index) != first) return false;
  }
  return true;
}

/// Sequência crescente consecutiva cobrindo o PIN inteiro: `123456`,
/// `456789`, `12345678`, …
bool _ascendingRun(String digits) {
  for (var index = 1; index < digits.length; index++) {
    final step = digits.codeUnitAt(index) - digits.codeUnitAt(index - 1);
    if (step != 1) return false;
  }
  return true;
}

/// Sequência decrescente consecutiva cobrindo o PIN inteiro: `987654`, …
bool _descendingRun(String digits) {
  for (var index = 1; index < digits.length; index++) {
    final step = digits.codeUnitAt(index) - digits.codeUnitAt(index - 1);
    if (step != -1) return false;
  }
  return true;
}

/// Alternância de dois dígitos: `121212`, `989898`, `070707`, …
bool _twoDigitAlternation(String digits) {
  for (var index = 2; index < digits.length; index++) {
    if (digits.codeUnitAt(index) != digits.codeUnitAt(index - 2)) return false;
  }
  return true;
}
