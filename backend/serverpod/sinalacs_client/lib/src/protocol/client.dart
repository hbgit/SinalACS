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

import 'package:serverpod_client/serverpod_client.dart' as _i1;
import 'dart:async' as _i2;
import 'package:sinalacs_client/src/protocol/api/red_alert_result.dart' as _i3;
import 'package:sinalacs_client/src/protocol/api/alert_ack_result.dart' as _i4;
import 'package:sinalacs_client/src/protocol/api/development_login_result.dart'
    as _i5;
import 'package:sinalacs_client/src/protocol/api/service_health.dart' as _i6;
import 'package:sinalacs_client/src/protocol/api/triage_result.dart' as _i7;
import 'protocol.dart' as _i8;

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
class EndpointAlerts extends _i1.EndpointRef {
  EndpointAlerts(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'alerts';

  _i2.Future<_i3.RedAlertResult> createRedAlert({
    required String accessToken,
    required String idempotencyKey,
    required String locationHash,
  }) => caller.callServerEndpoint<_i3.RedAlertResult>(
    'alerts',
    'createRedAlert',
    {
      'accessToken': accessToken,
      'idempotencyKey': idempotencyKey,
      'locationHash': locationHash,
    },
  );

  _i2.Future<_i4.AlertAckResult> acknowledge({
    required String accessToken,
    required String alertId,
  }) => caller.callServerEndpoint<_i4.AlertAckResult>(
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
class EndpointAuth extends _i1.EndpointRef {
  EndpointAuth(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'auth';

  _i2.Future<_i5.DevelopmentLoginResult> developmentLogin({
    required String role,
  }) => caller.callServerEndpoint<_i5.DevelopmentLoginResult>(
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
class EndpointHealth extends _i1.EndpointRef {
  EndpointHealth(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'health';

  _i2.Future<_i6.ServiceHealth> check() =>
      caller.callServerEndpoint<_i6.ServiceHealth>(
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
class EndpointTriage extends _i1.EndpointRef {
  EndpointTriage(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'triage';

  _i2.Future<_i7.TriageResult> evaluate({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) => caller.callServerEndpoint<_i7.TriageResult>(
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

class Client extends _i1.ServerpodClientShared {
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
      _i1.MethodCallContext,
      Object,
      StackTrace,
    )?
    onFailedCall,
    Function(_i1.MethodCallContext)? onSucceededCall,
    bool? disconnectStreamsOnLostInternetConnection,
  }) : super(
         host,
         _i8.Protocol(),
         securityContext: securityContext,
         streamingConnectionTimeout: streamingConnectionTimeout,
         connectionTimeout: connectionTimeout,
         onFailedCall: onFailedCall,
         onSucceededCall: onSucceededCall,
         disconnectStreamsOnLostInternetConnection:
             disconnectStreamsOnLostInternetConnection,
       ) {
    alerts = EndpointAlerts(this);
    auth = EndpointAuth(this);
    health = EndpointHealth(this);
    triage = EndpointTriage(this);
  }

  late final EndpointAlerts alerts;

  late final EndpointAuth auth;

  late final EndpointHealth health;

  late final EndpointTriage triage;

  @override
  Map<String, _i1.EndpointRef> get endpointRefLookup => {
    'alerts': alerts,
    'auth': auth,
    'health': health,
    'triage': triage,
  };

  @override
  Map<String, _i1.ModuleEndpointCaller> get moduleLookup => {};
}
