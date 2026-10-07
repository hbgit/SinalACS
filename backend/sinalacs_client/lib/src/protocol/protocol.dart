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
import 'acs_refresh_token.dart' as _i3;
import 'acs_upload_token.dart' as _i4;
import 'alert.dart' as _i5;
import 'alert_delivery_record.dart' as _i6;
import 'alert_idempotency_key.dart' as _i7;
import 'alert_outbox_entry.dart' as _i8;
import 'api/admin_alert.dart' as _i9;
import 'api/admin_alert_page.dart' as _i10;
import 'api/admin_audit_entry.dart' as _i11;
import 'api/admin_audit_page.dart' as _i12;
import 'api/admin_indicators.dart' as _i13;
import 'api/admin_micro_area.dart' as _i14;
import 'api/alert_ack_result.dart' as _i15;
import 'api/alert_status_result.dart' as _i16;
import 'api/development_login_result.dart' as _i17;
import 'api/enrollment_result.dart' as _i18;
import 'api/enrollment_token_result.dart' as _i19;
import 'api/micro_area_patient.dart' as _i20;
import 'api/notice_send_result.dart' as _i21;
import 'api/patient_consent_record.dart' as _i22;
import 'api/patient_data_overview.dart' as _i23;
import 'api/patient_data_subject_request_record.dart' as _i24;
import 'api/patient_risk_event.dart' as _i25;
import 'api/red_alert_result.dart' as _i26;
import 'api/service_health.dart' as _i27;
import 'api/terms_change_notice.dart' as _i28;
import 'api/totp_enrollment_start.dart' as _i29;
import 'api/triage_result.dart' as _i30;
import 'api/ubs_contact.dart' as _i31;
import 'api/visit_sync_entry.dart' as _i32;
import 'api/visit_sync_result.dart' as _i33;
import 'audit_log.dart' as _i34;
import 'consent_log.dart' as _i35;
import 'data_subject_request.dart' as _i36;
import 'enrollment_token.dart' as _i37;
import 'enums/alert_status.dart' as _i38;
import 'enums/arrival_method.dart' as _i39;
import 'enums/consent_purpose.dart' as _i40;
import 'enums/data_subject_request_status.dart' as _i41;
import 'enums/data_subject_request_type.dart' as _i42;
import 'enums/risk_level.dart' as _i43;
import 'enums/sync_status.dart' as _i44;
import 'enums/user_role.dart' as _i45;
import 'enums/visit_authorship.dart' as _i46;
import 'exceptions/admin_invalid_request_exception.dart' as _i47;
import 'exceptions/alert_dispatch_unavailable_exception.dart' as _i48;
import 'exceptions/alert_permission_exception.dart' as _i49;
import 'exceptions/alert_validation_exception.dart' as _i50;
import 'exceptions/authentication_failed_exception.dart' as _i51;
import 'exceptions/data_rights_exception.dart' as _i52;
import 'exceptions/endpoint_disabled_exception.dart' as _i53;
import 'exceptions/enrollment_exception.dart' as _i54;
import 'exceptions/mfa_enrollment_required_exception.dart' as _i55;
import 'exceptions/mfa_required_exception.dart' as _i56;
import 'exceptions/notice_delivery_exception.dart' as _i57;
import 'exceptions/otp_request_exception.dart' as _i58;
import 'exceptions/session_expired_exception.dart' as _i59;
import 'micro_area.dart' as _i60;
import 'otp_challenge.dart' as _i61;
import 'patient.dart' as _i62;
import 'push_token.dart' as _i63;
import 'staff_account.dart' as _i64;
import 'triage_answer.dart' as _i65;
import 'triage_session.dart' as _i66;
import 'ubs.dart' as _i67;
import 'user.dart' as _i68;
import 'user_credential.dart' as _i69;
import 'visit.dart' as _i70;
import 'package:sinalacs_client/src/protocol/api/micro_area_patient.dart'
    as _i71;
import 'package:sinalacs_client/src/protocol/api/visit_sync_result.dart'
    as _i72;
