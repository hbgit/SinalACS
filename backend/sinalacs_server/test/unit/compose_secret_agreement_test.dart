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
///
/// `APP_ENV` entrou nesta tabela no review da rodada 2, pelo mesmo defeito na
/// mesma forma: os três passos de seed em Dart leem a variável (o guarda de
/// `seed_cpf_hashes.dart` e o de `seed_acs_credentials.dart` leem a variável
/// crua; `seed_health_data.dart` a lê por dentro do `AppConfig`), e os dois
/// guardas tratam a variável AUSENTE como `development` — então tirar a linha de
/// um deles não dispara nada: o serviço deixa de recusar e grava dado de
/// desenvolvimento contra o banco que o `SERVERPOD_DATABASE_HOST` apontar.
/// `acs-credential-seed` é o caso caro (grava a credencial do ACS).
const _sharedByServices = <String, List<String>>{
  'CPF_HASH_PEPPER': ['serverpod', 'cpf-hash-seed'],
  'HEALTH_DATA_ENCRYPTION_KEY': ['serverpod', 'health-data-seed'],
  'APP_ENV': [
    'serverpod',
    'cpf-hash-seed',
    'health-data-seed',
    'acs-credential-seed',
  ],
};

/// O `docker-compose.yml` da raiz do repositório.
///
/// Relativo a `backend/sinalacs_server`, que é o cwd do `dart test` — o mesmo
/// pressuposto que `endpoint_auth_posture_test.dart` documenta para
/// `lib/src/endpoints`.
const _composePath = '../../docker-compose.yml';

/// Serviços de seed que NÃO compartilham variável nenhuma com outro processo,
/// cada um com o motivo por escrito.
///
/// É uma allowlist no sentido do `endpoint_auth_posture_test.dart`: acrescentar
/// um passo de seed ao `docker-compose.yml` faz o teste do "contabilizado"
/// falhar até que alguém decida, por escrito, de que lado ele fica. A decisão
/// implícita é o defeito que este teste fecha: na rodada 2 a tabela
/// `_sharedByServices` era escrita à mão e `acs-credential-seed` ficou de fora
/// dela — um serviço de seed que grava credencial de desenvolvimento e que
/// nenhuma linha deste arquivo olhava.
const _seedServicesWithoutSharedVariable = <String, String>{
  'database-seed':
      'roda `psql` com o `development.sql`, FORA do processo Dart: não lê o '
      'pepper, nem a chave de cifra, nem o `APP_ENV` — o `environment` dele é '
      'só o PGPASSWORD',
};

/// O processo que CONSOME os valores em execução (o servidor), não um passo de
/// seed: é o outro lado que `_sharedByServices` prende.
///
/// Tudo o que aparece em `_sharedByServices` além dele tem de ser um passo de
/// seed, e é isso que o teste do "contabilizado" confere — um nome de serviço
/// que não roda seed numa das pontas seria uma comparação sem consequência.
const _runtimeService = 'serverpod';

/// O que faz de um serviço um passo de seed: o `entrypoint` dele invoca um
/// binário `seed_*` desta imagem ou o SQL do diretório de seeds.
///
/// A derivação é pelo `entrypoint`, e não pelo nome do serviço, porque é o
/// `entrypoint` que diz o que o serviço roda — um nome novo não pode nascer
/// fora da checagem por não terminar em `-seed`. Errar aqui é errar para o lado
/// do alarme (um serviço a mais vira uma decisão a escrever), nunca para o lado
/// da absolvição, que é o que este teste existe para impedir.
final _seedEntrypoint = RegExp(r'seed_|/seeds/', caseSensitive: false);

/// Variável de controle da extração.
///
/// `APP_ENV` é declarada com a mesma expressão pelo servidor e pelos três passos
/// de seed em Dart, e é isso que a torna um bom controle: o mecanismo de
/// comparação deste arquivo roda de ponta a ponta sobre o arquivo de verdade e
/// encontra igualdade onde ela existe. Sem ele, uma extração quebrada (que
/// devolvesse `{}` para todo serviço) deixaria a asserção principal vermelha por
/// um motivo que não é o que ela diz, e ninguém saberia qual das duas coisas
/// consertar.
const _controlVariable = 'APP_ENV';
const _controlExpression = r'${APP_ENV:-development}';

