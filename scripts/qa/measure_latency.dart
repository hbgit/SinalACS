import 'dart:convert';
import 'dart:io';
import 'dart:math';

String _arg(List<String> args, String name, String fallback) {
  final index = args.indexOf('--$name');
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
}

int _intArg(List<String> args, String name, int fallback) {
  final value = _arg(args, name, '$fallback');
  return int.tryParse(value) ?? fallback;
}

double _p95(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final rank = max(0, ((sorted.length * 0.95).ceil()) - 1);
  return sorted[rank].toDouble();
}

Map<String, dynamic>? _parseMetric(String line) {
  if (!line.startsWith('METRIC ')) return null;
  final payload = line.substring('METRIC '.length);
  return jsonDecode(payload) as Map<String, dynamic>;
}

DateTime? _timeOf(List<Map<String, dynamic>> metrics, String event) {
  final match = metrics.where((metric) => metric['event'] == event).lastOrNull;
  final raw = match?['at'] as String?;
  return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
}

extension on Iterable<Map<String, dynamic>> {
  Map<String, dynamic>? get lastOrNull {
    if (isEmpty) return null;
    return last;
  }
}

Future<void> main(List<String> args) async {
  final repoRoot = Directory.fromUri(Platform.script).parent.parent.parent.path;
  // O RPC é HTTPS na 443: a 8080 em texto claro não é mais publicada e quem
  // termina TLS é o Traefik (RNF04/L-08). O `live_check` recebe este host e lê
  // a CA de desenvolvimento do RPC sozinho, do runtime local.
  final host = _arg(args, 'host', 'https://localhost/');

  // O host explícito é validado AQUI também. O `live_check` já para com a
  // mensagem certa, mas ela chegaria enterrada no `failures` do relatório JSON,
  // depois de gastar as amostras — e este script repassa `--host` direto para
  // ele. A regra é a mesma do `requireSecureHost` do app, reescrita aqui porque
  // esta ferramenta roda da raiz do repositório e só importa `dart:`.
  if (!(Uri.tryParse(host)?.isScheme('https') ?? false)) {
    stderr.writeln('erro: o host ($host) não está em HTTPS. A porta 8080 em '
        'texto claro não é mais publicada (RNF04/L-08).');
    exitCode = 2;
    return;
  }

  final broker = _arg(args, 'broker', 'localhost');
  final mqttPassword = _arg(
    args,
    'mqtt-password',
    Platform.environment['MQTT_ACS_PASSWORD'] ?? '',
  );
  final sampleCount = _intArg(args, 'samples', 5).clamp(1, 50);
  final visitCount = _intArg(args, 'visit-count', 100).clamp(1, 1000);
  final outputPath = _arg(args, 'output', '');

  if (mqttPassword.isEmpty) {
    stderr.writeln('erro: informe --mqtt-password ou exporte MQTT_ACS_PASSWORD.');
    exitCode = 2;
    return;
  }

  final alertLatencies = <int>[];
  final syncLatencies = <int>[];
  var alertSuccesses = 0;
  var syncSuccesses = 0;
  final failures = <Map<String, Object?>>[];

  for (var sample = 1; sample <= sampleCount; sample++) {
    stdout.writeln('sample $sample/$sampleCount: executando live_check com $visitCount visita(s)');
    final result = await Process.run(
      'dart',
      [
        'run',
        'tool/live_check.dart',
        '--host',
        host,
        '--broker',
        broker,
        '--mqtt-password',
        mqttPassword,
        '--visit-count',
        '$visitCount',
        '--emit-metrics',
      ],
      workingDirectory: '$repoRoot/apps/acs',
    );

    final stdoutText = result.stdout as String;
    final stderrText = result.stderr as String;
    final metrics = stdoutText
        .split('\n')
        .map(_parseMetric)
        .whereType<Map<String, dynamic>>()
        .toList();

    final triggered = _timeOf(metrics, 'alert_triggered');
    final received = _timeOf(metrics, 'alert_received_acs');
    final syncAttempt = _timeOf(metrics, 'sync_attempt');
    final syncResult = _timeOf(metrics, 'sync_result');
    final syncResultMetric = metrics.where((metric) => metric['event'] == 'sync_result').lastOrNull;

    if (result.exitCode == 0 && triggered != null && received != null) {
      alertLatencies.add(received.difference(triggered).inMilliseconds);
      alertSuccesses++;
    }

    if (result.exitCode == 0 && syncAttempt != null && syncResult != null) {
      syncLatencies.add(syncResult.difference(syncAttempt).inMilliseconds);
      final kind = syncResultMetric?['kind'];
      final processed = syncResultMetric?['processed'];
      final pendingCount = syncResultMetric?['pending_count'];
      if (kind == 'synced' && processed == visitCount && pendingCount == 0) {
        syncSuccesses++;
      }
    }

    if (result.exitCode != 0) {
      failures.add(<String, Object?>{
        'sample': sample,
        'exit_code': result.exitCode,
        'stderr': stderrText.trim(),
      });
    }
  }

  final report = <String, Object?>{
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'host': host,
    'broker': broker,
    'samples': sampleCount,
    'visit_count': visitCount,
    'alert_delivery': <String, Object?>{
      'success_rate': alertSuccesses / sampleCount,
      'p95_ms': _p95(alertLatencies),
      'goal_rnf01_p95_ms': 500,
      'executed_samples': alertLatencies.length,
    },
    'sync': <String, Object?>{
      'success_rate': syncSuccesses / sampleCount,
      'p95_ms': _p95(syncLatencies),
      'goal_rnf02_success_rate': 0.995,
      'executed_samples': syncLatencies.length,
    },
    'failures': failures,
  };

  final pretty = const JsonEncoder.withIndent('  ').convert(report);
  stdout.writeln(pretty);

  if (outputPath.isNotEmpty) {
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString('$pretty\n');
  }

  if (alertLatencies.length != sampleCount ||
      syncLatencies.length != sampleCount) {
    stderr.writeln(
      'erro: a medicao nao produziu amostras completas '
      '(alertas ${alertLatencies.length}/$sampleCount, '
      'sync ${syncLatencies.length}/$sampleCount).',
    );
    exitCode = 1;
  }
}