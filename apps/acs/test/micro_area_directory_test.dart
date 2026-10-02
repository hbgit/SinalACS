import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'support/fakes.dart';
import 'support/memory_micro_area_store.dart';

AuthSession _sessao({String userId = 'u1', String? microAreaId = 'm1'}) => AuthSession(
      accessToken: 't',
      tokenType: 'Bearer',
      userId: userId,
      role: 'acs',
      microAreaId: microAreaId,
      expiresAt: DateTime.utc(2030),
    );

MicroAreaPatient _p(int n) =>
    MicroAreaPatient(patientId: syntheticPatientId(n), name: 'P$n', isChronic: false, chronicConditions: const []);

void main() {
  late MemoryMicroAreaStore store;
  late DateTime agora;
  late AuthSession? sessao;
  late Future<List<MicroAreaPatient>> Function() busca;

  MicroAreaDirectory diretorio() => MicroAreaDirectory(
        fetch: () => busca(),
        session: () => sessao,
        store: store,
        clock: () => agora,
      );

  setUp(() {
    store = MemoryMicroAreaStore();
    agora = DateTime.utc(2026, 10, 2, 8);
    sessao = _sessao();
    busca = () async => [_p(1), _p(2)];
  });

  test('com rede: devolve a lista fresca e grava', () async {
    final r = await diretorio().load();

    expect(r.fromCache, isFalse);
    expect(r.patients, hasLength(2));
    expect(store.patients, hasLength(2));
    expect(store.owner, 'u1|m1');
  });

  test('sem rede, com cache do mesmo dono: serve o cache e diz a data', () async {
    await diretorio().load();
    agora = agora.add(const Duration(hours: 5));
    busca = () async => throw const BackendFailure('Sem conexão.');

    final r = await diretorio().load();

    expect(r.fromCache, isTrue);
    expect(r.patients, hasLength(2));
    expect(r.fetchedAt, DateTime.utc(2026, 10, 2, 8));
  });

  test('sem rede e sem cache: a falha original sobe', () async {
    busca = () async => throw const BackendFailure('Sem conexão.');
    await expectLater(diretorio().load(), throwsA(isA<BackendFailure>()));
  });

  test('recusa do servidor NUNCA cai no cache', () async {
    await diretorio().load();
    busca = () async => throw const BackendFailure('Sessão inválida.', isRecoverable: false);

    await expectLater(diretorio().load(), throwsA(isA<BackendFailure>()));
  });

  test('outro dono apaga e não serve', () async {
    await diretorio().load();
    sessao = _sessao(userId: 'u2');
    busca = () async => throw const BackendFailure('Sem conexão.');

    await expectLater(diretorio().load(), throwsA(isA<BackendFailure>()));
    expect(store.owner, isNull, reason: 'o cache do outro usuário foi apagado');
  });

  test('outra microárea apaga e não serve', () async {
    await diretorio().load();
    sessao = _sessao(microAreaId: 'm2');
    busca = () async => throw const BackendFailure('Sem conexão.');

    await expectLater(diretorio().load(), throwsA(isA<BackendFailure>()));
    expect(store.owner, isNull);
  });

  test('vencido não serve e é apagado', () async {
    await diretorio().load();
    agora = agora.add(const Duration(hours: 73));
    busca = () async => throw const BackendFailure('Sem conexão.');

    await expectLater(diretorio().load(), throwsA(isA<BackendFailure>()));
    expect(store.owner, isNull);
  });

  test('exatamente 72 h ainda serve', () async {
    await diretorio().load();
    agora = agora.add(const Duration(hours: 72));
    busca = () async => throw const BackendFailure('Sem conexão.');

    expect((await diretorio().load()).fromCache, isTrue);
  });

  test('falha ao gravar o cache não derruba a lista fresca', () async {
    store.falhaAoGravar = true;
    final r = await diretorio().load();
    expect(r.patients, hasLength(2));
    expect(r.fromCache, isFalse);
  });

  test('sem sessão não há dono: nada é lido nem gravado', () async {
    sessao = null;
    final r = await diretorio().load();
    expect(r.fromCache, isFalse);
    expect(store.owner, isNull);
  });

  test('lista vazia fresca substitui o cache (a microárea esvaziou)', () async {
    await diretorio().load();
    busca = () async => <MicroAreaPatient>[];
    await diretorio().load();
    expect(store.patients, isEmpty);
  });
}
