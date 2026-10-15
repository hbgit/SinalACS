import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Monitoração contínua do backoffice (#44, decisão D5 do ADR
/// `docs/superpowers/specs/2026-10-11-adr-tempo-real-alertas-admin.md`).
///
/// O painel consulta [alertsPulse] a cada 30 s. Uma linha `read` por pulso
/// encheria a trilha com uma linha por coordenador a cada 30 s; por isso a
/// leitura contínua vira uma **sessão**:
///
/// 1. **Papel e escopo primeiro, sempre:** o [AdminScopeResolver] de todo o
///    backoffice; a recusa é auditada (`denied`) e fail-closed.
/// 2. **O pulso não grava `read`.** Consulta o store direto: só contagens e
///    instantes, sem identidade.
/// 3. **START fail-closed:** sem sessão viva do usuário — nenhum pulso nos
///    [sessionIdle] anteriores; exatamente 90 s ainda é sessão viva — o pulso
///    grava `monitoring_session_start` com `record` ANTES de ler. Se a linha
///    não grava, a exceção sobe, nenhum dado sai e o mapa não muda: o próximo
///    pulso tenta o START de novo. Um pulso que chega depois da janela sem END
///    (sessão órfã) abre outra sessão, visível na trilha.
/// 4. **END best-effort:** [endMonitoringSession] remove a entrada e grava
///    `monitoring_session_end` com `recordSafely`. É a única exceção
///    justificada à regra do projeto de usar `record`: a linha de fim não
///    protege dado nenhum (nada é lido aqui), e o app pode ser morto ou perder
///    a rede antes de chamá-la. Idempotente: sem sessão, não grava nada.
///
/// O mapa [sessions] (`userId → último pulso`) é estado do **processo**, não
/// da requisição: vem do `AlertRuntime`, porque os endpoints são construídos
/// por requisição. O backend é de instância única (PRD); um reinício só abre
/// sessão nova, na direção conservadora. Dois primeiros pulsos concorrentes do
/// mesmo usuário podem gravar dois START — também na direção conservadora.
class AdminMonitoringService {
  AdminMonitoringService({
    required this.store,
    required this.audit,
    required this.sessions,
    required this.threshold,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AdminReadStore store;
  final AuditTrail audit;

  /// `userId → instante do último pulso aceito`, compartilhado pelo processo.
  final Map<String, DateTime> sessions;

  /// Prazo do alerta vermelho (`AppConfig.redAlertEscalationSeconds`): o mesmo
  /// de `AdminAlert.overdue` e do escalonamento.
  final Duration threshold;

  final DateTime Function() _clock;

  /// Três vezes o intervalo de 30 s do app: tolera dois pulsos perdidos.
  static const sessionIdle = Duration(seconds: 90);

  static const _recursoPulso = 'admin_pulse';
  static const _recursoSessao = 'admin_monitoring';
  static const _inicio = 'monitoring_session_start';
  static const _fim = 'monitoring_session_end';

  late final AdminScopeResolver _resolver = AdminScopeResolver(
    store: store,
    audit: audit,
  );

  Future<AdminAlertsPulse> alertsPulse(AuthenticatedUser user) async {
    final escopo = await _resolver.resolve(user, recurso: _recursoPulso);
    final agora = _clock().toUtc();

    final ultimo = sessions[user.id];
    if (ultimo == null || agora.difference(ultimo) > sessionIdle) {
      // Fail-closed: se lançar, o mapa fica como estava e nada é lido.
      await audit.record(_evento(user, _inicio));
    }
    sessions[user.id] = agora;

    final indicadores = await store.indicators(escopo, now: agora);
    final contagens = await store.pulse(
      escopo,
      now: agora,
      threshold: threshold,
    );
    return AdminAlertsPulse(
      indicators: indicadores,
      overdueRed: contagens.overdueRed,
      maxChangedAt: contagens.maxChangedAt,
      serverNow: agora,
    );
  }

  Future<void> endMonitoringSession(AuthenticatedUser user) async {
    // A recusa grava `denied` com o actionType do que foi tentado (o fim da
    // sessão), fail-closed como em todo o backoffice.
    await _resolver.resolve(user, recurso: _recursoSessao, actionType: _fim);
    if (sessions.remove(user.id) == null) return;
    // Best-effort de propósito (ver o doc da classe): a entrada já saiu do
    // mapa, então uma falha aqui só deixa a sessão sem linha de fim — o
    // próximo pulso abre outra com START.
    await audit.recordSafely(_evento(user, _fim));
  }

  AuditEvent _evento(AuthenticatedUser user, String actionType) => AuditEvent(
    userId: user.id,
    actionType: actionType,
    resourceType: _recursoSessao,
    result: 'success',
  );
}
