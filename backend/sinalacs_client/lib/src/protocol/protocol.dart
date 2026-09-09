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
import 'api/alert_ack_result.dart' as _i6;
import 'api/development_login_result.dart' as _i7;
import 'api/red_alert_result.dart' as _i8;
import 'api/service_health.dart' as _i9;
import 'api/triage_result.dart' as _i10;
import 'audit_log.dart' as _i11;
import 'consent_log.dart' as _i12;
import 'enums/alert_status.dart' as _i13;
import 'enums/risk_level.dart' as _i14;
import 'enums/sync_status.dart' as _i15;
import 'enums/user_role.dart' as _i16;
import 'exceptions/alert_dispatch_unavailable_exception.dart' as _i17;
import 'exceptions/alert_permission_exception.dart' as _i18;
import 'exceptions/alert_validation_exception.dart' as _i19;
import 'exceptions/endpoint_disabled_exception.dart' as _i20;
import 'micro_area.dart' as _i21;
import 'patient.dart' as _i22;
import 'triage_answer.dart' as _i23;
import 'triage_session.dart' as _i24;
import 'ubs.dart' as _i25;
import 'user.dart' as _i26;
import 'visit.dart' as _i27;
export 'acs.dart';
export 'alert.dart';
export 'alert_delivery_record.dart';
export 'alert_idempotency_key.dart';
export 'api/alert_ack_result.dart';
export 'api/development_login_result.dart';
export 'api/red_alert_result.dart';
export 'api/service_health.dart';
export 'api/triage_result.dart';
export 'audit_log.dart';
export 'consent_log.dart';
export 'enums/alert_status.dart';
export 'enums/risk_level.dart';
export 'enums/sync_status.dart';
export 'enums/user_role.dart';
export 'exceptions/alert_dispatch_unavailable_exception.dart';
export 'exceptions/alert_permission_exception.dart';
export 'exceptions/alert_validation_exception.dart';
export 'exceptions/endpoint_disabled_exception.dart';
export 'micro_area.dart';
export 'patient.dart';
export 'triage_answer.dart';
export 'triage_session.dart';
export 'ubs.dart';
export 'user.dart';
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
    if (t == _i6.AlertAckResult) {
      return _i6.AlertAckResult.fromJson(data) as T;
    }
    if (t == _i7.DevelopmentLoginResult) {
      return _i7.DevelopmentLoginResult.fromJson(data) as T;
    }
    if (t == _i8.RedAlertResult) {
      return _i8.RedAlertResult.fromJson(data) as T;
    }
    if (t == _i9.ServiceHealth) {
      return _i9.ServiceHealth.fromJson(data) as T;
    }
    if (t == _i10.TriageResult) {
      return _i10.TriageResult.fromJson(data) as T;
    }
    if (t == _i11.AuditLog) {
      return _i11.AuditLog.fromJson(data) as T;
    }
    if (t == _i12.ConsentLog) {
      return _i12.ConsentLog.fromJson(data) as T;
    }
    if (t == _i13.AlertStatus) {
      return _i13.AlertStatus.fromJson(data) as T;
    }
    if (t == _i14.RiskLevel) {
      return _i14.RiskLevel.fromJson(data) as T;
    }
    if (t == _i15.SyncStatus) {
      return _i15.SyncStatus.fromJson(data) as T;
    }
    if (t == _i16.UserRole) {
      return _i16.UserRole.fromJson(data) as T;
    }
    if (t == _i17.AlertDispatchUnavailableException) {
      return _i17.AlertDispatchUnavailableException.fromJson(data) as T;
    }
    if (t == _i18.AlertPermissionException) {
      return _i18.AlertPermissionException.fromJson(data) as T;
    }
    if (t == _i19.AlertValidationException) {
      return _i19.AlertValidationException.fromJson(data) as T;
    }
    if (t == _i20.EndpointDisabledException) {
      return _i20.EndpointDisabledException.fromJson(data) as T;
    }
    if (t == _i21.MicroArea) {
      return _i21.MicroArea.fromJson(data) as T;
    }
    if (t == _i22.Patient) {
      return _i22.Patient.fromJson(data) as T;
    }
    if (t == _i23.TriageAnswer) {
      return _i23.TriageAnswer.fromJson(data) as T;
    }
    if (t == _i24.TriageSession) {
      return _i24.TriageSession.fromJson(data) as T;
    }
    if (t == _i25.Ubs) {
      return _i25.Ubs.fromJson(data) as T;
    }
    if (t == _i26.User) {
      return _i26.User.fromJson(data) as T;
    }
    if (t == _i27.Visit) {
      return _i27.Visit.fromJson(data) as T;
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
    if (t == _i1.getType<_i6.AlertAckResult?>()) {
      return (data != null ? _i6.AlertAckResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i7.DevelopmentLoginResult?>()) {
      return (data != null ? _i7.DevelopmentLoginResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i8.RedAlertResult?>()) {
      return (data != null ? _i8.RedAlertResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i9.ServiceHealth?>()) {
      return (data != null ? _i9.ServiceHealth.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i10.TriageResult?>()) {
      return (data != null ? _i10.TriageResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i11.AuditLog?>()) {
      return (data != null ? _i11.AuditLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i12.ConsentLog?>()) {
      return (data != null ? _i12.ConsentLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i13.AlertStatus?>()) {
      return (data != null ? _i13.AlertStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i14.RiskLevel?>()) {
      return (data != null ? _i14.RiskLevel.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i15.SyncStatus?>()) {
      return (data != null ? _i15.SyncStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i16.UserRole?>()) {
      return (data != null ? _i16.UserRole.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i17.AlertDispatchUnavailableException?>()) {
      return (data != null
              ? _i17.AlertDispatchUnavailableException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i18.AlertPermissionException?>()) {
      return (data != null
              ? _i18.AlertPermissionException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i19.AlertValidationException?>()) {
      return (data != null
              ? _i19.AlertValidationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i20.EndpointDisabledException?>()) {
      return (data != null
              ? _i20.EndpointDisabledException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i21.MicroArea?>()) {
      return (data != null ? _i21.MicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i22.Patient?>()) {
      return (data != null ? _i22.Patient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i23.TriageAnswer?>()) {
      return (data != null ? _i23.TriageAnswer.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i24.TriageSession?>()) {
      return (data != null ? _i24.TriageSession.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i25.Ubs?>()) {
      return (data != null ? _i25.Ubs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i26.User?>()) {
      return (data != null ? _i26.User.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i27.Visit?>()) {
      return (data != null ? _i27.Visit.fromJson(data) : null) as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i23.TriageAnswer>) {
      return (data as List)
              .map((e) => deserialize<_i23.TriageAnswer>(e))
              .toList()
          as T;
    }
    if (t == Map<String, String>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<String>(v)),
          )
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
      _i6.AlertAckResult => 'AlertAckResult',
      _i7.DevelopmentLoginResult => 'DevelopmentLoginResult',
      _i8.RedAlertResult => 'RedAlertResult',
      _i9.ServiceHealth => 'ServiceHealth',
      _i10.TriageResult => 'TriageResult',
      _i11.AuditLog => 'AuditLog',
      _i12.ConsentLog => 'ConsentLog',
      _i13.AlertStatus => 'AlertStatus',
      _i14.RiskLevel => 'RiskLevel',
      _i15.SyncStatus => 'SyncStatus',
      _i16.UserRole => 'UserRole',
      _i17.AlertDispatchUnavailableException =>
        'AlertDispatchUnavailableException',
      _i18.AlertPermissionException => 'AlertPermissionException',
      _i19.AlertValidationException => 'AlertValidationException',
      _i20.EndpointDisabledException => 'EndpointDisabledException',
      _i21.MicroArea => 'MicroArea',
      _i22.Patient => 'Patient',
      _i23.TriageAnswer => 'TriageAnswer',
      _i24.TriageSession => 'TriageSession',
      _i25.Ubs => 'Ubs',
      _i26.User => 'User',
      _i27.Visit => 'Visit',
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
      case _i6.AlertAckResult():
        return 'AlertAckResult';
      case _i7.DevelopmentLoginResult():
        return 'DevelopmentLoginResult';
      case _i8.RedAlertResult():
        return 'RedAlertResult';
      case _i9.ServiceHealth():
        return 'ServiceHealth';
      case _i10.TriageResult():
        return 'TriageResult';
      case _i11.AuditLog():
        return 'AuditLog';
      case _i12.ConsentLog():
        return 'ConsentLog';
      case _i13.AlertStatus():
        return 'AlertStatus';
      case _i14.RiskLevel():
        return 'RiskLevel';
      case _i15.SyncStatus():
        return 'SyncStatus';
      case _i16.UserRole():
        return 'UserRole';
      case _i17.AlertDispatchUnavailableException():
        return 'AlertDispatchUnavailableException';
      case _i18.AlertPermissionException():
        return 'AlertPermissionException';
      case _i19.AlertValidationException():
        return 'AlertValidationException';
      case _i20.EndpointDisabledException():
        return 'EndpointDisabledException';
      case _i21.MicroArea():
        return 'MicroArea';
      case _i22.Patient():
        return 'Patient';
      case _i23.TriageAnswer():
        return 'TriageAnswer';
      case _i24.TriageSession():
        return 'TriageSession';
      case _i25.Ubs():
        return 'Ubs';
      case _i26.User():
        return 'User';
      case _i27.Visit():
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
    if (dataClassName == 'AlertAckResult') {
      return deserialize<_i6.AlertAckResult>(data['data']);
    }
    if (dataClassName == 'DevelopmentLoginResult') {
      return deserialize<_i7.DevelopmentLoginResult>(data['data']);
    }
    if (dataClassName == 'RedAlertResult') {
      return deserialize<_i8.RedAlertResult>(data['data']);
    }
    if (dataClassName == 'ServiceHealth') {
      return deserialize<_i9.ServiceHealth>(data['data']);
    }
    if (dataClassName == 'TriageResult') {
      return deserialize<_i10.TriageResult>(data['data']);
    }
    if (dataClassName == 'AuditLog') {
      return deserialize<_i11.AuditLog>(data['data']);
    }
    if (dataClassName == 'ConsentLog') {
      return deserialize<_i12.ConsentLog>(data['data']);
    }
    if (dataClassName == 'AlertStatus') {
      return deserialize<_i13.AlertStatus>(data['data']);
    }
    if (dataClassName == 'RiskLevel') {
      return deserialize<_i14.RiskLevel>(data['data']);
    }
    if (dataClassName == 'SyncStatus') {
      return deserialize<_i15.SyncStatus>(data['data']);
    }
    if (dataClassName == 'UserRole') {
      return deserialize<_i16.UserRole>(data['data']);
    }
    if (dataClassName == 'AlertDispatchUnavailableException') {
      return deserialize<_i17.AlertDispatchUnavailableException>(data['data']);
    }
    if (dataClassName == 'AlertPermissionException') {
      return deserialize<_i18.AlertPermissionException>(data['data']);
    }
    if (dataClassName == 'AlertValidationException') {
      return deserialize<_i19.AlertValidationException>(data['data']);
    }
    if (dataClassName == 'EndpointDisabledException') {
      return deserialize<_i20.EndpointDisabledException>(data['data']);
    }
    if (dataClassName == 'MicroArea') {
      return deserialize<_i21.MicroArea>(data['data']);
    }
    if (dataClassName == 'Patient') {
      return deserialize<_i22.Patient>(data['data']);
    }
    if (dataClassName == 'TriageAnswer') {
      return deserialize<_i23.TriageAnswer>(data['data']);
    }
    if (dataClassName == 'TriageSession') {
      return deserialize<_i24.TriageSession>(data['data']);
    }
    if (dataClassName == 'Ubs') {
      return deserialize<_i25.Ubs>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i26.User>(data['data']);
    }
    if (dataClassName == 'Visit') {
      return deserialize<_i27.Visit>(data['data']);
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
