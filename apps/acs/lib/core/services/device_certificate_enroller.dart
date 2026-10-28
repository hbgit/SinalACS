import 'dart:async';

import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/device_certificate_store.dart';
import 'package:sinalacs_acs/core/services/device_csr.dart';

// Dart puro, sem `package:flutter`: este arquivo fica na árvore de
// `backend_client.dart`, que `tool/live_check.dart` compila na VM. A guarda é
// `test/session_store_wiring_test.dart`.

/// Não há certificado utilizável e o servidor não pôde emitir outro agora
/// (sem rede). [expired]: havia um, da mesma microárea, e venceu.
class DeviceCertificateUnavailable implements Exception {
  const DeviceCertificateUnavailable({required this.expired});

  final bool expired;

  @override
  String toString() => expired
      ? 'O certificado deste aparelho venceu e não pôde ser renovado sem rede.'
      : 'Este aparelho ainda não tem certificado e não pôde pedir um sem rede.';
}

/// Garante o certificado de cliente MQTT deste aparelho (#94).
///
/// Regras de [ensure]:
///   * guardado, da mesma microárea e longe de vencer (mais que [renewWithin])
///     → devolve sem rede;
///   * perto de vencer → reemite (par novo, CSR, `issueDeviceCertificate`),
///     grava e devolve; sem rede ([BackendFailure.isRecoverable]) devolve o
///     guardado, que ainda vale;
///   * vencido, ausente ou de outra microárea → reemite; sem rede lança
///     [DeviceCertificateUnavailable];
///   * [DeviceWipeRequiredFailure] e recusas do servidor sobem como vieram,
///     sem gravar nada.
///
/// A validade é medida na hora do SERVIDOR: relógio local mais o desvio
/// (`serverNow − now()`) gravado na última emissão. Single-flight por
/// `deviceId`: chamadas simultâneas compartilham uma emissão.
class DeviceCertificateEnroller {
  DeviceCertificateEnroller({
    required DeviceCertificateStore store,
    required AcsBackend backend,
    DateTime Function() now = DateTime.now,
    this.renewWithin = const Duration(days: 10),
  })  : _store = store,
        _backend = backend,
        _now = now;

  final DeviceCertificateStore _store;
  final AcsBackend _backend;
  final DateTime Function() _now;
  final Duration renewWithin;

  final Map<String, Future<StoredDeviceCertificate>> _inFlight = <String, Future<StoredDeviceCertificate>>{};

  Future<StoredDeviceCertificate> ensure({
    required String acsId,
    required String deviceId,
    required String microAreaId,
  }) {
    final pending = _inFlight[deviceId];
    if (pending != null) return pending;
    final run = _ensure(acsId: acsId, deviceId: deviceId, microAreaId: microAreaId);
    _inFlight[deviceId] = run;
    // Limpa ao terminar, com sucesso ou não: a próxima chamada tenta de novo.
    return run.whenComplete(() {
      if (identical(_inFlight[deviceId], run)) _inFlight.remove(deviceId);
    });
  }

  Future<StoredDeviceCertificate> _ensure({
    required String acsId,
    required String deviceId,
    required String microAreaId,
  }) async {
    final stored = await _store.read(acsId: acsId, deviceId: deviceId);
    final sameArea = stored != null && stored.microAreaId == microAreaId;
    final Duration? remaining =
        sameArea ? stored.notAfter.difference(_now().toUtc().add(stored.serverOffset)) : null;

    if (remaining != null && remaining > renewWithin) return stored!;

    try {
      return await _issue(acsId: acsId, deviceId: deviceId, microAreaId: microAreaId);
    } on DeviceWipeRequiredFailure {
      rethrow;
    } on BackendFailure catch (failure) {
      if (!failure.isRecoverable) rethrow;
      if (remaining != null && remaining > Duration.zero) return stored!;
      throw DeviceCertificateUnavailable(expired: remaining != null);
    }
  }

  Future<StoredDeviceCertificate> _issue({
    required String acsId,
    required String deviceId,
    required String microAreaId,
  }) async {
    final keyPair = generateDeviceKeyPair();
    final csr = buildDeviceCsrPem(keyPair: keyPair, microAreaId: microAreaId);
    final issued = await _backend.issueDeviceCertificate(csr);
    final cert = StoredDeviceCertificate(
      acsId: acsId,
      deviceId: deviceId,
      microAreaId: microAreaId,
      serial: issued.serial,
      certificatePem: issued.certificatePem,
      privateKeyPem: keyPair.privateKeyPem,
      notAfter: issued.notAfter.toUtc(),
      serverOffset: issued.serverNow.toUtc().difference(_now().toUtc()),
    );
    await _store.write(cert);
    return cert;
  }
}
