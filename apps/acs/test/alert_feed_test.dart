import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';

/// Estes testes rodam **sem** `--dart-define`, que é exatamente a condição do
/// app compilado à mão — o defeito que eles travam.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('senha do broker', () {
    test('não tem valor padrão embutido no binário', () {
      // O default anterior ('development-acs-password') nunca bateu com o
      // broker, que usa um segredo por máquina: ele só servia para transformar
      // um erro de compilação em "sem conexão com a central".
      expect(
        BackendConfig.mqttPassword,
        isEmpty,
        reason: 'a suíte roda sem --dart-define; um valor aqui significa que '
            'alguém reintroduziu o defaultValue',
      );
      expect(BackendConfig.mqttPasswordMissing, isTrue);
    });

    test('o feed falha antes de abrir qualquer socket quando falta a senha', () async {
      // Se chegasse a tentar conectar, este teste gastaria o timeout do broker
      // em vez de responder na hora.
      final feed = MqttAlertFeed(queue: AlertQueue(microAreaId: 'micro-area'));

      await expectLater(
        feed.start(microAreaId: 'micro-area', acsId: 'acs'),
        throwsA(isA<AlertFeedFailure>().having(
          (failure) => failure.kind,
          'kind',
          AlertFeedFailureKind.missingPassword,
        )),
      );
    });
  });
}
