class NetworkChaosProfile {
  const NetworkChaosProfile({
    required this.latencyMs,
    required this.jitterMs,
    required this.packetLossPercent,
    required this.partitioned,
    required this.seed,
  });

  final int latencyMs;
  final int jitterMs;
  final int packetLossPercent;
  final bool partitioned;
  final int seed;
}

class NetworkChaosOutcome {
  const NetworkChaosOutcome({
    required this.delay,
    required this.shouldRetry,
    required this.error,
  });

  final Duration delay;
  final bool shouldRetry;
  final String error;
}

class NetworkChaosSimulator {
  const NetworkChaosSimulator();

  static NetworkChaosOutcome run(NetworkChaosProfile profile) {
    final effectiveDelay = profile.latencyMs + (profile.seed % (profile.jitterMs + 1));

    if (profile.partitioned) {
      return NetworkChaosOutcome(
        delay: Duration(milliseconds: effectiveDelay),
        shouldRetry: true,
        error: 'partitioned network: simulated outage',
      );
    }

    if (profile.packetLossPercent >= 100) {
      return NetworkChaosOutcome(
        delay: Duration(milliseconds: effectiveDelay),
        shouldRetry: true,
        error: 'packet loss detected; retry scheduled',
      );
    }

    return NetworkChaosOutcome(
      delay: Duration(milliseconds: effectiveDelay),
      shouldRetry: false,
      error: 'healthy transport',
    );
  }
}
