/// Limpeza remota do aparelho (#81) no emulador, contra o BANCO DE TESTE: o
/// aparelho é limpo com uma visita NÃO enviada e o painel aberto.
///
/// Montagem de produção (`main.dart`) no que a prova mede: o id da instalação
/// (`SecureStorageDeviceIdStore`), a chave do SQLCipher
/// (`SecureStorageDatabaseKeyStore`), o banco real `sinalacs_acs.db`, os tokens
/// de envio (`SecureStorageUploadTokenStore`) e o diário
/// (`SharedPreferencesWipeJournal`). O refresh token fica no
/// `SecureStorageSessionTokenStore` (desbloqueio `notRequired`), como nos
/// outros e2e do ACS: o `BiometricPrompt` não é o que está em prova aqui.
///
/// Roteiro:
///   1. o ACS entra pela tela;
///   2. registra uma visita com o ENVIO de visitas fora do ar (decorator
///      [EnvioDeVisitasForaDoAr]) e fica no formulário com o painel aberto —
///      sem "Sair": o envio diferido do logout subiria a visita;
///   3. por um `Client` próprio, o coordenador entra (relé `/coordenador`,
///      ativação da MFA e TOTP) e pede a limpeza (`stolen`);
///   4. segundo plano e volta: a retomada pergunta `pendingWipe` e o aparelho
///      é limpo, até a tela `device_wiped`;
///   5. no aparelho: o banco não existe ou reabre vazio, a chave mudou, não há
///      token de envio e o id da instalação é outro;
///   6. "Entrar de novo" com a mesma credencial abre o painel com o id novo.
///
/// Só roda por `scripts/qa/acs_remote_wipe_e2e.sh` (sufixo `_e2e`: a
/// descoberta do `flutter test integration_test` não o encontra). Linhas
/// marcadoras para o script:
///   E2E_WIPE_PEDIDO order=<uuid> device=<id antigo>
///   E2E_WIPE_OK visita=<localId> acs=<uuid> novo=<id novo>
///
/// PRIVACIDADE: só fixtures sintéticas geradas por execução. A chave do banco,
/// senhas e o segredo TOTP nunca são impressos.
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/security/secure_session_token_store.dart';
import 'package:sinalacs_acs/core/security/secure_upload_token_store.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory_factory.dart';
import 'package:sinalacs_acs/core/services/remote_wipe.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/e2e_acs.dart';
import 'support/envio_fora_do_ar.dart';
import 'support/totp.dart';

class _SemBiometria implements BiometricGate {
  @override
  Future<bool> get isAvailable async => false;
  @override
  Future<UnlockResult> authenticate({required String reason}) async => UnlockResult.unavailable;
}

