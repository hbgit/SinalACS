import 'dart:async';
import 'dart:io';

import 'package:serverpod/serverpod.dart';

import 'src/application/auth/development_auth_service.dart';
import 'src/generated/endpoints.dart';
import 'src/generated/protocol.dart';
import 'src/runtime/alert_runtime.dart';
import 'src/web/routes/app_config_route.dart';
import 'src/web/routes/root.dart';

/// The starting point of the Serverpod server.
void run(List<String> args) async {
  // Initialize Serverpod and connect it with your generated code.
  final pod = Serverpod(args, Protocol(), Endpoints());

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
        final acknowledged = await runtime.serviceFor(session).acknowledge(
              user: AuthenticatedUser(
                id: ack.acsId,
                role: UserRole.acs,
                microAreaId: ack.microAreaId,
                deviceId: 'mqtt',
              ),
              alertId: ack.alertId,
            );
        session.log(
          'ACK do alerta ${ack.alertId} pelo ACS ${ack.acsId}: '
          '${acknowledged ? 'registrado' : 'sem correspondência na microárea'}',
        );
      } finally {
        await session.close();
      }
    },
  );
}
