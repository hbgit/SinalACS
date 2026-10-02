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
import 'acs.dart' as _i2;
import 'alert.dart' as _i3;
import 'alert_delivery_record.dart' as _i4;
import 'alert_idempotency_key.dart' as _i5;
import 'alert_outbox_entry.dart' as _i6;
import 'api/alert_ack_result.dart' as _i7;
import 'api/alert_status_result.dart' as _i8;
import 'api/development_login_result.dart' as _i9;
import 'api/enrollment_result.dart' as _i10;
import 'api/enrollment_token_result.dart' as _i11;
import 'api/micro_area_patient.dart' as _i12;
import 'api/notice_send_result.dart' as _i13;
import 'api/patient_consent_record.dart' as _i14;
import 'api/patient_data_overview.dart' as _i15;
import 'api/patient_data_subject_request_record.dart' as _i16;
import 'api/patient_risk_event.dart' as _i17;
import 'api/red_alert_result.dart' as _i18;
import 'api/service_health.dart' as _i19;
import 'api/terms_change_notice.dart' as _i20;
import 'api/totp_enrollment_start.dart' as _i21;
import 'api/triage_result.dart' as _i22;
import 'api/ubs_contact.dart' as _i23;
import 'api/visit_sync_entry.dart' as _i24;
import 'api/visit_sync_result.dart' as _i25;
import 'audit_log.dart' as _i26;
import 'consent_log.dart' as _i27;
import 'data_subject_request.dart' as _i28;
import 'enrollment_token.dart' as _i29;
import 'enums/alert_status.dart' as _i30;
import 'enums/arrival_method.dart' as _i31;
import 'enums/consent_purpose.dart' as _i32;
import 'enums/data_subject_request_status.dart' as _i33;
import 'enums/data_subject_request_type.dart' as _i34;
import 'enums/risk_level.dart' as _i35;
import 'enums/sync_status.dart' as _i36;
import 'enums/user_role.dart' as _i37;
import 'exceptions/alert_dispatch_unavailable_exception.dart' as _i38;
import 'exceptions/alert_permission_exception.dart' as _i39;
import 'exceptions/alert_validation_exception.dart' as _i40;
import 'exceptions/authentication_failed_exception.dart' as _i41;
import 'exceptions/data_rights_exception.dart' as _i42;
import 'exceptions/endpoint_disabled_exception.dart' as _i43;
import 'exceptions/enrollment_exception.dart' as _i44;
import 'exceptions/mfa_enrollment_required_exception.dart' as _i45;
import 'exceptions/mfa_required_exception.dart' as _i46;
import 'exceptions/notice_delivery_exception.dart' as _i47;
import 'exceptions/otp_request_exception.dart' as _i48;
import 'micro_area.dart' as _i49;
import 'otp_challenge.dart' as _i50;
import 'patient.dart' as _i51;
import 'push_token.dart' as _i52;
import 'triage_answer.dart' as _i53;
import 'triage_session.dart' as _i54;
import 'ubs.dart' as _i55;
import 'user.dart' as _i56;
import 'user_credential.dart' as _i57;
import 'visit.dart' as _i58;
import 'package:sinalacs_client/src/protocol/api/micro_area_patient.dart'
    as _i59;
import 'package:sinalacs_client/src/protocol/api/visit_sync_result.dart'
    as _i60;
