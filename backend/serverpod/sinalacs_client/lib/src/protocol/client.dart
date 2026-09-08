/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart'
    as _i1;
import 'package:serverpod_client/serverpod_client.dart' as _i2;
import 'dart:async' as _i3;
import 'package:serverpod_auth_core_client/serverpod_auth_core_client.dart'
    as _i4;
import 'package:sinalacs_client/src/protocol/api/red_alert_result.dart' as _i5;
import 'package:sinalacs_client/src/protocol/api/alert_ack_result.dart' as _i6;
import 'package:sinalacs_client/src/protocol/api/development_login_result.dart'
    as _i7;
import 'package:sinalacs_client/src/protocol/api/service_health.dart' as _i8;
import 'package:sinalacs_client/src/protocol/api/triage_result.dart' as _i9;
import 'protocol.dart' as _i10;

/// By extending [EmailIdpBaseEndpoint], the email identity provider endpoints
/// are made available on the server and enable the corresponding sign-in widget
/// on the client.
/// {@category Endpoint}
class EndpointEmailIdp extends _i1.EndpointEmailIdpBase {
  EndpointEmailIdp(_i2.EndpointCaller caller) : super(caller);

  @override
  String get name => 'emailIdp';

  /// Logs in the user and returns a new session.
  ///
  /// Throws an [EmailAccountLoginException] in case of errors, with reason:
  /// - [EmailAccountLoginExceptionReason.invalidCredentials] if the email or
  ///   password is incorrect.
  /// - [EmailAccountLoginExceptionReason.tooManyAttempts] if there have been
  ///   too many failed login attempts.
  ///
  /// Throws an [AuthUserBlockedException] if the auth user is blocked.
  @override
  _i3.Future<_i4.AuthSuccess> login({
    required String email,
    required String password,
  }) => caller.callServerEndpoint<_i4.AuthSuccess>(
    'emailIdp',
    'login',
    {
      'email': email,
      'password': password,
    },
  );

  /// Starts the registration for a new user account with an email-based login
  /// associated to it.
  ///
  /// Upon successful completion of this method, an email will have been
  /// sent to [email] with a verification link, which the user must open to
  /// complete the registration.
  ///
  /// Always returns a account request ID, which can be used to complete the
  /// registration. If the email is already registered, the returned ID will not
  /// be valid.
  @override
  _i3.Future<_i2.UuidValue> startRegistration({required String email}) =>
      caller.callServerEndpoint<_i2.UuidValue>(
        'emailIdp',
        'startRegistration',
        {'email': email},
      );

  /// Verifies an account request code and returns a token
  /// that can be used to complete the account creation.
  ///
  /// Throws an [EmailAccountRequestException] in case of errors, with reason:
  /// - [EmailAccountRequestExceptionReason.expired] if the account request has
  ///   already expired.
  /// - [EmailAccountRequestExceptionReason.policyViolation] if the password
  ///   does not comply with the password policy.
  /// - [EmailAccountRequestExceptionReason.invalid] if no request exists
  ///   for the given [accountRequestId] or [verificationCode] is invalid.
  @override
  _i3.Future<String> verifyRegistrationCode({
    required _i2.UuidValue accountRequestId,
    required String verificationCode,
  }) => caller.callServerEndpoint<String>(
    'emailIdp',
    'verifyRegistrationCode',
    {
      'accountRequestId': accountRequestId,
      'verificationCode': verificationCode,
    },
  );

  /// Completes a new account registration, creating a new auth user with a
  /// profile and attaching the given email account to it.
  ///
  /// Throws an [EmailAccountRequestException] in case of errors, with reason:
  /// - [EmailAccountRequestExceptionReason.expired] if the account request has
  ///   already expired.
  /// - [EmailAccountRequestExceptionReason.policyViolation] if the password
  ///   does not comply with the password policy.
  /// - [EmailAccountRequestExceptionReason.invalid] if the [registrationToken]
  ///   is invalid.
  ///
  /// Throws an [AuthUserBlockedException] if the auth user is blocked.
  ///
  /// Returns a session for the newly created user.
  @override
  _i3.Future<_i4.AuthSuccess> finishRegistration({
    required String registrationToken,
    required String password,
  }) => caller.callServerEndpoint<_i4.AuthSuccess>(
    'emailIdp',
    'finishRegistration',
    {
      'registrationToken': registrationToken,
      'password': password,
    },
  );

