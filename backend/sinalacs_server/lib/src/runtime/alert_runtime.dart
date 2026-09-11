import 'package:meta/meta.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/alert_outbox_dispatcher.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_outbox.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_visit_store.dart';
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

  /// Substitui a configuração lida do ambiente.
  ///
  /// Existe para os testes de integração, que precisam exercitar o caminho com
  /// dev-login habilitado sem depender de variáveis de ambiente do processo de
  /// teste. Passar `null` volta a ler do ambiente.
  @visibleForTesting
  void overrideConfig(AppConfig? value) {
    _config = value;
    // O serviço de auth deriva do segredo, então precisa ser reconstruído.
    _auth = null;
  }

  AlertPublisher? _publisherOverride;

  /// Substitui o publisher usado pelos endpoints.
  ///
  /// Existe para os testes de integração: o harness do Serverpod sobe o
  /// servidor sem broker, e sem esta costura todo `createRedAlert` falharia
  /// antes de exercitar o que se quer testar. Passar `null` restaura o
  /// dispatcher real.
  @visibleForTesting
  void overridePublisher(AlertPublisher? publisher) =>
      _publisherOverride = publisher;

  AlertPublisher get _publisher => _publisherOverride ?? dispatcher;

  /// Constrói o serviço de alerta para uma requisição, ligando o publisher de
  /// processo ao store amarrado à sessão desta chamada.
  ///
  /// Passando [transaction], a gravação do alerta e o registro da chave de
  /// idempotência participam dela — o que permite desfazer as duas se a
  /// publicação no broker falhar.
  RedAlertService serviceFor(Session session, {Transaction? transaction}) =>
      RedAlertService(
        store: OrmAlertStore(session: () => session, transaction: transaction),
        outbox: OrmAlertOutbox(session: () => session, transaction: transaction),
      );

  /// Constrói o serviço de sincronização de visitas para uma requisição.
  ///
  /// Mesmo arranjo de [serviceFor]: o store é amarrado à sessão da chamada e, se
  /// houver [transaction], o lote inteiro participa dela.
  VisitSyncService visitSyncServiceFor(
    Session session, {
    Transaction? transaction,
  }) =>
      VisitSyncService(
        store: OrmVisitStore(session: () => session, transaction: transaction),
      );

  /// Drenador do outbox.
  ///
  /// Construído sem transação: a publicação acontece **depois** do commit, e
  /// marcar a entrada como publicada não deve ficar presa à transação que a
  /// criou — se ficasse, um rollback desfaria a marcação de algo já entregue.
  ///
  /// [clock] existe para os testes exercitarem o backoff sem esperar em tempo
  /// real — uma entrada adiada só volta a ser elegível quando o relógio passa
  /// de `nextAttemptAt`.
  AlertOutboxDispatcher dispatcherFor(
    Session session, {
    DateTime Function()? clock,
  }) =>
      AlertOutboxDispatcher(
        outbox: OrmAlertOutbox(session: () => session, clock: clock),
        publisher: _publisher,
        clock: clock,
      );
}
