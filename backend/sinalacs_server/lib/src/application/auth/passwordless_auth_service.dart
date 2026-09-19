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
  ///
  /// **O intervalo é silencioso, e não é detalhe de estilo.** O pedido repetido
  /// devolve a mesma resposta que o CPF inexistente e que o nascimento errado:
  /// um "aguarde um minuto" na tela só é alcançável por quem já acertou CPF e
  /// nascimento, então a mensagem seria um verificador do par. Não existe texto
  /// de cooldown neste serviço de propósito — o aviso é do app, que é quem sabe
  /// quando pediu por último (registrado no `PROGRESS.md`).
  static const resendCooldown = Duration(seconds: 60);

  static const _invalidInput = 'Confira os dados informados.';
  static const _invalidCode = 'Código inválido ou expirado. Peça um novo.';

  /// `requestOtp` devolve `void` e a resposta é a **mesma** em todos os
  /// desfechos: CPF não encontrado, nascimento errado e pedido repetido dentro
  /// do intervalo mínimo. Qualquer diferença transformaria este endpoint num
  /// verificador de quem é paciente da unidade — e é por isso que o intervalo
  /// mínimo também é silencioso (ver [resendCooldown]).
  ///
  /// A igualdade é de **payload, status e efeitos**: os três caminhos devolvem
  /// o mesmo `void`, não lançam, não gravam desafio, não enviam SMS e não
  /// escrevem auditoria. Quem prende isso é `duas chamadas respondem o mesmo
  /// com e sem cadastro`, que compara a SEQUÊNCIA de duas chamadas: uma
  /// chamada só não separa a igualdade da violação, e foi por isso que o
  /// oráculo de 2026-09-19 sobreviveu a duas revisões com a suíte verde.
  ///
  /// O **tempo não está equalizado**, e os dois termos disto não podem ser
  /// trocados: o que está igual dos dois lados é o CONTEÚDO (status e payload);
  /// o que continua diferente é o RELÓGIO — o caminho válido faz um
  /// `latestOpen`, um `save` e o envio, que a recusa não faz. Um cronômetro
  /// distingue os dois; o que não se mede com confiança é o tamanho da
  /// diferença, que se sobrepõe ao ruído entre chamadas. Não dá para equalizar
  /// aqui sem mentir sobre o envio; quando houver gateway de verdade o termo
  /// dominante é a ida ao provedor, e tirar o envio do caminho de resposta é a
  /// correção. Lacuna registrada na Task 8 — não resolvida.
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
      // `return` em silêncio, e **não** uma exceção de "aguarde um minuto".
      //
      // Chegar NESTA linha exige CPF **e** nascimento corretos — é a
      // precondição do ramo, e é justamente ela que faz do lançamento um
      // oráculo: a exceção só existe para quem já provou o par, então o código
      // de status da segunda chamada responde "este par existe". Medido contra
      // a stack em 2026-09-19, quatro chamadas por caso: o par cadastrado
      // devolvia 200 seguido de 400, 400, 400 e o CPF não cadastrado devolvia
      // 200 nas quatro. Duas chamadas decidiam o par.
      //
      // A versão anterior deste comentário dizia o oposto — "aqui lançar é
      // seguro: chegar neste ponto exige CPF e nascimento corretos, então a
      // exceção não revela nada a quem sonda" — e é essa inversão que explica
      // o defeito ter atravessado duas revisões: a precondição é o segredo, e
      // a frase a usava como atestado de inocência. Um comentário que afirma
      // que o ramo é seguro não prova nada; o que prova é a resposta ser igual
      // à dos outros caminhos, e é isso que o teste de sequência mede.
      //
      // O que o intervalo segue impedindo é o EFEITO, não o sinal: sem `save`
      // e sem `sendOtp`, um CPF conhecido não vira gerador de SMS nem semeia
      // desafios em série — e quem pedir de novo dentro do minuto continua com
      // o código anterior valendo, porque o TTL dele é maior que o intervalo.
      return;
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
