import 'dart:async';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:sinalacs_server/src/runtime/uncaught_error_policy.dart';
import 'package:test/test.dart';

void main() {
  group('isTransientIoError', () {
    test('reconhece os erros de E/S de queda de rede e de broker', () {
      expect(isTransientIoError(const SocketException('x')), isTrue);
      expect(isTransientIoError(const HandshakeException('x')), isTrue);
      expect(isTransientIoError(const TlsException('x')), isTrue);
      expect(isTransientIoError(TimeoutException('x')), isTrue);
      expect(
        isTransientIoError(ConnectionException(MqttConnectionState.faulted)),
        isTrue,
      );
      expect(isTransientIoError(NoConnectionException('x')), isTrue);
      expect(isTransientIoError(StateError('socket is null')), isTrue);
    });

    test('não trata como transitório o que é defeito de programa', () {
      expect(isTransientIoError(StateError('outro')), isFalse);
      expect(isTransientIoError(ArgumentError('x')), isFalse);
      expect(isTransientIoError(const FormatException('x')), isFalse);
      expect(isTransientIoError(Exception('x')), isFalse);
    });
  });

  group('buildUncaughtErrorHandler', () {
    late List<String> logs;
    late List<int> exits;
    late void Function(Object, StackTrace) handler;

    setUp(() {
      logs = [];
      exits = [];
      handler = buildUncaughtErrorHandler(log: logs.add, exitFn: exits.add);
    });

    test('E/S transitória: registra tipo e errno, mantém vivo', () {
      handler(
        const SocketException(
          'segredo 10.0.0.1:8883',
          osError: OSError('Connection reset by peer', 104),
        ),
        StackTrace.current,
      );
      expect(exits, isEmpty);
      expect(logs.single, contains('SocketException'));
      expect(logs.single, contains('errno=104'));
      expect(logs.single, isNot(contains('segredo')));
      expect(logs.single, isNot(contains('10.0.0.1')));
    });

    test('outro erro: registra só o tipo e sai com código != 0', () {
      handler(StateError('dado do paciente 123'), StackTrace.current);
      expect(exits, [uncaughtFatalExitCode]);
      expect(uncaughtFatalExitCode, isNot(0));
      expect(logs.single, contains('StateError'));
      expect(logs.single, isNot(contains('paciente')));
      expect(logs.single, isNot(contains('#0')));
    });
  });
}