void main() {
  test('os serviços que compartilham uma variável recebem a mesma expressão', () {
    final servicos = _servicesByCompose(_composeSource());

    // Sem isto, a mensagem de falha da variável que ficou sem texto sairia com
    // "null" no lugar da explicação — um defeito que só apareceria no dia do
    // RED, quando a mensagem é a única coisa que quem lê tem em mãos.
    for (final variavel in _sharedByServices.keys) {
      expect(
        _whyItMatters[variavel],
        isNotNull,
        reason:
            'a variável `$variavel` está em `_sharedByServices` e não tem '
            'texto em `_whyItMatters` — escreva a consequência do modo de '
            'falha dela antes de prendê-la',
      );
    }

    final offenders = <String>[];
    for (final requisito in _sharedByServices.entries) {
      final variavel = requisito.key;
      final nomes = requisito.value;

      final declaradas = <String, String?>{};
      for (final servico in nomes) {
        if (!servicos.containsKey(servico)) {
          offenders.add(
            '$variavel: o serviço `$servico` não existe em $_composePath. Se ele '
            'foi renomeado, atualize `_sharedByServices` junto — um nome que não '
            'existe isenta o serviço de verdade da checagem em silêncio.',
          );
          declaradas[servico] = null;
          continue;
        }
        declaradas[servico] = servicos[servico]!.environment[variavel];
      }

      final semDeclarar = declaradas.entries
          .where((entry) => entry.value == null)
          .map((entry) => '`${entry.key}`')
          .toList();
      if (semDeclarar.isNotEmpty) {
        final quemDeclara = _emLista(
          declaradas.entries
              .where((entry) => entry.value != null)
              .map((entry) => '`${entry.key}` (${entry.value})'),
        );
        final singular = semDeclarar.length == 1;
        offenders.add(
          '$variavel: ${_emLista(semDeclarar)} ${singular ? 'não declara' : 'não declaram'} '
          'a variável, então ${singular ? 'não recebe' : 'não recebem'} o valor do '
          '`.env` — ${semDeclarar.length == declaradas.length ? _whenNobodyDeclares : 'quem declara é $quemDeclara.'} '
          '${_whyItMatters[variavel]}',
        );
        continue;
      }

      final expressoes = declaradas.map(
        (servico, expressao) => MapEntry(servico, _withoutQuotes(expressao!)),
      );
      if (expressoes.values.toSet().length > 1) {
        final detalhe = _emLista(
          expressoes.entries.map((entry) => '`${entry.key}` usa ${entry.value}'),
        );
        offenders.add('$variavel: $detalhe. ${_whyItMatters[variavel]}');
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('controle: a extração enxerga os serviços de seed e o environment deles', () {
    // O controle é o que separa "as expressões concordam" de "o teste não leu
    // nada": sem ele, uma extração quebrada (que devolvesse mapas vazios) faria
    // a asserção acima acusar ausência de variável em todo mundo, com uma
    // mensagem que não descreve o defeito real.
    final servicos = _servicesByCompose(_composeSource());

    expect(
      servicos.keys,
      containsAll(_declaredServices),
      reason:
          'a extração não reconheceu estes serviços em $_composePath — '
          'conserte o teste antes de confiar na asserção principal',
    );

    for (final servico in _declaredServices) {
      expect(
        servicos[servico]!.environment,
        isNotEmpty,
        reason:
            'o `environment` de `$servico` saiu vazio da extração: ou o '
            'serviço perdeu as variáveis, ou o parser deste teste quebrou',
      );
    }

    // E o valor CONHECIDO, não só a chave: uma extração que devolvesse `''`
    // para toda variável deixaria a comparação da asserção principal verde —
    // dois serviços "concordam" no vazio. São os serviços que o requisito exige
    // para a variável de controle, e é a mesma igualdade que a asserção
    // principal pede para ela, repetida aqui de propósito: o papel deste teste
    // não é a garantia (essa é da asserção principal), é provar que a leitura
    // foi feita, para que uma falha dela não seja lida como falha do compose.
    for (final servico in _sharedByServices[_controlVariable]!) {
      expect(
        _withoutQuotes(servicos[servico]!.environment[_controlVariable] ?? ''),
        _controlExpression,
        reason:
            '`$servico` declara $_controlVariable com outra expressão, ou a '
            'extração não leu o valor. Além de ser o controle da extração, é '
            'requisito real: um seed rodando fora de development se recusa a '
            'rodar, e um servidor em development atendendo um seed que não é '
            'deixa a stack pela metade',
      );
    }
  });

  test('todo passo de seed do compose está contabilizado', () {
    // Sem esta checagem, um serviço de seed novo nasce fora de todas as
    // comparações deste arquivo: a tabela acima é explícita, e nada a obriga a
    // crescer junto com o compose. Foi assim que `acs-credential-seed` — que
    // grava a credencial de desenvolvimento do ACS e lê `APP_ENV` — ficou sem
    // quem prendesse a variável dele.
    final servicos = _servicesByCompose(_composeSource());
    final derivados = _seedServicesIn(servicos);

    expect(
      derivados,
      isNotEmpty,
      reason:
          'a extração não reconheceu nenhum passo de seed em $_composePath: o '
          'parser do `entrypoint` quebrou, e sem ele esta checagem absolveria '
          'todo serviço de seed novo',
    );

    final offenders = <String>[
      for (final servico in derivados.difference(_declaredSeedServices))
        '`$servico` invoca um seed no `entrypoint` '
            '(${servicos[servico]!.entrypoint}) e não está em nenhum lugar '
            'deste teste. Decida por escrito: liste em `_sharedByServices` as '
            'variáveis que ele precisa receber do `.env`, junto com quem as '
            'consome, ou isente-o em `_seedServicesWithoutSharedVariable` com '
            'o motivo',
      for (final servico in _declaredSeedServices.difference(derivados))
        '`$servico` está contabilizado neste teste, mas o `entrypoint` dele '
            '(${servicos[servico]?.entrypoint ?? 'serviço inexistente em '
                    '$_composePath'}) não invoca nenhum seed — se ele deixou de ser '
            'um passo de seed, atualize a contabilização',
    ];

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test(
    'a isenção não guarda serviço que já compartilha variável nem serviço que sumiu',
    () {
      // Entrada obsoleta na isenção é pior que entrada ausente: ela documenta uma
      // isenção que não existe mais e esconde a hora de removê-la — a mesma razão
      // do teste equivalente em `endpoint_auth_posture_test.dart`. E a isenção sem
      // motivo escrito é uma tabela que cala: o motivo é o que faz a próxima
      // pessoa decidir em segundos se o serviço novo pertence a ela.
      final compartilhadaPor = <String, String>{};
      for (final requisito in _sharedByServices.entries) {
        for (final nome in requisito.value) {
          compartilhadaPor[nome] = requisito.key;
        }
      }
      final servicos = _servicesByCompose(_composeSource());
      final derivados = _seedServicesIn(servicos);

      for (final isencao in _seedServicesWithoutSharedVariable.entries) {
        final servico = isencao.key;
        expect(
          isencao.value.trim(),
          isNotEmpty,
          reason:
              'a isenção de `$servico` está sem motivo escrito — escreva o que '
              'faz o serviço não precisar de nenhuma variável compartilhada',
        );
        expect(
          compartilhadaPor[servico],
          isNull,
          reason:
              '`$servico` está isento de compartilhar variável, mas '
              '`_sharedByServices` prende ${compartilhadaPor[servico]} nele — '
              'remova a isenção',
        );
        expect(
          derivados,
          contains(servico),
          reason:
              '`$servico` está isento, mas o `entrypoint` dele não invoca seed '
              'nenhum: ele deixou de ser um passo de seed — remova a isenção',
        );

        // A isenção diz "não compartilha variável nenhuma"; se o compose passou a
        // declarar uma delas no serviço, a frase deixou de ser verdadeira — e a
        // decisão é de novo de quem mexeu, não do próximo leitor.
        final declaradas = [
          for (final variavel in _sharedByServices.keys)
            if (servicos[servico]!.environment.containsKey(variavel)) variavel,
        ];
        expect(
          declaradas,
          isEmpty,
          reason:
              '`$servico` está isento de compartilhar variável, mas o `environment` '
              'dele declara ${declaradas.join(', ')}. Ele pertence ao requisito '
              '(com a MESMA expressão dos outros) ou a linha é engano — a isenção '
              'não pode ficar dizendo que ele não recebe nada',
        );
      }
    },
  );
}

/// Os serviços que este arquivo julga: os passos de seed declarados (pelo
/// requisito ou pela isenção) mais o processo que consome os valores.
///
/// Derivado das duas tabelas, e não uma terceira lista escrita à mão — uma lista
/// a mais é uma lista a mais para esquecer de atualizar, que é o defeito desta
/// rodada.
final _declaredServices = <String>{
  for (final nomes in _sharedByServices.values) ...nomes,
  ..._seedServicesWithoutSharedVariable.keys,
};

/// O lado do requisito que tem de ser um passo de seed: tudo o que o arquivo
/// julga, menos o processo que consome os valores na outra ponta.
final _declaredSeedServices = <String>{
  for (final servico in _declaredServices)
    if (servico != _runtimeService) servico,
};

/// A cláusula que entra quando NINGUÉM do requisito declara a variável.
///
/// Aqui os serviços concordam, a rigor: sem a variável, todos caem no MESMO
/// fallback público de desenvolvimento. O que esta checagem prende é a garantia
/// mais forte — o valor do `.env` tem de chegar a todos —, porque o fallback é
/// versionado e público, e um dos serviços pode trocar de fallback numa linha
/// sem que nada mais acuse. É uma escolha consciente: o RED aqui é por
/// invariante, não por divergência medida.
const _whenNobodyDeclares =
    'nenhum dos serviços deste requisito declara a variável: hoje todos caem no '
    'MESMO fallback público de desenvolvimento e por isso concordam, mas o valor '
    'do `.env` deixa de chegar a eles, que é a garantia que esta checagem existe '
    'para manter.';

/// Por que uma expressão divergente é pior que um erro — por variável, usado nas
/// mensagens de falha, que é onde alguém vai ler isso.
///
/// Cada variável tem o seu: a consequência de um pepper divergente (o login não
/// acha paciente) não é a de um `APP_ENV` ausente (o seed grava credencial de
/// desenvolvimento onde o host apontar), e uma mensagem que descrevesse a outra
/// mandaria quem lê consertar o lugar errado.
const _whyItMatters = <String, String>{
  'CPF_HASH_PEPPER':
      'O seed e o servidor precisam da MESMA expressão: cada um resolve o valor '
      'por conta própria, e um processo sem a variável cai no fallback público '
      'de desenvolvimento enquanto o outro usa o valor do `.env`. A falha é '
      'silenciosa — o seed termina com sucesso, o servidor sobe saudável, e o '
      'login deixa de encontrar qualquer CPF semeado. E o `requestOtp` responde '
      'a mesma coisa que responde para um CPF que não existe: nenhum SMS, '
      'nenhum desafio, nenhum erro.',
  'HEALTH_DATA_ENCRYPTION_KEY':
      'O seed e o servidor precisam da MESMA expressão: o seed grava o '
      'ciphertext que o diretório de pacientes depois tenta decifrar, e um '
      'processo sem a variável cai no hex público de desenvolvimento enquanto o '
      'outro usa o valor do `.env`. A falha é silenciosa — a leitura para na '
      'autenticação do GCM, e o diretório deixa de decifrar o que o seed gravou '
      'sem que nada aponte a variável.',
  'APP_ENV':
      'Todos os passos de seed em Dart leem esta variável, e os guardas de '
      '`seed_cpf_hashes.dart` e `seed_acs_credentials.dart` tratam a variável '
      'AUSENTE como `development`: sem ela o serviço não recusa, não avisa, e '
      'grava dado de desenvolvimento — no `acs-credential-seed`, a credencial '
      'do ACS — contra o banco que o `SERVERPOD_DATABASE_HOST` apontar. Com ela, '
      'um `APP_ENV` que não seja `development` faz o serviço parar com `exit 2`. '
      'Tirar a linha é trocar a recusa por uma gravação, em silêncio, e é por '
      'isso que ela é requisito e não enfeite.',
};

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
/// espaços, `environment:`/`entrypoint:` com 4 e cada item com 6 —, sem
/// `package:yaml`: não é dependência declarada deste pacote, e não se paga uma
/// dependência nova para ler um arquivo cujo formato este repositório controla.
/// Linhas de comentário são ignoradas, e um `#` precedido de espaço é comentário
/// de fim de linha, como no próprio YAML.
///
/// O que a função NÃO entende, ela recusa em vez de devolver um mapa vazio: um
/// `environment:` na forma de lista (`- VAR=valor`) daria o mesmo mapa vazio de
/// um serviço sem variável nenhuma, e o teste acusaria "não declara a variável"
/// pelo motivo errado.
Map<String, _ComposeService> _servicesByCompose(String source) {
  final services = <String, _ComposeService>{};
  var insideServices = false;
  _ComposeService? current;
  var insideEnvironment = false;
  var insideEntrypoint = false;

  for (final raw in source.split('\n')) {
    final line = raw.trimRight();
    final content = line.trimLeft();
    if (content.isEmpty || content.startsWith('#')) continue;

    final indent = line.length - content.length;

    if (indent == 0) {
      // Só `services:` interessa; qualquer outra seção de topo (`volumes:`,
      // `networks:`) encerra a varredura.
      insideServices = content == 'services:';
      current = null;
      insideEnvironment = false;
      insideEntrypoint = false;
      continue;
    }
    if (!insideServices) continue;

    if (indent == 2) {
      final name = content.endsWith(':')
          ? content.substring(0, content.length - 1).trim()
          : '';
      current = name.isEmpty ? null : (services[name] = _ComposeService(name));
      insideEnvironment = false;
      insideEntrypoint = false;
      continue;
    }
    if (current == null) continue;

    if (indent == 4) {
      insideEnvironment = content == 'environment:';
      insideEntrypoint = content.startsWith('entrypoint:');
      if (insideEntrypoint) {
        current.entrypoint = content.substring('entrypoint:'.length).trim();
      }
      continue;
    }

    // Um `entrypoint` em lista (`- /bin/sh`, `- -c`, …) chega uma linha por vez.
    if (indent == 6 && insideEntrypoint) {
      final item = content.startsWith('- ') ? content.substring(2) : content;
      current.entrypoint = '${current.entrypoint} $item'.trim();
      continue;
    }

    if (indent != 6 || !insideEnvironment) continue;

    if (content.startsWith('- ')) {
      throw StateError(
        '$_composePath declara o `environment` de `${current.name}` na forma de '
        'lista, que este teste não lê. Reescreva a extração antes de confiar '
        'nela: um servidor sem variável e um servidor cuja variável o parser '
        'não sabe ler produziriam a mesma acusação.',
      );
    }

    final separator = content.indexOf(':');
    if (separator == -1) continue;
    final key = content.substring(0, separator).trim();
    current.environment[key] = _withoutInlineComment(
      content.substring(separator + 1),
    ).trim();
  }

  return services;
}

/// Um serviço do `docker-compose.yml`, com o que este arquivo lê dele.
class _ComposeService {
  _ComposeService(this.name);

  final String name;

  /// O `environment` como mapa variável → expressão crua.
  final Map<String, String> environment = <String, String>{};

  /// O `entrypoint` com os itens juntos por espaço — vazio quando o serviço não
  /// declara um (`serverpod`, `postgres` e `traefik` declaram `command:` ou
  /// nada, e não passam por aqui).
  String entrypoint = '';
}

/// Os passos de seed do compose, pelo `entrypoint` (ver [_seedEntrypoint]).
Set<String> _seedServicesIn(Map<String, _ComposeService> services) => {
  for (final service in services.values)
    if (_seedEntrypoint.hasMatch(service.entrypoint)) service.name,
};

/// A lista em português: `` `a` ``, `` `b` `` **e** `` `c` `` — e não
/// `` `a`, `b`, `c` `` nem `` `a` e `b` e `c` ``, que é como saía enquanto as
/// mensagens só tinham dois serviços para citar. `APP_ENV` tem quatro.
String _emLista(Iterable<String> itens) {
  final lista = itens.toList();
  if (lista.isEmpty) return '';
  if (lista.length == 1) return lista.single;
  return '${lista.sublist(0, lista.length - 1).join(', ')} e ${lista.last}';
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
