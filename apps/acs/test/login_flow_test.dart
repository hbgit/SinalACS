import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

void main() {
  testWidgets('deve autenticar e abrir dashboard com pacientes priorizados', (tester) async {
    await tester.pumpWidget(const SinalAcsApp());

    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), '123456');
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(find.text('Painel de Priorização'), findsOneWidget);
    expect(find.text('Maria Souza'), findsOneWidget);
    expect(find.text('Risco: Vermelho'), findsOneWidget);
  });

  testWidgets('deve expor rótulo semântico e alvo de toque acessível no login do ACS', (tester) async {
    await tester.pumpWidget(const SinalAcsApp());

    final loginButton = tester.widget<FilledButton>(find.byKey(const Key('login_button')));
    final minimumSize = loginButton.style?.minimumSize?.resolve({}) ?? const Size(0, 0);

    expect(find.bySemanticsLabel('Entrar no painel de priorização'), findsOneWidget);
    expect(minimumSize.height, greaterThanOrEqualTo(48));
    expect(minimumSize.width, greaterThanOrEqualTo(48));
  });

  test('deve registrar visita localmente e sincronizar em fila offline', () async {
    final queue = OfflineVisitQueue();

    await queue.add(
      OfflineVisitRecord(
        patientName: 'Maria Souza',
        risk: 'VERMELHO',
        status: 'PENDENTE',
      ),
    );

    expect(queue.pendingCount, 1);

    final result = await queue.sync();

    expect(result.kind, SyncOutcomeKind.synced);
    expect(queue.pendingCount, 0);
    expect(queue.syncedCount, 1);
  });

  test('deve reencolar registros em conflito e reprocessar no retry', () async {
    final queue = OfflineVisitQueue();

    await queue.add(
      OfflineVisitRecord(
        patientName: 'João Souza',
        risk: 'AMARELO',
        status: 'PENDENTE',
      ),
    );

    final conflict = await queue.sync(forceConflict: true);

    expect(conflict.kind, SyncOutcomeKind.conflict);
    expect(queue.pendingCount, 1);
    expect(queue.conflictCount, 1);

    final retried = await queue.sync();

    expect(retried.kind, SyncOutcomeKind.synced);
    expect(queue.pendingCount, 0);
    expect(queue.syncedCount, 1);
  });
}
