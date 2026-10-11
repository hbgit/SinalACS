import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Autenticação e dados saem do MESMO cliente (mesma CA, mesmo host https): o
  // painel de produção nunca cai no MockAdminDataSource.
  final fiacao = buildAdminWiring(caBytes: await _rpcCaBytes());
  runApp(SinalAdminApp(auth: fiacao.auth, dataSourceFor: fiacao.dataSourceFor));
}

/// Bytes da CA de desenvolvimento do RPC, ou `null` quando não há como usá-la.
///
/// Nenhuma falha é fatal: sem a CA o cliente segue fail-closed (só as raízes do
/// sistema) e a falha aparece na tela como erro de conexão. A corrupção é
/// medida aqui com um `SecurityContext` de sonda, como no app do ACS.
Future<List<int>?> _rpcCaBytes() async {
  try {
    final bytes = (await rootBundle.load(adminRpcCaAsset)).buffer.asUint8List();
    SecurityContext().setTrustedCertificatesBytes(bytes);
    return bytes;
  } catch (erro) {
    debugPrint(
      'CA do RPC não pôde ser carregada de $adminRpcCaAsset: $erro. '
      'Rode ./scripts/dev/sync_dev_ca.sh depois de subir a stack.',
    );
    return null;
  }
}