  /// Requests a password reset for [email].
  ///
  /// If the email address is registered, an email with reset instructions will
  /// be send out. If the email is unknown, this method will have no effect.
  ///
  /// Always returns a password reset request ID, which can be used to complete
  /// the reset. If the email is not registered, the returned ID will not be
  /// valid.
  ///
  /// Throws an [EmailAccountPasswordResetException] in case of errors, with reason:
  /// - [EmailAccountPasswordResetExceptionReason.tooManyAttempts] if the user has
  ///   made too many attempts trying to request a password reset.
  ///
  @override
  _i3.Future<_i2.UuidValue> startPasswordReset({required String email}) =>
      caller.callServerEndpoint<_i2.UuidValue>(
        'emailIdp',
        'startPasswordReset',
        {'email': email},
      );

  /// Verifies a password reset code and returns a finishPasswordResetToken
  /// that can be used to finish the password reset.
  ///
  /// Throws an [EmailAccountPasswordResetException] in case of errors, with reason:
  /// - [EmailAccountPasswordResetExceptionReason.expired] if the password reset
  ///   request has already expired.
  /// - [EmailAccountPasswordResetExceptionReason.tooManyAttempts] if the user has
  ///   made too many attempts trying to verify the password reset.
  /// - [EmailAccountPasswordResetExceptionReason.invalid] if no request exists
  ///   for the given [passwordResetRequestId] or [verificationCode] is invalid.
  ///
  /// If multiple steps are required to complete the password reset, this endpoint
  /// should be overridden to return credentials for the next step instead
  /// of the credentials for setting the password.
  @override
  _i3.Future<String> verifyPasswordResetCode({
    required _i2.UuidValue passwordResetRequestId,
    required String verificationCode,
  }) => caller.callServerEndpoint<String>(
    'emailIdp',
    'verifyPasswordResetCode',
    {
      'passwordResetRequestId': passwordResetRequestId,
      'verificationCode': verificationCode,
    },
  );

  /// Completes a password reset request by setting a new password.
  ///
  /// The [verificationCode] returned from [verifyPasswordResetCode] is used to
  /// validate the password reset request.
  ///
  /// Throws an [EmailAccountPasswordResetException] in case of errors, with reason:
  /// - [EmailAccountPasswordResetExceptionReason.expired] if the password reset
  ///   request has already expired.
  /// - [EmailAccountPasswordResetExceptionReason.policyViolation] if the new
  ///   password does not comply with the password policy.
  /// - [EmailAccountPasswordResetExceptionReason.invalid] if no request exists
  ///   for the given [passwordResetRequestId] or [verificationCode] is invalid.
  ///
  /// Throws an [AuthUserBlockedException] if the auth user is blocked.
  @override
  _i3.Future<void> finishPasswordReset({
    required String finishPasswordResetToken,
    required String newPassword,
  }) => caller.callServerEndpoint<void>(
    'emailIdp',
    'finishPasswordReset',
    {
      'finishPasswordResetToken': finishPasswordResetToken,
      'newPassword': newPassword,
    },
  );

  @override
  _i3.Future<bool> hasAccount() => caller.callServerEndpoint<bool>(
    'emailIdp',
    'hasAccount',
    {},
  );
}

/// By extending [RefreshJwtTokensEndpoint], the JWT token refresh endpoint
/// is made available on the server and enables automatic token refresh on the client.
/// {@category Endpoint}
class EndpointJwtRefresh extends _i4.EndpointRefreshJwtTokens {
  EndpointJwtRefresh(_i2.EndpointCaller caller) : super(caller);

  @override
  String get name => 'jwtRefresh';

