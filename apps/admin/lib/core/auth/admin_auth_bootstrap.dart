import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart';

import '../data/admin_data_source.dart';
import '../data/backend_admin_data_source.dart';
import 'admin_auth_backend.dart';
import 'backend_config.dart';

/// Asset com a CA que assina o certificado do Traefik em :443 (RNF04).
///
/// Cópia do mesmo arquivo que os outros dois apps usam, feita por
/// `scripts/dev/sync_dev_ca.sh`; é uma CA pública de desenvolvimento, não um
/// segredo, mas é regenerável e por isso fica fora do versionamento.
const adminRpcCaAsset = 'assets/certs/dev_rpc_ca.crt';

/// Backend de auth usado quando a configuração é inválida (host sem https).
///
/// O app sobe e recusa toda chamada dizendo o motivo, em vez de cair no boot.
class MisconfiguredAdminAuth implements AdminAuthBackend {
  const MisconfiguredAdminAuth(this.failure);
  final AdminAuthFailure failure;

  @override
  Future<AdminSession> login({required String matricula, required String senha, String? totpCode}) =>
      Future.error(failure);

  @override
  Future<({String secret, String otpauthUri})> beginMfaEnrollment({required String matricula, required String senha, required String activationCode}) =>
      Future.error(failure);

  @override
  Future<void> confirmMfaEnrollment({required String matricula, required String senha, required String activationCode, required String code}) =>
      Future.error(failure);
}

/// Cria o [AdminDataSource] de uma sessão já autenticada. O token vive só na
/// fonte de dados, criada depois do login.
typedef AdminDataSourceFactory = AdminDataSource Function(AdminSession session);

/// O que o app precisa para falar com o backend: a autenticação e a fonte de
/// dados, **do mesmo `Client`** (mesma CA, mesmo host https).
class AdminWiring {
  const AdminWiring({required this.auth, required this.dataSourceFor});
  final AdminAuthBackend auth;
  final AdminDataSourceFactory dataSourceFor;
}

/// Monta [AdminWiring]. Host sem https: a autenticação recusa toda chamada com o
/// motivo, e como nenhuma sessão chega a existir, a fonte de dados nunca é pedida.
AdminWiring buildAdminWiring({String? host, List<int>? caBytes}) {
  try {
    final client = Client(
      AdminBackendConfig.requireSecureHost(host ?? AdminBackendConfig.host),
      securityContext: caBytes == null ? null : (SecurityContext()..setTrustedCertificatesBytes(caBytes)),
    )..connectivityMonitor = null;
    return AdminWiring(
      auth: BackendAdminAuth(client.auth),
      dataSourceFor: (session) => BackendAdminDataSource(client.admin, accessToken: session.accessToken),
    );
  } on FormatException catch (erro) {
    return AdminWiring(
      auth: MisconfiguredAdminAuth(AdminAuthFailure(erro.message)),
      dataSourceFor: (_) => throw StateError('host inválido: não há sessão para abrir o painel'),
    );
  }
}

/// Monta o [AdminAuthBackend] real.
///
/// [caBytes] é a CA de desenvolvimento do RPC. `null` mantém o padrão
/// fail-closed: o `Client` usa as raízes do sistema, e o certificado de
/// desenvolvimento é recusado. Nunca há `badCertificateCallback` que aceite
/// tudo. Um host sem https vira [MisconfiguredAdminAuth].
AdminAuthBackend buildAdminAuth({String? host, List<int>? caBytes}) =>
    buildAdminWiring(host: host, caBytes: caBytes).auth;
