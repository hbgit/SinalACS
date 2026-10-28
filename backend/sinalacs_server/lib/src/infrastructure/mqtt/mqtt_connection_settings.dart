import 'dart:io';

import 'package:sinalacs_server/src/config/app_config.dart';

/// Host e porta de `MQTT_BROKER` (`host:porta` ou URI; porta padrão 1883).
({String host, int port}) parseMqttBroker(String value) {
  final uri = Uri.parse(value.contains('://') ? value : 'mqtt://$value');
  return (host: uri.host, port: uri.hasPort ? uri.port : 1883);
}

/// O contexto TLS das conexões MQTT do backend: confia só na CA de
/// `MQTT_CA_CERT_PATH` e apresenta o certificado de cliente quando
/// configurado. Compartilhado pelo despachante de alertas e pela derrubada de
/// sessão (#94), que precisam ser o MESMO cliente aos olhos do broker. `null`
/// sem TLS ou sem CA (aí vale o padrão da biblioteca).
SecurityContext? mqttSecurityContext(AppConfig config) {
  final ca = config.mqttCaCertificatePath;
  if (!config.mqttUseTls || ca == null) return null;
  final contexto = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificates(ca);
  final cert = config.mqttClientCertificatePath;
  final chave = config.mqttClientKeyPath;
  if (cert != null && chave != null) {
    contexto
      ..useCertificateChain(cert)
      ..usePrivateKey(chave);
  }
  return contexto;
}
