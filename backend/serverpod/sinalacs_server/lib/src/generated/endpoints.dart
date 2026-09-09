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
import '../endpoints/triage_endpoint.dart' as _i5;

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
      'triage': _i5.TriageEndpoint()
        ..initialize(
          server,
          'triage',
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
    connectors['triage'] = _i1.EndpointConnector(
      name: 'triage',
      endpoint: endpoints['triage']!,
      methodConnectors: {
        'evaluate': _i1.MethodConnector(
          name: 'evaluate',
          params: {
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
              ) async => (endpoints['triage'] as _i5.TriageEndpoint).evaluate(
                session,
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
  }
}
