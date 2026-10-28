import 'package:sinalacs_server/src/generated/protocol.dart';

/// Em qual contador de `AdminIndicators` um alerta vermelho cai, pelo status
/// (#87). A partição é fechada: `red` é sempre `openRedAlerts +
/// acknowledgedRedAlerts + resolvedRedAlerts` (INV-03 — nenhum vermelho some
/// da coordenação). O `switch` de [of] é exaustivo: um valor novo de
/// [AlertStatus] não compila sem decidir em que contador entra.
enum RedAlertBucket {
  /// `openRedAlerts`: pendente, inclusive o legado `escalated` (nada o grava
  /// desde a #44, D3; um escalonado é um aberto sem confirmação).
  open,

  /// `acknowledgedRedAlerts`: em atendimento. Não cumulativo: o concluído sai.
  acknowledged,

  /// `resolvedRedAlerts`: atendimento concluído pelo ACS (#76).
  resolved;

  static RedAlertBucket of(AlertStatus status) => switch (status) {
    AlertStatus.pending || AlertStatus.escalated => RedAlertBucket.open,
    AlertStatus.acknowledged => RedAlertBucket.acknowledged,
    AlertStatus.resolved => RedAlertBucket.resolved,
  };

  /// Os status deste balde, na ordem de [AlertStatus.values].
  List<AlertStatus> get statuses => [
    for (final s in AlertStatus.values)
      if (of(s) == this) s,
  ];

  /// `'pending','escalated'`: a lista de um `IN (…)` de SQL. Só nomes de enum,
  /// nunca entrada do usuário — por isso pode entrar no texto da consulta.
  String get sqlList => statuses.map((s) => "'${s.name}'").join(',');
}
