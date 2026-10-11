import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guarda contra texto/borda em branco translúcido fixo (`Colors.white24/54/70`):
/// foi escrito para o tema escuro e some sobre o fundo claro (medido no emulador,
/// 2026-10-01). Use `Theme.of(context).colorScheme.onSurfaceVariant` (texto) ou
/// `outlineVariant` (borda), que seguem o tema ativo.
void main() {
  test('lib/ não usa Colors.white24/54/70 fixos', () {
    final padrao = RegExp(r'Colors\.white(24|54|70)\b');
    final achados = <String>[];
    for (final arquivo in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!arquivo.path.endsWith('.dart')) continue;
      final linhas = arquivo.readAsLinesSync();
      for (var i = 0; i < linhas.length; i++) {
        if (padrao.hasMatch(linhas[i])) achados.add('${arquivo.path}:${i + 1}');
      }
    }
    expect(achados, isEmpty, reason: 'cores brancas fixas somem no tema claro');
  });
}
