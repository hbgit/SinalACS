import 'dart:io';

import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/passwordless_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/sms_gateway.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';
import 'package:test/test.dart';

const _patientId = '00000000-0000-4000-8000-000000000001';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
final _cpf = Cpf.tryParse('12345678909')!;
final _nascimento = DateTime.utc(1990, 1, 1);

/// Store em memória: o serviço é o que está sob teste, não o Postgres.
///
/// `save` não guarda o registro recebido ao pé da letra — o `id` do desafio é
/// do banco, não de quem chama, então o fake numera as linhas e devolve o id em
/// `latestOpen`, como o `OtpChallenge` gerado faz depois do INSERT.
///
/// `registerAttempt` e `consume` **alteram** a linha guardada. Com no-ops,
/// "o código não vale duas vezes" e "o contador para no limite" passariam sem
/// medir nada: o desafio continuaria aberto e com zero tentativas, e o serviço
/// pareceria certo sem estar. Quem prova que o SQL do store ORM aplica essas
/// duas regras é o teste de integração da task do store.
class _FakeStore implements OtpChallengeStore {
  _FakeStore({this.record});

  PatientCredentialRecord? record;
  final challenges = <OtpChallengeRecord>[];

  var _lastId = 0;

  @override
  Future<PatientCredentialRecord?> findByCpfHash(String cpfHash) async =>
      cpfHash == _hasher.hash(_cpf) ? record : null;

  @override
  Future<void> save(OtpChallengeRecord challenge) async {
    _lastId++;
    challenges.add(
      OtpChallengeRecord(
        id: 'desafio-$_lastId',
        userId: challenge.userId,
        codeHash: challenge.codeHash,
        attempts: challenge.attempts,
        createdAt: challenge.createdAt,
        expiresAt: challenge.expiresAt,
      ),
    );
  }

  @override
  Future<OtpChallengeRecord?> latestOpen(String userId, DateTime at) async {
    final open = challenges.where(
      (challenge) =>
          challenge.userId == userId &&
          challenge.consumedAt == null &&
          challenge.expiresAt.isAfter(at),
    );
    return open.isEmpty ? null : open.last;
  }

  @override
  Future<void> registerAttempt(String challengeId, int attempts) async =>
      _replace(challengeId, attempts: attempts);

  @override
  Future<void> consume(String challengeId, DateTime at) async =>
      _replace(challengeId, consumedAt: at);

  void _replace(String challengeId, {int? attempts, DateTime? consumedAt}) {
    final index = challenges.lastIndexWhere(
      (challenge) => challenge.id == challengeId,
    );
    if (index == -1) return;
    final current = challenges[index];
    challenges[index] = OtpChallengeRecord(
      id: current.id,
      userId: current.userId,
      codeHash: current.codeHash,
      attempts: attempts ?? current.attempts,
      createdAt: current.createdAt,
      expiresAt: current.expiresAt,
      consumedAt: consumedAt ?? current.consumedAt,
    );
  }
}

/// Store que **descumpre** o contrato de `latestOpen`: devolve o desafio mais
/// recente do usuário mesmo já consumido ou expirado, como faria uma consulta
/// que tivesse esquecido o `consumedAt IS NULL` ou o `expiresAt > :at`.
///
/// O contrato diz que o filtro é do store, e o store da Task 5 o implementa.
/// Mas uso único e validade são duas propriedades de SEGURANÇA, e apoiá-las só
/// num arquivo que ainda não existe deixa a suíte incapaz de medir o dia em que
/// ele esquecer um dos dois filtros. Este fake é esse dia, simulado.
class _FakeStoreSemFiltro extends _FakeStore {
  _FakeStoreSemFiltro({super.record});

  @override
  Future<OtpChallengeRecord?> latestOpen(String userId, DateTime at) async {
    final doUsuario = challenges.where(
      (challenge) => challenge.userId == userId,
    );
    return doUsuario.isEmpty ? null : doUsuario.last;
  }
}

