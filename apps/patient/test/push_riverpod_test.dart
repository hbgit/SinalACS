import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/push/native_push_token_source.dart';
import 'package:sinalacs_patient/core/push/push_token_provider.dart';
import 'package:sinalacs_patient/core/push/push_token_source.dart';

import 'support/fake_patient_backend.dart';

class _Fonte implements PushTokenSource {
  const _Fonte(this.device);

  final PushDevice? device;

  @override
  Future<PushDevice?> currentDevice() async => device;
}

Future<void> login(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('cpf_field')), '123.456.789-09');
  await tester.enterText(find.byKey(const Key('birth_date_field')), '01/01/1990');
  await tester.tap(find.byKey(const Key('enter_button')));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
  await tester.tap(find.byKey(const Key('verify_code_button')));
  await tester.pumpAndSettle();
}

const _canal = MethodChannel('sinalacs/push_token');

void _mockCanal(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_canal, handler);
}

void main() {
  testWidgets('o provider entrega o token da fonte e o registro chega ao backend', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pushTokenSourceProvider
            .overrideWithValue(const _Fonte(PushDevice(token: 'tok-9', platform: 'android'))),
      ],
      child: SinalAcsApp(backend: backend),
    ));
    await login(tester);

    expect(backend.pushRegistrations, [('tok-9', 'android')]);
  });

  testWidgets('sem ProviderScope acima, o app ainda sobe e não registra', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(find.byType(PatientHomeShell), findsOneWidget);
    expect(backend.pushRegistrations, isEmpty);
  });

  testWidgets('a fonte injetada por parâmetro tem precedência sobre o provider', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pushTokenSourceProvider
            .overrideWithValue(const _Fonte(PushDevice(token: 'do-provider', platform: 'ios'))),
      ],
      child: SinalAcsApp(
        backend: backend,
        pushTokens: const _Fonte(PushDevice(token: 'do-parametro', platform: 'android')),
      ),
    ));
    await login(tester);

    expect(backend.pushRegistrations, [('do-parametro', 'android')]);
  });

  test('NativePushTokenSource devolve null quando o canal não existe', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockCanal(null);
    expect(await const NativePushTokenSource().currentDevice(), isNull);
  });

  test('NativePushTokenSource lê o token e a plataforma do canal', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockCanal((call) async {
      expect(call.method, 'getToken');
      return {'token': 'abc', 'platform': 'ios'};
    });
    addTearDown(() => _mockCanal(null));

    final device = await const NativePushTokenSource().currentDevice();
    expect((device!.token, device.platform), ('abc', 'ios'));
  });

  test('resposta malformada ou plataforma desconhecida vira null', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    addTearDown(() => _mockCanal(null));
    for (final resposta in <Object?>[
      {'token': '', 'platform': 'android'},
      {'token': 'abc', 'platform': 'web'},
      {'platform': 'android'},
      'lixo',
      null,
    ]) {
      _mockCanal((call) async => resposta);
      expect(await const NativePushTokenSource().currentDevice(), isNull, reason: '$resposta');
    }
  });

  test('erro de plataforma no canal vira null, não exceção', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockCanal((call) async => throw PlatformException(code: 'sem_permissao'));
    addTearDown(() => _mockCanal(null));
    expect(await const NativePushTokenSource().currentDevice(), isNull);
  });
}
