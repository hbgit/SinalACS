import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart';

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

/// Monta o [AdminAuthBackend] real.
///
/// [caBytes] é a CA de desenvolvimento do RPC. `null` mantém o padrão
/// fail-closed: o `Client` usa as raízes do sistema, e o certificado de
/// desenvolvimento é recusado. Nunca há `badCertificateCallback` que aceite
/// tudo. Um host sem https vira [MisconfiguredAdminAuth].
AdminAuthBackend buildAdminAuth({String? host, List<int>? caBytes}) {
  try {
    return BackendAdminAuth.forHost(
      host: AdminBackendConfig.requireSecureHost(host ?? AdminBackendConfig.host),
      clientFactory: (h) => Client(
        h,
        securityContext: caBytes == null ? null : (SecurityContext()..setTrustedCertificatesBytes(caBytes)),
      )..connectivityMonitor = null,
    );
  } on FormatException catch (erro) {
    return MisconfiguredAdminAuth(AdminAuthFailure(erro.message));
  }
}
