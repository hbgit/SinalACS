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
import 'api/alert_ack_result.dart' as _i5;
import 'api/development_login_result.dart' as _i6;
import 'api/red_alert_result.dart' as _i7;
import 'api/service_health.dart' as _i8;
import 'api/triage_result.dart' as _i9;
import 'audit_log.dart' as _i10;
import 'consent_log.dart' as _i11;
import 'enums/alert_status.dart' as _i12;
import 'enums/risk_level.dart' as _i13;
import 'enums/sync_status.dart' as _i14;
import 'enums/user_role.dart' as _i15;
import 'exceptions/alert_dispatch_unavailable_exception.dart' as _i16;
import 'exceptions/alert_permission_exception.dart' as _i17;
import 'exceptions/alert_validation_exception.dart' as _i18;
import 'exceptions/endpoint_disabled_exception.dart' as _i19;
import 'micro_area.dart' as _i20;
import 'patient.dart' as _i21;
import 'triage_answer.dart' as _i22;
import 'triage_session.dart' as _i23;
import 'ubs.dart' as _i24;
import 'user.dart' as _i25;
import 'visit.dart' as _i26;
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart'
    as _i27;
import 'package:serverpod_auth_core_client/serverpod_auth_core_client.dart'
    as _i28;
export 'acs.dart';
export 'alert.dart';
export 'alert_delivery_record.dart';
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
    if (t == _i5.AlertAckResult) {
      return _i5.AlertAckResult.fromJson(data) as T;
    }
    if (t == _i6.DevelopmentLoginResult) {
      return _i6.DevelopmentLoginResult.fromJson(data) as T;
    }
    if (t == _i7.RedAlertResult) {
      return _i7.RedAlertResult.fromJson(data) as T;
    }
    if (t == _i8.ServiceHealth) {
      return _i8.ServiceHealth.fromJson(data) as T;
    }
    if (t == _i9.TriageResult) {
      return _i9.TriageResult.fromJson(data) as T;
    }
    if (t == _i10.AuditLog) {
      return _i10.AuditLog.fromJson(data) as T;
    }
    if (t == _i11.ConsentLog) {
      return _i11.ConsentLog.fromJson(data) as T;
    }
    if (t == _i12.AlertStatus) {
      return _i12.AlertStatus.fromJson(data) as T;
    }
    if (t == _i13.RiskLevel) {
      return _i13.RiskLevel.fromJson(data) as T;
    }
    if (t == _i14.SyncStatus) {
      return _i14.SyncStatus.fromJson(data) as T;
    }
    if (t == _i15.UserRole) {
      return _i15.UserRole.fromJson(data) as T;
    }
    if (t == _i16.AlertDispatchUnavailableException) {
      return _i16.AlertDispatchUnavailableException.fromJson(data) as T;
    }
    if (t == _i17.AlertPermissionException) {
      return _i17.AlertPermissionException.fromJson(data) as T;
    }
    if (t == _i18.AlertValidationException) {
      return _i18.AlertValidationException.fromJson(data) as T;
    }
    if (t == _i19.EndpointDisabledException) {
      return _i19.EndpointDisabledException.fromJson(data) as T;
    }
    if (t == _i20.MicroArea) {
      return _i20.MicroArea.fromJson(data) as T;
    }
    if (t == _i21.Patient) {
      return _i21.Patient.fromJson(data) as T;
    }
    if (t == _i22.TriageAnswer) {
      return _i22.TriageAnswer.fromJson(data) as T;
    }
    if (t == _i23.TriageSession) {
      return _i23.TriageSession.fromJson(data) as T;
    }
    if (t == _i24.Ubs) {
      return _i24.Ubs.fromJson(data) as T;
    }
    if (t == _i25.User) {
      return _i25.User.fromJson(data) as T;
    }
    if (t == _i26.Visit) {
      return _i26.Visit.fromJson(data) as T;
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
    if (t == _i1.getType<_i5.AlertAckResult?>()) {
      return (data != null ? _i5.AlertAckResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i6.DevelopmentLoginResult?>()) {
      return (data != null ? _i6.DevelopmentLoginResult.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i7.RedAlertResult?>()) {
      return (data != null ? _i7.RedAlertResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i8.ServiceHealth?>()) {
      return (data != null ? _i8.ServiceHealth.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i9.TriageResult?>()) {
      return (data != null ? _i9.TriageResult.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i10.AuditLog?>()) {
      return (data != null ? _i10.AuditLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i11.ConsentLog?>()) {
      return (data != null ? _i11.ConsentLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i12.AlertStatus?>()) {
      return (data != null ? _i12.AlertStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i13.RiskLevel?>()) {
      return (data != null ? _i13.RiskLevel.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i14.SyncStatus?>()) {
      return (data != null ? _i14.SyncStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i15.UserRole?>()) {
      return (data != null ? _i15.UserRole.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i16.AlertDispatchUnavailableException?>()) {
      return (data != null
              ? _i16.AlertDispatchUnavailableException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i17.AlertPermissionException?>()) {
      return (data != null
              ? _i17.AlertPermissionException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i18.AlertValidationException?>()) {
      return (data != null
              ? _i18.AlertValidationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i19.EndpointDisabledException?>()) {
      return (data != null
              ? _i19.EndpointDisabledException.fromJson(data)
              : null)
          as T;
    }
    if (t == _i1.getType<_i20.MicroArea?>()) {
      return (data != null ? _i20.MicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i21.Patient?>()) {
      return (data != null ? _i21.Patient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i22.TriageAnswer?>()) {
      return (data != null ? _i22.TriageAnswer.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i23.TriageSession?>()) {
      return (data != null ? _i23.TriageSession.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i24.Ubs?>()) {
      return (data != null ? _i24.Ubs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i25.User?>()) {
      return (data != null ? _i25.User.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i26.Visit?>()) {
      return (data != null ? _i26.Visit.fromJson(data) : null) as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i22.TriageAnswer>) {
      return (data as List)
              .map((e) => deserialize<_i22.TriageAnswer>(e))
              .toList()
          as T;
    }
    if (t == Map<String, String>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<String>(v)),
          )
          as T;
    }
    try {
      return _i27.Protocol().deserialize<T>(data, t);
    } on _i1.DeserializationTypeNotFoundException catch (_) {}
    try {
      return _i28.Protocol().deserialize<T>(data, t);
    } on _i1.DeserializationTypeNotFoundException catch (_) {}
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _i2.Acs => 'Acs',
      _i3.Alert => 'Alert',
      _i4.AlertDeliveryRecord => 'AlertDeliveryRecord',
      _i5.AlertAckResult => 'AlertAckResult',
      _i6.DevelopmentLoginResult => 'DevelopmentLoginResult',
      _i7.RedAlertResult => 'RedAlertResult',
      _i8.ServiceHealth => 'ServiceHealth',
      _i9.TriageResult => 'TriageResult',
      _i10.AuditLog => 'AuditLog',
      _i11.ConsentLog => 'ConsentLog',
      _i12.AlertStatus => 'AlertStatus',
      _i13.RiskLevel => 'RiskLevel',
      _i14.SyncStatus => 'SyncStatus',
      _i15.UserRole => 'UserRole',
      _i16.AlertDispatchUnavailableException =>
        'AlertDispatchUnavailableException',
      _i17.AlertPermissionException => 'AlertPermissionException',
      _i18.AlertValidationException => 'AlertValidationException',
      _i19.EndpointDisabledException => 'EndpointDisabledException',
      _i20.MicroArea => 'MicroArea',
      _i21.Patient => 'Patient',
      _i22.TriageAnswer => 'TriageAnswer',
      _i23.TriageSession => 'TriageSession',
      _i24.Ubs => 'Ubs',
      _i25.User => 'User',
      _i26.Visit => 'Visit',
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
      case _i5.AlertAckResult():
        return 'AlertAckResult';
      case _i6.DevelopmentLoginResult():
        return 'DevelopmentLoginResult';
      case _i7.RedAlertResult():
        return 'RedAlertResult';
      case _i8.ServiceHealth():
        return 'ServiceHealth';
      case _i9.TriageResult():
        return 'TriageResult';
      case _i10.AuditLog():
        return 'AuditLog';
      case _i11.ConsentLog():
        return 'ConsentLog';
      case _i12.AlertStatus():
        return 'AlertStatus';
      case _i13.RiskLevel():
        return 'RiskLevel';
      case _i14.SyncStatus():
        return 'SyncStatus';
      case _i15.UserRole():
        return 'UserRole';
      case _i16.AlertDispatchUnavailableException():
        return 'AlertDispatchUnavailableException';
      case _i17.AlertPermissionException():
        return 'AlertPermissionException';
      case _i18.AlertValidationException():
        return 'AlertValidationException';
      case _i19.EndpointDisabledException():
        return 'EndpointDisabledException';
      case _i20.MicroArea():
        return 'MicroArea';
      case _i21.Patient():
        return 'Patient';
      case _i22.TriageAnswer():
        return 'TriageAnswer';
      case _i23.TriageSession():
        return 'TriageSession';
      case _i24.Ubs():
        return 'Ubs';
      case _i25.User():
        return 'User';
      case _i26.Visit():
        return 'Visit';
    }
    className = _i27.Protocol().getClassNameForObject(data);
    if (className != null) {
      return 'serverpod_auth_idp.$className';
    }
    className = _i28.Protocol().getClassNameForObject(data);
    if (className != null) {
      return 'serverpod_auth_core.$className';
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
    if (dataClassName == 'AlertAckResult') {
      return deserialize<_i5.AlertAckResult>(data['data']);
    }
    if (dataClassName == 'DevelopmentLoginResult') {
      return deserialize<_i6.DevelopmentLoginResult>(data['data']);
    }
    if (dataClassName == 'RedAlertResult') {
      return deserialize<_i7.RedAlertResult>(data['data']);
    }
    if (dataClassName == 'ServiceHealth') {
      return deserialize<_i8.ServiceHealth>(data['data']);
    }
    if (dataClassName == 'TriageResult') {
      return deserialize<_i9.TriageResult>(data['data']);
    }
    if (dataClassName == 'AuditLog') {
      return deserialize<_i10.AuditLog>(data['data']);
    }
    if (dataClassName == 'ConsentLog') {
      return deserialize<_i11.ConsentLog>(data['data']);
    }
    if (dataClassName == 'AlertStatus') {
      return deserialize<_i12.AlertStatus>(data['data']);
    }
    if (dataClassName == 'RiskLevel') {
      return deserialize<_i13.RiskLevel>(data['data']);
    }
    if (dataClassName == 'SyncStatus') {
      return deserialize<_i14.SyncStatus>(data['data']);
    }
    if (dataClassName == 'UserRole') {
      return deserialize<_i15.UserRole>(data['data']);
    }
    if (dataClassName == 'AlertDispatchUnavailableException') {
      return deserialize<_i16.AlertDispatchUnavailableException>(data['data']);
    }
    if (dataClassName == 'AlertPermissionException') {
      return deserialize<_i17.AlertPermissionException>(data['data']);
    }
    if (dataClassName == 'AlertValidationException') {
      return deserialize<_i18.AlertValidationException>(data['data']);
    }
    if (dataClassName == 'EndpointDisabledException') {
      return deserialize<_i19.EndpointDisabledException>(data['data']);
    }
    if (dataClassName == 'MicroArea') {
      return deserialize<_i20.MicroArea>(data['data']);
    }
    if (dataClassName == 'Patient') {
      return deserialize<_i21.Patient>(data['data']);
    }
    if (dataClassName == 'TriageAnswer') {
      return deserialize<_i22.TriageAnswer>(data['data']);
    }
    if (dataClassName == 'TriageSession') {
      return deserialize<_i23.TriageSession>(data['data']);
    }
    if (dataClassName == 'Ubs') {
      return deserialize<_i24.Ubs>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i25.User>(data['data']);
    }
    if (dataClassName == 'Visit') {
      return deserialize<_i26.Visit>(data['data']);
    }
    if (dataClassName.startsWith('serverpod_auth_idp.')) {
      data['className'] = dataClassName.substring(19);
      return _i27.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod_auth_core.')) {
      data['className'] = dataClassName.substring(20);
      return _i28.Protocol().deserializeByClassName(data);
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
    try {
      return _i27.Protocol().mapRecordToJson(record);
    } catch (_) {}
    try {
      return _i28.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
