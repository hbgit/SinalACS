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
import 'api/admin_acs.dart' as _i9;
import 'api/admin_acs_creation_result.dart' as _i10;
import 'api/admin_alert.dart' as _i11;
import 'api/admin_alert_page.dart' as _i12;
import 'api/admin_audit_entry.dart' as _i13;
import 'api/admin_audit_page.dart' as _i14;
import 'api/admin_indicators.dart' as _i15;
import 'api/admin_micro_area.dart' as _i16;
import 'api/admin_password_reset_result.dart' as _i17;
import 'api/admin_staff.dart' as _i18;
import 'api/alert_ack_result.dart' as _i19;
import 'api/alert_status_result.dart' as _i20;
import 'api/development_login_result.dart' as _i21;
import 'api/enrollment_result.dart' as _i22;
import 'api/enrollment_token_result.dart' as _i23;
import 'api/micro_area_patient.dart' as _i24;
import 'api/notice_send_result.dart' as _i25;
import 'api/patient_consent_record.dart' as _i26;
import 'api/patient_data_overview.dart' as _i27;
import 'api/patient_data_subject_request_record.dart' as _i28;
import 'api/patient_risk_event.dart' as _i29;
import 'api/red_alert_result.dart' as _i30;
import 'api/service_health.dart' as _i31;
import 'api/terms_change_notice.dart' as _i32;
import 'api/totp_enrollment_start.dart' as _i33;
import 'api/triage_result.dart' as _i34;
import 'api/ubs_contact.dart' as _i35;
import 'api/visit_sync_entry.dart' as _i36;
import 'api/visit_sync_result.dart' as _i37;
import 'audit_log.dart' as _i38;
import 'consent_log.dart' as _i39;
import 'data_subject_request.dart' as _i40;
import 'enrollment_token.dart' as _i41;
import 'enums/alert_status.dart' as _i42;
import 'enums/arrival_method.dart' as _i43;
import 'enums/consent_purpose.dart' as _i44;
import 'enums/data_subject_request_status.dart' as _i45;
import 'enums/data_subject_request_type.dart' as _i46;
import 'enums/risk_level.dart' as _i47;
import 'enums/sync_status.dart' as _i48;
import 'enums/user_role.dart' as _i49;
import 'enums/visit_authorship.dart' as _i50;
import 'exceptions/admin_invalid_request_exception.dart' as _i51;
import 'exceptions/alert_dispatch_unavailable_exception.dart' as _i52;
import 'exceptions/alert_permission_exception.dart' as _i53;
import 'exceptions/alert_validation_exception.dart' as _i54;
import 'exceptions/authentication_failed_exception.dart' as _i55;
import 'exceptions/data_rights_exception.dart' as _i56;
import 'exceptions/endpoint_disabled_exception.dart' as _i57;
import 'exceptions/enrollment_exception.dart' as _i58;
import 'exceptions/mfa_enrollment_required_exception.dart' as _i59;
import 'exceptions/mfa_required_exception.dart' as _i60;
import 'exceptions/notice_delivery_exception.dart' as _i61;
import 'exceptions/otp_request_exception.dart' as _i62;
import 'exceptions/session_expired_exception.dart' as _i63;
import 'micro_area.dart' as _i64;
import 'otp_challenge.dart' as _i65;
import 'patient.dart' as _i66;
import 'push_token.dart' as _i67;
import 'staff_account.dart' as _i68;
import 'triage_answer.dart' as _i69;
import 'triage_session.dart' as _i70;
import 'ubs.dart' as _i71;
import 'user.dart' as _i72;
import 'user_credential.dart' as _i73;
import 'visit.dart' as _i74;
import 'package:sinalacs_client/src/protocol/api/admin_micro_area.dart' as _i75;
import 'package:sinalacs_client/src/protocol/api/admin_acs.dart' as _i76;
import 'package:sinalacs_client/src/protocol/api/admin_staff.dart' as _i77;
import 'package:sinalacs_client/src/protocol/api/micro_area_patient.dart'
    as _i78;
import 'package:sinalacs_client/src/protocol/api/visit_sync_result.dart'
    as _i79;
