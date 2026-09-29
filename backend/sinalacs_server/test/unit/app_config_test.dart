import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:test/test.dart';

/// Regras de aceitação dos segredos de assinatura.
///
/// A validação anterior cobria apenas `APP_ENV=production` e testava só
/// `== null`, então `JWT_SECRET=""` e `APP_ENV=staging` subiam assinando com um
/// valor público — e o `docker-compose.yml` sequer passava a variável.
/// `AUDIT_CHAIN_SECRET` segue exatamente a mesma regra, para a cadeia de hash
/// de `audit_logs`. `CPF_HASH_PEPPER` entrou depois, com a mesma regra.
///
/// Depois de `SMS_GATEWAY`, **nenhuma configuração fora de `development` pode
/// ser construída**: o único gateway implementado é `log`, que só vale em
/// desenvolvimento, e nenhum provedor real foi escolhido (`spec` do RF01). Por
/// isso os casos de SUCESSO daqui montam em `development` — é o único ambiente
/// em que existe configuração válida para os segredos serem observados. Os
/// casos de recusa continuam cobrindo `production`.
void main() {
  AppConfig build({
    required String appEnv,
    String? jwtSecret,
    String? auditChainSecret,
    String? healthDataEncryptionKey,
    String? cpfHashPepper,
    String? smsGateway,
  }) =>
      AppConfig.fromMap({
        'APP_ENV': appEnv,
        'JWT_SECRET': ?jwtSecret,
        'AUDIT_CHAIN_SECRET': ?auditChainSecret,
        'HEALTH_DATA_ENCRYPTION_KEY': ?healthDataEncryptionKey,
        'CPF_HASH_PEPPER': ?cpfHashPepper,
        'SMS_GATEWAY': ?smsGateway,
      });

  group('JWT_SECRET', () {
    test('development sem a variável usa o fallback conhecido', () {
      expect(
        build(appEnv: 'development').jwtSecret,
        AppConfig.developmentJwtSecret,
      );
    });

    test('development aceita um segredo próprio', () {
      expect(
        build(appEnv: 'development', jwtSecret: 'a' * 64).jwtSecret,
        'a' * 64,
      );
    });

    test('production sem a variável não sobe', () {
      expect(
        () => build(appEnv: 'production'),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('JWT_SECRET é obrigatório'),
        )),
      );
    });

    test('staging sem a variável também não sobe', () {
      // A checagem anterior cobria só production.
      expect(() => build(appEnv: 'staging'), throwsA(isA<StateError>()));
    });

    test('string vazia conta como ausente', () {
      expect(
        () => build(appEnv: 'production', jwtSecret: ''),
        throwsA(isA<StateError>()),
      );
    });

    test('string só de espaços conta como ausente', () {
      expect(
        () => build(appEnv: 'production', jwtSecret: '   '),
        throwsA(isA<StateError>()),
      );
    });

    test('o segredo de desenvolvimento não pode ser promovido', () {
      // Está neste repositório versionado: usá-lo fora de development é assinar
      // token com chave pública, e o token carrega papel e microárea.
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: AppConfig.developmentJwtSecret,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('valor de desenvolvimento'),
        )),
      );
    });

    test('os quatro segredos próprios juntos produzem a configuração', () {
      // Cada segredo é resolvido de forma independente: este caso preenche os
      // quatro de uma vez e confere que nenhum sobrescreve o outro.
      final config = build(
        appEnv: 'development',
        jwtSecret: 'b' * 64,
        auditChainSecret: 'd' * 64,
        healthDataEncryptionKey: 'e' * 64,
        cpfHashPepper: 'f' * 64,
      );

      expect(config.jwtSecret, 'b' * 64);
      expect(config.auditChainSecret, 'd' * 64);
      expect(config.healthDataEncryptionKey, 'e' * 64);
      expect(config.cpfHashPepper, 'f' * 64);
    });

    test('espaços em volta do segredo são aparados', () {
      expect(
        build(
          appEnv: 'development',
          jwtSecret: '  ${'c' * 64}  ',
          auditChainSecret: 'd' * 64,
          healthDataEncryptionKey: 'e' * 64,
        ).jwtSecret,
        'c' * 64,
      );
    });
  });

  group('AUDIT_CHAIN_SECRET', () {
    // Mesmas regras de JWT_SECRET, testadas de novo porque cada segredo é
    // resolvido de forma independente: um poderia estar certo e o outro
    // esquecido sem que os testes de JWT_SECRET percebessem.
    test('development sem a variável usa o fallback conhecido', () {
      expect(
        build(appEnv: 'development').auditChainSecret,
        AppConfig.developmentAuditChainSecret,
      );
    });

    test('development aceita um segredo próprio', () {
      expect(
        build(appEnv: 'development', auditChainSecret: 'a' * 64)
            .auditChainSecret,
        'a' * 64,
      );
    });

    test('production sem a variável não sobe', () {
      expect(
        () => build(appEnv: 'production', jwtSecret: 'b' * 64),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('AUDIT_CHAIN_SECRET é obrigatório'),
        )),
      );
    });

    test('string vazia conta como ausente', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'b' * 64,
          auditChainSecret: '',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('o segredo de desenvolvimento não pode ser promovido', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'b' * 64,
          auditChainSecret: AppConfig.developmentAuditChainSecret,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('valor de desenvolvimento'),
        )),
      );
    });

    test('segredo próprio sobe, independente do JWT_SECRET', () {
      final config = build(
        appEnv: 'development',
        jwtSecret: 'b' * 64,
        auditChainSecret: 'd' * 64,
        healthDataEncryptionKey: 'e' * 64,
      );

      expect(config.auditChainSecret, 'd' * 64);
      expect(config.jwtSecret, 'b' * 64);
    });
  });

  group('HEALTH_DATA_ENCRYPTION_KEY', () {
    test('development sem a variável usa o fallback conhecido', () {
      expect(
        build(appEnv: 'development').healthDataEncryptionKey,
        AppConfig.developmentHealthDataEncryptionKey,
      );
    });

    test('production sem a variável não sobe', () {
      expect(
        () => build(appEnv: 'production'),
        throwsA(isA<StateError>()),
      );
    });

    test('production com o valor de desenvolvimento não sobe', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'a' * 64,
          auditChainSecret: 'b' * 64,
          healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
        ),
        throwsA(isA<StateError>()),
      );
    });

    // Formato: diferente de JWT_SECRET/AUDIT_CHAIN_SECRET, que são chaves HMAC
    // de tamanho livre, esta vira uma chave AES-256 byte a byte. Sem validação
    // no boot, uma chave malformada subia o servidor e só quebrava na primeira
    // gravação — falha que TriageSessionService captura de propósito, devolvendo
    // o risco ao paciente e deixando o prontuário sem registro, em silêncio.
    test('chave mais curta que 64 caracteres não sobe', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'a' * 64,
          auditChainSecret: 'b' * 64,
          healthDataEncryptionKey: 'c' * 32,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('HEALTH_DATA_ENCRYPTION_KEY'),
            contains('64'),
          ),
        )),
      );
    });

    test('comprimento ímpar não sobe (truncava em silêncio)', () {
      // 63 caracteres: o `hex.length ~/ 2` de HealthDataCipher descartava o
      // último e produzia uma chave de 31 bytes sem reclamar.
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'a' * 64,
          auditChainSecret: 'b' * 64,
          healthDataEncryptionKey: 'c' * 63,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('caractere não-hexadecimal não sobe, mesmo com 64 caracteres', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'a' * 64,
          auditChainSecret: 'b' * 64,
          healthDataEncryptionKey: '${'a' * 63}z',
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('hexadecimal'),
        )),
      );
    });

    test('64 hexadecimais sobem, em maiúsculas ou minúsculas', () {
      final minusculas = build(
        appEnv: 'development',
        jwtSecret: 'a' * 64,
        auditChainSecret: 'b' * 64,
        healthDataEncryptionKey: '0123456789abcdef' * 4,
      );
      expect(minusculas.healthDataEncryptionKey, '0123456789abcdef' * 4);

      final maiusculas = build(
        appEnv: 'development',
        jwtSecret: 'a' * 64,
        auditChainSecret: 'b' * 64,
        healthDataEncryptionKey: '0123456789ABCDEF' * 4,
      );
      expect(maiusculas.healthDataEncryptionKey, '0123456789ABCDEF' * 4);
    });

    test('a mensagem de erro não vaza a chave', () {
      // Segredo malformado continua sendo segredo: só o comprimento aparece.
      try {
        build(
          appEnv: 'production',
          jwtSecret: 'a' * 64,
          auditChainSecret: 'b' * 64,
          healthDataEncryptionKey: 'segredo-que-nao-deveria-aparecer',
        );
        fail('deveria ter lançado StateError');
      } on StateError catch (error) {
        expect(error.message, isNot(contains('segredo-que-nao-deveria')));
        expect(error.message, contains('32')); // o comprimento recebido
      }
    });

    test('o fallback de desenvolvimento é hexadecimal válido', () {
      // Se deixar de ser, `development` volta a morrer com FormatException na
      // primeira cifragem — foi exatamente o que aconteceu antes.
      expect(
        AppConfig.developmentHealthDataEncryptionKey,
        matches(RegExp(r'^[0-9a-fA-F]{64}$')),
      );
      expect(
        build(appEnv: 'development').healthDataEncryptionKey,
        AppConfig.developmentHealthDataEncryptionKey,
      );
    });
  });

  group('SMS_GATEWAY', () {
    // `log` NÃO envia SMS: escreve o código no log do processo, e por isso só
    // vale em desenvolvimento. Fora dele, subir assim deixa todo paciente sem
    // receber o código de acesso — falha no boot, não no primeiro cadastro.
    test('log fora de development não sobe', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'a' * 64,
          auditChainSecret: 'b' * 64,
          healthDataEncryptionKey: 'c' * 64,
          cpfHashPepper: 'd' * 64,
          smsGateway: 'log',
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('SMS_GATEWAY=log'),
        )),
      );
    });

    test('ausente fora de development não sobe', () {
      // Sem gateway nenhum o servidor sobe incapaz de enviar código.
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'a' * 64,
          auditChainSecret: 'b' * 64,
          healthDataEncryptionKey: 'c' * 64,
          cpfHashPepper: 'd' * 64,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('SMS_GATEWAY é obrigatório'),
        )),
      );
    });
  });

  group('defaults', () {
    test('um ambiente vazio produz a configuração de desenvolvimento', () {
      final config = AppConfig.fromMap(const {});

      expect(config.appEnv, 'development');
      expect(config.mqttBroker, 'localhost:1883');
      expect(config.mqttUseTls, isFalse);
      // Sem gateway escolhido, development cai no `log` — é o que faz a stack
      // local subir com o `SMS_GATEWAY=` vazio do .env gerado pelo bootstrap.
      expect(config.smsGateway, 'log');
      // Gate do auth.developmentLogin: desligado quando não pedido.
      expect(config.enableDevLogin, isFalse);
    });

    test('ENABLE_DEV_LOGIN só liga com a string exata "true"', () {
      expect(AppConfig.fromMap(const {'ENABLE_DEV_LOGIN': 'true'}).enableDevLogin, isTrue);
      expect(AppConfig.fromMap(const {'ENABLE_DEV_LOGIN': 'TRUE'}).enableDevLogin, isFalse);
      expect(AppConfig.fromMap(const {'ENABLE_DEV_LOGIN': '1'}).enableDevLogin, isFalse);
    });
  });
}
