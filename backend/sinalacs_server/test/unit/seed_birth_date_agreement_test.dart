import 'dart:io';

import 'package:test/test.dart';

/// As datas de nascimento do seed de CPF são uma SEGUNDA cópia das que o
/// `development.sql` grava, e nada prendia as duas.
///
/// O login passwordless confere a data de nascimento junto com o CPF, e o
/// `cpf-hash-seed` roda DEPOIS do `database-seed` (é dependência dele no
/// compose): divergindo, o valor do MAPA vence. O desfecho é o mesmo do pepper
/// divergente que o `compose_secret_agreement_test.dart` prende — nenhum erro,
/// nenhum SMS, nenhuma linha vermelha, e um paciente que existe e não entra.
///
/// Não é hipotético: a `…0009` ficou de fora do mapa por descuido do plano, e
/// o que a fez aparecer foi alguém ler os dois arquivos. Nada no repositório
/// comparava estas duas listas.
///
/// Leitura por TEXTO-FONTE, como o `compose_secret_agreement_test.dart`: o mapa
/// é privado do `bin/`, e o que se compara aqui são dois arquivos versionados.
/// Nenhum CPF e nenhuma data de nascimento entram nas mensagens deste arquivo
/// (regra do repositório, e vale para dado sintético também): quem identifica
/// uma divergência é o UUID.
const _seedSourcePath = 'bin/seed_cpf_hashes.dart';
const _sqlPath = 'lib/src/infrastructure/database/seeds/development.sql';

/// UUIDs que o `development.sql` grava em `users` e que o seed de CPF NÃO toca,
/// cada um com o motivo por escrito.
///
/// Allowlist no sentido do `endpoint_auth_posture_test.dart`: um paciente novo
/// no `.sql` faz este teste falhar até que alguém decida, por escrito, de que
/// lado ele fica. É o descuido da `…0009` fechado na outra direção — lá a linha
/// existia no SQL e ninguém escreveu o CPF; aqui ninguém pode simplesmente
/// esquecer.
const _usersForaDoSeedDeCpf = <String, String>{
  '00000000-0000-4000-8000-000000000002':
      'o ACS entra por matrícula e senha (RF07), e um CPF nele seria pior que '
      'faltar: `findByCpfHash` não filtra papel e `verifyOtp` crava '
      '`role: patient`, então o login passwordless emitiria um token de '
      'PACIENTE com o id e a microárea do ACS',
};

