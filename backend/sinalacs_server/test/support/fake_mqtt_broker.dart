import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Broker MQTT 3.1.1 mínimo sobre TCP real, só para testar o dispatcher.
///
/// Cobre CONNECT, SUBSCRIBE, PINGREQ e PUBLISH QoS 1 (com PUBACK). Qualquer outro pacote
/// é ignorado, não rejeitado.
class FakeMqttBroker {
  FakeMqttBroker._(this._server);

  final ServerSocket _server;
  final _clients = <Socket>[];
  final _buffers = <Socket, BytesBuilder>{};

  int connectCount = 0;
  int publishCount = 0;
  bool ignorePings = false;

  /// H5 (#56): conta o PUBLISH, mas não responde PUBACK e derruba a conexão
  /// logo em seguida, como um broker que cai com a mensagem em voo.
  bool dropOnPublish = false;

  /// H5 (#56): conta o PUBLISH e mantém a conexão aberta, mas nunca responde
  /// PUBACK, como um par que some sem FIN/RST (partição de rede).
  bool withholdPuback = false;

  /// Número de PUBACKs enviados.
  int pubackCount = 0;

  /// Client id de cada conexão aberta. Um CONNECT com um id já em uso derruba
  /// a conexão anterior (takeover do MQTT 3.1.1, §3.1.4-2), como o Mosquitto:
  /// é o que a derrubada de sessão da #94 usa.
  final _clientIds = <Socket, String>{};

  /// Client ids cujas conexões foram derrubadas por takeover.
  final takenOver = <String>[];

  int get port => _server.port;

  static Future<FakeMqttBroker> start({int port = 0}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    final broker = FakeMqttBroker._(server);
    server.listen(broker._accept);
    return broker;
  }

  void _accept(Socket socket) {
    _clients.add(socket);
    // O lado do broker também escreve (CONNACK, PINGRESP...) num socket que o
    // cliente pode ter fechado: o EPIPE completaria o `done` do sink sem
    // ouvinte e cairia na zona do teste, mascarando o que se quer medir.
    socket.done.then<void>((_) {}, onError: (Object _) {});
    socket.listen(
      (data) => _onData(socket, data),
      onError: (_) {},
      onDone: () {
        _clients.remove(socket);
        _buffers.remove(socket);
        _clientIds.remove(socket);
      },
      cancelOnError: true,
    );
  }

  void _onData(Socket socket, List<int> data) {
    final builder = _buffers.putIfAbsent(socket, BytesBuilder.new)..add(data);
    final bytes = builder.takeBytes();
    var offset = 0;
    while (offset + 2 <= bytes.length) {
      var length = 0;
      var multiplier = 1;
      var i = offset + 1;
      int digit;
      var incompleto = false;
      do {
        if (i >= bytes.length) {
          incompleto = true;
          break;
        }
        digit = bytes[i++];
        length += (digit & 127) * multiplier;
        multiplier *= 128;
      } while (digit & 128 != 0);
      if (incompleto || i + length > bytes.length) break;
      final end = i + length;
      _handle(socket, bytes[offset], Uint8List.sublistView(bytes, i, end));
      offset = end;
    }
    // O que sobrou (pacote parcial) volta ao buffer do socket.
    if (offset < bytes.length) {
      _buffers[socket]!.add(Uint8List.sublistView(bytes, offset));
    }
  }

  void _handle(Socket socket, int header, Uint8List body) {
    switch (header >> 4) {
      case 1: // CONNECT
        connectCount++;
        final id = _clientIdOf(body);
        if (id != null && id.isNotEmpty) {
          for (final e in _clientIds.entries.toList()) {
            if (e.value == id && e.key != socket) {
              _clientIds.remove(e.key);
              takenOver.add(id);
              e.key.destroy();
            }
          }
          _clientIds[socket] = id;
        }
        socket.add([0x20, 0x02, 0x00, 0x00]);
      case 8: // SUBSCRIBE
        socket.add([0x90, 0x03, body[0], body[1], 0x01]);
      case 12: // PINGREQ
        if (!ignorePings) socket.add([0xD0, 0x00]);
      case 3: // PUBLISH
        publishCount++;
        if (dropOnPublish) {
          socket.destroy();
          return;
        }
        if (withholdPuback) return;
        if ((header >> 1) & 3 == 1) {
          final topicLength = (body[0] << 8) | body[1];
          socket.add([0x40, 0x02, body[2 + topicLength], body[3 + topicLength]]);
          pubackCount++;
        }
    }
  }

  /// Client id do payload do CONNECT: nome do protocolo (2 + n bytes), nível,
  /// flags e keepalive (4 bytes), e então o id (2 + n bytes).
  static String? _clientIdOf(Uint8List body) {
    if (body.length < 2) return null;
    final nome = (body[0] << 8) | body[1];
    final inicio = 2 + nome + 4;
    if (body.length < inicio + 2) return null;
    final n = (body[inicio] << 8) | body[inicio + 1];
    if (body.length < inicio + 2 + n) return null;
    return String.fromCharCodes(body, inicio + 2, inicio + 2 + n);
  }

  /// Fecha todas as conexões abertas, mas continua aceitando novas.
  void dropClients() {
    for (final socket in List.of(_clients)) {
      socket.destroy();
    }
  }

  /// Derruba todas as conexões com RST (SO_LINGER 0) em vez de FIN, como uma
  /// partição ou um par que some: no cliente, o erro (errno 104) completa o
  /// `Socket.done` do sink de escrita sem ouvinte, o mesmo caminho da #56.
  void resetClients() {
    final linger = Uint8List(8);
    linger.buffer.asByteData()
      ..setInt32(0, 1, Endian.host) // l_onoff
      ..setInt32(4, 0, Endian.host); // l_linger
    for (final socket in List.of(_clients)) {
      // SOL_SOCKET/SO_LINGER do Linux (13); em outro SO a opção pode falhar.
      socket.setRawOption(
        RawSocketOption(RawSocketOption.levelSocket, 13, linger),
      );
      socket.destroy();
    }
  }

  Future<void> close() async {
    dropClients();
    await _server.close();
  }
}
