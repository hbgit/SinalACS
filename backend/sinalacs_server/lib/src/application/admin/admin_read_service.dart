import 'package:sinalacs_server/src/generated/protocol.dart';

/// Até onde o chamador enxerga no backoffice (PRD §4.2.2): o administrador vê o
/// sistema inteiro; o coordenador, só a sua UBS.
class AdminScope {
  const AdminScope.system() : ubsId = null;
  const AdminScope.ubs(String this.ubsId);

  /// `null` = sistema inteiro.
  final String? ubsId;
}

/// Leitura do backoffice. Interface à parte do ORM, no espírito de
/// `AlertStore`: o serviço e seus testes não conhecem SQL.
abstract interface class AdminReadStore {
  /// Contagens por risco e TMRAV no escopo. O TMRAV olha os 30 dias anteriores
  /// a [now]; sem alerta vermelho reconhecido na janela, `tmravSeconds` é nulo.
  Future<AdminIndicators> indicators(AdminScope scope, {required DateTime now});

  Future<List<AdminMicroArea>> microAreas(AdminScope scope);

  /// Mais recentes primeiro (`triggeredAt` desc, `id` desc: ordem estável).
  /// `nextOffset` nulo = fim da lista.
  Future<AdminAlertPage> alerts(
    AdminScope scope, {
    String? microAreaId,
    AlertStatus? status,
    required int limit,
    required int offset,
  });

  /// Mais recentes primeiro, por keyset (`sequence` menor que [beforeSequence]).
  Future<AdminAuditPage> auditLogs({required int limit, int? beforeSequence});

  /// UBS do coordenador (`staff_accounts.ubsId`), ou `null` se não houver.
  Future<String?> ubsOf(String staffId);
}
