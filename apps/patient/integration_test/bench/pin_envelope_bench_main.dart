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
//      o pior caso, só como referência do que a issue presumia;
//   D  `Isolate.run` com `DartArgon2id(maxIsolates: 0)` dentro: a derivação
//      inteira fora da thread da UI sem o isolate extra da biblioteca;
//   P1 `PinEnvelope.encrypt`, o código do app ao criar o PIN (derivação no
//      `Isolate.run` da #170 + AES-GCM);
//   P2 `PinEnvelope.decrypt`, o código do app ao entrar com o PIN;
//   Z  linha de base: nenhuma derivação, só uma espera do tamanho da de A,
//      para separar o atraso da derivação do ruído do relógio e dos quadros.
//
// Métricas por rodada: tempo total; maior atraso entre dois tiques de um
// `Timer` de 8 ms (a thread da UI sem atender a fila de eventos); quadros
// desenhados durante a derivação e o maior intervalo entre dois quadros
// (`addPersistentFrameCallback`, com o `CircularProgressIndicator` girando:
// é a prova de que o indicador anima).
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sinalacs_patient/core/security/pin_envelope.dart';

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

Future<List<int>> _deriveInIsolateNoInnerIsolate(List<int> pin, List<int> salt) async {
  const kdf = DartArgon2id(
    memory: _memory,
    iterations: _iterations,
    parallelism: _parallelism,
    hashLength: _hashLength,
    maxIsolates: 0,
  );
  final key = await kdf.deriveKey(secretKey: SecretKey(pin), nonce: salt);
  return key.extractBytes();
}

Future<List<int>> _variantD() {
  final pin = List<int>.of(_pin);
  final salt = List<int>.of(_salt);
  return Isolate.run(() => _deriveInIsolateNoInnerIsolate(pin, salt));
}

final _envelope = PinEnvelope();
String? _sealed;

Future<List<int>> _variantP1() async {
  _sealed = await _envelope.encrypt(pin: '284637', plaintext: 'segredo-sintetico');
  return const <int>[];
}

Future<List<int>> _variantP2() async {
  await _envelope.decrypt(pin: '284637', envelopeJson: _sealed!);
  return const <int>[];
}

int _baselineMs = 230;

Future<List<int>> _variantZ() async {
  await Future<void>.delayed(Duration(milliseconds: _baselineMs));
  return const <int>[];
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
  _Result(this.totalMs, this.maxGapMs, this.frames, this.maxFrameIntervalMs);
  final int totalMs;
  final int maxGapMs;
  final int frames;
  final int maxFrameIntervalMs;
}

/// Conta os quadros desenhados enquanto [_counting] está ligado e o maior
/// intervalo entre dois deles. Registrado uma vez (o callback persistente não
/// tem remoção).
bool _counting = false;
int _frames = 0;
int _maxFrameInterval = 0;
Duration? _lastFrame;
bool _frameCallbackRegistered = false;

void _ensureFrameCounter() {
  if (_frameCallbackRegistered) return;
  _frameCallbackRegistered = true;
  SchedulerBinding.instance.addPersistentFrameCallback((timeStamp) {
    if (!_counting) return;
    final last = _lastFrame;
    if (last != null) {
      final interval = (timeStamp - last).inMilliseconds;
      if (interval > _maxFrameInterval) _maxFrameInterval = interval;
    }
    _lastFrame = timeStamp;
    _frames++;
  });
}

Future<_Result> _measure(Future<List<int>> Function() derive) async {
  _ensureFrameCounter();
  _frames = 0;
  _maxFrameInterval = 0;
  _lastFrame = null;
  _counting = true;

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
  _counting = false;
  final frames = _frames;
  final maxFrameInterval = _maxFrameInterval;
  // Um tique depois do fim, para o último bloqueio (se houver) entrar na conta.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  timer.cancel();
  return _Result(total.elapsedMilliseconds, maxGap, frames, maxFrameInterval);
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
    final aquecimento = Stopwatch()..start();
    await _variantA();
    _baselineMs = aquecimento.elapsedMilliseconds;
    _log('BENCH inicio m=$_memory t=$_iterations p=$_parallelism saida=$_hashLength runs=$_runs '
        'base_ms=$_baselineMs');
    for (final (nome, derive) in [
      ('Z', _variantZ),
      ('A', _variantA),
      ('B', _variantB),
      ('C', _variantC),
      ('D', _variantD),
      ('P1', _variantP1),
      ('P2', _variantP2),
    ]) {
      final check = await derive();
      final mesma = nome == 'Z' || nome.startsWith('P') ||
          (check.length == expected.length &&
              List.generate(check.length, (i) => check[i] == expected[i]).every((x) => x));
      final totals = <int>[], gaps = <int>[], intervals = <int>[], fps = <int>[];
      for (var i = 0; i < _runs; i++) {
        final r = await _measure(derive);
        totals.add(r.totalMs);
        gaps.add(r.maxGapMs);
        intervals.add(r.maxFrameIntervalMs);
        fps.add(r.totalMs == 0 ? 0 : (r.frames * 1000 / r.totalMs).round());
        _log('BENCH variante=$nome run=$i total_ms=${r.totalMs} max_gap_ui_ms=${r.maxGapMs} '
            'quadros=${r.frames} max_intervalo_quadro_ms=${r.maxFrameIntervalMs}');
      }
      int maior(List<int> v) => v.reduce((a, b) => a > b ? a : b);
      _log('BENCH resumo variante=$nome mesma_chave=$mesma mediana_total_ms=${_median(totals)} '
          'max_total_ms=${maior(totals)} mediana_gap_ui_ms=${_median(gaps)} max_gap_ui_ms=${maior(gaps)} '
          'mediana_quadros_por_s=${_median(fps)} max_intervalo_quadro_ms=${maior(intervals)}');
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
