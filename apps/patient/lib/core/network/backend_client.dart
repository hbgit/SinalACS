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

  Future<AuthSession> login();

  Future<RiskLevel> evaluateTriage({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  });

  Future<RedAlertResult> createRedAlert({
    required String idempotencyKey,
    required String locationHash,
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

  /// Token válido para as chamadas que exigem autenticação.
  ///
  /// Reautentica sozinho quando o token de 15 minutos expirou — sem isso, um
  /// fluxo demorado falha com erro de permissão, que esconde a causa real.
  Future<String> _requireToken() async {
    if (!isAuthenticated) await login();
    final current = _session;
    if (current == null) {
      throw const BackendFailure('Sessão não iniciada.', isRecoverable: false);
    }
    return current.accessToken;
  }

  @override
  Future<ServiceHealth> health() {
    return _guard(() => _client.health.check());
  }

  /// Autentica como paciente. Ver ressalvas em [AuthSession].
  @override
  Future<AuthSession> login() async {
    final result = await _guard(
      () => _client.auth.developmentLogin(role: 'patient'),
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
    final result = await _guard(
      () => _client.triage.evaluate(
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

  /// Dispara o alerta vermelho.
  ///
  /// [idempotencyKey] precisa ser **estável para a mesma tentativa do usuário**:
  /// é o que impede que um retry vire um segundo alerta. [locationHash] é o
  /// hash da localização — coordenada crua nunca sai do dispositivo (LGPD).
  @override
  Future<RedAlertResult> createRedAlert({
    required String idempotencyKey,
    required String locationHash,
  }) async {
    final token = await _requireToken();
    return _guard(
      () => _client.alerts.createRedAlert(
        accessToken: token,
        idempotencyKey: idempotencyKey,
        locationHash: locationHash,
      ),
    );
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
