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

  void close();
}

/// Fachada do backend para o app do paciente.
///
/// Mantém um único [Client] e a [AuthSession] corrente. O cliente é o mesmo
/// código gerado por `serverpod generate` que o servidor usa, então qualquer
/// divergência de contrato quebra em tempo de compilação, não em produção.
class BackendClient implements PatientBackend {
  BackendClient({String? host})
      : _client = Client(host ?? BackendConfig.host)
          ..connectivityMonitor = null;

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
    } catch (_) {
      throw const BackendFailure(
        'Sem conexão com o servidor. Verifique a rede e tente de novo.',
      );
    }
  }
}
