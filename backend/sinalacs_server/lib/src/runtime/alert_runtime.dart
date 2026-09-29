import 'package:meta/meta.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/alert_outbox_dispatcher.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/cpf_hasher.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/passwordless_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/sms_gateway.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_directory_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_outbox.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_onboarding_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_otp_challenge_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_patient_data_overview_store.dart';
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

  /// Hash do CPF e do código OTP do login passwordless (RF01), keyed pelo
  /// pepper da config — sem ele o hash de um CPF é reversível por força bruta.
  CpfHasher get cpfHasher =>
      _cpfHasher ??= HmacCpfHasher(pepper: config.cpfHashPepper);
  CpfHasher? _cpfHasher;

  /// Mesmo hasher de [cpfHasher], exposto com nome próprio para os testes de
  /// integração que precisam gravar o hash de um CPF sintético sem passar pelo
  /// fluxo de login (o `users.cpfHash` é o índice que o login consulta).
  @visibleForTesting
  CpfHasher get cpfHasherForTests => cpfHasher;

  /// Gateway de SMS do login passwordless.
  ///
  /// Sem override, é o de `SMS_GATEWAY`; hoje só existe `log`, e `AppConfig`
  /// já recusa esse valor fora de `APP_ENV=development` — a exceção aqui é a
  /// segunda linha de defesa, para uma config construída fora do
  /// `fromEnvironment` (os testes) apontar o gateway errado em produção.
  SmsGateway get smsGateway =>
      _smsGatewayOverride ??
      (_smsGateway ??= config.smsGateway == 'log'
          ? const LoggingSmsGateway()
          : throw StateError(
              'SMS_GATEWAY=${config.smsGateway} não tem implementação: só '
              '"log" existe hoje. Implemente SmsGateway antes de configurá-lo.',
            ));
  SmsGateway? _smsGateway;
  SmsGateway? _smsGatewayOverride;

  /// Substitui o gateway de SMS usado pelo login passwordless.
  ///
  /// Existe para os testes: o gateway de produção **envia** (ou escreve o
  /// código no log), e o teste precisa capturar o código para provar o
  /// caminho de verificação sem depender de um provedor. Passar `null`
  /// restaura o gateway da config.
  @visibleForTesting
  void overrideSmsGateway(SmsGateway? gateway) => _smsGatewayOverride = gateway;

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
    // O hasher de CPF é keyed pelo pepper e o gateway de SMS depende do
    // `smsGateway` da config: os dois foram derivados da config antiga.
    _cpfHasher = null;
    _smsGateway = null;
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

  /// Constrói o painel "Meus Dados" (LGPD) para uma requisição.
  PatientDataOverviewService patientDataOverviewServiceFor(Session session) =>
      PatientDataOverviewService(
        store: OrmPatientDataOverviewStore(
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

  /// Serviço de login passwordless do paciente (RF01) para uma requisição.
  ///
  /// Mesmo arranjo dos outros `*ServiceFor`: o store recebe a sessão por
  /// chamada, e a trilha é a da requisição, para que cada desfecho
  /// (`otp_requested`, `denied_code`, `granted`…) vire uma linha encadeada em
  /// `audit_logs`.
  PasswordlessAuthService passwordlessAuthServiceFor(Session session) =>
      PasswordlessAuthService(
        store: OrmOtpChallengeStore(session: () => session),
        hasher: cpfHasher,
        sms: smsGateway,
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
