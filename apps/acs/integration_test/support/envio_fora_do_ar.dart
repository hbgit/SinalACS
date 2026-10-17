import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

/// Backend do app com o ENVIO de visitas (sync, legado, diferido, revogação do
/// token de envio) "fora do ar" enquanto [offline]: falha recuperável, como a
/// queda de rede. Login, lista da microárea e logout seguem o servidor real —
/// é o que permite a A registrar e sair com a visita pendente, e a B entrar.
/// Não é a rede do aparelho caindo: só os caminhos de envio de visita.
class EnvioDeVisitasForaDoAr implements AcsBackend {
  EnvioDeVisitasForaDoAr(this._inner);

  final AcsBackend _inner;
  bool offline = true;
  int recusas = 0;

  Future<T> _rede<T>(Future<T> Function() call) {
    if (offline) {
      recusas++;
      return Future.error(const BackendFailure('Sem conexão (simulada no e2e).'));
    }
    return call();
  }

  @override
  AuthSession? get session => _inner.session;
  @override
  bool get isAuthenticated => _inner.isAuthenticated;
  @override
  void Function()? get onSessionExpired => _inner.onSessionExpired;
  @override
  set onSessionExpired(void Function()? value) => _inner.onSessionExpired = value;
  @override
  void Function(String orderId)? get onDeviceWipeRequired => _inner.onDeviceWipeRequired;
  @override
  set onDeviceWipeRequired(void Function(String orderId)? value) => _inner.onDeviceWipeRequired = value;
  @override
  Future<String?> pendingDeviceWipe(String deviceId) => _inner.pendingDeviceWipe(deviceId);
  @override
  Future<void> confirmDeviceWipe(String deviceId, String orderId) => _inner.confirmDeviceWipe(deviceId, orderId);
  @override
  Future<void> forgetLocalSession() => _inner.forgetLocalSession();
  @override
  Future<bool> get hasStoredSession => _inner.hasStoredSession;
  @override
  Future<SessionUnlock> unlockStoredSession({required String reason}) => _inner.unlockStoredSession(reason: reason);
  @override
  Future<AuthSession?> resumeSession() => _inner.resumeSession();
  @override
  Future<void> logout() => _inner.logout();
  @override
  Future<AuthSession> login({required String matricula, required String senha, String? totpCode}) =>
      _inner.login(matricula: matricula, senha: senha, totpCode: totpCode);
  @override
  Future<api.TotpEnrollmentStart> beginTotpEnrollment({required String matricula, required String senha}) =>
      _inner.beginTotpEnrollment(matricula: matricula, senha: senha);
  @override
  Future<void> confirmTotpEnrollment({required String matricula, required String senha, required String code}) =>
      _inner.confirmTotpEnrollment(matricula: matricula, senha: senha, code: code);
  @override
  Future<AuthSession> developmentLogin({required String role}) => _inner.developmentLogin(role: role);
  @override
  Future<api.AlertAckResult> acknowledge({required String alertId}) => _inner.acknowledge(alertId: alertId);
  @override
  Future<List<api.AcsOpenAlert>> openAlerts() => _inner.openAlerts();
  @override
  Future<api.AlertResolveResult> resolveAlert({required String alertId}) =>
      _inner.resolveAlert(alertId: alertId);
  @override
  Future<List<api.VisitSyncResult>> syncVisits(List<api.VisitSyncEntry> visits, {String? expectedUserId}) =>
      _rede(() => _inner.syncVisits(visits, expectedUserId: expectedUserId));
  @override
  Future<api.VisitSyncResult> resolveVisitConflict(
    api.VisitSyncEntry visit, {
    required int expectedServerVersion,
    String? expectedUserId,
  }) =>
      _rede(() => _inner.resolveVisitConflict(
            visit,
            expectedServerVersion: expectedServerVersion,
            expectedUserId: expectedUserId,
          ));
  @override
  Future<List<api.VisitSyncResult>> syncLegacyVisits(List<api.VisitSyncEntry> visits, {required String deviceId}) =>
      _rede(() => _inner.syncLegacyVisits(visits, deviceId: deviceId));
  @override
  Future<List<api.VisitSyncResult>> syncDeferredVisits({
    required String uploadToken,
    required String deviceId,
    required List<api.VisitSyncEntry> visits,
  }) =>
      _rede(() => _inner.syncDeferredVisits(uploadToken: uploadToken, deviceId: deviceId, visits: visits));
  @override
  Future<void> revokeUploadToken(String uploadToken) => _rede(() => _inner.revokeUploadToken(uploadToken));
  @override
  Future<List<api.VisitSyncEntry>> pullVisits({required DateTime since}) => _inner.pullVisits(since: since);
  @override
  Future<List<api.MicroAreaPatient>> listPatients() => _inner.listPatients();
  @override
  Future<api.UbsContact> ubsContact() => _inner.ubsContact();
  @override
  Future<api.EnrollmentTokenResult> generateInvite({required String patientId}) =>
      _inner.generateInvite(patientId: patientId);
  @override
  Future<api.NoticeSendResult> sendNotice({required String title, required String message, required bool chronicOnly}) =>
      _inner.sendNotice(title: title, message: message, chronicOnly: chronicOnly);
  @override
  void close() => _inner.close();
}
