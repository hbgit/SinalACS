import 'dart:convert';

// Sem `package:flutter` aqui, de propósito: o `DeviceCertificateEnroller`
// importa este arquivo e fica na árvore de `backend_client.dart`, que
// `tool/live_check.dart` compila na VM do Dart. A loja sobre o Keystore mora
// em `secure_device_certificate_store.dart`, montada só pelo `main.dart`.

/// Certificado de cliente MQTT deste aparelho (#94), com a chave privada que
/// o acompanha e a microárea do CN.
///
/// **Nunca registre [privateKeyPem] em log**, nem em mensagem de erro.
class StoredDeviceCertificate {
  const StoredDeviceCertificate({
    required this.acsId,
    required this.deviceId,
    required this.microAreaId,
    required this.serial,
    required this.certificatePem,
    required this.privateKeyPem,
    required this.notAfter,
    this.serverOffset = Duration.zero,
  });

  final String acsId;
  final String deviceId;

  /// O CN da folha: a microárea da sessão que a pediu.
  final String microAreaId;
  final String serial;
  final String certificatePem;
  final String privateKeyPem;
  final DateTime notAfter;

  /// `serverNow − relógio local` no momento da emissão. A validade é medida
  /// na hora do servidor (relógio local + este desvio), não só na do
  /// aparelho, que o ACS pode ter adiantado ou atrasado.
  final Duration serverOffset;

  Map<String, Object?> toJson() => {
        'acsId': acsId,
        'deviceId': deviceId,
        'microAreaId': microAreaId,
        'serial': serial,
        'certificatePem': certificatePem,
        'privateKeyPem': privateKeyPem,
        'notAfter': notAfter.toUtc().toIso8601String(),
        'serverOffsetMs': serverOffset.inMilliseconds,
      };

  /// `null` para qualquer valor que não seja um registro completo: uma loja
  /// corrompida vale como ausente (o aparelho pede outro certificado).
  static StoredDeviceCertificate? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return StoredDeviceCertificate(
        acsId: json['acsId'] as String,
        deviceId: json['deviceId'] as String,
        microAreaId: json['microAreaId'] as String,
        serial: json['serial'] as String,
        certificatePem: json['certificatePem'] as String,
        privateKeyPem: json['privateKeyPem'] as String,
        notAfter: DateTime.parse(json['notAfter'] as String).toUtc(),
        serverOffset: Duration(milliseconds: (json['serverOffsetMs'] as int?) ?? 0),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

/// Custódia do certificado MQTT do aparelho, um por `acsId|deviceId`.
abstract interface class DeviceCertificateStore {
  Future<StoredDeviceCertificate?> read({required String acsId, required String deviceId});

  Future<void> write(StoredDeviceCertificate c);

  /// Apaga os certificados de TODOS os ACS deste aparelho (limpeza remota,
  /// #81: o id da instalação vai embora e a folha emitida para ele também).
  Future<void> delete({required String deviceId});
}

/// Duplo de teste e loja padrão sem Keystore: só em memória.
class InMemoryDeviceCertificateStore implements DeviceCertificateStore {
  final Map<String, StoredDeviceCertificate> _data = <String, StoredDeviceCertificate>{};

  /// Quantas gravações aconteceram (o teste prova "não gravou nada").
  int writeCount = 0;

  @override
  Future<StoredDeviceCertificate?> read({required String acsId, required String deviceId}) async =>
      _data['$acsId|$deviceId'];

  @override
  Future<void> write(StoredDeviceCertificate c) async {
    writeCount++;
    _data['${c.acsId}|${c.deviceId}'] = c;
  }

  @override
  Future<void> delete({required String deviceId}) async =>
      _data.removeWhere((_, c) => c.deviceId == deviceId);
}