  /// Creates a new token pair for the given [refreshToken].
  ///
  /// Can throw the following exceptions:
  /// -[RefreshTokenMalformedException]: refresh token is malformed and could
  ///   not be parsed. Not expected to happen for tokens issued by the server.
  /// -[RefreshTokenNotFoundException]: refresh token is unknown to the server.
  ///   Either the token was deleted or generated by a different server.
  /// -[RefreshTokenExpiredException]: refresh token has expired. Will happen
  ///   only if it has not been used within configured `refreshTokenLifetime`.
  /// -[RefreshTokenInvalidSecretException]: refresh token is incorrect, meaning
  ///   it does not refer to the current secret refresh token. This indicates
  ///   either a malfunctioning client or a malicious attempt by someone who has
  ///   obtained the refresh token. In this case the underlying refresh token
  ///   will be deleted, and access to it will expire fully when the last access
  ///   token is elapsed.
  ///
  /// This endpoint is unauthenticated, meaning the client won't include any
  /// authentication information with the call.
  @override
  _i3.Future<_i4.AuthSuccess> refreshAccessToken({
    required String refreshToken,
  }) => caller.callServerEndpoint<_i4.AuthSuccess>(
    'jwtRefresh',
    'refreshAccessToken',
    {'refreshToken': refreshToken},
    authenticated: false,
  );
}

/// Ciclo do alerta vermelho.
///
/// Substitui `POST /v1/alerts/red` e `POST /v1/alerts/{id}/ack`. Como o
/// Serverpod é RPC e não REST, três coisas que antes viajavam no HTTP mudaram
/// de lugar:
///
///  * a chave de idempotência era o header `Idempotency-Key` e agora é um
///    parâmetro do método;
///  * o mapeamento de exceção para status (400/403/503) virou exceção tipada,
///    serializada até o cliente;
///  * o 404 do ACK sem correspondência virou o campo `acknowledged: false`.
///
/// A autenticação continua sendo o token HMAC de desenvolvimento, verificado
/// aqui em vez de no laço de requisições do servidor `dart:io`.
/// {@category Endpoint}
class EndpointAlerts extends _i2.EndpointRef {
  EndpointAlerts(_i2.EndpointCaller caller) : super(caller);

  @override
  String get name => 'alerts';

  _i3.Future<_i5.RedAlertResult> createRedAlert({
    required String accessToken,
    required String idempotencyKey,
    required String locationHash,
  }) => caller.callServerEndpoint<_i5.RedAlertResult>(
    'alerts',
    'createRedAlert',
    {
      'accessToken': accessToken,
      'idempotencyKey': idempotencyKey,
      'locationHash': locationHash,
    },
  );

  _i3.Future<_i6.AlertAckResult> acknowledge({
    required String accessToken,
    required String alertId,
  }) => caller.callServerEndpoint<_i6.AlertAckResult>(
    'alerts',
    'acknowledge',
    {
      'accessToken': accessToken,
      'alertId': alertId,
    },
  );
}

/// Acesso de desenvolvimento. **Não** é autenticação institucional.
///
/// Substitui `POST /v1/auth/development/login`, preservando o gate do
/// `ENABLE_DEV_LOGIN`: quando desligado, a chamada falha como se o endpoint não
/// existisse, e não como "proibido" — o servidor `dart:io` respondia 404 e não
/// 403, para não revelar a existência da rota.
/// {@category Endpoint}
class EndpointAuth extends _i2.EndpointRef {
  EndpointAuth(_i2.EndpointCaller caller) : super(caller);

  @override
  String get name => 'auth';

  _i3.Future<_i7.DevelopmentLoginResult> developmentLogin({
    required String role,
  }) => caller.callServerEndpoint<_i7.DevelopmentLoginResult>(
    'auth',
    'developmentLogin',
    {'role': role},
  );
}

