import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fake_rpc_server.dart';

/// A renovação silenciosa de 15 minutos usa o refresh token, nunca a senha (o
/// código TOTP não se reaproveita). Se o servidor recusa o refresh, a sessão
/// acaba e a pessoa entra de novo.
void main() {
  late FakeRpcServer server;
  late BackendClient backend;

  setUp(() async {
    server = await FakeRpcServer.start()
      ..mfaRequired = true
      ..rejectRefresh = true
      ..tokenLifetime = const Duration(minutes: -1);
    backend = BackendClient(host: server.host, tokenStore: MemorySessionTokenStore(), deviceIds: MemoryDeviceIdStore());
  });

  tearDown(() async {
    backend.close();
    await server.stop();
  });

  const mensagem = 'Sua sessão expirou. Entre novamente com o código do autenticador.';

  test('refresh recusado falha de forma NÃO recuperável, avisa a UI uma vez e esquece o token', () async {
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
    expect(server.loginCount, 1, reason: 'a senha nunca é reenviada');
    expect(server.refreshCount, 1);

    // O token foi descartado: nova chamada não bate mais no servidor.
    await expectLater(backend.listPatients(), throwsA(isA<BackendFailure>()));
    expect(server.refreshCount, 1);
  });

  test('visita pendente continua pendente quando a sessão MFA expira', () async {
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica', totpCode: '123456');
    final fila = OfflineVisitQueue(synchronizer: BackendVisitSynchronizer(backend: backend, ownerId: backend.session!.userId));
    await fila.add(OfflineVisitRecord(patientId: '00000000-0000-4000-8000-0000000000a1', risk: 'red', status: 'PENDENTE'));

    final resultado = await fila.sync();

    expect(resultado.kind, SyncOutcomeKind.error);
    expect(resultado.message, mensagem);
    expect(fila.pendingCount, 1);
  });
}
