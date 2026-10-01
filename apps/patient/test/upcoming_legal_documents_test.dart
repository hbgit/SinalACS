import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

/// Versão anunciada no backend: `null` só quando a declaração é `= null`; a versão
/// quando há uma agenda com `version:` literal; qualquer outra forma **lança** —
/// "não entendi a agenda" nunca pode passar por "sem agenda".
String? backendUpcomingVersion(String source) {
  final semComentarios = source.replaceAll(RegExp(r'//[^\n]*'), '');
  final declaracao = RegExp(
    r'final\s+TermsChangeSchedule\?\s+upcomingTermsChange\s*=\s*',
  ).firstMatch(semComentarios);
  if (declaracao == null) {
    throw StateError('declaração de upcomingTermsChange não encontrada');
  }
  final resto = semComentarios.substring(declaracao.end);
  if (RegExp(r'^null\s*;').hasMatch(resto)) return null;
  final versao = RegExp(r'^TermsChangeSchedule\([^]*?version:\s*([\x27"])([^\x27"]+)\1').firstMatch(resto);
  if (versao == null) {
    throw StateError('não consegui ler a versão da agenda (use um literal em version:)');
  }
  return versao.group(2);
}

/// Passa pelo tipo declarado: o analisador enxerga a constante como `null` fixo.
UpcomingLegalDocuments? _atual() => upcomingLegalDocuments;

void main() {
  const decl = 'final TermsChangeSchedule? upcomingTermsChange';

  test('o leitor devolve null só para "= null" e a versão para uma agenda literal', () {
    expect(backendUpcomingVersion('$decl = null;'), isNull);
    expect(backendUpcomingVersion('$decl =\n    null;'), isNull);
    expect(
      backendUpcomingVersion("$decl = TermsChangeSchedule(version: '2026.2', publishedAt: x);"),
      '2026.2',
    );
  });

  test('o leitor aceita aspas duplas, ponto e vírgula no resumo e comentário enganoso', () {
    expect(backendUpcomingVersion('$decl = TermsChangeSchedule(version: "2026.3", x: 1);'), '2026.3');
    expect(
      backendUpcomingVersion("$decl = TermsChangeSchedule(summary: 'a; b', version: '2026.4');"),
      '2026.4',
    );
    expect(
      backendUpcomingVersion("// upcomingTermsChange = null;\n$decl = TermsChangeSchedule(version: '2026.5');"),
      '2026.5',
    );
  });

  test('o leitor NÃO trata "não entendi" como "sem agenda": lança', () {
    expect(
      () => backendUpcomingVersion('$decl = TermsChangeSchedule(version: proximaVersao);'),
      throwsStateError,
    );
    expect(() => backendUpcomingVersion('nada aqui'), throwsStateError);
    expect(() => backendUpcomingVersion('$decl = criaAgenda();'), throwsStateError);
  });

  test('agenda do backend e texto do app andam juntos', () {
    final source = File(
      '../../backend/sinalacs_server/lib/src/application/patients/terms_change_schedule.dart',
    ).readAsStringSync();
    expect(
      upcomingLegalDocuments?.version,
      backendUpcomingVersion(source),
      reason: 'o aviso anunciado no servidor precisa ter o texto novo embarcado no app '
          '(e vice-versa): publique o app antes de publicar o aviso',
    );
  });

  test('o texto novo, quando existe, não repete a versão vigente e é coerente', () {
    final novo = _atual();
    if (novo != null) {
      expect(novo.version, isNot(legalDocumentsVersion));
      expect(novo.privacy.version, novo.version);
      expect(novo.terms.version, novo.version);
    }
  });
}
