import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart';
import 'package:sinalacs_patient/core/network/auth_session.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';

/// Falha já traduzida para a pessoa que está usando o app.
///
/// O backend é RPC tipado, então o erro chega como exceção declarada no
/// `.spy.yaml` — não como código HTTP. Traduzir aqui mantém a UI livre de
/// `try/catch` espalhado e garante mensagem em português.
class BackendFailure implements Exception {
  const BackendFailure(this.message, {this.isRecoverable = true});

  final String message;

  /// `false` quando repetir a mesma ação não deve resolver (rota desligada,
  /// permissão negada).
  final bool isRecoverable;

  @override
  String toString() => message;
}

/// Recusa um host de RPC que não esteja em **HTTPS** (RNF04/L-08).
///
/// Existe porque a rede do sistema operacional **não** segura mais nada: a Task
/// 4 deste plano mediu que o `network_security_config.xml` não bloqueia o
/// cleartext do `dart:io` (quatro variantes, com o controle de que a config
/// estava aplicada dentro do APK, e o POST em claro saiu assim mesmo). A única
/// decisão que resta é a do aplicativo — e [BackendConfig.host] é uma constante
/// de compilação: um `--dart-define=SINALACS_HOST=http://…` "funcionava", isto
/// é, subia e falava em texto claro sem nada vermelho em lugar nenhum.
///
/// Função pura de propósito: é o único ponto onde o defeito ("aceitar http")
/// consegue ficar vermelho num teste hermético, porque o valor validado é um
/// parâmetro e não a constante de compilação.
String requireSecureHost(String host) {
  final uri = Uri.tryParse(host);
  if (uri == null || !uri.isScheme('https')) {
    throw BackendFailure(
      'O endereço do backend ($host) não está em HTTPS. A porta 8080 em texto '
      'claro não é mais publicada (RNF04): use https://… em SINALACS_HOST.',
      isRecoverable: false,
    );
  }
  return host;
}

/// Contrato do backend visto pela UI do paciente.
///
/// A UI depende desta abstração, nunca do [Client] gerado — mesmo padrão que o
/// servidor usa entre `application/` e `infrastructure/` (`AlertPublisher`,
/// `AlertStore`). É o que permite testar as telas sem rede.
abstract class PatientBackend {
  AuthSession? get session;

  bool get isAuthenticated;

  Future<ServiceHealth> health();

  /// Pede o código de acesso (RF01). A resposta não diz se o CPF existe.
  Future<void> requestOtp({
    required String cpf,
    required DateTime birthDate,
  });

  /// Verifica o código e abre a sessão do paciente (RF01).
  ///
  /// Diferente do ACS, **não há renovação silenciosa**: o código OTP é de uso
  /// único e não existe credencial reutilizável. Quando a sessão de 1 hora
  /// expira, o app manda a pessoa autenticar de novo — é a consequência
  /// registrada de adiar o refresh token de LGPD-RT06.
  Future<AuthSession> verifyOtp({
    required String cpf,
    required String code,
  });

  /// Login de DESENVOLVIMENTO, para `tool/` e `integration_test/` contra a
  /// stack local. Exige `ENABLE_DEV_LOGIN=true`. **Não** é o caminho do
  /// produto — RF01 é [requestOtp]/[verifyOtp].
  Future<AuthSession> developmentLogin({required String role});

  Future<RiskLevel> evaluateTriage({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  });

  /// Status do alerta mais recente do paciente autenticado (RF05, decisão
  /// §5). `found: false` quando o paciente nunca disparou um alerta.
  Future<AlertStatusResult> statusFor();

  Future<RedAlertResult> createRedAlert({
    required String idempotencyKey,
    required String locationHash,
    String? locationCell,
  });

  /// Conclui o onboarding a partir de um convite do ACS, gravando os 3
  /// consentimentos por finalidade (LGPD-RF02) e ativando a sessão.
  Future<AuthSession> completeEnrollment({
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
  });

  /// Condições crônicas do próprio paciente autenticado (tela "Perfil
  /// clínico"). `patientId` nunca é argumento — o servidor deriva do token
  /// (INV-05), mesma ressalva de [statusFor].
  Future<List<String>> myChronicConditions();

  /// Grava a lista de condições crônicas do próprio paciente autenticado,
  /// substituindo a anterior por inteiro — não é um merge.
  Future<void> updateChronicConditions(List<String> conditions);

  /// Painel "Meus Dados" (LGPD): confirmação de existência de tratamento e
  /// acesso aos dados pessoais do próprio paciente autenticado.
  Future<PatientDataOverview> myData();

  void close();
}

