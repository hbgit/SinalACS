import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferência de tema (claro/escuro/automático) do Paciente, persistida
/// localmente.
///
/// `ValueNotifier` simples em vez de framework de estado externo — o app já
/// não usa Provider/Riverpod/Bloc (ver AGENTS.md), e o `MaterialApp` é o
/// único ouvinte. Falha ao ler/gravar a preferência NUNCA pode travar a
/// tela: é uma preferência de UI, não um dado que o app precisa para
/// funcionar, então qualquer erro aqui apenas mantém `ThemeMode.system`.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController([super.value = ThemeMode.system]);

  static const _prefsKey = 'theme_mode';

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      value = ThemeMode.values.firstWhere(
        (mode) => mode.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (error, stackTrace) {
      developer.log(
        'não foi possível restaurar a preferência de tema',
        name: 'sinalacs.patient.theme_controller',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (error, stackTrace) {
      developer.log(
        'não foi possível salvar a preferência de tema',
        name: 'sinalacs.patient.theme_controller',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
