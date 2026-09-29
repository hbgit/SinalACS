import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'support/fakes.dart';
import 'support/semantics_scan.dart';

/// Mesmo caminho de `entrar` em `login_flow_test.dart` (não importável entre
/// arquivos de teste). Credenciais sintéticas.
Future<void> entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
  await tester.enterText(
    find.byKey(const Key('senha_field')),
    'senha-sintetica',
  );
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();
}

Future<void> abrirConvite(WidgetTester tester) async {
  await tester.tap(find.text('Mais'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Convidar paciente'));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

FakeAcsBackend backendComPacientes() => FakeAcsBackend()
  ..patients = [
    MicroAreaPatient(
      patientId: syntheticPatientId(5),
      name: 'Fulano de Tal',
      isChronic: false,
      chronicConditions: const [],
    ),
    MicroAreaPatient(
      patientId: syntheticPatientId(6),
      name: 'Ciclana da Silva',
      isChronic: true,
      chronicConditions: const ['diabetes'],
    ),
  ];

void main() {
  testWidgets('escolher o paciente e gerar mostra o QR com validade', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes();
    await tester.pumpWidget(
      SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ),
    );
    await entrar(tester);
    await abrirConvite(tester);

    final gerar = tester.widget<FilledButton>(
      find.byKey(const Key('generate_invite_button')),
    );
    expect(
      gerar.onPressed,
      isNull,
      reason: 'sem paciente escolhido não há convite',
    );

    await tapKey(tester, 'invite_patient_${syntheticPatientId(6)}');
    await tapKey(tester, 'generate_invite_button');

    expect(backend.inviteCalls, [syntheticPatientId(6)]);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('invite_expires_at')), findsOneWidget);
    expect(find.textContaining('Válido até'), findsOneWidget);
    expect(find.text('convite-sintetico-1'), findsOneWidget);
  });

  testWidgets('gerar de novo substitui o convite exibido', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes();
    await tester.pumpWidget(
      SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ),
    );
    await entrar(tester);
    await abrirConvite(tester);

    await tapKey(tester, 'invite_patient_${syntheticPatientId(5)}');
    await tapKey(tester, 'generate_invite_button');
    await tapKey(tester, 'generate_invite_button');

    expect(backend.inviteCalls, hasLength(2));
    expect(find.text('convite-sintetico-2'), findsOneWidget);
    expect(find.text('convite-sintetico-1'), findsNothing);
  });

  testWidgets('trocar de paciente esconde o convite anterior', (tester) async {
    // Um QR na tela atribuído ao nome errado ativaria o cadastro de outra
    // pessoa no aparelho de quem ler.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes();
    await tester.pumpWidget(
      SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ),
    );
    await entrar(tester);
    await abrirConvite(tester);

    await tapKey(tester, 'invite_patient_${syntheticPatientId(5)}');
    await tapKey(tester, 'generate_invite_button');
    expect(find.byType(QrImageView), findsOneWidget);

    await tapKey(tester, 'invite_patient_${syntheticPatientId(6)}');
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('convite-sintetico-1'), findsNothing);
  });

  testWidgets('recusa do servidor mostra o motivo e nenhum QR', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes()
      ..inviteFailure = const BackendFailure(
        'Este paciente não pertence à sua microárea.',
        isRecoverable: false,
      );
    await tester.pumpWidget(
      SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ),
    );
    await entrar(tester);
    await abrirConvite(tester);

    await tapKey(tester, 'invite_patient_${syntheticPatientId(5)}');
    await tapKey(tester, 'generate_invite_button');

    expect(find.byKey(const Key('invite_error')), findsOneWidget);
    expect(
      find.text('Este paciente não pertence à sua microárea.'),
      findsOneWidget,
    );
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('falha ao carregar pacientes permite tentar de novo', (
    tester,
  ) async {
    final backend = backendComPacientes()
      ..listPatientsFailure = const BackendFailure(
        'Sem conexão com o servidor.',
      );
    await tester.pumpWidget(
      SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ),
    );
    await entrar(tester);
    await abrirConvite(tester);

    expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
    backend.listPatientsFailure = null;
    await tapKey(tester, 'invite_retry');
    expect(find.text('Fulano de Tal'), findsOneWidget);
  });

  testWidgets('microárea sem paciente explica e não oferece geração', (
    tester,
  ) async {
    await tester.pumpWidget(
      SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ),
    );
    await entrar(tester);
    await abrirConvite(tester);

    expect(find.byKey(const Key('invite_no_patients')), findsOneWidget);
    expect(find.byKey(const Key('generate_invite_button')), findsNothing);
  });

  testWidgets('tela de convite não tem botão inerte para leitor de tela', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      SinalAcsApp(
        backend: backendComPacientes(),
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ),
    );
    await entrar(tester);
    await abrirConvite(tester);
    expectNenhumBotaoInerte(tester);
    handle.dispose();
  });
}
