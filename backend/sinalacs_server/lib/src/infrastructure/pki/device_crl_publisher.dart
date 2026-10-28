import 'dart:async';
import 'dart:io';

import 'package:sinalacs_server/src/application/devices/device_certificate_service.dart';
import 'package:sinalacs_server/src/config/device_ca_config.dart';
import 'package:sinalacs_server/src/infrastructure/pki/atomic_file.dart';
import 'package:sinalacs_server/src/infrastructure/pki/openssl_device_ca.dart';

/// A geração da CRL (`OpensslDeviceCa.buildCrl`), injetável nos testes.
typedef BuildCrl =
    Future<String> Function({
      required List<RevokedEntry> revoked,
      required BigInt crlNumber,
      required DateTime now,
      required int days,
    });

/// Publica a CRL dos aparelhos (#94) no arquivo que o broker relê.
///
/// Cada publicação lê do banco as revogadas não vencidas e o próximo
/// `CRL Number`, gera a CRL com a CA e a grava com [writeFileAtomically],
/// **validando a assinatura contra a CA** no temporário antes do `rename`
/// (`openssl crl -CAfile ca.crt -noout`): uma CRL corrompida ou assinada por
/// outra CA nunca substitui a anterior.
///
/// - **Single-flight:** uma publicação por vez; quem chama durante uma em
///   curso espera a seguinte, que é uma só para todos os que chegaram juntos.
/// - **Falha não é engolida:** openssl, disco ou validação marcam
///   [pendingSince], vão ao log só pelo tipo do erro e agendam nova tentativa
///   com recuo exponencial ([initialBackoff], dobrando, até [maxBackoff]), sem
///   teto de tentativas, até uma publicação completa — aí [pendingSince] volta
///   a `null`. [publish] durante a espera tenta na hora e zera o recuo.
/// - [publish] nunca lança: quem revoga já fez o commit e não pode receber
///   erro por causa do arquivo.
///
/// O log traz só a contagem e o número da CRL, nunca serial ou CN.
class DeviceCrlPublisher implements CrlPublication {
  DeviceCrlPublisher({
    required DeviceCaConfig config,
    required DeviceCrlSource source,
    BuildCrl? buildCrl,
    Future<void> Function(String path, String pem)? writeCrl,
    void Function(String line)? log,
    DateTime Function()? clock,
    Duration initialBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(minutes: 5),
  }) : _config = config,
       _source = source,
       _build = buildCrl ?? OpensslDeviceCa(config).buildCrl,
       _log = log ?? stderr.writeln,
       _clock = clock ?? DateTime.now,
       _initialBackoff = initialBackoff,
       _maxBackoff = maxBackoff < initialBackoff ? initialBackoff : maxBackoff,
       _backoff = initialBackoff {
    _write = writeCrl ?? _gravarValidada;
  }

  final DeviceCaConfig _config;
  final DeviceCrlSource _source;
  final BuildCrl _build;
  late final Future<void> Function(String path, String pem) _write;
  final void Function(String line) _log;
  final DateTime Function() _clock;
  final Duration _initialBackoff;
  final Duration _maxBackoff;

  Duration _backoff;
  Timer? _retry;
  DateTime? _pendingSince;
  Future<void>? _emCurso;
  Future<void>? _seguinte;
  bool _closed = false;

  /// Instante da primeira falha ainda não superada; `null` = a última
  /// publicação completou.
  DateTime? get pendingSince => _pendingSince;

  @override
  Future<void> publish({DateTime? now}) {
    if (_closed) return Future.value();
    _retry?.cancel();
    _retry = null;
    _backoff = _initialBackoff;
    return _agendar(now);
  }

  /// Cancela a tentativa agendada; publicações seguintes viram no-op.
  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _retry = null;
  }

  Future<void> _agendar(DateTime? now) {
    final emCurso = _emCurso;
    if (emCurso == null) return _emCurso = _rodar(now);
    return _seguinte ??= emCurso.then((_) {
      _seguinte = null;
      return _agendar(now);
    });
  }

  Future<void> _rodar(DateTime? now) async {
    try {
      await _tentar(now);
    } finally {
      _emCurso = null;
    }
  }

  Future<void> _tentar(DateTime? now) async {
    if (_closed) return;
    try {
      final t = (now ?? _clock()).toUtc();
      final revogadas = await _source.revokedUnexpired(t);
      final numero = await _source.nextCrlNumber();
      final pem = await _build(
        revoked: [
          for (final c in revogadas)
            RevokedEntry(
              serial: BigInt.parse(c.serial, radix: 16),
              revokedAt: c.revokedAt!,
              notAfter: c.notAfter,
              commonName: c.microAreaId.toString(),
            ),
        ],
        crlNumber: numero,
        now: t,
        days: _config.crlDays,
      );
      await _write(_config.crlPath, pem);
      _pendingSince = null;
      _backoff = _initialBackoff;
      _log('CRL dos aparelhos publicada: ${revogadas.length} revogada(s), número $numero.');
    } catch (error) {
      _pendingSince ??= _clock().toUtc();
      if (_closed) return;
      // Já há uma publicação enfileirada (um `publish()` chegou durante esta
      // tentativa): ela é a nova tentativa, e roda logo em seguida.
      if (_seguinte != null) {
        _log('Falha ao publicar a CRL dos aparelhos (${error.runtimeType}); '
            'a publicação enfileirada tenta de novo.');
        return;
      }
      final espera = _backoff;
      _log(
        'Falha ao publicar a CRL dos aparelhos (${error.runtimeType}); '
        'nova tentativa em ${espera.inSeconds} s.',
      );
      final dobro = espera * 2;
      _backoff = dobro > _maxBackoff ? _maxBackoff : dobro;
      // Um só timer vivo: a publicação enfileirada que falha logo depois de
      // outra substituiria o timer sem cancelá-lo, e duas cadeias de recuo
      // correriam em paralelo.
      _retry?.cancel();
      _retry = Timer(espera, () {
        _retry = null;
        unawaited(_agendar(null));
      });
    }
  }

  Future<void> _gravarValidada(String path, String pem) => writeFileAtomically(
    path,
    pem,
    validate: (tmp) async {
      final r = await Process.run('openssl', [
        'crl', '-in', tmp, '-CAfile', _config.caCertPath, '-noout',
      ]);
      if (r.exitCode != 0) {
        throw StateError('CRL recusada na validação contra a CA (saída ${r.exitCode}).');
      }
    },
  );
}
