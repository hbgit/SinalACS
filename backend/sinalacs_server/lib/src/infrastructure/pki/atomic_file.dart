import 'dart:io';
import 'dart:math';

/// Grava [contents] em [path] sem que um leitor jamais veja o arquivo pela
/// metade (#94: a CRL que o broker relê).
///
/// O temporário `<path>.tmp-<pid>-<aleatório>` fica no MESMO diretório, porque
/// só ali o `rename` é atômico (outro sistema de arquivos viraria cópia). Antes
/// de trocar, [validate] recebe o caminho do temporário e pode lançar para
/// recusar o conteúdo — quem grava uma CRL confere a assinatura contra a CA ali.
/// Qualquer falha (gravação, validação ou `rename`) apaga o temporário e relança:
/// o arquivo anterior, se havia, fica intacto.
Future<void> writeFileAtomically(
  String path,
  String contents, {
  Future<void> Function(String tmpPath)? validate,
}) async {
  final sufixo = Random.secure().nextInt(1 << 32).toRadixString(16);
  final tmp = File('$path.tmp-$pid-$sufixo');
  try {
    await tmp.writeAsString(contents, flush: true);
    if (validate != null) await validate(tmp.path);
    await tmp.rename(path);
  } catch (_) {
    try {
      if (tmp.existsSync()) await tmp.delete();
    } on FileSystemException {
      // O erro que importa é o original, relançado abaixo.
    }
    rethrow;
  }
}
