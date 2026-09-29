import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_rpc_server.dart';

/// A tradução `DataRightsException → BackendFailure(mensagem do servidor, não
/// recuperável)` pelo [BackendClient] real. A suíte de widgets usa o
/// `FakePatientBackend`, que não tem `_guard`, e apagar a cláusula de lá não
/// deixaria nada vermelho sem este arquivo.
void main() {
  late FakeRpcServer server;
  late BackendClient backend;

  setUp(() async {
    server = await FakeRpcServer.start();
    backend = BackendClient(host: server.host);
    await backend.verifyOtp(cpf: '123.456.789-09', code: '123456');
  });

  tearDown(() async {
    backend.close();
    await server.stop();
  });

  Matcher recusaDoServidor(String mensagem) => throwsA(
        isA<BackendFailure>()
            .having((falha) => falha.message, 'mensagem', mensagem)
            .having((falha) => falha.isRecoverable, 'isRecoverable', isFalse),
      );

  test('a recusa de updateConsent chega com a mensagem do servidor', () async {
    server.rejectDataRightsWith = 'O consentimento para dados de saúde é obrigatório.';

    await expectLater(
      backend.updateConsent(purpose: ConsentPurpose.healthDataProcessing, granted: false),
      recusaDoServidor('O consentimento para dados de saúde é obrigatório.'),
    );

    final pedido = server.requests.last;
    expect(pedido.endpoint, 'patients');
    expect(pedido.method, 'updateConsent');
    expect(pedido.args['purpose'], 'healthDataProcessing');
    expect(pedido.args['granted'], false);
  });

  test('a recusa de requestDataCorrection chega com a mensagem do servidor', () async {
    server.rejectDataRightsWith = 'Descreva o que precisa ser corrigido.';

    await expectLater(
      backend.requestDataCorrection('   '),
      recusaDoServidor('Descreva o que precisa ser corrigido.'),
    );
    expect(server.requests.last.args['details'], '   ');
  });

  test('a recusa de requestDataDeletion chega com a mensagem do servidor', () async {
    server.rejectDataRightsWith = 'Recusado.';

    await expectLater(backend.requestDataDeletion(), recusaDoServidor('Recusado.'));
    expect(server.requests.last.method, 'requestDataDeletion');
  });
}
