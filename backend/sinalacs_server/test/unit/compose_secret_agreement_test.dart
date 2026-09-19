import 'dart:io';

import 'package:test/test.dart';

/// Variáveis que precisam chegar com a MESMA expressão a mais de um serviço do
/// `docker-compose.yml`, e quais serviços são esses.
///
/// O defeito que este mapa prende é SILENCIOSO, e foi medido no review da
/// Task 6: `cpf-hash-seed` grava `users.cpfHash = HMAC(cpf, pepper)` e o
/// servidor procura pelo mesmo HMAC. Com peppers diferentes, nenhum CPF
/// semeado é encontrado — e o `requestOtp` responde **byte a byte** o mesmo que
/// responde para um CPF válido que não existe no banco: nenhum SMS, nenhum
/// desafio, nenhum erro no log, nenhuma linha vermelha. Só um paciente de
/// desenvolvimento que nunca entra.
///
/// A verificação manual que a Task 6 prescrevia (`docker compose logs
/// cpf-hash-seed` → 5 linhas) passa dos DOIS jeitos, porque só conta linhas de
/// saída — o script termina felizmente com um pepper que o servidor não usa. O
/// que este teste mede é o **texto-fonte** do `docker-compose.yml`: a
/// concordância não é observável por nenhuma outra suíte, porque nenhuma outra
/// sobe os dois processos.
///
/// A ausência da variável em um dos serviços é o caso central, não a exceção:
/// o Compose interpola vazio, o `AppConfig` cai no fallback PÚBLICO de
/// desenvolvimento (`AppConfig.developmentCpfHashPepper` e
/// `developmentHealthDataEncryptionKey`, ambos versionados) e o outro serviço
/// usa o valor do `.env` — exatamente a divergência acima.
const _sharedByServices = <String, List<String>>{
  'CPF_HASH_PEPPER': ['serverpod', 'cpf-hash-seed'],
  'HEALTH_DATA_ENCRYPTION_KEY': ['serverpod', 'health-data-seed'],
};

/// O `docker-compose.yml` da raiz do repositório.
///
/// Relativo a `backend/sinalacs_server`, que é o cwd do `dart test` — o mesmo
/// pressuposto que `endpoint_auth_posture_test.dart` documenta para
/// `lib/src/endpoints`.
const _composePath = '../../docker-compose.yml';

/// Serviços cuja leitura o CONTROLE abaixo exige: se a extração deixar de
/// enxergar um deles, é o controle que acusa, e não a asserção principal — que
/// acusaria a variável "ausente" pelo motivo errado (o mesmo cuidado do
/// `expect(files, isNotEmpty)` do teste de postura dos endpoints).
const _servicesUnderTest = ['serverpod', 'cpf-hash-seed', 'health-data-seed'];

/// Variável de controle da extração.
///
/// `APP_ENV` é declarada com a mesma expressão pelos quatro serviços que
/// rodam seed, e é isso que a torna um bom controle: o mecanismo de comparação
/// deste arquivo roda de ponta a ponta sobre o arquivo de verdade e encontra
/// igualdade onde ela existe. Sem ele, uma extração quebrada (que devolvesse
/// `{}` para todo serviço) deixaria a asserção principal vermelha por um motivo
/// que não é o que ela diz, e ninguém saberia qual das duas coisas consertar.
const _controlVariable = 'APP_ENV';
const _controlExpression = r'${APP_ENV:-development}';

