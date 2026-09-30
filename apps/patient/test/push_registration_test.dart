import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/push/push_token_source.dart';

import 'support/fake_patient_backend.dart';

class _FakeSource implements PushTokenSource {
  const _FakeSource(this.device);

  final PushDevice? device;

  @override
  Future<PushDevice?> currentDevice() async => device;
}

const _aparelho = PushDevice(token: 'tok-1', platform: 'android');

Future<void> login(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('cpf_field')), '123.456.789-09');
  await tester.enterText(find.byKey(const Key('birth_date_field')), '01/01/1990');
  await tester.tap(find.byKey(const Key('enter_button')));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
  await tester.tap(find.byKey(const Key('verify_code_button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('depois do login registra o token do aparelho', (tester) async {
    final backend = FakePatientBackend()..grantPushConsent();
    await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: const _FakeSource(_aparelho)));
    await login(tester);

    expect(backend.pushRegistrations, [('tok-1', 'android')]);
  });

  testWidgets('sem token (sem Firebase) não chama o servidor', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(backend.pushRegistrations, isEmpty);
    expect(find.byType(PatientHomeShell), findsOneWidget);
  });

  testWidgets('recusa do servidor não afeta a home nem mostra erro', (tester) async {
    final backend = FakePatientBackend()
      ..grantPushConsent()
      ..pushRegistrationFailure = const BackendFailure('sem consentimento');
    await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: const _FakeSource(_aparelho)));
    await login(tester);

    expect(backend.pushRegistrations, hasLength(1));
    expect(find.byType(PatientHomeShell), findsOneWidget);
    expect(find.textContaining('sem consentimento'), findsNothing);
  });

  testWidgets('fonte que lança não afeta a home', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      pushTokens: _ThrowingSource(),
    ));
    await login(tester);

    expect(find.byType(PatientHomeShell), findsOneWidget);
  });

  testWidgets('fonte de token que nunca completa não atrasa a home', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      pushTokens: _NeverSource(),
    ));
    await login(tester);
    expect(find.byType(PatientHomeShell), findsOneWidget);
  });

  testWidgets('sem consentimento de avisos, nem pergunta o token ao provedor', (tester) async {
    final backend = FakePatientBackend();
    final source = _CountingSource();
    await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: source));
    await login(tester);

    expect(source.calls, 0);
    expect(backend.pushRegistrations, isEmpty);
    expect(find.byType(PatientHomeShell), findsOneWidget);
  });

  testWidgets('concedido e depois revogado: vale o mais recente e o provedor não é consultado',
      (tester) async {
    final backend = FakePatientBackend()
      ..addConsentRecord('segmentedPush', 'granted', DateTime.utc(2026, 9, 1))
      ..addConsentRecord('segmentedPush', 'revoked', DateTime.utc(2026, 9, 2));
    final source = _CountingSource();
    await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: source));
    await login(tester);

    expect(source.calls, 0);
  });

  testWidgets('myData falhando no login fecha: nada é pedido nem registrado', (tester) async {
    final backend = FakePatientBackend()
      ..grantPushConsent()
      ..myDataFailure = const BackendFailure('falha');
    final source = _CountingSource();
    await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: source));
    await login(tester);

    expect(source.calls, 0);
    expect(find.byType(PatientHomeShell), findsOneWidget);
  });

  testWidgets('myData que nunca responde não atrasa a home e nada é pedido', (tester) async {
    final backend = FakePatientBackend()..grantPushConsent();
    final gate = Completer<void>();
    backend.myDataGate = gate;
    final source = _CountingSource();
    await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: source));
    await login(tester);

    expect(find.byType(PatientHomeShell), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(source.calls, 0);
  });

  testWidgets('com consentimento vigente, o login registra o token', (tester) async {
    final backend = FakePatientBackend()..grantPushConsent();
    final source = _CountingSource();
    await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: source));
    await login(tester);

    expect(source.calls, 1);
    expect(backend.pushRegistrations, [('tok-1', 'android')]);
  });

  testWidgets('sem PushTokenScope, maybeOf devolve a fonte inerte', (tester) async {
    PushTokenSource? achada;
    await tester.pumpWidget(Builder(builder: (context) {
      achada = PushTokenScope.maybeOf(context);
      return const SizedBox();
    }));
    expect(achada, isA<NoPushTokenSource>());
  });
}

class _CountingSource implements PushTokenSource {
  int calls = 0;

  @override
  Future<PushDevice?> currentDevice() async {
    calls++;
    return _aparelho;
  }
}

class _ThrowingSource implements PushTokenSource {
  @override
  Future<PushDevice?> currentDevice() async => throw StateError('sem provedor');
}

class _NeverSource implements PushTokenSource {
  @override
  Future<PushDevice?> currentDevice() => Completer<PushDevice?>().future;
}
