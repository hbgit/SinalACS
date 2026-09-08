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
import 'audit_log.dart' as _i5;
import 'consent_log.dart' as _i6;
import 'enums/alert_status.dart' as _i7;
import 'enums/risk_level.dart' as _i8;
import 'enums/sync_status.dart' as _i9;
import 'enums/user_role.dart' as _i10;
import 'micro_area.dart' as _i11;
import 'patient.dart' as _i12;
import 'triage_answer.dart' as _i13;
import 'triage_session.dart' as _i14;
import 'ubs.dart' as _i15;
import 'user.dart' as _i16;
import 'visit.dart' as _i17;
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart'
    as _i18;
import 'package:serverpod_auth_core_client/serverpod_auth_core_client.dart'
    as _i19;
export 'acs.dart';
export 'alert.dart';
export 'alert_delivery_record.dart';
export 'audit_log.dart';
export 'consent_log.dart';
export 'enums/alert_status.dart';
export 'enums/risk_level.dart';
export 'enums/sync_status.dart';
export 'enums/user_role.dart';
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
    if (t == _i5.AuditLog) {
      return _i5.AuditLog.fromJson(data) as T;
    }
    if (t == _i6.ConsentLog) {
      return _i6.ConsentLog.fromJson(data) as T;
    }
    if (t == _i7.AlertStatus) {
      return _i7.AlertStatus.fromJson(data) as T;
    }
    if (t == _i8.RiskLevel) {
      return _i8.RiskLevel.fromJson(data) as T;
    }
    if (t == _i9.SyncStatus) {
      return _i9.SyncStatus.fromJson(data) as T;
    }
    if (t == _i10.UserRole) {
      return _i10.UserRole.fromJson(data) as T;
    }
    if (t == _i11.MicroArea) {
      return _i11.MicroArea.fromJson(data) as T;
    }
    if (t == _i12.Patient) {
      return _i12.Patient.fromJson(data) as T;
    }
    if (t == _i13.TriageAnswer) {
      return _i13.TriageAnswer.fromJson(data) as T;
    }
    if (t == _i14.TriageSession) {
      return _i14.TriageSession.fromJson(data) as T;
    }
    if (t == _i15.Ubs) {
      return _i15.Ubs.fromJson(data) as T;
    }
    if (t == _i16.User) {
      return _i16.User.fromJson(data) as T;
    }
    if (t == _i17.Visit) {
      return _i17.Visit.fromJson(data) as T;
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
    if (t == _i1.getType<_i5.AuditLog?>()) {
      return (data != null ? _i5.AuditLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i6.ConsentLog?>()) {
      return (data != null ? _i6.ConsentLog.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i7.AlertStatus?>()) {
      return (data != null ? _i7.AlertStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i8.RiskLevel?>()) {
      return (data != null ? _i8.RiskLevel.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i9.SyncStatus?>()) {
      return (data != null ? _i9.SyncStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i10.UserRole?>()) {
      return (data != null ? _i10.UserRole.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i11.MicroArea?>()) {
      return (data != null ? _i11.MicroArea.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i12.Patient?>()) {
      return (data != null ? _i12.Patient.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i13.TriageAnswer?>()) {
      return (data != null ? _i13.TriageAnswer.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i14.TriageSession?>()) {
      return (data != null ? _i14.TriageSession.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i15.Ubs?>()) {
      return (data != null ? _i15.Ubs.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i16.User?>()) {
      return (data != null ? _i16.User.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i17.Visit?>()) {
      return (data != null ? _i17.Visit.fromJson(data) : null) as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i13.TriageAnswer>) {
      return (data as List)
              .map((e) => deserialize<_i13.TriageAnswer>(e))
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
      return _i18.Protocol().deserialize<T>(data, t);
    } on _i1.DeserializationTypeNotFoundException catch (_) {}
    try {
      return _i19.Protocol().deserialize<T>(data, t);
    } on _i1.DeserializationTypeNotFoundException catch (_) {}
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _i2.Acs => 'Acs',
      _i3.Alert => 'Alert',
      _i4.AlertDeliveryRecord => 'AlertDeliveryRecord',
      _i5.AuditLog => 'AuditLog',
      _i6.ConsentLog => 'ConsentLog',
      _i7.AlertStatus => 'AlertStatus',
      _i8.RiskLevel => 'RiskLevel',
      _i9.SyncStatus => 'SyncStatus',
      _i10.UserRole => 'UserRole',
      _i11.MicroArea => 'MicroArea',
      _i12.Patient => 'Patient',
      _i13.TriageAnswer => 'TriageAnswer',
      _i14.TriageSession => 'TriageSession',
      _i15.Ubs => 'Ubs',
      _i16.User => 'User',
      _i17.Visit => 'Visit',
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
      case _i5.AuditLog():
        return 'AuditLog';
      case _i6.ConsentLog():
        return 'ConsentLog';
      case _i7.AlertStatus():
        return 'AlertStatus';
      case _i8.RiskLevel():
        return 'RiskLevel';
      case _i9.SyncStatus():
        return 'SyncStatus';
      case _i10.UserRole():
        return 'UserRole';
      case _i11.MicroArea():
        return 'MicroArea';
      case _i12.Patient():
        return 'Patient';
      case _i13.TriageAnswer():
        return 'TriageAnswer';
      case _i14.TriageSession():
        return 'TriageSession';
      case _i15.Ubs():
        return 'Ubs';
      case _i16.User():
        return 'User';
      case _i17.Visit():
        return 'Visit';
    }
    className = _i18.Protocol().getClassNameForObject(data);
    if (className != null) {
      return 'serverpod_auth_idp.$className';
    }
    className = _i19.Protocol().getClassNameForObject(data);
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
    if (dataClassName == 'AuditLog') {
      return deserialize<_i5.AuditLog>(data['data']);
    }
    if (dataClassName == 'ConsentLog') {
      return deserialize<_i6.ConsentLog>(data['data']);
    }
    if (dataClassName == 'AlertStatus') {
      return deserialize<_i7.AlertStatus>(data['data']);
    }
    if (dataClassName == 'RiskLevel') {
      return deserialize<_i8.RiskLevel>(data['data']);
    }
    if (dataClassName == 'SyncStatus') {
      return deserialize<_i9.SyncStatus>(data['data']);
    }
    if (dataClassName == 'UserRole') {
      return deserialize<_i10.UserRole>(data['data']);
    }
    if (dataClassName == 'MicroArea') {
      return deserialize<_i11.MicroArea>(data['data']);
    }
    if (dataClassName == 'Patient') {
      return deserialize<_i12.Patient>(data['data']);
    }
    if (dataClassName == 'TriageAnswer') {
      return deserialize<_i13.TriageAnswer>(data['data']);
    }
    if (dataClassName == 'TriageSession') {
      return deserialize<_i14.TriageSession>(data['data']);
    }
    if (dataClassName == 'Ubs') {
      return deserialize<_i15.Ubs>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i16.User>(data['data']);
    }
    if (dataClassName == 'Visit') {
      return deserialize<_i17.Visit>(data['data']);
    }
    if (dataClassName.startsWith('serverpod_auth_idp.')) {
      data['className'] = dataClassName.substring(19);
      return _i18.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod_auth_core.')) {
      data['className'] = dataClassName.substring(20);
      return _i19.Protocol().deserializeByClassName(data);
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
      return _i18.Protocol().mapRecordToJson(record);
    } catch (_) {}
    try {
      return _i19.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
