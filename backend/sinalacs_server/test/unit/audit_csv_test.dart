import 'dart:io';

import 'package:sinalacs_server/src/application/audit/audit_csv.dart';
import 'package:test/test.dart';

AuditExportRow _row({
  int sequence = 1,
  DateTime? timestamp,
  String autor = 'Agente Teste',
  String papelAutor = 'acs',
  String acao = 'read',
  String recurso = 'patients',
  String rotuloRecurso = 'Paciente #A1B2',
  String resultado = 'success',
  String selo = 'valid',
}) => AuditExportRow(
  sequence: sequence,
  timestampUtc: timestamp ?? DateTime.utc(2026, 10, 13, 12, 30, 5),
  autor: autor,
  papelAutor: papelAutor,
  acao: acao,
  recurso: recurso,
  rotuloRecurso: rotuloRecurso,
  resultado: resultado,
  selo: selo,
);

void main() {
  const cabecalho =
      'sequence,timestamp_utc,autor,papel_autor,acao,recurso,rotulo_recurso,resultado,selo';

  group('lista fechada', () {
    test('colunas exatas', () {
      expect(AuditCsv.columns, [
        'sequence',
        'timestamp_utc',
        'autor',
        'papel_autor',
        'acao',
        'recurso',
        'rotulo_recurso',
        'resultado',
        'selo',
      ]);
    });

    test('AuditExportRow tem exatamente nove campos', () {
      final fonte = File(
        'lib/src/application/audit/audit_csv.dart',
      ).readAsStringSync();
      final inicio = fonte.indexOf('class AuditExportRow');
      expect(inicio, greaterThanOrEqualTo(0));
      final bloco = fonte.substring(inicio);
      final fim = bloco.indexOf('\n}\n');
      final campos = RegExp(
        r'^\s+final\s+\S+\s+\w+;',
        multiLine: true,
      ).allMatches(bloco.substring(0, fim)).length;
      expect(campos, AuditCsv.columns.length);
      expect(campos, 9);
    });
  });

  group('formato', () {
    test('cabecalho + CRLF', () {
      final csv = AuditCsv.build([_row()]);
      expect(
        csv,
        '$cabecalho\r\n'
        '1,2026-10-13T12:30:05.000Z,Agente Teste,acs,read,patients,'
        'Paciente #A1B2,success,valid\r\n',
      );
    });

    test('vazio => so cabecalho', () {
      expect(AuditCsv.build(const []), '$cabecalho\r\n');
    });

    test('timestamp local vira UTC com Z', () {
      final csv = AuditCsv.build([
        _row(timestamp: DateTime.parse('2026-10-13T09:00:00-03:00')),
      ]);
      expect(csv, contains(',2026-10-13T12:00:00.000Z,'));
    });

    test('aspas duplas escapadas', () {
      final csv = AuditCsv.build([_row(rotuloRecurso: 'diz "oi"')]);
      expect(csv, contains(',"diz ""oi""",'));
    });

    test('virgula e quebra de linha dentro do campo ficam entre aspas', () {
      final csv = AuditCsv.build([
        _row(autor: 'Silva, Ana', rotuloRecurso: 'linha1\nlinha2'),
      ]);
      expect(csv, contains('"Silva, Ana"'));
      expect(csv, contains('"linha1\nlinha2"'));
    });
  });

  group('injecao de formula', () {
    for (final entrada in ['=HYPERLINK("x")', '+1', '-1', '@a']) {
      test('autor $entrada recebe prefixo apostrofo', () {
        final csv = AuditCsv.build([_row(autor: entrada)]);
        final linha = csv.split('\r\n')[1];
        final esperado = entrada.contains('"')
            ? '"\'${entrada.replaceAll('"', '""')}"'
            : "'$entrada";
        expect(linha, contains(',$esperado,'));
      });
    }

    test('apos espaco, TAB, CR ou LF iniciais tambem recebe prefixo', () {
      expect(AuditCsv.build([_row(autor: ' =1')]), contains(",' =1,"));
      expect(AuditCsv.build([_row(autor: '\t@x')]), contains(",'\t@x,"));
      expect(AuditCsv.build([_row(autor: ' +1')]), contains(",' +1,"));
      expect(AuditCsv.build([_row(autor: '\n=1')]), contains(",\"'\n=1\","));
      expect(AuditCsv.build([_row(autor: '\r+1')]), contains(",\"'\r+1\","));
    });

    test('espaco inicial sem fórmula e "-" no meio nao recebem prefixo', () {
      final csv = AuditCsv.build([_row(autor: ' abc', rotuloRecurso: 'a-b')]);
      expect(csv, contains(', abc,'));
      expect(csv, contains(',a-b,'));
      expect(csv, isNot(contains("'")));
    });

    test('sequence e timestamp numericos nao sofrem prefixo', () {
      final csv = AuditCsv.build([_row(sequence: 42)]);
      expect(csv.split('\r\n')[1], startsWith('42,2026-'));
      expect(csv, isNot(contains("'42")));
    });

    test('texto comum nao recebe prefixo', () {
      final csv = AuditCsv.build([_row()]);
      expect(csv, isNot(contains("'")));
    });
  });

  group('PII', () {
    const uuid = '3f2b8c1e-9d4a-4e7b-8a61-5c0d2f9e7a11';
    final hash64 = 'a1b2c3d4' * 8;
    const ip = '192.168.10.77';
    const nome = 'Fulano Sintetico da Silva';

    int ocorrencias(String texto, String trecho) =>
        trecho.allMatches(texto).length;

    test('o gerador nao inventa UUID, hash de 64 hex nem IP', () {
      final csv = AuditCsv.build([_row(), _row(sequence: 2)]);
      expect(
        RegExp(
          r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        ).hasMatch(csv),
        isFalse,
      );
      expect(RegExp(r'[0-9a-fA-F]{64}').hasMatch(csv), isFalse);
      expect(RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b').hasMatch(csv), isFalse);
    });

    test('valores sensiveis em autor/rotulo saem so onde foram postos', () {
      final csv = AuditCsv.build([
        _row(autor: nome, rotuloRecurso: '$uuid $hash64 $ip'),
      ]);
      final linhas = csv.split('\r\n');
      expect(linhas[0], isNot(contains(nome)));
      for (final v in [nome, uuid, hash64, ip]) {
        expect(ocorrencias(csv, v), 1, reason: v);
      }
      // autor e a 3a coluna, rotulo a 7a: nenhuma outra coluna os repete.
      final campos = linhas[1].split(',');
      expect(campos[2], nome);
      expect(campos[6], contains(uuid));
      for (final i in [0, 1, 3, 4, 5, 7, 8]) {
        expect(campos[i], isNot(contains(uuid)));
        expect(campos[i], isNot(contains(nome)));
      }
    });

    // A garantia estrutural contra vazamento de ipHash/entryHash/resourceId e
    // o teste "lista fechada" acima: o gerador so conhece nove campos.
  });
}