import 'package:sinalacs_client/src/protocol/api/visit_sync_entry.dart' as _i80;
export 'acs.dart';
export 'acs_refresh_token.dart';
export 'acs_upload_token.dart';
export 'alert.dart';
export 'alert_delivery_record.dart';
export 'alert_idempotency_key.dart';
export 'alert_outbox_entry.dart';
export 'api/admin_acs.dart';
export 'api/admin_acs_creation_result.dart';
export 'api/admin_alert.dart';
export 'api/admin_alert_page.dart';
export 'api/admin_audit_entry.dart';
export 'api/admin_audit_page.dart';
export 'api/admin_indicators.dart';
export 'api/admin_micro_area.dart';
export 'api/admin_password_reset_result.dart';
export 'api/admin_staff.dart';
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
    if (t == _i9.AdminAcs) {
      return _i9.AdminAcs.fromJson(data) as T;
    }
    if (t == _i10.AdminAcsCreationResult) {
      return _i10.AdminAcsCreationResult.fromJson(data) as T;
    }
    if (t == _i11.AdminAlert) {
      return _i11.AdminAlert.fromJson(data) as T;
    }
    if (t == _i12.AdminAlertPage) {
      return _i12.AdminAlertPage.fromJson(data) as T;
    }
    if (t == _i13.AdminAuditEntry) {
      return _i13.AdminAuditEntry.fromJson(data) as T;
    }
    if (t == _i14.AdminAuditPage) {
      return _i14.AdminAuditPage.fromJson(data) as T;
    }
    if (t == _i15.AdminIndicators) {
      return _i15.AdminIndicators.fromJson(data) as T;
    }
    if (t == _i16.AdminMicroArea) {
      return _i16.AdminMicroArea.fromJson(data) as T;
    }
    if (t == _i17.AdminPasswordResetResult) {
      return _i17.AdminPasswordResetResult.fromJson(data) as T;
    }
    if (t == _i18.AdminStaff) {
      return _i18.AdminStaff.fromJson(data) as T;
    }
    if (t == _i19.AlertAckResult) {
      return _i19.AlertAckResult.fromJson(data) as T;
    }
    if (t == _i20.AlertStatusResult) {
      return _i20.AlertStatusResult.fromJson(data) as T;
    }
    if (t == _i21.DevelopmentLoginResult) {
      return _i21.DevelopmentLoginResult.fromJson(data) as T;
    }
    if (t == _i22.EnrollmentResult) {
      return _i22.EnrollmentResult.fromJson(data) as T;
    }
    if (t == _i23.EnrollmentTokenResult) {
      return _i23.EnrollmentTokenResult.fromJson(data) as T;
    }
    if (t == _i24.MicroAreaPatient) {
      return _i24.MicroAreaPatient.fromJson(data) as T;
    }
    if (t == _i25.NoticeSendResult) {
      return _i25.NoticeSendResult.fromJson(data) as T;
    }
    if (t == _i26.PatientConsentRecord) {
      return _i26.PatientConsentRecord.fromJson(data) as T;
    }
    if (t == _i27.PatientDataOverview) {
      return _i27.PatientDataOverview.fromJson(data) as T;
    }
    if (t == _i28.PatientDataSubjectRequestRecord) {
      return _i28.PatientDataSubjectRequestRecord.fromJson(data) as T;
    }
    if (t == _i29.PatientRiskEvent) {
      return _i29.PatientRiskEvent.fromJson(data) as T;
    }
    if (t == _i30.RedAlertResult) {
      return _i30.RedAlertResult.fromJson(data) as T;
    }
    if (t == _i31.ServiceHealth) {
      return _i31.ServiceHealth.fromJson(data) as T;
    }
    if (t == _i32.TermsChangeNotice) {
      return _i32.TermsChangeNotice.fromJson(data) as T;
    }
    if (t == _i33.TotpEnrollmentStart) {
      return _i33.TotpEnrollmentStart.fromJson(data) as T;
    }
    if (t == _i34.TriageResult) {
      return _i34.TriageResult.fromJson(data) as T;
    }
    if (t == _i35.UbsContact) {
      return _i35.UbsContact.fromJson(data) as T;
    }
    if (t == _i36.VisitSyncEntry) {
      return _i36.VisitSyncEntry.fromJson(data) as T;
    }
    if (t == _i37.VisitSyncResult) {
      return _i37.VisitSyncResult.fromJson(data) as T;
    }
    if (t == _i38.AuditLog) {
      return _i38.AuditLog.fromJson(data) as T;
    }
    if (t == _i39.ConsentLog) {
      return _i39.ConsentLog.fromJson(data) as T;
    }
    if (t == _i40.DataSubjectRequest) {
      return _i40.DataSubjectRequest.fromJson(data) as T;
    }
    if (t == _i41.EnrollmentToken) {
      return _i41.EnrollmentToken.fromJson(data) as T;
    }
    if (t == _i42.AlertStatus) {
      return _i42.AlertStatus.fromJson(data) as T;
    }
    if (t == _i43.ArrivalMethod) {
      return _i43.ArrivalMethod.fromJson(data) as T;
    }
    if (t == _i44.ConsentPurpose) {
      return _i44.ConsentPurpose.fromJson(data) as T;
    }
    if (t == _i45.DataSubjectRequestStatus) {
      return _i45.DataSubjectRequestStatus.fromJson(data) as T;
    }
    if (t == _i46.DataSubjectRequestType) {
      return _i46.DataSubjectRequestType.fromJson(data) as T;
    }
    if (t == _i47.RiskLevel) {
      return _i47.RiskLevel.fromJson(data) as T;
    }
    if (t == _i48.SyncStatus) {
      return _i48.SyncStatus.fromJson(data) as T;
    }
    if (t == _i49.UserRole) {
      return _i49.UserRole.fromJson(data) as T;
    }
    if (t == _i50.VisitAuthorship) {
      return _i50.VisitAuthorship.fromJson(data) as T;
    }
    if (t == _i51.AdminInvalidRequestException) {
      return _i51.AdminInvalidRequestException.fromJson(data) as T;
    }
    if (t == _i52.AlertDispatchUnavailableException) {
      return _i52.AlertDispatchUnavailableException.fromJson(data) as T;
    }
    if (t == _i53.AlertPermissionException) {
      return _i53.AlertPermissionException.fromJson(data) as T;
    }
    if (t == _i54.AlertValidationException) {
      return _i54.AlertValidationException.fromJson(data) as T;
    }
    if (t == _i55.AuthenticationFailedException) {
      return _i55.AuthenticationFailedException.fromJson(data) as T;
    }
    if (t == _i56.DataRightsException) {
      return _i56.DataRightsException.fromJson(data) as T;
    }
    if (t == _i57.EndpointDisabledException) {
      return _i57.EndpointDisabledException.fromJson(data) as T;
    }
    if (t == _i58.EnrollmentException) {
      return _i58.EnrollmentException.fromJson(data) as T;
    }
    if (t == _i59.MfaEnrollmentRequiredException) {
      return _i59.MfaEnrollmentRequiredException.fromJson(data) as T;
    }
    if (t == _i60.MfaRequiredException) {
      return _i60.MfaRequiredException.fromJson(data) as T;
    }
    if (t == _i61.NoticeDeliveryException) {
      return _i61.NoticeDeliveryException.fromJson(data) as T;
    }
    if (t == _i62.OtpRequestException) {
      return _i62.OtpRequestException.fromJson(data) as T;
    }
    if (t == _i63.SessionExpiredException) {
      return _i63.SessionExpiredException.fromJson(data) as T;
    }
    if (t == _i64.MicroArea) {
      return _i64.MicroArea.fromJson(data) as T;
    }
    if (t == _i65.OtpChallenge) {
      return _i65.OtpChallenge.fromJson(data) as T;
    }
    if (t == _i66.Patient) {
      return _i66.Patient.fromJson(data) as T;
    }
    if (t == _i67.PushToken) {
      return _i67.PushToken.fromJson(data) as T;
    }
    if (t == _i68.StaffAccount) {
      return _i68.StaffAccount.fromJson(data) as T;
    }
    if (t == _i69.TriageAnswer) {
      return _i69.TriageAnswer.fromJson(data) as T;
    }
    if (t == _i70.TriageSession) {
      return _i70.TriageSession.fromJson(data) as T;
    }
    if (t == _i71.Ubs) {
      return _i71.Ubs.fromJson(data) as T;
    }
    if (t == _i72.User) {
      return _i72.User.fromJson(data) as T;
    }
    if (t == _i73.UserCredential) {
      return _i73.UserCredential.fromJson(data) as T;
    }
    if (t == _i74.Visit) {
      return _i74.Visit.fromJson(data) as T;
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
    if (t == _i1.getType<_i9.AdminAcs?>()) {
      return (data != null ? _i9.AdminAcs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i10.AdminAcsCreationResult?>()) {
      return (data != null ? _i10.AdminAcsCreationResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i11.AdminAlert?>()) {
      return (data != null ? _i11.AdminAlert.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i12.AdminAlertPage?>()) {
      return (data != null ? _i12.AdminAlertPage.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i13.AdminAuditEntry?>()) {
      return (data != null ? _i13.AdminAuditEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i14.AdminAuditPage?>()) {
      return (data != null ? _i14.AdminAuditPage.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i15.AdminIndicators?>()) {
      return (data != null ? _i15.AdminIndicators.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i16.AdminMicroArea?>()) {
      return (data != null ? _i16.AdminMicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i17.AdminPasswordResetResult?>()) {
      return (data != null
              ? _i17.AdminPasswordResetResult.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i18.AdminStaff?>()) {
      return (data != null ? _i18.AdminStaff.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i19.AlertAckResult?>()) {
      return (data != null ? _i19.AlertAckResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i20.AlertStatusResult?>()) {
      return (data != null ? _i20.AlertStatusResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i21.DevelopmentLoginResult?>()) {
      return (data != null ? _i21.DevelopmentLoginResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i22.EnrollmentResult?>()) {
      return (data != null ? _i22.EnrollmentResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i23.EnrollmentTokenResult?>()) {
      return (data != null ? _i23.EnrollmentTokenResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i24.MicroAreaPatient?>()) {
      return (data != null ? _i24.MicroAreaPatient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i25.NoticeSendResult?>()) {
      return (data != null ? _i25.NoticeSendResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i26.PatientConsentRecord?>()) {
      return (data != null ? _i26.PatientConsentRecord.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i27.PatientDataOverview?>()) {
      return (data != null ? _i27.PatientDataOverview.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i28.PatientDataSubjectRequestRecord?>()) {
      return (data != null
              ? _i28.PatientDataSubjectRequestRecord.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i29.PatientRiskEvent?>()) {
      return (data != null ? _i29.PatientRiskEvent.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i30.RedAlertResult?>()) {
      return (data != null ? _i30.RedAlertResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i31.ServiceHealth?>()) {
      return (data != null ? _i31.ServiceHealth.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i32.TermsChangeNotice?>()) {
      return (data != null ? _i32.TermsChangeNotice.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i33.TotpEnrollmentStart?>()) {
      return (data != null ? _i33.TotpEnrollmentStart.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i34.TriageResult?>()) {
      return (data != null ? _i34.TriageResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i35.UbsContact?>()) {
      return (data != null ? _i35.UbsContact.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i36.VisitSyncEntry?>()) {
      return (data != null ? _i36.VisitSyncEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i37.VisitSyncResult?>()) {
      return (data != null ? _i37.VisitSyncResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i38.AuditLog?>()) {
      return (data != null ? _i38.AuditLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i39.ConsentLog?>()) {
      return (data != null ? _i39.ConsentLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i40.DataSubjectRequest?>()) {
      return (data != null ? _i40.DataSubjectRequest.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i41.EnrollmentToken?>()) {
      return (data != null ? _i41.EnrollmentToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i42.AlertStatus?>()) {
      return (data != null ? _i42.AlertStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i43.ArrivalMethod?>()) {
      return (data != null ? _i43.ArrivalMethod.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i44.ConsentPurpose?>()) {
      return (data != null ? _i44.ConsentPurpose.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i45.DataSubjectRequestStatus?>()) {
      return (data != null
              ? _i45.DataSubjectRequestStatus.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i46.DataSubjectRequestType?>()) {
      return (data != null ? _i46.DataSubjectRequestType.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i47.RiskLevel?>()) {
      return (data != null ? _i47.RiskLevel.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i48.SyncStatus?>()) {
      return (data != null ? _i48.SyncStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i49.UserRole?>()) {
      return (data != null ? _i49.UserRole.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i50.VisitAuthorship?>()) {
      return (data != null ? _i50.VisitAuthorship.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i51.AdminInvalidRequestException?>()) {
      return (data != null
              ? _i51.AdminInvalidRequestException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i52.AlertDispatchUnavailableException?>()) {
      return (data != null
              ? _i52.AlertDispatchUnavailableException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i53.AlertPermissionException?>()) {
      return (data != null
              ? _i53.AlertPermissionException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i54.AlertValidationException?>()) {
      return (data != null
              ? _i54.AlertValidationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i55.AuthenticationFailedException?>()) {
      return (data != null
              ? _i55.AuthenticationFailedException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i56.DataRightsException?>()) {
      return (data != null ? _i56.DataRightsException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i57.EndpointDisabledException?>()) {
      return (data != null
              ? _i57.EndpointDisabledException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i58.EnrollmentException?>()) {
      return (data != null ? _i58.EnrollmentException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i59.MfaEnrollmentRequiredException?>()) {
      return (data != null
              ? _i59.MfaEnrollmentRequiredException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i60.MfaRequiredException?>()) {
      return (data != null ? _i60.MfaRequiredException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i61.NoticeDeliveryException?>()) {
      return (data != null ? _i61.NoticeDeliveryException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i62.OtpRequestException?>()) {
      return (data != null ? _i62.OtpRequestException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i63.SessionExpiredException?>()) {
      return (data != null ? _i63.SessionExpiredException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i64.MicroArea?>()) {
      return (data != null ? _i64.MicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i65.OtpChallenge?>()) {
      return (data != null ? _i65.OtpChallenge.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i66.Patient?>()) {
      return (data != null ? _i66.Patient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i67.PushToken?>()) {
      return (data != null ? _i67.PushToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i68.StaffAccount?>()) {
      return (data != null ? _i68.StaffAccount.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i69.TriageAnswer?>()) {
      return (data != null ? _i69.TriageAnswer.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i70.TriageSession?>()) {
      return (data != null ? _i70.TriageSession.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i71.Ubs?>()) {
      return (data != null ? _i71.Ubs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i72.User?>()) {
      return (data != null ? _i72.User.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i73.UserCredential?>()) {
      return (data != null ? _i73.UserCredential.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i74.Visit?>()) {
      return (data != null ? _i74.Visit.fromJson(data) : null) as T;
    }
    if (t == List<_i11.AdminAlert>) {
      return (data as List).map((e) => deserialize<_i11.AdminAlert>(e)).toList()
          as T;
    }
    if (t == List<_i13.AdminAuditEntry>) {
      return (data as List)
              .map((e) => deserialize<_i13.AdminAuditEntry>(e))
              .toList()
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i26.PatientConsentRecord>) {
      return (data as List)
              .map((e) => deserialize<_i26.PatientConsentRecord>(e))
              .toList()
          as T;
    }
    if (t == List<_i29.PatientRiskEvent>) {
      return (data as List)
              .map((e) => deserialize<_i29.PatientRiskEvent>(e))
              .toList()
          as T;
    }
    if (t == List<_i28.PatientDataSubjectRequestRecord>) {
      return (data as List)
              .map((e) => deserialize<_i28.PatientDataSubjectRequestRecord>(e))
              .toList()
          as T;
    }
    if (t == Map<String, String>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<String>(v)),
          )
          as T;
    }
    if (t == List<_i75.AdminMicroArea>) {
      return (data as List)
              .map((e) => deserialize<_i75.AdminMicroArea>(e))
              .toList()
          as T;
    }
    if (t == List<_i76.AdminAcs>) {
      return (data as List).map((e) => deserialize<_i76.AdminAcs>(e)).toList()
          as T;
    }
    if (t == List<_i77.AdminStaff>) {
      return (data as List).map((e) => deserialize<_i77.AdminStaff>(e)).toList()
          as T;
    }
    if (t == List<_i78.MicroAreaPatient>) {
      return (data as List)
              .map((e) => deserialize<_i78.MicroAreaPatient>(e))
              .toList()
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i79.VisitSyncResult>) {
      return (data as List)
              .map((e) => deserialize<_i79.VisitSyncResult>(e))
              .toList()
          as T;
    }
    if (t == List<_i80.VisitSyncEntry>) {
      return (data as List)
              .map((e) => deserialize<_i80.VisitSyncEntry>(e))
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
      _i9.AdminAcs => 'AdminAcs',
      _i10.AdminAcsCreationResult => 'AdminAcsCreationResult',
      _i11.AdminAlert => 'AdminAlert',
      _i12.AdminAlertPage => 'AdminAlertPage',
      _i13.AdminAuditEntry => 'AdminAuditEntry',
      _i14.AdminAuditPage => 'AdminAuditPage',
      _i15.AdminIndicators => 'AdminIndicators',
      _i16.AdminMicroArea => 'AdminMicroArea',
      _i17.AdminPasswordResetResult => 'AdminPasswordResetResult',
      _i18.AdminStaff => 'AdminStaff',
      _i19.AlertAckResult => 'AlertAckResult',
      _i20.AlertStatusResult => 'AlertStatusResult',
      _i21.DevelopmentLoginResult => 'DevelopmentLoginResult',
      _i22.EnrollmentResult => 'EnrollmentResult',
      _i23.EnrollmentTokenResult => 'EnrollmentTokenResult',
      _i24.MicroAreaPatient => 'MicroAreaPatient',
      _i25.NoticeSendResult => 'NoticeSendResult',
      _i26.PatientConsentRecord => 'PatientConsentRecord',
      _i27.PatientDataOverview => 'PatientDataOverview',
      _i28.PatientDataSubjectRequestRecord => 'PatientDataSubjectRequestRecord',
      _i29.PatientRiskEvent => 'PatientRiskEvent',
      _i30.RedAlertResult => 'RedAlertResult',
      _i31.ServiceHealth => 'ServiceHealth',
      _i32.TermsChangeNotice => 'TermsChangeNotice',
      _i33.TotpEnrollmentStart => 'TotpEnrollmentStart',
      _i34.TriageResult => 'TriageResult',
      _i35.UbsContact => 'UbsContact',
      _i36.VisitSyncEntry => 'VisitSyncEntry',
      _i37.VisitSyncResult => 'VisitSyncResult',
      _i38.AuditLog => 'AuditLog',
      _i39.ConsentLog => 'ConsentLog',
      _i40.DataSubjectRequest => 'DataSubjectRequest',
      _i41.EnrollmentToken => 'EnrollmentToken',
      _i42.AlertStatus => 'AlertStatus',
      _i43.ArrivalMethod => 'ArrivalMethod',
      _i44.ConsentPurpose => 'ConsentPurpose',
      _i45.DataSubjectRequestStatus => 'DataSubjectRequestStatus',
      _i46.DataSubjectRequestType => 'DataSubjectRequestType',
      _i47.RiskLevel => 'RiskLevel',
      _i48.SyncStatus => 'SyncStatus',
      _i49.UserRole => 'UserRole',
      _i50.VisitAuthorship => 'VisitAuthorship',
      _i51.AdminInvalidRequestException => 'AdminInvalidRequestException',
      _i52.AlertDispatchUnavailableException =>
        'AlertDispatchUnavailableException',
      _i53.AlertPermissionException => 'AlertPermissionException',
      _i54.AlertValidationException => 'AlertValidationException',
      _i55.AuthenticationFailedException => 'AuthenticationFailedException',
      _i56.DataRightsException => 'DataRightsException',
      _i57.EndpointDisabledException => 'EndpointDisabledException',
      _i58.EnrollmentException => 'EnrollmentException',
      _i59.MfaEnrollmentRequiredException => 'MfaEnrollmentRequiredException',
      _i60.MfaRequiredException => 'MfaRequiredException',
      _i61.NoticeDeliveryException => 'NoticeDeliveryException',
      _i62.OtpRequestException => 'OtpRequestException',
      _i63.SessionExpiredException => 'SessionExpiredException',
      _i64.MicroArea => 'MicroArea',
      _i65.OtpChallenge => 'OtpChallenge',
      _i66.Patient => 'Patient',
      _i67.PushToken => 'PushToken',
      _i68.StaffAccount => 'StaffAccount',
      _i69.TriageAnswer => 'TriageAnswer',
      _i70.TriageSession => 'TriageSession',
      _i71.Ubs => 'Ubs',
      _i72.User => 'User',
      _i73.UserCredential => 'UserCredential',
      _i74.Visit => 'Visit',
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
      case _i9.AdminAcs():
        return 'AdminAcs';
      case _i10.AdminAcsCreationResult():
        return 'AdminAcsCreationResult';
      case _i11.AdminAlert():
        return 'AdminAlert';
      case _i12.AdminAlertPage():
        return 'AdminAlertPage';
      case _i13.AdminAuditEntry():
        return 'AdminAuditEntry';
      case _i14.AdminAuditPage():
        return 'AdminAuditPage';
      case _i15.AdminIndicators():
        return 'AdminIndicators';
      case _i16.AdminMicroArea():
        return 'AdminMicroArea';
      case _i17.AdminPasswordResetResult():
        return 'AdminPasswordResetResult';
      case _i18.AdminStaff():
        return 'AdminStaff';
      case _i19.AlertAckResult():
        return 'AlertAckResult';
      case _i20.AlertStatusResult():
        return 'AlertStatusResult';
      case _i21.DevelopmentLoginResult():
        return 'DevelopmentLoginResult';
      case _i22.EnrollmentResult():
        return 'EnrollmentResult';
      case _i23.EnrollmentTokenResult():
        return 'EnrollmentTokenResult';
      case _i24.MicroAreaPatient():
        return 'MicroAreaPatient';
      case _i25.NoticeSendResult():
        return 'NoticeSendResult';
      case _i26.PatientConsentRecord():
        return 'PatientConsentRecord';
      case _i27.PatientDataOverview():
        return 'PatientDataOverview';
      case _i28.PatientDataSubjectRequestRecord():
        return 'PatientDataSubjectRequestRecord';
      case _i29.PatientRiskEvent():
        return 'PatientRiskEvent';
      case _i30.RedAlertResult():
        return 'RedAlertResult';
      case _i31.ServiceHealth():
        return 'ServiceHealth';
      case _i32.TermsChangeNotice():
        return 'TermsChangeNotice';
      case _i33.TotpEnrollmentStart():
        return 'TotpEnrollmentStart';
      case _i34.TriageResult():
        return 'TriageResult';
      case _i35.UbsContact():
        return 'UbsContact';
      case _i36.VisitSyncEntry():
        return 'VisitSyncEntry';
      case _i37.VisitSyncResult():
        return 'VisitSyncResult';
      case _i38.AuditLog():
        return 'AuditLog';
      case _i39.ConsentLog():
        return 'ConsentLog';
      case _i40.DataSubjectRequest():
        return 'DataSubjectRequest';
      case _i41.EnrollmentToken():
        return 'EnrollmentToken';
      case _i42.AlertStatus():
        return 'AlertStatus';
      case _i43.ArrivalMethod():
        return 'ArrivalMethod';
      case _i44.ConsentPurpose():
        return 'ConsentPurpose';
      case _i45.DataSubjectRequestStatus():
        return 'DataSubjectRequestStatus';
      case _i46.DataSubjectRequestType():
        return 'DataSubjectRequestType';
      case _i47.RiskLevel():
        return 'RiskLevel';
      case _i48.SyncStatus():
        return 'SyncStatus';
      case _i49.UserRole():
        return 'UserRole';
      case _i50.VisitAuthorship():
        return 'VisitAuthorship';
      case _i51.AdminInvalidRequestException():
        return 'AdminInvalidRequestException';
      case _i52.AlertDispatchUnavailableException():
        return 'AlertDispatchUnavailableException';
      case _i53.AlertPermissionException():
        return 'AlertPermissionException';
      case _i54.AlertValidationException():
        return 'AlertValidationException';
      case _i55.AuthenticationFailedException():
        return 'AuthenticationFailedException';
      case _i56.DataRightsException():
        return 'DataRightsException';
      case _i57.EndpointDisabledException():
        return 'EndpointDisabledException';
      case _i58.EnrollmentException():
        return 'EnrollmentException';
      case _i59.MfaEnrollmentRequiredException():
        return 'MfaEnrollmentRequiredException';
      case _i60.MfaRequiredException():
        return 'MfaRequiredException';
      case _i61.NoticeDeliveryException():
        return 'NoticeDeliveryException';
      case _i62.OtpRequestException():
        return 'OtpRequestException';
      case _i63.SessionExpiredException():
        return 'SessionExpiredException';
      case _i64.MicroArea():
        return 'MicroArea';
      case _i65.OtpChallenge():
        return 'OtpChallenge';
      case _i66.Patient():
        return 'Patient';
      case _i67.PushToken():
        return 'PushToken';
      case _i68.StaffAccount():
        return 'StaffAccount';
      case _i69.TriageAnswer():
        return 'TriageAnswer';
      case _i70.TriageSession():
        return 'TriageSession';
      case _i71.Ubs():
        return 'Ubs';
      case _i72.User():
        return 'User';
      case _i73.UserCredential():
        return 'UserCredential';
      case _i74.Visit():
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
    if (dataClassName == 'AdminAcs') {
      return deserialize<_i9.AdminAcs>(data['data']);
    }
    if (dataClassName == 'AdminAcsCreationResult') {
      return deserialize<_i10.AdminAcsCreationResult>(data['data']);
    }
    if (dataClassName == 'AdminAlert') {
      return deserialize<_i11.AdminAlert>(data['data']);
    }
    if (dataClassName == 'AdminAlertPage') {
      return deserialize<_i12.AdminAlertPage>(data['data']);
    }
    if (dataClassName == 'AdminAuditEntry') {
      return deserialize<_i13.AdminAuditEntry>(data['data']);
    }
    if (dataClassName == 'AdminAuditPage') {
      return deserialize<_i14.AdminAuditPage>(data['data']);
    }
    if (dataClassName == 'AdminIndicators') {
      return deserialize<_i15.AdminIndicators>(data['data']);
    }
    if (dataClassName == 'AdminMicroArea') {
      return deserialize<_i16.AdminMicroArea>(data['data']);
    }
    if (dataClassName == 'AdminPasswordResetResult') {
      return deserialize<_i17.AdminPasswordResetResult>(data['data']);
    }
    if (dataClassName == 'AdminStaff') {
      return deserialize<_i18.AdminStaff>(data['data']);
    }
    if (dataClassName == 'AlertAckResult') {
      return deserialize<_i19.AlertAckResult>(data['data']);
    }
    if (dataClassName == 'AlertStatusResult') {
      return deserialize<_i20.AlertStatusResult>(data['data']);
    }
    if (dataClassName == 'DevelopmentLoginResult') {
      return deserialize<_i21.DevelopmentLoginResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentResult') {
      return deserialize<_i22.EnrollmentResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentTokenResult') {
      return deserialize<_i23.EnrollmentTokenResult>(data['data']);
    }
    if (dataClassName == 'MicroAreaPatient') {
      return deserialize<_i24.MicroAreaPatient>(data['data']);
    }
    if (dataClassName == 'NoticeSendResult') {
      return deserialize<_i25.NoticeSendResult>(data['data']);
    }
    if (dataClassName == 'PatientConsentRecord') {
      return deserialize<_i26.PatientConsentRecord>(data['data']);
    }
    if (dataClassName == 'PatientDataOverview') {
      return deserialize<_i27.PatientDataOverview>(data['data']);
    }
    if (dataClassName == 'PatientDataSubjectRequestRecord') {
      return deserialize<_i28.PatientDataSubjectRequestRecord>(data['data']);
    }
    if (dataClassName == 'PatientRiskEvent') {
      return deserialize<_i29.PatientRiskEvent>(data['data']);
    }
    if (dataClassName == 'RedAlertResult') {
      return deserialize<_i30.RedAlertResult>(data['data']);
    }
    if (dataClassName == 'ServiceHealth') {
      return deserialize<_i31.ServiceHealth>(data['data']);
    }
    if (dataClassName == 'TermsChangeNotice') {
      return deserialize<_i32.TermsChangeNotice>(data['data']);
    }
    if (dataClassName == 'TotpEnrollmentStart') {
      return deserialize<_i33.TotpEnrollmentStart>(data['data']);
    }
    if (dataClassName == 'TriageResult') {
      return deserialize<_i34.TriageResult>(data['data']);
    }
    if (dataClassName == 'UbsContact') {
      return deserialize<_i35.UbsContact>(data['data']);
    }
    if (dataClassName == 'VisitSyncEntry') {
      return deserialize<_i36.VisitSyncEntry>(data['data']);
    }
    if (dataClassName == 'VisitSyncResult') {
      return deserialize<_i37.VisitSyncResult>(data['data']);
    }
    if (dataClassName == 'AuditLog') {
      return deserialize<_i38.AuditLog>(data['data']);
    }
    if (dataClassName == 'ConsentLog') {
      return deserialize<_i39.ConsentLog>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequest') {
      return deserialize<_i40.DataSubjectRequest>(data['data']);
    }
    if (dataClassName == 'EnrollmentToken') {
      return deserialize<_i41.EnrollmentToken>(data['data']);
    }
    if (dataClassName == 'AlertStatus') {
      return deserialize<_i42.AlertStatus>(data['data']);
    }
    if (dataClassName == 'ArrivalMethod') {
      return deserialize<_i43.ArrivalMethod>(data['data']);
    }
    if (dataClassName == 'ConsentPurpose') {
      return deserialize<_i44.ConsentPurpose>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestStatus') {
      return deserialize<_i45.DataSubjectRequestStatus>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestType') {
      return deserialize<_i46.DataSubjectRequestType>(data['data']);
    }
    if (dataClassName == 'RiskLevel') {
      return deserialize<_i47.RiskLevel>(data['data']);
    }
    if (dataClassName == 'SyncStatus') {
      return deserialize<_i48.SyncStatus>(data['data']);
    }
    if (dataClassName == 'UserRole') {
      return deserialize<_i49.UserRole>(data['data']);
    }
    if (dataClassName == 'VisitAuthorship') {
      return deserialize<_i50.VisitAuthorship>(data['data']);
    }
    if (dataClassName == 'AdminInvalidRequestException') {
      return deserialize<_i51.AdminInvalidRequestException>(data['data']);
    }
    if (dataClassName == 'AlertDispatchUnavailableException') {
      return deserialize<_i52.AlertDispatchUnavailableException>(data['data']);
    }
    if (dataClassName == 'AlertPermissionException') {
      return deserialize<_i53.AlertPermissionException>(data['data']);
    }
    if (dataClassName == 'AlertValidationException') {
      return deserialize<_i54.AlertValidationException>(data['data']);
    }
    if (dataClassName == 'AuthenticationFailedException') {
      return deserialize<_i55.AuthenticationFailedException>(data['data']);
    }
    if (dataClassName == 'DataRightsException') {
      return deserialize<_i56.DataRightsException>(data['data']);
    }
    if (dataClassName == 'EndpointDisabledException') {
      return deserialize<_i57.EndpointDisabledException>(data['data']);
    }
    if (dataClassName == 'EnrollmentException') {
      return deserialize<_i58.EnrollmentException>(data['data']);
    }
    if (dataClassName == 'MfaEnrollmentRequiredException') {
      return deserialize<_i59.MfaEnrollmentRequiredException>(data['data']);
    }
    if (dataClassName == 'MfaRequiredException') {
      return deserialize<_i60.MfaRequiredException>(data['data']);
    }
    if (dataClassName == 'NoticeDeliveryException') {
      return deserialize<_i61.NoticeDeliveryException>(data['data']);
    }
    if (dataClassName == 'OtpRequestException') {
      return deserialize<_i62.OtpRequestException>(data['data']);
    }
    if (dataClassName == 'SessionExpiredException') {
      return deserialize<_i63.SessionExpiredException>(data['data']);
    }
    if (dataClassName == 'MicroArea') {
      return deserialize<_i64.MicroArea>(data['data']);
    }
    if (dataClassName == 'OtpChallenge') {
      return deserialize<_i65.OtpChallenge>(data['data']);
    }
    if (dataClassName == 'Patient') {
      return deserialize<_i66.Patient>(data['data']);
    }
    if (dataClassName == 'PushToken') {
      return deserialize<_i67.PushToken>(data['data']);
    }
    if (dataClassName == 'StaffAccount') {
      return deserialize<_i68.StaffAccount>(data['data']);
    }
    if (dataClassName == 'TriageAnswer') {
      return deserialize<_i69.TriageAnswer>(data['data']);
    }
    if (dataClassName == 'TriageSession') {
      return deserialize<_i70.TriageSession>(data['data']);
    }
    if (dataClassName == 'Ubs') {
      return deserialize<_i71.Ubs>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i72.User>(data['data']);
    }
    if (dataClassName == 'UserCredential') {
      return deserialize<_i73.UserCredential>(data['data']);
    }
    if (dataClassName == 'Visit') {
      return deserialize<_i74.Visit>(data['data']);
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
