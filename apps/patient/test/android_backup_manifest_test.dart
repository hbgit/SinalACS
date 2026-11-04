import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #136: a chave do banco local mora no Keystore e não sai do aparelho. Se o
/// Android copiasse o banco (backup na nuvem ou transferência entre aparelhos),
/// o banco restaurado ficaria ilegível, sem a chave. O pilar A não precisa de
/// backup, então ele fica desligado. Os testes leem o texto-fonte, o mesmo
/// idioma de `android_push_manifest_test.dart`: o manifesto não existe no
/// `flutter test`.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final rulesFile = File('android/app/src/main/res/xml/data_extraction_rules.xml');
  final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest)?.group(0) ?? '';

  test('allowBackup="false" no <application>', () {
    expect(application.contains('android:allowBackup="false"'), isTrue);
  });

  test('fullBackupContent="false"', () {
    expect(application.contains('android:fullBackupContent="false"'), isTrue);
  });

  test('dataExtractionRules aponta para @xml/data_extraction_rules', () {
    expect(
      application.contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      isTrue,
    );
  });

  test('regras excluem root, file, database, sharedpref e external em cloud-backup e device-transfer', () {
    expect(rulesFile.existsSync(), isTrue, reason: 'o recurso referenciado precisa existir');
    final rules = rulesFile.readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final block = RegExp('<$section[^>]*>([\\s\\S]*?)</$section>').firstMatch(rules);
      expect(block, isNotNull, reason: 'falta <$section>');
      for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
        final exclude = RegExp('<exclude\\s+domain="$domain"\\s+path="\\."\\s*/>');
        expect(exclude.hasMatch(block!.group(1)!), isTrue,
            reason: '$section deve excluir o domínio $domain');
      }
    }
  });

  test('shared_preferences só é importado por theme_controller.dart', () {
    final importers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('package:shared_preferences/'))
        .map((f) => f.path.replaceAll('\\', '/'))
        .toList();
    expect(importers, ['lib/core/services/theme_controller.dart']);
  });

  final storageFiles = Directory('lib/core/storage')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('nenhum print/debugPrint/log em lib/core/storage', () {
    final proibido = RegExp(r'\b(print|debugPrint|log)\s*\(|dart:developer');
    for (final f in storageFiles) {
      expect(proibido.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('nenhum catch em lib/core/storage interpola a exceção', () {
    expect(storageFiles, isNotEmpty);
    for (final f in storageFiles) {
      expect(violacoesDeCatch(f.readAsStringSync()), isEmpty, reason: f.path);
    }
  });

  test('a varredura de catch encontra uma violação plantada', () {
    expect(violacoesDeCatch("try {} catch (e) { throw StateError('x \$e'); }"), isNotEmpty);
    expect(violacoesDeCatch("try {} catch (e) { x = '\${e}'; }"), isNotEmpty);
    expect(violacoesDeCatch('try {} catch (err, s) { x = err.toString(); }'), isNotEmpty);
    expect(violacoesDeCatch('try {} catch (_) { x = 1; }'), isEmpty);
    expect(violacoesDeCatch('try {} catch (error, s) { f = error; }'), isEmpty);
  });
}

/// Devolve os nomes de variáveis de `catch` cujo corpo interpola ou imprime a
/// exceção (`$v`, `${v`, `v.toString()`). `catch (_)` nunca acusa.
List<String> violacoesDeCatch(String source) {
  final achados = <String>[];
  for (final m in RegExp(r'catch\s*\(\s*(\w+)').allMatches(source)) {
    final nome = m.group(1)!;
    if (nome == '_') continue;
    final abre = source.indexOf('{', m.end);
    if (abre < 0) continue;
    var nivel = 0;
    var fim = abre;
    for (; fim < source.length; fim++) {
      if (source[fim] == '{') nivel++;
      if (source[fim] == '}' && --nivel == 0) break;
    }
    final corpo = source.substring(abre, fim);
    final n = RegExp.escape(nome);
    if (RegExp('\\\$$n\\b|\\\$\\{\\s*$n\\b|\\b$n\\.toString\\(\\)').hasMatch(corpo)) {
      achados.add(nome);
    }
  }
  return achados;
}
