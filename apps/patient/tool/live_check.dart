/// Verificação rápida da camada de rede do app contra a stack local.
///
/// Roda na VM, sem emulador, e usa o MESMO `BackendClient` que a UI usa — é o
/// que separa "o backend está de pé" (video/rpc_demo) de "o app fala com ele".
///
/// Pré-requisito: `docker compose up` com o database-seed concluído.
///
///   cd apps/patient
///   dart run tool/live_check.dart
///   dart run tool/live_check.dart --host http://10.0.2.2:8080/
library;

import 'dart:io';

import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/privacy/location_hash.dart';

Future<void> main(List<String> args) async {
  final hostIndex = args.indexOf('--host');
  final host = hostIndex >= 0 && hostIndex + 1 < args.length
      ? args[hostIndex + 1]
      : 'http://localhost:8080/';

  final backend = BackendClient(host: host);
  stdout.writeln('paciente → $host');

  try {
    final health = await backend.health();
    stdout.writeln('  health ............. ${health.status} '
        '(db=${health.dbConnected} mqtt=${health.mqttConnected})');

    final session = await backend.login();
    // O token nunca é impresso inteiro.
    stdout.writeln('  login .............. papel=${session.role} '
        'microárea=${session.microAreaId} expira=${session.expiresAt.toIso8601String()}');

    final red = await backend.evaluateTriage(
      chestPain: true,
      difficultyBreathing: false,
      fever: false,
      persistentVomiting: false,
      bleeding: false,
      severeWeakness: false,
    );
    final green = await backend.evaluateTriage(
      chestPain: false,
      difficultyBreathing: false,
      fever: false,
      persistentVomiting: false,
      bleeding: false,
      severeWeakness: false,
    );
    stdout.writeln('  triagem ............ dor no peito=${red.name}  '
        'sem sintomas=${green.name}');
    if (red.name != 'red' || green.name != 'green') {
      stderr.writeln('  ERRO: motor de triagem do servidor respondeu fora do esperado.');
      exitCode = 1;
    }

    final key = 'live-check-${DateTime.now().millisecondsSinceEpoch}';
    final hash = locationHashFrom(-23.55052, -46.633308);
    final first = await backend.createRedAlert(
      idempotencyKey: key,
      locationHash: hash,
    );
    final again = await backend.createRedAlert(
      idempotencyKey: key,
      locationHash: hash,
    );
    stdout.writeln('  alerta vermelho .... ${first.alertId} '
        '(publicado=${first.published})');
    if (first.alertId == again.alertId) {
      stdout.writeln('  idempotência ....... mesmo alertId no reenvio');
    } else {
      stderr.writeln('  ERRO: reenvio com a mesma chave criou outro alerta.');
      exitCode = 1;
    }

    stdout.writeln(exitCode == 0 ? '\nOK — o app fala com o backend.' : '\nFALHOU.');
  } on BackendFailure catch (failure) {
    stderr.writeln('  falhou: ${failure.message}');
    exitCode = 1;
  } finally {
    backend.close();
  }
}
