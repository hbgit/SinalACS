import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Prefixo dos tópicos de alerta, espelhando `AlertDelivery.topicPrefix` no
/// servidor e a ACL do broker (infra/docker/mosquitto/aclfile).
///
/// Os três lugares precisam concordar: o servidor publica aqui, o broker só
/// autoriza aqui, e o app só recebe o que assinar aqui.
const String alertTopicPrefix = 'sinalacs/v1/microareas';

/// Tópico onde os alertas de uma microárea são publicados.
String alertTopicFor(String microAreaId) =>
    '$alertTopicPrefix/$microAreaId/alerts';

/// Client id MQTT do aparelho (#94): estável por ACS **e** por instalação.
///
/// Tem de ser a MESMA string de `deviceMqttClientId` no servidor
/// (`backend/sinalacs_server/lib/src/application/devices/device_certificate_service.dart`,
/// usada por `MqttSessionKicker.clientIdFor` em
/// `backend/sinalacs_server/lib/src/infrastructure/mqtt/mqtt_session_kicker.dart`):
/// é por ela que o servidor derruba a sessão do aparelho cujo certificado
/// revogou. O app não importa o servidor; `test/alert_feed_enrollment_test.dart`
/// fixa a igualdade com a constante copiada.
String deviceClientId({required String acsId, required String deviceId}) => 'sinalacs-acs-$acsId-$deviceId';

/// Tópico onde o ACS confirma o recebimento de um alerta.
String ackTopicFor(String alertId) => 'sinalacs/v1/alerts/$alertId/acks';

/// O broker respondeu, e recusou.
///
/// Distinguir isso de "não deu para chegar ao broker" é o que separa uma senha
/// errada de uma central fora do ar — que antes chegavam à tela como a mesma
/// frase.
class MqttConnectionRefused implements Exception {
  const MqttConnectionRefused(this.message, {this.transient = false});

  /// Já em português e pronta para a tela. **Nunca** contém credencial.
  final String message;

  /// Se vale a pena tentar de novo sem intervenção humana.
  ///
  /// Ver [mqttRefusalIsTransient] para o critério.
  final bool transient;

  @override
  String toString() => message;
}

/// Traduz o código de recusa do CONNACK.
///
/// O `mqtt_client` grava o motivo em `connectionStatus.returnCode` antes de
/// derrubar a conexão; o código antigo lançava um `StateError` genérico e
/// jogava fora a única informação que separava os casos. Devolve `null` quando
/// não houve recusa — aí a falha foi de transporte, não de autorização.
///
/// Nunca cita usuário nem senha: a mensagem vai para a tela do ACS.
String? mqttRefusalReason(MqttConnectReturnCode? code) => switch (code) {
      MqttConnectReturnCode.badUsernameOrPassword ||
      MqttConnectReturnCode.notAuthorized =>
        'A central recusou as credenciais deste aplicativo.',
      MqttConnectReturnCode.identifierRejected =>
        'A central recusou o identificador deste aplicativo.',
      MqttConnectReturnCode.brokerUnavailable =>
        'A central de alertas está indisponível.',
      MqttConnectReturnCode.unacceptedProtocolVersion =>
        'A central não aceita a versão de protocolo deste aplicativo.',
      _ => null,
    };

/// Se vale tentar de novo depois de uma recusa.
///
/// Só `brokerUnavailable`: a central pode estar reiniciando ou sobrecarregada.
/// Credencial e identificador recusados não mudam sozinhos — insistir neles
/// só gastaria bateria sem chance de sucesso.
bool mqttRefusalIsTransient(MqttConnectReturnCode? code) =>
    code == MqttConnectReturnCode.brokerUnavailable;

/// Contexto TLS do cliente MQTT: confia **só** na CA do projeto e, se houver
/// certificado de cliente, o apresenta (mTLS). Hostname segue verificado.
SecurityContext buildMqttSecurityContext(SecureMqttConfig config) {
  final contexto = SecurityContext(withTrustedRoots: false);
  final ca = config.caCertificate;
  if (ca != null) {
    contexto.setTrustedCertificatesBytes(ca);
  }
  final cert = config.clientCertificate;
  final chave = config.clientPrivateKey;
  if (cert != null && chave != null) {
    contexto
      ..useCertificateChainBytes(cert)
      ..usePrivateKeyBytes(chave);
  }
  return contexto;
}

