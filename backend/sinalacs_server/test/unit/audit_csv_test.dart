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
}) =>
    AuditExportRow(
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
      final fonte =
          File('lib/src/application/audit/audit_csv.dart').readAsStringSync();
      final inicio = fonte.indexOf('class AuditExportRow');
      expect(inicio, greaterThanOrEqualTo(0));
      final bloco = fonte.substring(inicio);
      final fim = bloco.indexOf('\n}\n');
      final campos = RegExp(r'^\s+final\s+\S+\s+\w+;', multiLine: true)
          .allMatches(bloco.substring(0, fim))
          .length;
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

    test('apos TAB/CR iniciais tambem recebe prefixo', () {
      final csv = AuditCsv.build([_row(rotuloRecurso: '\t=1+1')]);
      expect(csv, contains("'\t=1+1"));
      final csv2 = AuditCsv.build([_row(rotuloRecurso: '\r+1')]);
      expect(csv2, contains("\"'\r+1\""));
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
    test('a linha so tem as nove colunas: nada alem delas vaza', () {
      const uuid = '3f2b8c1e-9d4a-4e7b-8a61-5c0d2f9e7a11';
      final hash64 = 'a1b2c3d4' * 8;
      const ip = '192.168.10.77';
      const nomeSintetico = 'Fulano Sintetico da Silva';
      // Campos de origem (fora das colunas permitidas) que o servico tem em
      // maos; o gerador nunca os recebe.
      final origem = {
        'resourceId': uuid,
        'entryHash': hash64,
        'ipHash': ip,
        'nome': nomeSintetico,
      };
      expect(origem, hasLength(4));

      final csv = AuditCsv.build([_row(), _row(sequence: 2)]);

      expect(csv, isNot(contains(uuid)));
      expect(csv, isNot(contains(hash64)));
      expect(csv, isNot(contains(ip)));
      expect(csv, isNot(contains(nomeSintetico)));
      expect(
        RegExp(
          r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        ).hasMatch(csv),
        isFalse,
      );
      expect(RegExp(r'[0-9a-fA-F]{64}').hasMatch(csv), isFalse);
      expect(RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b').hasMatch(csv), isFalse);
    });
  });
}
