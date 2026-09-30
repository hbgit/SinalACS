import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

/// Versão anunciada no backend, ou `null` quando `upcomingTermsChange = null`.
String? backendUpcomingVersion(String source) {
  if (RegExp(r'upcomingTermsChange\s*=\s*null').hasMatch(source)) return null;
  final match = RegExp(
    r"upcomingTermsChange[^;]*version:\s*'([^']+)'",
    dotAll: true,
  ).firstMatch(source);
  return match?.group(1);
}

/// Passa pelo tipo declarado: o analisador enxerga a constante como `null` fixo.
UpcomingLegalDocuments? _atual() => upcomingLegalDocuments;

void main() {
  test('o leitor devolve null com a agenda vazia e a versão quando há agenda', () {
    expect(backendUpcomingVersion('final TermsChangeSchedule? upcomingTermsChange = null;'), isNull);
    expect(
      backendUpcomingVersion(
        "final TermsChangeSchedule? upcomingTermsChange = TermsChangeSchedule(version: '2026.2', publishedAt: x);",
      ),
      '2026.2',
    );
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
