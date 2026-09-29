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
    final backend = FakePatientBackend();
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

  testWidgets('sem PushTokenScope, maybeOf devolve a fonte inerte', (tester) async {
    PushTokenSource? achada;
    await tester.pumpWidget(Builder(builder: (context) {
      achada = PushTokenScope.maybeOf(context);
      return const SizedBox();
    }));
    expect(achada, isA<NoPushTokenSource>());
  });
}

class _ThrowingSource implements PushTokenSource {
  @override
  Future<PushDevice?> currentDevice() async => throw StateError('sem provedor');
}

class _NeverSource implements PushTokenSource {
  @override
  Future<PushDevice?> currentDevice() => Completer<PushDevice?>().future;
}
