import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

/// Conteúdo mínimo que `spec/lgpd_design.md` exige de cada documento
/// (LGPD-RF18, linha 249; LGPD-RF19, linha 259). O teste procura o tópico no
/// título das seções, sem acento e em minúsculas, para não quebrar por uma
/// troca de redação que mantém o tópico.
String _norm(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

void expectTopics(LegalDocument document, List<String> topics) {
  final titles = document.sections.map((s) => _norm(s.title)).join(' | ');
  for (final topic in topics) {
    expect(
      titles,
      contains(topic),
      reason: '${document.title} sem seção sobre "$topic"',
    );
  }
}

void main() {
  test('política de privacidade cobre o conteúdo mínimo do LGPD-RF19', () {
    expectTopics(privacyPolicy, [
      'quem cuida dos seus dados',
      'dados que coletamos',
      'para que usamos',
      'bases legais',
      'com quem compartilhamos',
      'por quanto tempo',
      'seus direitos',
      'como protegemos',
      'encarregado',
      'duvidas',
    ]);
  });

  test('termo de uso cobre o conteúdo mínimo do LGPD-RF18', () {
    expectTopics(termsOfUse, [
      'regras de uso',
      'responsabilidades',
      'o que nao e permitido',
      'propriedade intelectual',
      'limites de responsabilidade',
      'lei aplicavel',
      'alteracoes',
    ]);
  });

  test(
    'os dois documentos têm resumo, versão vigente e histórico que a inclui',
    () {
      for (final document in [privacyPolicy, termsOfUse]) {
        expect(document.summary, isNotEmpty, reason: document.title);
        expect(document.version, legalDocumentsVersion, reason: document.title);
        expect(
          document.history.map((v) => v.version),
          contains(document.version),
          reason: '${document.title}: versão vigente fora do histórico',
        );
        for (final section in document.sections) {
          expect(
            section.body.trim(),
            isNotEmpty,
            reason: '${document.title} › ${section.title}',
          );
        }
      }
    },
  );

  test('versão dos documentos é a mesma que o backend carimba em consent_logs', () {
    // Guarda de deriva: o aceite gravado no cadastro leva `consentPolicyVersion`
    // do backend; se o app mostrar outra versão, "Meus dados" passa a exibir um
    // aceite de um texto que a pessoa nunca viu. Monorepo: o CI do app faz
    // checkout do repositório inteiro, então o arquivo do servidor existe.
    final source = File(
      '../../backend/sinalacs_server/lib/src/application/onboarding/onboarding_service.dart',
    ).readAsStringSync();
    final match = RegExp(
      r"consentPolicyVersion = '([^']+)'",
    ).firstMatch(source);
    expect(
      match,
      isNotNull,
      reason: 'consentPolicyVersion não encontrado no backend',
    );
    expect(legalDocumentsVersion, match!.group(1));
  });
}
