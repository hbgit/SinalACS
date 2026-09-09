import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_store.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart';

/// Estado de processo compartilhado pelos endpoints.
///
/// Endpoints do Serverpod são instanciados por requisição, então o dispatcher
/// MQTT — que é uma conexão longa com retry e backoff próprios — precisa viver
/// fora deles.
///
/// A `Session` não é guardada aqui: o [OrmAlertStore] a recebe por chamada,
/// porque o Serverpod amarra a conexão de banco à sessão da requisição.
class AlertRuntime {
  AlertRuntime._();

  static final AlertRuntime instance = AlertRuntime._();

  AppConfig? _config;
  MqttAlertDispatcher? _dispatcher;
  DevelopmentAuthService? _auth;

  AppConfig get config => _config ??= AppConfig.fromEnvironment();

  DevelopmentAuthService get auth =>
      _auth ??= DevelopmentAuthService(secret: config.jwtSecret);

  MqttAlertDispatcher get dispatcher =>
      _dispatcher ??= MqttAlertDispatcher(config: config);

  bool get isMqttConnected => _dispatcher?.isConnected ?? false;

  /// Constrói o serviço de alerta para uma requisição, ligando o publisher de
  /// processo ao store amarrado à sessão desta chamada.
  ///
  /// Passando [transaction], a gravação do alerta e o registro da chave de
  /// idempotência participam dela — o que permite desfazer as duas se a
  /// publicação no broker falhar.
  RedAlertService serviceFor(Session session, {Transaction? transaction}) =>
      RedAlertService(
        publisher: dispatcher,
        store: OrmAlertStore(session: () => session, transaction: transaction),
      );
}
