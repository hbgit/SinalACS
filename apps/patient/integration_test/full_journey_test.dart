/// Jornada completa do paciente, pela TELA, contra a stack de e2e (banco de
/// teste, sem login de desenvolvimento): OTP real, termos, triagem, alerta,
/// status e "Meus dados" (o território do ACS é `tool/territory_check.dart`, no host). Só roda com as fixtures
/// (`--dart-define=E2E_FIXTURES=...`, ver `scripts/qa/patient_full_e2e.sh`); sem
/// elas o grupo é pulado, então `e2e.sh --full` não quebra.
///
/// O servidor impõe 60 s entre dois pedidos de código do MESMO paciente, por
/// isso cada teste usa o seu: `main` (código errado e certo), `chronic` (a
/// jornada inteira). O GPS é um leitor fixo: o diálogo de permissão do sistema
/// não é alcançável por `flutter test`, e o alerta tem de sair mesmo assim.
///
/// PRIVACIDADE: só dados sintéticos das fixtures; CPF, código e token nunca são
/// impressos.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';
import 'package:sinalacs_patient/core/privacy/location_hash.dart';

import '../test/support/e2e_config.dart';
import '../test/support/e2e_login_core.dart';
import 'support/e2e_login.dart';

const _relay = String.fromEnvironment('OTP_RELAY', defaultValue: 'http://localhost:8765/code');

class _FixedLocation implements LocationReader {
  @override
  Future<LocationReading> read({Duration timeout = const Duration(seconds: 8)}) async =>
      const LocationAvailable('e2ehash00001', '-2356:-4664');
}

/// Bate frames até [finder] aparecer: com rede de verdade o `pumpAndSettle`
/// pode terminar antes da resposta chegar (não há frame agendado enquanto se
/// espera o socket).
Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final limit = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(limit)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('não apareceu em ${timeout.inSeconds}s: $finder');
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final config = e2eConfig();

  Future<BackendClient> backendReal() async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    return BackendClient(trustedCaBytes: ca);
  }

  /// Preenche CPF e data, pede o código e devolve o instante do pedido.
  Future<int> pedirCodigo(WidgetTester tester, E2ePatientFixture p) async {
    await tester.enterText(find.byKey(const Key('cpf_field')), p.cpf);
    await tester.enterText(find.byKey(const Key('birth_date_field')), _ddmmyyyy(p.birthDate));
    final pedidoEm = await relayNow(_relay);
    await tapKey(tester, 'enter_button');
    await pumpUntil(tester, find.byKey(const Key('otp_code_field')));
    return pedidoEm;
  }

  Future<void> digitarCodigo(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('otp_code_field')), code);
    await tapKey(tester, 'verify_code_button');
  }

  /// Passa pelo convite de termos, se o paciente ainda não os aceitou.
  Future<void> aceitarTermosSePedido(WidgetTester tester) async {
    final termos = find.byKey(const Key('terms_gate_accept_button'));
    final home = find.text('Urgência');
    final limit = DateTime.now().add(const Duration(seconds: 30));
    while (termos.evaluate().isEmpty && home.evaluate().isEmpty) {
      if (DateTime.now().isAfter(limit)) throw TestFailure('nem termos nem home após o login');
      await tester.pump(const Duration(milliseconds: 250));
    }
    if (termos.evaluate().isNotEmpty) {
      await tapKey(tester, 'terms_gate_checkbox');
      await tapKey(tester, 'terms_gate_accept_button');
      await pumpUntil(tester, home);
    }
  }

  group(
    'jornada do paciente contra o banco de teste',
    skip: config == null ? 'defina E2E_FIXTURES (scripts/qa/patient_full_e2e.sh)' : false,
    () {
      testWidgets('código errado não entra; o certo, pedido uma única vez, entra', (tester) async {
        final backend = await backendReal();
        addTearDown(backend.close);
        await tester.pumpWidget(SinalAcsApp(backend: backend, locationReader: _FixedLocation()));
        final p = config!.patient('main');

        final pedidoEm = await pedirCodigo(tester, p);
        await digitarCodigo(tester, '000000');
        await pumpUntil(tester, find.byKey(const Key('login_error')));
        expect(find.byKey(const Key('panic_button')), findsNothing, reason: 'código errado não abre a sessão');

        // O código verdadeiro é o do PRIMEIRO pedido: errar não gasta outro SMS.
        await digitarCodigo(tester, await codeFromRelay(_relay, pedidoEm));
        await aceitarTermosSePedido(tester);
        expect(find.text('Urgência'), findsOneWidget);
        // E de fato foi UM pedido: errar o código não pode ter gasto outro SMS.
        expect(await relayCount(_relay, pedidoEm), 1);
      });

      testWidgets('triagem vermelha, alerta, status e Meus dados do próprio paciente', (tester) async {
        final backend = await backendReal();
        addTearDown(backend.close);
        await tester.pumpWidget(SinalAcsApp(backend: backend, locationReader: _FixedLocation()));
        final p = config!.patient('chronic');

        final pedidoEm = await pedirCodigo(tester, p);
        await digitarCodigo(tester, await codeFromRelay(_relay, pedidoEm));
        await aceitarTermosSePedido(tester);

        // Triagem: dor no peito, "não" ao resto; quem classifica é o servidor.
        for (final symptom in TriageSymptom.values) {
          final key = symptom == TriageSymptom.chestPain ? symptom.key : '${symptom.key}_no';
          await tester.tap(find.byKey(Key(key)));
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(find.byKey(const Key('submit_triage')));
          await tester.pump(const Duration(milliseconds: 400));
        }
        await pumpUntil(tester, find.text('Risco: Vermelho'));

        // Alerta de urgência: sai mesmo sem o GPS do sistema.
        await tester.tap(find.text('Urgência'));
        await tester.pump(const Duration(milliseconds: 400));
        await tapKey(tester, 'panic_button');
        await tester.tap(find.text('Confirmar alerta'));
        await pumpUntil(tester, find.textContaining('Alerta recebido pela equipe'));

        // Status real, não o vazio.
        await tester.tap(find.text('Status'));
        await pumpUntil(tester, find.text('Enviado — aguardando confirmação da equipe'));
        expect(find.byKey(const Key('status_empty')), findsNothing);

        // Meus dados: o cadastro da fixture, a condição crônica decifrada, e só.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.tap(find.text('Mais'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Meus dados'));
        await pumpUntil(tester, find.text(p.name));
        expect(find.textContaining('ipertens'), findsWidgets);
        expect(find.text(config.patient('main').name), findsNothing);
        expect(find.text(config.patient('outsider').name), findsNothing);
      });
    },
  );
}
