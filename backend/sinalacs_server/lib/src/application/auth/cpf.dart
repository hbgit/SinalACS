/// CPF validado — o identificador de login do paciente (RF01).
///
/// Existe porque a validação de dígito verificador precisa acontecer **antes**
/// de o CPF virar hash: um CPF com DV errado não pode nem ser procurado no
/// banco, senão um erro de digitação vira "paciente não encontrado" em vez de
/// "confira o número".
class Cpf {
  const Cpf._(this.digits);

  /// Apenas os 11 dígitos, sem máscara.
  final String digits;

  /// `123.456.789-09` — só para exibição.
  String get formatted =>
      '${digits.substring(0, 3)}.${digits.substring(3, 6)}.'
      '${digits.substring(6, 9)}-${digits.substring(9)}';

  /// Normaliza e valida. Devolve `null` para qualquer entrada inválida — quem
  /// chama decide a mensagem, e `null` não diz *por que* é inválido, o que
  /// evita distinguir "DV errado" de "não existe" na resposta ao cliente.
  static Cpf? tryParse(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 11) return null;

    // Repetição de dígito passa na aritmética abaixo e não é CPF válido:
    // a Receita não emite 111.111.111-11 nem nenhum outro múltiplo assim.
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return null;

    if (!_checkDigitMatches(digits, 9) || !_checkDigitMatches(digits, 10)) {
      return null;
    }
    return Cpf._(digits);
  }

  /// Confere o dígito verificador na posição [position] (9 = primeiro DV,
  /// 10 = segundo), pelos pesos decrescentes do algoritmo.
  static bool _checkDigitMatches(String digits, int position) {
    var sum = 0;
    for (var index = 0; index < position; index++) {
      sum += int.parse(digits[index]) * (position + 1 - index);
    }
    final remainder = sum % 11;
    final expected = remainder < 2 ? 0 : 11 - remainder;
    return expected == int.parse(digits[position]);
  }

  @override
  String toString() => formatted;
}