/// O backend de um app cujo host de RPC não está em HTTPS (RNF04/L-08).
///
/// Existe porque o boot **não pode morrer por configuração** — a mesma política
/// que o asset da CA recebeu em `main.dart`. Como o [BackendClient] se recusa a
/// ser construído com um host em texto claro (é o que [requireSecureHost]
/// garante), o `main` monta este no lugar dele: o app sobe, a tela de login
/// aparece, e **toda** chamada falha com [failure], que nomeia o host e diz o
/// que fazer.
///
/// O que havia antes: a falha do host era capturada pelo `catch` da leitura do
/// asset da CA, que logava "CA do RPC não pôde ser carregada" (**falso** — a CA
/// tinha carregado) e, na linha seguinte, construía o cliente sem CA fora de
/// qualquer guarda, o que subia antes do `runApp`. Log mentindo sobre a causa e
/// app que não subia, para quem seguisse a receita antiga de
/// `--dart-define=SINALACS_HOST=http://…`.
class MisconfiguredBackend implements PatientBackend {
  const MisconfiguredBackend(this.failure);

  /// O motivo, como [requireSecureHost] o produziu.
  final BackendFailure failure;

  @override
  AuthSession? get session => null;

  @override
  bool get isAuthenticated => false;

  /// Recusa uma chamada. `Never` avisa o analisador de que nada abaixo disto
  /// executa, então cada método abaixo é uma linha só.
  Never _recusar() => throw failure;

  @override
  Future<ServiceHealth> health() async => _recusar();

  @override
  Future<void> requestOtp({required String cpf, required DateTime birthDate}) async =>
      _recusar();

  @override
  Future<AuthSession> verifyOtp({required String cpf, required String code}) async =>
      _recusar();

  @override
  Future<AuthSession> developmentLogin({required String role}) async => _recusar();

