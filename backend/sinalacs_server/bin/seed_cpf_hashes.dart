import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';

/// Quarta metade do seed de desenvolvimento: os hashes de CPF do RF01.
///
/// `seeds/development.sql` gravava literais (`'development-patient'`) porque
/// nenhum código calculava CPF. Agora que o login procura por
/// `users.cpfHash = HMAC(cpf)`, um literal nunca casa — e o paciente de
/// desenvolvimento não conseguiria entrar.
///
/// CPFs SINTÉTICOS, os exemplos da documentação do algoritmo de dígito
/// verificador — `00000000191` é o menor número com DV válido, o vetor de
/// teste clássico do algoritmo. **Nunca** um CPF real (regra do repositório:
/// nada de dado real em seed, teste ou log).
///
/// O ACS (`…0002`) NÃO entra aqui, e não é esquecimento: `findByCpfHash` não
/// filtra por papel e `verifyOtp` crava `role: UserRole.patient`, então um CPF
/// no usuário do ACS faria o login passwordless emitir um **token de paciente
/// com o id e a microárea do ACS**. Ele entra por matrícula e senha (RF07).
const _cpfByUser = <String, String>{
  '00000000-0000-4000-8000-000000000001': '12345678909',
  '00000000-0000-4000-8000-000000000005': '98765432100',
  '00000000-0000-4000-8000-000000000006': '11144477735',
  '00000000-0000-4000-8000-000000000007': '52998224725',
  '00000000-0000-4000-8000-000000000008': '16899535009',
  // A paciente de OUTRA microárea (`…0099`). O que a mantém fora do alcance do
  // ACS de desenvolvimento é o território que vai no token dela, não a falta de
  // CPF: sem uma entrada aqui ela não era "uma paciente que não consegue
  // entrar", era uma paciente que não tinha como ser exercitada em nada.
  '00000000-0000-4000-8000-000000000009': '00000000191',
};

/// Datas de nascimento correspondentes (as mesmas do `development.sql`: o login
/// confere a data, então divergir daqui é um paciente que existe e não entra).
const _birthDateByUser = <String, String>{
  '00000000-0000-4000-8000-000000000001': '1990-01-01',
  '00000000-0000-4000-8000-000000000005': '1975-03-10',
  '00000000-0000-4000-8000-000000000006': '1988-07-22',
  '00000000-0000-4000-8000-000000000007': '1962-11-30',
  '00000000-0000-4000-8000-000000000008': '1999-05-14',
  '00000000-0000-4000-8000-000000000009': '1970-01-01',
};

/// Recusa, antes de abrir conexão, quando os dois mapas não cobrem os mesmos
/// usuários.
///
/// Sem esta checagem a divergência falha **no meio do laço**, depois de já ter
/// atualizado as linhas anteriores, e como erro de Postgres (`birthDate` é
/// `NOT NULL`) — que não diz qual entrada do mapa ficou pela metade. Comparar
/// as chaves é barato e nomeia a entrada: os UUIDs identificam a linha em
/// `development.sql` sem depender do CPF, que não pode aparecer em mensagem de
/// erro.
void _assertSameUserKeys() {
  final semCpf = _birthDateByUser.keys.toSet().difference(
    _cpfByUser.keys.toSet(),
  );
  final semData = _cpfByUser.keys.toSet().difference(
    _birthDateByUser.keys.toSet(),
  );
  if (semCpf.isEmpty && semData.isEmpty) return;

  throw StateError(
    'Os dois mapas deste seed precisam cobrir os mesmos usuários'
    '${semCpf.isEmpty ? '' : '; sem CPF em _cpfByUser: ${semCpf.join(', ')}'}'
    '${semData.isEmpty ? '' : '; sem data em _birthDateByUser: ${semData.join(', ')}'}.',
  );
}

Future<void> main(List<String> args) async {
  final env = Platform.environment;

  // A guarda lê a variável CRUA, e não `config.appEnv`: `AppConfig` valida os
  // segredos no construtor e lança ANTES de devolver config, então uma guarda
  // escrita depois dele nunca é quem recusa — fora de development quem recusa
  // primeiro é o construtor (`JWT_SECRET` ausente, `SMS_GATEWAY` inválido), com
  // a mensagem dele. Hoje a proteção real deste script é uma regra sobre SMS,
  // avaliada por acidente; no dia em que existir um gateway de verdade, é esta
  // guarda que fica. É o mesmo arranjo de `seed_acs_credentials.dart`, cuja
  // guarda é alcançável justamente por isso.
  final appEnv = env['APP_ENV'] ?? 'development';
  if (appEnv != 'development') {
    stderr.writeln(
      'Recusando rodar: este script grava CPFs SINTÉTICOS de desenvolvimento e '
      'APP_ENV=$appEnv.',
    );
    exit(2);
  }

  final config = AppConfig.fromEnvironment();

  // Sem a variável, o driver do Postgres falha com `28P01 password
  // authentication failed`, que não diz qual variável faltou — e rodando o
  // binário à mão é fácil esquecê-la, já que no compose ela vem por `:?`.
  final databasePassword = env['SERVERPOD_DATABASE_PASSWORD'];
  if (databasePassword == null || databasePassword.isEmpty) {
    stderr.writeln(
      'SERVERPOD_DATABASE_PASSWORD não definida. No `docker compose` ela vem do '
      '.env; rodando o binário à mão, exporte-a.',
    );
    exit(2);
  }

  _assertSameUserKeys();

  // A MESMA instância que o servidor usa, pelo mesmo pepper: se divergirem,
  // nenhum CPF do seed é encontrado no login.
  final hasher = HmacCpfHasher(pepper: config.cpfHashPepper);

  final connection = await Connection.open(
    Endpoint(
      host: env['SERVERPOD_DATABASE_HOST'] ?? 'localhost',
      port: int.parse(env['SERVERPOD_DATABASE_PORT'] ?? '5432'),
      database: env['SERVERPOD_DATABASE_NAME'] ?? 'sinalacs_db',
      username: env['SERVERPOD_DATABASE_USER'] ?? 'sinalacs_user',
      password: databasePassword,
    ),
    settings: ConnectionSettings(
      sslMode: env['SERVERPOD_DATABASE_REQUIRE_SSL'] == 'true'
          ? SslMode.require
          : SslMode.disable,
    ),
  );

  try {
    var atualizados = 0;
    for (final entry in _cpfByUser.entries) {
      final cpf = Cpf.tryParse(entry.value);
      if (cpf == null) {
        // Falha alto em vez de gravar um hash de CPF inválido: um DV errado no
        // mapa acima produziria um paciente que existe e não consegue entrar.
        throw StateError('CPF sintético inválido para ${entry.key}');
      }
      final result = await connection.execute(
        Sql.named(
          'UPDATE "users" '
          '   SET "cpfHash" = @cpfHash, "birthDate" = @birthDate::date, '
          '       "updatedAt" = NOW() '
          ' WHERE "id" = @id',
        ),
        parameters: {
          'cpfHash': hasher.hash(cpf),
          'birthDate': _birthDateByUser[entry.key],
          'id': entry.key,
        },
      );
      atualizados += result.affectedRows;
    }
    stdout.writeln(
      'Seed de CPF (RF01): $atualizados linha(s) de users atualizada(s).',
    );
  } finally {
    await connection.close();
  }
}
