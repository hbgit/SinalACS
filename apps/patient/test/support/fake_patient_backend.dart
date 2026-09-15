import 'package:sinalacs_client/sinalacs_client.dart';
import 'package:sinalacs_patient/core/network/auth_session.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

/// Duplo de teste do backend do paciente.
///
/// Mantém os testes de widget herméticos: eles verificam o comportamento da
/// tela (o que é enviado, o que é exibido), não a rede. A conexão real é
/// verificada pelos testes de integração e por `tool/live_check.dart`.
class FakePatientBackend implements PatientBackend {
  FakePatientBackend({
    this.risk = RiskLevel.green,
    this.loginFailure,
    this.alertFailure,
  });

  /// Risco que o "servidor" devolve. A tela não pode derivá-lo por conta própria.
  RiskLevel risk;

  BackendFailure? loginFailure;
  BackendFailure? alertFailure;

  /// Argumentos recebidos, para as asserções.
  final List<Map<String, bool>> triageCalls = <Map<String, bool>>[];
  final List<String> idempotencyKeys = <String>[];
  int loginCount = 0;
  bool closed = false;

  AuthSession? _session;

  @override
  AuthSession? get session => _session;

  @override
  bool get isAuthenticated => _session != null;

  @override
  Future<ServiceHealth> health() async => ServiceHealth(
        status: 'ok',
        mqttConnected: true,
        dbConnected: true,
      );

  @override
  Future<AuthSession> login() async {
    loginCount++;
    final failure = loginFailure;
    if (failure != null) throw failure;

    final session = AuthSession(
      accessToken: 'token-de-teste',
      tokenType: 'Bearer',
      userId: '00000000-0000-4000-8000-000000000001',
      role: 'patient',
      microAreaId: '00000000-0000-4000-8000-000000000003',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
    );
    _session = session;
    return session;
  }

  @override
  Future<RiskLevel> evaluateTriage({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async {
    triageCalls.add(<String, bool>{
      'chestPain': chestPain,
      'difficultyBreathing': difficultyBreathing,
      'fever': fever,
      'persistentVomiting': persistentVomiting,
      'bleeding': bleeding,
      'severeWeakness': severeWeakness,
    });
    return risk;
  }

  @override
  Future<RedAlertResult> createRedAlert({
    required String idempotencyKey,
    required String locationHash,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    final failure = alertFailure;
    if (failure != null) throw failure;

    return RedAlertResult(
      alertId: 'alerta-de-teste',
      status: AlertStatus.pending,
      published: true,
    );
  }

  @override
  void close() => closed = true;
}