// `extends`, não `implements`: `AuditTrail` é uma `abstract class` com
// `recordSafely` concreto, herdado de propósito por todo implementador.
class _RecordingAudit extends AuditTrail {
  final events = <AuditEvent>[];
  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

final _hasher = HmacCpfHasher(pepper: 'pepper-de-teste');

PasswordlessAuthService _build({
  PatientCredentialRecord? record,
  SmsGateway? gateway,
  _FakeStore? store,
  _RecordingAudit? audit,
}) =>
    PasswordlessAuthService(
      store: store ?? _FakeStore(record: record),
      hasher: _hasher,
      sms: gateway ?? RecordingSmsGateway(),
      audit: audit ?? _RecordingAudit(),
      codeGenerator: () => '123456',
    );

/// A mensagem com que [recusar] recusou; falha se a chamada foi ACEITA.
///
/// A classe da exceção não basta para fixar uma recusa: `OtpRequestException`
/// é a mesma para todas, então uma mensagem nova num caminho passa despercebida
/// enquanto o teste só olhar o tipo. O que precisa ser comparado é o texto.
Future<String> _mensagemDe(Future<void> Function() recusar) async {
  try {
    await recusar();
  } on OtpRequestException catch (erro) {
    return erro.message;
  }
  fail('a chamada foi aceita — este caminho tinha de ser recusado');
}

void main() {
  final encontrado = PatientCredentialRecord(
    userId: _patientId,
    birthDate: _nascimento,
    microAreaId: _microAreaId,
  );

  group('requestOtp', () {
    test('grava desafio, envia o código e audita quando CPF e nascimento conferem',
        () async {
      final store = _FakeStore(record: encontrado);
      final gateway = RecordingSmsGateway();
      final audit = _RecordingAudit();
      final service = _build(store: store, gateway: gateway, audit: audit);

      await service.requestOtp(cpf: _cpf, birthDate: _nascimento);

      expect(store.challenges, hasLength(1));
      expect(gateway.sent.single.code, '123456');
      // O código nunca é persistido: só o HMAC dele.
      expect(store.challenges.single.codeHash, isNot(contains('123456')));
      expect(store.challenges.single.codeHash, _hasher.hashOtpCode('123456'));
      // O pedido também entra na trilha: todo desfecho do RF01 é auditado.
      expect(audit.events.single.result, 'otp_requested');
      expect(audit.events.single.resourceType, 'session');
    });

    test('não revela CPF inexistente nem nascimento errado', () async {
      final storeInexistente = _FakeStore();
      final storeNascimentoErrado = _FakeStore(record: encontrado);
      final semSms = RecordingSmsGateway();
      final semSmsNascimento = RecordingSmsGateway();
      final audit = _RecordingAudit();
      final inexistente = _build(
        store: storeInexistente,
        gateway: semSms,
        audit: audit,
      );
      final comOutroNascimento = _build(
        store: storeNascimentoErrado,
        gateway: semSmsNascimento,
        audit: audit,
      );

      // Nenhum dos dois lança: a resposta é a mesma de um pedido bem-sucedido,
      // senão o formulário vira um oráculo de "este CPF está cadastrado".
      await expectLater(
        inexistente.requestOtp(cpf: _cpf, birthDate: _nascimento),
        completes,
      );
      await expectLater(
        comOutroNascimento.requestOtp(
          cpf: _cpf,
          birthDate: DateTime.utc(1991, 2, 2),
        ),
        completes,
      );

      // E nenhum dos dois envia SMS: o envio é o outro sinal que distinguiria
      // o CPF cadastrado do inventado.
      expect(semSms.sent, isEmpty);
      expect(semSmsNascimento.sent, isEmpty);

      // E nenhum dos dois grava desafio. Sem esta linha, uma recusa que
      // chegasse a `store.save` deixaria uma linha em `otp_challenges` — um
      // desafio que o caminho válido nunca teria para aquele CPF — e o teste
      // continuaria verde, porque só olhava o SMS enviado.
      expect(storeInexistente.challenges, isEmpty);
      expect(storeNascimentoErrado.challenges, isEmpty);

      // E nenhum dos dois escreve auditoria: uma linha `otp_requested` para um
      // CPF que não existe é o mesmo oráculo, só que no banco.
      expect(audit.events, isEmpty);
    });

    test('não envia SMS quando o CPF não existe', () async {
      final gateway = RecordingSmsGateway();
      await _build(store: _FakeStore(), gateway: gateway)
          .requestOtp(cpf: _cpf, birthDate: _nascimento);

      expect(gateway.sent, isEmpty);
    });

    test('compara o nascimento por dia, não por instante', () async {
      // A coluna é `timestamp` (o Serverpod não expõe tipo de coluna `date`),
      // então ela carrega hora, enquanto o app manda o dia puro. O RF01 usa a
      // data como credencial: comparar instantes recusaria um nascimento
      // correto por causa de um horário que ninguém digitou.
      final store = _FakeStore(
        record: PatientCredentialRecord(
          userId: _patientId,
          birthDate: DateTime.utc(1990, 1, 1, 12),
          microAreaId: _microAreaId,
        ),
      );
      final gateway = RecordingSmsGateway();

      await _build(store: store, gateway: gateway)
          .requestOtp(cpf: _cpf, birthDate: _nascimento);

      expect(gateway.sent, hasLength(1));
    });

    test('expira em 5 minutos', () async {
      final store = _FakeStore(record: encontrado);
      final agora = DateTime.utc(2026, 9, 18, 12);
      await _build(store: store).requestOtp(
        cpf: _cpf,
        birthDate: _nascimento,
        now: agora,
      );

      expect(
        store.challenges.single.expiresAt,
        agora.add(PasswordlessAuthService.codeTtl),
      );
    });

    test('respeita o intervalo mínimo entre pedidos', () async {
      final store = _FakeStore(record: encontrado);
      final agora = DateTime.utc(2026, 9, 18, 12);
      final service = _build(store: store);

      await service.requestOtp(cpf: _cpf, birthDate: _nascimento, now: agora);

      // Um segundo pedido imediato lança para quem chamou, mas sem dizer nada
      // sobre o CPF — a mensagem é de fluxo, não de cadastro.
      await expectLater(
        service.requestOtp(cpf: _cpf, birthDate: _nascimento, now: agora),
        throwsA(isA<OtpRequestException>()),
      );
      expect(store.challenges, hasLength(1));
    });
  });

  group('verifyOtp', () {
    Future<PasswordlessAuthService> comCodigoPendente({
      _FakeStore? store,
      DateTime? agora,
    }) async {
      final target = store ?? _FakeStore(record: encontrado);
      final service = _build(store: target);
      await service.requestOtp(
        cpf: _cpf,
        birthDate: _nascimento,
        now: agora,
      );
      return service;
    }

    test('aceita o código correto e devolve paciente territorializado', () async {
      final service = await comCodigoPendente();

      final user = await service.verifyOtp(cpf: _cpf, code: '123456');

      expect(user.id, _patientId);
      expect(user.role, UserRole.patient);
      expect(user.microAreaId, _microAreaId);
    });

    test('recusa código errado', () async {
      final service = await comCodigoPendente();

      await expectLater(
        service.verifyOtp(cpf: _cpf, code: '000000'),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('recusa quando não há código pendente', () async {
      final service = _build(store: _FakeStore(record: encontrado));

      await expectLater(
        service.verifyOtp(cpf: _cpf, code: '123456'),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('recusa código expirado', () async {
      final agora = DateTime.utc(2026, 9, 18, 12);
      final service = await comCodigoPendente(agora: agora);

      await expectLater(
        service.verifyOtp(
          cpf: _cpf,
          code: '123456',
          now: agora.add(
            PasswordlessAuthService.codeTtl + const Duration(minutes: 1),
          ),
        ),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('não deixa o código ser usado duas vezes', () async {
      final service = await comCodigoPendente();

      await service.verifyOtp(cpf: _cpf, code: '123456');

      await expectLater(
        service.verifyOtp(cpf: _cpf, code: '123456'),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('corta o desafio depois de 5 tentativas erradas, mesmo com o código certo',
        () async {
      final service = await comCodigoPendente();

      for (var tentativa = 0;
          tentativa < PasswordlessAuthService.maxAttempts;
          tentativa++) {
        await expectLater(
          service.verifyOtp(cpf: _cpf, code: '000000'),
          throwsA(isA<OtpRequestException>()),
        );
      }

      // Sem contador, 10^6 combinações são força bruta viável; e o teto tem de
      // valer também para o código CERTO, senão o limite não protege o desafio
      // que já foi sondado cinco vezes.
      await expectLater(
        service.verifyOtp(cpf: _cpf, code: '123456'),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('as recusas não se distinguem pela mensagem', () async {
      // Três caminhos recusam por três motivos: CPF que não está no cadastro,
      // nenhum desafio aberto, e código errado. Basta uma delas ganhar texto
      // próprio para a resposta passar a dizer QUAL aconteceu — e "este CPF não
      // existe" é o oráculo de quem é paciente da unidade que esta task existe
      // para fechar. A comparação é entre as mensagens, e não contra o literal:
      // a redação pode mudar, a igualdade é a propriedade.
      final semCadastro = _build(store: _FakeStore());
      final mensagemSemCadastro = await _mensagemDe(
        () => semCadastro.verifyOtp(cpf: _cpf, code: '123456'),
      );

      final semDesafio = _build(store: _FakeStore(record: encontrado));
      final mensagemSemDesafio = await _mensagemDe(
        () => semDesafio.verifyOtp(cpf: _cpf, code: '123456'),
      );

      final comDesafio = await comCodigoPendente();
      final mensagemCodigoErrado = await _mensagemDe(
        () => comDesafio.verifyOtp(cpf: _cpf, code: '000000'),
      );

      expect(mensagemSemCadastro, mensagemCodigoErrado);
      expect(mensagemSemDesafio, mensagemCodigoErrado);
    });

    test('recusa o código já consumido mesmo se o store o devolver', () async {
      // O store real filtra o consumido em `latestOpen`; este devolve a linha
      // assim mesmo. O uso único não pode repousar só no filtro de quem
      // consulta: a segunda verificação com o MESMO código tem de ser recusada
      // ainda que a consulta traga o desafio consumido de volta.
      final audit = _RecordingAudit();
      final service = _build(
        store: _FakeStoreSemFiltro(record: encontrado),
        audit: audit,
      );
      await service.requestOtp(cpf: _cpf, birthDate: _nascimento);
      await service.verifyOtp(cpf: _cpf, code: '123456');

      await expectLater(
        service.verifyOtp(cpf: _cpf, code: '123456'),
        throwsA(isA<OtpRequestException>()),
      );
      // O desfecho é o mesmo de qualquer recusa de código: quem lê a trilha
      // não pode ficar sem a linha só porque a recusa veio de outro ramo.
      expect(audit.events.last.result, 'denied_code');
    });

    test('recusa o código expirado mesmo se o store o devolver', () async {
      // Mesma ideia do desafio consumido: a validade é conferida pelo serviço,
      // e não só pelo filtro da consulta que o store promete aplicar.
      final agora = DateTime.utc(2026, 9, 18, 12);
      final audit = _RecordingAudit();
      final service = _build(
        store: _FakeStoreSemFiltro(record: encontrado),
        audit: audit,
      );
      await service.requestOtp(
        cpf: _cpf,
        birthDate: _nascimento,
        now: agora,
      );

      await expectLater(
        service.verifyOtp(
          cpf: _cpf,
          code: '123456',
          now: agora.add(
            PasswordlessAuthService.codeTtl + const Duration(minutes: 1),
          ),
        ),
        throwsA(isA<OtpRequestException>()),
      );
      expect(audit.events.last.result, 'denied_code');
    });

    test('audita cada desfecho', () async {
      final audit = _RecordingAudit();
      final service = await comCodigoPendente();
      // Reusa o mesmo audit nos dois caminhos.
      final instrumented = PasswordlessAuthService(
        store: service.store,
        hasher: _hasher,
        sms: RecordingSmsGateway(),
        audit: audit,
        codeGenerator: () => '123456',
      );

      await instrumented.verifyOtp(cpf: _cpf, code: '000000').then(
            (_) {},
            onError: (Object _) {},
          );
      await instrumented.verifyOtp(cpf: _cpf, code: '123456');

      expect(
        audit.events.map((event) => event.result).toList(),
        ['denied_code', 'granted'],
      );
      expect(
        audit.events.every((event) => event.resourceType == 'session'),
        isTrue,
      );
    });
  });

  group('parâmetros de segurança', () {
    // Literais de propósito. "expira em 5 minutos" e "respeita o intervalo
    // mínimo entre pedidos" comparam contra as PRÓPRIAS constantes, então
    // acompanham qualquer mutação do valor: com 5 minutos virando 5 horas, ou
    // 60 segundos virando 1 ms, as duas continuam verdes. O literal é o único
    // ponto da suíte que prende o número.
    //
    // `maxAttempts` entra na mesma linha de raciocínio: o teste do limite
    // itera `maxAttempts` vezes e depois exige a recusa, o que é
    // auto-referente — qualquer valor passa, porque o laço acompanha o valor
    // mutado e o contador chega exatamente nele.
    test('validade do código, teto de tentativas e intervalo entre pedidos', () {
      expect(PasswordlessAuthService.codeTtl, const Duration(minutes: 5));
      expect(PasswordlessAuthService.maxAttempts, 5);
      expect(
        PasswordlessAuthService.resendCooldown,
        const Duration(seconds: 60),
      );
    });
  });

  group('gateway de log', () {
    // O defeito que este guard prende: `LoggingSmsGateway` escrevia o DESTINO
    // na linha de log, e o único chamador passa `cpf.formatted`. Não é uma
    // questão de disciplina de quem edita — é dado pessoal saindo por um canal
    // que ninguém revisa, e log de desenvolvimento é justamente o que acaba
    // colado numa issue. O desenvolvedor não precisa do destino: ele acabou de
    // digitar o CPF no formulário e sabe de quem é o pedido; o que ele não tem
    // é o código.
    //
    // Duas versões deste guard erraram antes desta, uma de cada vez, e cada uma
    // tapou um buraco abrindo outro. A rodada 1 prendia o NOME `phone`
    // (`RegExp(r'\bphone\b')`), e nome não é dado: renomear o parâmetro para
    // `telefone` — exatamente o que a doc desta classe empurra a fazer, já que
    // ela mesma diz que `phone` é nome falso para um CPF — e reintroduzir a
    // referência na linha de log deixava a suíte INTEIRA verde. A rodada 2
    // passou a prender as INTERPOLAÇÕES do corpo (todas têm de ser `code`) e
    // com isso perdeu a outra forma da mesma referência: `stdout.writeln(phone);`,
    // sem `$` nenhum, atravessava o guard com a suíte verde — medido, não
    // suposto.
    //
    // O que este guard prende agora são as duas formas de uma vez, e a lista de
    // nomes proibidos sai da PRÓPRIA ASSINATURA (`_parametrosDe`): o corpo não
    // pode mencionar nenhum dos parâmetros declarados ali, exceto `code`, seja
    // interpolado (`$phone`) ou como argumento direto (`writeln(phone)`). Um
    // parâmetro novo entra na lista proibida sozinho, sem ninguém precisar
    // lembrar de acrescentá-lo, e renomear o destino só muda o nome que aparece
    // na mensagem de falha. A exceção — `code` — é explícita, não um efeito
    // colateral da forma do texto.
    test('registra o código e nenhuma outra referência da assinatura', () {
      _exigeLogDoSmsSemDadoPessoal(_leituraDoGatewayDeLog());
    });

    // O vazamento SEM interpolação, que a rodada 2 deixava passar. A fonte é
    // sintética pelo mesmo motivo de `_fonteComCorpoDeExpressao`: o defeito tem
    // de ficar preso NA SUÍTE, e não só no script de mutantes de quem revisa.
    // Sem poder injetar a fonte, provar que este guard pega o argumento direto
    // exigiria editar `sms_gateway.dart` à mão a cada revisão — e nada
    // impediria uma próxima rodada de perder esta forma outra vez.
    test('prende o vazamento direto, sem interpolação', () {
      expect(
        () => _exigeLogDoSmsSemDadoPessoal(
          _leituraDoGatewayDeLog(fonte: _fonteComVazamentoDireto),
        ),
        throwsA(
          isA<TestFailure>().having(
            (falha) => falha.message,
            'mensagem',
            allOf(contains('menciona'), contains('phone')),
          ),
        ),
      );
    });

    // O defeito que este guard prende: o corpo do método não estar no formato
    // com chaves que ele sabe ler. A versão anterior achava a chave de abertura
    // com `indexOf('{')` a partir do fechamento dos parênteses — num corpo de
    // expressão (`async => stdout.writeln(...)`, refactor legítimo e SEM
    // vazamento) isso salta para a próxima chave do ARQUIVO, lê o corpo de
    // `RecordingSmsGateway` e acusa a referência proibida no lugar errado; se o
    // bloco seguinte não tivesse essa referência, o guard passaria lendo lixo.
    // As duas saídas são ruins; a certa é dizer que não sabe ler.
    test('não sabe ler corpo de expressão — e diz isso, em vez de acusar outro '
        'trecho', () {
      expect(
        () => _leituraDoGatewayDeLog(fonte: _fonteComCorpoDeExpressao),
        throwsA(
          isA<TestFailure>().having(
            (falha) => falha.message,
            'mensagem',
            contains('não está no formato com chaves'),
          ),
        ),
      );
    });

    // A checagem que fecha a lista de parâmetros ficou sem teste dedicado na
    // rodada 2 (a discordância 4 de lá, divulgada em vez de provada). Ela
    // deixou de ser só diagnóstico: `_parametrosDe` recorta a assinatura por
    // esses dois índices, então um `parametersClose` em -1 passaria a estourar
    // um RangeError no `substring`, no lugar de dizer o que aconteceu. Este
    // teste é o respaldo que faltava, e a única forma de obter essa falha é
    // injetando a fonte.
    test('não sabe ler assinatura sem o `)` da lista de parâmetros — e diz '
        'isso', () {
      expect(
        () => _leituraDoGatewayDeLog(fonte: _fonteComAssinaturaSemFechar),
        throwsA(
          isA<TestFailure>().having(
            (falha) => falha.message,
            'mensagem',
            contains('não foi possível delimitar a lista de parâmetros'),
          ),
        ),
      );
    });
  });
}

/// Classe cujo corpo [main] vigia.
const _loggingGatewayClass = 'LoggingSmsGateway';

/// Método cujo corpo [main] vigia.
const _loggingGatewayMethod = 'sendOtp';

/// Fonte sintética com o formato que o guard tem de RECUSAR: corpo de
/// expressão, sem vazamento nenhum, seguido de outra classe.
///
/// A classe seguinte tem de conter uma interpolação proibida — é ela que
/// reproduz o defeito medido, e não um caso de laboratório: o `indexOf('{')`
/// de antes saltava para o corpo dela, e o guard acusava um trecho de
/// `LoggingSmsGateway` que não existe. É o mesmo arranjo do arquivo real, onde
/// o bloco seguinte é `RecordingSmsGateway`.
const _fonteComCorpoDeExpressao = r'''
class LoggingSmsGateway implements SmsGateway {
  @override
  Future<void> sendOtp({required String phone, required String code}) async =>
      stdout.writeln('[SMS-GATEWAY=log] código de acesso: $code ');
}

class RecordingSmsGateway implements SmsGateway {
  final sent = <({String phone, String code})>[];

  @override
  Future<void> sendOtp({required String phone, required String code}) async {
    sent.add((phone: phone, code: code));
  }
}
''';

/// Fonte sintética com o vazamento que a rodada 2 deixava passar: a referência
/// ao destino como ARGUMENTO, sem `$` nenhum, na mesma linha de log que
/// continua entregando o `code`.
///
/// É o corpo real de `LoggingSmsGateway.sendOtp` com uma linha acrescentada no
/// começo — o que o guard tem de ver é a menção, e não a forma do texto.
const _fonteComVazamentoDireto = r'''
class LoggingSmsGateway implements SmsGateway {
  @override
  Future<void> sendOtp({required String phone, required String code}) async {
    stdout.writeln(phone);
    stdout.writeln('[SMS-GATEWAY=log] código de acesso: $code ');
  }
}
''';

/// Fonte sintética cuja lista de parâmetros não fecha: não há um único `)`
/// depois do `sendOtp(`.
///
/// Não é um caso de laboratório — é uma edição pela metade (parêntese apagado,
/// colagem truncada) num arquivo que o guard lê como TEXTO, sem compilar. O
/// guard tem de dizer que não sabe delimitar a assinatura; sem essa checagem,
/// `_parametrosDe` recortaria um trecho inventado e o corpo seria lido de
/// qualquer lugar.
const _fonteComAssinaturaSemFechar = r'''
class LoggingSmsGateway implements SmsGateway {
  @override
  Future<void> sendOtp({required String phone, required String code
}
''';

/// O corpo de `LoggingSmsGateway.sendOtp` e os nomes declarados na sua
/// assinatura, com os comentários já apagados.
///
/// Lê o TEXTO-FONTE pelo mesmo motivo de
/// `endpoint_auth_posture_test.dart`, que já faz isso neste repositório: a
/// propriedade a prender não é observável em execução. O gateway escreve no
/// stdout do processo, e capturar o stdout provaria o que saiu hoje, não o que
/// o método pode voltar a escrever — a referência que este guard existe para
/// impedir apareceria de novo sem que nenhuma execução a denunciasse.
///
/// O CORPO continua sendo o recorte do que se proíbe: o parâmetro de destino
/// precisa continuar na assinatura, porque Dart exige que um override declare
/// os mesmos parâmetros nomeados da interface. O que mudou na rodada 3 é que a
/// assinatura deixou de ser ignorada — ela é LIDA para dar a lista de nomes
/// proibidos (ver `_parametrosDe`), e é isso que prende as duas formas de usar
/// o valor: `$phone` interpolado e `writeln(phone)` como argumento direto.
///
/// [fonte] é dos testes que provam o que este guard faz com uma fonte que ele
/// NÃO sabe ler, ou com um corpo que ele tem de recusar: sem poder injetar a
/// fonte, essas falhas só seriam observáveis editando `sms_gateway.dart` à mão.
/// Sem argumento, lê o arquivo de verdade.
({String corpo, Set<String> parametros}) _leituraDoGatewayDeLog({
  String? fonte,
}) {
  const path = 'lib/src/application/auth/sms_gateway.dart';
  final String cru;
  if (fonte != null) {
    cru = fonte;
  } else {
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'o teste roda com cwd em backend/sinalacs_server',
    );
    cru = file.readAsStringSync();
  }

  final source = _withoutComments(cru);
  final classAt = source.indexOf('class $_loggingGatewayClass');
  expect(
    classAt,
    isNot(-1),
    reason: '$_loggingGatewayClass não está mais em $path — se a classe saiu '
        'do projeto, este guard sai junto',
  );

  final methodAt = source.indexOf(_loggingGatewayMethod, classAt);
  expect(
    methodAt,
    isNot(-1),
    reason: '$_loggingGatewayClass.$_loggingGatewayMethod não existe mais em '
        '$path — aponte este guard para o método que passou a escrever o log',
  );

  final parametersOpen = source.indexOf('(', methodAt);
  final parametersClose = _matching(source, parametersOpen, '(', ')');
  // Sem o `)` da lista de parâmetros, o `indexOf('{')` de depois procuraria a
  // partir do começo do arquivo e o guard leria o primeiro bloco que
  // aparecesse — a mesma leitura de lixo que _bodyBraceAfter existe para
  // impedir, um passo antes dela. Desde a rodada 3 esta checagem tem um segundo
  // consumidor: `_parametrosDe` recorta a assinatura por esses índices, e com
  // -1 o `substring` estouraria um RangeError no lugar desta mensagem.
  expect(
    parametersClose,
    isNot(-1),
    reason: 'não foi possível delimitar a lista de parâmetros de '
        '$_loggingGatewayClass.$_loggingGatewayMethod em $path — sem isso o '
        'guard lê um trecho qualquer do arquivo',
  );

  final parametros = _parametrosDe(source, parametersOpen, parametersClose);
  final bodyOpen = _bodyBraceAfter(source, parametersClose);
  final bodyClose = _matching(source, bodyOpen, '{', '}');
  expect(
    bodyClose,
    isNot(-1),
    reason: 'não foi possível delimitar o corpo de '
        '$_loggingGatewayClass.$_loggingGatewayMethod em $path — sem isso o '
        'guard não lê nada e absolve tudo',
  );

  return (
    corpo: source.substring(bodyOpen, bodyClose + 1),
    parametros: parametros,
  );
}

/// As regras que o log de `LoggingSmsGateway.sendOtp` tem de satisfazer, mais as
/// auto-asserções que impedem este guard de absolver tudo.
///
/// É uma função, e não um bloco dentro do teste, por causa do teste da fonte
/// sintética (`_fonteComVazamentoDireto`): ele roda EXATAMENTE estas regras
/// contra um corpo que tem de ser recusado. Com as regras inline, provar que o
/// guard pega o vazamento direto exigiria uma cópia — e a cópia é justamente o
/// que sai de sincronia com o original.
void _exigeLogDoSmsSemDadoPessoal(
  ({String corpo, Set<String> parametros}) leitura,
) {
  final corpo = leitura.corpo;

  // Auto-teste 1: se a leitura do corpo quebrar, as asserções de baixo
  // passariam por não estar olhando para lugar nenhum — e um guard que não lê
  // nada absolve tudo.
  expect(
    corpo,
    contains('code'),
    reason: 'o corpo lido não menciona o código, que é o que a linha de log tem '
        'de entregar: a leitura deste guard quebrou; conserte-a antes de '
        'confiar nela',
  );

  // Auto-teste 2: uma assinatura lida errado (recorte vazio, regex quebrada)
  // devolveria LISTA VAZIA de nomes, e lista vazia de nomes proibidos absolve
  // qualquer menção. É a mesma armadilha do auto-teste 3, um nível acima: sem
  // nenhum nome lido, "o corpo não menciona nenhum deles" é verdade.
  expect(
    leitura.parametros,
    isNotEmpty,
    reason: 'o guard não leu NENHUM nome de parâmetro na assinatura de '
        '$_loggingGatewayClass.$_loggingGatewayMethod — a leitura quebrou; '
        'conserte-a antes de confiar nela',
  );

  final interpolacoes = _interpolacoesDe(corpo);

  // Auto-teste 3, e é ele que sustenta a regra 1: "toda interpolação é `code`"
  // é verdade para o conjunto VAZIO. Sem exigir conjunto não vazio, uma
  // extração que parasse de achar qualquer interpolação (regex quebrada, corpo
  // trocado) absolveria o corpo inteiro.
  expect(
    interpolacoes,
    isNotEmpty,
    reason: 'o guard não achou nenhuma interpolação no corpo de '
        '$_loggingGatewayClass.$_loggingGatewayMethod — a extração quebrou; '
        'conserte-a antes de confiar nela',
  );

  // Regra 1 — a forma interpolada (`$phone`, `${phone}`, `$telefone`).
  final interpoladasProibidas =
      interpolacoes.where((nome) => nome != 'code').toList()..sort();

  expect(
    interpoladasProibidas,
    isEmpty,
    reason: '$_loggingGatewayClass.$_loggingGatewayMethod interpola '
        '${interpoladasProibidas.join(', ')}, e não só `code`: o único chamador '
        'preenche o parâmetro de destino com `cpf.formatted`, então essa '
        'referência põe CPF em claro no log do processo. O texto do log tem de '
        'sair só do código — `code`, e nada mais.',
  );

  // Auto-teste 4, e é ele que sustenta a regra 2: a regra proíbe mencionar os
  // nomes da assinatura EXCETO `code`, então uma lista que trouxesse só `code`
  // deixaria a regra vazia — verde por não haver o que proibir, não por o corpo
  // estar limpo. A assinatura sempre declara o destino além do código (o
  // override tem de repetir os parâmetros nomeados de `SmsGateway.sendOtp`),
  // então uma leitura sem NENHUM nome além de `code` é leitura quebrada.
  expect(
    leitura.parametros.where((nome) => nome != 'code'),
    isNotEmpty,
    reason: 'o guard leu a assinatura de '
        '$_loggingGatewayClass.$_loggingGatewayMethod e não achou nenhum nome '
        'de parâmetro além de `code` — sem o nome do destino, a regra 2 não '
        'prende nada; a leitura quebrou',
  );

  // Regra 2 — a forma DIRETA da mesma referência: `writeln(phone)`,
  // `phone.length`, `_mascarar(phone)`. A regra 1 não vê nada disso, porque não
  // há `$` nenhum, e era exatamente por aí que o CPF saía com a suíte verde
  // antes desta rodada.
  final mencionados = leitura.parametros
      .where((nome) => nome != 'code' && _mencionaNoCorpo(corpo, nome))
      .toList()
    ..sort();

  expect(
    mencionados,
    isEmpty,
    reason: '$_loggingGatewayClass.$_loggingGatewayMethod menciona '
        '${mencionados.join(', ')} no corpo — e a assinatura só declara `code` '
        'para o texto do log. O único chamador preenche o parâmetro de destino '
        'com `cpf.formatted`, então qualquer menção a ele põe CPF em claro no '
        'log do processo, interpolada (`\$phone`) ou não (`writeln(phone)`). '
        'Renomear o parâmetro (para `telefone`, `destino`, `numero`) só muda o '
        'nome que aparece nesta mensagem: a lista sai da própria assinatura. Se '
        'o gateway passou a precisar do destino para alguma coisa que não seja '
        'escrevê-lo, este guard tem de ser repensado de propósito — não '
        'afrouxado.',
  );
}

/// `true` se [corpo] menciona [nome] como palavra — `$nome`, `${nome}`,
/// `writeln(nome)`, `nome.length`.
///
/// A fronteira de palavra é o que separa menção de coincidência: `telefonePessoal`
/// e `destinos` não mencionam `telefone` nem `destino`. O casamento é sobre o
/// corpo já sem comentários (`_withoutComments`), então um nome citado num
/// comentário não conta — comentário não vai para o log.
bool _mencionaNoCorpo(String corpo, String nome) => RegExp(
      '(?:^|[^A-Za-z0-9_])${RegExp.escape(nome)}(?![A-Za-z0-9_])',
    ).hasMatch(corpo);

/// Os nomes de parâmetro declarados na lista que vai de [parametersOpen] a
/// [parametersClose] em [source].
///
/// É daqui que sai a lista de nomes proibidos do guard, e é por isso que ela é
/// LIDA da assinatura em vez de fixada aqui: um parâmetro novo entra na lista
/// proibida sozinho, sem ninguém precisar lembrar de acrescentá-lo, e renomear
/// o destino (o refactor que a doc de `SmsGateway` empurra a fazer, porque
/// `phone` é nome falso para um CPF) não abre buraco nenhum.
///
/// Um nome de parâmetro é um identificador seguido de `,`, `=` ou do
/// fechamento da lista (`)`, `}`, `]`) — em qualquer forma que o Dart aceite:
/// nomeado, posicional, opcional, com valor padrão ou com tipo de função. O
/// recorte NÃO tenta distinguir nome de TIPO, de propósito: num parâmetro
/// genérico (`Map<String, int> destino`) ou de função (`void Function(String)
/// aoEnviar`) o tipo também casa e entra na lista proibida, e num valor padrão
/// casa um identificador de dentro dele. O falso positivo é aceito — o corpo
/// mencionar `String` faz o guard falhar e alguém olhar; tentar adivinhar qual
/// identificador é o nome é o que deixaria um nome de fora, que é o erro que
/// esta rodada existe para não repetir.
Set<String> _parametrosDe(
  String source,
  int parametersOpen,
  int parametersClose,
) =>
    _nomeNaAssinaturaPattern
        .allMatches(source.substring(parametersOpen + 1, parametersClose))
        .map((match) => match.group(1)!)
        .toSet();

/// Identificador imediatamente antes de um separador da lista de parâmetros.
final _nomeNaAssinaturaPattern =
    RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*(?=[,=)\]}])');

/// Índice da `{` que abre o corpo do método cuja lista de parâmetros fecha em
/// [parametersClose].
///
/// A chave tem de ser o primeiro token do CORPO: brancos não contam, e `async`
/// é modificador da assinatura, não do corpo. Qualquer outra coisa ali — um
/// corpo de expressão (`async => stdout.writeln(...)`) ou uma assinatura sem
/// chaves — faz este guard falhar dizendo que não sabe ler.
///
/// Não é preciosismo. `indexOf('{')` a partir do fechamento dos parênteses, que
/// era o que este guard fazia, num corpo de expressão salta para a próxima
/// chave do ARQUIVO: no arquivo de hoje, o corpo de `RecordingSmsGateway`, que
/// contém a palavra outrora proibida — e o guard acusava o lugar errado. Se o
/// bloco seguinte não a contivesse, o guard passaria lendo lixo, que é o mesmo
/// defeito calado. Exigir a chave onde ela tem de estar fecha os dois.
int _bodyBraceAfter(String source, int parametersClose) {
  var index = _semBrancos(source, parametersClose + 1);
  if (source.startsWith('async', index)) {
    index = _semBrancos(source, index + 'async'.length);
  }

  expect(
    index < source.length && source[index] == '{',
    isTrue,
    reason: 'o corpo de $_loggingGatewayClass.$_loggingGatewayMethod não está no '
        'formato com chaves que este guard sabe ler: depois da lista de '
        'parâmetros vem ${_trechoApos(source, index)}, e não `{`. Este guard '
        'delimita o corpo por casamento de chaves, e sem a chave de abertura '
        'ele saltaria para um bloco qualquer do arquivo e acusaria o trecho '
        'errado. Volte a escrever o método com corpo entre chaves ou reescreva '
        'este guard.',
  );
  return index;
}

/// Índice do primeiro caractere não branco a partir de [from].
int _semBrancos(String source, int from) {
  var index = from;
  while (index < source.length && _ehBranco(source[index])) {
    index++;
  }
  return index;
}

/// Trecho curto a partir de [from], para a mensagem de falha mostrar o que o
/// guard achou onde esperava a chave — um `=>` fica visível de imediato.
String _trechoApos(String source, int from) {
  if (from >= source.length) return 'o fim do arquivo';
  final end = from + 16 > source.length ? source.length : from + 16;
  return '"${source.substring(from, end).replaceAll('\n', ' ')}"';
}

bool _ehBranco(String char) =>
    char == ' ' || char == '\n' || char == '\r' || char == '\t';

/// Os nomes interpolados no texto de [body] — `$code`, `${code}`, `$telefone`.
///
/// A regex casa as duas formas de interpolação e devolve só o NOME, que é o
/// que o texto-fonte revela sobre o valor que entra na string. É o VALOR que o
/// guard prende: prender o nome de um parâmetro não prende nada, porque o
/// próximo a mexer no arquivo pode renomeá-lo.
///
/// `$` que não abre interpolação não casa, porque a regex exige um
/// identificador logo depois dele (`'R$ 5'` fica de fora). O falso positivo
/// aceito de propósito é o dólar escapado: um `\$telefone` (TEXTO literal no
/// log) casa como se fosse interpolação. Falhar a mais é o lado certo de
/// errar — esse texto literal não existe nesta linha, e o guard não pode
/// absolver um vazamento por causa de uma barra invertida.
final _interpolacaoPattern = RegExp(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?');

Set<String> _interpolacoesDe(String body) => _interpolacaoPattern
    .allMatches(body)
    .map((match) => match.group(1)!)
    .toSet();

/// Índice do fechamento que casa com a abertura em [open]; `-1` se não fechar.
int _matching(String source, int open, String opening, String closing) {
  if (open < 0) return -1;
  var depth = 0;
  for (var index = open; index < source.length; index++) {
    if (source[index] == opening) depth++;
    if (source[index] == closing) {
      depth--;
      if (depth == 0) return index;
    }
  }
  return -1;
}

/// Apaga os comentários, preservando comprimento, quebras de linha e o
/// conteúdo dos literais de texto.
///
/// Os literais são PRESERVADOS de propósito, ao contrário do que faz o
/// `_withoutCommentsOrStrings` de `endpoint_auth_posture_test.dart`: aqui a
/// interpolação proibida mora DENTRO de um literal (`'... para $phone: ...'`),
/// e apagá-los cegaria o guard exatamente no ponto que ele vigia.
///
/// E os literais são respeitados também na busca por comentários, para que um
/// `//` dentro de uma mensagem de log não engula o resto da linha — com isso, o
/// `$phone` de depois dele sairia de vista.
String _withoutComments(String source) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';

    if (char == '/' && next == '/') {
      while (index < source.length && source[index] != '\n') {
        buffer.write(' ');
        index++;
      }
      continue;
    }

    if (char == '/' && next == '*') {
      buffer.write('  ');
      index += 2;
      while (index < source.length &&
          !(source[index] == '*' &&
              index + 1 < source.length &&
              source[index + 1] == '/')) {
        buffer.write(source[index] == '\n' ? '\n' : ' ');
        index++;
      }
      if (index < source.length) {
        buffer.write('  ');
        index += 2;
      }
      continue;
    }

    if (char == "'" || char == '"') {
      final delimiter = source.startsWith(char * 3, index) ? char * 3 : char;
      buffer.write(delimiter);
      index += delimiter.length;
      while (index < source.length && !source.startsWith(delimiter, index)) {
        if (source[index] == r'\' && index + 1 < source.length) {
          buffer.write(source.substring(index, index + 2));
          index += 2;
          continue;
        }
        buffer.write(source[index]);
        index++;
      }
      if (index < source.length) {
        buffer.write(delimiter);
        index += delimiter.length;
      }
      continue;
    }

    buffer.write(char);
    index++;
  }
  return buffer.toString();
}
