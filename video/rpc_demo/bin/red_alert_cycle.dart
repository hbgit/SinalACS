/// Bloco 5 do vídeo do sponsor — o ciclo do alerta vermelho, ponta a ponta.
///
/// O backend é **Serverpod RPC, não REST**: não existe URL para filmar. O que
/// se filma é a chamada de método tipada e o resultado tipado. Este script usa
/// o mesmo cliente gerado (`sinalacs_client`) que os apps Flutter vão consumir.
///
/// O RPC responde por **HTTPS na 443** e quem termina TLS é o Traefik
/// (RNF04/L-08): a porta 8080 em texto claro deixou de ser publicada. Diferente
/// dos apps, esta ferramenta roda na máquina (não num APK), então lê a CA de
/// desenvolvimento do runtime local em vez de um asset Flutter — o mesmo
/// caminho dos `tool/live_check.dart`.
///
/// Pré-requisitos (ver video/README.md):
///   · `docker compose up` com o serviço `database-seed` concluído — sem o seed,
///     `createRedAlert` falha por chave estrangeira em `alerts.patientId`;
///   · `./scripts/dev/sync_dev_ca.sh` — a CA do RPC não é versionada;
///   · `ENABLE_DEV_LOGIN=true` (já está em docker-compose.yml).
///
/// PRIVACIDADE: o token de acesso é impresso truncado. Nunca mostrar um token
/// inteiro em quadro.
library;

import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart';

const _host = String.fromEnvironment('SINALACS_HOST', defaultValue: 'https://localhost/');

/// Pausa entre passos: o vídeo precisa que cada resultado fique legível em
/// quadro antes do próximo aparecer.
const _beat = Duration(milliseconds: 1800);

/// Caminho da CA de desenvolvimento do RPC (a que assina o certificado do
/// Traefik em 443), dentro do repositório.
///
/// Sai da posição DESTE arquivo, e não do diretório de onde o comando foi
/// executado (`Directory.fromUri(Platform.script)`, o mesmo idioma dos
/// `tool/live_check.dart`): assim a CA é encontrada tanto de `video/rpc_demo`
/// (o uso documentado no README) quanto da raiz do repositório. Um caminho
/// relativo ao CWD erraria por um `../` conforme quem chamasse.
File _devRpcCaFile() {
  // video/rpc_demo/bin/red_alert_cycle.dart → raiz do repositório.
  final repoRoot = Directory.fromUri(Platform.script).parent.parent.parent.parent;
  return File('${repoRoot.path}/infra/docker/traefik/runtime/certs/ca.crt');
}

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
  // O host desta ferramenta também é validado. A regra é a mesma do
  // `requireSecureHost` do app (`apps/*/lib/core/network/backend_client.dart`),
  // reescrita aqui porque `video/` depende de `sinalacs_client`, e não dos apps.
  // Sem ela, `--dart-define=SINALACS_HOST=http://…` faria o vídeo mostrar o
  // ciclo inteiro por um caminho sem criptografia — com o `securityContext`
  // abaixo aceito e ignorado, sem nada vermelho em lugar nenhum.
  if (!(Uri.tryParse(_host)?.isScheme('https') ?? false)) {
    stderr.writeln('erro: o endereço do backend ($_host) não está em HTTPS.');
    stderr.writeln('A porta 8080 em texto claro não é mais publicada (RNF04/L-08).');
    exitCode = 2;
    return;
  }

  // A CA é lida ANTES de construir o cliente, e a ausência dela PARA a
  // execução com o motivo real. Se ela faltasse e o cliente fosse construído
  // assim mesmo, ele cairia no armazenamento do sistema, o handshake falharia
  // com `CERTIFICATE_VERIFY_FAILED`, e a saída dizia só "falhou" — sem dizer
  // que faltava um arquivo que o `sync_dev_ca.sh` produz.
  final caFile = _devRpcCaFile();
  if (!caFile.existsSync()) {
    stderr.writeln('erro: a CA do RPC não existe em ${caFile.path}.');
    stderr.writeln('Suba a stack (docker compose up) e rode ./scripts/dev/sync_dev_ca.sh.');
    exitCode = 2;
    return;
  }

  // A construção do cliente fica sob a **mesma** guarda da leitura acima: uma
  // CA presente mas corrompida lança `TlsException` aqui, e sem guarda nenhuma
  // isso subia como exceção não tratada (exit 255) — nunca chegava ao
  // handshake, e nada na saída dizia qual arquivo estava errado. Guarda
  // própria, e não o `try` do ciclo, porque o `catch` de lá imprime
  // `falhou: $error`, que também não nomeia o caminho.
  Client client;
  try {
    client = Client(
      _host,
      // Sem os bytes da CA local o cliente cai no armazenamento do sistema, que
      // não conhece a CA de desenvolvimento: o handshake falha de forma
      // explícita, nunca aceitando qualquer certificado.
      securityContext: SecurityContext()..setTrustedCertificatesBytes(caFile.readAsBytesSync()),
    )..connectivityMonitor = null;
  } catch (error) {
    stderr.writeln('erro: a CA do RPC em ${caFile.path} não pôde ser usada: $error');
    stderr.writeln('Rode ./scripts/dev/sync_dev_ca.sh para copiá-la de novo.');
    exitCode = 2;
    return;
  }

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
