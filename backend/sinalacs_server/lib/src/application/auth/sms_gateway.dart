import 'dart:io';

/// Envio do código OTP por SMS (RF01).
///
/// **Nenhum provedor está escolhido** — nem `spec/PRD_system.md` (que só cita
/// "SMS Gateway" como dependência), nem `spec/stack.md`, nem o documento de
/// decisões pós-validação. Escolher provedor é decisão de produto/infra, e
/// depende de conta, custo por mensagem e contrato, como o projeto Firebase do
/// RF14. Por isso a interface existe: o serviço de login não sabe quem envia, e
/// trocar o gateway é implementar esta interface.
abstract interface class SmsGateway {
  /// [phone] é o identificador de destino. Hoje é o CPF formatado, porque não
  /// existe coluna de telefone em `Patient` nem no ER do PRD — ver a lacuna
  /// registrada no plano. O gateway real traduz para o número na integração.
  Future<void> sendOtp({required String phone, required String code});
}

/// Gateway de desenvolvimento: **não envia SMS**, escreve o código no log do
/// processo para o desenvolvedor conseguir entrar.
///
/// Só é construído quando `SMS_GATEWAY=log`, que `AppConfig` recusa fora de
/// `APP_ENV=development`. O código é dado de curta duração e de uso único, mas
/// ainda assim vai para o log de propósito — é o único jeito de exercitar o
/// fluxo sem provedor — e o texto deixa isso explícito.
class LoggingSmsGateway implements SmsGateway {
  const LoggingSmsGateway();

  @override
  Future<void> sendOtp({required String phone, required String code}) async {
    stdout.writeln(
      '[SMS-GATEWAY=log] código de acesso para $phone: $code '
      '(gateway de desenvolvimento — nenhum SMS foi enviado)',
    );
  }
}

/// Gateway de teste: guarda o que "enviaria" para o teste asseverar.
class RecordingSmsGateway implements SmsGateway {
  final sent = <({String phone, String code})>[];

  @override
  Future<void> sendOtp({required String phone, required String code}) async {
    sent.add((phone: phone, code: code));
  }
}
