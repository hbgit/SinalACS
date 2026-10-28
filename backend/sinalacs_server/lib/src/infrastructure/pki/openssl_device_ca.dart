import 'dart:io';

import 'package:sinalacs_server/src/config/device_ca_config.dart';

/// O que o backend extrai de um CSR antes de decidir assiná-lo.
class CsrInfo {
  const CsrInfo({
    required this.commonName,
    required this.keyAlgorithm,
    required this.curve,
  });

  /// O CN do sujeito do CSR, ou `null` se o CSR não traz CN.
  final String? commonName;

  /// Como o `openssl` nomeia o algoritmo da chave: `id-ecPublicKey`,
  /// `rsaEncryption`...
  final String keyAlgorithm;

  /// A curva de uma chave EC (`prime256v1`); `null` para outros algoritmos.
  final String? curve;
}

/// Uma folha revogada, como entra na CRL.
class RevokedEntry {
  const RevokedEntry({
    required this.serial,
    required this.revokedAt,
    required this.notAfter,
    required this.commonName,
  });

  final BigInt serial;
  final DateTime revokedAt;
  final DateTime notAfter;
  final String commonName;
}

/// A CA de aparelhos (#94) operada pelo binário `openssl`, sem dependência Dart
/// nova: assina o CSR do aparelho, inspeciona CSRs e gera a CRL.
///
/// Todo arquivo intermediário vai para um diretório de `Directory.systemTemp`
/// apagado no `finally`. Uma falha do `openssl` vira exceção com o subcomando,
/// o código de saída e o `stderr` — que nunca traz o conteúdo da chave; a chave
/// em si nunca é lida por este processo, só o caminho é passado ao `openssl`.
///
/// `sign` usa `openssl x509 -req -not_before/-not_after`, que só existem a
/// partir do OpenSSL 3.4 (medido 3.5.9 no `alpine:latest` e no host em
/// 2026-10-27). `buildCrl` usa `openssl ca -gencrl` com um `index.txt`
/// montado da lista recebida: a fonte de verdade das revogações é o banco, não
/// um banco de dados do `openssl` em disco.
class OpensslDeviceCa {
  OpensslDeviceCa(this._cfg, {String opensslBinary = 'openssl'})
      : _openssl = opensslBinary;

  final DeviceCaConfig _cfg;
  final String _openssl;

  // CN entra no `-subj` e no `index.txt`: só os caracteres que nenhum dos dois
  // interpreta (UUID de microárea, nomes simples).
  static final _cnSeguro = RegExp(r'^[A-Za-z0-9._:-]{1,64}$');
  // URI entra numa linha `subjectAltName=URI:a,URI:b` do arquivo de extensões
  // (`-extfile`), que o OpenSSL lê como CONFIGURAÇÃO: expande `$var` e
  // `${ENV::NOME}` (vazaria o ambiente do processo, segredos inclusive, para
  // dentro da folha assinada) e trata `#` como comentário. Por isso só `urn:`
  // com um alfabeto fechado, sem `$`, `{`, `}`, `#`, espaço, vírgula ou quebra
  // de linha (#94, achado C1 da revisão final).
  static final _uriSegura = RegExp(r'^urn:[A-Za-z0-9:._-]+$');
  // Defesa em profundidade, conferida antes da regex: qualquer um destes num
  // texto que vai ao arquivo de configuração do OpenSSL é recusado com motivo
  // explícito, mesmo que a regex um dia seja afrouxada.
  static final _metacaracteresDoOpenssl = RegExp(r'[$\{\}#\n\r\\]');

  static void _semMetacaracteres(String valor, String nome) {
    if (_metacaracteresDoOpenssl.hasMatch(valor)) {
      throw ArgumentError.value(
        valor,
        nome,
        r'contém caractere que o OpenSSL interpreta na configuração ($, {, }, #, \, quebra de linha)',
      );
    }
  }