import 'package:sinalacs_client/src/protocol/api/visit_sync_entry.dart' as _i61;
export 'acs.dart';
export 'alert.dart';
export 'alert_delivery_record.dart';
export 'alert_idempotency_key.dart';
export 'alert_outbox_entry.dart';
export 'api/alert_ack_result.dart';
export 'api/alert_status_result.dart';
export 'api/development_login_result.dart';
export 'api/enrollment_result.dart';
export 'api/enrollment_token_result.dart';
export 'api/micro_area_patient.dart';
export 'api/notice_send_result.dart';
export 'api/patient_consent_record.dart';
export 'api/patient_data_overview.dart';
export 'api/patient_data_subject_request_record.dart';
export 'api/patient_risk_event.dart';
export 'api/red_alert_result.dart';
export 'api/service_health.dart';
export 'api/terms_change_notice.dart';
export 'api/totp_enrollment_start.dart';
export 'api/triage_result.dart';
export 'api/ubs_contact.dart';
export 'api/visit_sync_entry.dart';
export 'api/visit_sync_result.dart';
export 'audit_log.dart';
export 'consent_log.dart';
export 'data_subject_request.dart';
export 'enrollment_token.dart';
export 'enums/alert_status.dart';
export 'enums/arrival_method.dart';
export 'enums/consent_purpose.dart';
export 'enums/data_subject_request_status.dart';
export 'enums/data_subject_request_type.dart';
export 'enums/risk_level.dart';
export 'enums/sync_status.dart';
export 'enums/user_role.dart';
export 'exceptions/alert_dispatch_unavailable_exception.dart';
export 'exceptions/alert_permission_exception.dart';
export 'exceptions/alert_validation_exception.dart';
export 'exceptions/authentication_failed_exception.dart';
export 'exceptions/data_rights_exception.dart';
export 'exceptions/endpoint_disabled_exception.dart';
export 'exceptions/enrollment_exception.dart';
export 'exceptions/mfa_enrollment_required_exception.dart';
export 'exceptions/mfa_required_exception.dart';
export 'exceptions/notice_delivery_exception.dart';
export 'exceptions/otp_request_exception.dart';
export 'micro_area.dart';
export 'otp_challenge.dart';
export 'patient.dart';
export 'push_token.dart';
export 'triage_answer.dart';
export 'triage_session.dart';
export 'ubs.dart';
export 'user.dart';
export 'user_credential.dart';
export 'visit.dart';
export 'client.dart';

class Protocol extends _i1.SerializationManager {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._();

  static String? getClassNameFromObjectJson(dynamic data) {
    if (data is! Map) return null;
    final className = data['__className__'] as String?;
    return className;
  }

