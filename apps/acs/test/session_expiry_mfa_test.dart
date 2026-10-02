import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fake_rpc_server.dart';

/// Sem refresh token, a renovação silenciosa de 15 minutos não pode reenviar a
/// senha sozinha para um ACS com MFA: o código TOTP não se reaproveita.
void main() {
  late FakeRpcServer server;
  late BackendClient backend;

  setUp(() async {
    server = await FakeRpcServer.start()
      ..mfaRequired = true
      ..tokenLifetime = const Duration(minutes: -1);
    backend = BackendClient(host: server.host);
  });

  tearDown(() async {
    backend.close();
    await server.stop();
  });

  const mensagem = 'Sua sessão expirou. Entre novamente com o código do autenticador.';

  test('renovação sem código falha de forma NÃO recuperável, avisa a UI e esquece a credencial', () async {
    var avisos = 0;
    backend.onSessionExpired = () => avisos++;
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica', totpCode: '123456');
    expect(server.loginCount, 1);

    await expectLater(
      backend.listPatients(),
      throwsA(isA<BackendFailure>()
          .having((f) => f.message, 'message', mensagem)
          .having((f) => f.isRecoverable, 'isRecoverable', isFalse)),
    );
    expect(avisos, 1);
    expect(server.loginCount, 2, reason: 'uma tentativa de renovação, recusada pela MFA');

    // A credencial foi descartada: nova chamada não bate mais no servidor.
    await expectLater(backend.listPatients(), throwsA(isA<BackendFailure>()));
    expect(server.loginCount, 2);
  });

  test('visita pendente continua pendente quando a sessão MFA expira', () async {
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica', totpCode: '123456');
    final fila = OfflineVisitQueue(synchronizer: BackendVisitSynchronizer(backend: backend));
    await fila.add(OfflineVisitRecord(patientId: '00000000-0000-4000-8000-0000000000a1', risk: 'red', status: 'PENDENTE'));

    final resultado = await fila.sync();

    expect(resultado.kind, SyncOutcomeKind.error);
    expect(resultado.message, mensagem);
    expect(fila.pendingCount, 1);
  });
}
