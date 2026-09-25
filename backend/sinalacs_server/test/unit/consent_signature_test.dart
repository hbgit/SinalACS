import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:test/test.dart';

void main() {
  test('assinatura não é vazia', () {
    final signature = ConsentSignature(secret: 'test-audit-chain-secret');

    final value = signature.compute(
      userId: 'patient-001',
      purpose: 'healthDataProcessing',
      action: 'granted',
      version: '2026.1',
      timestamp: DateTime.utc(2026, 9, 17, 12),
    );

    expect(value, isNotEmpty);
  });

  test('duas gravações com dados diferentes produzem assinaturas diferentes', () {
    final signature = ConsentSignature(secret: 'test-audit-chain-secret');

    final first = signature.compute(
      userId: 'patient-001',
      purpose: 'healthDataProcessing',
      action: 'granted',
      version: '2026.1',
      timestamp: DateTime.utc(2026, 9, 17, 12),
    );
    final second = signature.compute(
      userId: 'patient-001',
      purpose: 'healthDataProcessing',
      action: 'denied',
      version: '2026.1',
      timestamp: DateTime.utc(2026, 9, 17, 12),
    );

    expect(first, isNot(equals(second)));
  });

  test('mesmos dados com segredos diferentes produzem assinaturas diferentes', () {
    final first = ConsentSignature(secret: 'secret-a').compute(
      userId: 'patient-001',
      purpose: 'healthDataProcessing',
      action: 'granted',
      version: '2026.1',
      timestamp: DateTime.utc(2026, 9, 17, 12),
    );
    final second = ConsentSignature(secret: 'secret-b').compute(
      userId: 'patient-001',
      purpose: 'healthDataProcessing',
      action: 'granted',
      version: '2026.1',
      timestamp: DateTime.utc(2026, 9, 17, 12),
    );

    expect(first, isNot(equals(second)));
  });

  test('mesmos dados e mesmo segredo produzem a mesma assinatura (determinística)', () {
    final signature = ConsentSignature(secret: 'test-audit-chain-secret');
    String compute() => signature.compute(
          userId: 'patient-001',
          purpose: 'healthDataProcessing',
          action: 'granted',
          version: '2026.1',
          timestamp: DateTime.utc(2026, 9, 17, 12),
        );

    expect(compute(), compute());
  });
}
