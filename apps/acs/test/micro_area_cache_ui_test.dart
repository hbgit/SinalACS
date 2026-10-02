import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'login_flow_test.dart' show entrar;
import 'support/fakes.dart';
import 'support/memory_micro_area_store.dart';

void main() {
  guardaDoMain();
  late FakeAcsBackend backend;

  setUp(() {
    backend = FakeAcsBackend()
      ..patients = [
        MicroAreaPatient(
          patientId: syntheticPatientId(5),
          name: 'Fulano de Tal',
          isChronic: false,
          chronicConditions: const [],
        ),
      ];
  });

  Future<void> abrirVisita(WidgetTester tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      feedBuilder: (queue) => FakeAlertFeed(queue),
      visitQueue: OfflineVisitQueue(),
      microAreaDirectory: MicroAreaDirectory(
        fetch: backend.listPatients,
        session: () => backend.session,
        store: MemoryMicroAreaStore(),
      ),
    ));
    await entrar(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('sem rede, a tela de visita serve o cache e avisa de quando é', (tester) async {
    await abrirVisita(tester);
    // A primeira carga (ao abrir o painel) gravou a lista.
    backend.listPatientsFailure = const BackendFailure('Sem conexão.');

    await tester.tap(find.text('Visita'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('micro_area_cache_notice')), findsOneWidget);
    expect(find.byKey(const Key('patient_picker')), findsOneWidget);
    expect(find.text('Fulano de Tal'), findsOneWidget);
    expect(find.byKey(const Key('patient_directory_error')), findsNothing);
  });

  testWidgets('recusa do servidor não cai no cache: mostra o erro, sem aviso', (tester) async {
    await abrirVisita(tester);
    backend.listPatientsFailure = const BackendFailure('Sessão inválida.', isRecoverable: false);

    await tester.tap(find.text('Visita'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('micro_area_cache_notice')), findsNothing);
    expect(find.byKey(const Key('patient_directory_error')), findsOneWidget);
    expect(find.text('Sessão inválida.'), findsOneWidget);
  });
}

// O padrão de `SinalAcsApp` é sem cache (o Keystore não existe no `flutter test`):
// quem liga o cache de produção é o `main.dart`, e esta guarda impede que ele
// perca a ligação sem ninguém notar.
void guardaDoMain() {
  test('o main.dart liga o cache da microárea de produção', () {
    final fonte = File('lib/main.dart').readAsStringSync();
    expect(fonte, contains('microAreaDirectory: buildMicroAreaDirectory(backend: backend)'));
  });
}
