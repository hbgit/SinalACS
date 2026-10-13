import 'dart:async';

import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

/// Mock com o pulso roteirizado pelo teste (#44, Task 11).
///
/// Conta pulsos e leituras, deixa o teste mudar `maxChangedAt`, as contagens
/// ou os indicadores do próximo pulso, fazer o pulso falhar e acrescentar
/// alertas à lista — tudo sem rede e com o relógio injetado no mock.
class ScriptedPulseDataSource extends MockAdminDataSource {
  ScriptedPulseDataSource({super.now});

  int pulsos = 0;
  int buscasDeAlertas = 0;
  int buscasDeIndicadores = 0;
  int buscasDeMicroareas = 0;

  /// Quando não nulo, o pulso devolve este futuro (por exemplo, um que nunca
  /// completa, para provar o prazo do pulso no app).
  Future<AlertsPulse>? pulsoPendurado;
  bool _dentroDoPulso = false;

  /// Substituem o campo correspondente do pulso do mock quando não nulos.
  DateTime? maxChangedAt;
  int? overdueRed;
  DashboardIndicators? indicadores;

  /// Lançada por todo pulso enquanto não for nula (falha persistente).
  Object? falhaDoPulso;

  /// Lançada por `fetchAlerts` enquanto não for nula.
  Object? falhaDasBuscas;

  /// Acrescentados ao fim de `fetchAlerts` (um alerta "novo" visível na tela).
  final List<AlertSummary> extras = [];

  /// Quando não nulo, `endMonitoringSession` devolve este futuro (por exemplo,
  /// um que nunca completa, para provar que ninguém dá `await` nele).
  Future<void>? fimDaSessao;

  @override
  Future<AlertsPulse> alertsPulse() async {
    pulsos++;
    final falha = falhaDoPulso;
    if (falha != null) throw falha;
    final pendurado = pulsoPendurado;
    if (pendurado != null) return pendurado;
    // O pulso do mock monta os indicadores por `fetchDashboardIndicators`:
    // essa chamada interna (síncrona, antes do primeiro `await` do mock) não
    // conta como leitura da tela.
    _dentroDoPulso = true;
    final futuro = super.alertsPulse();
    _dentroDoPulso = false;
    final base = await futuro;
    return AlertsPulse(
      indicators: indicadores ?? base.indicators,
      overdueRed: overdueRed ?? base.overdueRed,
      maxChangedAt: maxChangedAt ?? base.maxChangedAt,
      serverNow: base.serverNow,
    );
  }

  @override
  Future<List<MicroAreaSummary>> fetchMicroAreas() {
    buscasDeMicroareas++;
    return super.fetchMicroAreas();
  }

  @override
  Future<DashboardIndicators> fetchDashboardIndicators() {
    if (!_dentroDoPulso) buscasDeIndicadores++;
    return super.fetchDashboardIndicators();
  }

  @override
  Future<List<AlertSummary>> fetchAlerts({
    String? microAreaId,
    AlertStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    buscasDeAlertas++;
    final falha = falhaDasBuscas;
    if (falha != null) throw falha;
    final lista = await super.fetchAlerts(microAreaId: microAreaId, status: status, limit: limit, offset: offset);
    return [...lista, ...extras];
  }

  @override
  Future<void> endMonitoringSession() {
    final fim = fimDaSessao;
    if (fim == null) return super.endMonitoringSession();
    monitoringSessionEnds++;
    return fim;
  }
}
