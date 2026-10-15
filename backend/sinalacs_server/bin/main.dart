import 'dart:async';
import 'dart:io';

import 'package:sinalacs_server/server.dart';
import 'package:sinalacs_server/src/runtime/uncaught_error_policy.dart';

/// This is the starting point for your Serverpod server.
///
/// `run` roda numa zona protegida (#56, defesa em profundidade): um erro
/// assíncrono sem dono não derruba mais o processo com um `Unhandled exception`
/// opaco. Erro transitório de E/S é registrado e o processo segue; qualquer
/// outro é registrado (só o tipo) e encerra com código != 0 para a política de
/// restart do Docker assumir. Não substitui a zona do dispatcher MQTT.
void main(List<String> args) {
  runZonedGuarded(
    () => run(args),
    buildUncaughtErrorHandler(
      log: (m) => stderr.writeln('[processo] $m'),
      exitFn: exit,
    ),
  );
}
