import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

/// Falha já traduzida para a pessoa que está usando o app.
///
/// O backend é RPC tipado, então o erro chega como exceção declarada no
/// `.spy.yaml` — não como código HTTP.
class BackendFailure implements Exception {
  const BackendFailure(this.message, {this.isRecoverable = true});

  final String message;

  /// `false` quando repetir a mesma ação não deve resolver.
  final bool isRecoverable;

  @override
  String toString() => message;
}

/// Contrato do backend visto pela UI do ACS.
///
/// A UI depende desta abstração, nunca do [Client] gerado — mesmo padrão que o
/// servidor usa entre `application/` e `infrastructure/`.
abstract class AcsBackend {
  AuthSession? get session;

  bool get isAuthenticated;

  Future<ServiceHealth> health();

  Future<AuthSession> login();

  Future<AlertAckResult> acknowledge({required String alertId});

  Future<List<VisitSyncResult>> syncVisits(List<VisitSyncEntry> visits);

  void close();
}

/// Fachada do backend para o app do ACS.
class BackendClient implements AcsBackend {
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
  /// Reautentica sozinho quando o token de 15 minutos expirou — sem isso, um
  /// turno de campo longo passa a falhar com erro de permissão, que esconde a
  /// causa real.
  Future<String> _requireToken() async {
    if (!isAuthenticated) await login();
    final current = _session;
    if (current == null) {
      throw const BackendFailure('Sessão não iniciada.', isRecoverable: false);
    }
    return current.accessToken;
  }

  @override
  Future<ServiceHealth> health() => _guard(() => _client.health.check());

  /// Autentica como ACS. Ver ressalvas em [AuthSession].
  @override
  Future<AuthSession> login() async {
    final result = await _guard(
      () => _client.auth.developmentLogin(role: 'acs'),
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

  /// Confirma o recebimento do alerta vermelho.
  ///
  /// Usa o caminho RPC em vez de publicar o ACK no broker: é tipado e o
  /// servidor já trata alerta inexistente devolvendo `acknowledged: false`, em
  /// vez de erro. O dispatcher do servidor assina o tópico de ACKs, então o
  /// efeito chega ao broker de qualquer forma.
  @override
  Future<AlertAckResult> acknowledge({required String alertId}) async {
    final token = await _requireToken();
    return _guard(
      () => _client.alerts.acknowledge(accessToken: token, alertId: alertId),
    );
  }

  /// Envia as visitas registradas offline.
  ///
  /// O lote inteiro roda em uma transação no servidor, e cada visita volta com
  /// o próprio `syncStatus`: o app casa pelo `localId`, nunca pela posição.
  @override
  Future<List<VisitSyncResult>> syncVisits(List<VisitSyncEntry> visits) async {
    final token = await _requireToken();
    return _guard(
      () => _client.visits.sync(accessToken: token, visits: visits),
    );
  }

  @override
  void close() => _client.close();

  /// Traduz as exceções tipadas do backend para [BackendFailure].
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on EndpointDisabledException {
      throw const BackendFailure(
        'O acesso de desenvolvimento está desativado neste servidor.',
        isRecoverable: false,
      );
    } on AlertPermissionException {
      // Acontece quando o alerta é de outra microárea. A territorialização é
      // invariante: o servidor recusa, e o app não deve tentar contornar.
      throw const BackendFailure(
        'Este alerta não pertence à sua microárea.',
        isRecoverable: false,
      );
    } on AlertValidationException catch (error) {
      throw BackendFailure(error.message, isRecoverable: false);
    } on AlertDispatchUnavailableException {
      throw const BackendFailure(
        'Registrado. A rede está instável e a confirmação será entregue assim '
        'que a conexão voltar.',
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
