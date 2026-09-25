import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';

/// Sobe o app do paciente.
///
/// [defaultHost] é o host de RPC que o `--dart-define` compilou — o mesmo valor
/// que [BackendConfig.host] carrega. Ele é **parâmetro** porque a constante de
/// compilação não muda dentro de um `flutter test`: sem esta porta, o desfecho
/// de um host sem https não teria como ficar vermelho num teste hermético.
/// Mesmo motivo (e mesma forma) do `defaultHost` de [BackendClient.resolveHost].
Future<void> main({String? defaultHost}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o plugin de notificações locais antes de `runApp`: é preciso
  // para que `LocalNotificationsReminderScheduler` (RF06 §3.1, lembretes de
  // saúde locais ao aparelho) consiga chamar `zonedSchedule`/`cancel` mais
  // tarde. `@mipmap/ic_launcher` é o ícone padrão já usado pelo app — ver
  // `android/app/src/main/res/mipmap-*/ic_launcher.png`.
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  // A partir do Android 13 (API 33) mostrar notificação exige permissão
  // concedida em tempo de execução; sem pedir, os lembretes agendados nunca
  // apareceriam nesses aparelhos. `resolvePlatformSpecificImplementation`
  // retorna `null` fora do Android (ex.: `flutter test`), daí o `?.`.
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  final caBytes = await _rpcCaBytes();

  // O host vem do `--dart-define` e é validado **aqui**, antes de construir
  // qualquer cliente: um host em texto claro é a única configuração em que este
  // app não pode falar com o backend (RNF04/L-08).
  //
  // Um host sem https **não derruba o boot** — é a mesma política que o asset
  // da CA recebeu. O app sobe com um backend que recusa toda chamada dizendo o
  // motivo, e o motivo nomeia o host. Antes disto, esta falha chegava
  // disfarçada: o `catch` da leitura da CA a capturava, logava *"CA do RPC não
  // pôde ser carregada"* (falso, a CA tinha carregado) e a segunda construção
  // do cliente estourava fora de qualquer guarda, antes do `runApp`.
  PatientBackend backend;
  try {
    backend = BackendClient(
      host: requireSecureHost(defaultHost ?? BackendConfig.host),
      trustedCaBytes: caBytes,
    );
  } on BackendFailure catch (failure) {
    debugPrint(
      '${failure.message} O app sobe, mas nenhuma chamada ao backend vai '
      'funcionar enquanto o host não for https.',
    );
    backend = MisconfiguredBackend(failure);
  }

  // O cliente é construído aqui, e não dentro de `SinalAcsApp`, porque só aqui
  // a CA já foi lida: `BackendConfig` não importa `rootBundle` de propósito —
  // `tool/live_check.dart` o importa fora do Flutter, onde `dart:ui` não existe.
  runApp(SinalAcsApp(backend: backend));
}

/// Os bytes da CA de desenvolvimento do RPC, ou `null` quando ela não pode ser
/// usada.
///
/// **Nenhuma das duas falhas é fatal**, de propósito: o cliente é construído
/// sem CA, o app sobe, e a falha aparece na tela como erro de conexão, com a
/// causa real no log abaixo — melhor que derrubar o app no boot por um arquivo
/// que só existe depois de `scripts/dev/sync_dev_ca.sh`.
///
///   · **ausente** — `rootBundle.load` lança, e é o caso mais comum (o asset
///     não é versionado);
///   · **presente mas corrompida** (vazia ou lixo) — `setTrustedCertificatesBytes`
///     lança `TlsException`, e essa exceção acontecia **fora** de qualquer
///     guarda, antes do `runApp`: exceção não tratada e app que não subia.
///
/// A corrupção é medida **aqui**, com um `SecurityContext` de sonda, e não na
/// construção do `BackendClient`. As duas coisas moravam na mesma guarda, e era
/// por isso que uma falha de *host* saía carimbada como falha de *CA*: o `catch`
/// não sabia qual das duas tinha falhado. Separadas, cada uma é dita por si.
Future<List<int>?> _rpcCaBytes() async {
  try {
    final data = await rootBundle.load(BackendConfig.rpcCaAsset);
    final bytes = data.buffer.asUint8List();
    // Sonda: exatamente a chamada que o `BackendClient` faz com estes bytes.
    SecurityContext().setTrustedCertificatesBytes(bytes);
    return bytes;
  } catch (error) {
    debugPrint(
      'CA do RPC não pôde ser carregada de ${BackendConfig.rpcCaAsset}: $error. '
      'Rode ./scripts/dev/sync_dev_ca.sh depois de subir a stack.',
    );
    return null;
  }
}
