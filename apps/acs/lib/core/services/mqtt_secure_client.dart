import 'dart:convert';
import 'dart:io';

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

/// Tópico onde o ACS confirma o recebimento de um alerta.
String ackTopicFor(String alertId) => 'sinalacs/v1/alerts/$alertId/acks';

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
    required this.triggeredAt,
  });

  final String alertId;
  final String patientId;
  final String microAreaId;
  final String riskLevel;
  final String locationHash;
  final DateTime triggeredAt;

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
        triggeredAt: DateTime.parse(triggeredAtRaw),
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
      'triggered_at': timestamp,
      'timestamp': timestamp,
      // Namespace do backend (AlertDelivery.topicPrefix) e da ACL do broker.
      // Era '/alerts/$microAreaId', que não existe em nenhum dos dois.
      'mqtt_topic': alertTopicFor(microAreaId),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static String _defaultLocationHash(double latitude, double longitude) {
    final normalized = '${latitude.toStringAsFixed(6)}:${longitude.toStringAsFixed(6)}';
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

class MqttSecureClient {
  MqttSecureClient({required this.config});

  final SecureMqttConfig config;
  MqttServerClient? _client;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({
    required void Function(ReceivedMqttAlert alert) onAlert,
    void Function(bool connected)? onConnectionChanged,
  }) async {
    if (config.useWebSocket) {
      throw UnsupportedError('O transporte WebSocket será configurado pelo gateway de produção.');
    }

    final client = MqttServerClient.withPort(config.brokerHost, config.clientId, config.port)
      ..keepAlivePeriod = 30
      ..secure = config.useTls
      // Um ACS em campo perde rede o tempo todo; sem reconexão automática a
      // fila de alertas simplesmente para de chegar, em silêncio.
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..onDisconnected = (() => onConnectionChanged?.call(false))
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
      client.securityContext = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(caCertificate);
    }

    // O cliente é assumido ANTES de conectar. Com `autoReconnect`, uma falha de
    // conexão (certificado errado, credencial recusada) deixa o cliente
    // tentando de novo indefinidamente; se a referência só fosse guardada
    // depois do sucesso, esse cliente ficaria órfão, reconectando para sempre e
    // fora do alcance de [disconnect].
    _client = client;

    try {
      await client.connect(config.username, config.password);
    } catch (_) {
      disconnect();
      rethrow;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      disconnect();
      throw StateError('Não foi possível conectar ao broker MQTT.');
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
