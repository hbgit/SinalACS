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

/// Métodos públicos que NÃO chamam `authenticate`/`authenticateToken`, na forma
/// `Classe.método`, cada um com o motivo.
///
/// A allowlist de cima isenta um endpoint inteiro; esta isenta um método. Um
/// método público que recebe `Session` sem autenticar é o mesmo F4 um nível
/// abaixo: dentro de um endpoint que já estende a base, um método novo nasceria
/// público sem que nada acusasse — o arquivo continua dizendo "estende
/// AuthenticatedEndpoint" e a suíte fica verde.
///
/// `OnboardingEndpoint.generateEnrollmentToken` **não** está aqui de propósito:
/// ele autentica (`authenticateToken`), e uma entrada sua documentaria uma
/// isenção que não existe.
const _publicMethodsByDesign = <String, String>{
  'HealthEndpoint.check':
      'liveness: precisa responder antes de haver credencial',
  'AuthEndpoint.developmentLogin': 'é o próprio emissor de token',
  'AuthEndpoint.loginInstitutional':
      'é o próprio emissor de token: quem chama o login institucional (RF07) '
      'ainda não tem credencial — a matrícula e a senha SÃO a credencial',
  'OnboardingEndpoint.completeEnrollment':
      'público por desenho: quem conclui o onboarding ainda não tem sessão — o '
      'convite de uso único é a credencial',
};

/// A classe que o teste protege — e cuja declaração ele precisa ignorar.
///
/// `authenticated_endpoint.dart` casa com o mesmo glob `*_endpoint.dart` dos
/// endpoints, mas é a DEFINIÇÃO da base, não um usuário dela: a sua declaração
/// é `abstract class AuthenticatedEndpoint extends Endpoint`, que não contém
/// `extends AuthenticatedEndpoint`.
const _baseClassName = 'AuthenticatedEndpoint';

/// Diretório varrido, relativo à raiz do pacote (`cwd` do `dart test`).
const _endpointsDirectory = 'lib/src/endpoints';

/// Declaração de classe com o nome e a superclasse.
///
/// Casamento por DECLARAÇÃO, não por texto solto: `source.contains('extends
/// AuthenticatedEndpoint')` seria satisfeito por uma frase em qualquer
/// comentário — inclusive em português se alguém escrevesse `extends
/// AuthenticatedEndpoint` citando o nome da classe. O padrão exige
/// `class <Nome> extends <Superclasse>` sobre um texto sem comentários nem
/// literais (`_withoutCommentsOrStrings`), que é o que garante que a frase num
/// comentário não vale como declaração.
///
/// `allMatches`, e não `firstMatch`, é deliberado: um arquivo cuja PRIMEIRA
/// classe é pública mas que contém uma segunda estendendo a base passaria
/// escondido se só a primeira fosse lida.
final _classPattern = RegExp(r'class (\w+) extends (\w+)');

