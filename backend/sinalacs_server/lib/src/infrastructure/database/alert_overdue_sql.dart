/// A regra única de "alerta vencido" (#44) em SQL, compartilhada pela leitura
/// do backoffice (`AdminAlert.overdue` e `AdminAlertsPulse.overdueRed`, em
/// `OrmAdminReadStore`) e pelo escalonamento (`OrmAlertEscalationStore`).
///
/// Os fragmentos supõem o alias `a` para `alerts` e os parâmetros nomeados
/// `@now` (o relógio do servidor) e `@limite` (o prazo em microssegundos,
/// `Duration.inMicroseconds`). A concordância entre os três usos é pinada por
/// test/integration/admin_read_store_test.dart ('acordo: …').
library;

/// Prazo vencido: `now − triggeredAt > limite`, **estritamente** e em
/// microssegundos; `triggeredAt` no futuro dá intervalo negativo e nunca vence.
/// O escalonamento usa só este pedaço, porque decide risco, status e
/// escalonamento anterior em Dart, com precedência própria.
const alertDeadlinePassedSql =
    '''(@now::timestamp - a."triggeredAt") > (@limite::bigint * interval '1 microsecond')''';

/// Vencido para a leitura: só o vermelho pendente ainda não escalonado, com o
/// prazo vencido. Escalonar tira o alerta daqui (mas não da lista nem do
/// filtro `pending`, D3).
const alertOverdueSql =
    '''(a."riskLevel" = 'red' AND a."status" = 'pending' AND a."escalatedAt" IS NULL AND $alertDeadlinePassedSql)''';
