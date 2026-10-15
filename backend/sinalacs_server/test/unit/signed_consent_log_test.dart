import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/signed_consent_log.dart';
import 'package:test/test.dart';

void main() {
  final signature = ConsentSignature(secret: 'segredo-de-teste');
  final entry = ConsentLogEntry(
    userId: '00000000-0000-4000-8000-000000000001',
    purpose: ConsentPurpose.localReminders,
    action: 'denied',
    version: '2026.1',
    timestamp: DateTime.utc(2026, 9, 28, 12),
  );

  test('assina exatamente os campos que ConsentSignature.compute recebe', () {
    final row = signedConsentLog(entry, signature: signature, origin: 'painel-titular');

    expect(
      row.signature,
      signature.compute(
        userId: entry.userId,
        purpose: 'localReminders',
        action: 'denied',
        version: '2026.1',
        timestamp: entry.timestamp,
      ),
    );
    expect(row.userId.uuid, entry.userId);
    expect(row.purpose, 'localReminders');
    expect(row.action, 'denied');
    expect(row.version, '2026.1');
    expect(row.timestamp, entry.timestamp);
  });

  test('ipHash e userAgent levam o marcador de ausência com a origem do evento', () {
    final onboarding = signedConsentLog(entry, signature: signature, origin: 'onboarding');
    expect(onboarding.ipHash, 'nao-aplicavel-onboarding');
    expect(onboarding.userAgent, 'nao-aplicavel-onboarding');

    final painel = signedConsentLog(entry, signature: signature, origin: 'painel-titular');
    expect(painel.ipHash, 'nao-aplicavel-painel-titular');
  });
}
