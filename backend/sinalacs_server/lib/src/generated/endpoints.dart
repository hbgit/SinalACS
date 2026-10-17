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
import '../endpoints/admin_endpoint.dart' as _i2;
import '../endpoints/alerts_endpoint.dart' as _i3;
import '../endpoints/auth_endpoint.dart' as _i4;
import '../endpoints/devices_endpoint.dart' as _i5;
import '../endpoints/health_endpoint.dart' as _i6;
import '../endpoints/notices_endpoint.dart' as _i7;
import '../endpoints/onboarding_endpoint.dart' as _i8;
import '../endpoints/patients_endpoint.dart' as _i9;
import '../endpoints/triage_endpoint.dart' as _i10;
import '../endpoints/ubs_endpoint.dart' as _i11;
import '../endpoints/visits_endpoint.dart' as _i12;
import 'package:sinalacs_server/src/generated/enums/alert_status.dart' as _i13;
import 'package:sinalacs_server/src/generated/api/admin_audit_filter.dart'
    as _i14;
import 'package:sinalacs_server/src/generated/enums/data_subject_request_status.dart'
    as _i15;
import 'package:sinalacs_server/src/generated/enums/escalation_reason.dart'
    as _i16;
import 'package:sinalacs_server/src/generated/enums/consent_purpose.dart'
    as _i17;
import 'package:sinalacs_server/src/generated/api/visit_sync_entry.dart'
    as _i18;

