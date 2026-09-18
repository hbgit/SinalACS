import 'dart:io';

import 'package:test/test.dart';

/// Endpoints que NÃO estendem `AuthenticatedEndpoint`, cada um com o motivo.
///
/// A allowlist é o ponto do teste: adicionar um endpoint novo faz esta suíte
/// falhar até que alguém decida, por escrito, qual é a postura dele. Antes
/// disso a decisão era implícita — um endpoint nascia público porque ninguém
/// tinha escrito a checagem ainda (achado F4 de spec/security_assessment.md).
const _publicByDesign = <String, String>{
  'HealthEndpoint': 'liveness: precisa responder antes de haver credencial',
  'AuthEndpoint': 'é o próprio emissor de token',
  'OnboardingEndpoint':
      'postura mista: completeEnrollment é público por desenho (o convite de '
      'uso único é a credencial), generateEnrollmentToken exige token de ACS',
};

/// A classe que o teste protege — e cujo arquivo ele precisa ignorar.
///
/// `authenticated_endpoint.dart` casa com o mesmo glob `*_endpoint.dart` dos
/// endpoints, mas é a DEFINIÇÃO da base, não um usuário dela: a sua declaração
/// é `abstract class AuthenticatedEndpoint extends Endpoint`, que não contém
/// `extends AuthenticatedEndpoint`.
const _baseClassName = 'AuthenticatedEndpoint';

/// Casamento por DECLARAÇÃO, não por texto solto.
///
/// `source.contains('extends AuthenticatedEndpoint')` seria satisfeito por uma
/// frase em qualquer comentário — inclusive em português se alguém escrevesse
/// `extends AuthenticatedEndpoint` citando o nome da classe. O padrão exige
/// `class <Nome> extends AuthenticatedEndpoint`, que é o que a regra quer
/// dizer.
final _extendsBasePattern = RegExp(r'class \w+ extends AuthenticatedEndpoint\b');

void main() {
  test('todo endpoint é autenticado por padrão ou explicitamente isento', () {
    final directory = Directory('lib/src/endpoints');
    expect(
      directory.existsSync(),
      isTrue,
      reason: 'o teste roda com cwd em backend/sinalacs_server',
    );

    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_endpoint.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'nenhum endpoint encontrado — o caminho mudou?');

    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      final match = RegExp(r'class (\w+) extends').firstMatch(source);
      final name = match?.group(1);
      if (name == null) {
        offenders.add('${file.path}: não foi possível ler o nome da classe');
        continue;
      }

      // O arquivo que DEFINE a base não é um endpoint e não estende a si
      // mesmo: `authenticated_endpoint.dart` casa com o glob `*_endpoint.dart`
      // e a sua declaração (`abstract class AuthenticatedEndpoint extends
      // Endpoint`) não contém o literal procurado — sem esta linha de guarda,
      // a suíte acusaria o próprio arquivo correto que ela deveria proteger.
      if (name == _baseClassName) continue;

      final isGuarded = _extendsBasePattern.hasMatch(source);
      final isAllowlisted = _publicByDesign.containsKey(name);
      if (!isGuarded && !isAllowlisted) {
        offenders.add(
          '$name (${file.path}) não estende AuthenticatedEndpoint e não está '
          'na allowlist de postura pública',
        );
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('a allowlist não guarda endpoint que já virou autenticado', () {
    // Entrada obsoleta na allowlist é pior que entrada ausente: ela documenta
    // uma postura pública que não existe mais e esconde a hora de removê-la.
    for (final name in _publicByDesign.keys) {
      final path = 'lib/src/endpoints/${_fileNameFor(name)}';
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$name não existe mais em $path');
      expect(
        _extendsBasePattern.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '$name já é autenticado — remova-o da allowlist',
      );
    }
  });
}

/// `HealthEndpoint` → `health_endpoint.dart`.
String _fileNameFor(String className) {
  final snake = className
      .replaceAll('Endpoint', '')
      .replaceAllMapped(RegExp('[A-Z]'), (match) => '_${match.group(0)!}')
      .toLowerCase()
      .replaceAll(RegExp('^_'), '');
  return '${snake}_endpoint.dart';
}
