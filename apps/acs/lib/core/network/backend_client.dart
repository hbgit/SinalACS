import 'dart:io';

import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
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

/// O ACS tem MFA ativa e a senha conferiu: falta o código do autenticador.
class MfaCodeRequired extends BackendFailure {
  const MfaCodeRequired() : super('Informe o código do aplicativo autenticador.');
}

/// O servidor exige MFA e este ACS ainda não a ativou.
class MfaEnrollmentRequired extends BackendFailure {
  const MfaEnrollmentRequired() : super('Ative a verificação em duas etapas antes de entrar.', isRecoverable: false);
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

/// Contrato do backend visto pela UI do ACS.
///
/// A UI depende desta abstração, nunca do [Client] gerado — mesmo padrão que o
/// servidor usa entre `application/` e `infrastructure/`.
abstract class AcsBackend {
  AuthSession? get session;

  bool get isAuthenticated;

  /// Chamado quando a sessão venceu e **não** dá para renová-la sozinho (o
  /// refresh token foi recusado ou não existe mais). A UI leva a pessoa de
  /// volta ao login.
  void Function()? onSessionExpired;

  /// `true` se há um refresh token guardado no aparelho (a UI pode tentar
  /// [resumeSession] na partida).
  Future<bool> get hasStoredSession;

  /// Tenta abrir uma sessão com o refresh token guardado. `null` se não há
  /// token ou se ele foi recusado/não pôde ser usado agora. Não chama
  /// [onSessionExpired]: na partida a UI já é a tela de login.
  Future<AuthSession?> resumeSession();

  /// Encerra a sessão: revoga o refresh token no servidor (best-effort) e
  /// apaga o token local.
  Future<void> logout();

  /// Autentica o ACS com matrícula e senha (RF07).
  ///
  /// A senha **não** é retida: a renovação silenciosa usa o refresh token
  /// rotativo guardado no Keystore.
  ///
  /// [totpCode] é o código do autenticador (MFA); sem ele, um ACS com MFA ativa
  /// recebe [MfaCodeRequired].
  Future<AuthSession> login({required String matricula, required String senha, String? totpCode});

  /// Começa a ativação da verificação em duas etapas. Sem token: vale a
  /// matrícula e a senha.
  Future<TotpEnrollmentStart> beginTotpEnrollment({required String matricula, required String senha});

  /// Conclui a ativação com o primeiro código do autenticador.
  Future<void> confirmTotpEnrollment({required String matricula, required String senha, required String code});

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

  /// Contato da UBS do ACS (RF13): nome e telefone, que pode não estar cadastrado.
  Future<UbsContact> ubsContact();

  /// Convite de onboarding de um paciente da própria microárea (RF02). O
  /// token em claro volta só nesta resposta e vira o QR Code da tela
  /// "Convidar paciente" — nunca é gravado no aparelho.
  Future<EnrollmentTokenResult> generateInvite({required String patientId});

  /// Envia um aviso comunitário aos pacientes da microárea do ACS que aceitaram
  /// receber avisos (RF14). A microárea vem do token, nunca de parâmetro;
  /// [chronicOnly] restringe a quem tem condição crônica.
  Future<NoticeSendResult> sendNotice({
    required String title,
    required String message,
    required bool chronicOnly,
  });

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
class MisconfiguredBackend implements AcsBackend {
  const MisconfiguredBackend(this.failure);

  /// O motivo, como [requireSecureHost] o produziu.
  final BackendFailure failure;

  @override
  void Function()? get onSessionExpired => null;

  @override
  set onSessionExpired(void Function()? _) {}

  @override
  AuthSession? get session => null;

  @override
  bool get isAuthenticated => false;

  @override
  Future<bool> get hasStoredSession async => false;

  @override
  Future<AuthSession?> resumeSession() async => null;

  @override
  Future<void> logout() async {}

  /// Recusa uma chamada. `Never` avisa o analisador de que nada abaixo disto
  /// executa, então cada método abaixo é uma linha só.
  Never _recusar() => throw failure;

  @override
  Future<AuthSession> login({required String matricula, required String senha, String? totpCode}) async =>
      _recusar();

  @override
  Future<TotpEnrollmentStart> beginTotpEnrollment({required String matricula, required String senha}) async =>
      _recusar();

  @override
  Future<void> confirmTotpEnrollment({required String matricula, required String senha, required String code}) async =>
      _recusar();

  @override
  Future<AuthSession> developmentLogin({required String role}) async => _recusar();

  @override
  Future<AlertAckResult> acknowledge({required String alertId}) async => _recusar();

  @override
  Future<List<VisitSyncResult>> syncVisits(List<VisitSyncEntry> visits) async => _recusar();

  @override
  Future<List<VisitSyncEntry>> pullVisits({required DateTime since}) async => _recusar();

  @override
  Future<List<MicroAreaPatient>> listPatients() async => _recusar();

  @override
  Future<UbsContact> ubsContact() async => _recusar();