  @override
  T deserialize<T>(
    dynamic data, [
    Type? t,
  ]) {
    t ??= T;

    final dataClassName = getClassNameFromObjectJson(data);
    if (dataClassName != null && dataClassName != getClassNameForType(t)) {
      try {
        return deserializeByClassName({
          'className': dataClassName,
          'data': data,
        });
      } on FormatException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _i2.Acs) {
      return _i2.Acs.fromJson(data) as T;
    }
    if (t == _i3.Alert) {
      return _i3.Alert.fromJson(data) as T;
    }
    if (t == _i4.AlertDeliveryRecord) {
      return _i4.AlertDeliveryRecord.fromJson(data) as T;
    }
    if (t == _i5.AlertIdempotencyKey) {
      return _i5.AlertIdempotencyKey.fromJson(data) as T;
    }
    if (t == _i6.AlertOutboxEntry) {
      return _i6.AlertOutboxEntry.fromJson(data) as T;
    }
    if (t == _i7.AlertAckResult) {
      return _i7.AlertAckResult.fromJson(data) as T;
    }
    if (t == _i8.AlertStatusResult) {
      return _i8.AlertStatusResult.fromJson(data) as T;
    }
    if (t == _i9.DevelopmentLoginResult) {
      return _i9.DevelopmentLoginResult.fromJson(data) as T;
    }
    if (t == _i10.EnrollmentResult) {
      return _i10.EnrollmentResult.fromJson(data) as T;
    }
    if (t == _i11.EnrollmentTokenResult) {
      return _i11.EnrollmentTokenResult.fromJson(data) as T;
    }
    if (t == _i12.MicroAreaPatient) {
      return _i12.MicroAreaPatient.fromJson(data) as T;
    }
    if (t == _i13.NoticeSendResult) {
      return _i13.NoticeSendResult.fromJson(data) as T;
    }
    if (t == _i14.PatientConsentRecord) {
      return _i14.PatientConsentRecord.fromJson(data) as T;
    }
    if (t == _i15.PatientDataOverview) {
      return _i15.PatientDataOverview.fromJson(data) as T;
    }
    if (t == _i16.PatientDataSubjectRequestRecord) {
      return _i16.PatientDataSubjectRequestRecord.fromJson(data) as T;
    }
    if (t == _i17.PatientRiskEvent) {
      return _i17.PatientRiskEvent.fromJson(data) as T;
    }
    if (t == _i18.RedAlertResult) {
      return _i18.RedAlertResult.fromJson(data) as T;
    }
    if (t == _i19.ServiceHealth) {
      return _i19.ServiceHealth.fromJson(data) as T;
    }
    if (t == _i20.TermsChangeNotice) {
      return _i20.TermsChangeNotice.fromJson(data) as T;
    }
    if (t == _i21.TotpEnrollmentStart) {
      return _i21.TotpEnrollmentStart.fromJson(data) as T;
    }
    if (t == _i22.TriageResult) {
      return _i22.TriageResult.fromJson(data) as T;
    }
    if (t == _i23.UbsContact) {
      return _i23.UbsContact.fromJson(data) as T;
    }
    if (t == _i24.VisitSyncEntry) {
      return _i24.VisitSyncEntry.fromJson(data) as T;
    }
    if (t == _i25.VisitSyncResult) {
      return _i25.VisitSyncResult.fromJson(data) as T;
    }
    if (t == _i26.AuditLog) {
      return _i26.AuditLog.fromJson(data) as T;
    }
    if (t == _i27.ConsentLog) {
      return _i27.ConsentLog.fromJson(data) as T;
    }
    if (t == _i28.DataSubjectRequest) {
      return _i28.DataSubjectRequest.fromJson(data) as T;
    }
    if (t == _i29.EnrollmentToken) {
      return _i29.EnrollmentToken.fromJson(data) as T;
    }
    if (t == _i30.AlertStatus) {
      return _i30.AlertStatus.fromJson(data) as T;
    }
    if (t == _i31.ArrivalMethod) {
      return _i31.ArrivalMethod.fromJson(data) as T;
    }
    if (t == _i32.ConsentPurpose) {
      return _i32.ConsentPurpose.fromJson(data) as T;
    }
    if (t == _i33.DataSubjectRequestStatus) {
      return _i33.DataSubjectRequestStatus.fromJson(data) as T;
    }
    if (t == _i34.DataSubjectRequestType) {
      return _i34.DataSubjectRequestType.fromJson(data) as T;
    }
    if (t == _i35.RiskLevel) {
      return _i35.RiskLevel.fromJson(data) as T;
    }
    if (t == _i36.SyncStatus) {
      return _i36.SyncStatus.fromJson(data) as T;
    }
    if (t == _i37.UserRole) {
      return _i37.UserRole.fromJson(data) as T;
    }
    if (t == _i38.AlertDispatchUnavailableException) {
      return _i38.AlertDispatchUnavailableException.fromJson(data) as T;
    }
    if (t == _i39.AlertPermissionException) {
      return _i39.AlertPermissionException.fromJson(data) as T;
    }
    if (t == _i40.AlertValidationException) {
      return _i40.AlertValidationException.fromJson(data) as T;
    }
    if (t == _i41.AuthenticationFailedException) {
      return _i41.AuthenticationFailedException.fromJson(data) as T;
    }
    if (t == _i42.DataRightsException) {
      return _i42.DataRightsException.fromJson(data) as T;
    }
    if (t == _i43.EndpointDisabledException) {
      return _i43.EndpointDisabledException.fromJson(data) as T;
    }
    if (t == _i44.EnrollmentException) {
      return _i44.EnrollmentException.fromJson(data) as T;
    }
    if (t == _i45.MfaEnrollmentRequiredException) {
      return _i45.MfaEnrollmentRequiredException.fromJson(data) as T;
    }
    if (t == _i46.MfaRequiredException) {
      return _i46.MfaRequiredException.fromJson(data) as T;
    }
    if (t == _i47.NoticeDeliveryException) {
      return _i47.NoticeDeliveryException.fromJson(data) as T;
    }
    if (t == _i48.OtpRequestException) {
      return _i48.OtpRequestException.fromJson(data) as T;
    }
    if (t == _i49.MicroArea) {
      return _i49.MicroArea.fromJson(data) as T;
    }
    if (t == _i50.OtpChallenge) {
      return _i50.OtpChallenge.fromJson(data) as T;
    }
    if (t == _i51.Patient) {
      return _i51.Patient.fromJson(data) as T;
    }
    if (t == _i52.PushToken) {
      return _i52.PushToken.fromJson(data) as T;
    }
    if (t == _i53.TriageAnswer) {
      return _i53.TriageAnswer.fromJson(data) as T;
    }
    if (t == _i54.TriageSession) {
      return _i54.TriageSession.fromJson(data) as T;
    }
    if (t == _i55.Ubs) {
      return _i55.Ubs.fromJson(data) as T;
    }
    if (t == _i56.User) {
      return _i56.User.fromJson(data) as T;
    }
    if (t == _i57.UserCredential) {
      return _i57.UserCredential.fromJson(data) as T;
    }
    if (t == _i58.Visit) {
      return _i58.Visit.fromJson(data) as T;
    }
    if (t == _i1.getType<_i2.Acs?>()) {
      return (data != null ? _i2.Acs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i3.Alert?>()) {
      return (data != null ? _i3.Alert.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i4.AlertDeliveryRecord?>()) {
      return (data != null ? _i4.AlertDeliveryRecord.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i5.AlertIdempotencyKey?>()) {
      return (data != null ? _i5.AlertIdempotencyKey.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i6.AlertOutboxEntry?>()) {
      return (data != null ? _i6.AlertOutboxEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i7.AlertAckResult?>()) {
      return (data != null ? _i7.AlertAckResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i8.AlertStatusResult?>()) {
      return (data != null ? _i8.AlertStatusResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i9.DevelopmentLoginResult?>()) {
      return (data != null ? _i9.DevelopmentLoginResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i10.EnrollmentResult?>()) {
      return (data != null ? _i10.EnrollmentResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i11.EnrollmentTokenResult?>()) {
      return (data != null ? _i11.EnrollmentTokenResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i12.MicroAreaPatient?>()) {
      return (data != null ? _i12.MicroAreaPatient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i13.NoticeSendResult?>()) {
      return (data != null ? _i13.NoticeSendResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i14.PatientConsentRecord?>()) {
      return (data != null ? _i14.PatientConsentRecord.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i15.PatientDataOverview?>()) {
      return (data != null ? _i15.PatientDataOverview.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i16.PatientDataSubjectRequestRecord?>()) {
      return (data != null
              ? _i16.PatientDataSubjectRequestRecord.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i17.PatientRiskEvent?>()) {
      return (data != null ? _i17.PatientRiskEvent.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i18.RedAlertResult?>()) {
      return (data != null ? _i18.RedAlertResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i19.ServiceHealth?>()) {
      return (data != null ? _i19.ServiceHealth.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i20.TermsChangeNotice?>()) {
      return (data != null ? _i20.TermsChangeNotice.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i21.TotpEnrollmentStart?>()) {
      return (data != null ? _i21.TotpEnrollmentStart.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i22.TriageResult?>()) {
      return (data != null ? _i22.TriageResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i23.UbsContact?>()) {
      return (data != null ? _i23.UbsContact.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i24.VisitSyncEntry?>()) {
      return (data != null ? _i24.VisitSyncEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i25.VisitSyncResult?>()) {
      return (data != null ? _i25.VisitSyncResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i26.AuditLog?>()) {
      return (data != null ? _i26.AuditLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i27.ConsentLog?>()) {
      return (data != null ? _i27.ConsentLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i28.DataSubjectRequest?>()) {
      return (data != null ? _i28.DataSubjectRequest.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i29.EnrollmentToken?>()) {
      return (data != null ? _i29.EnrollmentToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i30.AlertStatus?>()) {
      return (data != null ? _i30.AlertStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i31.ArrivalMethod?>()) {
      return (data != null ? _i31.ArrivalMethod.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i32.ConsentPurpose?>()) {
      return (data != null ? _i32.ConsentPurpose.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i33.DataSubjectRequestStatus?>()) {
      return (data != null
              ? _i33.DataSubjectRequestStatus.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i34.DataSubjectRequestType?>()) {
      return (data != null ? _i34.DataSubjectRequestType.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i35.RiskLevel?>()) {
      return (data != null ? _i35.RiskLevel.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i36.SyncStatus?>()) {
      return (data != null ? _i36.SyncStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i37.UserRole?>()) {
      return (data != null ? _i37.UserRole.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i38.AlertDispatchUnavailableException?>()) {
      return (data != null
              ? _i38.AlertDispatchUnavailableException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i39.AlertPermissionException?>()) {
      return (data != null
              ? _i39.AlertPermissionException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i40.AlertValidationException?>()) {
      return (data != null
              ? _i40.AlertValidationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i41.AuthenticationFailedException?>()) {
      return (data != null
              ? _i41.AuthenticationFailedException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i42.DataRightsException?>()) {
      return (data != null ? _i42.DataRightsException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i43.EndpointDisabledException?>()) {
      return (data != null
              ? _i43.EndpointDisabledException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i44.EnrollmentException?>()) {
      return (data != null ? _i44.EnrollmentException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i45.MfaEnrollmentRequiredException?>()) {
      return (data != null
              ? _i45.MfaEnrollmentRequiredException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i46.MfaRequiredException?>()) {
      return (data != null ? _i46.MfaRequiredException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i47.NoticeDeliveryException?>()) {
      return (data != null ? _i47.NoticeDeliveryException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i48.OtpRequestException?>()) {
      return (data != null ? _i48.OtpRequestException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i49.MicroArea?>()) {
      return (data != null ? _i49.MicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i50.OtpChallenge?>()) {
      return (data != null ? _i50.OtpChallenge.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i51.Patient?>()) {
      return (data != null ? _i51.Patient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i52.PushToken?>()) {
      return (data != null ? _i52.PushToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i53.TriageAnswer?>()) {
      return (data != null ? _i53.TriageAnswer.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i54.TriageSession?>()) {
      return (data != null ? _i54.TriageSession.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i55.Ubs?>()) {
      return (data != null ? _i55.Ubs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i56.User?>()) {
      return (data != null ? _i56.User.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i57.UserCredential?>()) {
      return (data != null ? _i57.UserCredential.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i58.Visit?>()) {
      return (data != null ? _i58.Visit.fromJson(data) : null) as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i14.PatientConsentRecord>) {
      return (data as List)
              .map((e) => deserialize<_i14.PatientConsentRecord>(e))
              .toList()
          as T;
    }
    if (t == List<_i17.PatientRiskEvent>) {
      return (data as List)
              .map((e) => deserialize<_i17.PatientRiskEvent>(e))
              .toList()
          as T;
    }
    if (t == List<_i16.PatientDataSubjectRequestRecord>) {
      return (data as List)
              .map((e) => deserialize<_i16.PatientDataSubjectRequestRecord>(e))
              .toList()
          as T;
    }
    if (t == Map<String, String>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<String>(v)),
          )
          as T;
    }
    if (t == List<_i59.MicroAreaPatient>) {
      return (data as List)
              .map((e) => deserialize<_i59.MicroAreaPatient>(e))
              .toList()
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i60.VisitSyncResult>) {
      return (data as List)
              .map((e) => deserialize<_i60.VisitSyncResult>(e))
              .toList()
          as T;
    }
    if (t == List<_i61.VisitSyncEntry>) {
      return (data as List)
              .map((e) => deserialize<_i61.VisitSyncEntry>(e))
              .toList()
          as T;
    }
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _i2.Acs => 'Acs',
      _i3.Alert => 'Alert',
      _i4.AlertDeliveryRecord => 'AlertDeliveryRecord',
      _i5.AlertIdempotencyKey => 'AlertIdempotencyKey',
      _i6.AlertOutboxEntry => 'AlertOutboxEntry',
      _i7.AlertAckResult => 'AlertAckResult',
      _i8.AlertStatusResult => 'AlertStatusResult',
      _i9.DevelopmentLoginResult => 'DevelopmentLoginResult',
      _i10.EnrollmentResult => 'EnrollmentResult',
      _i11.EnrollmentTokenResult => 'EnrollmentTokenResult',
      _i12.MicroAreaPatient => 'MicroAreaPatient',
      _i13.NoticeSendResult => 'NoticeSendResult',
      _i14.PatientConsentRecord => 'PatientConsentRecord',
      _i15.PatientDataOverview => 'PatientDataOverview',
      _i16.PatientDataSubjectRequestRecord => 'PatientDataSubjectRequestRecord',
      _i17.PatientRiskEvent => 'PatientRiskEvent',
      _i18.RedAlertResult => 'RedAlertResult',
      _i19.ServiceHealth => 'ServiceHealth',
      _i20.TermsChangeNotice => 'TermsChangeNotice',
      _i21.TotpEnrollmentStart => 'TotpEnrollmentStart',
      _i22.TriageResult => 'TriageResult',
      _i23.UbsContact => 'UbsContact',
      _i24.VisitSyncEntry => 'VisitSyncEntry',
      _i25.VisitSyncResult => 'VisitSyncResult',
      _i26.AuditLog => 'AuditLog',
      _i27.ConsentLog => 'ConsentLog',
      _i28.DataSubjectRequest => 'DataSubjectRequest',
      _i29.EnrollmentToken => 'EnrollmentToken',
      _i30.AlertStatus => 'AlertStatus',
      _i31.ArrivalMethod => 'ArrivalMethod',
      _i32.ConsentPurpose => 'ConsentPurpose',
      _i33.DataSubjectRequestStatus => 'DataSubjectRequestStatus',
      _i34.DataSubjectRequestType => 'DataSubjectRequestType',
      _i35.RiskLevel => 'RiskLevel',
      _i36.SyncStatus => 'SyncStatus',
      _i37.UserRole => 'UserRole',
      _i38.AlertDispatchUnavailableException =>
        'AlertDispatchUnavailableException',
      _i39.AlertPermissionException => 'AlertPermissionException',
      _i40.AlertValidationException => 'AlertValidationException',
      _i41.AuthenticationFailedException => 'AuthenticationFailedException',
      _i42.DataRightsException => 'DataRightsException',
      _i43.EndpointDisabledException => 'EndpointDisabledException',
      _i44.EnrollmentException => 'EnrollmentException',
      _i45.MfaEnrollmentRequiredException => 'MfaEnrollmentRequiredException',
      _i46.MfaRequiredException => 'MfaRequiredException',
      _i47.NoticeDeliveryException => 'NoticeDeliveryException',
      _i48.OtpRequestException => 'OtpRequestException',
      _i49.MicroArea => 'MicroArea',
      _i50.OtpChallenge => 'OtpChallenge',
      _i51.Patient => 'Patient',
      _i52.PushToken => 'PushToken',
      _i53.TriageAnswer => 'TriageAnswer',
      _i54.TriageSession => 'TriageSession',
      _i55.Ubs => 'Ubs',
      _i56.User => 'User',
      _i57.UserCredential => 'UserCredential',
      _i58.Visit => 'Visit',
      _ => null,
    };
  }

  @override
  String? getClassNameForObject(Object? data) {
    String? className = super.getClassNameForObject(data);
    if (className != null) return className;

    if (data is Map<String, dynamic> && data['__className__'] is String) {
      return (data['__className__'] as String).replaceFirst('sinalacs.', '');
    }

    switch (data) {
      case _i2.Acs():
        return 'Acs';
      case _i3.Alert():
        return 'Alert';
      case _i4.AlertDeliveryRecord():
        return 'AlertDeliveryRecord';
      case _i5.AlertIdempotencyKey():
        return 'AlertIdempotencyKey';
      case _i6.AlertOutboxEntry():
        return 'AlertOutboxEntry';
      case _i7.AlertAckResult():
        return 'AlertAckResult';
      case _i8.AlertStatusResult():
        return 'AlertStatusResult';
      case _i9.DevelopmentLoginResult():
        return 'DevelopmentLoginResult';
      case _i10.EnrollmentResult():
        return 'EnrollmentResult';
      case _i11.EnrollmentTokenResult():
        return 'EnrollmentTokenResult';
      case _i12.MicroAreaPatient():
        return 'MicroAreaPatient';
      case _i13.NoticeSendResult():
        return 'NoticeSendResult';
      case _i14.PatientConsentRecord():
        return 'PatientConsentRecord';
      case _i15.PatientDataOverview():
        return 'PatientDataOverview';
      case _i16.PatientDataSubjectRequestRecord():
        return 'PatientDataSubjectRequestRecord';
      case _i17.PatientRiskEvent():
        return 'PatientRiskEvent';
      case _i18.RedAlertResult():
        return 'RedAlertResult';
      case _i19.ServiceHealth():
        return 'ServiceHealth';
      case _i20.TermsChangeNotice():
        return 'TermsChangeNotice';
      case _i21.TotpEnrollmentStart():
        return 'TotpEnrollmentStart';
      case _i22.TriageResult():
        return 'TriageResult';
      case _i23.UbsContact():
        return 'UbsContact';
      case _i24.VisitSyncEntry():
        return 'VisitSyncEntry';
      case _i25.VisitSyncResult():
        return 'VisitSyncResult';
      case _i26.AuditLog():
        return 'AuditLog';
      case _i27.ConsentLog():
        return 'ConsentLog';
      case _i28.DataSubjectRequest():
        return 'DataSubjectRequest';
      case _i29.EnrollmentToken():
        return 'EnrollmentToken';
      case _i30.AlertStatus():
        return 'AlertStatus';
      case _i31.ArrivalMethod():
        return 'ArrivalMethod';
      case _i32.ConsentPurpose():
        return 'ConsentPurpose';
      case _i33.DataSubjectRequestStatus():
        return 'DataSubjectRequestStatus';
      case _i34.DataSubjectRequestType():
        return 'DataSubjectRequestType';
      case _i35.RiskLevel():
        return 'RiskLevel';
      case _i36.SyncStatus():
        return 'SyncStatus';
      case _i37.UserRole():
        return 'UserRole';
      case _i38.AlertDispatchUnavailableException():
        return 'AlertDispatchUnavailableException';
      case _i39.AlertPermissionException():
        return 'AlertPermissionException';
      case _i40.AlertValidationException():
        return 'AlertValidationException';
      case _i41.AuthenticationFailedException():
        return 'AuthenticationFailedException';
      case _i42.DataRightsException():
        return 'DataRightsException';
      case _i43.EndpointDisabledException():
        return 'EndpointDisabledException';
      case _i44.EnrollmentException():
        return 'EnrollmentException';
      case _i45.MfaEnrollmentRequiredException():
        return 'MfaEnrollmentRequiredException';
      case _i46.MfaRequiredException():
        return 'MfaRequiredException';
      case _i47.NoticeDeliveryException():
        return 'NoticeDeliveryException';
      case _i48.OtpRequestException():
        return 'OtpRequestException';
      case _i49.MicroArea():
        return 'MicroArea';
      case _i50.OtpChallenge():
        return 'OtpChallenge';
      case _i51.Patient():
        return 'Patient';
      case _i52.PushToken():
        return 'PushToken';
      case _i53.TriageAnswer():
        return 'TriageAnswer';
      case _i54.TriageSession():
        return 'TriageSession';
      case _i55.Ubs():
        return 'Ubs';
      case _i56.User():
        return 'User';
      case _i57.UserCredential():
        return 'UserCredential';
      case _i58.Visit():
        return 'Visit';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'Acs') {
      return deserialize<_i2.Acs>(data['data']);
    }
    if (dataClassName == 'Alert') {
      return deserialize<_i3.Alert>(data['data']);
    }
    if (dataClassName == 'AlertDeliveryRecord') {
      return deserialize<_i4.AlertDeliveryRecord>(data['data']);
    }
    if (dataClassName == 'AlertIdempotencyKey') {
      return deserialize<_i5.AlertIdempotencyKey>(data['data']);
    }
    if (dataClassName == 'AlertOutboxEntry') {
      return deserialize<_i6.AlertOutboxEntry>(data['data']);
    }
    if (dataClassName == 'AlertAckResult') {
      return deserialize<_i7.AlertAckResult>(data['data']);
    }
    if (dataClassName == 'AlertStatusResult') {
      return deserialize<_i8.AlertStatusResult>(data['data']);
    }
    if (dataClassName == 'DevelopmentLoginResult') {
      return deserialize<_i9.DevelopmentLoginResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentResult') {
      return deserialize<_i10.EnrollmentResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentTokenResult') {
      return deserialize<_i11.EnrollmentTokenResult>(data['data']);
    }
    if (dataClassName == 'MicroAreaPatient') {
      return deserialize<_i12.MicroAreaPatient>(data['data']);
    }
    if (dataClassName == 'NoticeSendResult') {
      return deserialize<_i13.NoticeSendResult>(data['data']);
    }
    if (dataClassName == 'PatientConsentRecord') {
      return deserialize<_i14.PatientConsentRecord>(data['data']);
    }
    if (dataClassName == 'PatientDataOverview') {
      return deserialize<_i15.PatientDataOverview>(data['data']);
    }
    if (dataClassName == 'PatientDataSubjectRequestRecord') {
      return deserialize<_i16.PatientDataSubjectRequestRecord>(data['data']);
    }
    if (dataClassName == 'PatientRiskEvent') {
      return deserialize<_i17.PatientRiskEvent>(data['data']);
    }
    if (dataClassName == 'RedAlertResult') {
      return deserialize<_i18.RedAlertResult>(data['data']);
    }
    if (dataClassName == 'ServiceHealth') {
      return deserialize<_i19.ServiceHealth>(data['data']);
    }
    if (dataClassName == 'TermsChangeNotice') {
      return deserialize<_i20.TermsChangeNotice>(data['data']);
    }
    if (dataClassName == 'TotpEnrollmentStart') {
      return deserialize<_i21.TotpEnrollmentStart>(data['data']);
    }
    if (dataClassName == 'TriageResult') {
      return deserialize<_i22.TriageResult>(data['data']);
    }
    if (dataClassName == 'UbsContact') {
      return deserialize<_i23.UbsContact>(data['data']);
    }
    if (dataClassName == 'VisitSyncEntry') {
      return deserialize<_i24.VisitSyncEntry>(data['data']);
    }
    if (dataClassName == 'VisitSyncResult') {
      return deserialize<_i25.VisitSyncResult>(data['data']);
    }
    if (dataClassName == 'AuditLog') {
      return deserialize<_i26.AuditLog>(data['data']);
    }
    if (dataClassName == 'ConsentLog') {
      return deserialize<_i27.ConsentLog>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequest') {
      return deserialize<_i28.DataSubjectRequest>(data['data']);
    }
    if (dataClassName == 'EnrollmentToken') {
      return deserialize<_i29.EnrollmentToken>(data['data']);
    }
    if (dataClassName == 'AlertStatus') {
      return deserialize<_i30.AlertStatus>(data['data']);
    }
    if (dataClassName == 'ArrivalMethod') {
      return deserialize<_i31.ArrivalMethod>(data['data']);
    }
    if (dataClassName == 'ConsentPurpose') {
      return deserialize<_i32.ConsentPurpose>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestStatus') {
      return deserialize<_i33.DataSubjectRequestStatus>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestType') {
      return deserialize<_i34.DataSubjectRequestType>(data['data']);
    }
    if (dataClassName == 'RiskLevel') {
      return deserialize<_i35.RiskLevel>(data['data']);
    }
    if (dataClassName == 'SyncStatus') {
      return deserialize<_i36.SyncStatus>(data['data']);
    }
    if (dataClassName == 'UserRole') {
      return deserialize<_i37.UserRole>(data['data']);
    }
    if (dataClassName == 'AlertDispatchUnavailableException') {
      return deserialize<_i38.AlertDispatchUnavailableException>(data['data']);
    }
    if (dataClassName == 'AlertPermissionException') {
      return deserialize<_i39.AlertPermissionException>(data['data']);
    }
    if (dataClassName == 'AlertValidationException') {
      return deserialize<_i40.AlertValidationException>(data['data']);
    }
    if (dataClassName == 'AuthenticationFailedException') {
      return deserialize<_i41.AuthenticationFailedException>(data['data']);
    }
    if (dataClassName == 'DataRightsException') {
      return deserialize<_i42.DataRightsException>(data['data']);
    }
    if (dataClassName == 'EndpointDisabledException') {
      return deserialize<_i43.EndpointDisabledException>(data['data']);
    }
    if (dataClassName == 'EnrollmentException') {
      return deserialize<_i44.EnrollmentException>(data['data']);
    }
    if (dataClassName == 'MfaEnrollmentRequiredException') {
      return deserialize<_i45.MfaEnrollmentRequiredException>(data['data']);
    }
    if (dataClassName == 'MfaRequiredException') {
      return deserialize<_i46.MfaRequiredException>(data['data']);
    }
    if (dataClassName == 'NoticeDeliveryException') {
      return deserialize<_i47.NoticeDeliveryException>(data['data']);
    }
    if (dataClassName == 'OtpRequestException') {
      return deserialize<_i48.OtpRequestException>(data['data']);
    }
    if (dataClassName == 'MicroArea') {
      return deserialize<_i49.MicroArea>(data['data']);
    }
    if (dataClassName == 'OtpChallenge') {
      return deserialize<_i50.OtpChallenge>(data['data']);
    }
    if (dataClassName == 'Patient') {
      return deserialize<_i51.Patient>(data['data']);
    }
    if (dataClassName == 'PushToken') {
      return deserialize<_i52.PushToken>(data['data']);
    }
    if (dataClassName == 'TriageAnswer') {
      return deserialize<_i53.TriageAnswer>(data['data']);
    }
    if (dataClassName == 'TriageSession') {
      return deserialize<_i54.TriageSession>(data['data']);
    }
    if (dataClassName == 'Ubs') {
      return deserialize<_i55.Ubs>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i56.User>(data['data']);
    }
    if (dataClassName == 'UserCredential') {
      return deserialize<_i57.UserCredential>(data['data']);
    }
    if (dataClassName == 'Visit') {
      return deserialize<_i58.Visit>(data['data']);
    }
    return super.deserializeByClassName(data);
  }

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