void main() {
  test('todo endpoint é autenticado por padrão ou explicitamente isento', () {
    final offenders = <String>[];
    for (final endpoint in _scan()) {
      if (endpoint.isBase) continue;
      if (endpoint.name.isEmpty) {
        offenders.add('${endpoint.file}: não foi possível ler o nome da classe');
        continue;
      }
      if (!endpoint.extendsBase &&
          !_publicByDesign.containsKey(endpoint.name)) {
        offenders.add(
          '${endpoint.name} (${endpoint.file}) não estende AuthenticatedEndpoint '
          'e não está na allowlist de postura pública',
        );
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  // A postura do arquivo não basta: um endpoint que já estende a base continua
  // podendo ganhar um método público que nunca autentica. Foi assim que a
  // revisão final derrubou a versão anterior deste teste, que só olhava o
  // arquivo — e é este o caso que a allowlist fina (`_publicMethodsByDesign`)
  // torna explícito.
  test('todo método público que recebe Session autentica ou está isento', () {
    final endpoints = _scan();

    // Sem este auto-teste, uma extração que passasse a reconhecer zero métodos
    // deixaria a asserção final verde pelo motivo errado — o mesmo cuidado do
    // `expect(files, isNotEmpty)` da varredura.
    for (final endpoint in endpoints) {
      if (!endpoint.extendsBase) continue;
      expect(
        endpoint.methods,
        isNotEmpty,
        reason: '${endpoint.name} (${endpoint.file}) estende a base, mas o teste '
            'não reconheceu nenhum método que receba `Session session` nele — a '
            'extração deste guard quebrou; conserte-a antes de confiar nele',
      );
    }

    final offenders = <String>[];
    for (final endpoint in endpoints) {
      if (endpoint.isBase) continue;
      for (final method in endpoint.methods) {
        final key = '${endpoint.name}.${method.name}';
        if (method.authenticates) continue;
        if (_publicMethodsByDesign.containsKey(key)) continue;
        offenders.add(
          '$key (${endpoint.file}) é público, recebe `Session session` e não chama '
          '`authenticate(...)` nem `authenticateToken(...)`. Autentique o método '
          'com um dos dois ou acrescente-o a `_publicMethodsByDesign` com o '
          'motivo de ele ser público por desenho.',
        );
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('a allowlist não guarda endpoint que já virou autenticado', () {
    // Entrada obsoleta na allowlist é pior que entrada ausente: ela documenta
    // uma postura pública que não existe mais e esconde a hora de removê-la.
    final byName = {
      for (final endpoint in _scan())
        if (endpoint.name.isNotEmpty) endpoint.name: endpoint,
    };
    for (final name in _publicByDesign.keys) {
      final endpoint = byName[name];
      expect(
        endpoint,
        isNotNull,
        reason: '$name não existe mais em $_endpointsDirectory — remova-o de '
            '`_publicByDesign`',
      );
      expect(
        endpoint!.extendsBase,
        isFalse,
        reason: '$name já é autenticado — remova-o de `_publicByDesign`',
      );
    }
  });

  test('a allowlist de métodos não guarda método que já autentica', () {
    // Mesma razão da allowlist de endpoints: uma isenção que já não isenta
    // nada documenta uma exceção inexistente e esconde a hora de removê-la.
    final byKey = <String, _SessionMethod>{};
    for (final endpoint in _scan()) {
      for (final method in endpoint.methods) {
        byKey['${endpoint.name}.${method.name}'] = method;
      }
    }
    for (final key in _publicMethodsByDesign.keys) {
      final method = byKey[key];
      expect(
        method,
        isNotNull,
        reason: '$key não é mais um método público que recebe `Session session` '
            '— remova-o de `_publicMethodsByDesign`',
      );
      expect(
        method!.authenticates,
        isFalse,
        reason: '$key já autentica — remova-o de `_publicMethodsByDesign`',
      );
    }
  });
}

/// Uma classe declarada em `lib/src/endpoints/`.
class _EndpointClass {
  _EndpointClass({
    required this.name,
    required this.superclass,
    required this.file,
    required this.declaration,
  });

  /// Nome da classe (`PatientsEndpoint`), ou vazio quando o arquivo não tem
  /// nenhuma declaração legível.
  final String name;

  /// Nome da superclasse declarada (`AuthenticatedEndpoint`, `Endpoint`, …).
  final String superclass;

  /// Caminho do arquivo, para a mensagem de falha.
  final String file;

  /// O texto da classe, já sem comentários nem literais.
  final String declaration;

  /// Se esta é a base que o teste protege.
  bool get isBase => name == _baseClassName;

  /// Se a declaração estende a base.
  bool get extendsBase => superclass == _baseClassName;

  /// Os métodos públicos da classe que recebem `Session session`.
  List<_SessionMethod> get methods => _sessionMethodsIn(declaration);
}

/// Um método público que recebe `Session session`.
class _SessionMethod {
  _SessionMethod({required this.name, required this.body});

  final String name;
  final String body;

  /// Se o método chama a verificação de token — pelo wrapper herdado
  /// (`authenticate(accessToken)`) ou pela função de topo
  /// (`authenticateToken(accessToken)`).
  bool get authenticates =>
      body.contains('authenticate(') || body.contains('authenticateToken(');
}

/// Lê `lib/src/endpoints/` e devolve toda classe declarada em cada arquivo
/// `*_endpoint.dart`.
///
/// A varredura é `recursive: true` de propósito: um endpoint em
/// `lib/src/endpoints/<subpasta>/` escaparia de uma listagem plana, e escapar da
/// varredura é exatamente o que este teste existe para impedir.
List<_EndpointClass> _scan() {
  final directory = Directory(_endpointsDirectory);
  expect(
    directory.existsSync(),
    isTrue,
    reason: 'o teste roda com cwd em backend/sinalacs_server',
  );

  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('_endpoint.dart'))
      .toList();
  expect(files, isNotEmpty, reason: 'nenhum endpoint encontrado — o caminho mudou?');

  final endpoints = <_EndpointClass>[];
  for (final file in files) {
    final source = _withoutCommentsOrStrings(file.readAsStringSync());
    final declarations = _classPattern.allMatches(source).toList();
    if (declarations.isEmpty) {
      // Arquivo `*_endpoint.dart` sem declaração de classe legível: em vez de
      // sair da varredura em silêncio, ele entra como classe sem nome e o teste
      // de postura o acusa.
      endpoints.add(_EndpointClass(
        name: '',
        superclass: '',
        file: file.path,
        declaration: '',
      ));
      continue;
    }
    for (var index = 0; index < declarations.length; index++) {
      final declaration = declarations[index];
      // A classe vai da sua declaração até a próxima (ou até o fim do arquivo):
      // Dart não tem classe aninhada, então isso delimita o corpo dela.
      final end = index + 1 < declarations.length
          ? declarations[index + 1].start
          : source.length;
      endpoints.add(_EndpointClass(
        name: declaration.group(1)!,
        superclass: declaration.group(2)!,
        file: file.path,
        declaration: source.substring(declaration.start, end),
      ));
    }
  }

  return endpoints;
}

/// Todo método PÚBLICO declarado em [classSource] que recebe `Session session`,
/// com o corpo.
///
/// O corpo é delimitado por casamento de chaves a partir do fechamento da lista
/// de parâmetros — e não "até o próximo método" —, para que o `authenticate` de
/// um método não seja emprestado ao vizinho. Um corpo que não dá para delimitar
/// entra com corpo vazio, ou seja, conta como não autenticado: na dúvida, o
/// teste acusa em vez de absolver.
List<_SessionMethod> _sessionMethodsIn(String classSource) {
  final methods = <_SessionMethod>[];
  for (final match in RegExp(r'\bSession\s+session\b').allMatches(classSource)) {
    final parametersOpen = _parametersOpenBefore(classSource, match.start);
    if (parametersOpen == null) continue;

    final name = _identifierBefore(classSource, parametersOpen);
    if (name == null || name.startsWith('_')) continue;

    final parametersClose = _matchingParenthesis(classSource, parametersOpen);
    if (parametersClose == null) continue;

    methods.add(_SessionMethod(
      name: name,
      body: _bodyAfterParenthesis(classSource, parametersClose) ?? '',
    ));
  }
  return methods;
}

/// Índice do `(` que abre a lista de parâmetros onde [before] está; `null`
/// quando o texto em volta não é uma assinatura de método.
int? _parametersOpenBefore(String source, int before) {
  var depth = 0;
  for (var index = before - 1; index >= 0; index--) {
    final char = source[index];
    if (char == ')') depth++;
    if (char == '(') {
      if (depth == 0) return index;
      depth--;
    }
    // `{`/`}` abrem os parâmetros nomeados ou fecham o corpo anterior: chegar
    // neles sem ter achado o `(` significa que não é uma assinatura.
    if (char == '{' || char == '}') return null;
  }
  return null;
}

/// Nome do método que precede o `(` em [open]; `null` quando não há um
/// identificador ali — o que exclui `if (`, `Function(` e afins.
String? _identifierBefore(String source, int open) {
  var index = open - 1;
  while (index >= 0 && _isSpace(source[index])) {
    index--;
  }
  if (index < 0 || source[index] == '.') return null;

  final end = index + 1;
  while (index >= 0 && _isIdentifierChar(source[index])) {
    index--;
  }
  final name = source.substring(index + 1, end);
  if (name.isEmpty || _notMethodNames.contains(name)) return null;
  return name;
}

/// Índice do `)` que fecha o `(` em [open].
int? _matchingParenthesis(String source, int open) {
  var depth = 0;
  for (var index = open; index < source.length; index++) {
    final char = source[index];
    if (char == '(') depth++;
    if (char == ')') {
      depth--;
      if (depth == 0) return index;
    }
  }
  return null;
}

/// Corpo do método cuja lista de parâmetros fecha em [close]; `null` quando não
/// dá para delimitá-lo.
String? _bodyAfterParenthesis(String source, int close) {
  var index = close + 1;
  while (index < source.length && _isSpace(source[index])) {
    index++;
  }

  if (source.startsWith('async', index) &&
      (index + 5 >= source.length || !_isIdentifierChar(source[index + 5]))) {
    index += 5;
    while (index < source.length && _isSpace(source[index])) {
      index++;
    }
  }
  if (index >= source.length) return null;

  if (source[index] == '{') return _bracedBody(source, index);
  if (source.startsWith('=>', index)) {
    final end = source.indexOf(';', index);
    return end == -1 ? null : source.substring(index, end + 1);
  }
  return null;
}

/// Trecho entre a chave em [open] e a chave que a fecha.
///
/// Contar chaves só é exato porque o texto já passou por
/// [_withoutCommentsOrStrings]: sem isso, uma chave dentro de um literal de
/// texto bagunçaria a contagem.
String? _bracedBody(String source, int open) {
  var depth = 0;
  for (var index = open; index < source.length; index++) {
    final char = source[index];
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) return source.substring(open, index + 1);
    }
  }
  return null;
}

/// Apaga comentários e literais de texto, preservando o comprimento e as
/// quebras de linha do original.
///
/// Sem isto, `// aqui o método chama authenticate(...)` num comentário contaria
/// como se o método autenticasse — e um comentário não autentica ninguém.
String _withoutCommentsOrStrings(String source) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final char = source[index];

    if (char == '/' && index + 1 < source.length && source[index + 1] == '/') {
      while (index < source.length && source[index] != '\n') {
        buffer.write(' ');
        index++;
      }
      continue;
    }

    if (char == '/' && index + 1 < source.length && source[index + 1] == '*') {
      buffer.write('  ');
      index += 2;
      while (index < source.length &&
          !(source[index] == '*' &&
              index + 1 < source.length &&
              source[index + 1] == '/')) {
        buffer.write(source[index] == '\n' ? '\n' : ' ');
        index++;
      }
      if (index < source.length) {
        buffer.write('  ');
        index += 2;
      }
      continue;
    }

    if (char == "'" || char == '"') {
      final isTriple = index + 2 < source.length &&
          source[index + 1] == char &&
          source[index + 2] == char;
      final delimiter = isTriple ? char * 3 : char;

      buffer.write(' ' * delimiter.length);
      index += delimiter.length;
      while (index < source.length) {
        if (source[index] == r'\' && index + 1 < source.length) {
          buffer.write(source[index] == '\n' ? '\n' : ' ');
          buffer.write(source[index + 1] == '\n' ? '\n' : ' ');
          index += 2;
          continue;
        }
        if (source.startsWith(delimiter, index)) break;
        buffer.write(source[index] == '\n' ? '\n' : ' ');
        index++;
      }
      if (index < source.length) {
        buffer.write(' ' * delimiter.length);
        index += delimiter.length;
      }
      continue;
    }

    buffer.write(char);
    index++;
  }
  return buffer.toString();
}

bool _isSpace(String char) =>
    char == ' ' || char == '\n' || char == '\r' || char == '\t';

bool _isIdentifierChar(String char) {
  final code = char.codeUnitAt(0);
  final isDigit = code >= 0x30 && code <= 0x39;
  final isUpper = code >= 0x41 && code <= 0x5A;
  final isLower = code >= 0x61 && code <= 0x7A;
  return isDigit || isUpper || isLower || char == '_' || char == r'$';
}

/// Tokens que parecem nome de método antes de um `(`, mas não são.
const _notMethodNames = {
  'Function',
  'assert',
  'catch',
  'for',
  'if',
  'new',
  'return',
  'switch',
  'while',
};
