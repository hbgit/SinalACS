import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinalacs_acs/core/services/theme_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sem nada gravado, abre em Automático', () async {
    final controller = ThemeController();
    await controller.restore();
    expect(controller.value, ThemeMode.system);
  });

  test('a escolha sobrevive a um reinício', () async {
    final primeira = ThemeController();
    await primeira.setThemeMode(ThemeMode.light);

    final depoisDoReinicio = ThemeController();
    await depoisDoReinicio.restore();
    expect(depoisDoReinicio.value, ThemeMode.light);
  });

  test('valor inválido na preferência (arquivo corrompido ou de versão futura) cai em Automático', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
    final controller = ThemeController(ThemeMode.dark);
    await controller.restore();
    expect(controller.value, ThemeMode.system);
  });

  test('o ouvinte é avisado ao trocar', () async {
    final controller = ThemeController();
    var avisos = 0;
    controller.addListener(() => avisos++);
    await controller.setThemeMode(ThemeMode.dark);
    expect(avisos, 1);
    expect(controller.value, ThemeMode.dark);
  });
}