import 'package:sinalacs_client/src/protocol/api/visit_sync_entry.dart' as _i73;
export 'acs.dart';
export 'acs_refresh_token.dart';
export 'acs_upload_token.dart';
export 'alert.dart';
export 'alert_delivery_record.dart';
export 'alert_idempotency_key.dart';
export 'alert_outbox_entry.dart';
export 'api/admin_alert.dart';
export 'api/admin_alert_page.dart';
export 'api/admin_audit_entry.dart';
export 'api/admin_audit_page.dart';
export 'api/admin_indicators.dart';
export 'api/admin_micro_area.dart';
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
export 'enums/visit_authorship.dart';
export 'exceptions/admin_invalid_request_exception.dart';
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
export 'exceptions/session_expired_exception.dart';
export 'micro_area.dart';
export 'otp_challenge.dart';
export 'patient.dart';
export 'push_token.dart';
export 'staff_account.dart';
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
    if (t == _i3.AcsRefreshToken) {
      return _i3.AcsRefreshToken.fromJson(data) as T;
    }
    if (t == _i4.AcsUploadToken) {
      return _i4.AcsUploadToken.fromJson(data) as T;
    }
    if (t == _i5.Alert) {
      return _i5.Alert.fromJson(data) as T;
    }
    if (t == _i6.AlertDeliveryRecord) {
      return _i6.AlertDeliveryRecord.fromJson(data) as T;
    }
    if (t == _i7.AlertIdempotencyKey) {
      return _i7.AlertIdempotencyKey.fromJson(data) as T;
    }
    if (t == _i8.AlertOutboxEntry) {
      return _i8.AlertOutboxEntry.fromJson(data) as T;
    }
    if (t == _i9.AdminAlert) {
      return _i9.AdminAlert.fromJson(data) as T;
    }
    if (t == _i10.AdminAlertPage) {
      return _i10.AdminAlertPage.fromJson(data) as T;
    }
    if (t == _i11.AdminAuditEntry) {
      return _i11.AdminAuditEntry.fromJson(data) as T;
    }
    if (t == _i12.AdminAuditPage) {
      return _i12.AdminAuditPage.fromJson(data) as T;
    }
    if (t == _i13.AdminIndicators) {
      return _i13.AdminIndicators.fromJson(data) as T;
    }
    if (t == _i14.AdminMicroArea) {
      return _i14.AdminMicroArea.fromJson(data) as T;
    }
    if (t == _i15.AlertAckResult) {
      return _i15.AlertAckResult.fromJson(data) as T;
    }
    if (t == _i16.AlertStatusResult) {
      return _i16.AlertStatusResult.fromJson(data) as T;
    }
    if (t == _i17.DevelopmentLoginResult) {
      return _i17.DevelopmentLoginResult.fromJson(data) as T;
    }
    if (t == _i18.EnrollmentResult) {
      return _i18.EnrollmentResult.fromJson(data) as T;
    }
    if (t == _i19.EnrollmentTokenResult) {
      return _i19.EnrollmentTokenResult.fromJson(data) as T;
    }
    if (t == _i20.MicroAreaPatient) {
      return _i20.MicroAreaPatient.fromJson(data) as T;
    }
    if (t == _i21.NoticeSendResult) {
      return _i21.NoticeSendResult.fromJson(data) as T;
    }
    if (t == _i22.PatientConsentRecord) {
      return _i22.PatientConsentRecord.fromJson(data) as T;
    }
    if (t == _i23.PatientDataOverview) {
      return _i23.PatientDataOverview.fromJson(data) as T;
    }
    if (t == _i24.PatientDataSubjectRequestRecord) {
      return _i24.PatientDataSubjectRequestRecord.fromJson(data) as T;
    }
    if (t == _i25.PatientRiskEvent) {
      return _i25.PatientRiskEvent.fromJson(data) as T;
    }
    if (t == _i26.RedAlertResult) {
      return _i26.RedAlertResult.fromJson(data) as T;
    }
    if (t == _i27.ServiceHealth) {
      return _i27.ServiceHealth.fromJson(data) as T;
    }
    if (t == _i28.TermsChangeNotice) {
      return _i28.TermsChangeNotice.fromJson(data) as T;
    }
    if (t == _i29.TotpEnrollmentStart) {
      return _i29.TotpEnrollmentStart.fromJson(data) as T;
    }
    if (t == _i30.TriageResult) {
      return _i30.TriageResult.fromJson(data) as T;
    }
    if (t == _i31.UbsContact) {
      return _i31.UbsContact.fromJson(data) as T;
    }
    if (t == _i32.VisitSyncEntry) {
      return _i32.VisitSyncEntry.fromJson(data) as T;
    }
    if (t == _i33.VisitSyncResult) {
      return _i33.VisitSyncResult.fromJson(data) as T;
    }
    if (t == _i34.AuditLog) {
      return _i34.AuditLog.fromJson(data) as T;
    }
    if (t == _i35.ConsentLog) {
      return _i35.ConsentLog.fromJson(data) as T;
    }
    if (t == _i36.DataSubjectRequest) {
      return _i36.DataSubjectRequest.fromJson(data) as T;
    }
    if (t == _i37.EnrollmentToken) {
      return _i37.EnrollmentToken.fromJson(data) as T;
    }
    if (t == _i38.AlertStatus) {
      return _i38.AlertStatus.fromJson(data) as T;
    }
    if (t == _i39.ArrivalMethod) {
      return _i39.ArrivalMethod.fromJson(data) as T;
    }
    if (t == _i40.ConsentPurpose) {
      return _i40.ConsentPurpose.fromJson(data) as T;
    }
    if (t == _i41.DataSubjectRequestStatus) {
      return _i41.DataSubjectRequestStatus.fromJson(data) as T;
    }
    if (t == _i42.DataSubjectRequestType) {
      return _i42.DataSubjectRequestType.fromJson(data) as T;
    }
    if (t == _i43.RiskLevel) {
      return _i43.RiskLevel.fromJson(data) as T;
    }
    if (t == _i44.SyncStatus) {
      return _i44.SyncStatus.fromJson(data) as T;
    }
    if (t == _i45.UserRole) {
      return _i45.UserRole.fromJson(data) as T;
    }
    if (t == _i46.VisitAuthorship) {
      return _i46.VisitAuthorship.fromJson(data) as T;
    }
    if (t == _i47.AdminInvalidRequestException) {
      return _i47.AdminInvalidRequestException.fromJson(data) as T;
    }
    if (t == _i48.AlertDispatchUnavailableException) {
      return _i48.AlertDispatchUnavailableException.fromJson(data) as T;
    }
    if (t == _i49.AlertPermissionException) {
      return _i49.AlertPermissionException.fromJson(data) as T;
    }
    if (t == _i50.AlertValidationException) {
      return _i50.AlertValidationException.fromJson(data) as T;
    }
    if (t == _i51.AuthenticationFailedException) {
      return _i51.AuthenticationFailedException.fromJson(data) as T;
    }
    if (t == _i52.DataRightsException) {
      return _i52.DataRightsException.fromJson(data) as T;
    }
    if (t == _i53.EndpointDisabledException) {
      return _i53.EndpointDisabledException.fromJson(data) as T;
    }
    if (t == _i54.EnrollmentException) {
      return _i54.EnrollmentException.fromJson(data) as T;
    }
    if (t == _i55.MfaEnrollmentRequiredException) {
      return _i55.MfaEnrollmentRequiredException.fromJson(data) as T;
    }
    if (t == _i56.MfaRequiredException) {
      return _i56.MfaRequiredException.fromJson(data) as T;
    }
    if (t == _i57.NoticeDeliveryException) {
      return _i57.NoticeDeliveryException.fromJson(data) as T;
    }
    if (t == _i58.OtpRequestException) {
      return _i58.OtpRequestException.fromJson(data) as T;
    }
    if (t == _i59.SessionExpiredException) {
      return _i59.SessionExpiredException.fromJson(data) as T;
    }
    if (t == _i60.MicroArea) {
      return _i60.MicroArea.fromJson(data) as T;
    }
    if (t == _i61.OtpChallenge) {
      return _i61.OtpChallenge.fromJson(data) as T;
    }
    if (t == _i62.Patient) {
      return _i62.Patient.fromJson(data) as T;
    }
    if (t == _i63.PushToken) {
      return _i63.PushToken.fromJson(data) as T;
    }
    if (t == _i64.StaffAccount) {
      return _i64.StaffAccount.fromJson(data) as T;
    }
    if (t == _i65.TriageAnswer) {
      return _i65.TriageAnswer.fromJson(data) as T;
    }
    if (t == _i66.TriageSession) {
      return _i66.TriageSession.fromJson(data) as T;
    }
    if (t == _i67.Ubs) {
      return _i67.Ubs.fromJson(data) as T;
    }
    if (t == _i68.User) {
      return _i68.User.fromJson(data) as T;
    }
    if (t == _i69.UserCredential) {
      return _i69.UserCredential.fromJson(data) as T;
    }
    if (t == _i70.Visit) {
      return _i70.Visit.fromJson(data) as T;
    }
    if (t == _i1.getType<_i2.Acs?>()) {
      return (data != null ? _i2.Acs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i3.AcsRefreshToken?>()) {
      return (data != null ? _i3.AcsRefreshToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i4.AcsUploadToken?>()) {
      return (data != null ? _i4.AcsUploadToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i5.Alert?>()) {
      return (data != null ? _i5.Alert.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i6.AlertDeliveryRecord?>()) {
      return (data != null ? _i6.AlertDeliveryRecord.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i7.AlertIdempotencyKey?>()) {
      return (data != null ? _i7.AlertIdempotencyKey.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i8.AlertOutboxEntry?>()) {
      return (data != null ? _i8.AlertOutboxEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i9.AdminAlert?>()) {
      return (data != null ? _i9.AdminAlert.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i10.AdminAlertPage?>()) {
      return (data != null ? _i10.AdminAlertPage.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i11.AdminAuditEntry?>()) {
      return (data != null ? _i11.AdminAuditEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i12.AdminAuditPage?>()) {
      return (data != null ? _i12.AdminAuditPage.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i13.AdminIndicators?>()) {
      return (data != null ? _i13.AdminIndicators.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i14.AdminMicroArea?>()) {
      return (data != null ? _i14.AdminMicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i15.AlertAckResult?>()) {
      return (data != null ? _i15.AlertAckResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i16.AlertStatusResult?>()) {
      return (data != null ? _i16.AlertStatusResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i17.DevelopmentLoginResult?>()) {
      return (data != null ? _i17.DevelopmentLoginResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i18.EnrollmentResult?>()) {
      return (data != null ? _i18.EnrollmentResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i19.EnrollmentTokenResult?>()) {
      return (data != null ? _i19.EnrollmentTokenResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i20.MicroAreaPatient?>()) {
      return (data != null ? _i20.MicroAreaPatient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i21.NoticeSendResult?>()) {
      return (data != null ? _i21.NoticeSendResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i22.PatientConsentRecord?>()) {
      return (data != null ? _i22.PatientConsentRecord.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i23.PatientDataOverview?>()) {
      return (data != null ? _i23.PatientDataOverview.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i24.PatientDataSubjectRequestRecord?>()) {
      return (data != null
              ? _i24.PatientDataSubjectRequestRecord.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i25.PatientRiskEvent?>()) {
      return (data != null ? _i25.PatientRiskEvent.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i26.RedAlertResult?>()) {
      return (data != null ? _i26.RedAlertResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i27.ServiceHealth?>()) {
      return (data != null ? _i27.ServiceHealth.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i28.TermsChangeNotice?>()) {
      return (data != null ? _i28.TermsChangeNotice.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i29.TotpEnrollmentStart?>()) {
      return (data != null ? _i29.TotpEnrollmentStart.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i30.TriageResult?>()) {
      return (data != null ? _i30.TriageResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i31.UbsContact?>()) {
      return (data != null ? _i31.UbsContact.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i32.VisitSyncEntry?>()) {
      return (data != null ? _i32.VisitSyncEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i33.VisitSyncResult?>()) {
      return (data != null ? _i33.VisitSyncResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i34.AuditLog?>()) {
      return (data != null ? _i34.AuditLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i35.ConsentLog?>()) {
      return (data != null ? _i35.ConsentLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i36.DataSubjectRequest?>()) {
      return (data != null ? _i36.DataSubjectRequest.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i37.EnrollmentToken?>()) {
      return (data != null ? _i37.EnrollmentToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i38.AlertStatus?>()) {
      return (data != null ? _i38.AlertStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i39.ArrivalMethod?>()) {
      return (data != null ? _i39.ArrivalMethod.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i40.ConsentPurpose?>()) {
      return (data != null ? _i40.ConsentPurpose.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i41.DataSubjectRequestStatus?>()) {
      return (data != null
              ? _i41.DataSubjectRequestStatus.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i42.DataSubjectRequestType?>()) {
      return (data != null ? _i42.DataSubjectRequestType.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i43.RiskLevel?>()) {
      return (data != null ? _i43.RiskLevel.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i44.SyncStatus?>()) {
      return (data != null ? _i44.SyncStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i45.UserRole?>()) {
      return (data != null ? _i45.UserRole.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i46.VisitAuthorship?>()) {
      return (data != null ? _i46.VisitAuthorship.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i47.AdminInvalidRequestException?>()) {
      return (data != null
              ? _i47.AdminInvalidRequestException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i48.AlertDispatchUnavailableException?>()) {
      return (data != null
              ? _i48.AlertDispatchUnavailableException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i49.AlertPermissionException?>()) {
      return (data != null
              ? _i49.AlertPermissionException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i50.AlertValidationException?>()) {
      return (data != null
              ? _i50.AlertValidationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i51.AuthenticationFailedException?>()) {
      return (data != null
              ? _i51.AuthenticationFailedException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i52.DataRightsException?>()) {
      return (data != null ? _i52.DataRightsException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i53.EndpointDisabledException?>()) {
      return (data != null
              ? _i53.EndpointDisabledException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i54.EnrollmentException?>()) {
      return (data != null ? _i54.EnrollmentException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i55.MfaEnrollmentRequiredException?>()) {
      return (data != null
              ? _i55.MfaEnrollmentRequiredException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i56.MfaRequiredException?>()) {
      return (data != null ? _i56.MfaRequiredException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i57.NoticeDeliveryException?>()) {
      return (data != null ? _i57.NoticeDeliveryException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i58.OtpRequestException?>()) {
      return (data != null ? _i58.OtpRequestException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i59.SessionExpiredException?>()) {
      return (data != null ? _i59.SessionExpiredException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i60.MicroArea?>()) {
      return (data != null ? _i60.MicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i61.OtpChallenge?>()) {
      return (data != null ? _i61.OtpChallenge.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i62.Patient?>()) {
      return (data != null ? _i62.Patient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i63.PushToken?>()) {
      return (data != null ? _i63.PushToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i64.StaffAccount?>()) {
      return (data != null ? _i64.StaffAccount.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i65.TriageAnswer?>()) {
      return (data != null ? _i65.TriageAnswer.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i66.TriageSession?>()) {
      return (data != null ? _i66.TriageSession.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i67.Ubs?>()) {
      return (data != null ? _i67.Ubs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i68.User?>()) {
      return (data != null ? _i68.User.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i69.UserCredential?>()) {
      return (data != null ? _i69.UserCredential.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i70.Visit?>()) {
      return (data != null ? _i70.Visit.fromJson(data) : null) as T;
    }
    if (t == List<_i9.AdminAlert>) {
      return (data as List).map((e) => deserialize<_i9.AdminAlert>(e)).toList()
          as T;
    }
    if (t == List<_i11.AdminAuditEntry>) {
      return (data as List)
              .map((e) => deserialize<_i11.AdminAuditEntry>(e))
              .toList()
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i22.PatientConsentRecord>) {
      return (data as List)
              .map((e) => deserialize<_i22.PatientConsentRecord>(e))
              .toList()
          as T;
    }
    if (t == List<_i25.PatientRiskEvent>) {
      return (data as List)
              .map((e) => deserialize<_i25.PatientRiskEvent>(e))
              .toList()
          as T;
    }
    if (t == List<_i24.PatientDataSubjectRequestRecord>) {
      return (data as List)
              .map((e) => deserialize<_i24.PatientDataSubjectRequestRecord>(e))
              .toList()
          as T;
    }
    if (t == Map<String, String>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<String>(v)),
          )
          as T;
    }
    if (t == List<_i71.MicroAreaPatient>) {
      return (data as List)
              .map((e) => deserialize<_i71.MicroAreaPatient>(e))
              .toList()
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i72.VisitSyncResult>) {
      return (data as List)
              .map((e) => deserialize<_i72.VisitSyncResult>(e))
              .toList()
          as T;
    }
    if (t == List<_i73.VisitSyncEntry>) {
      return (data as List)
              .map((e) => deserialize<_i73.VisitSyncEntry>(e))
              .toList()
          as T;
    }
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _i2.Acs => 'Acs',
      _i3.AcsRefreshToken => 'AcsRefreshToken',
      _i4.AcsUploadToken => 'AcsUploadToken',
      _i5.Alert => 'Alert',
      _i6.AlertDeliveryRecord => 'AlertDeliveryRecord',
      _i7.AlertIdempotencyKey => 'AlertIdempotencyKey',
      _i8.AlertOutboxEntry => 'AlertOutboxEntry',
      _i9.AdminAlert => 'AdminAlert',
      _i10.AdminAlertPage => 'AdminAlertPage',
      _i11.AdminAuditEntry => 'AdminAuditEntry',
      _i12.AdminAuditPage => 'AdminAuditPage',
      _i13.AdminIndicators => 'AdminIndicators',
      _i14.AdminMicroArea => 'AdminMicroArea',
      _i15.AlertAckResult => 'AlertAckResult',
      _i16.AlertStatusResult => 'AlertStatusResult',
      _i17.DevelopmentLoginResult => 'DevelopmentLoginResult',
      _i18.EnrollmentResult => 'EnrollmentResult',
      _i19.EnrollmentTokenResult => 'EnrollmentTokenResult',
      _i20.MicroAreaPatient => 'MicroAreaPatient',
      _i21.NoticeSendResult => 'NoticeSendResult',
      _i22.PatientConsentRecord => 'PatientConsentRecord',
      _i23.PatientDataOverview => 'PatientDataOverview',
      _i24.PatientDataSubjectRequestRecord => 'PatientDataSubjectRequestRecord',
      _i25.PatientRiskEvent => 'PatientRiskEvent',
      _i26.RedAlertResult => 'RedAlertResult',
      _i27.ServiceHealth => 'ServiceHealth',
      _i28.TermsChangeNotice => 'TermsChangeNotice',
      _i29.TotpEnrollmentStart => 'TotpEnrollmentStart',
      _i30.TriageResult => 'TriageResult',
      _i31.UbsContact => 'UbsContact',
      _i32.VisitSyncEntry => 'VisitSyncEntry',
      _i33.VisitSyncResult => 'VisitSyncResult',
      _i34.AuditLog => 'AuditLog',
      _i35.ConsentLog => 'ConsentLog',
      _i36.DataSubjectRequest => 'DataSubjectRequest',
      _i37.EnrollmentToken => 'EnrollmentToken',
      _i38.AlertStatus => 'AlertStatus',
      _i39.ArrivalMethod => 'ArrivalMethod',
      _i40.ConsentPurpose => 'ConsentPurpose',
      _i41.DataSubjectRequestStatus => 'DataSubjectRequestStatus',
      _i42.DataSubjectRequestType => 'DataSubjectRequestType',
      _i43.RiskLevel => 'RiskLevel',
      _i44.SyncStatus => 'SyncStatus',
      _i45.UserRole => 'UserRole',
      _i46.VisitAuthorship => 'VisitAuthorship',
      _i47.AdminInvalidRequestException => 'AdminInvalidRequestException',
      _i48.AlertDispatchUnavailableException =>
        'AlertDispatchUnavailableException',
      _i49.AlertPermissionException => 'AlertPermissionException',
      _i50.AlertValidationException => 'AlertValidationException',
      _i51.AuthenticationFailedException => 'AuthenticationFailedException',
      _i52.DataRightsException => 'DataRightsException',
      _i53.EndpointDisabledException => 'EndpointDisabledException',
      _i54.EnrollmentException => 'EnrollmentException',
      _i55.MfaEnrollmentRequiredException => 'MfaEnrollmentRequiredException',
      _i56.MfaRequiredException => 'MfaRequiredException',
      _i57.NoticeDeliveryException => 'NoticeDeliveryException',
      _i58.OtpRequestException => 'OtpRequestException',
      _i59.SessionExpiredException => 'SessionExpiredException',
      _i60.MicroArea => 'MicroArea',
      _i61.OtpChallenge => 'OtpChallenge',
      _i62.Patient => 'Patient',
      _i63.PushToken => 'PushToken',
      _i64.StaffAccount => 'StaffAccount',
      _i65.TriageAnswer => 'TriageAnswer',
      _i66.TriageSession => 'TriageSession',
      _i67.Ubs => 'Ubs',
      _i68.User => 'User',
      _i69.UserCredential => 'UserCredential',
      _i70.Visit => 'Visit',
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
      case _i3.AcsRefreshToken():
        return 'AcsRefreshToken';
      case _i4.AcsUploadToken():
        return 'AcsUploadToken';
      case _i5.Alert():
        return 'Alert';
      case _i6.AlertDeliveryRecord():
        return 'AlertDeliveryRecord';
      case _i7.AlertIdempotencyKey():
        return 'AlertIdempotencyKey';
      case _i8.AlertOutboxEntry():
        return 'AlertOutboxEntry';
      case _i9.AdminAlert():
        return 'AdminAlert';
      case _i10.AdminAlertPage():
        return 'AdminAlertPage';
      case _i11.AdminAuditEntry():
        return 'AdminAuditEntry';
      case _i12.AdminAuditPage():
        return 'AdminAuditPage';
      case _i13.AdminIndicators():
        return 'AdminIndicators';
      case _i14.AdminMicroArea():
        return 'AdminMicroArea';
      case _i15.AlertAckResult():
        return 'AlertAckResult';
      case _i16.AlertStatusResult():
        return 'AlertStatusResult';
      case _i17.DevelopmentLoginResult():
        return 'DevelopmentLoginResult';
      case _i18.EnrollmentResult():
        return 'EnrollmentResult';
      case _i19.EnrollmentTokenResult():
        return 'EnrollmentTokenResult';
      case _i20.MicroAreaPatient():
        return 'MicroAreaPatient';
      case _i21.NoticeSendResult():
        return 'NoticeSendResult';
      case _i22.PatientConsentRecord():
        return 'PatientConsentRecord';
      case _i23.PatientDataOverview():
        return 'PatientDataOverview';
      case _i24.PatientDataSubjectRequestRecord():
        return 'PatientDataSubjectRequestRecord';
      case _i25.PatientRiskEvent():
        return 'PatientRiskEvent';
      case _i26.RedAlertResult():
        return 'RedAlertResult';
      case _i27.ServiceHealth():
        return 'ServiceHealth';
      case _i28.TermsChangeNotice():
        return 'TermsChangeNotice';
      case _i29.TotpEnrollmentStart():
        return 'TotpEnrollmentStart';
      case _i30.TriageResult():
        return 'TriageResult';
      case _i31.UbsContact():
        return 'UbsContact';
      case _i32.VisitSyncEntry():
        return 'VisitSyncEntry';
      case _i33.VisitSyncResult():
        return 'VisitSyncResult';
      case _i34.AuditLog():
        return 'AuditLog';
      case _i35.ConsentLog():
        return 'ConsentLog';
      case _i36.DataSubjectRequest():
        return 'DataSubjectRequest';
      case _i37.EnrollmentToken():
        return 'EnrollmentToken';
      case _i38.AlertStatus():
        return 'AlertStatus';
      case _i39.ArrivalMethod():
        return 'ArrivalMethod';
      case _i40.ConsentPurpose():
        return 'ConsentPurpose';
      case _i41.DataSubjectRequestStatus():
        return 'DataSubjectRequestStatus';
      case _i42.DataSubjectRequestType():
        return 'DataSubjectRequestType';
      case _i43.RiskLevel():
        return 'RiskLevel';
      case _i44.SyncStatus():
        return 'SyncStatus';
      case _i45.UserRole():
        return 'UserRole';
      case _i46.VisitAuthorship():
        return 'VisitAuthorship';
      case _i47.AdminInvalidRequestException():
        return 'AdminInvalidRequestException';
      case _i48.AlertDispatchUnavailableException():
        return 'AlertDispatchUnavailableException';
      case _i49.AlertPermissionException():
        return 'AlertPermissionException';
      case _i50.AlertValidationException():
        return 'AlertValidationException';
      case _i51.AuthenticationFailedException():
        return 'AuthenticationFailedException';
      case _i52.DataRightsException():
        return 'DataRightsException';
      case _i53.EndpointDisabledException():
        return 'EndpointDisabledException';
      case _i54.EnrollmentException():
        return 'EnrollmentException';
      case _i55.MfaEnrollmentRequiredException():
        return 'MfaEnrollmentRequiredException';
      case _i56.MfaRequiredException():
        return 'MfaRequiredException';
      case _i57.NoticeDeliveryException():
        return 'NoticeDeliveryException';
      case _i58.OtpRequestException():
        return 'OtpRequestException';
      case _i59.SessionExpiredException():
        return 'SessionExpiredException';
      case _i60.MicroArea():
        return 'MicroArea';
      case _i61.OtpChallenge():
        return 'OtpChallenge';
      case _i62.Patient():
        return 'Patient';
      case _i63.PushToken():
        return 'PushToken';
      case _i64.StaffAccount():
        return 'StaffAccount';
      case _i65.TriageAnswer():
        return 'TriageAnswer';
      case _i66.TriageSession():
        return 'TriageSession';
      case _i67.Ubs():
        return 'Ubs';
      case _i68.User():
        return 'User';
      case _i69.UserCredential():
        return 'UserCredential';
      case _i70.Visit():
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
    if (dataClassName == 'AcsRefreshToken') {
      return deserialize<_i3.AcsRefreshToken>(data['data']);
    }
    if (dataClassName == 'AcsUploadToken') {
      return deserialize<_i4.AcsUploadToken>(data['data']);
    }
    if (dataClassName == 'Alert') {
      return deserialize<_i5.Alert>(data['data']);
    }
    if (dataClassName == 'AlertDeliveryRecord') {
      return deserialize<_i6.AlertDeliveryRecord>(data['data']);
    }
    if (dataClassName == 'AlertIdempotencyKey') {
      return deserialize<_i7.AlertIdempotencyKey>(data['data']);
    }
    if (dataClassName == 'AlertOutboxEntry') {
      return deserialize<_i8.AlertOutboxEntry>(data['data']);
    }
    if (dataClassName == 'AdminAlert') {
      return deserialize<_i9.AdminAlert>(data['data']);
    }
    if (dataClassName == 'AdminAlertPage') {
      return deserialize<_i10.AdminAlertPage>(data['data']);
    }
    if (dataClassName == 'AdminAuditEntry') {
      return deserialize<_i11.AdminAuditEntry>(data['data']);
    }
    if (dataClassName == 'AdminAuditPage') {
      return deserialize<_i12.AdminAuditPage>(data['data']);
    }
    if (dataClassName == 'AdminIndicators') {
      return deserialize<_i13.AdminIndicators>(data['data']);
    }
    if (dataClassName == 'AdminMicroArea') {
      return deserialize<_i14.AdminMicroArea>(data['data']);
    }
    if (dataClassName == 'AlertAckResult') {
      return deserialize<_i15.AlertAckResult>(data['data']);
    }
    if (dataClassName == 'AlertStatusResult') {
      return deserialize<_i16.AlertStatusResult>(data['data']);
    }
    if (dataClassName == 'DevelopmentLoginResult') {
      return deserialize<_i17.DevelopmentLoginResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentResult') {
      return deserialize<_i18.EnrollmentResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentTokenResult') {
      return deserialize<_i19.EnrollmentTokenResult>(data['data']);
    }
    if (dataClassName == 'MicroAreaPatient') {
      return deserialize<_i20.MicroAreaPatient>(data['data']);
    }
    if (dataClassName == 'NoticeSendResult') {
      return deserialize<_i21.NoticeSendResult>(data['data']);
    }
    if (dataClassName == 'PatientConsentRecord') {
      return deserialize<_i22.PatientConsentRecord>(data['data']);
    }
    if (dataClassName == 'PatientDataOverview') {
      return deserialize<_i23.PatientDataOverview>(data['data']);
    }
    if (dataClassName == 'PatientDataSubjectRequestRecord') {
      return deserialize<_i24.PatientDataSubjectRequestRecord>(data['data']);
    }
    if (dataClassName == 'PatientRiskEvent') {
      return deserialize<_i25.PatientRiskEvent>(data['data']);
    }
    if (dataClassName == 'RedAlertResult') {
      return deserialize<_i26.RedAlertResult>(data['data']);
    }
    if (dataClassName == 'ServiceHealth') {
      return deserialize<_i27.ServiceHealth>(data['data']);
    }
    if (dataClassName == 'TermsChangeNotice') {
      return deserialize<_i28.TermsChangeNotice>(data['data']);
    }
    if (dataClassName == 'TotpEnrollmentStart') {
      return deserialize<_i29.TotpEnrollmentStart>(data['data']);
    }
    if (dataClassName == 'TriageResult') {
      return deserialize<_i30.TriageResult>(data['data']);
    }
    if (dataClassName == 'UbsContact') {
      return deserialize<_i31.UbsContact>(data['data']);
    }
    if (dataClassName == 'VisitSyncEntry') {
      return deserialize<_i32.VisitSyncEntry>(data['data']);
    }
    if (dataClassName == 'VisitSyncResult') {
      return deserialize<_i33.VisitSyncResult>(data['data']);
    }
    if (dataClassName == 'AuditLog') {
      return deserialize<_i34.AuditLog>(data['data']);
    }
    if (dataClassName == 'ConsentLog') {
      return deserialize<_i35.ConsentLog>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequest') {
      return deserialize<_i36.DataSubjectRequest>(data['data']);
    }
    if (dataClassName == 'EnrollmentToken') {
      return deserialize<_i37.EnrollmentToken>(data['data']);
    }
    if (dataClassName == 'AlertStatus') {
      return deserialize<_i38.AlertStatus>(data['data']);
    }
    if (dataClassName == 'ArrivalMethod') {
      return deserialize<_i39.ArrivalMethod>(data['data']);
    }
    if (dataClassName == 'ConsentPurpose') {
      return deserialize<_i40.ConsentPurpose>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestStatus') {
      return deserialize<_i41.DataSubjectRequestStatus>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestType') {
      return deserialize<_i42.DataSubjectRequestType>(data['data']);
    }
    if (dataClassName == 'RiskLevel') {
      return deserialize<_i43.RiskLevel>(data['data']);
    }
    if (dataClassName == 'SyncStatus') {
      return deserialize<_i44.SyncStatus>(data['data']);
    }
    if (dataClassName == 'UserRole') {
      return deserialize<_i45.UserRole>(data['data']);
    }
    if (dataClassName == 'VisitAuthorship') {
      return deserialize<_i46.VisitAuthorship>(data['data']);
    }
    if (dataClassName == 'AdminInvalidRequestException') {
      return deserialize<_i47.AdminInvalidRequestException>(data['data']);
    }
    if (dataClassName == 'AlertDispatchUnavailableException') {
      return deserialize<_i48.AlertDispatchUnavailableException>(data['data']);
    }
    if (dataClassName == 'AlertPermissionException') {
      return deserialize<_i49.AlertPermissionException>(data['data']);
    }
    if (dataClassName == 'AlertValidationException') {
      return deserialize<_i50.AlertValidationException>(data['data']);
    }
    if (dataClassName == 'AuthenticationFailedException') {
      return deserialize<_i51.AuthenticationFailedException>(data['data']);
    }
    if (dataClassName == 'DataRightsException') {
      return deserialize<_i52.DataRightsException>(data['data']);
    }
    if (dataClassName == 'EndpointDisabledException') {
      return deserialize<_i53.EndpointDisabledException>(data['data']);
    }
    if (dataClassName == 'EnrollmentException') {
      return deserialize<_i54.EnrollmentException>(data['data']);
    }
    if (dataClassName == 'MfaEnrollmentRequiredException') {
      return deserialize<_i55.MfaEnrollmentRequiredException>(data['data']);
    }
    if (dataClassName == 'MfaRequiredException') {
      return deserialize<_i56.MfaRequiredException>(data['data']);
    }
    if (dataClassName == 'NoticeDeliveryException') {
      return deserialize<_i57.NoticeDeliveryException>(data['data']);
    }
    if (dataClassName == 'OtpRequestException') {
      return deserialize<_i58.OtpRequestException>(data['data']);
    }
    if (dataClassName == 'SessionExpiredException') {
      return deserialize<_i59.SessionExpiredException>(data['data']);
    }
    if (dataClassName == 'MicroArea') {
      return deserialize<_i60.MicroArea>(data['data']);
    }
    if (dataClassName == 'OtpChallenge') {
      return deserialize<_i61.OtpChallenge>(data['data']);
    }
    if (dataClassName == 'Patient') {
      return deserialize<_i62.Patient>(data['data']);
    }
    if (dataClassName == 'PushToken') {
      return deserialize<_i63.PushToken>(data['data']);
    }
    if (dataClassName == 'StaffAccount') {
      return deserialize<_i64.StaffAccount>(data['data']);
    }
    if (dataClassName == 'TriageAnswer') {
      return deserialize<_i65.TriageAnswer>(data['data']);
    }
    if (dataClassName == 'TriageSession') {
      return deserialize<_i66.TriageSession>(data['data']);
    }
    if (dataClassName == 'Ubs') {
      return deserialize<_i67.Ubs>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i68.User>(data['data']);
    }
    if (dataClassName == 'UserCredential') {
      return deserialize<_i69.UserCredential>(data['data']);
    }
    if (dataClassName == 'Visit') {
      return deserialize<_i70.Visit>(data['data']);
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
