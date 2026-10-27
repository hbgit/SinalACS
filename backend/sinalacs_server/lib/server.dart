import 'dart:async';
import 'dart:io';

import 'package:serverpod/serverpod.dart';

import 'src/application/alerts/red_alert_service.dart';
import 'src/application/auth/development_auth_service.dart';
import 'src/application/notices/notice_scheduling_service.dart';
import 'src/application/retention/expurge_future_call.dart';
import 'src/application/retention/expurge_service.dart';
import 'src/config/api_tls_config.dart';
import 'src/generated/endpoints.dart';
import 'src/generated/protocol.dart';
import 'src/runtime/alert_runtime.dart';
import 'src/runtime/mtls_api_server.dart';
import 'src/runtime/notice_dispatch_loop.dart';
import 'src/web/routes/app_config_route.dart';
import 'src/web/routes/root.dart';

/// The starting point of the Serverpod server.
void run(List<String> args) async {
  // TLS 1.3 MÚTUO no apiServer quando API_TLS_* está definido (RNF04, #78 e
  // #90): é o trecho Traefik → backend da stack local, e o backend exige o
  // certificado de cliente assinado pela CA de API_TLS_CLIENT_CA_PATH. Sem as
  // variáveis segue em HTTP, que é o caminho do Render (TLS na borda). Insights
  // e webServer ficam em HTTP: nenhum dos dois é publicado nem roteado.
  final apiTls = ApiTlsConfig.fromMap(Platform.environment);

  // Initialize Serverpod and connect it with your generated code.
  //
  // O contexto TLS e a fábrica do adapter saem do MESMO `apiTls`, de propósito:
  // o contexto sozinho subiria em TLS sem exigir o certificado (o estado que a
  // #90 fechou), e a fábrica sozinha não tem com que ligar. `test/unit/
  // server_wiring_test.dart` acusa se os dois forem separados. A fábrica
  // (`mtls_api_server.dart`) liga o socket com `requireClientCertificate`, o
  // que o Serverpod do pub.dev não permite — daí o fork pinado
  // (`backend/patches/README.md`).
  final pod = Serverpod(
    args,
    Protocol(),
    Endpoints(),
    securityContextConfig: apiTls == null
        ? null
        : SecurityContextConfig(apiServer: apiTls.toSecurityContext()),
    apiServerAdapterFactory: apiTls == null ? null : mtlsApiServerAdapter,
  );

  // O módulo serverpod_auth_idp não é inicializado: o acesso hoje é o token
  // HMAC de DevelopmentAuthService, e o módulo trazia ~70 tabelas de identidade
  // que nenhum endpoint deste servidor usava. A autenticação institucional
  // (Gov.br / matrícula da Secretaria) é uma decisão separada, ainda em aberto.

  // Setup a default page at the web root.
  // These are used by the default page.
  pod.webServer.addRoute(RootRoute(), '/');
  pod.webServer.addRoute(RootRoute(), '/index.html');

  // Serve all files in the web/static relative directory under /.
  // These are used by the default web page.
  final root = Directory(Uri(path: 'web/static').toFilePath());
  pod.webServer.addRoute(StaticRoute.directory(root));

  // Setup the app config route.
  // We build this configuration based on the servers api url and serve it to
  // the flutter app.
  pod.webServer.addRoute(
    AppConfigRoute(apiConfig: pod.config.apiServer),
    '/app/assets/assets/config.json',
  );

  // Checks if the flutter web app has been built and serves it if it has.
  final appDir = Directory(Uri(path: 'web/app').toFilePath());
  if (appDir.existsSync()) {
    // Serve the flutter web app under the /app path.
    pod.webServer.addRoute(
      FlutterRoute(
        Directory(
          Uri(path: 'web/app').toFilePath(),
        ),
      ),
      '/app',
    );
  } else {
    // If the flutter web app has not been built, serve the build app page.
    pod.webServer.addRoute(
      StaticRoute.file(
        File(
          Uri(path: 'web/pages/build_flutter_app.html').toFilePath(),
        ),
      ),
      '/app/**',
    );
  }

  // Start the server.
  await pod.start();

  // A conexão MQTT sobe depois do servidor e em segundo plano, com retry e
  // backoff próprios, para não travar o boot caso o broker esteja fora do ar —
  // hosts free-tier hibernam e precisam responder ao healthcheck mesmo sem
  // broker. Era o comportamento do servidor dart:io e é preservado aqui.
  unawaited(_connectAlertDispatcher(pod));

  // Rede de segurança do outbox: publica o que ficou para trás quando o broker
  // estava fora, ou quando o processo caiu entre o commit e a publicação.
  _startOutboxSweeper(pod);

  // Disparo dos avisos comunitários agendados (RF14, #46).
  _startNoticeDispatchLoop(pod);

  // Rotina de retenção (LGPD-RF07): registra o FutureCall de expurgo e agenda
  // a primeira janela diária (03:00 UTC). Depois do `start()`: o
  // FutureCallManager só existe a partir daí.
  _registerRetentionExpurge(pod);
}

