import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Diretório de pacientes da microárea do ACS.
///
/// Existe para a visita de rotina: o único produtor de alertas
/// (`alerts.createRedAlert`) publica só `riskLevel: 'red'` — emergência com
/// SAMU —, e sem esta lista não havia como o ACS escolher um paciente para
/// visitar fora do caminho reativo.
class PatientsEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  Future<List<MicroAreaPatient>> listMicroArea(
    Session session, {
    required String accessToken,
  }) async {
    final user = AlertRuntime.instance.auth.verifyToken(accessToken);
    if (user == null) {
      throw AlertPermissionException(message: 'token inválido ou expirado');
    }

    try {
      return await AlertRuntime.instance.patientDirectoryServiceFor(session).listForAcs(user);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
