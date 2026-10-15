import 'dart:io';

import 'package:test/test.dart';

/// O admin de desenvolvimento (ADM-001, issue #39) existe em DOIS processos que
/// não se enxergam: o `development.sql` (roda por `psql`) grava `users` e
/// `staff_accounts`, e o `seed_acs_credentials.dart` grava a credencial no UUID
/// que o SQL escolheu. Divergindo, o resultado é silencioso, no estilo do
/// `seed_birth_date_agreement_test.dart`: a credencial vai para um id sem
/// `staff_accounts` (ou a FK de `users` falha) e o admin simplesmente não entra.
///
/// `DEV_ADMIN_PASSWORD` precisa estar em quatro lugares: sem ela no compose o
/// seed não recebe a senha; sem ela no `bootstrap_env.sh` ou no `.env.example`
/// um clone limpo sobe sem admin.
///
/// Leitura por TEXTO-FONTE; nenhuma senha entra nestas mensagens.
const _adminId = '00000000-0000-4000-8000-000000000090';
const _adminEnrollment = 'ADM-001';
const _adminPasswordVar = 'DEV_ADMIN_PASSWORD';

const _sqlPath = 'lib/src/infrastructure/database/seeds/development.sql';
const _seedPath = 'bin/seed_acs_credentials.dart';
const _envFiles = <String>[
  '../../docker-compose.yml',
  '../../scripts/dev/bootstrap_env.sh',
  '../../.env.example',
];

void main() {
  test('o UUID e a matrícula do admin concordam entre o SQL e o seed de credencial', () {
    final sql = File(_sqlPath).readAsStringSync();
    final seed = File(_seedPath).readAsStringSync();

    final offenders = <String>[
      if (!sql.contains(_adminId)) '$_sqlPath não grava o UUID $_adminId',
      if (!sql.contains("'$_adminEnrollment'"))
        '$_sqlPath não grava a matrícula $_adminEnrollment em staff_accounts',
      if (!sql.contains('staff_accounts'))
        '$_sqlPath não insere em staff_accounts',
      if (!seed.contains(_adminId))
        '$_seedPath não grava credencial para o UUID $_adminId',
      if (!seed.contains(_adminPasswordVar))
        '$_seedPath não lê $_adminPasswordVar',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('o admin do SQL é role admin, sem microárea', () {
    final sql = File(_sqlPath).readAsStringSync();
    final linha = RegExp(
      "\\('$_adminId'[^\\n]*",
    ).allMatches(sql).map((m) => m.group(0)!).firstWhere(
          (l) => l.contains("'admin'"),
          orElse: () => '',
        );
    expect(linha, isNotEmpty, reason: 'não há linha de users com role admin para $_adminId');
    expect(linha, contains('NULL'), reason: 'o admin não pertence a microárea (microAreaId NULL)');
  });

  test('$_adminPasswordVar está no compose, no bootstrap e no .env.example', () {
    final offenders = <String>[
      for (final path in _envFiles)
        if (!File(path).readAsStringSync().contains(_adminPasswordVar))
          '$path não menciona $_adminPasswordVar',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