  @override
  Future<EnrollmentTokenResult> generateInvite({required String patientId}) async => _recusar();

  @override
  Future<NoticeSendResult> sendNotice({
    required String title,
    required String message,
    required bool chronicOnly,
  }) async =>
      _recusar();

  /// Fechar **não** é uma chamada ao backend: não há o que fechar, e um `close`
  /// que lançasse derrubaria o `finally` de quem só queria encerrar.
  @override
  void close() {}
}

/// Fachada do backend para o app do ACS.
class BackendClient implements AcsBackend {
  /// [trustedCaBytes] é a CA de desenvolvimento do RPC (RNF04). `null` faz o
  /// cliente usar o armazenamento de confiança do sistema — que **não** conhece
  /// a CA local, e por isso a conexão falha de forma explícita em vez de ser
  /// aceita às cegas. Nunca instale um `badCertificateCallback` que aceite tudo:
  /// este app já faz verificação de hostname no MQTT e ceder aqui anularia
  /// RNF04 no ponto onde ele mais importa.
  BackendClient({
    String? host,
    List<int>? trustedCaBytes,
    SessionTokenStore? tokenStore,
    DeviceIdStore? deviceIds,
  })  : _tokenStore = tokenStore ?? SecureStorageSessionTokenStore(),
        _deviceIds = deviceIds ?? SecureStorageDeviceIdStore(),
        _client = Client(
          // Só o host que veio do `--dart-define` (o default de compilação) é
          // validado. Um host **explícito** passa como veio: é o caminho dos
          // testes herméticos, que apontam para servidores fake em
          // `http://127.0.0.1:<porta efêmera>/` — validá-lo quebraria testes
          // que precisam ficar verdes.
          resolveHost(host),
          // `SecurityContext()` já vem com `withTrustedRoots: false`, isto é,
          // **só** a CA passada abaixo é aceita — nenhuma autoridade pública.
          // Mesma técnica (e mesma escolha) do `mqtt_secure_client.dart` deste
          // mesmo app, que faz isso com a CA do broker.
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

  final SessionTokenStore _tokenStore;
  final DeviceIdStore _deviceIds;

  @override
  AuthSession? get session => _session;

  @override
  void Function()? onSessionExpired;

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
    String? totpCode,
  }) async {
    final deviceId = await _storage(_deviceIds.readOrCreate);
    final result = await _guard(
      () => _client.auth.loginInstitutional(
        matricula: matricula,
        password: senha,
        totpCode: totpCode,
        // O servidor só emite refresh token a quem informa o aparelho.
        deviceId: deviceId,
      ),
    );

    final session = AuthSession.tryParse(result.accessToken, result.tokenType);
    if (session == null) {
      throw const BackendFailure(
        'O servidor devolveu um token que o aplicativo não entendeu.',
        isRecoverable: false,
      );
    }

    // Grava o refresh token ANTES de expor a sessão. Sem token na resposta,
    // não deixa um token velho de outra conta para trás.
    final refreshToken = result.refreshToken;
    try {
      if (refreshToken == null || refreshToken.isEmpty) {
        await _tokenStore.clear();
      } else {
        await _tokenStore.write(refreshToken);
      }
    } catch (_) {
      throw _storeLost;
    }
    _session = session;
    return session;
  }

  /// Ativação da MFA: sem `_requireToken()` (ainda não há token) e sem reter a
  /// senha.
  @override
  Future<TotpEnrollmentStart> beginTotpEnrollment({
    required String matricula,
    required String senha,
  }) =>
      _guard(() => _client.auth.beginTotpEnrollment(matricula: matricula, password: senha));

  @override
  Future<void> confirmTotpEnrollment({
    required String matricula,
    required String senha,
    required String code,
  }) =>
      _guard(() => _client.auth.confirmTotpEnrollment(matricula: matricula, password: senha, code: code));

  Future<AuthSession>? _renewal;

  /// Renova o JWT com o refresh token guardado. **Single-flight**: chamadas
  /// simultâneas compartilham UMA renovação (o token rotativo só vale uma vez).
  Future<AuthSession> renewSession({bool notify = true}) =>
      _renewal ??= _doRenew(notify: notify).whenComplete(() => _renewal = null);

