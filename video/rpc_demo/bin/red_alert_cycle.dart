/// Bloco 5 do vídeo do sponsor — o ciclo do alerta vermelho, ponta a ponta.
///
/// O backend é **Serverpod RPC, não REST**: não existe URL para filmar. O que
/// se filma é a chamada de método tipada e o resultado tipado. Este script usa
/// o mesmo cliente gerado (`sinalacs_client`) que os apps Flutter vão consumir.
///
/// Pré-requisitos (ver video/README.md):
///   · `docker compose up` com o serviço `database-seed` concluído — sem o seed,
///     `createRedAlert` falha por chave estrangeira em `alerts.patientId`;
///   · `ENABLE_DEV_LOGIN=true` (já está em docker-compose.yml).
///
/// PRIVACIDADE: o token de acesso é impresso truncado. Nunca mostrar um token
/// inteiro em quadro.
library;

import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart';

const _host = String.fromEnvironment('SINALACS_HOST', defaultValue: 'http://localhost:8080/');

/// Pausa entre passos: o vídeo precisa que cada resultado fique legível em
/// quadro antes de o próximo aparecer.
const _beat = Duration(milliseconds: 1800);

void _step(String n, String title) {
  stdout.writeln('');
  stdout.writeln('\x1B[1;36m[$n]\x1B[0m \x1B[1m$title\x1B[0m');
}

void _ok(String label, String value) =>
    stdout.writeln('    \x1B[32m✓\x1B[0m $label: \x1B[1m$value\x1B[0m');

void _plain(String label, String value) =>
    stdout.writeln('      $label: $value');

String _truncate(String token) =>
    token.length <= 12 ? '***' : '${token.substring(0, 8)}…${token.substring(token.length - 4)}';

Future<void> main() async {
  final client = Client(_host)..connectivityMonitor = null;

  stdout.writeln('\x1B[1mSinalACS — ciclo do alerta vermelho\x1B[0m');
  stdout.writeln('servidor: $_host   (Serverpod RPC)');

  try {
    // ---------------------------------------------------------------------
    _step('1/5', 'Saúde da stack');
    final health = await client.health.check();
    _ok('status', health.status);
    _plain('banco', '${health.dbConnected}');
    _plain('broker MQTT', '${health.mqttConnected}');
    await Future<void>.delayed(_beat);

    // ---------------------------------------------------------------------
    _step('2/5', 'Autenticação de desenvolvimento (paciente)');
    final login = await client.auth.developmentLogin(role: 'patient');
    _ok('token', '${login.tokenType} ${_truncate(login.accessToken)}');
    stdout.writeln('      \x1B[2m(truncado de propósito — nunca exibir o token inteiro)\x1B[0m');
    await Future<void>.delayed(_beat);

    // ---------------------------------------------------------------------
    // A chave de idempotência é PARÂMETRO DO MÉTODO, não header — foi uma das
    // três mudanças da migração de REST para RPC.
    final idempotencyKey = 'video-demo-${DateTime.now().millisecondsSinceEpoch}';

    _step('3/5', 'alerts.createRedAlert');
    _plain('idempotencyKey', idempotencyKey);
    final created = await client.alerts.createRedAlert(
      accessToken: login.accessToken,
      idempotencyKey: idempotencyKey,
      locationHash: 'hash-sintetico-microarea-12',
    );
    _ok('alertId', created.alertId);
    _ok('status', created.status.name);
    _ok('published', '${created.published}');
    stdout.writeln('      \x1B[2mgravado em transação e publicado no tópico MQTT da microárea\x1B[0m');
    await Future<void>.delayed(_beat);

    // ---------------------------------------------------------------------
    _step('4/5', 'Reenvio com a MESMA chave — prova de idempotência');
    final repeated = await client.alerts.createRedAlert(
      accessToken: login.accessToken,
      idempotencyKey: idempotencyKey,
      locationHash: 'hash-sintetico-microarea-12',
    );
    final same = repeated.alertId == created.alertId;
    _ok('alertId', repeated.alertId);
    stdout.writeln(same
        ? '      \x1B[32mmesmo alertId — nenhum alerta duplicado\x1B[0m'
        : '      \x1B[31mALERTA DUPLICADO — a idempotência falhou\x1B[0m');
    if (!same) exitCode = 1;
    await Future<void>.delayed(_beat);

    // ---------------------------------------------------------------------
    // O ACS confirma o recebimento. Antes era POST /v1/alerts/{id}/ack; o 404
    // de "não encontrado" virou o campo `acknowledged: false`.
    _step('5/5', 'alerts.acknowledge (pelo ACS)');
    final acsLogin = await client.auth.developmentLogin(role: 'acs');
    final ack = await client.alerts.acknowledge(
      accessToken: acsLogin.accessToken,
      alertId: created.alertId,
    );
    _ok('acknowledged', '${ack.acknowledged}');
    _ok('status', ack.status?.name ?? '(sem status)');

    stdout.writeln('');
    stdout.writeln(ack.acknowledged
        ? '\x1B[1;32m  Alerta vermelho não se perde em silêncio.\x1B[0m'
        : '\x1B[1;31m  ACK não confirmado.\x1B[0m');
    if (!ack.acknowledged) exitCode = 1;
    stdout.writeln('');
  } catch (error) {
    stderr.writeln('\n\x1B[31mfalhou: $error\x1B[0m');
    exitCode = 1;
  } finally {
    client.close();
  }
}