void main() {
  test('os serviços que compartilham um segredo recebem a mesma expressão', () {
    final ambientes = _environmentByService(_composeSource());

    final offenders = <String>[];
    for (final requisito in _sharedByServices.entries) {
      final variavel = requisito.key;
      final servicos = requisito.value;

      final declaradas = <String, String?>{};
      for (final servico in servicos) {
        if (!ambientes.containsKey(servico)) {
          offenders.add(
            '$variavel: o serviço `$servico` não existe em $_composePath. Se ele '
            'foi renomeado, atualize `_sharedByServices` junto — um nome que não '
            'existe isenta o serviço de verdade da checagem em silêncio.',
          );
          declaradas[servico] = null;
          continue;
        }
        declaradas[servico] = ambientes[servico]![variavel];
      }

      final semDeclarar = declaradas.entries
          .where((entry) => entry.value == null)
          .map((entry) => '`${entry.key}`')
          .toList();
      if (semDeclarar.isNotEmpty) {
        final quemDeclara = declaradas.entries
            .where((entry) => entry.value != null)
            .map((entry) => '`${entry.key}` (${entry.value})')
            .join(', ');
        offenders.add(
          '$variavel: ${semDeclarar.join(' e ')} não declara a variável, então '
          'não recebe o valor do `.env` — quem declara é $quemDeclara. '
          '$_whyItMatters',
        );
        continue;
      }

      final expressoes = declaradas.map(
        (servico, expressao) => MapEntry(servico, _withoutQuotes(expressao!)),
      );
      if (expressoes.values.toSet().length > 1) {
        final detalhe = expressoes.entries
            .map((entry) => '`${entry.key}` usa ${entry.value}')
            .join(' e ');
        offenders.add('$variavel: $detalhe. $_whyItMatters');
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('controle: a extração enxerga o environment dos serviços de seed', () {
    // O controle é o que separa "as expressões concordam" de "o teste não leu
    // nada": sem ele, um `_environmentByService` que devolvesse mapas vazios
    // faria a asserção acima acusar ausência de variável em todo mundo, com uma
    // mensagem que não descreve o defeito real.
    final ambientes = _environmentByService(_composeSource());

    expect(
      ambientes.keys,
      containsAll(_servicesUnderTest),
      reason:
          'a extração não reconheceu estes serviços em $_composePath — '
          'conserte o teste antes de confiar na asserção principal',
    );

    for (final servico in _servicesUnderTest) {
      expect(
        ambientes[servico],
        isNotEmpty,
        reason:
            'o `environment` de `$servico` saiu vazio da extração: ou o '
            'serviço perdeu as variáveis, ou o parser deste teste quebrou',
      );
      expect(
        ambientes[servico]![_controlVariable],
        _controlExpression,
        reason:
            '`$servico` declara $_controlVariable com outra expressão. Além '
            'de ser o controle da extração, é requisito real: um seed rodando '
            'fora de development se recusa a rodar, e um servidor em '
            'development atendendo um seed que não é deixa a stack pela metade',
      );
    }
  });
}

/// Por que uma expressão divergente é pior que um erro — usado nas mensagens de
/// falha, que é onde alguém vai ler isso.
const _whyItMatters =
    'O seed e o servidor precisam da MESMA expressão: cada um resolve o valor '
    'por conta própria, e um processo sem a variável cai no fallback público de '
    'desenvolvimento enquanto o outro usa o valor do `.env`. A falha é '
    'silenciosa — o seed termina com sucesso, o servidor sobe saudável, e o '
    'login deixa de encontrar qualquer CPF semeado (ou o diretório de pacientes '
    'deixa de decifrar o que o seed gravou), sem erro em lugar nenhum.';

/// O compose como texto — é o texto-fonte que este teste mede, e não a
/// configuração já interpretada pelo Docker (que exigiria o CLI e recusaria
/// diagnosticar justamente o caso "variável ausente").
String _composeSource() {
  final file = File(_composePath);
  expect(
    file.existsSync(),
    isTrue,
    reason:
        'o teste roda com cwd em backend/sinalacs_server e lê $_composePath; '
        'o compose da stack mudou de lugar?',
  );
  return file.readAsStringSync();
}

/// O bloco `environment:` de cada serviço, como mapa variável → expressão crua.
///
/// Leitura por indentação — `services:` na coluna 0, o nome do serviço com 2
/// espaços, `environment:` com 4 e cada variável com 6 —, sem `package:yaml`:
/// não é dependência declarada deste pacote, e não se paga uma dependência nova
/// para ler um arquivo cujo formato este repositório controla. Linhas de
/// comentário são ignoradas, e um `#` precedido de espaço é comentário de fim
/// de linha, como no próprio YAML.
///
/// O que a função NÃO entende, ela recusa em vez de devolver um mapa vazio: um
/// `environment:` na forma de lista (`- VAR=valor`) daria o mesmo mapa vazio de
/// um serviço sem variável nenhuma, e o teste acusaria "não declara a variável"
/// pelo motivo errado.
Map<String, Map<String, String>> _environmentByService(String source) {
  final services = <String, Map<String, String>>{};
  var insideServices = false;
  String? currentService;
  var insideEnvironment = false;

  for (final raw in source.split('\n')) {
    final line = raw.trimRight();
    final content = line.trimLeft();
    if (content.isEmpty || content.startsWith('#')) continue;

    final indent = line.length - content.length;

    if (indent == 0) {
      // Só `services:` interessa; qualquer outra seção de topo (`volumes:`,
      // `networks:`) encerra a varredura.
      insideServices = content == 'services:';
      currentService = null;
      insideEnvironment = false;
      continue;
    }
    if (!insideServices) continue;

    if (indent == 2) {
      final name = content.endsWith(':')
          ? content.substring(0, content.length - 1).trim()
          : '';
      currentService = name.isEmpty ? null : name;
      insideEnvironment = false;
      if (name.isNotEmpty) {
        services[name] = <String, String>{};
      }
      continue;
    }
    if (currentService == null) continue;

    if (indent == 4) {
      insideEnvironment = content == 'environment:';
      continue;
    }
    if (indent != 6 || !insideEnvironment) continue;

    if (content.startsWith('- ')) {
      throw StateError(
        '$_composePath declara o `environment` de `$currentService` na forma de '
        'lista, que este teste não lê. Reescreva a extração antes de confiar '
        'nela: um servidor sem variável e um servidor cuja variável o parser '
        'não sabe ler produziriam a mesma acusação.',
      );
    }

    final separator = content.indexOf(':');
    if (separator == -1) continue;
    final key = content.substring(0, separator).trim();
    services[currentService]![key] = _withoutInlineComment(
      content.substring(separator + 1),
    ).trim();
  }

  return services;
}

/// O valor sem o comentário de fim de linha (` # ...`), preservando um `#`
/// colado a texto — que em YAML faz parte do valor.
String _withoutInlineComment(String value) {
  final comment = RegExp(r'\s#').firstMatch(value);
  return comment == null ? value : value.substring(0, comment.start);
}

/// A expressão sem as aspas externas.
///
/// `CPF_HASH_PEPPER: "${CPF_HASH_PEPPER:-}"` e `CPF_HASH_PEPPER:
/// ${CPF_HASH_PEPPER:-}` são o mesmo valor para o YAML, e a comparação aqui é
/// sobre a expressão interpolada, não sobre a aspa que a embrulha.
String _withoutQuotes(String expression) {
  final value = expression.trim();
  for (final quote in ['"', "'"]) {
    if (value.length >= 2 && value.startsWith(quote) && value.endsWith(quote)) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}
