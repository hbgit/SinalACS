import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:sinalacs_server/src/infrastructure/database/orm_telemetry_metrics_store.dart';

/// Relatório das métricas de telemetria do PRD §1.3 (#83).
///
///   `dart run bin/telemetry_report.dart --from 2026-10-01 --to 2026-11-01`
///
/// Ferramenta de OPERAÇÃO: roda com acesso ao banco (as mesmas variáveis
/// `SERVERPOD_DATABASE_*` do servidor) e imprime o `TelemetryReport` em JSON.
/// As datas são ISO 8601; sem fuso, valem como UTC. A janela é `[from, to)`.
///
/// Saída 2: argumento ausente, data inválida ou `from >= to`, sem conectar ao
/// banco.
Future<void> main(List<String> args) async {
  DateTime? from;
  DateTime? to;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--from':
        from = _utc(i + 1 < args.length ? args[++i] : '');
      case '--to':
        to = _utc(i + 1 < args.length ? args[++i] : '');
    }
  }
  if (from == null || to == null || !from.isBefore(to)) {
    stderr.writeln('uso: dart run bin/telemetry_report.dart --from <AAAA-MM-DD> --to <AAAA-MM-DD> (from < to, UTC)');
    exit(2);
  }

  final env = Platform.environment;
  final conexao = await pg.Connection.open(
    pg.Endpoint(
      host: env['SERVERPOD_DATABASE_HOST'] ?? 'localhost',
      port: int.parse(env['SERVERPOD_DATABASE_PORT'] ?? '5432'),
      database: env['SERVERPOD_DATABASE_NAME'] ?? 'sinalacs_db',
      username: env['SERVERPOD_DATABASE_USER'] ?? 'sinalacs_user',
      password: env['SERVERPOD_DATABASE_PASSWORD'],
    ),
    settings: pg.ConnectionSettings(
      sslMode: env['SERVERPOD_DATABASE_REQUIRE_SSL'] == 'true' ? pg.SslMode.require : pg.SslMode.disable,
    ),
  );
  try {
    final report = await OrmTelemetryMetricsStore.postgres(conexao).report(from: from, to: to);
    stdout.writeln(jsonEncode(report.toJson()));
  } finally {
    await conexao.close();
  }
}

/// Data ISO 8601; sem fuso explícito, os mesmos campos em UTC.
DateTime? _utc(String texto) {
  final d = DateTime.tryParse(texto);
  if (d == null) return null;
  if (d.isUtc) return d;
  return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond, d.microsecond);
}
