import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/network_chaos_simulator.dart';

void main() {
  test('deve simular latência e jitter determinísticos', () {
    const profile = NetworkChaosProfile(
      latencyMs: 250,
      jitterMs: 50,
      packetLossPercent: 0,
      partitioned: false,
      seed: 7,
    );

    final outcome = NetworkChaosSimulator.run(profile);

    expect(outcome.shouldRetry, isFalse);
    expect(outcome.delay.inMilliseconds, greaterThanOrEqualTo(250));
    expect(outcome.delay.inMilliseconds, lessThanOrEqualTo(300));
  });

  test('deve detectar perda de pacote e acionar retry', () {
    const profile = NetworkChaosProfile(
      latencyMs: 100,
      jitterMs: 0,
      packetLossPercent: 100,
      partitioned: false,
      seed: 1,
    );

    final outcome = NetworkChaosSimulator.run(profile);

    expect(outcome.shouldRetry, isTrue);
    expect(outcome.error, contains('packet loss'));
  });

  test('deve bloquear a rede em particionamento para falha graciosa', () {
    const profile = NetworkChaosProfile(
      latencyMs: 50,
      jitterMs: 10,
      packetLossPercent: 0,
      partitioned: true,
      seed: 9,
    );

    final outcome = NetworkChaosSimulator.run(profile);

    expect(outcome.shouldRetry, isTrue);
    expect(outcome.error, contains('partitioned'));
  });
}
