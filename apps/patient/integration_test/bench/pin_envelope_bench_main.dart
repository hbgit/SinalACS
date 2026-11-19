// Bancada da #170: mede, em build release no aparelho, quanto custa derivar a
// chave do envelope do PIN (Argon2id m = 19 MiB, t = 2, p = 1, 32 bytes — D3)
// e quanto a thread da UI fica sem responder enquanto isso acontece.
//
// Não faz parte do app: é um `main` próprio, fora de `lib/`, que não termina
// em `_test.dart` (o `flutter test integration_test` não o descobre). Rodar:
//
//   cd apps/patient
//   flutter run --release -d <aparelho> -t integration_test/bench/pin_envelope_bench_main.dart
//
// e ler as linhas `BENCH ...` no console (ou `adb logcat -s flutter`). PIN e
// salt são sintéticos; nada é gravado.
//
// Variantes:
//   A  `Argon2id(...)` como o envelope da C-05 faz, chamado da thread principal
//      (o `package:cryptography` 2.9.0 já preenche a memória num isolate dele);
//   B  a mesma derivação inteira dentro de `Isolate.run` (a proposta da #170);
//   C  `DartArgon2id(maxIsolates: 0)` na thread principal, sem isolate nenhum:
//      o pior caso, só como referência do que a issue presumia.
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _memory = 19456;
const _iterations = 2;
const _parallelism = 1;
const _hashLength = 32;
const _runs = 5;

final _pin = utf8.encode('284637');
final _salt = List<int>.generate(16, (i) => (i * 37 + 11) & 0xff);

Future<List<int>> _variantA() async {
  final kdf = Argon2id(memory: _memory, iterations: _iterations, parallelism: _parallelism, hashLength: _hashLength);
  final key = await kdf.deriveKey(secretKey: SecretKey(_pin), nonce: _salt);
  return key.extractBytes();
}

Future<List<int>> _deriveInIsolate(List<int> pin, List<int> salt) async {
  final kdf = Argon2id(memory: _memory, iterations: _iterations, parallelism: _parallelism, hashLength: _hashLength);
  final key = await kdf.deriveKey(secretKey: SecretKey(pin), nonce: salt);
  return key.extractBytes();
}

Future<List<int>> _variantB() {
  final pin = List<int>.of(_pin);
  final salt = List<int>.of(_salt);
  return Isolate.run(() => _deriveInIsolate(pin, salt));
}

Future<List<int>> _variantC() async {
  const kdf = DartArgon2id(
    memory: _memory,
    iterations: _iterations,
    parallelism: _parallelism,
    hashLength: _hashLength,
    maxIsolates: 0,
  );
  final key = await kdf.deriveKey(secretKey: SecretKey(_pin), nonce: _salt);
  return key.extractBytes();
}

class _Result {
  _Result(this.totalMs, this.maxGapMs, this.frames, this.maxBuildMs);
  final int totalMs;
  final int maxGapMs;
  final int frames;
  final int maxBuildMs;
}

Future<_Result> _measure(Future<List<int>> Function() derive) async {
  final frames = <FrameTiming>[];
  void onTimings(List<FrameTiming> t) => frames.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(onTimings);

  var maxGap = 0;
  final tick = Stopwatch()..start();
  var last = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
    final now = tick.elapsedMilliseconds;
    final gap = now - last;
    if (gap > maxGap) maxGap = gap;
    last = now;
  });

  final total = Stopwatch()..start();
  await derive();
  total.stop();
  // Um tique depois do fim, para o último bloqueio (se houver) entrar na conta.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  timer.cancel();
  SchedulerBinding.instance.removeTimingsCallback(onTimings);

  var maxBuild = 0;
  for (final f in frames) {
    final b = f.buildDuration.inMilliseconds;
    if (b > maxBuild) maxBuild = b;
  }
  return _Result(total.elapsedMilliseconds, maxGap, frames.length, maxBuild);
}

int _median(List<int> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

void main() => runApp(const _BenchApp());

class _BenchApp extends StatefulWidget {
  const _BenchApp();

  @override
  State<_BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<_BenchApp> {
  final _lines = <String>[];

  void _log(String line) {
    // ignore: avoid_print
    print(line);
    if (mounted) setState(() => _lines.add(line));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final expected = await _variantA();
    _log('BENCH inicio m=$_memory t=$_iterations p=$_parallelism saida=$_hashLength runs=$_runs');
    for (final (nome, derive) in [('A', _variantA), ('B', _variantB), ('C', _variantC)]) {
      final check = await derive();
      final mesma = check.length == expected.length &&
          List.generate(check.length, (i) => check[i] == expected[i]).every((x) => x);
      final totals = <int>[], gaps = <int>[];
      for (var i = 0; i < _runs; i++) {
        final r = await _measure(derive);
        totals.add(r.totalMs);
        gaps.add(r.maxGapMs);
        _log('BENCH variante=$nome run=$i total_ms=${r.totalMs} max_gap_ui_ms=${r.maxGapMs} '
            'quadros=${r.frames} max_build_ms=${r.maxBuildMs}');
      }
      _log('BENCH resumo variante=$nome mesma_chave=$mesma mediana_total_ms=${_median(totals)} '
          'max_total_ms=${totals.reduce((a, b) => a > b ? a : b)} '
          'mediana_gap_ui_ms=${_median(gaps)} max_gap_ui_ms=${gaps.reduce((a, b) => a > b ? a : b)}');
    }
    _log('BENCH fim');
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Bancada #170')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            for (final l in _lines) Text(l, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ]),
        ),
      );
}
