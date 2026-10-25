/// Valida o id de dono: vazio ou só espaços é erro de programação (sem dono, a
/// visita cairia na quarentena ou numa visão compartilhada).
///
/// Arquivo próprio, em Dart puro, para a telemetria usá-lo sem puxar a fila de
/// visitas (que importa o gravador e, por ele, o `connectivity_plus`): o
/// `backend_client.dart` importa o envio da telemetria e roda na VM.
String requireOwnerId(String ownerId) {
  if (ownerId.trim().isEmpty) {
    throw ArgumentError.value(ownerId, 'ownerId', 'não pode ser vazio');
  }
  return ownerId;
}