/// Intervalo da varredura do outbox.
///
/// Curto porque atrasa a entrega de um alerta vermelho apenas no caminho de
/// exceção — o caminho feliz publica logo após o commit, no próprio endpoint.
const _outboxSweepInterval = Duration(seconds: 10);

void _startOutboxSweeper(Serverpod pod) {
  Timer.periodic(_outboxSweepInterval, (_) async {
    final session = await pod.createSession(enableLogging: false);
    try {
      final published =
          await AlertRuntime.instance.dispatcherFor(session).drainOnce();
      if (published > 0) {
        session.log('Outbox: $published entrega(s) publicada(s) na varredura.');
      }
    } catch (error) {
      // A varredura nunca pode morrer: é o que garante a entrega eventual.
      // Só o tipo do erro: `$error`/`$stackTrace` brutos podem carregar
      // atributos de alerta num aggregator de log (VAZ-01).
      stderr.writeln('Falha na varredura do outbox (${error.runtimeType}).');
    } finally {
      await session.close();
    }
  });
}

/// Laço de disparo dos avisos agendados. Na partida, avisos presos em `sending`
/// viram `unknown` (nunca são reenviados). Um erro é registrado só pelo tipo
/// (o aviso carrega texto digitado pelo staff) e o laço segue.
void _startNoticeDispatchLoop(Serverpod pod) {
  Future<T> withService<T>(Future<T> Function(NoticeSchedulingService) body) async {
    final session = await pod.createSession(enableLogging: false);
    try {
      return await body(
        AlertRuntime.instance.noticeSchedulingServiceFor(session),
      );
    } finally {
      await session.close();
    }
  }

  final loop = NoticeDispatchLoop(
    startup: () async {
      final moved = await withService((s) => s.recoverStuckSending());
      if (moved > 0) {
        stderr.writeln('Avisos: $moved aviso(s) em envio na queda viraram "unknown".');
      }
    },
    tick: () => withService((s) => s.dispatchDue()),
    onError: (error) =>
        stderr.writeln('Falha no disparo de avisos (${error.runtimeType}).'),
  )..start();
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    try {
      signal.watch().listen((_) => loop.stop());
    } on Object {
      // Plataforma sem esse sinal: o processo encerra os timers ao sair.
    }
  }
}

/// Registra o FutureCall de expurgo (LGPD-RF07) e garante exatamente um
/// agendamento pendente da próxima janela diária.
void _registerRetentionExpurge(Serverpod pod) {
  final retentionConfig = AlertRuntime.instance.config;
  pod.registerFutureCall(
    ExpurgeFutureCall(
      policy: RetentionPolicy(
        alertsDays: retentionConfig.retentionAlertDays,
        visitsDays: retentionConfig.retentionVisitDays,
        triageSessionsDays: retentionConfig.retentionTriageDays,
        telemetryDays: retentionConfig.retentionTelemetryDays,
      ),
    ),
    retentionExpurgeFutureCallName,
  );
  unawaited(_ensureRetentionExpurgeScheduled(pod));
}

/// Idempotente: [ensureRetentionExpurgeScheduled] remove pendentes com o
/// identifier fixo antes de inserir, então restarts não empilham janelas.
Future<void> _ensureRetentionExpurgeScheduled(Serverpod pod) async {
  final session = await pod.createSession(enableLogging: false);
  try {
    await ensureRetentionExpurgeScheduled(session);
  } finally {
    await session.close();
  }
}

/// Liga o dispatcher MQTT e encaminha os ACKs recebidos para o serviço de
/// alerta.
///
/// O ACK chega por MQTT, sem passar por endpoint nenhum, então precisa da sua
/// própria `Session`: os endpoints não participam deste caminho.
Future<void> _connectAlertDispatcher(Serverpod pod) async {
  final runtime = AlertRuntime.instance;

  await runtime.dispatcher.connect(
    onAcknowledgement: (ack) async {
      final session = await pod.createSession(enableLogging: false);
      try {
        final status = await runtime.serviceFor(session).acknowledge(
              user: AuthenticatedUser(
                id: ack.acsId,
                role: UserRole.acs,
                microAreaId: ack.microAreaId,
                deviceId: RedAlertService.mqttAckDeviceId,
              ),
              alertId: ack.alertId,
            );
        session.log(
          'ACK do alerta ${ack.alertId} pelo ACS ${ack.acsId}: '
          '${status != null ? 'registrado (${status.name})' : 'sem correspondência na microárea'}',
        );
      } finally {
        await session.close();
      }
    },
  );
}
