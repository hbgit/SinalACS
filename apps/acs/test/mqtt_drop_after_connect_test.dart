import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';

/// Queda do broker DEPOIS da primeira conexão (#80, achado da revisão final).
///
/// Com `autoReconnect` ligado, o `mqtt_client` 10.5.1 não chama
/// `onDisconnected` nessa queda: dispara o laço de reconexão e chama só
/// `onAutoReconnect`. Sem tratar esse callback, `onConnectionChanged(false)`
/// nunca chegava ao painel, que seguia "em linha" e nunca armava a reserva por
/// HTTP. Broker falso em TCP real (sem TLS), para usar o cliente de verdade.
void main() {
  test('o broker derruba o socket depois do CONNACK: onConnectionChanged(false) chega', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final conexoes = <Socket>[];
    server.listen((socket) {
      conexoes.add(socket);
      socket.listen((bytes) {
        // CONNECT (0x10) → CONNACK aceito; SUBSCRIBE (0x82) → SUBACK QoS 1.
        if (bytes.isNotEmpty && bytes.first == 0x10) {
          socket.add([0x20, 0x02, 0x00, 0x00]);
        } else if (bytes.isNotEmpty && bytes.first == 0x82 && bytes.length >= 4) {
          socket.add([0x90, 0x03, bytes[2], bytes[3], 0x01]);
        }
      }, onError: (_) {});
    });

    final client = MqttSecureClient(
      config: SecureMqttConfig(
        brokerHost: '127.0.0.1',
        port: server.port,
        clientId: 'acs-queda-teste',
        topic: 'sinalacs/v1/microareas/area-teste/alerts',
        useTls: false,
      ),
    );
    addTearDown(client.disconnect);

    final estados = <bool>[];
    final caiu = Completer<void>();
    await client.connect(
      onAlert: (_) {},
      onConnectionChanged: (conectado) {
        estados.add(conectado);
        if (!conectado && !caiu.isCompleted) caiu.complete();
      },
    );
    expect(client.isConnected, isTrue);

    // O broker cai: fecha a conexão aceita e para de aceitar novas.
    await server.close();
    for (final s in conexoes) {
      s.destroy();
    }

    await caiu.future.timeout(const Duration(seconds: 5), onTimeout: () {
      fail('a queda depois de conectar nunca virou onConnectionChanged(false): $estados');
    });
    expect(estados.last, isFalse);
  });
}
