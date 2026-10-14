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
import 'api/admin_alerts_pulse.dart' as _i13;
import 'api/admin_audit_chain_status.dart' as _i14;
import 'api/admin_audit_entry.dart' as _i15;
import 'api/admin_audit_export.dart' as _i16;
import 'api/admin_audit_filter.dart' as _i17;
import 'api/admin_audit_page.dart' as _i18;
import 'api/admin_data_subject_request.dart' as _i19;
import 'api/admin_data_subject_request_detail.dart' as _i20;
import 'api/admin_data_subject_request_page.dart' as _i21;
import 'api/admin_escalation_result.dart' as _i22;
import 'api/admin_indicators.dart' as _i23;
import 'api/admin_micro_area.dart' as _i24;
import 'api/admin_password_reset_result.dart' as _i25;
import 'api/admin_staff.dart' as _i26;
import 'api/admin_staff_mfa_reset_result.dart' as _i27;
import 'api/alert_ack_result.dart' as _i28;
import 'api/alert_status_result.dart' as _i29;
import 'api/development_login_result.dart' as _i30;
import 'api/enrollment_result.dart' as _i31;
import 'api/enrollment_token_result.dart' as _i32;
import 'api/micro_area_patient.dart' as _i33;
import 'api/notice_history_entry.dart' as _i34;
import 'api/notice_history_page.dart' as _i35;
import 'api/notice_send_result.dart' as _i36;
import 'api/patient_consent_record.dart' as _i37;
import 'api/patient_data_overview.dart' as _i38;
import 'api/patient_data_subject_request_record.dart' as _i39;
import 'api/patient_risk_event.dart' as _i40;
import 'api/red_alert_result.dart' as _i41;
import 'api/service_health.dart' as _i42;
import 'api/terms_change_notice.dart' as _i43;
import 'api/terms_version_entry.dart' as _i44;
import 'api/totp_enrollment_start.dart' as _i45;
import 'api/triage_result.dart' as _i46;
import 'api/ubs_contact.dart' as _i47;
import 'api/visit_sync_entry.dart' as _i48;
import 'api/visit_sync_result.dart' as _i49;
import 'audit_chain_checkpoint.dart' as _i50;
import 'audit_export.dart' as _i51;
import 'audit_log.dart' as _i52;
import 'consent_log.dart' as _i53;
import 'data_subject_request.dart' as _i54;
import 'enrollment_token.dart' as _i55;
import 'enums/alert_status.dart' as _i56;
import 'enums/arrival_method.dart' as _i57;
import 'enums/audit_chain_reason.dart' as _i58;
import 'enums/audit_integrity_state.dart' as _i59;
import 'enums/audit_row_seal.dart' as _i60;
import 'enums/consent_purpose.dart' as _i61;
import 'enums/data_subject_request_status.dart' as _i62;
import 'enums/data_subject_request_type.dart' as _i63;
import 'enums/escalation_reason.dart' as _i64;
import 'enums/risk_level.dart' as _i65;
import 'enums/scheduled_notice_status.dart' as _i66;
import 'enums/sync_status.dart' as _i67;
import 'enums/user_role.dart' as _i68;
import 'enums/visit_authorship.dart' as _i69;
import 'exceptions/admin_invalid_request_exception.dart' as _i70;
import 'exceptions/alert_dispatch_unavailable_exception.dart' as _i71;
import 'exceptions/alert_permission_exception.dart' as _i72;
import 'exceptions/alert_validation_exception.dart' as _i73;
import 'exceptions/authentication_failed_exception.dart' as _i74;
import 'exceptions/data_rights_exception.dart' as _i75;
import 'exceptions/endpoint_disabled_exception.dart' as _i76;
import 'exceptions/enrollment_exception.dart' as _i77;
import 'exceptions/mfa_enrollment_required_exception.dart' as _i78;
import 'exceptions/mfa_required_exception.dart' as _i79;
import 'exceptions/notice_delivery_exception.dart' as _i80;
import 'exceptions/otp_request_exception.dart' as _i81;
import 'exceptions/session_expired_exception.dart' as _i82;
import 'micro_area.dart' as _i83;
import 'otp_challenge.dart' as _i84;
import 'patient.dart' as _i85;
import 'push_token.dart' as _i86;
import 'scheduled_notice.dart' as _i87;
import 'staff_account.dart' as _i88;
import 'terms_version.dart' as _i89;
import 'triage_answer.dart' as _i90;
import 'triage_session.dart' as _i91;
import 'ubs.dart' as _i92;
import 'user.dart' as _i93;
import 'user_credential.dart' as _i94;
import 'visit.dart' as _i95;
import 'package:sinalacs_client/src/protocol/api/admin_micro_area.dart' as _i96;
import 'package:sinalacs_client/src/protocol/api/admin_acs.dart' as _i97;
import 'package:sinalacs_client/src/protocol/api/admin_staff.dart' as _i98;
import 'package:sinalacs_client/src/protocol/api/terms_version_entry.dart'
    as _i99;
import 'package:sinalacs_client/src/protocol/api/micro_area_patient.dart'
    as _i100;
import 'package:sinalacs_client/src/protocol/api/visit_sync_result.dart'
    as _i101;
