import 'dart:io';

/// Um evento de acesso a dado sensível, pronto para a trilha.
///
/// Não é o `AuditLog` gerado: este é o formato que os serviços de aplicação
/// conhecem, sem acoplar `application/` ao ORM.
class AuditEvent {
  const AuditEvent({
    required this.userId,
    required this.actionType,
    required this.resourceType,
    required this.result,
    this.resourceId,
  });

  final String userId;

  /// `read` ou `write` — o que a §132 de spec/lgpd_design.md chama de "quais
  /// dados".
  final String actionType;

  final String resourceType;

  /// De propósito opcional: uma leitura de LISTA (ex.: o diretório de
  /// pacientes da microárea) não enumera cada paciente aqui — fazer isso
  /// recriaria o prontuário dentro do próprio log de auditoria. Só eventos
  /// sobre UM recurso específico (uma recusa de sincronização, por exemplo)
  /// preenchem este campo.
  final String? resourceId;

  /// `granted`, `denied_territory`, etc. — nunca contém dado do paciente.
  final String result;
}

/// Trilha de auditoria de acesso a dados sensíveis (append-only).
///
/// `audit_logs` existe desde a migração-base e, até este serviço, não tinha
/// escritor nenhum — a spec de LGPD promete "logs de acesso com quem, quando e
/// quais dados" (§132) e "alerta para auditoria" quando um ACS tenta um
/// paciente fora da própria microárea (§404), e nada gravava para cumprir isso.
///
/// Uma `abstract class` comum, não `abstract interface class`: as outras
/// interfaces deste `application/` (`AlertStore`, `VisitStore`) são puras de
/// propósito, mas aqui o `recordSafely` precisa ser herdado por TODO
/// implementador — inclusive o fake de teste que simula falha — em vez de
/// reescrito em cada um.
abstract class AuditTrail {
  Future<void> record(AuditEvent event);

  /// Registra sem propagar falha: uma trilha de auditoria fora do ar não pode
  /// impedir o ACS de listar pacientes ou de ter sua visita recusada por
  /// território — mas a falha não pode desaparecer, então vai para o log do
  /// processo.
  Future<void> recordSafely(AuditEvent event) async {
    try {
      await record(event);
    } catch (error) {
      stderr.writeln(
        'Falha ao gravar auditoria (${event.actionType}/${event.resourceType}): $error.',
      );
    }
  }
}
