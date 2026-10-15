import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/runtime/uncaught_error_policy.dart';

class MqttUnavailableException implements Exception {
  const MqttUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MqttAlertDispatcher implements AlertPublisher {
  MqttAlertDispatcher({
    required AppConfig config,
    Duration initialBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(seconds: 60),
    void Function(Object error)? onFatal,
    void Function(String line)? log,
    Duration publishAckTimeout = const Duration(seconds: 10),
    int keepAliveSeconds = 30,
    int pingResponseTimeoutSeconds = 10,
  })  : _config = config,
        _ackTimeout = publishAckTimeout,
        _keepAliveSecs = keepAliveSeconds,
        _pingTimeoutSecs = pingResponseTimeoutSeconds,
        _initialBackoff = initialBackoff,
        // Teto menor que o piso faria o backoff encolher a cada falha.
        _maxBackoff = maxBackoff < initialBackoff ? initialBackoff : maxBackoff,
        _backoff = initialBackoff,
        _onFatal = onFatal ?? _exitFatal,
        _log = log ?? _stderrLog;

  /// Destino padrão das linhas de log (`log` no construtor troca, nos testes).
  /// Toda linha leva só tipo e errno, nunca mensagem, pilha ou endereço.
  static void _stderrLog(String line) => stderr.writeln(line);

  /// EX_SOFTWARE: falha não prevista no cliente MQTT. O processo sai de forma
  /// controlada (o motivo já foi registrado só pelo tipo) e o orquestrador o
  /// reinicia, em vez de continuar com o dispatcher num estado desconhecido.
  static void _exitFatal(Object error) => exit(70);

  final AppConfig _config;
  final Duration _initialBackoff;
  final Duration _maxBackoff;
  final void Function(Object error) _onFatal;
  final void Function(String line) _log;

  /// Prazo para o PUBACK de uma publicação QoS 1 (H5, #56). Estourado, a
  /// publicação falha e a conexão do cliente é dada como perdida.
  final Duration _ackTimeout;

  /// PINGREQ a cada [_keepAliveSecs] (o `keepAlivePeriod` do cliente).
  final int _keepAliveSecs;

  /// `disconnectOnNoResponsePeriod` do cliente: sem PINGRESP neste prazo
  /// depois de um PINGREQ, a biblioteca derruba a conexão e chama
  /// `onDisconnected` (H5, #56). Ver [_connectOnce].
  final int _pingTimeoutSecs;

  /// Publicações à espera de PUBACK, por cliente e por id de mensagem. O id
  /// é do dispensador do cliente, por isso o mapa vive com ele.
  final _pendingAcks = Expando<Map<int, Completer<void>>>('PUBACKs pendentes');

  /// Zona protegida de cada cliente (ver [_zoneFor]).
  final _zones = Expando<Zone>('zona protegida do cliente MQTT');

  /// Gancho de teste chamado logo depois de um cliente novo assumir, antes de
  /// o anterior ser descartado: a janela em que uma queda já foi perdida.
  @visibleForTesting
  Future<void> Function()? afterClientSwapForTest;
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;
  Future<void> Function(AlertDeliveryAck ack)? _onAcknowledgement;
  Duration _backoff;
  bool _reconnecting = false;
  bool _closed = false;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  /// Cliente ativo, só para os testes de cliente obsoleto.
  @visibleForTesting
  MqttServerClient? get clientForTest => _client;

  /// Zona protegida (#56) de uma tentativa de conexão.
  ///
  /// O `Socket` do cliente MQTT nasce dentro de `client.connect(...)`, e um
  /// erro de E/S do socket (EPIPE/ECONNRESET) completa o `Socket.done` do sink
  /// de escrita, que nem o mqtt_client nem ninguém escuta. Esse erro é entregue
  /// à zona em que o socket foi criado; sem handler ali, ele sobe até a zona
  /// raiz e derruba o processo inteiro (provado na Tarefa 6b). Um `try/catch`
  /// em volta de `connect`/`publish` não o vê, por isso cada `connect` roda
  /// numa zona própria, e o handler sabe de QUAL cliente veio o erro: um erro
  /// tardio do socket de um cliente já substituído não derruba o atual.
  ///
  /// Deriva da zona raiz, não de `Zone.current`: o dispatcher é criado sob
  /// demanda e pode nascer dentro da zona de uma requisição do Serverpod, cujos
  /// valores não devem viver junto com a conexão MQTT do processo.
  Zone _zoneFor(MqttServerClient client) => _zones[client] ??= Zone.root.fork(
        specification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stack) =>
              _onAsyncError(error, stack, client),
        ),
      );

  Future<void> connect({
    Future<void> Function(AlertDeliveryAck ack)? onAcknowledgement,
  }) async {
    _onAcknowledgement = onAcknowledgement;
    try {
      await _connectOnce();
    } catch (error) {
      _log(
        'Falha ao conectar ao broker MQTT (${error.runtimeType}). '
        'Tentando novamente em segundo plano...',
      );
      unawaited(_reconnectWithBackoff());
    }
  }

  Future<void> _connectOnce() async {
    final broker = _parseBroker(_config.mqttBroker);
    final clientId = 'sinalacs-backend-${DateTime.now().microsecondsSinceEpoch}';
    late final MqttServerClient client;
    client = MqttServerClient.withPort(broker.host, clientId, broker.port)
      ..keepAlivePeriod = _keepAliveSecs
      // Partição sem FIN/RST (#56, cenário C): sem isto (padrão 0, desligado)
      // o cliente seguia `connected` enquanto a rede não voltasse, mesmo
      // com o broker já tendo expirado a sessão. A biblioteca manda PINGREQ a
      // cada `keepAlivePeriod` e, se o PINGRESP não chega neste prazo,
      // destrói o socket e chama `onDisconnected` (o timer nasce dentro de
      // `connect`, logo na zona protegida). Pior caso de detecção:
      // keepalive + este prazo (30 + 10 = 40 s), antes de o broker desistir
      // do cliente (1,5 x keepalive = 45 s).
      ..disconnectOnNoResponsePeriod = _pingTimeoutSecs
      ..secure = _config.mqttUseTls
      ..autoReconnect = false
      // O callback carrega o cliente que o registrou: um aviso tardio de um
      // cliente já substituído é ignorado em vez de derrubar o atual (H4).
      ..onDisconnected = (() => _handleDisconnected(client))
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .withWillQos(MqttQos.atLeastOnce);

    if (_config.mqttUseTls && _config.mqttCaCertificatePath != null) {
      final contexto = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(_config.mqttCaCertificatePath!);
      final cert = _config.mqttClientCertificatePath;
      final chave = _config.mqttClientKeyPath;
      if (cert != null && chave != null) {
        contexto
          ..useCertificateChain(cert)
          ..usePrivateKey(chave);
      }
      client.securityContext = contexto;
    }

    try {
      // O socket (e o timer do keepalive) nascem aqui: dentro da zona.
      await _runProtected(
        _zoneFor(client),
        () => client.connect(_config.mqttUsername, _config.mqttPassword),
      );
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw StateError('Não foi possível conectar ao broker MQTT.');
      }
      if (_closed) {
        throw StateError('Dispatcher MQTT encerrado durante a conexão.');
      }
      _zoneFor(client).run(() {
        client.subscribe('sinalacs/v1/alerts/+/acks', MqttQos.atLeastOnce);
        // PUBACK das publicações QoS 1: a biblioteca só emite em `published`
        // quando há ouvinte. O stream fecha quando o cliente desconecta; aí
        // as publicações em voo deste cliente falham (nunca ficam penduradas).
        client.published?.listen(
          (message) => _onPublishAck(client, message),
          onDone: () => _failPendingAcks(client),
          onError: (Object _) => _failPendingAcks(client),
        );
      });
    } catch (_) {
      _disconnectQuietly(client);
      rethrow;
    }

    // O cliente novo assume antes de o anterior ser descartado, sem `await`
    // entre a checagem de estado e a troca: assim um `onDisconnected` do novo
    // nunca cai numa janela em que ele ainda não é o `_client`. A subscription
    // e o cliente anteriores são descartados logo depois: sem isso, cada
    // reconexão deixava um listener vivo no cliente antigo, e uma tempestade
    // de reconexão disparava o callback de ACK em duplicata.
    final previousSubscription = _subscription;
    final previousClient = _client;
    _subscription = client.updates?.listen(_handleMessages);
    _client = client;
    _backoff = _initialBackoff;
    final gancho = afterClientSwapForTest;
    if (gancho != null) await gancho();
    await previousSubscription?.cancel();
    _disconnectQuietly(previousClient);
  }

  /// Roda [body] em [zone] (protegida) e devolve o resultado na zona do chamador.
  ///
  /// Um `Future` que falha dentro de uma zona com handler de erro não cruza
  /// para outra zona de erro: `await zone.run(...)` ficaria pendurado para
  /// sempre numa falha de `connect` (o erro iria só para o handler). O
  /// `Completer` criado aqui fora entrega valor e erro ao chamador.
  Future<T> _runProtected<T>(Zone zone, Future<T> Function() body) {
    final resultado = Completer<T>();
    zone.run(() {
      body().then(resultado.complete, onError: resultado.completeError);
    });
    return resultado.future;
  }

  Future<void> _handleMessages(
    List<MqttReceivedMessage<MqttMessage>> messages,
  ) async {
    final handler = _onAcknowledgement;
    if (handler == null) return;

    for (final message in messages) {
      final payload = message.payload as MqttPublishMessage;
      final body =
          MqttPublishPayload.bytesToStringAsString(payload.payload.message);
      final ack = _decodeAck(body);
      if (ack == null) continue;

      // O callback é assíncrono e antes era invocado sem await, então qualquer
      // falha ao registrar o ACK virava erro assíncrono não tratado. Um ACK
      // perdido em silêncio deixa um alerta vermelho eternamente pendente
      // (INV-03), por isso a falha é aguardada e registrada.
      try {
        await handler(ack);
      } catch (error) {
        // Só o id sintético e o TIPO do erro, nunca `$error`/`$stackTrace`
        // brutos: um aggregator de log arquiva o stderr sem tratamento, e a
        // exceção pode carregar atributos do alerta (VAZ-01).
        _log(
          'Falha ao processar ACK do alerta ${ack.alertId} '
          '(${error.runtimeType}).',
        );
      }
    }
  }

  Future<void> _teardownCurrentConnection() async {
    final previousSubscription = _subscription;
    final previousClient = _client;
    _subscription = null;
    _client = null;
    await previousSubscription?.cancel();
    _disconnectQuietly(previousClient);
  }

  void _disconnectQuietly(MqttServerClient? client) {
    if (client == null) return;
    _failPendingAcks(client);
    try {
      client.disconnect();
    } catch (error) {
      _log(
        'Falha ao encerrar cliente MQTT antigo (${error.runtimeType}).',
      );
    }
  }

  void _handleDisconnected(MqttServerClient origem) {
    if (_closed || !identical(origem, _client)) return;
    unawaited(_markConnectionLost(origem));
  }

  /// A conexão de [client] caiu: descarta-o (para `publish` lançar
  /// [MqttUnavailableException] mesmo que a biblioteca ainda o dê por
  /// conectado) e agenda a reconexão. Idempotente: a checagem de identidade e
  /// a troca de `_client` acontecem sem `await` entre elas, então o
  /// `onDisconnected` e o erro de E/S da mesma queda descartam o cliente uma
  /// vez só. Não volta cedo por `_reconnecting`: uma queda do cliente recém-
  /// conectado, ainda dentro do laço de reconexão, precisa zerar `_client`
  /// para o laço ver que a conexão já caiu e tentar de novo.
  Future<void> _markConnectionLost(MqttServerClient client) async {
    if (_closed || !identical(client, _client)) return;
    await _teardownCurrentConnection();
    if (!_reconnecting) unawaited(_reconnectWithBackoff());
  }

  bool _isTransient(Object e) => isTransientIoError(e);

  /// Handler da zona protegida. Registra só o tipo (e o errno de um
  /// `SocketException`), nunca a mensagem, a pilha ou o endereço (VAZ-01).
  void _onAsyncError(Object error, StackTrace stack, MqttServerClient client) {
    if (_closed) {
      // Encerrado: nada a reconectar e nenhum motivo para derrubar o processo
      // por um erro tardio de um socket que já foi descartado.
      _log(
        'Erro tardio no cliente MQTT encerrado '
        '(${error.runtimeType}${_errno(error)}); ignorado.',
      );
      return;
    }
    if (_isTransient(error)) {
      _log(
        'Erro de E/S no cliente MQTT (${error.runtimeType}${_errno(error)}); '
        'reconectando.',
      );
      // Só derruba a conexão se o erro veio do cliente atual (identidade
      // checada em _markConnectionLost).
      unawaited(_markConnectionLost(client));
      return;
    }
    _log('Erro fatal no cliente MQTT (${error.runtimeType}).');
    _onFatal(error);
  }

  static String _errno(Object e) {
    if (e is SocketException) {
      final code = e.osError?.errorCode;
      if (code != null) return ', errno=$code';
    }
    return '';
  }

  /// Entrega [error] à zona protegida como erro assíncrono não tratado. Prova
  /// a política do handler, não o comportamento de um socket real (esse é o
  /// teste de RST do broker falso e os cenários no Docker).
  ///
  /// [from] escolhe a zona de um cliente específico (padrão: o atual).
  @visibleForTesting
  Future<void> simulateAsyncErrorForTest(
    Object error, {
    MqttServerClient? from,
  }) async {
    final client = from ?? _client;
    if (client == null) throw StateError('sem cliente MQTT para simular erro');
    _zoneFor(client).run(() {
      Future<void>.error(error);
    });
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> _reconnectWithBackoff() async {
    if (_reconnecting || _closed) return;
    _reconnecting = true;
    try {
      while (!_closed) {
        await Future<void>.delayed(_backoff);
        if (_closed) break;
        try {
          await _connectOnce();
          // A conexão nova pode ter caído na própria troca de cliente
          // (_markConnectionLost zera `_client`); nesse caso, tenta de novo
          // em vez de sair do laço com um cliente morto.
          if (_client != null && isConnected) break;
          _log('Conexão MQTT caiu logo após reconectar; tentando de novo.');
        } catch (error) {
          _log(
            'Falha ao reconectar ao broker MQTT (${error.runtimeType}).',
          );
          _backoff = Duration(
            microseconds: min(
              _backoff.inMicroseconds * 2,
              _maxBackoff.inMicroseconds,
            ),
          );
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  /// Publica [alert] com QoS 1 e completa só quando o broker confirma com
  /// PUBACK (H5, #56): antes, `publish` devolvia assim que a mensagem ia para
  /// o buffer do socket e o outbox a dava por entregue mesmo com a conexão
  /// morta.
  ///
  /// Falha com [MqttUnavailableException] quando não há conexão, quando a
  /// conexão cai antes do PUBACK ou quando ele não chega em
  /// `publishAckTimeout`. No tempo limite a conexão é dada como perdida (a
  /// reconexão começa e as publicações seguintes falham na hora, sem esperar
  /// outro prazo inteiro). Entrega é pelo menos uma vez: uma mensagem que o
  /// broker recebeu sem o PUBACK chegar volta a ser publicada pelo outbox.
  @override
  Future<void> publish(AlertDelivery alert) async {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) {
      throw const MqttUnavailableException('O dispatcher MQTT não está conectado.');
    }

    final payload = MqttClientPayloadBuilder()..addString(alert.toJson());
    // O Completer nasce na zona do chamador: o erro precisa chegar a quem
    // aguarda, e um Future com erro não cruza para outra zona de erro.
    final confirmacao = Completer<void>();
    final pendentes = _pendingAcks[client] ??= <int, Completer<void>>{};
    // A escrita vai para o socket nascido na zona protegida. `publishMessage`
    // é síncrono até a escrita, e o PUBACK só é processado num turno
    // seguinte do event loop: registrar o id logo depois não perde a
    // confirmação.
    final messageId = _zoneFor(client).run(
      () => client.publishMessage(
        alert.topic,
        MqttQos.atLeastOnce,
        payload.payload!,
      ),
    );
    pendentes[messageId] = confirmacao;

    final prazo = Timer(_ackTimeout, () {
      if (!identical(pendentes[messageId], confirmacao)) return;
      pendentes.remove(messageId);
      _log(
        'PUBACK não recebido em ${_ackTimeout.inMilliseconds} ms; '
        'conexão MQTT dada como perdida.',
      );
      confirmacao.completeError(
        const MqttUnavailableException('O broker MQTT não confirmou a publicação no prazo.'),
      );
      unawaited(_markConnectionLost(client));
    });
    try {
      await confirmacao.future;
    } finally {
      prazo.cancel();
    }
  }

  void _onPublishAck(MqttServerClient client, MqttPublishMessage message) {
    final id = message.variableHeader?.messageIdentifier;
    if (id == null) return;
    final confirmacao = _pendingAcks[client]?.remove(id);
    if (confirmacao != null && !confirmacao.isCompleted) confirmacao.complete();
  }

  /// A conexão de [client] acabou: nenhuma publicação dele terá PUBACK. Falha
  /// todas, para o outbox registrar a falha e reentregar depois.
  void _failPendingAcks(MqttServerClient client) {
    final pendentes = _pendingAcks[client];
    if (pendentes == null || pendentes.isEmpty) return;
    final emVoo = List.of(pendentes.values);
    pendentes.clear();
    for (final confirmacao in emVoo) {
      if (!confirmacao.isCompleted) {
        confirmacao.completeError(
          const MqttUnavailableException('A conexão MQTT caiu antes da confirmação da publicação.'),
        );
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    await _teardownCurrentConnection();
  }

  AlertDeliveryAck? _decodeAck(String body) => AlertDeliveryAck.tryParse(body);

  ({String host, int port}) _parseBroker(String value) {
    final uri = Uri.parse(value.contains('://') ? value : 'mqtt://$value');
    return (host: uri.host, port: uri.hasPort ? uri.port : 1883);
  }
}
