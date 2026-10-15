/// Linha exportada da trilha de auditoria (D6).
///
/// Tipo próprio e fechado: o gerador não recebe `AuditLog`/`AuditChainEntry`,
/// então `userId`, `resourceId`, `ipHash`, `previousHash` e `entryHash` não
/// têm como chegar ao CSV. Adicionar campo aqui quebra o teste de lista
/// fechada de propósito.
class AuditExportRow {
  const AuditExportRow({
    required this.sequence,
    required this.timestampUtc,
    required this.autor,
    required this.papelAutor,
    required this.acao,
    required this.recurso,
    required this.rotuloRecurso,
    required this.resultado,
    required this.selo,
  });

  final int sequence;
  final DateTime timestampUtc;
  final String autor;
  final String papelAutor;
  final String acao;
  final String recurso;
  final String rotuloRecurso;
  final String resultado;

  /// Estado do selo da linha como texto (ex.: `valid`), sem acoplar ao enum
  /// do cliente gerado.
  final String selo;
}

/// Gerador puro do CSV de exportação da auditoria (RFC 4180, CRLF, UTF-8).
abstract final class AuditCsv {
  static const columns = [
    'sequence',
    'timestamp_utc',
    'autor',
    'papel_autor',
    'acao',
    'recurso',
    'rotulo_recurso',
    'resultado',
    'selo',
  ];

  static const _crlf = '\r\n';

  static String build(List<AuditExportRow> rows) {
    final out = StringBuffer()
      ..write(columns.join(','))
      ..write(_crlf);
    for (final r in rows) {
      // `sequence` (int) e `timestamp_utc` (ISO-8601 gerado aqui) nunca vêm
      // de texto externo: não passam pela defesa de fórmula, que prefixaria
      // apenas por engano um valor legítimo. Todo o resto é texto de origem
      // externa e é neutralizado.
      out
        ..write(
          [
            r.sequence.toString(),
            r.timestampUtc.toUtc().toIso8601String(),
            _texto(r.autor),
            _texto(r.papelAutor),
            _texto(r.acao),
            _texto(r.recurso),
            _texto(r.rotuloRecurso),
            _texto(r.resultado),
            _texto(r.selo),
          ].map(_escape).join(','),
        )
        ..write(_crlf);
    }
    return out.toString();
  }

  /// Injeção de fórmula (CSV injection): célula que começa com `=`, `+`, `-`
  /// ou `@` (também depois de TAB/CR/LF/espaços iniciais) ganha o prefixo `'`.
  static final _inicioDeFormula = RegExp(r'^[\t\r\n ]*[=+\-@]');

  static String _texto(String valor) =>
      _inicioDeFormula.hasMatch(valor) ? "'$valor" : valor;

  static String _escape(String campo) {
    if (campo.contains(RegExp(r'[",\r\n]'))) {
      return '"${campo.replaceAll('"', '""')}"';
    }
    return campo;
  }
}
