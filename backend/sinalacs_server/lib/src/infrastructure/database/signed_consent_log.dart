import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show ConsentLogEntry;
import 'package:sinalacs_server/src/generated/protocol.dart';

/// A linha de `consent_logs` de [entry], assinada por [signature].
///
/// Há dois escritores de consentimento — a conclusão do onboarding e o painel
/// "Meus Dados" (LGPD-RF05) — e os dois gravam a mesma forma de linha. Esta
/// função é o único lugar que a define, para que a assinatura e os campos não
/// divirjam entre eles.
///
/// IP e user agent não se aplicam a nenhum dos dois eventos de domínio — o
/// request HTTP em si já é auditado em `audit_logs` por outros caminhos —, então
/// os campos exigidos pelo schema levam um marcador explícito de ausência com a
/// [origin] do evento, não um valor fabricado.
ConsentLog signedConsentLog(
  ConsentLogEntry entry, {
  required ConsentSignature signature,
  required String origin,
}) {
  final marker = 'nao-aplicavel-$origin';
  return ConsentLog(
    userId: UuidValue.fromString(entry.userId),
    purpose: entry.purpose.name,
    action: entry.action,
    version: entry.version,
    timestamp: entry.timestamp,
    ipHash: marker,
    userAgent: marker,
    signature: signature.compute(
      userId: entry.userId,
      purpose: entry.purpose.name,
      action: entry.action,
      version: entry.version,
      timestamp: entry.timestamp,
    ),
  );
}
