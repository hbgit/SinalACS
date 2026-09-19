import 'package:meta/meta.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/alert_outbox_dispatcher.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_directory_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_outbox.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_onboarding_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_patient_directory_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_triage_session_store.dart';
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
  HealthDataCipher? _healthDataCipher;

  AppConfig get config => _config ??= AppConfig.fromEnvironment();

  DevelopmentAuthService get auth =>
      _auth ??= DevelopmentAuthService(secret: config.jwtSecret);

  /// Cifra dos 3 campos clínicos em repouso (RNF03, INV-04), compartilhada
  /// pelos stores ORM de paciente, triagem e visita.
  ///
  /// `keyVersion: 1` é a versão corrente, e é o que vai gravado em cada linha
  /// — um marcador para uma rotina de rotação futura (que reescreveria as
  /// linhas antigas) saber o que já foi convertido. Hoje **não** existe essa
  /// rotina, e a decifragem não consulta a versão declarada pela linha: o
  /// processo conhece uma única chave, a de `HEALTH_DATA_ENCRYPTION_KEY`.
  /// Trocar essa chave torna ilegível tudo que foi cifrado com a anterior.
  /// Ver `HealthDataCipher` e o aviso no `.env.example`.
  HealthDataCipher get healthDataCipher => _healthDataCipher ??= HealthDataCipher(
        keyHex: config.healthDataEncryptionKey,
        keyVersion: 1,
      );

  MqttAlertDispatcher get dispatcher =>
      _dispatcher ??= MqttAlertDispatcher(config: config);

  /// Derivação de senha do login institucional (RF07). `const`, sem estado:
  /// os parâmetros de custo vivem em cada linha de `user_credentials`, não
  /// aqui — ver `PasswordDigest`.
  PasswordHasher get passwordHasher => const Argon2PasswordHasher();

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
    // Idem para a cifra: ela guarda a chave AES derivada de
    // `healthDataEncryptionKey`, e manter a antiga faria os stores cifrarem
    // com uma chave que a config atual não conhece mais.
    _healthDataCipher = null;
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
        store: OrmVisitStore(
          session: () => session,
          cipher: healthDataCipher,
          transaction: transaction,
        ),
        audit: auditTrailFor(session),
      );

  /// Constrói o diretório de pacientes da microárea para uma requisição.
  PatientDirectoryService patientDirectoryServiceFor(Session session) =>
      PatientDirectoryService(
        store: OrmPatientDirectoryStore(
          session: () => session,
          cipher: healthDataCipher,
        ),
        audit: auditTrailFor(session),
      );

  /// Constrói o serviço de triagem persistida para uma requisição.
  TriageSessionService triageSessionServiceFor(Session session) =>
      TriageSessionService(
        store: OrmTriageSessionStore(
          session: () => session,
          cipher: healthDataCipher,
        ),
        audit: auditTrailFor(session),
      );

  /// Constrói o serviço de onboarding para uma requisição.
  ///
  /// Passando [transaction], o consumo do convite e a gravação dos 3
  /// `consent_logs` participam dela — mesmo arranjo de [serviceFor] para o
  /// alerta vermelho, e o que fecha a janela de corrida de um segundo uso
  /// concorrente do mesmo token (fix round 1).
  OnboardingService onboardingServiceFor(Session session, {Transaction? transaction}) =>
      OnboardingService(
        store: OrmOnboardingStore(
          session: () => session,
          chainSecret: config.auditChainSecret,
          transaction: transaction,
        ),
      );

  /// Serviço de login institucional para uma requisição.
  ///
  /// Mesmo arranjo dos outros `*ServiceFor`: o store recebe a sessão por
  /// chamada e a trilha de auditoria é a da requisição, para que cada
  /// tentativa (granted, denied_credentials, denied_locked…) vire uma linha
  /// encadeada em `audit_logs`.
  InstitutionalAuthService institutionalAuthServiceFor(Session session) =>
      InstitutionalAuthService(
        store: OrmAcsCredentialStore(session: () => session),
        hasher: passwordHasher,
        audit: auditTrailFor(session),
      );

  /// Trilha de auditoria amarrada à sessão da chamada.
  AuditTrail auditTrailFor(Session session) => OrmAuditTrail(
        session: () => session,
        chainSecret: config.auditChainSecret,
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
