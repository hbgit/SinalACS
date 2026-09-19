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

  /// Grava o desafio e **atribui o `id` dele**: o identificador é do store, não
  /// de quem chama. `OtpChallengeRecord.id` é obrigatório para que a leitura o
  /// carregue, mas quem grava manda `id: ''` — quem gera a chave é o banco, no
  /// INSERT — e o id de verdade só aparece em [latestOpen], que é de onde o
  /// serviço o tira para chamar [registerAttempt] e [consume].
  ///
  /// Honrar o `id: ''` quebra o fluxo em qualquer store, mas COMO ele quebra
  /// depende de quem gera o id — e a diferença é de severidade, então vale
  /// saber qual dos dois casos é o do store que se está escrevendo:
  ///
  /// - no store ORM, a quebra é **alta**: `otp_challenges.id` é `uuid NOT NULL
  ///   DEFAULT gen_random_uuid()` e PRIMARY KEY, e a string vazia não é um
  ///   uuid — o Postgres recusa o INSERT, e recusa qualquer comparação por esse
  ///   id, com `invalid input syntax for type uuid: ""` (medido no banco de
  ///   teste deste projeto). A escrita falha e não sobra linha nenhuma: o
  ///   problema aparece no primeiro login, e não meses depois.
  /// - num store cujos ids são **strings**, a quebra é **silenciosa**, e é de
  ///   colisão, não de ausência: todo desafio passaria a carregar o mesmo id
  ///   vazio, e [registerAttempt] e [consume] escreveriam na linha que casar
  ///   com esse id — que não é necessariamente a que o serviço acabou de ler.
  ///   Nenhuma das duas tem como falhar por linha ausente, então nem o teto de
  ///   tentativas nem o uso único acusariam nada. Esta suíte não cobre esse
  ///   caso: mutar o fake dela para honrar o `id: ''` a mantém verde.
  ///
  /// A regra é uma só, e é o que esta doc existe para dizer: **o id é do
  /// store**. Quem implementa [save] não grava o `id: ''` recebido — no ORM,
  /// `OtpChallenge.id` é opcional (`UuidValue?`, `defaultPersist=random`, e a
  /// coluna tem `DEFAULT gen_random_uuid()`) justamente para o dono da coluna
  /// atribuir a chave.
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
  /// encontrado": qualquer diferença de resposta transformaria este endpoint num
  /// verificador de quem é paciente da unidade.
  ///
  /// A igualdade é de **payload, status e efeitos**: as duas recusas não
  /// lançam, não gravam desafio, não enviam SMS e não escrevem auditoria.
  ///
  /// O **tempo não está equalizado**, e a versão anterior deste comentário
  /// dizia o contrário: o caminho válido faz um `latestOpen`, um `save` e o
  /// envio, que a recusa não faz. Um cronômetro distingue os dois. Não dá para
  /// equalizar aqui sem mentir sobre o envio; quando houver gateway de verdade
  /// o termo dominante é a ida ao provedor, e tirar o envio do caminho de
  /// resposta é a correção. Lacuna registrada na Task 8 — não resolvida.
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
    // As duas últimas condições repetem o que `latestOpen` promete filtrar, de
    // propósito: uso único e validade são propriedades de SEGURANÇA, e apoiá-las
    // só na consulta de outro arquivo faz esta suíte ficar verde no dia em que
    // aquele filtro for esquecido. Contra o store real não muda nada — ele já
    // não devolve desafio consumido nem expirado —, e o desfecho é o mesmo de
    // qualquer recusa de código.
    if (challenge == null ||
        challenge.attempts >= maxAttempts ||
        challenge.consumedAt != null ||
        !challenge.expiresAt.isAfter(at)) {
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