import 'package:sinalacs_client/src/protocol/api/visit_sync_entry.dart'
    as _i102;
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
export 'api/admin_alerts_pulse.dart';
export 'api/admin_audit_chain_status.dart';
export 'api/admin_audit_entry.dart';
export 'api/admin_audit_export.dart';
export 'api/admin_audit_filter.dart';
export 'api/admin_audit_page.dart';
export 'api/admin_data_subject_request.dart';
export 'api/admin_data_subject_request_detail.dart';
export 'api/admin_data_subject_request_page.dart';
export 'api/admin_escalation_result.dart';
export 'api/admin_indicators.dart';
export 'api/admin_micro_area.dart';
export 'api/admin_password_reset_result.dart';
export 'api/admin_staff.dart';
export 'api/admin_staff_mfa_reset_result.dart';
export 'api/alert_ack_result.dart';
export 'api/alert_status_result.dart';
export 'api/development_login_result.dart';
export 'api/enrollment_result.dart';
export 'api/enrollment_token_result.dart';
export 'api/micro_area_patient.dart';
export 'api/notice_history_entry.dart';
export 'api/notice_history_page.dart';
export 'api/notice_send_result.dart';
export 'api/patient_consent_record.dart';
export 'api/patient_data_overview.dart';
export 'api/patient_data_subject_request_record.dart';
export 'api/patient_risk_event.dart';
export 'api/red_alert_result.dart';
export 'api/service_health.dart';
export 'api/terms_change_notice.dart';
export 'api/terms_version_entry.dart';
export 'api/totp_enrollment_start.dart';
export 'api/triage_result.dart';
export 'api/ubs_contact.dart';
export 'api/visit_sync_entry.dart';
export 'api/visit_sync_result.dart';
export 'audit_chain_checkpoint.dart';
export 'audit_export.dart';
export 'audit_log.dart';
export 'consent_log.dart';
export 'data_subject_request.dart';
export 'enrollment_token.dart';
export 'enums/alert_status.dart';
export 'enums/arrival_method.dart';
export 'enums/audit_chain_reason.dart';
export 'enums/audit_integrity_state.dart';
export 'enums/audit_row_seal.dart';
export 'enums/consent_purpose.dart';
export 'enums/data_subject_request_status.dart';
export 'enums/data_subject_request_type.dart';
export 'enums/escalation_reason.dart';
export 'enums/risk_level.dart';
export 'enums/scheduled_notice_status.dart';
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
export 'scheduled_notice.dart';
export 'staff_account.dart';
export 'terms_version.dart';
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
    if (t == _i13.AdminAlertsPulse) {
      return _i13.AdminAlertsPulse.fromJson(data) as T;
    }
    if (t == _i14.AdminAuditChainStatus) {
      return _i14.AdminAuditChainStatus.fromJson(data) as T;
    }
    if (t == _i15.AdminAuditEntry) {
      return _i15.AdminAuditEntry.fromJson(data) as T;
    }
    if (t == _i16.AdminAuditExport) {
      return _i16.AdminAuditExport.fromJson(data) as T;
    }
    if (t == _i17.AdminAuditFilter) {
      return _i17.AdminAuditFilter.fromJson(data) as T;
    }
    if (t == _i18.AdminAuditPage) {
      return _i18.AdminAuditPage.fromJson(data) as T;
    }
    if (t == _i19.AdminDataSubjectRequest) {
      return _i19.AdminDataSubjectRequest.fromJson(data) as T;
    }
    if (t == _i20.AdminDataSubjectRequestDetail) {
      return _i20.AdminDataSubjectRequestDetail.fromJson(data) as T;
    }
    if (t == _i21.AdminDataSubjectRequestPage) {
      return _i21.AdminDataSubjectRequestPage.fromJson(data) as T;
    }
    if (t == _i22.AdminEscalationResult) {
      return _i22.AdminEscalationResult.fromJson(data) as T;
    }
    if (t == _i23.AdminIndicators) {
      return _i23.AdminIndicators.fromJson(data) as T;
    }
    if (t == _i24.AdminMicroArea) {
      return _i24.AdminMicroArea.fromJson(data) as T;
    }
    if (t == _i25.AdminPasswordResetResult) {
      return _i25.AdminPasswordResetResult.fromJson(data) as T;
    }
    if (t == _i26.AdminStaff) {
      return _i26.AdminStaff.fromJson(data) as T;
    }
    if (t == _i27.AdminStaffMfaResetResult) {
      return _i27.AdminStaffMfaResetResult.fromJson(data) as T;
    }
    if (t == _i28.AlertAckResult) {
      return _i28.AlertAckResult.fromJson(data) as T;
    }
    if (t == _i29.AlertStatusResult) {
      return _i29.AlertStatusResult.fromJson(data) as T;
    }
    if (t == _i30.DevelopmentLoginResult) {
      return _i30.DevelopmentLoginResult.fromJson(data) as T;
    }
    if (t == _i31.EnrollmentResult) {
      return _i31.EnrollmentResult.fromJson(data) as T;
    }
    if (t == _i32.EnrollmentTokenResult) {
      return _i32.EnrollmentTokenResult.fromJson(data) as T;
    }
    if (t == _i33.MicroAreaPatient) {
      return _i33.MicroAreaPatient.fromJson(data) as T;
    }
    if (t == _i34.NoticeHistoryEntry) {
      return _i34.NoticeHistoryEntry.fromJson(data) as T;
    }
    if (t == _i35.NoticeHistoryPage) {
      return _i35.NoticeHistoryPage.fromJson(data) as T;
    }
    if (t == _i36.NoticeSendResult) {
      return _i36.NoticeSendResult.fromJson(data) as T;
    }
    if (t == _i37.PatientConsentRecord) {
      return _i37.PatientConsentRecord.fromJson(data) as T;
    }
    if (t == _i38.PatientDataOverview) {
      return _i38.PatientDataOverview.fromJson(data) as T;
    }
    if (t == _i39.PatientDataSubjectRequestRecord) {
      return _i39.PatientDataSubjectRequestRecord.fromJson(data) as T;
    }
    if (t == _i40.PatientRiskEvent) {
      return _i40.PatientRiskEvent.fromJson(data) as T;
    }
    if (t == _i41.RedAlertResult) {
      return _i41.RedAlertResult.fromJson(data) as T;
    }
    if (t == _i42.ServiceHealth) {
      return _i42.ServiceHealth.fromJson(data) as T;
    }
    if (t == _i43.TermsChangeNotice) {
      return _i43.TermsChangeNotice.fromJson(data) as T;
    }
    if (t == _i44.TermsVersionEntry) {
      return _i44.TermsVersionEntry.fromJson(data) as T;
    }
    if (t == _i45.TotpEnrollmentStart) {
      return _i45.TotpEnrollmentStart.fromJson(data) as T;
    }
    if (t == _i46.TriageResult) {
      return _i46.TriageResult.fromJson(data) as T;
    }
    if (t == _i47.UbsContact) {
      return _i47.UbsContact.fromJson(data) as T;
    }
    if (t == _i48.VisitSyncEntry) {
      return _i48.VisitSyncEntry.fromJson(data) as T;
    }
    if (t == _i49.VisitSyncResult) {
      return _i49.VisitSyncResult.fromJson(data) as T;
    }
    if (t == _i50.AuditChainCheckpoint) {
      return _i50.AuditChainCheckpoint.fromJson(data) as T;
    }
    if (t == _i51.AuditExport) {
      return _i51.AuditExport.fromJson(data) as T;
    }
    if (t == _i52.AuditLog) {
      return _i52.AuditLog.fromJson(data) as T;
    }
    if (t == _i53.ConsentLog) {
      return _i53.ConsentLog.fromJson(data) as T;
    }
    if (t == _i54.DataSubjectRequest) {
      return _i54.DataSubjectRequest.fromJson(data) as T;
    }
    if (t == _i55.EnrollmentToken) {
      return _i55.EnrollmentToken.fromJson(data) as T;
    }
    if (t == _i56.AlertStatus) {
      return _i56.AlertStatus.fromJson(data) as T;
    }
    if (t == _i57.ArrivalMethod) {
      return _i57.ArrivalMethod.fromJson(data) as T;
    }
    if (t == _i58.AuditChainReason) {
      return _i58.AuditChainReason.fromJson(data) as T;
    }
    if (t == _i59.AuditIntegrityState) {
      return _i59.AuditIntegrityState.fromJson(data) as T;
    }
    if (t == _i60.AuditRowSeal) {
      return _i60.AuditRowSeal.fromJson(data) as T;
    }
    if (t == _i61.ConsentPurpose) {
      return _i61.ConsentPurpose.fromJson(data) as T;
    }
    if (t == _i62.DataSubjectRequestStatus) {
      return _i62.DataSubjectRequestStatus.fromJson(data) as T;
    }
    if (t == _i63.DataSubjectRequestType) {
      return _i63.DataSubjectRequestType.fromJson(data) as T;
    }
    if (t == _i64.EscalationReason) {
      return _i64.EscalationReason.fromJson(data) as T;
    }
    if (t == _i65.RiskLevel) {
      return _i65.RiskLevel.fromJson(data) as T;
    }
    if (t == _i66.ScheduledNoticeStatus) {
      return _i66.ScheduledNoticeStatus.fromJson(data) as T;
    }
    if (t == _i67.SyncStatus) {
      return _i67.SyncStatus.fromJson(data) as T;
    }
    if (t == _i68.UserRole) {
      return _i68.UserRole.fromJson(data) as T;
    }
    if (t == _i69.VisitAuthorship) {
      return _i69.VisitAuthorship.fromJson(data) as T;
    }
    if (t == _i70.AdminInvalidRequestException) {
      return _i70.AdminInvalidRequestException.fromJson(data) as T;
    }
    if (t == _i71.AlertDispatchUnavailableException) {
      return _i71.AlertDispatchUnavailableException.fromJson(data) as T;
    }
    if (t == _i72.AlertPermissionException) {
      return _i72.AlertPermissionException.fromJson(data) as T;
    }
    if (t == _i73.AlertValidationException) {
      return _i73.AlertValidationException.fromJson(data) as T;
    }
    if (t == _i74.AuthenticationFailedException) {
      return _i74.AuthenticationFailedException.fromJson(data) as T;
    }
    if (t == _i75.DataRightsException) {
      return _i75.DataRightsException.fromJson(data) as T;
    }
    if (t == _i76.EndpointDisabledException) {
      return _i76.EndpointDisabledException.fromJson(data) as T;
    }
    if (t == _i77.EnrollmentException) {
      return _i77.EnrollmentException.fromJson(data) as T;
    }
    if (t == _i78.MfaEnrollmentRequiredException) {
      return _i78.MfaEnrollmentRequiredException.fromJson(data) as T;
    }
    if (t == _i79.MfaRequiredException) {
      return _i79.MfaRequiredException.fromJson(data) as T;
    }
    if (t == _i80.NoticeDeliveryException) {
      return _i80.NoticeDeliveryException.fromJson(data) as T;
    }
    if (t == _i81.OtpRequestException) {
      return _i81.OtpRequestException.fromJson(data) as T;
    }
    if (t == _i82.SessionExpiredException) {
      return _i82.SessionExpiredException.fromJson(data) as T;
    }
    if (t == _i83.MicroArea) {
      return _i83.MicroArea.fromJson(data) as T;
    }
    if (t == _i84.OtpChallenge) {
      return _i84.OtpChallenge.fromJson(data) as T;
    }
    if (t == _i85.Patient) {
      return _i85.Patient.fromJson(data) as T;
    }
    if (t == _i86.PushToken) {
      return _i86.PushToken.fromJson(data) as T;
    }
    if (t == _i87.ScheduledNotice) {
      return _i87.ScheduledNotice.fromJson(data) as T;
    }
    if (t == _i88.StaffAccount) {
      return _i88.StaffAccount.fromJson(data) as T;
    }
    if (t == _i89.TermsVersion) {
      return _i89.TermsVersion.fromJson(data) as T;
    }
    if (t == _i90.TriageAnswer) {
      return _i90.TriageAnswer.fromJson(data) as T;
    }
    if (t == _i91.TriageSession) {
      return _i91.TriageSession.fromJson(data) as T;
    }
    if (t == _i92.Ubs) {
      return _i92.Ubs.fromJson(data) as T;
    }
    if (t == _i93.User) {
      return _i93.User.fromJson(data) as T;
    }
    if (t == _i94.UserCredential) {
      return _i94.UserCredential.fromJson(data) as T;
    }
    if (t == _i95.Visit) {
      return _i95.Visit.fromJson(data) as T;
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
    if (t == _i1.getType<_i13.AdminAlertsPulse?>()) {
      return (data != null ? _i13.AdminAlertsPulse.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i14.AdminAuditChainStatus?>()) {
      return (data != null ? _i14.AdminAuditChainStatus.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i15.AdminAuditEntry?>()) {
      return (data != null ? _i15.AdminAuditEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i16.AdminAuditExport?>()) {
      return (data != null ? _i16.AdminAuditExport.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i17.AdminAuditFilter?>()) {
      return (data != null ? _i17.AdminAuditFilter.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i18.AdminAuditPage?>()) {
      return (data != null ? _i18.AdminAuditPage.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i19.AdminDataSubjectRequest?>()) {
      return (data != null ? _i19.AdminDataSubjectRequest.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i20.AdminDataSubjectRequestDetail?>()) {
      return (data != null
              ? _i20.AdminDataSubjectRequestDetail.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i21.AdminDataSubjectRequestPage?>()) {
      return (data != null
              ? _i21.AdminDataSubjectRequestPage.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i22.AdminEscalationResult?>()) {
      return (data != null ? _i22.AdminEscalationResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i23.AdminIndicators?>()) {
      return (data != null ? _i23.AdminIndicators.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i24.AdminMicroArea?>()) {
      return (data != null ? _i24.AdminMicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i25.AdminPasswordResetResult?>()) {
      return (data != null
              ? _i25.AdminPasswordResetResult.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i26.AdminStaff?>()) {
      return (data != null ? _i26.AdminStaff.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i27.AdminStaffMfaResetResult?>()) {
      return (data != null
              ? _i27.AdminStaffMfaResetResult.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i28.AlertAckResult?>()) {
      return (data != null ? _i28.AlertAckResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i29.AlertStatusResult?>()) {
      return (data != null ? _i29.AlertStatusResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i30.DevelopmentLoginResult?>()) {
      return (data != null ? _i30.DevelopmentLoginResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i31.EnrollmentResult?>()) {
      return (data != null ? _i31.EnrollmentResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i32.EnrollmentTokenResult?>()) {
      return (data != null ? _i32.EnrollmentTokenResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i33.MicroAreaPatient?>()) {
      return (data != null ? _i33.MicroAreaPatient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i34.NoticeHistoryEntry?>()) {
      return (data != null ? _i34.NoticeHistoryEntry.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i35.NoticeHistoryPage?>()) {
      return (data != null ? _i35.NoticeHistoryPage.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i36.NoticeSendResult?>()) {
      return (data != null ? _i36.NoticeSendResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i37.PatientConsentRecord?>()) {
      return (data != null ? _i37.PatientConsentRecord.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i38.PatientDataOverview?>()) {
      return (data != null ? _i38.PatientDataOverview.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i39.PatientDataSubjectRequestRecord?>()) {
      return (data != null
              ? _i39.PatientDataSubjectRequestRecord.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i40.PatientRiskEvent?>()) {
      return (data != null ? _i40.PatientRiskEvent.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i41.RedAlertResult?>()) {
      return (data != null ? _i41.RedAlertResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i42.ServiceHealth?>()) {
      return (data != null ? _i42.ServiceHealth.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i43.TermsChangeNotice?>()) {
      return (data != null ? _i43.TermsChangeNotice.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i44.TermsVersionEntry?>()) {
      return (data != null ? _i44.TermsVersionEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i45.TotpEnrollmentStart?>()) {
      return (data != null ? _i45.TotpEnrollmentStart.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i46.TriageResult?>()) {
      return (data != null ? _i46.TriageResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i47.UbsContact?>()) {
      return (data != null ? _i47.UbsContact.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i48.VisitSyncEntry?>()) {
      return (data != null ? _i48.VisitSyncEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i49.VisitSyncResult?>()) {
      return (data != null ? _i49.VisitSyncResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i50.AuditChainCheckpoint?>()) {
      return (data != null ? _i50.AuditChainCheckpoint.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i51.AuditExport?>()) {
      return (data != null ? _i51.AuditExport.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i52.AuditLog?>()) {
      return (data != null ? _i52.AuditLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i53.ConsentLog?>()) {
      return (data != null ? _i53.ConsentLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i54.DataSubjectRequest?>()) {
      return (data != null ? _i54.DataSubjectRequest.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i55.EnrollmentToken?>()) {
      return (data != null ? _i55.EnrollmentToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i56.AlertStatus?>()) {
      return (data != null ? _i56.AlertStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i57.ArrivalMethod?>()) {
      return (data != null ? _i57.ArrivalMethod.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i58.AuditChainReason?>()) {
      return (data != null ? _i58.AuditChainReason.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i59.AuditIntegrityState?>()) {
      return (data != null ? _i59.AuditIntegrityState.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i60.AuditRowSeal?>()) {
      return (data != null ? _i60.AuditRowSeal.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i61.ConsentPurpose?>()) {
      return (data != null ? _i61.ConsentPurpose.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i62.DataSubjectRequestStatus?>()) {
      return (data != null
              ? _i62.DataSubjectRequestStatus.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i63.DataSubjectRequestType?>()) {
      return (data != null ? _i63.DataSubjectRequestType.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i64.EscalationReason?>()) {
      return (data != null ? _i64.EscalationReason.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i65.RiskLevel?>()) {
      return (data != null ? _i65.RiskLevel.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i66.ScheduledNoticeStatus?>()) {
      return (data != null ? _i66.ScheduledNoticeStatus.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i67.SyncStatus?>()) {
      return (data != null ? _i67.SyncStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i68.UserRole?>()) {
      return (data != null ? _i68.UserRole.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i69.VisitAuthorship?>()) {
      return (data != null ? _i69.VisitAuthorship.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i70.AdminInvalidRequestException?>()) {
      return (data != null
              ? _i70.AdminInvalidRequestException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i71.AlertDispatchUnavailableException?>()) {
      return (data != null
              ? _i71.AlertDispatchUnavailableException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i72.AlertPermissionException?>()) {
      return (data != null
              ? _i72.AlertPermissionException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i73.AlertValidationException?>()) {
      return (data != null
              ? _i73.AlertValidationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i74.AuthenticationFailedException?>()) {
      return (data != null
              ? _i74.AuthenticationFailedException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i75.DataRightsException?>()) {
      return (data != null ? _i75.DataRightsException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i76.EndpointDisabledException?>()) {
      return (data != null
              ? _i76.EndpointDisabledException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i77.EnrollmentException?>()) {
      return (data != null ? _i77.EnrollmentException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i78.MfaEnrollmentRequiredException?>()) {
      return (data != null
              ? _i78.MfaEnrollmentRequiredException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i79.MfaRequiredException?>()) {
      return (data != null ? _i79.MfaRequiredException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i80.NoticeDeliveryException?>()) {
      return (data != null ? _i80.NoticeDeliveryException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i81.OtpRequestException?>()) {
      return (data != null ? _i81.OtpRequestException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i82.SessionExpiredException?>()) {
      return (data != null ? _i82.SessionExpiredException.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i83.MicroArea?>()) {
      return (data != null ? _i83.MicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i84.OtpChallenge?>()) {
      return (data != null ? _i84.OtpChallenge.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i85.Patient?>()) {
      return (data != null ? _i85.Patient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i86.PushToken?>()) {
      return (data != null ? _i86.PushToken.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i87.ScheduledNotice?>()) {
      return (data != null ? _i87.ScheduledNotice.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i88.StaffAccount?>()) {
      return (data != null ? _i88.StaffAccount.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i89.TermsVersion?>()) {
      return (data != null ? _i89.TermsVersion.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i90.TriageAnswer?>()) {
      return (data != null ? _i90.TriageAnswer.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i91.TriageSession?>()) {
      return (data != null ? _i91.TriageSession.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i92.Ubs?>()) {
      return (data != null ? _i92.Ubs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i93.User?>()) {
      return (data != null ? _i93.User.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i94.UserCredential?>()) {
      return (data != null ? _i94.UserCredential.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i95.Visit?>()) {
      return (data != null ? _i95.Visit.fromJson(data) : null) as T;
    }
    if (t == List<_i11.AdminAlert>) {
      return (data as List).map((e) => deserialize<_i11.AdminAlert>(e)).toList()
          as T;
    }
    if (t == List<_i15.AdminAuditEntry>) {
      return (data as List)
              .map((e) => deserialize<_i15.AdminAuditEntry>(e))
              .toList()
          as T;
    }
    if (t == List<_i19.AdminDataSubjectRequest>) {
      return (data as List)
              .map((e) => deserialize<_i19.AdminDataSubjectRequest>(e))
              .toList()
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i34.NoticeHistoryEntry>) {
      return (data as List)
              .map((e) => deserialize<_i34.NoticeHistoryEntry>(e))
              .toList()
          as T;
    }
    if (t == List<_i37.PatientConsentRecord>) {
      return (data as List)
              .map((e) => deserialize<_i37.PatientConsentRecord>(e))
              .toList()
          as T;
    }
    if (t == List<_i40.PatientRiskEvent>) {
      return (data as List)
              .map((e) => deserialize<_i40.PatientRiskEvent>(e))
              .toList()
          as T;
    }
    if (t == List<_i39.PatientDataSubjectRequestRecord>) {
      return (data as List)
              .map((e) => deserialize<_i39.PatientDataSubjectRequestRecord>(e))
              .toList()
          as T;
    }
    if (t == Map<String, String>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<String>(v)),
          )
          as T;
    }
    if (t == List<_i96.AdminMicroArea>) {
      return (data as List)
              .map((e) => deserialize<_i96.AdminMicroArea>(e))
              .toList()
          as T;
    }
    if (t == List<_i97.AdminAcs>) {
      return (data as List).map((e) => deserialize<_i97.AdminAcs>(e)).toList()
          as T;
    }
    if (t == List<_i98.AdminStaff>) {
      return (data as List).map((e) => deserialize<_i98.AdminStaff>(e)).toList()
          as T;
    }
    if (t == List<_i99.TermsVersionEntry>) {
      return (data as List)
              .map((e) => deserialize<_i99.TermsVersionEntry>(e))
              .toList()
          as T;
    }
    if (t == List<_i100.MicroAreaPatient>) {
      return (data as List)
              .map((e) => deserialize<_i100.MicroAreaPatient>(e))
              .toList()
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i101.VisitSyncResult>) {
      return (data as List)
              .map((e) => deserialize<_i101.VisitSyncResult>(e))
              .toList()
          as T;
    }
    if (t == List<_i102.VisitSyncEntry>) {
      return (data as List)
              .map((e) => deserialize<_i102.VisitSyncEntry>(e))
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
      _i13.AdminAlertsPulse => 'AdminAlertsPulse',
      _i14.AdminAuditChainStatus => 'AdminAuditChainStatus',
      _i15.AdminAuditEntry => 'AdminAuditEntry',
      _i16.AdminAuditExport => 'AdminAuditExport',
      _i17.AdminAuditFilter => 'AdminAuditFilter',
      _i18.AdminAuditPage => 'AdminAuditPage',
      _i19.AdminDataSubjectRequest => 'AdminDataSubjectRequest',
      _i20.AdminDataSubjectRequestDetail => 'AdminDataSubjectRequestDetail',
      _i21.AdminDataSubjectRequestPage => 'AdminDataSubjectRequestPage',
      _i22.AdminEscalationResult => 'AdminEscalationResult',
      _i23.AdminIndicators => 'AdminIndicators',
      _i24.AdminMicroArea => 'AdminMicroArea',
      _i25.AdminPasswordResetResult => 'AdminPasswordResetResult',
      _i26.AdminStaff => 'AdminStaff',
      _i27.AdminStaffMfaResetResult => 'AdminStaffMfaResetResult',
      _i28.AlertAckResult => 'AlertAckResult',
      _i29.AlertStatusResult => 'AlertStatusResult',
      _i30.DevelopmentLoginResult => 'DevelopmentLoginResult',
      _i31.EnrollmentResult => 'EnrollmentResult',
      _i32.EnrollmentTokenResult => 'EnrollmentTokenResult',
      _i33.MicroAreaPatient => 'MicroAreaPatient',
      _i34.NoticeHistoryEntry => 'NoticeHistoryEntry',
      _i35.NoticeHistoryPage => 'NoticeHistoryPage',
      _i36.NoticeSendResult => 'NoticeSendResult',
      _i37.PatientConsentRecord => 'PatientConsentRecord',
      _i38.PatientDataOverview => 'PatientDataOverview',
      _i39.PatientDataSubjectRequestRecord => 'PatientDataSubjectRequestRecord',
      _i40.PatientRiskEvent => 'PatientRiskEvent',
      _i41.RedAlertResult => 'RedAlertResult',
      _i42.ServiceHealth => 'ServiceHealth',
      _i43.TermsChangeNotice => 'TermsChangeNotice',
      _i44.TermsVersionEntry => 'TermsVersionEntry',
      _i45.TotpEnrollmentStart => 'TotpEnrollmentStart',
      _i46.TriageResult => 'TriageResult',
      _i47.UbsContact => 'UbsContact',
      _i48.VisitSyncEntry => 'VisitSyncEntry',
      _i49.VisitSyncResult => 'VisitSyncResult',
      _i50.AuditChainCheckpoint => 'AuditChainCheckpoint',
      _i51.AuditExport => 'AuditExport',
      _i52.AuditLog => 'AuditLog',
      _i53.ConsentLog => 'ConsentLog',
      _i54.DataSubjectRequest => 'DataSubjectRequest',
      _i55.EnrollmentToken => 'EnrollmentToken',
      _i56.AlertStatus => 'AlertStatus',
      _i57.ArrivalMethod => 'ArrivalMethod',
      _i58.AuditChainReason => 'AuditChainReason',
      _i59.AuditIntegrityState => 'AuditIntegrityState',
      _i60.AuditRowSeal => 'AuditRowSeal',
      _i61.ConsentPurpose => 'ConsentPurpose',
      _i62.DataSubjectRequestStatus => 'DataSubjectRequestStatus',
      _i63.DataSubjectRequestType => 'DataSubjectRequestType',
      _i64.EscalationReason => 'EscalationReason',
      _i65.RiskLevel => 'RiskLevel',
      _i66.ScheduledNoticeStatus => 'ScheduledNoticeStatus',
      _i67.SyncStatus => 'SyncStatus',
      _i68.UserRole => 'UserRole',
      _i69.VisitAuthorship => 'VisitAuthorship',
      _i70.AdminInvalidRequestException => 'AdminInvalidRequestException',
      _i71.AlertDispatchUnavailableException =>
        'AlertDispatchUnavailableException',
      _i72.AlertPermissionException => 'AlertPermissionException',
      _i73.AlertValidationException => 'AlertValidationException',
      _i74.AuthenticationFailedException => 'AuthenticationFailedException',
      _i75.DataRightsException => 'DataRightsException',
      _i76.EndpointDisabledException => 'EndpointDisabledException',
      _i77.EnrollmentException => 'EnrollmentException',
      _i78.MfaEnrollmentRequiredException => 'MfaEnrollmentRequiredException',
      _i79.MfaRequiredException => 'MfaRequiredException',
      _i80.NoticeDeliveryException => 'NoticeDeliveryException',
      _i81.OtpRequestException => 'OtpRequestException',
      _i82.SessionExpiredException => 'SessionExpiredException',
      _i83.MicroArea => 'MicroArea',
      _i84.OtpChallenge => 'OtpChallenge',
      _i85.Patient => 'Patient',
      _i86.PushToken => 'PushToken',
      _i87.ScheduledNotice => 'ScheduledNotice',
      _i88.StaffAccount => 'StaffAccount',
      _i89.TermsVersion => 'TermsVersion',
      _i90.TriageAnswer => 'TriageAnswer',
      _i91.TriageSession => 'TriageSession',
      _i92.Ubs => 'Ubs',
      _i93.User => 'User',
      _i94.UserCredential => 'UserCredential',
      _i95.Visit => 'Visit',
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
      case _i13.AdminAlertsPulse():
        return 'AdminAlertsPulse';
      case _i14.AdminAuditChainStatus():
        return 'AdminAuditChainStatus';
      case _i15.AdminAuditEntry():
        return 'AdminAuditEntry';
      case _i16.AdminAuditExport():
        return 'AdminAuditExport';
      case _i17.AdminAuditFilter():
        return 'AdminAuditFilter';
      case _i18.AdminAuditPage():
        return 'AdminAuditPage';
      case _i19.AdminDataSubjectRequest():
        return 'AdminDataSubjectRequest';
      case _i20.AdminDataSubjectRequestDetail():
        return 'AdminDataSubjectRequestDetail';
      case _i21.AdminDataSubjectRequestPage():
        return 'AdminDataSubjectRequestPage';
      case _i22.AdminEscalationResult():
        return 'AdminEscalationResult';
      case _i23.AdminIndicators():
        return 'AdminIndicators';
      case _i24.AdminMicroArea():
        return 'AdminMicroArea';
      case _i25.AdminPasswordResetResult():
        return 'AdminPasswordResetResult';
      case _i26.AdminStaff():
        return 'AdminStaff';
      case _i27.AdminStaffMfaResetResult():
        return 'AdminStaffMfaResetResult';
      case _i28.AlertAckResult():
        return 'AlertAckResult';
      case _i29.AlertStatusResult():
        return 'AlertStatusResult';
      case _i30.DevelopmentLoginResult():
        return 'DevelopmentLoginResult';
      case _i31.EnrollmentResult():
        return 'EnrollmentResult';
      case _i32.EnrollmentTokenResult():
        return 'EnrollmentTokenResult';
      case _i33.MicroAreaPatient():
        return 'MicroAreaPatient';
      case _i34.NoticeHistoryEntry():
        return 'NoticeHistoryEntry';
      case _i35.NoticeHistoryPage():
        return 'NoticeHistoryPage';
      case _i36.NoticeSendResult():
        return 'NoticeSendResult';
      case _i37.PatientConsentRecord():
        return 'PatientConsentRecord';
      case _i38.PatientDataOverview():
        return 'PatientDataOverview';
      case _i39.PatientDataSubjectRequestRecord():
        return 'PatientDataSubjectRequestRecord';
      case _i40.PatientRiskEvent():
        return 'PatientRiskEvent';
      case _i41.RedAlertResult():
        return 'RedAlertResult';
      case _i42.ServiceHealth():
        return 'ServiceHealth';
      case _i43.TermsChangeNotice():
        return 'TermsChangeNotice';
      case _i44.TermsVersionEntry():
        return 'TermsVersionEntry';
      case _i45.TotpEnrollmentStart():
        return 'TotpEnrollmentStart';
      case _i46.TriageResult():
        return 'TriageResult';
      case _i47.UbsContact():
        return 'UbsContact';
      case _i48.VisitSyncEntry():
        return 'VisitSyncEntry';
      case _i49.VisitSyncResult():
        return 'VisitSyncResult';
      case _i50.AuditChainCheckpoint():
        return 'AuditChainCheckpoint';
      case _i51.AuditExport():
        return 'AuditExport';
      case _i52.AuditLog():
        return 'AuditLog';
      case _i53.ConsentLog():
        return 'ConsentLog';
      case _i54.DataSubjectRequest():
        return 'DataSubjectRequest';
      case _i55.EnrollmentToken():
        return 'EnrollmentToken';
      case _i56.AlertStatus():
        return 'AlertStatus';
      case _i57.ArrivalMethod():
        return 'ArrivalMethod';
      case _i58.AuditChainReason():
        return 'AuditChainReason';
      case _i59.AuditIntegrityState():
        return 'AuditIntegrityState';
      case _i60.AuditRowSeal():
        return 'AuditRowSeal';
      case _i61.ConsentPurpose():
        return 'ConsentPurpose';
      case _i62.DataSubjectRequestStatus():
        return 'DataSubjectRequestStatus';
      case _i63.DataSubjectRequestType():
        return 'DataSubjectRequestType';
      case _i64.EscalationReason():
        return 'EscalationReason';
      case _i65.RiskLevel():
        return 'RiskLevel';
      case _i66.ScheduledNoticeStatus():
        return 'ScheduledNoticeStatus';
      case _i67.SyncStatus():
        return 'SyncStatus';
      case _i68.UserRole():
        return 'UserRole';
      case _i69.VisitAuthorship():
        return 'VisitAuthorship';
      case _i70.AdminInvalidRequestException():
        return 'AdminInvalidRequestException';
      case _i71.AlertDispatchUnavailableException():
        return 'AlertDispatchUnavailableException';
      case _i72.AlertPermissionException():
        return 'AlertPermissionException';
      case _i73.AlertValidationException():
        return 'AlertValidationException';
      case _i74.AuthenticationFailedException():
        return 'AuthenticationFailedException';
      case _i75.DataRightsException():
        return 'DataRightsException';
      case _i76.EndpointDisabledException():
        return 'EndpointDisabledException';
      case _i77.EnrollmentException():
        return 'EnrollmentException';
      case _i78.MfaEnrollmentRequiredException():
        return 'MfaEnrollmentRequiredException';
      case _i79.MfaRequiredException():
        return 'MfaRequiredException';
      case _i80.NoticeDeliveryException():
        return 'NoticeDeliveryException';
      case _i81.OtpRequestException():
        return 'OtpRequestException';
      case _i82.SessionExpiredException():
        return 'SessionExpiredException';
      case _i83.MicroArea():
        return 'MicroArea';
      case _i84.OtpChallenge():
        return 'OtpChallenge';
      case _i85.Patient():
        return 'Patient';
      case _i86.PushToken():
        return 'PushToken';
      case _i87.ScheduledNotice():
        return 'ScheduledNotice';
      case _i88.StaffAccount():
        return 'StaffAccount';
      case _i89.TermsVersion():
        return 'TermsVersion';
      case _i90.TriageAnswer():
        return 'TriageAnswer';
      case _i91.TriageSession():
        return 'TriageSession';
      case _i92.Ubs():
        return 'Ubs';
      case _i93.User():
        return 'User';
      case _i94.UserCredential():
        return 'UserCredential';
      case _i95.Visit():
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
    if (dataClassName == 'AdminAlertsPulse') {
      return deserialize<_i13.AdminAlertsPulse>(data['data']);
    }
    if (dataClassName == 'AdminAuditChainStatus') {
      return deserialize<_i14.AdminAuditChainStatus>(data['data']);
    }
    if (dataClassName == 'AdminAuditEntry') {
      return deserialize<_i15.AdminAuditEntry>(data['data']);
    }
    if (dataClassName == 'AdminAuditExport') {
      return deserialize<_i16.AdminAuditExport>(data['data']);
    }
    if (dataClassName == 'AdminAuditFilter') {
      return deserialize<_i17.AdminAuditFilter>(data['data']);
    }
    if (dataClassName == 'AdminAuditPage') {
      return deserialize<_i18.AdminAuditPage>(data['data']);
    }
    if (dataClassName == 'AdminDataSubjectRequest') {
      return deserialize<_i19.AdminDataSubjectRequest>(data['data']);
    }
    if (dataClassName == 'AdminDataSubjectRequestDetail') {
      return deserialize<_i20.AdminDataSubjectRequestDetail>(data['data']);
    }
    if (dataClassName == 'AdminDataSubjectRequestPage') {
      return deserialize<_i21.AdminDataSubjectRequestPage>(data['data']);
    }
    if (dataClassName == 'AdminEscalationResult') {
      return deserialize<_i22.AdminEscalationResult>(data['data']);
    }
    if (dataClassName == 'AdminIndicators') {
      return deserialize<_i23.AdminIndicators>(data['data']);
    }
    if (dataClassName == 'AdminMicroArea') {
      return deserialize<_i24.AdminMicroArea>(data['data']);
    }
    if (dataClassName == 'AdminPasswordResetResult') {
      return deserialize<_i25.AdminPasswordResetResult>(data['data']);
    }
    if (dataClassName == 'AdminStaff') {
      return deserialize<_i26.AdminStaff>(data['data']);
    }
    if (dataClassName == 'AdminStaffMfaResetResult') {
      return deserialize<_i27.AdminStaffMfaResetResult>(data['data']);
    }
    if (dataClassName == 'AlertAckResult') {
      return deserialize<_i28.AlertAckResult>(data['data']);
    }
    if (dataClassName == 'AlertStatusResult') {
      return deserialize<_i29.AlertStatusResult>(data['data']);
    }
    if (dataClassName == 'DevelopmentLoginResult') {
      return deserialize<_i30.DevelopmentLoginResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentResult') {
      return deserialize<_i31.EnrollmentResult>(data['data']);
    }
    if (dataClassName == 'EnrollmentTokenResult') {
      return deserialize<_i32.EnrollmentTokenResult>(data['data']);
    }
    if (dataClassName == 'MicroAreaPatient') {
      return deserialize<_i33.MicroAreaPatient>(data['data']);
    }
    if (dataClassName == 'NoticeHistoryEntry') {
      return deserialize<_i34.NoticeHistoryEntry>(data['data']);
    }
    if (dataClassName == 'NoticeHistoryPage') {
      return deserialize<_i35.NoticeHistoryPage>(data['data']);
    }
    if (dataClassName == 'NoticeSendResult') {
      return deserialize<_i36.NoticeSendResult>(data['data']);
    }
    if (dataClassName == 'PatientConsentRecord') {
      return deserialize<_i37.PatientConsentRecord>(data['data']);
    }
    if (dataClassName == 'PatientDataOverview') {
      return deserialize<_i38.PatientDataOverview>(data['data']);
    }
    if (dataClassName == 'PatientDataSubjectRequestRecord') {
      return deserialize<_i39.PatientDataSubjectRequestRecord>(data['data']);
    }
    if (dataClassName == 'PatientRiskEvent') {
      return deserialize<_i40.PatientRiskEvent>(data['data']);
    }
    if (dataClassName == 'RedAlertResult') {
      return deserialize<_i41.RedAlertResult>(data['data']);
    }
    if (dataClassName == 'ServiceHealth') {
      return deserialize<_i42.ServiceHealth>(data['data']);
    }
    if (dataClassName == 'TermsChangeNotice') {
      return deserialize<_i43.TermsChangeNotice>(data['data']);
    }
    if (dataClassName == 'TermsVersionEntry') {
      return deserialize<_i44.TermsVersionEntry>(data['data']);
    }
    if (dataClassName == 'TotpEnrollmentStart') {
      return deserialize<_i45.TotpEnrollmentStart>(data['data']);
    }
    if (dataClassName == 'TriageResult') {
      return deserialize<_i46.TriageResult>(data['data']);
    }
    if (dataClassName == 'UbsContact') {
      return deserialize<_i47.UbsContact>(data['data']);
    }
    if (dataClassName == 'VisitSyncEntry') {
      return deserialize<_i48.VisitSyncEntry>(data['data']);
    }
    if (dataClassName == 'VisitSyncResult') {
      return deserialize<_i49.VisitSyncResult>(data['data']);
    }
    if (dataClassName == 'AuditChainCheckpoint') {
      return deserialize<_i50.AuditChainCheckpoint>(data['data']);
    }
    if (dataClassName == 'AuditExport') {
      return deserialize<_i51.AuditExport>(data['data']);
    }
    if (dataClassName == 'AuditLog') {
      return deserialize<_i52.AuditLog>(data['data']);
    }
    if (dataClassName == 'ConsentLog') {
      return deserialize<_i53.ConsentLog>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequest') {
      return deserialize<_i54.DataSubjectRequest>(data['data']);
    }
    if (dataClassName == 'EnrollmentToken') {
      return deserialize<_i55.EnrollmentToken>(data['data']);
    }
    if (dataClassName == 'AlertStatus') {
      return deserialize<_i56.AlertStatus>(data['data']);
    }
    if (dataClassName == 'ArrivalMethod') {
      return deserialize<_i57.ArrivalMethod>(data['data']);
    }
    if (dataClassName == 'AuditChainReason') {
      return deserialize<_i58.AuditChainReason>(data['data']);
    }
    if (dataClassName == 'AuditIntegrityState') {
      return deserialize<_i59.AuditIntegrityState>(data['data']);
    }
    if (dataClassName == 'AuditRowSeal') {
      return deserialize<_i60.AuditRowSeal>(data['data']);
    }
    if (dataClassName == 'ConsentPurpose') {
      return deserialize<_i61.ConsentPurpose>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestStatus') {
      return deserialize<_i62.DataSubjectRequestStatus>(data['data']);
    }
    if (dataClassName == 'DataSubjectRequestType') {
      return deserialize<_i63.DataSubjectRequestType>(data['data']);
    }
    if (dataClassName == 'EscalationReason') {
      return deserialize<_i64.EscalationReason>(data['data']);
    }
    if (dataClassName == 'RiskLevel') {
      return deserialize<_i65.RiskLevel>(data['data']);
    }
    if (dataClassName == 'ScheduledNoticeStatus') {
      return deserialize<_i66.ScheduledNoticeStatus>(data['data']);
    }
    if (dataClassName == 'SyncStatus') {
      return deserialize<_i67.SyncStatus>(data['data']);
    }
    if (dataClassName == 'UserRole') {
      return deserialize<_i68.UserRole>(data['data']);
    }
    if (dataClassName == 'VisitAuthorship') {
      return deserialize<_i69.VisitAuthorship>(data['data']);
    }
    if (dataClassName == 'AdminInvalidRequestException') {
      return deserialize<_i70.AdminInvalidRequestException>(data['data']);
    }
    if (dataClassName == 'AlertDispatchUnavailableException') {
      return deserialize<_i71.AlertDispatchUnavailableException>(data['data']);
    }
    if (dataClassName == 'AlertPermissionException') {
      return deserialize<_i72.AlertPermissionException>(data['data']);
    }
    if (dataClassName == 'AlertValidationException') {
      return deserialize<_i73.AlertValidationException>(data['data']);
    }
    if (dataClassName == 'AuthenticationFailedException') {
      return deserialize<_i74.AuthenticationFailedException>(data['data']);
    }
    if (dataClassName == 'DataRightsException') {
      return deserialize<_i75.DataRightsException>(data['data']);
    }
    if (dataClassName == 'EndpointDisabledException') {
      return deserialize<_i76.EndpointDisabledException>(data['data']);
    }
    if (dataClassName == 'EnrollmentException') {
      return deserialize<_i77.EnrollmentException>(data['data']);
    }
    if (dataClassName == 'MfaEnrollmentRequiredException') {
      return deserialize<_i78.MfaEnrollmentRequiredException>(data['data']);
    }
    if (dataClassName == 'MfaRequiredException') {
      return deserialize<_i79.MfaRequiredException>(data['data']);
    }
    if (dataClassName == 'NoticeDeliveryException') {
      return deserialize<_i80.NoticeDeliveryException>(data['data']);
    }
    if (dataClassName == 'OtpRequestException') {
      return deserialize<_i81.OtpRequestException>(data['data']);
    }
    if (dataClassName == 'SessionExpiredException') {
      return deserialize<_i82.SessionExpiredException>(data['data']);
    }
    if (dataClassName == 'MicroArea') {
      return deserialize<_i83.MicroArea>(data['data']);
    }
    if (dataClassName == 'OtpChallenge') {
      return deserialize<_i84.OtpChallenge>(data['data']);
    }
    if (dataClassName == 'Patient') {
      return deserialize<_i85.Patient>(data['data']);
    }
    if (dataClassName == 'PushToken') {
      return deserialize<_i86.PushToken>(data['data']);
    }
    if (dataClassName == 'ScheduledNotice') {
      return deserialize<_i87.ScheduledNotice>(data['data']);
    }
    if (dataClassName == 'StaffAccount') {
      return deserialize<_i88.StaffAccount>(data['data']);
    }
    if (dataClassName == 'TermsVersion') {
      return deserialize<_i89.TermsVersion>(data['data']);
    }
    if (dataClassName == 'TriageAnswer') {
      return deserialize<_i90.TriageAnswer>(data['data']);
    }
    if (dataClassName == 'TriageSession') {
      return deserialize<_i91.TriageSession>(data['data']);
    }
    if (dataClassName == 'Ubs') {
      return deserialize<_i92.Ubs>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i93.User>(data['data']);
    }
    if (dataClassName == 'UserCredential') {
      return deserialize<_i94.UserCredential>(data['data']);
    }
    if (dataClassName == 'Visit') {
      return deserialize<_i95.Visit>(data['data']);
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