class Endpoints extends _i1.EndpointDispatch {
  @override
  void initializeEndpoints(_i1.Server server) {
    var endpoints = <String, _i1.Endpoint>{
      'admin': _i2.AdminEndpoint()
        ..initialize(
          server,
          'admin',
          null,
        ),
      'alerts': _i3.AlertsEndpoint()
        ..initialize(
          server,
          'alerts',
          null,
        ),
      'auth': _i4.AuthEndpoint()
        ..initialize(
          server,
          'auth',
          null,
        ),
      'devices': _i5.DevicesEndpoint()
        ..initialize(
          server,
          'devices',
          null,
        ),
      'health': _i6.HealthEndpoint()
        ..initialize(
          server,
          'health',
          null,
        ),
      'notices': _i7.NoticesEndpoint()
        ..initialize(
          server,
          'notices',
          null,
        ),
      'onboarding': _i8.OnboardingEndpoint()
        ..initialize(
          server,
          'onboarding',
          null,
        ),
      'patients': _i9.PatientsEndpoint()
        ..initialize(
          server,
          'patients',
          null,
        ),
      'triage': _i10.TriageEndpoint()
        ..initialize(
          server,
          'triage',
          null,
        ),
      'ubs': _i11.UbsEndpoint()
        ..initialize(
          server,
          'ubs',
          null,
        ),
      'visits': _i12.VisitsEndpoint()
        ..initialize(
          server,
          'visits',
          null,
        ),
    };
    connectors['admin'] = _i1.EndpointConnector(
      name: 'admin',
      endpoint: endpoints['admin']!,
      methodConnectors: {
        'indicators': _i1.MethodConnector(
          name: 'indicators',
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
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).indicators(
                session,
                accessToken: params['accessToken'],
              ),
        ),
        'microAreas': _i1.MethodConnector(
          name: 'microAreas',
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
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).microAreas(
                session,
                accessToken: params['accessToken'],
              ),
        ),
        'alerts': _i1.MethodConnector(
          name: 'alerts',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'microAreaId': _i1.ParameterDescription(
              name: 'microAreaId',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
            'status': _i1.ParameterDescription(
              name: 'status',
              type: _i1.getType<_i13.AlertStatus?>(),
              nullable: true,
            ),
            'limit': _i1.ParameterDescription(
              name: 'limit',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'offset': _i1.ParameterDescription(
              name: 'offset',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).alerts(
                session,
                accessToken: params['accessToken'],
                microAreaId: params['microAreaId'],
                status: params['status'],
                limit: params['limit'],
                offset: params['offset'],
              ),
        ),
        'alertsPulse': _i1.MethodConnector(
          name: 'alertsPulse',
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
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).alertsPulse(
                session,
                accessToken: params['accessToken'],
              ),
        ),
        'endMonitoringSession': _i1.MethodConnector(
          name: 'endMonitoringSession',
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
              ) async => (endpoints['admin'] as _i2.AdminEndpoint)
                  .endMonitoringSession(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
        'auditLogs': _i1.MethodConnector(
          name: 'auditLogs',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'filter': _i1.ParameterDescription(
              name: 'filter',
              type: _i1.getType<_i14.AdminAuditFilter?>(),
              nullable: true,
            ),
            'limit': _i1.ParameterDescription(
              name: 'limit',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'beforeSequence': _i1.ParameterDescription(
              name: 'beforeSequence',
              type: _i1.getType<int?>(),
              nullable: true,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).auditLogs(
                session,
                accessToken: params['accessToken'],
                filter: params['filter'],
                limit: params['limit'],
                beforeSequence: params['beforeSequence'],
              ),
        ),
        'verifyAuditChain': _i1.MethodConnector(
          name: 'verifyAuditChain',
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
                  (endpoints['admin'] as _i2.AdminEndpoint).verifyAuditChain(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
        'exportAuditLogs': _i1.MethodConnector(
          name: 'exportAuditLogs',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'filter': _i1.ParameterDescription(
              name: 'filter',
              type: _i1.getType<_i14.AdminAuditFilter>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).exportAuditLogs(
                    session,
                    accessToken: params['accessToken'],
                    filter: params['filter'],
                  ),
        ),
        'dataSubjectRequests': _i1.MethodConnector(
          name: 'dataSubjectRequests',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'status': _i1.ParameterDescription(
              name: 'status',
              type: _i1.getType<_i15.DataSubjectRequestStatus?>(),
              nullable: true,
            ),
            'limit': _i1.ParameterDescription(
              name: 'limit',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'offset': _i1.ParameterDescription(
              name: 'offset',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).dataSubjectRequests(
                    session,
                    accessToken: params['accessToken'],
                    status: params['status'],
                    limit: params['limit'],
                    offset: params['offset'],
                  ),
        ),
        'dataSubjectRequest': _i1.MethodConnector(
          name: 'dataSubjectRequest',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'id': _i1.ParameterDescription(
              name: 'id',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).dataSubjectRequest(
                    session,
                    accessToken: params['accessToken'],
                    id: params['id'],
                  ),
        ),
        'startDataSubjectReview': _i1.MethodConnector(
          name: 'startDataSubjectReview',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'id': _i1.ParameterDescription(
              name: 'id',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['admin'] as _i2.AdminEndpoint)
                  .startDataSubjectReview(
                    session,
                    accessToken: params['accessToken'],
                    id: params['id'],
                  ),
        ),
        'completeDataSubjectRequest': _i1.MethodConnector(
          name: 'completeDataSubjectRequest',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'id': _i1.ParameterDescription(
              name: 'id',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'note': _i1.ParameterDescription(
              name: 'note',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['admin'] as _i2.AdminEndpoint)
                  .completeDataSubjectRequest(
                    session,
                    accessToken: params['accessToken'],
                    id: params['id'],
                    note: params['note'],
                  ),
        ),
        'rejectDataSubjectRequest': _i1.MethodConnector(
          name: 'rejectDataSubjectRequest',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'id': _i1.ParameterDescription(
              name: 'id',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'reason': _i1.ParameterDescription(
              name: 'reason',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['admin'] as _i2.AdminEndpoint)
                  .rejectDataSubjectRequest(
                    session,
                    accessToken: params['accessToken'],
                    id: params['id'],
                    reason: params['reason'],
                  ),
        ),
        'acs': _i1.MethodConnector(
          name: 'acs',
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
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).acs(
                session,
                accessToken: params['accessToken'],
              ),
        ),
        'staff': _i1.MethodConnector(
          name: 'staff',
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
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).staff(
                session,
                accessToken: params['accessToken'],
              ),
        ),
        'createAcs': _i1.MethodConnector(
          name: 'createAcs',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'name': _i1.ParameterDescription(
              name: 'name',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'enrollmentId': _i1.ParameterDescription(
              name: 'enrollmentId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'microAreaId': _i1.ParameterDescription(
              name: 'microAreaId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).createAcs(
                session,
                accessToken: params['accessToken'],
                name: params['name'],
                enrollmentId: params['enrollmentId'],
                microAreaId: params['microAreaId'],
              ),
        ),
        'setAcsMicroArea': _i1.MethodConnector(
          name: 'setAcsMicroArea',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'acsId': _i1.ParameterDescription(
              name: 'acsId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'microAreaId': _i1.ParameterDescription(
              name: 'microAreaId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).setAcsMicroArea(
                    session,
                    accessToken: params['accessToken'],
                    acsId: params['acsId'],
                    microAreaId: params['microAreaId'],
                  ),
        ),
        'setAcsActive': _i1.MethodConnector(
          name: 'setAcsActive',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'acsId': _i1.ParameterDescription(
              name: 'acsId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'active': _i1.ParameterDescription(
              name: 'active',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).setAcsActive(
                session,
                accessToken: params['accessToken'],
                acsId: params['acsId'],
                active: params['active'],
              ),
        ),
        'resetAcsPassword': _i1.MethodConnector(
          name: 'resetAcsPassword',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'acsId': _i1.ParameterDescription(
              name: 'acsId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).resetAcsPassword(
                    session,
                    accessToken: params['accessToken'],
                    acsId: params['acsId'],
                  ),
        ),
        'resetAcsMfa': _i1.MethodConnector(
          name: 'resetAcsMfa',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'acsId': _i1.ParameterDescription(
              name: 'acsId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['admin'] as _i2.AdminEndpoint).resetAcsMfa(
                session,
                accessToken: params['accessToken'],
                acsId: params['acsId'],
              ),
        ),
        'resetStaffMfa': _i1.MethodConnector(
          name: 'resetStaffMfa',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'staffId': _i1.ParameterDescription(
              name: 'staffId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).resetStaffMfa(
                    session,
                    accessToken: params['accessToken'],
                    staffId: params['staffId'],
                  ),
        ),
        'escalateAlert': _i1.MethodConnector(
          name: 'escalateAlert',
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
            'reason': _i1.ParameterDescription(
              name: 'reason',
              type: _i1.getType<_i16.EscalationReason>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).escalateAlert(
                    session,
                    accessToken: params['accessToken'],
                    alertId: params['alertId'],
                    reason: params['reason'],
                  ),
        ),
        'scheduleNotice': _i1.MethodConnector(
          name: 'scheduleNotice',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'microAreaId': _i1.ParameterDescription(
              name: 'microAreaId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'audience': _i1.ParameterDescription(
              name: 'audience',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'title': _i1.ParameterDescription(
              name: 'title',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'message': _i1.ParameterDescription(
              name: 'message',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'scheduledFor': _i1.ParameterDescription(
              name: 'scheduledFor',
              type: _i1.getType<DateTime>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).scheduleNotice(
                    session,
                    accessToken: params['accessToken'],
                    microAreaId: params['microAreaId'],
                    audience: params['audience'],
                    title: params['title'],
                    message: params['message'],
                    scheduledFor: params['scheduledFor'],
                  ),
        ),
        'cancelScheduledNotice': _i1.MethodConnector(
          name: 'cancelScheduledNotice',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'id': _i1.ParameterDescription(
              name: 'id',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['admin'] as _i2.AdminEndpoint)
                  .cancelScheduledNotice(
                    session,
                    accessToken: params['accessToken'],
                    id: params['id'],
                  ),
        ),
        'noticeHistory': _i1.MethodConnector(
          name: 'noticeHistory',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'microAreaId': _i1.ParameterDescription(
              name: 'microAreaId',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
            'limit': _i1.ParameterDescription(
              name: 'limit',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'offset': _i1.ParameterDescription(
              name: 'offset',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).noticeHistory(
                    session,
                    accessToken: params['accessToken'],
                    microAreaId: params['microAreaId'],
                    limit: params['limit'],
                    offset: params['offset'],
                  ),
        ),
        'termsVersions': _i1.MethodConnector(
          name: 'termsVersions',
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
                  (endpoints['admin'] as _i2.AdminEndpoint).termsVersions(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
        'draftTermsVersion': _i1.MethodConnector(
          name: 'draftTermsVersion',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'version': _i1.ParameterDescription(
              name: 'version',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'summary': _i1.ParameterDescription(
              name: 'summary',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'effectiveFrom': _i1.ParameterDescription(
              name: 'effectiveFrom',
              type: _i1.getType<DateTime>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).draftTermsVersion(
                    session,
                    accessToken: params['accessToken'],
                    version: params['version'],
                    summary: params['summary'],
                    effectiveFrom: params['effectiveFrom'],
                  ),
        ),
        'markTermsReviewed': _i1.MethodConnector(
          name: 'markTermsReviewed',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'id': _i1.ParameterDescription(
              name: 'id',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).markTermsReviewed(
                    session,
                    accessToken: params['accessToken'],
                    id: params['id'],
                  ),
        ),
        'publishTermsVersion': _i1.MethodConnector(
          name: 'publishTermsVersion',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'id': _i1.ParameterDescription(
              name: 'id',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['admin'] as _i2.AdminEndpoint).publishTermsVersion(
                    session,
                    accessToken: params['accessToken'],
                    id: params['id'],
                  ),
        ),
      },
    );
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
                  (endpoints['alerts'] as _i3.AlertsEndpoint).createRedAlert(
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
                  (endpoints['alerts'] as _i3.AlertsEndpoint).acknowledge(
                    session,
                    accessToken: params['accessToken'],
                    alertId: params['alertId'],
                  ),
        ),
        'resolve': _i1.MethodConnector(
          name: 'resolve',
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
              ) async => (endpoints['alerts'] as _i3.AlertsEndpoint).resolve(
                session,
                accessToken: params['accessToken'],
                alertId: params['alertId'],
              ),
        ),
        'openForMicroArea': _i1.MethodConnector(
          name: 'openForMicroArea',
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
                  (endpoints['alerts'] as _i3.AlertsEndpoint).openForMicroArea(
                    session,
                    accessToken: params['accessToken'],
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
              ) async => (endpoints['alerts'] as _i3.AlertsEndpoint).statusFor(
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
                  (endpoints['auth'] as _i4.AuthEndpoint).developmentLogin(
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
            'totpCode': _i1.ParameterDescription(
              name: 'totpCode',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['auth'] as _i4.AuthEndpoint).loginInstitutional(
                    session,
                    matricula: params['matricula'],
                    password: params['password'],
                    deviceId: params['deviceId'],
                    totpCode: params['totpCode'],
                  ),
        ),
        'loginStaff': _i1.MethodConnector(
          name: 'loginStaff',
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
            'totpCode': _i1.ParameterDescription(
              name: 'totpCode',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['auth'] as _i4.AuthEndpoint).loginStaff(
                session,
                matricula: params['matricula'],
                password: params['password'],
                totpCode: params['totpCode'],
              ),
        ),
        'beginStaffTotpEnrollment': _i1.MethodConnector(
          name: 'beginStaffTotpEnrollment',
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
            'activationCode': _i1.ParameterDescription(
              name: 'activationCode',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['auth'] as _i4.AuthEndpoint)
                  .beginStaffTotpEnrollment(
                    session,
                    matricula: params['matricula'],
                    password: params['password'],
                    activationCode: params['activationCode'],
                  ),
        ),
        'confirmStaffTotpEnrollment': _i1.MethodConnector(
          name: 'confirmStaffTotpEnrollment',
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
            'activationCode': _i1.ParameterDescription(
              name: 'activationCode',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'code': _i1.ParameterDescription(
              name: 'code',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['auth'] as _i4.AuthEndpoint)
                  .confirmStaffTotpEnrollment(
                    session,
                    matricula: params['matricula'],
                    password: params['password'],
                    activationCode: params['activationCode'],
                    code: params['code'],
                  ),
        ),
        'refreshSession': _i1.MethodConnector(
          name: 'refreshSession',
          params: {
            'refreshToken': _i1.ParameterDescription(
              name: 'refreshToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'deviceId': _i1.ParameterDescription(
              name: 'deviceId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['auth'] as _i4.AuthEndpoint).refreshSession(
                session,
                refreshToken: params['refreshToken'],
                deviceId: params['deviceId'],
              ),
        ),
        'logout': _i1.MethodConnector(
          name: 'logout',
          params: {
            'refreshToken': _i1.ParameterDescription(
              name: 'refreshToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['auth'] as _i4.AuthEndpoint).logout(
                session,
                refreshToken: params['refreshToken'],
              ),
        ),
        'beginTotpEnrollment': _i1.MethodConnector(
          name: 'beginTotpEnrollment',
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
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['auth'] as _i4.AuthEndpoint).beginTotpEnrollment(
                    session,
                    matricula: params['matricula'],
                    password: params['password'],
                  ),
        ),
        'confirmTotpEnrollment': _i1.MethodConnector(
          name: 'confirmTotpEnrollment',
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
            'code': _i1.ParameterDescription(
              name: 'code',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['auth'] as _i4.AuthEndpoint).confirmTotpEnrollment(
                    session,
                    matricula: params['matricula'],
                    password: params['password'],
                    code: params['code'],
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
              ) async => (endpoints['auth'] as _i4.AuthEndpoint).requestOtp(
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
              ) async => (endpoints['auth'] as _i4.AuthEndpoint).verifyOtp(
                session,
                cpf: params['cpf'],
                code: params['code'],
                deviceId: params['deviceId'],
              ),
        ),
      },
    );
    connectors['devices'] = _i1.EndpointConnector(
      name: 'devices',
      endpoint: endpoints['devices']!,
      methodConnectors: {
        'registerPushToken': _i1.MethodConnector(
          name: 'registerPushToken',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'token': _i1.ParameterDescription(
              name: 'token',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'platform': _i1.ParameterDescription(
              name: 'platform',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['devices'] as _i5.DevicesEndpoint)
                  .registerPushToken(
                    session,
                    accessToken: params['accessToken'],
                    token: params['token'],
                    platform: params['platform'],
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
                  (endpoints['health'] as _i6.HealthEndpoint).check(session),
        ),
      },
    );
    connectors['notices'] = _i1.EndpointConnector(
      name: 'notices',
      endpoint: endpoints['notices']!,
      methodConnectors: {
        'sendSegmented': _i1.MethodConnector(
          name: 'sendSegmented',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'title': _i1.ParameterDescription(
              name: 'title',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'message': _i1.ParameterDescription(
              name: 'message',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'audience': _i1.ParameterDescription(
              name: 'audience',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['notices'] as _i7.NoticesEndpoint).sendSegmented(
                    session,
                    accessToken: params['accessToken'],
                    title: params['title'],
                    message: params['message'],
                    audience: params['audience'],
                  ),
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
              ) async => (endpoints['onboarding'] as _i8.OnboardingEndpoint)
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
            'termsAccepted': _i1.ParameterDescription(
              name: 'termsAccepted',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['onboarding'] as _i8.OnboardingEndpoint)
                  .completeEnrollment(
                    session,
                    token: params['token'],
                    healthDataConsent: params['healthDataConsent'],
                    remindersConsent: params['remindersConsent'],
                    pushConsent: params['pushConsent'],
                    termsAccepted: params['termsAccepted'],
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
                  (endpoints['patients'] as _i9.PatientsEndpoint).listMicroArea(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
        'myChronicConditions': _i1.MethodConnector(
          name: 'myChronicConditions',
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
              ) async => (endpoints['patients'] as _i9.PatientsEndpoint)
                  .myChronicConditions(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
        'updateChronicConditions': _i1.MethodConnector(
          name: 'updateChronicConditions',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'conditions': _i1.ParameterDescription(
              name: 'conditions',
              type: _i1.getType<List<String>>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['patients'] as _i9.PatientsEndpoint)
                  .updateChronicConditions(
                    session,
                    accessToken: params['accessToken'],
                    conditions: params['conditions'],
                  ),
        ),
        'myData': _i1.MethodConnector(
          name: 'myData',
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
              ) async => (endpoints['patients'] as _i9.PatientsEndpoint).myData(
                session,
                accessToken: params['accessToken'],
              ),
        ),
        'updateConsent': _i1.MethodConnector(
          name: 'updateConsent',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'purpose': _i1.ParameterDescription(
              name: 'purpose',
              type: _i1.getType<_i17.ConsentPurpose>(),
              nullable: false,
            ),
            'granted': _i1.ParameterDescription(
              name: 'granted',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['patients'] as _i9.PatientsEndpoint).updateConsent(
                    session,
                    accessToken: params['accessToken'],
                    purpose: params['purpose'],
                    granted: params['granted'],
                  ),
        ),
        'acceptTermsOfUse': _i1.MethodConnector(
          name: 'acceptTermsOfUse',
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
              ) async => (endpoints['patients'] as _i9.PatientsEndpoint)
                  .acceptTermsOfUse(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
        'hasAcceptedCurrentTerms': _i1.MethodConnector(
          name: 'hasAcceptedCurrentTerms',
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
              ) async => (endpoints['patients'] as _i9.PatientsEndpoint)
                  .hasAcceptedCurrentTerms(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
        'hasGrantedConsent': _i1.MethodConnector(
          name: 'hasGrantedConsent',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'purpose': _i1.ParameterDescription(
              name: 'purpose',
              type: _i1.getType<_i17.ConsentPurpose>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['patients'] as _i9.PatientsEndpoint)
                  .hasGrantedConsent(
                    session,
                    accessToken: params['accessToken'],
                    purpose: params['purpose'],
                  ),
        ),
        'termsChangeNotice': _i1.MethodConnector(
          name: 'termsChangeNotice',
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
              ) async => (endpoints['patients'] as _i9.PatientsEndpoint)
                  .termsChangeNotice(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
        'requestDataDeletion': _i1.MethodConnector(
          name: 'requestDataDeletion',
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
              ) async => (endpoints['patients'] as _i9.PatientsEndpoint)
                  .requestDataDeletion(
                    session,
                    accessToken: params['accessToken'],
                  ),
        ),
        'requestDataCorrection': _i1.MethodConnector(
          name: 'requestDataCorrection',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'details': _i1.ParameterDescription(
              name: 'details',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['patients'] as _i9.PatientsEndpoint)
                  .requestDataCorrection(
                    session,
                    accessToken: params['accessToken'],
                    details: params['details'],
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
              ) async => (endpoints['triage'] as _i10.TriageEndpoint).evaluate(
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
    connectors['ubs'] = _i1.EndpointConnector(
      name: 'ubs',
      endpoint: endpoints['ubs']!,
      methodConnectors: {
        'myContact': _i1.MethodConnector(
          name: 'myContact',
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
              ) async => (endpoints['ubs'] as _i11.UbsEndpoint).myContact(
                session,
                accessToken: params['accessToken'],
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
              type: _i1.getType<List<_i18.VisitSyncEntry>>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['visits'] as _i12.VisitsEndpoint).sync(
                session,
                accessToken: params['accessToken'],
                visits: params['visits'],
              ),
        ),
        'resolveConflict': _i1.MethodConnector(
          name: 'resolveConflict',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'visit': _i1.ParameterDescription(
              name: 'visit',
              type: _i1.getType<_i18.VisitSyncEntry>(),
              nullable: false,
            ),
            'expectedServerVersion': _i1.ParameterDescription(
              name: 'expectedServerVersion',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['visits'] as _i12.VisitsEndpoint).resolveConflict(
                    session,
                    accessToken: params['accessToken'],
                    visit: params['visit'],
                    expectedServerVersion: params['expectedServerVersion'],
                  ),
        ),
        'syncLegacy': _i1.MethodConnector(
          name: 'syncLegacy',
          params: {
            'accessToken': _i1.ParameterDescription(
              name: 'accessToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'deviceId': _i1.ParameterDescription(
              name: 'deviceId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'visits': _i1.ParameterDescription(
              name: 'visits',
              type: _i1.getType<List<_i18.VisitSyncEntry>>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['visits'] as _i12.VisitsEndpoint).syncLegacy(
                    session,
                    accessToken: params['accessToken'],
                    deviceId: params['deviceId'],
                    visits: params['visits'],
                  ),
        ),
        'syncDeferred': _i1.MethodConnector(
          name: 'syncDeferred',
          params: {
            'uploadToken': _i1.ParameterDescription(
              name: 'uploadToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'deviceId': _i1.ParameterDescription(
              name: 'deviceId',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'visits': _i1.ParameterDescription(
              name: 'visits',
              type: _i1.getType<List<_i18.VisitSyncEntry>>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['visits'] as _i12.VisitsEndpoint).syncDeferred(
                    session,
                    uploadToken: params['uploadToken'],
                    deviceId: params['deviceId'],
                    visits: params['visits'],
                  ),
        ),
        'revokeUploadToken': _i1.MethodConnector(
          name: 'revokeUploadToken',
          params: {
            'uploadToken': _i1.ParameterDescription(
              name: 'uploadToken',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['visits'] as _i12.VisitsEndpoint)
                  .revokeUploadToken(
                    session,
                    uploadToken: params['uploadToken'],
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
              ) async => (endpoints['visits'] as _i12.VisitsEndpoint).pull(
                session,
                accessToken: params['accessToken'],
                since: params['since'],
              ),
        ),
      },
    );
  }
}
