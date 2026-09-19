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

import 'package:serverpod/serverpod.dart' as _i1;
import '../endpoints/alerts_endpoint.dart' as _i2;
import '../endpoints/auth_endpoint.dart' as _i3;
import '../endpoints/health_endpoint.dart' as _i4;
import '../endpoints/onboarding_endpoint.dart' as _i5;
import '../endpoints/patients_endpoint.dart' as _i6;
import '../endpoints/triage_endpoint.dart' as _i7;
import '../endpoints/visits_endpoint.dart' as _i8;
import 'package:sinalacs_server/src/generated/api/visit_sync_entry.dart' as _i9;

class Endpoints extends _i1.EndpointDispatch {
  @override
  void initializeEndpoints(_i1.Server server) {
    var endpoints = <String, _i1.Endpoint>{
      'alerts': _i2.AlertsEndpoint()
        ..initialize(
          server,
          'alerts',
          null,
        ),
      'auth': _i3.AuthEndpoint()
        ..initialize(
          server,
          'auth',
          null,
        ),
      'health': _i4.HealthEndpoint()
        ..initialize(
          server,
          'health',
          null,
        ),
      'onboarding': _i5.OnboardingEndpoint()
        ..initialize(
          server,
          'onboarding',
          null,
        ),
      'patients': _i6.PatientsEndpoint()
        ..initialize(
          server,
          'patients',
          null,
        ),
      'triage': _i7.TriageEndpoint()
        ..initialize(
          server,
          'triage',
          null,
        ),
      'visits': _i8.VisitsEndpoint()
        ..initialize(
          server,
          'visits',
          null,
        ),
    };
    connectors['alerts'] = _i1.EndpointConnector(
      name: 'alerts',
      endpoint: endpoints['alerts']!,
      methodConnectors: {
        'createRedAlert': _i1.MethodConnector(
          name: 'createRedAlert',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'idempotencyKey': _i1.ParameterDescription(
              name: 'idempotencyKey',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'locationHash': _i1.ParameterDescription(
              name: 'locationHash',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'locationCell': _i1.ParameterDescription(
              name: 'locationCell',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['alerts'] as _i2.AlertsEndpoint).createRedAlert(
                    session,
                    accessToken: params['accessToken'],
                    idempotencyKey: params['idempotencyKey'],
                    locationHash: params['locationHash'],
                    locationCell: params['locationCell'],
                  ),
        ),
        'acknowledge': _i1.MethodConnector(
          name: 'acknowledge',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'alertId': _i1.ParameterDescription(
              name: 'alertId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['alerts'] as _i2.AlertsEndpoint).acknowledge(
                    session,
                    accessToken: params['accessToken'],
                    alertId: params['alertId'],
                  ),
        ),
        'statusFor': _i1.MethodConnector(
          name: 'statusFor',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['alerts'] as _i2.AlertsEndpoint).statusFor(
                session,
                accessToken: params['accessToken'],
              ),
        ),
      },
    );
    connectors['auth'] = _i1.EndpointConnector(
      name: 'auth',
      endpoint: endpoints['auth']!,
      methodConnectors: {
        'developmentLogin': _i1.MethodConnector(
          name: 'developmentLogin',
          params: {
            'role': _i1.ParameterDescription(
              name: 'role',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['auth'] as _i3.AuthEndpoint).developmentLogin(
                    session,
                    role: params['role'],
                  ),
        ),
        'loginInstitutional': _i1.MethodConnector(
          name: 'loginInstitutional',
          params: {
            'matricula': _i1.ParameterDescription(
              name: 'matricula',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'password': _i1.ParameterDescription(
              name: 'password',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'deviceId': _i1.ParameterDescription(
              name: 'deviceId',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['auth'] as _i3.AuthEndpoint).loginInstitutional(
                    session,
                    matricula: params['matricula'],
                    password: params['password'],
                    deviceId: params['deviceId'],
                  ),
        ),
        'requestOtp': _i1.MethodConnector(
          name: 'requestOtp',
          params: {
            'cpf': _i1.ParameterDescription(
              name: 'cpf',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'birthDate': _i1.ParameterDescription(
              name: 'birthDate',
              type: _i1.getType<DateTime>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['auth'] as _i3.AuthEndpoint).requestOtp(
                session,
                cpf: params['cpf'],
                birthDate: params['birthDate'],
              ),
        ),
        'verifyOtp': _i1.MethodConnector(
          name: 'verifyOtp',
          params: {
            'cpf': _i1.ParameterDescription(
              name: 'cpf',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'code': _i1.ParameterDescription(
              name: 'code',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'deviceId': _i1.ParameterDescription(
              name: 'deviceId',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['auth'] as _i3.AuthEndpoint).verifyOtp(
                session,
                cpf: params['cpf'],
                code: params['code'],
                deviceId: params['deviceId'],
              ),
        ),
      },
    );
    connectors['health'] = _i1.EndpointConnector(
      name: 'health',
      endpoint: endpoints['health']!,
      methodConnectors: {
        'check': _i1.MethodConnector(
          name: 'check',
          params: {},
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['health'] as _i4.HealthEndpoint).check(session),
        ),
      },
    );
    connectors['onboarding'] = _i1.EndpointConnector(
      name: 'onboarding',
      endpoint: endpoints['onboarding']!,
      methodConnectors: {
        'generateEnrollmentToken': _i1.MethodConnector(
          name: 'generateEnrollmentToken',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'patientId': _i1.ParameterDescription(
              name: 'patientId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['onboarding'] as _i5.OnboardingEndpoint)
                  .generateEnrollmentToken(
                    session,
                    accessToken: params['accessToken'],
                    patientId: params['patientId'],
                  ),
        ),
        'completeEnrollment': _i1.MethodConnector(
          name: 'completeEnrollment',
          params: {
            'token': _i1.ParameterDescription(
              name: 'token',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'healthDataConsent': _i1.ParameterDescription(
              name: 'healthDataConsent',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
            'remindersConsent': _i1.ParameterDescription(
              name: 'remindersConsent',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
            'pushConsent': _i1.ParameterDescription(
              name: 'pushConsent',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['onboarding'] as _i5.OnboardingEndpoint)
                  .completeEnrollment(
                    session,
                    token: params['token'],
                    healthDataConsent: params['healthDataConsent'],
                    remindersConsent: params['remindersConsent'],
                    pushConsent: params['pushConsent'],
                  ),
        ),
      },
    );
    connectors['patients'] = _i1.EndpointConnector(
      name: 'patients',
      endpoint: endpoints['patients']!,
      methodConnectors: {
        'listMicroArea': _i1.MethodConnector(
          name: 'listMicroArea',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['patients'] as _i6.PatientsEndpoint).listMicroArea(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
      },
    );
    connectors['triage'] = _i1.EndpointConnector(
      name: 'triage',
      endpoint: endpoints['triage']!,
      methodConnectors: {
        'evaluate': _i1.MethodConnector(
          name: 'evaluate',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'chestPain': _i1.ParameterDescription(
              name: 'chestPain',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
            'difficultyBreathing': _i1.ParameterDescription(
              name: 'difficultyBreathing',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
            'fever': _i1.ParameterDescription(
              name: 'fever',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
            'persistentVomiting': _i1.ParameterDescription(
              name: 'persistentVomiting',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
            'bleeding': _i1.ParameterDescription(
              name: 'bleeding',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
            'severeWeakness': _i1.ParameterDescription(
              name: 'severeWeakness',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['triage'] as _i7.TriageEndpoint).evaluate(
                session,
                accessToken: params['accessToken'],
                chestPain: params['chestPain'],
                difficultyBreathing: params['difficultyBreathing'],
                fever: params['fever'],
                persistentVomiting: params['persistentVomiting'],
                bleeding: params['bleeding'],
                severeWeakness: params['severeWeakness'],
              ),
        ),
      },
    );
    connectors['visits'] = _i1.EndpointConnector(
      name: 'visits',
      endpoint: endpoints['visits']!,
      methodConnectors: {
        'sync': _i1.MethodConnector(
          name: 'sync',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'visits': _i1.ParameterDescription(
              name: 'visits',
              type: _i1.getType<List<_i9.VisitSyncEntry>>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['visits'] as _i8.VisitsEndpoint).sync(
                session,
                accessToken: params['accessToken'],
                visits: params['visits'],
              ),
        ),
        'pull': _i1.MethodConnector(
          name: 'pull',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'since': _i1.ParameterDescription(
              name: 'since',
              type: _i1.getType<DateTime>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['visits'] as _i8.VisitsEndpoint).pull(
                session,
                accessToken: params['accessToken'],
                since: params['since'],
              ),
        ),
      },
    );
  }
}