class SecureMqttConfig {
  const SecureMqttConfig({
    required this.brokerHost,
    required this.port,
    required this.clientId,
    required this.topic,
    this.useTls = true,
    this.useWebSocket = false,
    this.username,
    this.password,
    this.caCertificate,
    this.clientCertificate,
    this.clientPrivateKey,
  });

  final String brokerHost;
  final int port;
  final String clientId;
  final String topic;
  final bool useTls;

  /// O broker publica **apenas** a porta 8883 (TCP/TLS): não há listener
  /// WebSocket. O default era `true`, o que fazia [MqttSecureClient.connect]
  /// lançar `UnsupportedError` na configuração padrão — ou seja, o cliente se
  /// autodesabilitava e nunca chegou a ser usado.
  final bool useWebSocket;

  final String? username;
  final String? password;

  /// Certificado da CA que assina o broker, em bytes (PEM).
  ///
  /// São bytes e não caminho de arquivo porque no Android a CA vem de um asset
  /// dentro do APK, onde não existe caminho no sistema de arquivos.
  final List<int>? caCertificate;

  /// Certificado e chave privada de CLIENTE (PEM) para o mTLS do broker. Só
  /// valem juntos; sem os dois, o cliente não apresenta certificado.
  final Uint8List? clientCertificate;
  final Uint8List? clientPrivateKey;

  String get connectionUri {
    if (useWebSocket) {
      final scheme = useTls ? 'wss' : 'ws';
      return '$scheme://$brokerHost:$port';
    }

    final scheme = useTls ? 'ssl' : 'tcp';
    return '$scheme://$brokerHost:$port';
  }
}

class ReceivedMqttAlert {
  const ReceivedMqttAlert({
    required this.alertId,
    required this.patientId,
    required this.microAreaId,
    required this.riskLevel,
    required this.locationHash,
    this.locationCell,
    required this.triggeredAt,
    this.escalated = false,
  });

  final String alertId;
  final String patientId;
  final String microAreaId;
  final String riskLevel;
  final String locationHash;

  /// Célula de baixa resolução (`"latCell:lngCell"`) calculada no dispositivo
  /// do paciente — `null` quando o GPS do paciente não estava disponível.
  /// O ACS só desenha um círculo de incerteza quando isto existe; nunca
  /// fabrica posição a partir de [locationHash].
  final String? locationCell;
  final DateTime triggeredAt;

  /// Reforço da coordenação (#44): o backend republica o MESMO alerta com
  /// `"escalated": true`. Opcional; só `true` literal conta — ausente, `false`
  /// ou de outro tipo é `false`. Não carrega identidade de quem escalonou.
  final bool escalated;

