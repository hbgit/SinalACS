import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/secure_session_token_store.dart';
import 'package:sinalacs_acs/core/services/remote_wipe.dart';

import 'support/fakes.dart';

/// Limpeza remota do aparelho (#81): o coordenador é single-flight, grava o
/// diário ANTES de apagar (D7) e só o apaga depois de o servidor confirmar.
/// Ids sintéticos.
void main() {
  const orderId = '00000000-0000-4000-8000-0000000000aa';
  const idAntigo = '00000000-0000-4000-8000-0000000000d1';

  late FakeAcsBackend backend;
  late DeviceIdStore deviceIds;
  late MemoryWipeJournal journal;
  late List<String> eventos;
  late int eraseCalls;
  late int wipedCalls;
  Object? falhaDoErase;
  Completer<void>? eraseGate;

  Future<void> erase() async {
    eraseCalls++;
    eventos.add('erase');
    await eraseGate?.future;
    final falha = falhaDoErase;
    if (falha != null) throw falha;
    // O apagador real (Task 5) troca o id da instalação.
    await deviceIds.delete();
  }

  RemoteWipeCoordinator novo() => RemoteWipeCoordinator(
        backend: backend,
        deviceIds: deviceIds,
        journal: journal,
        erase: erase,
        onWiped: () {
          wipedCalls++;
          eventos.add('onWiped');
        },
      );

  setUp(() {
    backend = FakeAcsBackend();
    deviceIds = MemoryDeviceIdStore(idAntigo);
    journal = MemoryWipeJournal();
    eventos = <String>[];
    eraseCalls = 0;
    wipedCalls = 0;
    falhaDoErase = null;
    eraseGate = null;
    backend.onConfirmDeviceWipe = () => eventos.add('confirm');
  });

  test('check sem pedido não apaga nada', () async {
    final coordinator = novo();

    expect(await coordinator.check(), isFalse);

    expect(backend.pendingWipeQueries, [idAntigo]);
    expect(eraseCalls, 0);
    expect(wipedCalls, 0);
    expect(backend.confirmedWipes, isEmpty);
    expect(await journal.read(), isNull);
  });

  test('check sem rede devolve false e não lança', () async {
    backend.pendingWipeFailure = const BackendFailure('Sem conexão com o servidor.');

    expect(await novo().check(), isFalse);
    expect(eraseCalls, 0);
  });

  test('check com pedido apaga, chama onWiped e confirma com o deviceId antigo', () async {
    backend.pendingWipeOrderId = orderId;

    expect(await novo().check(), isTrue);

    expect(eraseCalls, 1);
    expect(wipedCalls, 1);
    expect(eventos, ['erase', 'onWiped', 'confirm']);
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: orderId)]);
    expect(await deviceIds.readOrCreate(), isNot(idAntigo), reason: 'o apagador trocou o id');
    expect(await journal.read(), isNull);
  });

  test('o diário é gravado em erasing ANTES de apagar', () async {
    eraseGate = Completer<void>();
    final apply = novo().apply(orderId);
    await pumpEventQueue();

    expect(eraseCalls, 1);
    expect(await journal.read(), (orderId: orderId, deviceId: idAntigo, phase: WipePhase.erasing));

    eraseGate!.complete();
    await apply;
    expect(await journal.read(), isNull);
  });

  test('gatilhos concorrentes compartilham uma só limpeza', () async {
    backend.pendingWipeOrderId = orderId;
    eraseGate = Completer<void>();
    final coordinator = novo();

    final todos = Future.wait<Object?>([coordinator.check(), coordinator.apply(orderId), coordinator.apply(orderId)]);
    await pumpEventQueue();
    eraseGate!.complete();
    await todos;
    // Um gatilho atrasado depois da limpeza também não refaz nada.
    await coordinator.apply(orderId);

    expect(eraseCalls, 1);
    expect(backend.confirmedWipes, hasLength(1));
    expect(wipedCalls, 1);
  });

  test('gatilho que chega depois da limpeza não apaga de novo', () async {
    backend.pendingWipeOrderId = orderId;
    backend.pendingWipeGate = Completer<void>();
    final coordinator = novo();

    // A consulta sai com o id antigo, mas a resposta chega depois de outro
    // gatilho já ter limpado e confirmado.
    final consulta = coordinator.check();
    await pumpEventQueue();
    await coordinator.apply(orderId);
    backend.pendingWipeGate!.complete();
    await consulta;

    expect(eraseCalls, 1);
    expect(backend.confirmedWipes, hasLength(1));
  });

  test('confirmação sem rede fica no diário e é reenviada', () async {
    backend.confirmWipeFailure = const BackendFailure('Sem conexão com o servidor.');

    await novo().apply(orderId);

    expect(eraseCalls, 1);
    expect(wipedCalls, 1);
    expect(await journal.read(), (orderId: orderId, deviceId: idAntigo, phase: WipePhase.erased));

    // Próxima partida: só reenvia a confirmação, com o id antigo do diário.
    backend.confirmWipeFailure = null;
    await novo().resumePending();

    expect(eraseCalls, 1, reason: 'erased não apaga de novo');
    // A 1ª confirmação falhou (não chegou); a reenviada leva o id antigo.
    expect(eventos.where((e) => e == 'confirm'), hasLength(2));
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: orderId)]);
    expect(await journal.read(), isNull);
  });

  test('diário em erasing termina a limpeza na partida antes de abrir o banco', () async {
    // O processo morreu no meio da limpeza, antes de trocar o id da
    // instalação (o último passo do apagador).
    await journal.write(orderId, idAntigo, WipePhase.erasing);

    await novo().resumePending();

    expect(eventos, ['erase', 'onWiped', 'confirm']);
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: orderId)]);
    expect(await journal.read(), isNull);
  });

  test('diário preso em erasing com o id já trocado: a limpeza terminou, só confirma (I2)', () async {
    // Outra execução: o apagador foi até o fim (o id é outro), mas o diário
    // não chegou a `erased`. Apagar de novo levaria as visitas do login novo.
    await journal.write(orderId, idAntigo, WipePhase.erasing);
    deviceIds = MemoryDeviceIdStore('00000000-0000-4000-8000-0000000000d2');

    await novo().resumePending();

    expect(eraseCalls, 0);
    expect(wipedCalls, 0, reason: 'a tela de limpeza já foi mostrada naquela execução');
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: orderId)]);
    expect(await journal.read(), isNull);
  });

  test('diário preso em erasing na MESMA execução: resumePending não apaga de novo (I2)', () async {
    final diario = _DiarioQueFalhaEmErased();
    journal = diario;
    backend.confirmWipeFailure = const BackendFailure('Sem conexão com o servidor.');
    final coordinator = novo();

    await coordinator.apply(orderId);
    expect(eraseCalls, 1);
    expect((await journal.read())?.phase, WipePhase.erasing, reason: 'gravar erased falhou e a confirmação também');

    // Retomadas e voltas da rede depois de "Entrar de novo".
    await coordinator.resumePending();
    await coordinator.resumePending();

    expect(eraseCalls, 1);
    expect(wipedCalls, 1);
    expect(eventos.where((e) => e == 'confirm'), hasLength(3), reason: 'só a confirmação é reenviada');
    expect((await journal.read())?.phase, WipePhase.erased, reason: 'o diário passa a dizer o que aconteceu');
  });

  test('diário preso em erasing com o id ilegível: refaz a limpeza (lado seguro)', () async {
    await journal.write(orderId, idAntigo, WipePhase.erasing);
    deviceIds = _IdQueFalha();

    await novo().resumePending();

    expect(eraseCalls, 1);
  });

  test('confirmTimeout limita só a confirmação: servidor mudo não prende a retomada (M1)', () async {
    await journal.write(orderId, idAntigo, WipePhase.erased);
    backend.confirmWipeGate = Completer<void>();

    await novo().resumePending(confirmTimeout: const Duration(milliseconds: 50));

    expect(eraseCalls, 0);
    expect(await journal.read(), (orderId: orderId, deviceId: idAntigo, phase: WipePhase.erased),
        reason: 'a confirmação sem resposta segue no diário');
    backend.confirmWipeGate!.complete();
  });

  test('confirmTimeout não corta a limpeza em si (M1)', () async {
    await journal.write(orderId, idAntigo, WipePhase.erasing);
    eraseGate = Completer<void>();
    var terminou = false;
    final retomada = novo().resumePending(confirmTimeout: const Duration(milliseconds: 10)).then((_) => terminou = true);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(terminou, isFalse, reason: 'a retomada espera o apagador, sem teto');
    eraseGate!.complete();
    await retomada;
    expect(eraseCalls, 1);
    expect(await journal.read(), isNull);
  });

  test('resumePending sem diário não faz nada', () async {
    await novo().resumePending();

    expect(eraseCalls, 0);
    expect(backend.pendingWipeQueries, isEmpty);
    expect(backend.confirmedWipes, isEmpty);
  });

  test('falha do erase mantém erasing e não confirma', () async {
    falhaDoErase = StateError('disco ocupado');
    final coordinator = novo();

    await expectLater(coordinator.apply(orderId), throwsA(isA<StateError>()));

    expect(await journal.read(), (orderId: orderId, deviceId: idAntigo, phase: WipePhase.erasing));
    expect(backend.confirmedWipes, isEmpty);
    expect(wipedCalls, 0);

    // A próxima partida tenta de novo.
    falhaDoErase = null;
    await novo().resumePending();

    expect(eraseCalls, 2);
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: orderId)]);
    expect(await journal.read(), isNull);
  });

  test('check com falha do erase devolve false e não lança', () async {
    backend.pendingWipeOrderId = orderId;
    falhaDoErase = StateError('disco ocupado');

    expect(await novo().check(), isFalse);
    expect(backend.confirmedWipes, isEmpty);
  });

  test('o pedido vindo do BackendClient dispara apply', () async {
    final coordinator = novo();
    backend.onDeviceWipeRequired = (id) => unawaited(coordinator.apply(id));

    backend.onDeviceWipeRequired!(orderId);
    await pumpEventQueue();

    expect(eraseCalls, 1);
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: orderId)]);
  });

  group('SharedPreferencesWipeJournal', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('grava, lê e apaga o diário em acs_remote_wipe_journal', () async {
      final diario = SharedPreferencesWipeJournal();
      expect(await diario.read(), isNull);

      await diario.write(orderId, idAntigo, WipePhase.erased);

      expect(await diario.read(), (orderId: orderId, deviceId: idAntigo, phase: WipePhase.erased));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('acs_remote_wipe_journal'), contains('"phase":"erased"'));

      await diario.clear();
      expect(await diario.read(), isNull);
      expect(prefs.containsKey('acs_remote_wipe_journal'), isFalse);
    });

    test('diário ilegível é descartado como ausente', () async {
      SharedPreferences.setMockInitialValues({'acs_remote_wipe_journal': 'lixo'});
      expect(await SharedPreferencesWipeJournal().read(), isNull);
    });
  });

  test('SecureStorageDeviceIdStore.delete apaga acs_device_id e o próximo id é outro', () async {
    final storage = _MapStorage();
    final ids = SecureStorageDeviceIdStore(storage: storage);
    final primeiro = await ids.readOrCreate();
    expect(storage.data['acs_device_id'], primeiro);

    await ids.delete();
    expect(storage.data.containsKey('acs_device_id'), isFalse);

    final segundo = await ids.readOrCreate();
    expect(segundo, isNot(primeiro));
    expect(storage.data['acs_device_id'], segundo);
  });

  test('MemoryDeviceIdStore.delete troca o id', () async {
    final ids = MemoryDeviceIdStore(idAntigo);
    await ids.delete();
    expect(await ids.readOrCreate(), isNot(idAntigo));
  });
}

/// Diário cuja PRIMEIRA gravação de `erased` falha (disco cheio, por exemplo).
class _DiarioQueFalhaEmErased extends MemoryWipeJournal {
  bool _falhou = false;

  @override
  Future<void> write(String orderId, String deviceId, WipePhase phase) async {
    if (phase == WipePhase.erased && !_falhou) {
      _falhou = true;
      throw StateError('diário não gravado');
    }
    await super.write(orderId, deviceId, phase);
  }
}

class _IdQueFalha implements DeviceIdStore {
  @override
  Future<String> readOrCreate() async => throw StateError('Keystore indisponível');

  @override
  Future<void> delete() async {}
}

class _MapStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key] = value!;

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