  Future<AuthSession> _doRenew({required bool notify}) async {
    final token = await _storage(_tokenStore.read);
    if (token == null) {
      _expire(notify);
      throw const BackendFailure('Sua sessão expirou. Entre novamente.', isRecoverable: false);
    }
    // Fora do `_guard`: falha do armazenamento não é "sem conexão".
    final deviceId = await _storage(_deviceIds.readOrCreate);
    // `null` = o servidor recusou o refresh token. Tratado aqui, antes de o
    // `_guard` transformar a exceção em "sem conexão".
    final result = await _guard(() async {
      try {
        return await _client.auth.refreshSession(refreshToken: token, deviceId: deviceId);
      } on SessionExpiredException {
        return null;
      }
    });
    // Falha de rede/timeout já saiu pelo `_guard` como recuperável, sem apagar
    // o token: a repetição cai na tolerância de 30 s do servidor.
    if (result == null) {
      try {
        await _tokenStore.clear();
      } catch (_) {
        // Best-effort: a sessão acabou de qualquer jeito.
      }
      _expire(notify);
      throw const BackendFailure(
        'Sua sessão expirou. Entre novamente com o código do autenticador.',
        isRecoverable: false,
      );
    }
    final next = result.refreshToken;
    final hasNext = next != null && next.isNotEmpty;
    // Grava o filho ANTES de qualquer outra coisa: o servidor já rotacionou, e
    // perder o filho é perder o turno — mesmo se o JWT não puder ser lido.
    if (hasNext) {
      try {
        await _tokenStore.write(next);
      } catch (_) {
        // O token novo se perdeu e o antigo já foi gasto: sessão acabou.
        try {
          await _tokenStore.clear();
        } catch (_) {}
        _expire(notify);
        throw _storeLost;
      }
    }
    final session = AuthSession.tryParse(result.accessToken, result.tokenType);
    if (session == null || !hasNext) {
      throw const BackendFailure(
        'O servidor devolveu um token que o aplicativo não entendeu.',
        isRecoverable: false,
      );
    }
    return _session = session;
  }

  static const _storeLost = BackendFailure(
    'Não foi possível guardar a sessão neste aparelho. Entre novamente.',
    isRecoverable: false,
  );

  /// Executa uma operação do armazenamento seguro; qualquer exceção vira
  /// [BackendFailure] (nunca uma `PlatformException` crua na UI).
  Future<T> _storage<T>(Future<T> Function() op) async {
    try {
      return await op();
    } catch (_) {
      throw const BackendFailure(
        'Não foi possível acessar o armazenamento seguro deste aparelho.',
        isRecoverable: false,
      );
    }
  }

  void _expire(bool notify) {
    _session = null;
    if (notify) onSessionExpired?.call();
  }

  @override
  Future<bool> get hasStoredSession async {
    try {
      return await _tokenStore.read() != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AuthSession?> resumeSession() async {
    try {
      if (await _tokenStore.read() == null) return null;
      return await renewSession(notify: false);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> logout() async {
    // Uma renovação em voo, ao terminar, regravaria o token e ressuscitaria a
    // sessão: espera-a acabar (ignorando o resultado) e só então encerra.
    final pending = _renewal;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    String? token;
    try {
      token = await _tokenStore.read();
    } catch (_) {}
    if (token != null) {
      try {
        await _client.auth.logout(refreshToken: token);
      } catch (_) {
        // Best-effort: o aparelho pode estar sem rede. O token local sai de
        // qualquer jeito.
      }
    }
    _session = null;
    await _storage(_tokenStore.clear);
  }

  /// Login de desenvolvimento, para `tool/` e `integration_test/`.
  ///
  /// É a versão antiga de [login], preservada porque as ferramentas rodam
  /// contra a stack local com `ENABLE_DEV_LOGIN=true` e não têm — nem devem ter
  /// — a senha institucional embutida. Não grava refresh token: sem
  /// ele não há renovação, e quem usar isto em produção recebe a falha
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
  Future<UbsContact> ubsContact() async {
    final token = await _requireToken();
    return _guard(() => _client.ubs.myContact(accessToken: token));
  }

  @override
  Future<EnrollmentTokenResult> generateInvite({required String patientId}) async {
    final token = await _requireToken();
    return _guard(
      () => _client.onboarding.generateEnrollmentToken(
        accessToken: token,
        patientId: patientId,
      ),
      // O servidor recusa com `AlertPermissionException` quando o paciente
      // não é da microárea do ACS (INV-01) — "este alerta" não faria sentido.
      permissionMessage: 'Este paciente não pertence à sua microárea.',
    );
  }

  @override
  Future<NoticeSendResult> sendNotice({
    required String title,
    required String message,
    required bool chronicOnly,
  }) async {
    final token = await _requireToken();
    return _guard(
      () => _client.notices.sendSegmented(
        accessToken: token,
        title: title,
        message: message,
        audience: chronicOnly ? 'chronic' : 'everyone',
      ),
      permissionMessage: 'Somente o ACS pode enviar avisos à comunidade.',
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
    } on MfaRequiredException {
      throw const MfaCodeRequired();
    } on MfaEnrollmentRequiredException {
      throw const MfaEnrollmentRequired();
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
    } on DataRightsException catch (error) {
      // Recusa de negócio com texto pronto (aviso vazio ou longo demais).
      throw BackendFailure(error.message, isRecoverable: false);
    } on NoticeDeliveryException catch (error) {
      // O relé de push está fora do ar: tentar de novo faz sentido.
      throw BackendFailure(error.message);
    } on AlertDispatchUnavailableException {
      throw const BackendFailure(
        'Registrado. A rede está instável e a confirmação será entregue assim '
        'que a conexão voltar.',
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
