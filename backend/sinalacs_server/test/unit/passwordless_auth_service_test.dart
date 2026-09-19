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
    // A versão anterior deste guard prendia o NOME `phone`
    // (`RegExp(r'\bphone\b')`), e nome não é dado: renomear o parâmetro para
    // `telefone` — exatamente o que a doc desta classe empurra a fazer, já que
    // ela mesma diz que `phone` é nome falso para um CPF — e reintroduzir a
    // referência na linha de log deixava a suíte INTEIRA verde. O que este
    // guard prende agora é o VALOR referenciado no corpo: toda interpolação
    // tem de ser `code`, seja qual for o nome que o parâmetro venha a ter.
    test('registra o código e nenhuma outra interpolação', () {
      final body = _loggingGatewayBody();

      // Auto-teste: se a extração do corpo quebrar, as asserções de baixo
      // passariam por não estar olhando para lugar nenhum — e um guard que não
      // lê nada absolve tudo.
      expect(
        body,
        contains('code'),
        reason: 'o corpo lido não menciona o código, que é o que a linha de log '
            'tem de entregar: a extração deste guard quebrou; conserte-a antes '
            'de confiar nela',
      );

      final interpolacoes = _interpolacoesDe(body);

      // Segundo auto-teste, e é ele que sustenta o de baixo: "toda interpolação
      // é `code`" é verdade para o conjunto VAZIO. Sem exigir conjunto não
      // vazio, uma extração que parasse de achar qualquer interpolação (regex
      // quebrada, corpo trocado) absolveria o corpo inteiro — o defeito desta
      // rodada, um nível mais fundo.
      expect(
        interpolacoes,
        isNotEmpty,
        reason: 'o guard não achou nenhuma interpolação no corpo de '
            '$_loggingGatewayClass.$_loggingGatewayMethod — a extração quebrou; '
            'conserte-a antes de confiar nela',
      );

      final proibidas = interpolacoes.where((nome) => nome != 'code').toList();

      expect(
        proibidas,
        isEmpty,
        reason: '$_loggingGatewayClass.$_loggingGatewayMethod interpola '
            '${proibidas.join(', ')}, e não só `code`: o único chamador '
            'preenche o parâmetro de destino com `cpf.formatted`, então essa '
            'referência põe CPF em claro no log do processo. O texto do log tem '
            'de sair só do código — `code`, e nada mais. Renomear o parâmetro '
            '(para `telefone`, `destino`, `numero`) não escapa daqui: o guard '
            'prende o VALOR referenciado no corpo, não o nome `phone`.',
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
        () => _loggingGatewayBody(fonte: _fonteComCorpoDeExpressao),
        throwsA(
          isA<TestFailure>().having(
            (falha) => falha.message,
            'mensagem',
            contains('não está no formato com chaves'),
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

/// O corpo de `LoggingSmsGateway.sendOtp`, com os comentários já apagados.
///
/// Lê o TEXTO-FONTE pelo mesmo motivo de
/// `endpoint_auth_posture_test.dart`, que já faz isso neste repositório: a
/// propriedade a prender não é observável em execução. O gateway escreve no
/// stdout do processo, e capturar o stdout provaria o que saiu hoje, não o que
/// o método pode voltar a escrever — a interpolação que este guard existe para
/// impedir apareceria de novo sem que nenhuma execução a denunciasse.
///
/// A ASSINATURA fica fora do recorte de propósito: Dart exige que um override
/// declare os mesmos parâmetros nomeados da interface, então o parâmetro de
/// destino precisa continuar na lista. O que se pode proibir — e é o que basta
/// — é o corpo USAR o valor, e é o valor (não o nome dele) que o guard prende.
///
/// [fonte] é do teste que prova o que este guard faz com um corpo que ele NÃO
/// sabe ler: sem poder injetar a fonte, essa falha só seria observável editando
/// `sms_gateway.dart` à mão. Sem argumento, lê o arquivo de verdade.
String _loggingGatewayBody({String? fonte}) {
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
  // impedir, um passo antes dela.
  expect(
    parametersClose,
    isNot(-1),
    reason: 'não foi possível delimitar a lista de parâmetros de '
        '$_loggingGatewayClass.$_loggingGatewayMethod em $path — sem isso o '
        'guard lê um trecho qualquer do arquivo',
  );

  final bodyOpen = _bodyBraceAfter(source, parametersClose);
  final bodyClose = _matching(source, bodyOpen, '{', '}');
  expect(
    bodyClose,
    isNot(-1),
    reason: 'não foi possível delimitar o corpo de '
        '$_loggingGatewayClass.$_loggingGatewayMethod em $path — sem isso o '
        'guard não lê nada e absolve tudo',
  );

  return source.substring(bodyOpen, bodyClose + 1);
}

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
