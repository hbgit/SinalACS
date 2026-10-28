import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/devices/device_certificate_service.dart';

/// Espera o sidecar do broker (`infra/docker/mosquitto/crl_reload.sh`)
/// confirmar a recarga da CRL dos aparelhos (#94, Task 7a).
///
/// Depois de validar a `crl.pem` e mandar o SIGHUP ao Mosquitto, o sidecar
/// grava, por temporário + `mv`, `crl.loaded` no mesmo diretório com o sha256
/// (hex) dos bytes da `crl.pem` que sinalizou. Este observador relê o marcador
/// a cada [interval] até [timeout].
///
/// Também vale um marcador igual ao sha256 da `crl.pem` ATUAL quando ela já
/// não é a nossa: outra revogação a regravou depois (o sidecar, que relê a
/// cada 2 s, pode só ter visto a mais nova), e a mais nova foi lida do banco
/// depois do nosso commit, então também traz a nossa serial.
///
/// As leituras são síncronas de propósito: o arquivo tem 65 bytes, e assim a
/// espera roda inteira sob relógio falso nos testes.
class CrlReloadWatcher implements CrlReloadAwait {
  CrlReloadWatcher({
    required String crlPath,
    this.timeout = const Duration(seconds: 15),
    this.interval = const Duration(milliseconds: 250),
  }) : _crl = File(crlPath),
       _marcador = File('${File(crlPath).parent.path}/crl.loaded');

  final File _crl;
  final File _marcador;

  @override
  final Duration timeout;
  final Duration interval;

  @override
  Future<bool> loaded(String sha256Hex) async {
    for (var t = Duration.zero; ; t += interval) {
      if (_bate(sha256Hex)) return true;
      if (t >= timeout) return false;
      await Future<void>.delayed(interval);
    }
  }

  bool _bate(String esperado) {
    final marcado = _ler(() => _marcador.readAsStringSync().trim());
    if (marcado == null || marcado.isEmpty) return false;
    if (marcado == esperado) return true;
    final atual = _ler(() => sha256.convert(_crl.readAsBytesSync()).toString());
    return atual != null && atual != esperado && marcado == atual;
  }

  static String? _ler(String Function() ler) {
    try {
      return ler();
    } on FileSystemException {
      return null;
    }
  }
}
