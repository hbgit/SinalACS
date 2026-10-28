import 'dart:io';

import 'package:sinalacs_server/src/infrastructure/pki/atomic_file.dart';
import 'package:test/test.dart';

/// Gravação atômica (#94): a CRL publicada para o broker nunca pode ser lida
/// pela metade nem trocada por uma que não passou na validação.
void main() {
  late Directory dir;
  late String alvo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sinalacs-atomic-test-');
    alvo = '${dir.path}/crl.pem';
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  List<String> temporarios() => dir
      .listSync()
      .map((e) => e.uri.pathSegments.last)
      .where((n) => n.contains('.tmp-'))
      .toList();

  test('o caminho final nunca contém conteúdo parcial', () async {
    await File(alvo).writeAsString('anterior');
    await expectLater(
      writeFileAtomically(alvo, 'novo', validate: (tmp) async {
        expect(await File(tmp).readAsString(), 'novo');
        expect(File(tmp).parent.path, dir.path);
        throw const FormatException('inválido');
      }),
      throwsA(isA<FormatException>()),
    );
    expect(await File(alvo).readAsString(), 'anterior');
    expect(temporarios(), isEmpty);
  });

  test('sem arquivo anterior e validate que lança → caminho final não existe',
      () async {
    await expectLater(
      writeFileAtomically(alvo, 'novo',
          validate: (_) async => throw StateError('recusado')),
      throwsA(isA<StateError>()),
    );
    expect(File(alvo).existsSync(), isFalse);
    expect(temporarios(), isEmpty);
  });

  test('sucesso → conteúdo novo e nenhum temporário', () async {
    await File(alvo).writeAsString('anterior');
    var validou = false;
    await writeFileAtomically(alvo, 'novo', validate: (_) async {
      validou = true;
    });
    expect(validou, isTrue);
    expect(await File(alvo).readAsString(), 'novo');
    expect(temporarios(), isEmpty);
  });
}
