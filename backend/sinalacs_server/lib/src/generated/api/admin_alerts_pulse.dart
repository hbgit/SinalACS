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
import '../api/admin_indicators.dart' as _i2;
import 'package:sinalacs_server/src/generated/protocol.dart' as _i3;

/// Pulso da monitoração do backoffice (issue #44, D5): o que o painel consulta
/// a cada 30 s. Sem identidade nenhuma — nem o rótulo do paciente: só contagens
/// e instantes. O dashboard se atualiza por aqui (`indicators` são os mesmos de
/// `admin.indicators`, no mesmo escopo); a lista só é relida por `admin.alerts`
/// quando `maxChangedAt` muda. `overdueRed` segue a regra de `AdminAlert.overdue`.
/// `maxChangedAt` é nulo quando o escopo não tem alerta; `serverNow` é o
/// relógio do servidor, nunca o do aparelho.
abstract class AdminAlertsPulse
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminAlertsPulse._({
    required this.indicators,
    required this.overdueRed,
    this.maxChangedAt,
    required this.serverNow,
  });

  factory AdminAlertsPulse({
    required _i2.AdminIndicators indicators,
    required int overdueRed,
    DateTime? maxChangedAt,
    required DateTime serverNow,
  }) = _AdminAlertsPulseImpl;

  factory AdminAlertsPulse.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminAlertsPulse(
      indicators: _i3.Protocol().deserialize<_i2.AdminIndicators>(
        jsonSerialization['indicators'],
      ),
      overdueRed: jsonSerialization['overdueRed'] as int,
      maxChangedAt: jsonSerialization['maxChangedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['maxChangedAt'],
            ),
      serverNow: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['serverNow'],
      ),
    );
  }

  _i2.AdminIndicators indicators;

  int overdueRed;

  DateTime? maxChangedAt;

  DateTime serverNow;

  /// Returns a shallow copy of this [AdminAlertsPulse]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAlertsPulse copyWith({
    _i2.AdminIndicators? indicators,
    int? overdueRed,
    DateTime? maxChangedAt,
    DateTime? serverNow,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAlertsPulse',
      'indicators': indicators.toJson(),
      'overdueRed': overdueRed,
      if (maxChangedAt != null) 'maxChangedAt': maxChangedAt?.toJson(),
      'serverNow': serverNow.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminAlertsPulse',
      'indicators': indicators.toJsonForProtocol(),
      'overdueRed': overdueRed,
      if (maxChangedAt != null) 'maxChangedAt': maxChangedAt?.toJson(),
      'serverNow': serverNow.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminAlertsPulseImpl extends AdminAlertsPulse {
  _AdminAlertsPulseImpl({
    required _i2.AdminIndicators indicators,
    required int overdueRed,
    DateTime? maxChangedAt,
    required DateTime serverNow,
  }) : super._(
         indicators: indicators,
         overdueRed: overdueRed,
         maxChangedAt: maxChangedAt,
         serverNow: serverNow,
       );

  /// Returns a shallow copy of this [AdminAlertsPulse]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAlertsPulse copyWith({
    _i2.AdminIndicators? indicators,
    int? overdueRed,
    Object? maxChangedAt = _Undefined,
    DateTime? serverNow,
  }) {
    return AdminAlertsPulse(
      indicators: indicators ?? this.indicators.copyWith(),
      overdueRed: overdueRed ?? this.overdueRed,
      maxChangedAt: maxChangedAt is DateTime?
          ? maxChangedAt
          : this.maxChangedAt,
      serverNow: serverNow ?? this.serverNow,
    );
  }
}