void main() {
  test('as datas do seed de CPF são as que o development.sql grava', () {
    final seed = File(_seedSourcePath).readAsStringSync();
    final sql = File(_sqlPath).readAsStringSync();

    final cpfPorUsuario = _mapaDoSeed(seed, '_cpfByUser');
    final dataPorUsuario = _mapaDoSeed(seed, '_birthDateByUser');
    final dataDoSql = _datasDeNascimentoDoSql(sql);

    // Sem estas três, uma extração que parasse de achar as entradas deixaria
    // todas as comparações abaixo vazias — e um teste que não compara nada
    // passa verde, pelo motivo errado. É o mesmo cuidado do `expect(files,
    // isNotEmpty)` do teste de postura dos endpoints.
    expect(
      cpfPorUsuario,
      isNotEmpty,
      reason:
          'não saiu nenhuma entrada de `_cpfByUser` ($_seedSourcePath): a '
          'leitura deste teste quebrou, e nada abaixo está sendo conferido',
    );
    expect(dataPorUsuario, isNotEmpty, reason: 'idem para `_birthDateByUser`');
    expect(
      dataDoSql,
      isNotEmpty,
      reason:
          'não saiu nenhuma data do `INSERT INTO "users"` ($_sqlPath): a '
          'leitura deste teste quebrou, e nada abaixo está sendo conferido',
    );

    final offenders = <String>[
      // Os dois mapas do seed andam juntos: o script recusa (`StateError`,
      // antes de abrir conexão) quando um cobre usuário que o outro não cobre,
      // e aqui a divergência aparece sem precisar rodar o seed.
      for (final uuid in dataPorUsuario.keys.toSet().difference(
        cpfPorUsuario.keys.toSet(),
      ))
        '`$uuid` tem data de nascimento em `_birthDateByUser` e não tem CPF em '
            '`_cpfByUser`: o seed recusa rodar assim, e o login dele nunca vai '
            'achar ninguém',
      for (final uuid in cpfPorUsuario.keys.toSet().difference(
        dataPorUsuario.keys.toSet(),
      ))
        '`$uuid` tem CPF em `_cpfByUser` e não tem data em `_birthDateByUser`: '
            'o seed recusa rodar assim, e o login dele nunca vai achar ninguém',
      for (final entrada in dataPorUsuario.entries)
        ..._offendersDaData(entrada, dataDoSql),
    ];

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('a isenção cobre quem o SQL grava e o seed não toca — e só eles', () {
    // Duas direções, pela mesma razão do teste equivalente em
    // `endpoint_auth_posture_test.dart`: isenção que não isenta nada documenta
    // uma exceção inexistente, e usuário do SQL sem isenção é o próximo
    // paciente que ninguém lembrou de semear.
    final seed = File(_seedSourcePath).readAsStringSync();
    final sql = File(_sqlPath).readAsStringSync();
    final noSeed = {
      ..._mapaDoSeed(seed, '_cpfByUser').keys,
      ..._mapaDoSeed(seed, '_birthDateByUser').keys,
    };
    final noSql = _datasDeNascimentoDoSql(sql);

    for (final isencao in _usersForaDoSeedDeCpf.entries) {
      final uuid = isencao.key;
      expect(
        isencao.value.trim(),
        isNotEmpty,
        reason:
            'a isenção de `$uuid` está sem motivo escrito — é o motivo que faz '
            'a próxima pessoa decidir em segundos se o paciente novo pertence '
            'a ela',
      );
      expect(
        noSeed,
        isNot(contains(uuid)),
        reason:
            '`$uuid` está isento do seed de CPF, mas tem entrada no mapa — '
            'remova a isenção',
      );
      expect(
        noSql,
        contains(uuid),
        reason:
            '`$uuid` está isento, mas não é um `users` do $_sqlPath: o UUID '
            'mudou de lugar ou a linha saiu do seed — remova a isenção',
      );
    }

    final semIsencao = noSql.keys
        .where(
          (uuid) =>
              !noSeed.contains(uuid) &&
              !_usersForaDoSeedDeCpf.containsKey(uuid),
        )
        .toList();
    expect(
      semIsencao,
      isEmpty,
      reason:
          '$_sqlPath grava estes UUIDs em `users` sem entrada no seed de CPF e '
          'sem isenção: ${semIsencao.join(', ')}. Se for paciente, ele existe '
          'e não consegue entrar (o login procura por `cpfHash`, que o SQL '
          'deixa com um literal que nenhum HMAC produz); se não for, escreva a '
          'isenção em `_usersForaDoSeedDeCpf` com o motivo',
    );
  });
}

/// A divergência desta entrada, ou nada quando ela bate com o SQL.
///
/// A mesma data em dois lugares não precisa de comentário; os dois casos em que
/// ela falta são diferentes — a linha não existe no SQL (o `UPDATE` não acharia
/// ninguém) e a linha existe com outra data (o mapa vence) —, e por isso cada um
/// tem a sua mensagem.
Iterable<String> _offendersDaData(
  MapEntry<String, String> entrada,
  Map<String, String> dataDoSql,
) {
  final doSql = dataDoSql[entrada.key];
  if (doSql == null) {
    return [
      '`${entrada.key}` é atualizado pelo seed de CPF e não está no '
          '`INSERT INTO "users"` de $_sqlPath: o `UPDATE` não acharia linha '
          'nenhuma, o seed diria "0 linha(s) atualizada(s)" e o login não '
          'acharia o paciente',
    ];
  }
  if (doSql == entrada.value) return const [];
  return [
    '`${entrada.key}`: a data de nascimento de $_seedSourcePath diverge da de '
        '$_sqlPath. O valor não entra nesta mensagem; abra os dois arquivos. O '
        'login confere a data, e o mapa do seed roda DEPOIS do '
        'database-seed — é ele que vence, e o paciente deixa de entrar sem '
        'nenhum erro',
  ];
}

/// As entradas `'chave': 'valor'` do mapa declarado em [declaracao].
///
/// Casamento por DECLARAÇÃO, como o `_classPattern` do teste de postura: pega o
/// bloco a partir de `<declaracao> = <String, String>{` até o `};` que o fecha,
/// e ignora as linhas de comentário — uma frase citando um UUID em comentário
/// não vale como entrada.
Map<String, String> _mapaDoSeed(String source, String declaracao) {
  final inicio = source.indexOf('$declaracao = <String, String>{');
  expect(
    inicio,
    isNot(-1),
    reason:
        'não achei a declaração `$declaracao = <String, String>{` em '
        '$_seedSourcePath. Este teste lê o arquivo como texto-fonte: se a '
        'declaração mudou de forma, conserte a leitura antes de confiar nela — '
        'um mapa vazio passaria por todas as comparações',
  );
  final fim = source.indexOf('};', inicio);
  expect(
    fim,
    isNot(-1),
    reason:
        'a declaração `$declaracao` em $_seedSourcePath não fecha em `};` — a '
        'leitura deste teste quebrou',
  );

  final corpo = source
      .substring(inicio, fim)
      .split('\n')
      .where((linha) => !linha.trimLeft().startsWith('//'))
      .join('\n');

  final entradas = <String, String>{};
  for (final achado in RegExp(
    r"'([^']+)':\s*'([^']*)'",
  ).allMatches(corpo)) {
    entradas[achado.group(1)!] = achado.group(2)!;
  }
  return entradas;
}

/// As datas de nascimento que o `development.sql` grava em `users`, por UUID.
///
/// A coluna é localizada pelo próprio cabeçalho do `INSERT`, e não por posição
/// fixa: uma coluna nova no meio do `INSERT` não pode deslocar a leitura em
/// silêncio. As duas conferências — a coluna existir no cabeçalho e cada linha
/// ter tantos valores quantas colunas o `INSERT` declara — são o preço de ler
/// SQL por texto, e são o que faz a leitura quebrar ALTO em vez de devolver um
/// mapa menor.
Map<String, String> _datasDeNascimentoDoSql(String source) {
  final insert = RegExp(
    r'INSERT INTO "users" \(([^)]*)\)',
  ).firstMatch(source);
  expect(
    insert,
    isNotNull,
    reason:
        'não achei o `INSERT INTO "users"` em $_sqlPath — a leitura deste '
        'teste quebrou',
  );

  final colunas = insert!
      .group(1)!
      .split(',')
      .map((coluna) => coluna.trim().replaceAll('"', ''))
      .toList();
  final posicaoDoId = colunas.indexOf('id');
  final posicaoDaData = colunas.indexOf('birthDate');
  expect(
    posicaoDaData,
    isNot(-1),
    reason:
        'a coluna `birthDate` não está no cabeçalho do INSERT de $_sqlPath: o '
        'SQL deixou de gravar data de nascimento, e o login que a confere '
        'deixou de achar paciente',
  );
  expect(
    posicaoDoId,
    isNot(-1),
    reason: 'a coluna `id` não está no cabeçalho do INSERT de $_sqlPath',
  );

  final datas = <String, String>{};
  var dentroDosValores = false;
  for (final linha in source.substring(insert.start).split('\n')) {
    final conteudo = linha.trim();
    if (conteudo.isEmpty || conteudo.startsWith('--')) continue;

    if (!dentroDosValores) {
      if (!conteudo.startsWith('VALUES')) continue;
      expect(
        conteudo.substring('VALUES'.length).trim(),
        isEmpty,
        reason:
            'este teste lê os valores uma linha por vez, e o `VALUES` de '
            '$_sqlPath tem conteúdo na mesma linha — conserte a leitura',
      );
      dentroDosValores = true;
      continue;
    }
    if (conteudo.startsWith('ON CONFLICT')) break;
    if (!conteudo.startsWith('(')) continue;

    final valores = _valoresDa(conteudo);
    expect(
      valores.length,
      colunas.length,
      reason:
          'uma linha de valores do INSERT de $_sqlPath saiu com '
          '${valores.length} valores para ${colunas.length} colunas: a leitura '
          'deste teste desalinhou, e comparar datas fora de lugar é pior que '
          'não comparar',
    );
    datas[valores[posicaoDoId]] = valores[posicaoDaData];
  }
  return datas;
}

/// Os valores de uma linha `('…', '…', NOW())`, na ordem das colunas.
///
/// Cada vírgula fora de aspas separa um valor, e as aspas externas saem — o
/// valor é o conteúdo. O arquivo não tem aspa dentro de valor; se passar a ter,
/// a contagem acima quebra e a leitura para, que é a direção certa.
List<String> _valoresDa(String linha) {
  var corpo = linha.trim().substring(1);
  if (corpo.endsWith(',')) corpo = corpo.substring(0, corpo.length - 1);
  if (corpo.endsWith(')')) corpo = corpo.substring(0, corpo.length - 1);

  final valores = <String>[];
  var atual = StringBuffer();
  var dentroDeAspas = false;
  for (var i = 0; i < corpo.length; i++) {
    final caractere = corpo[i];
    if (caractere == "'") {
      dentroDeAspas = !dentroDeAspas;
      continue;
    }
    if (caractere == ',' && !dentroDeAspas) {
      valores.add(atual.toString().trim());
      atual = StringBuffer();
      continue;
    }
    atual.write(caractere);
  }
  valores.add(atual.toString().trim());
  return valores;
}
