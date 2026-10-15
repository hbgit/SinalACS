import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/security/upload_token_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fakes.dart';
import 'support/layout_harness.dart' show assentar;

/// Gatilhos do envio diferido no app (D8): depois de abrir o painel, na
/// retomada e quando a rede volta. Nunca bloqueia a UI. Ids sintéticos.
void main() {
  const acsA = 'acs-a';
  const acsB = 'acs-b';

  OfflineVisitRecord visita(String localId) =>
      OfflineVisitRecord(localId: localId, patientId: seedPatientId, risk: 'green', status: 'PENDENTE');

  late InMemoryVisitStorage storage;
  late FakeAcsBackend backend;
  late MemoryUploadTokenStore tokens;
  late StreamController<bool> rede;

  setUp(() async {
    storage = InMemoryVisitStorage();
    await storage.forOwner(acsA).save([visita('a-1')]);
    tokens = MemoryUploadTokenStore({acsA: 'upload-a'});
    backend = FakeAcsBackend()..nextUserId = acsB;
    rede = StreamController<bool>.broadcast();
  });

  tearDown(() => rede.close());

  Future<void> abrirApp(WidgetTester tester, {bool comEnvio = true}) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      visitStorage: storage,
      uploadTokens: comEnvio ? tokens : null,
      deviceIds: comEnvio ? MemoryDeviceIdStore('aparelho-sintetico') : null,
      connectivityChanges: rede.stream,
      biometricGate: FakeBiometricGate(),
      feedBuilder: (q) => FakeAlertFeed(q),
    ));
    await assentar(tester);
  }

  Future<void> entrar(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    final botao = find.byKey(const Key('login_button'));
    await tester.ensureVisible(botao);
    await tester.pump();
    await tester.tap(botao);
    await assentar(tester);
    expect(find.text('Painel operacional'), findsOneWidget);
  }

  List<String> enviadosCom(String token) => [
        for (final lote in backend.deferredBatches)
          if (lote.uploadToken == token) ...lote.visits.map((e) => e.localId),
      ];

  testWidgets('abrir o painel de B sobe a fila de A com o token de A', (tester) async {
    await abrirApp(tester);
    expect(backend.deferredBatches, isEmpty, reason: 'antes do login nada dispara');

    await entrar(tester);

    expect(enviadosCom('upload-a'), ['a-1']);
    expect(await storage.forOwner(acsA).load(), isEmpty);
    expect(backend.revokedUploadTokens, ['upload-a']);
  });

  testWidgets('retomada e volta da rede disparam de novo', (tester) async {
    await abrirApp(tester);
    await entrar(tester);
    final antes = backend.deferredBatches.length;

    await storage.forOwner(acsA).save([visita('a-2')]);
    await tokens.write(acsA, 'upload-a2');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await assentar(tester);
    expect(enviadosCom('upload-a2'), ['a-2']);

    await storage.forOwner(acsA).save([visita('a-3')]);
    await tokens.write(acsA, 'upload-a3');
    rede.add(false);
    await assentar(tester);
    expect(enviadosCom('upload-a3'), isEmpty, reason: 'sem rede não dispara');
    rede.add(true);
    await assentar(tester);
    expect(enviadosCom('upload-a3'), ['a-3']);
    expect(backend.deferredBatches.length, antes + 2);
  });

  testWidgets('sem token store nem id do aparelho (padrão dos testes) nada é enviado', (tester) async {
    await abrirApp(tester, comEnvio: false);
    await entrar(tester);
    rede.add(true);
    await assentar(tester);

    expect(backend.deferredBatches, isEmpty);
    expect(backend.legacyBatches, isEmpty);
  });
}
