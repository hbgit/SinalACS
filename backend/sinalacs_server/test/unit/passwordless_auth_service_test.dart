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
      final semSms = RecordingSmsGateway();
      final semSmsNascimento = RecordingSmsGateway();
      final inexistente = _build(store: _FakeStore(), gateway: semSms);
      final comOutroNascimento = _build(
        store: _FakeStore(record: encontrado),
        gateway: semSmsNascimento,
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
}
