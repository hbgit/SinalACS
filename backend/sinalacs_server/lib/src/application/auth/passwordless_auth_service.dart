import 'dart:math';

import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/cpf_hasher.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/sms_gateway.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// O que o login precisa saber sobre o paciente, sem `application/` conhecer o
/// ORM.
class PatientCredentialRecord {
  const PatientCredentialRecord({
    required this.userId,
    required this.birthDate,
    required this.microAreaId,
  });

  final String userId;

  /// Data sem hora: a comparação é de dia, não de instante.
  final DateTime birthDate;

  final String? microAreaId;
}

/// O desafio como o ORM o entrega, já traduzido.
class OtpChallengeRecord {
  const OtpChallengeRecord({
    required this.id,
    required this.userId,
    required this.codeHash,
    required this.attempts,
    required this.createdAt,
    required this.expiresAt,
    this.consumedAt,
  });

  final String id;
  final String userId;
  final String codeHash;
  final int attempts;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? consumedAt;
}

/// Acesso a `users` (por hash de CPF) e a `otp_challenges`.
abstract interface class OtpChallengeStore {
  Future<PatientCredentialRecord?> findByCpfHash(String cpfHash);

  Future<void> save(OtpChallengeRecord challenge);

  /// Desafio mais recente, não consumido e ainda dentro da validade.
  Future<OtpChallengeRecord?> latestOpen(String userId, DateTime at);

  Future<void> registerAttempt(String challengeId, int attempts);

  Future<void> consume(String challengeId, DateTime at);
}

/// Login passwordless do paciente (RF01): CPF + data de nascimento + código.
class PasswordlessAuthService {
  PasswordlessAuthService({
    required this.store,
    required this.hasher,
    required this.sms,
    required this.audit,
    String Function()? codeGenerator,
  }) : _generateCode = codeGenerator ?? _randomCode;

  final OtpChallengeStore store;
  final CpfHasher hasher;
  final SmsGateway sms;
  final AuditTrail audit;
  final String Function() _generateCode;

  /// Cinco minutos: tempo de o SMS chegar e a pessoa digitar, sem deixar um
  /// código válido circulando por muito tempo.
  static const codeTtl = Duration(minutes: 5);

  /// Teto de verificações por desafio. 6 dígitos são 10^6 combinações; sem
  /// contador, um código enviado seria uma porta aberta a força bruta.
  static const maxAttempts = 5;

  /// Intervalo mínimo entre dois pedidos, para um CPF conhecido não virar
  /// gerador de SMS pago.
  static const resendCooldown = Duration(seconds: 60);

  static const _invalidInput = 'Confira os dados informados.';
  static const _resendTooSoon = 'Um código já foi enviado. Aguarde um minuto '
      'antes de pedir outro.';
  static const _invalidCode = 'Código inválido ou expirado. Peça um novo.';

  /// `requestOtp` devolve `void` e **não** distingue "enviado" de "CPF não
  /// encontrado": qualquer diferença de resposta (inclusive de tempo, por isso
  /// o envio do SMS só acontece quando o paciente existe) transformaria este
  /// endpoint num verificador de quem é paciente da unidade.
  Future<void> requestOtp({
    required Cpf cpf,
    required DateTime birthDate,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByCpfHash(hasher.hash(cpf));

    if (record == null || !_sameDay(record.birthDate, birthDate)) {
      // Sem envio, sem lançamento: o formulário segue para a tela do código.
      return;
    }

    final open = await store.latestOpen(record.userId, at);
    if (open != null && at.difference(open.createdAt) < resendCooldown) {
      // Aqui lançar é seguro: chegar neste ponto exige CPF **e** nascimento
      // corretos, então a exceção não revela nada a quem sonda.
      throw OtpRequestException(message: _resendTooSoon);
    }

    final code = _generateCode();
    await store.save(
      OtpChallengeRecord(
        // O id é do banco: `save` insere e o devolve em `latestOpen`.
        id: '',
        userId: record.userId,
        codeHash: hasher.hashOtpCode(code),
        attempts: 0,
        createdAt: at,
        expiresAt: at.add(codeTtl),
      ),
    );
    await sms.sendOtp(phone: cpf.formatted, code: code);
    await _recordAudit(record.userId, 'otp_requested');
  }

  /// Verifica o código e devolve quem entrou. Uma exceção só, com mensagem de
  /// fluxo, para nenhuma recusa dizer se aquele CPF existe.
  Future<AuthenticatedUser> verifyOtp({
    required Cpf cpf,
    required String code,
    String? deviceId,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    if (code.trim().length != 6) {
      throw OtpRequestException(message: _invalidInput);
    }

    final record = await store.findByCpfHash(hasher.hash(cpf));
    if (record == null) {
      throw OtpRequestException(message: _invalidCode);
    }

    final challenge = await store.latestOpen(record.userId, at);
    if (challenge == null || challenge.attempts >= maxAttempts) {
      await _recordAudit(record.userId, 'denied_code');
      throw OtpRequestException(message: _invalidCode);
    }

    if (challenge.codeHash != hasher.hashOtpCode(code.trim())) {
      await store.registerAttempt(challenge.id, challenge.attempts + 1);
      await _recordAudit(record.userId, 'denied_code');
      throw OtpRequestException(message: _invalidCode);
    }

    final microAreaId = record.microAreaId;
    if (microAreaId == null) {
      await _recordAudit(record.userId, 'denied_no_territory');
      throw OtpRequestException(
        message: 'Este acesso não está vinculado a uma microárea.',
      );
    }

    await store.consume(challenge.id, at);
    await _recordAudit(record.userId, 'granted');

    return AuthenticatedUser(
      id: record.userId,
      role: UserRole.patient,
      microAreaId: microAreaId,
      deviceId: deviceId ?? 'nao-aplicavel-login-passwordless',
    );
  }

  /// Compara ano/mês/dia em UTC, **não instantes**: `birthDate` é
  /// `timestamp without time zone` (o Serverpod não expõe tipo de coluna
  /// `date`) carregando sempre meia-noite UTC, e a data digitada pelo app
  /// também. Comparar instantes recusaria um nascimento correto por causa de
  /// fuso, e comparar só o dia é o que a credencial do RF01 significa.
  bool _sameDay(DateTime a, DateTime b) =>
      a.toUtc().year == b.toUtc().year &&
      a.toUtc().month == b.toUtc().month &&
      a.toUtc().day == b.toUtc().day;

  Future<void> _recordAudit(String userId, String result) =>
      audit.recordSafely(
        AuditEvent(
          userId: userId,
          actionType: 'login',
          resourceType: 'session',
          result: result,
        ),
      );

  /// `Random.secure()`, zero à esquerda preservado: um código de 6 dígitos
  /// precisa ter 10^6 possibilidades, e não 9×10^5.
  ///
  /// **O que este gerador promete a quem verifica:** seis dígitos, sem espaço
  /// nenhum. `hashOtpCode` não normaliza (ver `CpfHasher`), então `requestOtp`
  /// hasheia o código cru e `verifyOtp` hasheia `code.trim()`; os dois casam
  /// porque não há o que aparar. Mudar o formato aqui — letras, hífen, espaço —
  /// quebra essa concordância em silêncio, e o código certo deixa de verificar.
  static String _randomCode() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < 6; index++) {
      buffer.write(random.nextInt(10));
    }
    return buffer.toString();
  }
}
