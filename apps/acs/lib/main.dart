import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // O RPC responde por HTTPS e o certificado é assinado por uma CA de
  // desenvolvimento que o armazenamento do sistema não conhece (RNF04/L-08).
  // Sem estes bytes o cliente cai no armazenamento do sistema e a conexão falha
  // — explicitamente, com `HandshakeException`, e não aceitando qualquer
  // certificado.
  //
  // O cliente é construído DENTRO da guarda, junto com a leitura do asset, e
  // não fora dela: são duas falhas possíveis, e a segunda não era tratada. Um
  // asset **presente mas corrompido** (vazio ou lixo) faz
  // `setTrustedCertificatesBytes` lançar `TlsException` na construção do
  // `BackendClient` — e, com a construção fora daqui, essa exceção subia ANTES
  // do `runApp`: exceção não tratada, app não subindo.
  //
  // Nenhuma das duas é fatal, de propósito: o cliente é construído sem CA, o
  // app sobe, e a falha aparece na tela como erro de conexão, com a causa real
  // no log abaixo — melhor que derrubar o app no boot por um arquivo que só
  // existe depois de `scripts/dev/sync_dev_ca.sh`.
  BackendClient backend;
  try {
    final data = await rootBundle.load(BackendConfig.rpcCaAsset);
    backend = BackendClient(trustedCaBytes: data.buffer.asUint8List());
  } catch (error) {
    debugPrint(
      'CA do RPC não pôde ser carregada de ${BackendConfig.rpcCaAsset}: $error. '
      'Rode ./scripts/dev/sync_dev_ca.sh depois de subir a stack.',
    );
    backend = BackendClient();
  }

  // O cliente é construído aqui, e não dentro de `SinalAcsApp`, porque só aqui
  // a CA já foi lida: `BackendConfig` não importa `rootBundle` de propósito —
  // `tool/live_check.dart` o importa fora do Flutter, onde `dart:ui` não existe.
  runApp(SinalAcsApp(backend: backend));
}
