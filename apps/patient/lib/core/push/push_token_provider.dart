import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinalacs_patient/core/push/native_push_token_source.dart';
import 'package:sinalacs_patient/core/push/push_token_source.dart';

/// De onde o app tira o token de push. Único uso de Riverpod no app do
/// paciente (decisão de 2026-09-29, RF14): o resto da injeção segue por
/// `InheritedWidget`. Sobrescrevível em teste com `overrideWithValue`.
final pushTokenSourceProvider = Provider<PushTokenSource>(
  (ref) => const NativePushTokenSource(),
);