  @override
  Future<RiskLevel> evaluateTriage({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async =>
      _recusar();

  @override
  Future<AlertStatusResult> statusFor() async => _recusar();

  @override
  Future<RedAlertResult> createRedAlert({
    required String idempotencyKey,
    required String locationHash,
    String? locationCell,
  }) async =>
      _recusar();

  @override
  Future<AuthSession> completeEnrollment({
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
  }) async =>
      _recusar();

  @override
  Future<List<String>> myChronicConditions() async => _recusar();

  @override
  Future<void> updateChronicConditions(List<String> conditions) async => _recusar();

  @override
  Future<PatientDataOverview> myData() async => _recusar();

  /// Fechar **não** é uma chamada ao backend: não há o que fechar, e um `close`
  /// que lançasse derrubaria o `finally` de quem só queria encerrar.
  @override
  void close() {}
}

/// Fachada do backend para o app do paciente.
///
/// Mantém um único [Client] e a [AuthSession] corrente. O cliente é o mesmo
/// código gerado por `serverpod generate` que o servidor usa, então qualquer
/// divergência de contrato quebra em tempo de compilação, não em produção.
class BackendClient implements PatientBackend {
  /// [trustedCaBytes] é a CA de desenvolvimento do RPC (RNF04). `null` faz o
  /// cliente usar o armazenamento de confiança do sistema — que **não** conhece
  /// a CA local, e por isso a conexão falha de forma explícita em vez de ser
  /// aceita às cegas. Nunca instale um `badCertificateCallback` que aceite tudo:
  /// a verificação de hostname é o que impede um certificado de outro host de
  /// passar, e ceder aqui anularia RNF04 exatamente no ponto onde ele mais
  /// importa.
  BackendClient({String? host, List<int>? trustedCaBytes})
      : _client = Client(
          // Só o host que veio do `--dart-define` (o default de compilação) é
          // validado. Um host **explícito** passa como veio: é o caminho dos
          // testes herméticos, que apontam para servidores fake em
          // `http://127.0.0.1:<porta efêmera>/` — validá-lo quebraria testes
          // que precisam ficar verdes.
          resolveHost(host),
          // `SecurityContext()` já vem com `withTrustedRoots: false`, isto é,
          // **só** a CA passada abaixo é aceita — nenhuma autoridade pública.
          // Mesma técnica (e mesma escolha) do `MqttSecureClient` do app ACS.
          securityContext: trustedCaBytes == null
              ? null
              : (SecurityContext()..setTrustedCertificatesBytes(trustedCaBytes)),
        )..connectivityMonitor = null;

  /// O host efetivo do cliente, com a validação de HTTPS do default.
  ///
  /// [defaultHost] só existe para o teste poder exercitar este caminho: o valor
  /// real é [BackendConfig.host], resolvido em tempo de **compilação**, e por
  /// isso não muda dentro de um `flutter test`. Sem ele, a linha do `??` — que
  /// é justamente onde a validação entra — ficaria sem teste que falhe no
  /// defeito.
  static String resolveHost(String? host, {String? defaultHost}) =>
      host ?? requireSecureHost(defaultHost ?? BackendConfig.host);

  final Client _client;

  AuthSession? _session;

  @override
  AuthSession? get session => _session;

  @override
  bool get isAuthenticated {
    final current = _session;
    return current != null && !current.isExpired();
  }

  /// Token válido para as chamadas autenticadas.
  ///
  /// Sem renovação automática (ver [verifyOtp]): se a sessão expirou, quem
  /// chama recebe uma falha não recuperável e a tela precisa mandar a pessoa
  /// entrar de novo. Inventar uma renovação aqui exigiria ou guardar a
  /// credencial — que para o paciente não existe — ou um refresh token, que
  /// LGPD-RT06 exige e este plano deliberadamente não implementa.
  Future<String> _requireToken() async {
    final current = _session;
    if (current != null && !current.isExpired()) return current.accessToken;

    throw const BackendFailure(
      'Sua sessão expirou. Entre novamente com o código de acesso.',
      isRecoverable: false,
    );
  }

  @override
  Future<ServiceHealth> health() {
    return _guard(() => _client.health.check());
  }

  /// Pede o código de acesso (RF01).
  ///
  /// Devolve `void` porque a resposta **não** diz se o CPF existe: o servidor
  /// trata "não encontrado", "data de nascimento errada" e "pedido repetido
  /// dentro do intervalo mínimo" de forma idêntica e silenciosa
  /// (anti-enumeração), e a tela avança para o passo do código nos três casos.
  /// A única recusa que sobra é o dígito verificador inválido, que chega como
  /// [BackendFailure] com a mensagem que o servidor escolheu.
  ///
  /// A repetição silenciosa tem uma consequência que é DESTE lado: o servidor
  /// não diz mais "aguarde um minuto", porque esse aviso só é alcançável por
  /// quem já acertou CPF e nascimento — ou seja, seria o próprio verificador
  /// do par. Quem pedir de novo dentro do minuto só pode ser avisado aqui, que
  /// é quem sabe quando o pedido anterior saiu (seguimento registrado no
  /// `PROGRESS.md`, no que ficou de fora do RF01).
  @override
  Future<void> requestOtp({
    required String cpf,
    required DateTime birthDate,
  }) {
    return _guard(
      () => _client.auth.requestOtp(cpf: cpf, birthDate: birthDate),
    );
  }

  /// Verifica o código de uso único e abre a sessão do paciente (RF01).
  ///
  /// A sessão emitida aqui é a do produto — ver [_requireToken] para o que
  /// acontece quando ela expira.
  @override
  Future<AuthSession> verifyOtp({
    required String cpf,
    required String code,
  }) async {
    final result = await _guard(
      () => _client.auth.verifyOtp(cpf: cpf, code: code),
    );

    final session = AuthSession.tryParse(result.accessToken, result.tokenType);
    if (session == null) {
      throw const BackendFailure(
        'O servidor devolveu um token que o aplicativo não entendeu.',
        isRecoverable: false,
      );
    }

    _session = session;
    return session;
  }

  /// Login de desenvolvimento. Ver ressalvas em [AuthSession].
  @override
  Future<AuthSession> developmentLogin({required String role}) async {
    final result = await _guard(
      () => _client.auth.developmentLogin(role: role),
    );

    final session = AuthSession.tryParse(result.accessToken, result.tokenType);
    if (session == null) {
      throw const BackendFailure(
        'O servidor devolveu um token que o aplicativo não entendeu.',
        isRecoverable: false,
      );
    }

    _session = session;
    return session;
  }

  /// Classificação de risco pelo motor determinístico do servidor.
  ///
  /// A regra de risco vive **só** no servidor (INV-02): o app envia sintomas e
  /// exibe o que voltar. Não recalcule nem ajuste o resultado aqui.
  @override
  Future<RiskLevel> evaluateTriage({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async {
    final token = await _requireToken();
    final result = await _guard(
      () => _client.triage.evaluate(
        accessToken: token,
        chestPain: chestPain,
        difficultyBreathing: difficultyBreathing,
        fever: fever,
        persistentVomiting: persistentVomiting,
        bleeding: bleeding,
        severeWeakness: severeWeakness,
      ),
    );
    return result.risk;
  }

  /// Ver ressalva de [PatientBackend.statusFor]. `patientId` nunca é
  /// argumento — o servidor deriva do token (INV-05).
  @override
  Future<AlertStatusResult> statusFor() async {
    final token = await _requireToken();
    return _guard(() => _client.alerts.statusFor(accessToken: token));
  }

  /// Dispara o alerta vermelho.
  ///
  /// [idempotencyKey] precisa ser **estável para a mesma tentativa do usuário**:
  /// é o que impede que um retry vire um segundo alerta. [locationHash] é o
  /// hash da localização — coordenada crua nunca sai do dispositivo (LGPD).
  /// [locationCell] é a célula de baixa resolução (~1,1 km) que o mapa do ACS
  /// usa para desenhar uma área de incerteza; opcional porque a localização
  /// pode não estar disponível.
  @override
  Future<RedAlertResult> createRedAlert({
    required String idempotencyKey,
    required String locationHash,
    String? locationCell,
  }) async {
    final token = await _requireToken();
    return _guard(
      () => _client.alerts.createRedAlert(
        accessToken: token,
        idempotencyKey: idempotencyKey,
        locationHash: locationHash,
        locationCell: locationCell,
      ),
    );
  }

  /// Conclui o onboarding a partir de um convite do ACS. Ver ressalvas em
  /// [AuthSession] — a sessão emitida aqui é a mesma forma de [verifyOtp].
  @override
  Future<AuthSession> completeEnrollment({
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
  }) async {
    final result = await _guard(
      () => _client.onboarding.completeEnrollment(
        token: token,
        healthDataConsent: healthDataConsent,
        remindersConsent: remindersConsent,
        pushConsent: pushConsent,
      ),
    );
    final session = AuthSession.tryParse(result.accessToken, result.tokenType);
    if (session == null) {
      throw const BackendFailure(
        'O servidor devolveu um token que o aplicativo não entendeu.',
        isRecoverable: false,
      );
    }
    _session = session;
    return session;
  }

  /// Ver ressalva de [PatientBackend.myChronicConditions]. `patientId` nunca
  /// é argumento — o servidor deriva do token (INV-05).
  @override
  Future<List<String>> myChronicConditions() async {
    final token = await _requireToken();
    return _guard(() => _client.patients.myChronicConditions(accessToken: token));
  }

  @override
  Future<void> updateChronicConditions(List<String> conditions) async {
    final token = await _requireToken();
    await _guard(
      () => _client.patients.updateChronicConditions(
        accessToken: token,
        conditions: conditions,
      ),
    );
  }

  @override
  Future<PatientDataOverview> myData() async {
    final token = await _requireToken();
    return _guard(() => _client.patients.myData(accessToken: token));
  }

  @override
  void close() => _client.close();

  /// Traduz as exceções tipadas do backend para [BackendFailure].
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on EndpointDisabledException {
      // ENABLE_DEV_LOGIN=false. O servidor responde como se a rota não
      // existisse, de propósito.
      throw const BackendFailure(
        'O acesso de desenvolvimento está desativado neste servidor.',
        isRecoverable: false,
      );
    } on AlertPermissionException {
      throw const BackendFailure(
        'Este acesso não tem permissão para esta ação.',
        isRecoverable: false,
      );
    } on AlertValidationException catch (error) {
      throw BackendFailure(error.message, isRecoverable: false);
    } on EnrollmentException catch (error) {
      // Token inválido/expirado/consumido ou consentimento obrigatório
      // recusado — nenhum caso é resolvido tentando de novo sem mudar nada.
      throw BackendFailure(error.message, isRecoverable: false);
    } on OtpRequestException catch (error) {
      // Recusa do login passwordless (RF01). A mensagem é a do servidor de
      // propósito: ela já é única para todas as causas, para não dizer se
      // aquele CPF está cadastrado.
      throw BackendFailure(error.message, isRecoverable: false);
    } on AlertDispatchUnavailableException {
      // O alerta FOI gravado; só a publicação imediata falhou. Dizer que
      // "falhou" seria mentira e faria a pessoa tentar de novo sem necessidade.
      throw const BackendFailure(
        'Alerta registrado. A rede está instável e ele será entregue à equipe '
        'assim que a conexão voltar.',
      );
    } on ServerpodClientException catch (error) {
      throw BackendFailure(
        'Não foi possível falar com o servidor (${error.statusCode}).',
      );
    } on TlsException {
      // Medido: uma CA que não assina o certificado do Traefik chega aqui como
      // `HandshakeException` (que é um `TlsException`) **cru**, sem vir
      // embrulhado pelo cliente gerado. Sem esta cláusula, ela cai no
      // `catch (_)` e a pessoa lê "sem conexão com o servidor" — que manda
      // procurar rede onde o problema é o certificado, que é exatamente a
      // confusão que a RNF04 não pode produzir.
      throw const BackendFailure(
        'Não foi possível confirmar a identidade do servidor (certificado '
        'TLS). Verifique a instalação e tente de novo.',
        isRecoverable: false,
      );
    } catch (_) {
      throw const BackendFailure(
        'Sem conexão com o servidor. Verifique a rede e tente de novo.',
      );
    }
  }
}