Future<void> _ate(WidgetTester tester, bool Function() feito, {required Duration teto, required String oQue}) async {
  final fim = DateTime.now().add(teto);
  while (!feito()) {
    if (DateTime.now().isAfter(fim)) fail('$oQue: não aconteceu em ${teto.inSeconds} s');
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _ateNoDisco(WidgetTester tester, Future<bool> Function() feito,
    {required Duration teto, required String oQue}) async {
  final fim = DateTime.now().add(teto);
  while (!await feito()) {
    if (DateTime.now().isAfter(fim)) fail('$oQue: não aconteceu em ${teto.inSeconds} s');
    await tester.pump(const Duration(milliseconds: 300));
  }
}

int _passo(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

/// Coordenador pela rede real, fora do app: ativa a MFA com o código de
/// ativação de uso único e entra com o TOTP do passo SEGUINTE (o servidor
/// barra o reuso do passo já gasto na confirmação).
Future<String> _tokenDoCoordenador(api.Client cliente) async {
  final cred = await coordinatorCredentialFromRelay();
  final inicio = await cliente.auth.beginStaffTotpEnrollment(
    matricula: cred.matricula,
    password: cred.senha,
    activationCode: cred.activationCode,
  );
  final segredo = base32Decode(inicio.secretBase32);
  final confirmacao = DateTime.now();
  await cliente.auth.confirmStaffTotpEnrollment(
    matricula: cred.matricula,
    password: cred.senha,
    activationCode: cred.activationCode,
    code: totpCode(segredo, confirmacao),
  );
  while (_passo(DateTime.now()) <= _passo(confirmacao)) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final login = await cliente.auth.loginStaff(
    matricula: cred.matricula,
    password: cred.senha,
    totpCode: totpCode(segredo, DateTime.now()),
  );
  return login.accessToken;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('limpeza remota com o painel aberto e uma visita não enviada: banco, chave, tokens e id saem',
      (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    const host = String.fromEnvironment('SINALACS_HOST', defaultValue: 'https://10.0.2.2/');
    final cred = await acsCredentialFromRelay();
    final main = e2ePatient('main');

    // 0) Montagem de produção, a partir de um aparelho sem restos de outras
    //    execuções: sessão, tokens de envio, diário e banco.
    final deviceIds = SecureStorageDeviceIdStore();
    final uploadTokens = SecureStorageUploadTokenStore();
    final chaves = SecureStorageDatabaseKeyStore();
    final diario = SharedPreferencesWipeJournal();
    final sessao = SecureStorageSessionTokenStore();
    await sessao.clear();
    await uploadTokens.clearAll();
    await diario.clear();
    const arquivo = 'sinalacs_acs.db';
    await EncryptedLocalDatabase.deleteDatabaseFile(arquivo);
    final caminho = await EncryptedLocalDatabase.pathFor(arquivo);

    final real = BackendClient(
      trustedCaBytes: ca,
      tokenStore: sessao,
      deviceIds: deviceIds,
      uploadTokens: uploadTokens,
    );
    addTearDown(real.close);
    final backend = EnvioDeVisitasForaDoAr(real);
    final storage = SqlCipherVisitStorage(keyStore: chaves);

    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      biometricGate: _SemBiometria(),
      syncInterval: const Duration(hours: 2),
      visitStorage: storage,
      microAreaDirectory: buildMicroAreaDirectory(backend: backend),
      uploadTokens: uploadTokens,
      deviceIds: deviceIds,
      wipeJournal: diario,
    ));

    Future<void> entrar() async {
      await _ate(tester, () => find.byKey(const Key('matricula_field')).evaluate().isNotEmpty,
          teto: const Duration(seconds: 30), oQue: 'tela de login');
      await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
      await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
      final entrarBotao = find.byKey(const Key('login_button'));
      await tester.ensureVisible(entrarBotao);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(entrarBotao);
      await _ate(
        tester,
        () => entrarBotao.evaluate().isEmpty || find.byKey(const Key('login_error')).evaluate().isNotEmpty,
        teto: const Duration(seconds: 30),
        oQue: 'login',
      );
      expect(find.byKey(const Key('login_error')), findsNothing);
    }

    // 1) O ACS entra pela tela. O login envia o id da instalação: refresh token
    //    e token de envio ficam amarrados a ele no servidor.
    await entrar();
    final acsId = real.session!.userId;
    final idAntigo = await deviceIds.readOrCreate();
    expect(await uploadTokens.read(acsId), isNotNull, reason: 'o login com deviceId deixa o token de envio');
    final chaveAntiga = await chaves.readOrCreate();

    // 2) Uma visita com o envio fora do ar: fica pendente, só no aparelho.
    await tester.tap(find.text('Visita'));
    await _ate(tester, () => find.byKey(Key('patient_${main.id}')).evaluate().isNotEmpty,
        teto: const Duration(seconds: 30), oQue: 'paciente da microárea no seletor');
    await tester.tap(find.byKey(Key('patient_${main.id}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('arrival_confirmation')));
    await tester.pump();
    final salvar = find.byKey(const Key('save_visit'));
    await Scrollable.ensureVisible(tester.element(salvar), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(salvar);
    await _ate(tester, () => find.text('Pendentes de sincronização: 1').evaluate().isNotEmpty,
        teto: const Duration(seconds: 20), oQue: 'visita pendente');
    final noDisco = await storage.forOwner(acsId).load();
    expect(noDisco, hasLength(1), reason: 'a visita está no disco, sob o dono');
    final visita = noDisco.single.localId;
    // O ACS segue no formulário, com o painel aberto (Review Focus 1).
    await tester.enterText(find.widgetWithText(TextField, 'Observações de campo'), 'e2e limpeza remota');
    await tester.pump();
    expect(backend.recusas, 0, reason: 'nada tentou subir ainda; a recusa abaixo é a prova do envio barrado');
    final sincronizar = find.byKey(const Key('sync_visits'));
    await Scrollable.ensureVisible(tester.element(sincronizar), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(sincronizar);
    await _ate(tester, () => backend.recusas > 0, teto: const Duration(seconds: 10), oQue: 'envio tentado e barrado');
    expect(find.text('Pendentes de sincronização: 1'), findsOneWidget, reason: 'a visita continua pendente');

    // 3) O coordenador pede a limpeza pela rede real (fora do app).
    final cliente = api.Client(host, securityContext: SecurityContext()..setTrustedCertificatesBytes(ca))
      ..connectivityMonitor = null;
    addTearDown(cliente.close);
    final tokenCoordenador = await _tokenDoCoordenador(cliente);
    final pedido = await cliente.admin.orderDeviceWipe(
      accessToken: tokenCoordenador,
      acsId: acsId,
      deviceId: idAntigo,
      reason: api.DeviceWipeReason.stolen,
    );
    expect(pedido.alreadyOrdered, isFalse);
    // ignore: avoid_print
    print('E2E_WIPE_PEDIDO order=${pedido.orderId} device=$idAntigo');
    expect(find.byKey(const Key('device_wiped')), findsNothing, reason: 'nada muda antes de um gatilho');

    // 4) Segundo plano e volta (a sequência completa: o campo de texto aberto
    //    escuta o ciclo e recusa pular estados). A retomada pergunta o pedido.
    for (final estado in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(estado);
    }
    await _ate(tester, () => find.byKey(const Key('device_wiped')).evaluate().isNotEmpty,
        teto: const Duration(seconds: 30), oQue: 'tela device_wiped');
    expect(find.byKey(const Key('save_visit')), findsNothing, reason: 'o painel saiu');
    expect(real.session, isNull, reason: 'a limpeza esquece a sessão local');
    // A confirmação chega ao servidor e só então o diário é apagado (D7).
    await _ateNoDisco(tester, () async => await diario.read() == null,
        teto: const Duration(seconds: 30), oQue: 'confirmação entregue e diário apagado');

    // 5) No aparelho. Antes de qualquer abertura: o arquivo sumiu?
    final arquivoExistia = File(caminho).existsSync();
    expect(await uploadTokens.owners(), isEmpty, reason: 'nenhum token de envio sobra');
    expect(await uploadTokens.read(acsId), isNull);
    final idNovo = await deviceIds.readOrCreate();
    expect(idNovo, isNot(idAntigo), reason: 'a instalação ganha outro id');
    final chaveNova = await chaves.readOrCreate();
    expect(chaveNova == chaveAntiga, isFalse, reason: 'a chave do SQLCipher foi trocada'); // sem imprimir a chave
    final db = await storage.database.open();
    for (final tabela in ['offline_visits', 'sync_cursor', 'micro_area_cache', 'micro_area_cache_meta']) {
      final n = (await db.rawQuery('SELECT COUNT(*) AS n FROM $tabela')).single['n']! as int;
      expect(n, 0, reason: '$tabela depois da limpeza (arquivo existia: $arquivoExistia)');
    }
    // ignore: avoid_print
    print('E2E_WIPE_APARELHO arquivo_existia=$arquivoExistia chave_trocada=true tokens_de_envio=0');

    // 6) "Entrar de novo" com a mesma credencial: o id novo não tem pedido.
    //    O envio volta ao ar; se a visita tivesse sobrado, subiria agora e o
    //    script a acharia em `visits`.
    backend.offline = false;
    final deNovo = find.byKey(const Key('device_wiped_login'));
    await tester.ensureVisible(deNovo);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(deNovo);
    await entrar();
    expect(real.session!.userId, acsId);
    expect(await deviceIds.readOrCreate(), idNovo);
    await tester.tap(find.text('Visita'));
    await _ate(tester, () => find.text('Pendentes de sincronização: 0').evaluate().isNotEmpty,
        teto: const Duration(seconds: 30), oQue: 'painel novo sem pendência');
    expect(await storage.forOwner(acsId).load(), isEmpty, reason: 'a visita não voltou');
    // ignore: avoid_print
    print('E2E_WIPE_OK visita=$visita acs=$acsId novo=$idNovo');

    // Desmonta o app aqui: o feed e os timers do painel ainda estão ativos.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
