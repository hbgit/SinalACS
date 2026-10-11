import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';

void main() {
  test('deve montar payload de alerta com metadados críticos do paciente', () {
    final payload = MqttSecureAlertPayload(
      alertId: 'alert-123',
      patientId: 'patient-42',
      riskLevel: 'VERMELHO',
      latitude: -23.5505,
      longitude: -46.6333,
      microAreaId: 'microarea-01',
    );

    final json = payload.toJson();

    expect(json['alert_id'], 'alert-123');
    expect(json['patient_id'], 'patient-42');
    expect(json['risk_level'], 'VERMELHO');
    expect(json['micro_area_id'], 'microarea-01');
    // Precisa ser o MESMO namespace de AlertDelivery.topicPrefix no servidor e
    // da ACL do broker. Este teste antes afirmava '/alerts/microarea-01', um
    // namespace que não existe em nenhum dos dois lados.
    expect(json['mqtt_topic'], 'sinalacs/v1/microareas/microarea-01/alerts');
  });

  test('deve montar os tópicos no namespace acordado com o backend', () {
    expect(
      alertTopicFor('00000000-0000-4000-8000-000000000003'),
      'sinalacs/v1/microareas/00000000-0000-4000-8000-000000000003/alerts',
    );
    expect(ackTopicFor('alert-123'), 'sinalacs/v1/alerts/alert-123/acks');
  });

  test('deve usar TCP/TLS por padrão, que é o único listener do broker', () {
    const config = SecureMqttConfig(
      brokerHost: 'broker.sinalacs.local',
      port: 8883,
      clientId: 'acs-client-01',
      topic: 'sinalacs/v1/microareas/microarea-01/alerts',
    );

    expect(config.useTls, isTrue);
    // O default era WebSocket, o que fazia connect() lançar UnsupportedError na
    // configuração padrão — o cliente se autodesabilitava.
    expect(config.useWebSocket, isFalse);
    expect(config.connectionUri, 'ssl://broker.sinalacs.local:8883');
  });

  test('deve montar URI WebSocket quando explicitamente pedido', () {
    const config = SecureMqttConfig(
      brokerHost: 'broker.sinalacs.local',
      port: 8883,
      clientId: 'acs-client-01',
      topic: 'sinalacs/v1/microareas/microarea-01/alerts',
      useWebSocket: true,
    );

    expect(config.connectionUri, contains('wss://'));
  });

  test('deve montar payload de confirmação do ACS para o alerta vermelho', () {
    final ack = MqttSecureAcknowledgementPayload(
      alertId: 'alert-123',
      acsId: 'acs-456',
      microAreaId: 'area-12',
      acknowledgedAt: DateTime.utc(2026, 9, 1, 12, 1),
    );

    final json = ack.toJson();
    expect(json['version'], 1);
    expect(json['alert_id'], 'alert-123');
    expect(json['acs_id'], 'acs-456');
    expect(json['micro_area_id'], 'area-12');
    expect(json['acknowledged_at'], '2026-09-01T12:01:00.000Z');
  });

  test('decodifica somente o envelope MQTT versionado', () {
    final alert = ReceivedMqttAlert.tryParse('''
      {"version":1,"alert_id":"alert-123","patient_id":"patient-42","micro_area_id":"area-12","risk_level":"red","location_hash":"6gyf4bf","triggered_at":"2026-09-01T12:00:00.000Z"}
    ''');

    expect(alert?.alertId, 'alert-123');
    expect(alert?.microAreaId, 'area-12');
    // Sem `location_cell` no envelope (GPS indisponível no paciente): o campo
    // fica `null`, não um valor fabricado.
    expect(alert?.locationCell, isNull);
    expect(ReceivedMqttAlert.tryParse('{"version":2}'), isNull);
  });

  test('decodifica location_cell quando o envelope traz a célula do paciente', () {
    final alert = ReceivedMqttAlert.tryParse('''
      {"version":1,"alert_id":"alert-123","patient_id":"patient-42","micro_area_id":"area-12","risk_level":"red","location_hash":"6gyf4bf","location_cell":"-1580:-4783","triggered_at":"2026-09-01T12:00:00.000Z"}
    ''');

    expect(alert?.locationCell, '-1580:-4783');
  });

  test('payload de alerta só inclui location_cell quando o teste fornece um', () {
    final semCelula = MqttSecureAlertPayload(
      alertId: 'alert-123',
      patientId: 'patient-42',
      riskLevel: 'vermelho',
      latitude: -23.5505,
      longitude: -46.6333,
      microAreaId: 'microarea-01',
    );
    expect(semCelula.toJson().containsKey('location_cell'), isFalse);

    final comCelula = MqttSecureAlertPayload(
      alertId: 'alert-124',
      patientId: 'patient-42',
      riskLevel: 'vermelho',
      latitude: -23.5505,
      longitude: -46.6333,
      microAreaId: 'microarea-01',
      locationCell: '-1580:-4783',
    );
    expect(comCelula.toJson()['location_cell'], '-1580:-4783');
  });

  group('recusa do broker', () {
    test('traduz cada código de CONNACK sem citar credencial', () {
      expect(
        mqttRefusalReason(MqttConnectReturnCode.badUsernameOrPassword),
        'A central recusou as credenciais deste aplicativo.',
      );
      expect(
        mqttRefusalReason(MqttConnectReturnCode.notAuthorized),
        'A central recusou as credenciais deste aplicativo.',
      );
      expect(
        mqttRefusalReason(MqttConnectReturnCode.identifierRejected),
        'A central recusou o identificador deste aplicativo.',
      );
      expect(
        mqttRefusalReason(MqttConnectReturnCode.brokerUnavailable),
        'A central de alertas está indisponível.',
      );
    });

    test('devolve null quando não houve recusa', () {
      // Aí a falha foi de transporte, não de autorização — e a mensagem da tela
      // precisa ser outra: "sem conexão" em vez de "credenciais recusadas".
      expect(mqttRefusalReason(null), isNull);
      expect(mqttRefusalReason(MqttConnectReturnCode.connectionAccepted), isNull);
    });

    test('só brokerUnavailable vale retentar sozinho', () {
      // Credencial e identificador recusados não mudam sozinhos — insistir
      // neles só gastaria bateria sem chance de sucesso. É justamente o erro
      // que mais tentaria induzir a retentar, por isso o teste explícito.
      expect(mqttRefusalIsTransient(MqttConnectReturnCode.brokerUnavailable), isTrue);
      expect(mqttRefusalIsTransient(MqttConnectReturnCode.badUsernameOrPassword), isFalse);
      expect(mqttRefusalIsTransient(MqttConnectReturnCode.notAuthorized), isFalse);
      expect(mqttRefusalIsTransient(MqttConnectReturnCode.identifierRejected), isFalse);
      expect(mqttRefusalIsTransient(MqttConnectReturnCode.unacceptedProtocolVersion), isFalse);
      expect(mqttRefusalIsTransient(null), isFalse);
    });
  });

  group('mTLS: certificado de cliente', () {
    test('a config guarda certificado e chave de cliente quando informados', () {
      final cert = Uint8List.fromList([1, 2, 3]);
      final chave = Uint8List.fromList([4, 5, 6]);
      final config = SecureMqttConfig(
        brokerHost: 'localhost',
        port: 8883,
        clientId: 'x',
        topic: 't',
        clientCertificate: cert,
        clientPrivateKey: chave,
      );
      expect(config.clientCertificate, cert);
      expect(config.clientPrivateKey, chave);
    });

    test('sem certificado de cliente os dois campos ficam nulos', () {
      const config = SecureMqttConfig(
        brokerHost: 'localhost',
        port: 8883,
        clientId: 'x',
        topic: 't',
      );
      expect(config.clientCertificate, isNull);
      expect(config.clientPrivateKey, isNull);
    });

    final temOpenssl = () {
      try {
        return Process.runSync('openssl', ['version']).exitCode == 0;
      } on ProcessException {
        return false;
      }
    }();

    test('buildMqttSecurityContext monta com um par PEM válido', () {
      final dir = Directory.systemTemp.createTempSync('mqtt_ctx_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final r = Process.runSync('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
        '-subj', '/CN=teste', '-keyout', '${dir.path}/k.pem',
        '-out', '${dir.path}/c.pem',
      ]);
      expect(r.exitCode, 0);
      final cert = File('${dir.path}/c.pem').readAsBytesSync();
      final chave = File('${dir.path}/k.pem').readAsBytesSync();
      final config = SecureMqttConfig(
        brokerHost: 'localhost',
        port: 8883,
        clientId: 'x',
        topic: 't',
        caCertificate: cert,
        clientCertificate: cert,
        clientPrivateKey: chave,
      );
      expect(() => buildMqttSecurityContext(config), returnsNormally);
    }, skip: temOpenssl ? false : 'openssl ausente');

    test('buildMqttSecurityContext recusa bytes que não são PEM', () {
      final lixo = Uint8List.fromList(List.filled(32, 7));
      final config = SecureMqttConfig(
        brokerHost: 'localhost',
        port: 8883,
        clientId: 'x',
        topic: 't',
        caCertificate: lixo,
        clientCertificate: lixo,
        clientPrivateKey: lixo,
      );
      expect(() => buildMqttSecurityContext(config), throwsA(isA<TlsException>()));
    });
  });
}