  static ReceivedMqttAlert? tryParse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['version'] != 1) return null;

      final triggeredAtRaw = json['triggered_at'] as String? ?? json['timestamp'] as String?;
      if (triggeredAtRaw == null) return null;

      return ReceivedMqttAlert(
        alertId: json['alert_id'] as String,
        patientId: json['patient_id'] as String,
        microAreaId: json['micro_area_id'] as String,
        riskLevel: json['risk_level'] as String,
        locationHash: (json['location_hash'] as String?) ?? (json['location_hash'] ?? 'unknown') as String,
        locationCell: json['location_cell'] as String?,
        triggeredAt: DateTime.parse(triggeredAtRaw),
        escalated: json['escalated'] == true,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class MqttSecureAlertPayload {
  MqttSecureAlertPayload({
    required this.alertId,
    required this.patientId,
    required this.riskLevel,
    required this.latitude,
    required this.longitude,
    required this.microAreaId,
    String? locationHash,
    this.locationCell,
    String? timestampOverride,
  })  : locationHash = locationHash ?? _defaultLocationHash(latitude, longitude),
        timestamp = timestampOverride ?? DateTime.now().toUtc().toIso8601String();

  final String alertId;
  final String patientId;
  final String riskLevel;
  final double latitude;
  final double longitude;
  final String microAreaId;
  final String locationHash;

  /// Só preenchido quando o teste passa um valor explícito — nada aqui
  /// fabrica uma célula a partir de latitude/longitude, esse cálculo é do
  /// dispositivo do paciente (`apps/patient/lib/core/privacy/location_cell.dart`).
  final String? locationCell;
  final String timestamp;

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'alert_id': alertId,
      'patient_id': patientId,
      'risk_level': riskLevel,
      'latitude': latitude,
      'longitude': longitude,
      'micro_area_id': microAreaId,
      'location_hash': locationHash,
      if (locationCell != null) 'location_cell': locationCell,
      'triggered_at': timestamp,
      'timestamp': timestamp,
      // Namespace do backend (AlertDelivery.topicPrefix) e da ACL do broker.
      // Era '/alerts/$microAreaId', que não existe em nenhum dos dois.
      'mqtt_topic': alertTopicFor(microAreaId),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static String _defaultLocationHash(double latitude, double longitude) {
    final normalized = '${latitude.toStringAsFixed(3)}:${longitude.toStringAsFixed(3)}';
    final bytes = utf8.encode(normalized);
    final digest = sha256.convert(bytes).toString();
    return digest.substring(0, 12);
  }
}

class MqttSecureAcknowledgementPayload {
  const MqttSecureAcknowledgementPayload({
    required this.alertId,
    required this.acsId,
    required this.microAreaId,
    required this.acknowledgedAt,
  });

  final String alertId;
  final String acsId;
  final String microAreaId;
  final DateTime acknowledgedAt;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'alert_id': alertId,
        'acs_id': acsId,
        'micro_area_id': microAreaId,
        'acknowledged_at': acknowledgedAt.toUtc().toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Por que o cliente desistiu da conexão sozinho, sem que ninguém pedisse.
enum MqttDropReason {
  /// O broker recusou o handshake TLS (#94): certificado do aparelho revogado
  /// ou não mais aceito. Insistir com o mesmo certificado não adianta; quem
  /// decide é o feed (descarta, consulta o wipe e reemite).
  tlsRefused,

  /// Outro erro assíncrono do `mqtt_client` fora de qualquer `await` nosso
  /// (reconexão automática). Vira queda em vez de erro não tratado.
  connectionError,
}

/// O broker recusou o handshake TLS já na PRIMEIRA conexão (#94).
class MqttTlsRefused implements Exception {
  const MqttTlsRefused(this.cause);

  /// Só para log; nunca chega à tela.
  final Object cause;

  @override
  String toString() => 'A central recusou a conexão segura deste aparelho.';
}

/// Classifica um erro que o `mqtt_client` deixou escapar.
///
/// `TlsException` (inclui `HandshakeException`) e `SocketException` contam
/// como recusa: é o que o broker produz ao recusar o certificado — o alerta TLS
/// (`SSLV3_ALERT_CERTIFICATE_REVOKED`, no e2e) ou o socket que ele fecha no
/// meio da escrita (`Broken pipe`, no broker falso de
/// `test/mqtt_tls_refused_test.dart`). Uma queda comum de rede não chega aqui:
/// a falha de abrir o socket o `mqtt_client` já trata, e a reconexão que dá
/// certo não deixa erro escapar (medido no mesmo teste).
MqttDropReason mqttDropReasonFor(Object error) =>
    error is TlsException || error is SocketException ? MqttDropReason.tlsRefused : MqttDropReason.connectionError;

class MqttSecureClient {
  MqttSecureClient({required this.config});

  final SecureMqttConfig config;
  MqttServerClient? _client;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  /// [onDrop]: o cliente desistiu sozinho (ver [MqttDropReason]); já está
  /// desconectado, sem `autoReconnect`, e [onConnectionChanged] recebeu
  /// `false`. Chamado no máximo uma vez por [connect].
  ///
  /// Recusa TLS durante a primeira conexão lança [MqttTlsRefused].
  Future<void> connect({
    required void Function(ReceivedMqttAlert alert) onAlert,
    void Function(bool connected)? onConnectionChanged,
    void Function(MqttDropReason reason)? onDrop,
  }) {
    if (config.useWebSocket) {
      throw UnsupportedError('O transporte WebSocket será configurado pelo gateway de produção.');
    }

    // O `mqtt_client` 10.5.1 deixa erros escaparem da própria cadeia de
    // futures: o `done` do `SecureSocket` que ele abre (ninguém o escuta) e o
    // laço `autoReconnect` (um `void async` disparado pelo barramento de
    // eventos). Na recusa TLS da reconexão, a `TlsException` saía como erro
    // não tratado (e2e da #94). Tudo o que o cliente agenda nasce nesta zona,
    // e o que escapa vira queda, nunca erro solto.
    // Os callbacks de quem chamou rodam na zona DELE: um erro no `onAlert`
    // segue o caminho de sempre e não derruba a conexão como se fosse do broker.
    final caller = Zone.current;
    final alertInCaller = caller.bindUnaryCallbackGuarded(onAlert);
    final changedInCaller =
        onConnectionChanged == null ? null : caller.bindUnaryCallbackGuarded(onConnectionChanged);
    final dropInCaller = onDrop == null ? null : caller.bindUnaryCallbackGuarded(onDrop);

    var connecting = true;
    var dropped = false;
    Object? refusedWhileConnecting;
    final result = Completer<void>();
    MqttServerClient? owned;

    void onZoneError(Object error, StackTrace stack) {
      final client = owned;
      // Desligado por quem chamou (ou já caído): o resto da reconexão que o
      // mqtt_client ainda desenrola não interessa a ninguém.
      if (dropped || client == null || !identical(_client, client)) return;
      final reason = mqttDropReasonFor(error);
      if (connecting) {
        if (reason == MqttDropReason.tlsRefused) refusedWhileConnecting ??= error;
        return;
      }
      dropped = true;
      disconnect();
      changedInCaller?.call(false);
      dropInCaller?.call(reason);
    }

    runZonedGuarded(() {
      _connect(
        onAlert: alertInCaller,
        onConnectionChanged: changedInCaller,
        onClient: (client) => owned = client,
      ).then((_) {
        connecting = false;
        result.complete();
      }, onError: (Object error, StackTrace stack) {
        connecting = false;
        final refused = refusedWhileConnecting;
        if (refused != null && error is! MqttConnectionRefused) {
          result.completeError(MqttTlsRefused(refused), stack);
        } else {
          result.completeError(error, stack);
        }
      });
    }, onZoneError);
    return result.future;
  }

  Future<void> _connect({
    required void Function(ReceivedMqttAlert alert) onAlert,
    required void Function(bool connected)? onConnectionChanged,
    required void Function(MqttServerClient client) onClient,
  }) async {
    final client = MqttServerClient.withPort(config.brokerHost, config.clientId, config.port)
      ..keepAlivePeriod = 30
      ..secure = config.useTls
      // Um ACS em campo perde rede o tempo todo; sem reconexão automática a
      // fila de alertas simplesmente para de chegar, em silêncio.
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..onDisconnected = (() => onConnectionChanged?.call(false))
      // Com `autoReconnect`, a queda DEPOIS da primeira conexão não chama
      // `onDisconnected` (o mqtt_client 10.5.1 entra direto no laço de
      // reconexão e só chama `onAutoReconnect`). Sem isto o painel seguia
      // "em linha" e nunca ligava a reserva por HTTP dos alertas (#80).
      ..onAutoReconnect = (() => onConnectionChanged?.call(false))
      // Conexão meio aberta (comum em 3G): sem resposta ao PINGREQ por este
      // tempo, o cliente a dá por caída. O padrão 0 nunca desconecta.
      ..disconnectOnNoResponsePeriod = 10
      ..onAutoReconnected = (() => onConnectionChanged?.call(true))
      ..onConnected = (() => onConnectionChanged?.call(true))
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(config.clientId)
          // NÃO chamar startClean(): sessão persistente é o default
          // (cleanStart = false). Com QoS 1, o broker guarda os alertas
          // publicados enquanto este ACS estava offline e os entrega na
          // reconexão — é o que impede um alerta vermelho de sumir porque o
          // aparelho estava sem sinal. Depende de o clientId ser ESTÁVEL entre
          // execuções; um id aleatório cria sessão nova a cada conexão e
          // descarta o que estava pendente.
          .withWillQos(MqttQos.atLeastOnce);
    final caCertificate = config.caCertificate;
    if (config.useTls && caCertificate != null) {
      // `withTrustedRoots: false` é deliberado: só a CA do broker é aceita,
      // nenhuma autoridade pública. A verificação de hostname continua ligada —
      // é o que o certificado com subjectAltName (infra/docker/mosquitto/init.sh)
      // passou a satisfazer. Não desligue com `onBadCertificate`: seria abrir o
      // caminho de spoofing do tópico de alertas.
      client.securityContext = buildMqttSecurityContext(config);
    }

    // O cliente é assumido ANTES de conectar. Com `autoReconnect`, uma falha de
    // conexão (certificado errado, credencial recusada) deixa o cliente
    // tentando de novo indefinidamente; se a referência só fosse guardada
    // depois do sucesso, esse cliente ficaria órfão, reconectando para sempre e
    // fora do alcance de [disconnect].
    _client = client;
    onClient(client);

    try {
      await client.connect(config.username, config.password);
    } catch (error) {
      // Lidos ANTES do disconnect, que zera o connectionStatus.
      final returnCode = client.connectionStatus?.returnCode;
      final refusal = mqttRefusalReason(returnCode);
      disconnect();
      if (refusal != null) {
        throw MqttConnectionRefused(refusal, transient: mqttRefusalIsTransient(returnCode));
      }
      rethrow;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final returnCode = client.connectionStatus?.returnCode;
      final refusal = mqttRefusalReason(returnCode);
      disconnect();
      throw MqttConnectionRefused(
        refusal ?? 'Não foi possível conectar ao broker MQTT.',
        transient: mqttRefusalIsTransient(returnCode),
      );
    }

    client.subscribe(config.topic, MqttQos.atLeastOnce);
    client.updates?.listen((messages) {
      for (final message in messages) {
        final publish = message.payload as MqttPublishMessage;
        final body = MqttPublishPayload.bytesToStringAsString(publish.payload.message);
        final alert = ReceivedMqttAlert.tryParse(body);
        if (alert != null && alert.microAreaId == _microAreaFromTopic(config.topic)) {
          onAlert(alert);
        }
      }
    });
    _client = client;
  }

  void disconnect() {
    final client = _client;
    _client = null;
    if (client == null) return;
    // Desligar a reconexão automática vem PRIMEIRO: sem isso, o disconnect
    // dispara o evento de reconexão e o cliente volta a tentar sozinho — quem
    // pediu para parar não conseguiria parar.
    client.autoReconnect = false;
    client.disconnect();
  }

  String _microAreaFromTopic(String topic) {
    final segments = topic.split('/').where((segment) => segment.isNotEmpty).toList();
    if (segments.length >= 2 && segments.contains('microareas')) {
      final index = segments.indexOf('microareas');
      if (index + 1 < segments.length) return segments[index + 1];
    }
    if (segments.length >= 2 && segments.contains('alerts')) {
      final index = segments.indexOf('alerts');
      if (index + 1 < segments.length) return segments[index + 1];
    }
    return segments.isEmpty ? '' : segments.last;
  }

  MqttSecureAlertPayload buildAlertPayload({
    required String patientId,
    required String riskLevel,
    required double latitude,
    required double longitude,
    required String microAreaId,
  }) {
    return MqttSecureAlertPayload(
      alertId: 'alert-${DateTime.now().microsecondsSinceEpoch}',
      patientId: patientId,
      riskLevel: riskLevel,
      latitude: latitude,
      longitude: longitude,
      microAreaId: microAreaId,
    );
  }
}
