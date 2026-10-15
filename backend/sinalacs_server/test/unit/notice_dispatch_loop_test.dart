import 'dart:async';

import 'package:sinalacs_server/src/runtime/notice_dispatch_loop.dart';
import 'package:test/test.dart';

void main() {
  test('o intervalo padrão é de 30 s', () {
    expect(defaultNoticeDispatchInterval, const Duration(seconds: 30));
  });

  test('a partida roda a varredura antes do primeiro ciclo', () async {
    final order = <String>[];
    final loop = NoticeDispatchLoop(
      startup: () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        order.add('startup');
      },
      tick: () async {
        order.add('tick');
        return 0;
      },
      interval: const Duration(hours: 1),
    )..start();
    await loop.runOnce();
    loop.stop();
    expect(order, ['startup', 'tick']);
  });

  test('erro no ciclo é registrado sem matar o laço', () async {
    var calls = 0;
    final errors = <Object>[];
    final loop = NoticeDispatchLoop(
      tick: () async {
        calls++;
        if (calls == 1) throw StateError('banco fora: texto do aviso');
        return 3;
      },
      onError: errors.add,
      interval: const Duration(hours: 1),
    );
    expect(await loop.runOnce(), 0);
    expect(await loop.runOnce(), 3);
    expect(errors, hasLength(1));
  });

  test('o timer injetado dispara ciclos e stop() o cancela', () async {
    late void Function(Timer) fire;
    final fake = _FakeTimer();
    var ticks = 0;
    final loop = NoticeDispatchLoop(
      tick: () async => ++ticks,
      timerFactory: (d, cb) {
        fire = cb;
        return fake;
      },
    )..start();
    expect(loop.isStarted, isTrue);
    fire(fake);
    await Future<void>.delayed(Duration.zero);
    expect(ticks, 1);
    loop.stop();
    expect(fake.cancelled, isTrue);
    expect(loop.isStarted, isFalse);
    expect(await loop.runOnce(), 0, reason: 'parado não processa');
  });

  test('ciclos não se sobrepõem', () async {
    final gate = Completer<void>();
    var ticks = 0;
    final loop = NoticeDispatchLoop(
      tick: () async {
        ticks++;
        await gate.future;
        return 1;
      },
      interval: const Duration(hours: 1),
    );
    final first = loop.runOnce();
    expect(await loop.runOnce(), 0);
    gate.complete();
    await first;
    expect(ticks, 1);
  });
}

class _FakeTimer implements Timer {
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}
