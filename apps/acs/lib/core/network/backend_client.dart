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

  /// Autentica o ACS com matrícula e senha (RF07).
  ///
  /// A credencial fica **apenas em memória** — ver `_credentials` em
  /// [BackendClient] — para a reautenticação silenciosa que o app já fazia
  /// quando o token de 15 minutos expirava. Nada é gravado em disco.
  Future<AuthSession> login({required String matricula, required String senha});

  /// Login de DESENVOLVIMENTO, para `tool/` e `integration_test/` contra a
  /// stack local. Só funciona com `ENABLE_DEV_LOGIN=true`; **não** é o caminho
  /// do produto (RF07 é [login]).
  Future<AuthSession> developmentLogin({required String role});

  Future<AlertAckResult> acknowledge({required String alertId});

  Future<List<VisitSyncResult>> syncVisits(List<VisitSyncEntry> visits);

  /// Visitas da microárea alteradas desde `since` — reconciliação
  /// central→dispositivo (RF15, decisão §5).
  Future<List<VisitSyncEntry>> pullVisits({required DateTime since});

  /// Pacientes da microárea do ACS, para a visita de rotina.
  ///
  /// Existe porque o único produtor de alertas publica só `riskLevel: 'red'`
  /// (emergência, com SAMU): sem esta lista, a aba "Visita" não tinha de onde
  /// partir fora do caminho reativo.
  Future<List<MicroAreaPatient>> listPatients();

  void close();
}

/// Fachada do backend para o app do ACS.
class BackendClient implements AcsBackend {
  BackendClient({String? host})
      : _client = Client(host ?? BackendConfig.host)
          ..connectivityMonitor = null;

  final Client _client;

  AuthSession? _session;

  /// Credencial em memória, para reautenticar quando o token de 15 min expira.
  ///
  /// **Só em memória, nunca em disco.** É o que preserva o comportamento que o
  /// app já tinha (reauth silencioso, que antes chamava `developmentLogin`) sem
  /// persistir senha nenhuma. A correção durável é o refresh token rotativo que
  /// `spec/lgpd_design.md` LGPD-RT06 exige e que este plano deliberadamente não
  /// implementa — ver a lacuna registrada no plano.
  ({String matricula, String senha})? _credentials;

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
    if (!isAuthenticated) await renewSession();
    final current = _session;
    if (current == null) {
      throw const BackendFailure('Sessão não iniciada.', isRecoverable: false);
    }
    return current.accessToken;
  }

  /// Autentica contra `auth.loginInstitutional` (RF07).
  ///
  /// A recusa chega como `AuthenticationFailedException`, traduzida em
  /// [BackendFailure] não recuperável por [_guard].
  @override
  Future<AuthSession> login({
    required String matricula,
    required String senha,
  }) async {
    final result = await _guard(
      () => _client.auth.loginInstitutional(
        matricula: matricula,
        password: senha,
      ),
    );

    final session = AuthSession.tryParse(result.accessToken, result.tokenType);
    if (session == null) {
      throw const BackendFailure(
        'O servidor devolveu um token que o aplicativo não entendeu.',
        isRecoverable: false,
      );
    }

    _credentials = (matricula: matricula, senha: senha);
    _session = session;
    return session;
  }

  /// Reautentica usando a credencial em memória.
  ///
  /// Sem credencial guardada não há como renovar: quem chama recebe uma falha
  /// não recuperável e a tela precisa mandar a pessoa entrar de novo.
  Future<AuthSession> renewSession() async {
    final credentials = _credentials;
    if (credentials == null) {
      throw const BackendFailure(
        'Sua sessão expirou. Entre novamente.',
        isRecoverable: false,
      );
    }
    return login(
      matricula: credentials.matricula,
      senha: credentials.senha,
    );
  }

  /// Login de desenvolvimento, para `tool/` e `integration_test/`.
  ///
  /// É a versão antiga de [login], preservada porque as ferramentas rodam
  /// contra a stack local com `ENABLE_DEV_LOGIN=true` e não têm — nem devem ter
  /// — a senha institucional embutida. Não guarda `_credentials`: sem
  /// credencial não há renovação, e quem usar isto em produção recebe a falha
  /// não recuperável de [renewSession] quando o token expirar.
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
      // `visits.sync` reaproveita AlertPermissionException para token inválido
      // e para ACS sem microárea. Dizer "este alerta não pertence à sua
      // microárea" aqui manda o ACS procurar um problema que não existe.
      permissionMessage:
          'Sua sessão não autoriza sincronizar visitas. Entre novamente.',
    );
  }

  /// Reconciliação central→dispositivo: visitas da microárea alteradas desde
  /// `since` (RF15, decisão §5). Espelha [syncVisits] na tradução de falhas.
  @override
  Future<List<VisitSyncEntry>> pullVisits({required DateTime since}) async {
    final token = await _requireToken();
    return _guard(
      () => _client.visits.pull(accessToken: token, since: since),
    );
  }

  @override
  Future<List<MicroAreaPatient>> listPatients() async {
    final token = await _requireToken();
    return _guard(
      () => _client.patients.listMicroArea(accessToken: token),
    );
  }

  @override
  void close() => _client.close();

  /// Traduz as exceções tipadas do backend para [BackendFailure].
  ///
  /// [permissionMessage] troca o texto de `AlertPermissionException`, que
  /// significa coisas diferentes conforme o endpoint que a lançou.
  Future<T> _guard<T>(
    Future<T> Function() call, {
    String? permissionMessage,
  }) async {
    try {
      return await call();
    } on EndpointDisabledException {
      throw const BackendFailure(
        'O acesso de desenvolvimento está desativado neste servidor.',
        isRecoverable: false,
      );
    } on AuthenticationFailedException catch (error) {
      // A mensagem vem do servidor de propósito: é ela que diferencia "senha
      // inválida" de "acesso bloqueado por tentativas" — e é igual para
      // matrícula inexistente e senha errada, para não revelar quais
      // matrículas existem.
      throw BackendFailure(error.message, isRecoverable: false);
    } on AlertPermissionException {
      // Acontece quando o alerta é de outra microárea. A territorialização é
      // invariante: o servidor recusa, e o app não deve tentar contornar.
      throw BackendFailure(
        permissionMessage ?? 'Este alerta não pertence à sua microárea.',
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
