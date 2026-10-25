import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/telemetry/connectivity_network_probe.dart';
import 'package:sinalacs_acs/core/telemetry/network_probe.dart';

class _BrokenConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => throw StateError('sem plugin');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('connectivityProbe com fonte lançando devolve unknown', () async {
    expect(await connectivityProbe(_BrokenConnectivity())(), NetworkKind.unknown);
  });

  group('networkKindOf', () {
    test('mapeamento e prioridade', () {
      expect(networkKindOf([]), NetworkKind.none);
      expect(networkKindOf([ConnectivityResult.none]), NetworkKind.none);
      expect(networkKindOf([ConnectivityResult.mobile, ConnectivityResult.wifi]), NetworkKind.wifi);
      expect(networkKindOf([ConnectivityResult.vpn, ConnectivityResult.mobile]), NetworkKind.mobile);
      expect(networkKindOf([ConnectivityResult.ethernet, ConnectivityResult.mobile]), NetworkKind.ethernet);
      expect(networkKindOf([ConnectivityResult.vpn]), NetworkKind.vpn);
      expect(networkKindOf([ConnectivityResult.bluetooth]), NetworkKind.other);
      expect(networkKindOf([ConnectivityResult.other, ConnectivityResult.none]), NetworkKind.other);
    });
  });
}