/// Sonda de saúde.
///
/// Preserva a forma do antigo `GET /health` — `{status, mqtt_connected,
/// db_connected}` — porque o `HEALTHCHECK` do Dockerfile e o runbook de
/// free-tier dependem dela.
///
/// Responde `ok` assim que o servidor está de pé, independentemente do estado
/// do broker e do banco: hosts free-tier hibernam, e um healthcheck que falha
/// junto com a dependência impede o host de acordar.
/// {@category Endpoint}
class EndpointHealth extends _i2.EndpointRef {
  EndpointHealth(_i2.EndpointCaller caller) : super(caller);

  @override
  String get name => 'health';

  _i3.Future<_i8.ServiceHealth> check() =>
      caller.callServerEndpoint<_i8.ServiceHealth>(
        'health',
        'check',
        {},
      );
}

/// Motor de triagem determinístico, inspirado no Protocolo de Manchester.
///
/// Endpoint novo: o [TriageEngine] já existia e era testado, mas nunca esteve
/// exposto por HTTP — os apps replicavam a regra do lado do cliente. Publicá-lo
/// permite que a classificação passe a vir de uma única fonte.
///
/// A mesma entrada produz sempre a mesma saída, sem modelo probabilístico e sem
/// campo editável: a classificação de risco não é alterável por intervenção
/// manual no fluxo de triagem (INV-02).
/// {@category Endpoint}
class EndpointTriage extends _i2.EndpointRef {
  EndpointTriage(_i2.EndpointCaller caller) : super(caller);

  @override
  String get name => 'triage';

  _i3.Future<_i9.TriageResult> evaluate({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) => caller.callServerEndpoint<_i9.TriageResult>(
    'triage',
    'evaluate',
    {
      'chestPain': chestPain,
      'difficultyBreathing': difficultyBreathing,
      'fever': fever,
      'persistentVomiting': persistentVomiting,
      'bleeding': bleeding,
      'severeWeakness': severeWeakness,
    },
  );
}

class Modules {
  Modules(Client client) {
    serverpod_auth_idp = _i1.Caller(client);
    serverpod_auth_core = _i4.Caller(client);
  }

  late final _i1.Caller serverpod_auth_idp;

  late final _i4.Caller serverpod_auth_core;
}

class Client extends _i2.ServerpodClientShared {
  Client(
    String host, {
    dynamic securityContext,
    @Deprecated(
      'Use authKeyProvider instead. This will be removed in future releases.',
    )
    super.authenticationKeyManager,
    Duration? streamingConnectionTimeout,
    Duration? connectionTimeout,
    Function(
      _i2.MethodCallContext,
      Object,
      StackTrace,
    )?
    onFailedCall,
    Function(_i2.MethodCallContext)? onSucceededCall,
    bool? disconnectStreamsOnLostInternetConnection,
  }) : super(
         host,
         _i10.Protocol(),
         securityContext: securityContext,
         streamingConnectionTimeout: streamingConnectionTimeout,
         connectionTimeout: connectionTimeout,
         onFailedCall: onFailedCall,
         onSucceededCall: onSucceededCall,
         disconnectStreamsOnLostInternetConnection:
             disconnectStreamsOnLostInternetConnection,
       ) {
    emailIdp = EndpointEmailIdp(this);
    jwtRefresh = EndpointJwtRefresh(this);
    alerts = EndpointAlerts(this);
    auth = EndpointAuth(this);
    health = EndpointHealth(this);
    triage = EndpointTriage(this);
    modules = Modules(this);
  }

  late final EndpointEmailIdp emailIdp;

  late final EndpointJwtRefresh jwtRefresh;

  late final EndpointAlerts alerts;

  late final EndpointAuth auth;

  late final EndpointHealth health;

  late final EndpointTriage triage;

  late final Modules modules;

  @override
  Map<String, _i2.EndpointRef> get endpointRefLookup => {
    'emailIdp': emailIdp,
    'jwtRefresh': jwtRefresh,
    'alerts': alerts,
    'auth': auth,
    'health': health,
    'triage': triage,
  };

  @override
  Map<String, _i2.ModuleEndpointCaller> get moduleLookup => {
    'serverpod_auth_idp': modules.serverpod_auth_idp,
    'serverpod_auth_core': modules.serverpod_auth_core,
  };
}
