import 'dart:async';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';

/// Política pura de classificação de erros assíncronos sem dono (#56).
///
/// Um erro de E/S transitório é o que uma queda de rede ou do broker produz
/// (socket reiniciado, handshake TLS interrompido, tempo esgotado, cliente MQTT
/// sem conexão). Reutilizada pelo dispatcher MQTT e pela zona global de
/// `bin/main.dart`, para a lista não existir em dois lugares.
bool isTransientIoError(Object e) =>
    e is SocketException ||
    e is TlsException || // inclui HandshakeException
    e is TimeoutException ||
    e is ConnectionException ||
    e is NoConnectionException ||
    e is StateError && e.message == 'socket is null';

/// Texto seguro para log: só o tipo e, para `SocketException`, o errno. Nunca
/// a mensagem, o endereço ou a pilha (VAZ-01).
String describeErrorForLog(Object e) {
  if (e is SocketException) {
    final code = e.osError?.errorCode;
    if (code != null) return '${e.runtimeType}, errno=$code';
  }
  return '${e.runtimeType}';
}

/// Código de saída do processo quando a zona global recebe um erro que não é
/// de E/S transitória (estado possivelmente inconsistente; o restart assume).
const uncaughtFatalExitCode = 70;

/// Cria o handler da zona global. [log] e [exitFn] são injetáveis para teste.
void Function(Object, StackTrace) buildUncaughtErrorHandler({
  required void Function(String) log,
  required void Function(int) exitFn,
}) {
  return (Object error, StackTrace _) {
    if (isTransientIoError(error)) {
      log(
        'Erro de E/S sem dono (${describeErrorForLog(error)}); '
        'processo mantido.',
      );
      return;
    }
    log('Erro assíncrono não tratado (${error.runtimeType}); encerrando.');
    exitFn(uncaughtFatalExitCode);
  };
}