  /// Lê o CSR e confere a assinatura dele. CSR malformado ou com assinatura que
  /// não confere → [FormatException]. A política (EC P-256, CN esperado) é de
  /// quem chama: aqui só se descreve o que o CSR traz.
  Future<CsrInfo> inspectCsr(String csrPem) async {
    final dir = await Directory.systemTemp.createTemp('sinalacs-csr-');
    try {
      final csr = File('${dir.path}/req.csr');
      await csr.writeAsString(csrPem);
      final r = await _run([
        'req', '-in', csr.path, '-noout', '-verify', '-text',
        '-subject', '-nameopt', 'RFC2253',
      ]);
      if (r.exitCode != 0) {
        throw const FormatException(
            'CSR inválido ou com assinatura que não confere.');
      }
      final out = r.stdout as String;
      final alg = RegExp(r'Public Key Algorithm:\s*(\S+)').firstMatch(out);
      if (alg == null) {
        throw const FormatException('CSR sem algoritmo de chave reconhecível.');
      }
      final curva = RegExp(r'ASN1 OID:\s*(\S+)').firstMatch(out);
      return CsrInfo(
        commonName: _cnDoSujeito(out),
        keyAlgorithm: alg.group(1)!,
        curve: curva?.group(1),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }

  static String? _cnDoSujeito(String saida) {
    final linha = RegExp(r'^subject=(.*)$', multiLine: true).firstMatch(saida);
    if (linha == null) return null;
    for (final rdn in linha.group(1)!.split(',')) {
      final t = rdn.trim();
      if (t.startsWith('CN=')) return t.substring(3);
    }
    return null;
  }

  /// Assina [csrPem] como folha de cliente MQTT: sujeito `CN=[commonName]`,
  /// `subjectAltName` com [sanUris], `extendedKeyUsage=clientAuth`, a serial e
  /// a validade pedidas. O CN do CSR tem de ser igual a [commonName] —
  /// diferente, ou CSR inválido, é [FormatException]. Devolve o PEM.
  Future<String> sign({
    required String csrPem,
    required BigInt serial,
    required String commonName,
    required List<String> sanUris,
    required DateTime notBefore,
    required DateTime notAfter,
  }) async {
    _semMetacaracteres(commonName, 'commonName');
    if (!_cnSeguro.hasMatch(commonName)) {
      throw ArgumentError.value(commonName, 'commonName', 'CN fora do padrão');
    }
    if (sanUris.isEmpty) {
      throw ArgumentError.value(sanUris, 'sanUris', 'ao menos uma URI');
    }
    for (final u in sanUris) {
      _semMetacaracteres(u, 'sanUris');
      if (!_uriSegura.hasMatch(u)) {
        throw ArgumentError.value(u, 'sanUris', 'URI fora do padrão');
      }
    }
    if (serial <= BigInt.zero) {
      throw ArgumentError.value(serial, 'serial', 'precisa ser positiva');
    }
    if (!notAfter.isAfter(notBefore)) {
      throw ArgumentError('notAfter precisa ser posterior a notBefore');
    }
    final info = await inspectCsr(csrPem);
    if (info.commonName != commonName) {
      throw const FormatException('CN do CSR difere do CN pedido.');
    }
    final dir = await Directory.systemTemp.createTemp('sinalacs-sign-');
    try {
      final csr = File('${dir.path}/req.csr');
      await csr.writeAsString(csrPem);
      final ext = File('${dir.path}/leaf.ext');
      await ext.writeAsString(
        'basicConstraints=critical,CA:FALSE\n'
        'keyUsage=critical,digitalSignature\n'
        'extendedKeyUsage=clientAuth\n'
        'subjectKeyIdentifier=hash\n'
        'authorityKeyIdentifier=keyid\n'
        'subjectAltName=${sanUris.map((u) => 'URI:$u').join(',')}\n',
      );
      final out = '${dir.path}/leaf.crt';
      await _checked('x509', [
        'x509', '-req', '-in', csr.path,
        '-CA', _cfg.caCertPath, '-CAkey', _cfg.caKeyPath,
        '-set_serial', '0x${serial.toRadixString(16)}',
        '-subj', '/CN=$commonName',
        '-extfile', ext.path,
        '-not_before', _generalizedTime(notBefore),
        '-not_after', _generalizedTime(notAfter),
        '-sha256', '-out', out,
      ]);
      return File(out).readAsString();
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Gera a CRL assinada pela CA, com `lastUpdate` em [now], `nextUpdate` em
  /// `now + days` e a extensão `CRL Number` = [crlNumber]. [revoked] vazia
  /// ainda produz uma CRL válida (é a do primeiro boot). Devolve o PEM.
  Future<String> buildCrl({
    required List<RevokedEntry> revoked,
    required BigInt crlNumber,
    required DateTime now,
    required int days,
  }) async {
    if (days <= 0) throw ArgumentError.value(days, 'days', 'precisa ser > 0');
    if (crlNumber < BigInt.zero) {
      throw ArgumentError.value(crlNumber, 'crlNumber', 'negativo');
    }
    for (final e in revoked) {
      if (!_cnSeguro.hasMatch(e.commonName)) {
        throw ArgumentError.value(e.commonName, 'commonName', 'CN fora do padrão');
      }
    }
    final dir = await Directory.systemTemp.createTemp('sinalacs-crl-');
    try {
      final index = File('${dir.path}/index.txt');
      await index.writeAsString(revoked
          .map((e) => 'R\t${_utcTime(e.notAfter)}\t${_utcTime(e.revokedAt)}\t'
              '${_hexPar(e.serial)}\tunknown\t/CN=${e.commonName}\n')
          .join());
      await File('${dir.path}/index.txt.attr')
          .writeAsString('unique_subject = no\n');
      await File('${dir.path}/crlnumber')
          .writeAsString('${_hexPar(crlNumber)}\n');
      final cnf = File('${dir.path}/ca.cnf');
      await cnf.writeAsString('''
[ ca ]
default_ca = devices

[ devices ]
database = ${index.path}
crlnumber = ${dir.path}/crlnumber
default_md = sha256
crl_extensions = crl_ext

[ crl_ext ]
authorityKeyIdentifier = keyid:always
''');
      final out = '${dir.path}/crl.pem';
      await _checked('ca', [
        'ca', '-gencrl', '-batch', '-config', cnf.path,
        '-cert', _cfg.caCertPath, '-keyfile', _cfg.caKeyPath,
        '-crl_lastupdate', _generalizedTime(now),
        '-crl_nextupdate', _generalizedTime(now.add(Duration(days: days))),
        '-out', out,
      ]);
      return File(out).readAsString();
    } finally {
      await dir.delete(recursive: true);
    }
  }

  Future<ProcessResult> _run(List<String> args) async {
    try {
      return await Process.run(_openssl, args);
    } on ProcessException catch (e) {
      throw StateError(
          'binário `$_openssl` indisponível para a CA de aparelhos: ${e.message}');
    }
  }

  Future<void> _checked(String sub, List<String> args) async {
    final r = await _run(args);
    if (r.exitCode != 0) {
      throw StateError(
          'openssl $sub saiu com ${r.exitCode}: ${(r.stderr as String).trim()}');
    }
  }

  static String _dois(int n) => n.toString().padLeft(2, '0');

  static String _hms(DateTime t) =>
      '${_dois(t.month)}${_dois(t.day)}${_dois(t.hour)}${_dois(t.minute)}'
      '${_dois(t.second)}Z';

  /// `YYYYMMDDHHMMSSZ`, o formato de `-not_before`/`-crl_lastupdate`.
  static String _generalizedTime(DateTime t) {
    final u = t.toUtc();
    return '${u.year.toString().padLeft(4, '0')}${_hms(u)}';
  }

  /// `YYMMDDHHMMSSZ`, o formato das datas no `index.txt` do `openssl ca`.
  static String _utcTime(DateTime t) {
    final u = t.toUtc();
    return '${_dois(u.year % 100)}${_hms(u)}';
  }

  /// Hex maiúsculo com número par de dígitos, como o `openssl ca` espera.
  static String _hexPar(BigInt n) {
    final h = n.toRadixString(16).toUpperCase();
    return h.length.isOdd ? '0$h' : h;
  }
}
