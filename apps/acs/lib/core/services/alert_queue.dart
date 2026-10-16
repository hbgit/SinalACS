import 'package:flutter/foundation.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';

/// Um alerta na fila de priorização do ACS.
@immutable
class PrioritizedAlert {
  const PrioritizedAlert({
    required this.alertId,
    required this.patientId,
    required this.microAreaId,
    required this.riskLevel,
    required this.locationHash,
    this.locationCell,
    required this.triggeredAt,
    this.acknowledged = false,
    this.escalated = false,
    this.resolved = false,
  });

  factory PrioritizedAlert.fromMqtt(ReceivedMqttAlert alert) {
    return PrioritizedAlert(
      alertId: alert.alertId,
      patientId: alert.patientId,
      microAreaId: alert.microAreaId,
      riskLevel: alert.riskLevel,
      locationHash: alert.locationHash,
      locationCell: alert.locationCell,
      triggeredAt: alert.triggeredAt,
      escalated: alert.escalated,
    );
  }

  final String alertId;
  final String patientId;
  final String microAreaId;

  /// Como veio no envelope do servidor (`red` / `yellow` / `green`).
  final String riskLevel;

  final String locationHash;

  /// Célula de baixa resolução do alerta, ou `null` quando o dispositivo do
  /// paciente não conseguiu GPS. É a única fonte de posição para o mapa do
  /// ACS — nada deriva coordenada de [locationHash].
  final String? locationCell;
  final DateTime triggeredAt;
  final bool acknowledged;

  /// O backoffice reforçou este alerta (#44). Só existe em memória: não é
  /// gravado no aparelho nem carrega quem escalonou.
  final bool escalated;

  /// O ACS concluiu o atendimento (#76). Implica [acknowledged].
  final bool resolved;

  PrioritizedAlert copyWith({bool? acknowledged, bool? escalated, bool? resolved}) => PrioritizedAlert(
        alertId: alertId,
        patientId: patientId,
        microAreaId: microAreaId,
        riskLevel: riskLevel,
        locationHash: locationHash,
        locationCell: locationCell,
        triggeredAt: triggeredAt,
        acknowledged: acknowledged ?? this.acknowledged,
        escalated: escalated ?? this.escalated,
        resolved: resolved ?? this.resolved,
      );

  /// Peso da ordenação. Menor vem primeiro.
  ///
  /// Risco desconhecido cai para o fim, mas **não** é descartado: um envelope
  /// com risco que o app não reconhece ainda é um chamado que alguém precisa
  /// ver.
  int get _riskRank => switch (riskLevel.toLowerCase()) {
        'red' || 'vermelho' => 0,
        'yellow' || 'amarelo' => 1,
        'green' || 'verde' => 2,
        _ => 3,
      };
}

/// Fila de priorização alimentada pelos alertas que chegam do broker.
///
/// A ordenação é determinística: risco primeiro (vermelho > amarelo > verde) e,
/// dentro do mesmo risco, o mais antigo na frente — quem espera há mais tempo
/// não pode ser ultrapassado por um chamado novo de mesma gravidade.
class AlertQueue extends ChangeNotifier {
  AlertQueue({required this.microAreaId});

  /// Microárea da sessão. Delimita o território do ACS.
  final String microAreaId;

  final List<PrioritizedAlert> _alerts = <PrioritizedAlert>[];

  List<PrioritizedAlert> get alerts => List.unmodifiable(_alerts);

  bool get isEmpty => _alerts.isEmpty;

  /// Alertas que o ACS ainda não confirmou à central. Conta todos, qualquer
  /// risco: um risco desconhecido também é um chamado que alguém precisa ver.
  int get unacknowledgedCount => _alerts.where((a) => !a.acknowledged).length;

  /// Insere ou atualiza um alerta.
  ///
  /// Devolve `false` quando o alerta é recusado. São duas razões:
  ///
  /// - **outra microárea**: territorialização é invariante, e o broker já
  ///   restringe por ACL — esta é a segunda barreira, para o caso de o app ser
  ///   apontado a um tópico mais amplo;
  /// - **duplicata**: com QoS 1 a entrega é *at-least-once*, então a mesma
  ///   mensagem pode chegar mais de uma vez e não pode virar dois cartões.
  ///
  /// O `true` é o "sinal de alerta novo" deste app (não há som nem vibração
  /// próprios: o `ChangeNotifier` move a lista, o contador e o banner).
  ///
  /// **Reforço** (`escalated`, #44): para um alerta ainda não confirmado,
  /// marca o cartão, sobe-o à frente dos demais do mesmo risco e devolve
  /// `true` (mesmo sinal). Um reforço sobre alerta já confirmado devolve
  /// `false`, como qualquer reentrega: nunca desfaz a confirmação nem sinaliza.
  /// Idempotência do QoS 1: cartão já marcado `escalated` recebendo outro
  /// reforço é duplicata (`false`); o backend escalona cada alerta uma só
  /// vez, então o marcador basta. Uma reentrega do original (sem o marcador)
  /// não apaga o reforço.
  bool upsert(PrioritizedAlert alert) {
    if (alert.microAreaId != microAreaId) return false;

    final index = _alerts.indexWhere((item) => item.alertId == alert.alertId);
    if (index >= 0) {
      // Preserva a confirmação já registrada: uma reentrega não pode "desfazer"
      // um alerta que o ACS já atendeu.
      final existing = _alerts[index];
      if (existing.acknowledged) return false;
      if (alert.escalated && existing.escalated) return false;
      _alerts[index] = existing.escalated ? alert.copyWith(escalated: true) : alert;
    } else {
      _alerts.add(alert);
    }

    _sort();
    notifyListeners();
    return true;
  }

  /// Marca o alerta como confirmado. Devolve `false` se ele não está na fila.
  bool markAcknowledged(String alertId) {
    final index = _alerts.indexWhere((item) => item.alertId == alertId);
    if (index < 0) return false;

    _alerts[index] = _alerts[index].copyWith(acknowledged: true);
    _sort();
    notifyListeners();
    return true;
  }

  /// Marca o atendimento como concluído (e, por consequência, confirmado).
  /// Devolve `false` se o alerta não está na fila.
  bool markResolved(String alertId) {
    final index = _alerts.indexWhere((item) => item.alertId == alertId);
    if (index < 0) return false;

    _alerts[index] = _alerts[index].copyWith(acknowledged: true, resolved: true);
    _sort();
    notifyListeners();
    return true;
  }

  void _sort() {
    _alerts.sort((a, b) {
      // Confirmados descem, para não competir com quem ainda espera.
      if (a.acknowledged != b.acknowledged) return a.acknowledged ? 1 : -1;
      // Concluídos descem abaixo dos confirmados: já não pedem ação.
      if (a.resolved != b.resolved) return a.resolved ? 1 : -1;
      final byRisk = a._riskRank.compareTo(b._riskRank);
      if (byRisk != 0) return byRisk;
      // Reforço da coordenação vem à frente dos demais do mesmo risco.
      if (a.escalated != b.escalated) return a.escalated ? -1 : 1;
      return a.triggeredAt.compareTo(b.triggeredAt);
    });
  }
}
