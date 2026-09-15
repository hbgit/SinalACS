import 'dart:io';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/generated/endpoints.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_chain_reader.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Verifica a cadeia de hash de `audit_logs` (LGPD-RT03) contra o banco
/// configurado em `config/*.yaml` — a mesma configuração que o servidor usa.
///
/// Uso: `dart run bin/audit_chain_check.dart`
///
/// Sai `0` quando a cadeia está íntegra, `1` quando encontra uma quebra
/// (edição, remoção ou reordenação de linha), imprimindo em que `sequence` e
/// por quê. Não sobe nenhum listener HTTP — só abre uma sessão interna para
/// ler o banco, no mesmo padrão de script avulso que o Serverpod documenta
/// para tarefas de manutenção.
Future<void> main(List<String> args) async {
  final pod = Serverpod(args, Protocol(), Endpoints());
  final session = await pod.createSession();

  try {
    final verifier = AuditChainVerifier(
      reader: OrmAuditChainReader(session: () => session),
      secret: AlertRuntime.instance.config.auditChainSecret,
    );
    final result = await verifier.verify();

    if (result.ok) {
      stdout.writeln(
        'OK — ${result.checked} linha(s) verificada(s), cadeia íntegra.',
      );
      exitCode = 0;
    } else {
      stderr.writeln(
        'FALHA na sequence ${result.brokenAtSequence}: ${result.reason} '
        '(${result.checked} linha(s) íntegra(s) antes da quebra)',
      );
      exitCode = 1;
    }
  } finally {
    await session.close();
    // `exitProcess: true` (o padrão) chamaria `exit()` internamente com seu
    // próprio código, descartando o `exitCode` que acabamos de definir acima —
    // é assim que o script perderia o `1` de uma cadeia quebrada.
    await pod.shutdown(exitProcess: false);
  }

  exit(exitCode);
}
