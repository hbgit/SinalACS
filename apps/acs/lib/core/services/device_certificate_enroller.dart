import 'dart:async';
import 'dart:developer' as developer;

import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/device_certificate_store.dart';
import 'package:sinalacs_acs/core/services/device_csr.dart';

// Dart puro, sem `package:flutter`: este arquivo fica na árvore de
// `backend_client.dart`, que `tool/live_check.dart` compila na VM. A guarda é
// `test/session_store_wiring_test.dart`.

/// Não há certificado utilizável e o servidor não pôde emitir outro agora
/// (sem rede, ou o servidor pediu para tentar mais tarde). [expired]: havia
/// um, da mesma microárea, e venceu.
class DeviceCertificateUnavailable implements Exception {
  const DeviceCertificateUnavailable({required this.expired, this.retryLater});

  final bool expired;

  /// O motivo dado pelo servidor quando ele respondeu "tente mais tarde"
  /// ([DeviceCertificateRetryLater]: limite de emissões, sessão a renovar);
  /// `null` quando a falha foi de rede.
  final String? retryLater;

  @override
  String toString() {
    final motivo = retryLater;
    if (motivo != null) return 'O servidor pediu para tentar mais tarde: $motivo';
    return expired
        ? 'O certificado deste aparelho venceu e não pôde ser renovado sem rede.'
        : 'Este aparelho ainda não tem certificado e não pôde pedir um sem rede.';
  }
}

/// Garante o certificado de cliente MQTT deste aparelho (#94).
///
/// Regras de [ensure]:
///   * guardado, da mesma microárea e longe de vencer (mais que [renewWithin])
///     → devolve sem rede;
///   * perto de vencer → reemite (par novo, CSR, `issueDeviceCertificate`),
///     grava e devolve; se a renovação falhar por QUALQUER motivo (rede,
///     limite de emissões, recusa), devolve o guardado, que ainda vale — uma
///     falha de renovação não pode derrubar a conexão de um certificado bom
///     (#94, I1);
///   * vencido, ausente ou de outra microárea → reemite; sem rede, ou com o
///     servidor pedindo para tentar mais tarde, lança
///     [DeviceCertificateUnavailable];
///   * [DeviceWipeRequiredFailure] sobe sempre, e as recusas do servidor sobem
///     como vieram quando não há guardado válido, sem gravar nada;
///   * a folha emitida que o Keystore não conseguiu gravar é devolvida assim
///     mesmo e fica só na RAM desta instância até a próxima gravação boa ou o
///     [discard] (#94, T5): reemitir a cada reconexão queimaria o limite de
///     emissões por hora.
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

  /// Folhas emitidas que o Keystore não gravou (T5), por `acsId|deviceId`.
  final Map<String, StoredDeviceCertificate> _unsaved = <String, StoredDeviceCertificate>{};

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

  /// O broker recusou o certificado deste aparelho no handshake TLS (#94):
  /// apaga o guardado para que o próximo [ensure] reemita. Se há emissão em
  /// voo para o aparelho, espera-a terminar (com sucesso ou não) antes de
  /// apagar, para que a gravação dela não sobreviva ao descarte.
  ///
  /// Apaga a folha de TODOS os ACS deste aparelho (`store.delete` é por
  /// aparelho): a de outro ACS é só reemitida no login dele, e a recusa quase
  /// sempre é do aparelho (revogação, limpeza remota). [acsId] identifica o
  /// pedido para quem lê o chamador.
  Future<void> discard({required String acsId, required String deviceId}) async {
    final pending = _inFlight[deviceId];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // O erro da emissão é de quem a pediu; aqui só importa que terminou.
      }
    }
    // Antes do Keystore: se o `delete` falhar, a folha recusada também não
    // volta pela RAM.
    _unsaved.removeWhere((_, c) => c.deviceId == deviceId);
    await _store.delete(deviceId: deviceId);
  }

  Future<StoredDeviceCertificate> _ensure({
    required String acsId,
    required String deviceId,
    required String microAreaId,
  }) async {
    final stored = _maisNovo(
      await _store.read(acsId: acsId, deviceId: deviceId),
      _unsaved['$acsId|$deviceId'],
    );
    final sameArea = stored != null && stored.microAreaId == microAreaId;
    final Duration? remaining =
        sameArea ? stored.notAfter.difference(_now().toUtc().add(stored.serverOffset)) : null;

    if (remaining != null && remaining > renewWithin) return stored!;

    try {
      return await _issue(acsId: acsId, deviceId: deviceId, microAreaId: microAreaId);
    } on DeviceWipeRequiredFailure {
      rethrow;
    } on BackendFailure catch (failure) {
      // I1: o guardado ainda vale → serve, qualquer que tenha sido a falha.
      if (remaining != null && remaining > Duration.zero) return stored!;
      if (!failure.isRecoverable) rethrow;
      throw DeviceCertificateUnavailable(
        expired: remaining != null,
        retryLater: failure is DeviceCertificateRetryLater ? failure.message : null,
      );
    }
  }

  static StoredDeviceCertificate? _maisNovo(StoredDeviceCertificate? a, StoredDeviceCertificate? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.notAfter.isAfter(a.notAfter) ? b : a;
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
    final chave = '$acsId|$deviceId';
    try {
      await _store.write(cert);
      _unsaved.remove(chave);
    } catch (error, stackTrace) {
      // T5: a folha já foi emitida (e conta no limite por hora do servidor).
      // Descartá-la por falha do Keystore obrigaria a reemitir a cada
      // reconexão; fica na RAM para esta sessão do app.
      developer.log(
        'Keystore não gravou o certificado do aparelho; mantido só na memória',
        name: 'sinalacs.acs.device_certificate',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      _unsaved[chave] = cert;
    }
    return cert;
  }
}
