import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';

/// O broker não tem mais senha para o ACS nem certificado compartilhado no
/// binário (#94): o aparelho se autentica pelo certificado que o backend
/// emite para ele. Os casos da emissão estão em
/// `alert_feed_enrollment_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('não existem mais as falhas de senha nem de certificado compartilhado', () {
    expect(
      AlertFeedFailureKind.values.map((k) => k.name),
      unorderedEquals(['missingCaAsset', 'certificateUnavailable', 'refused', 'unreachable']),
    );
  });

  test('sem id da instalação o feed falha na hora, sem socket e sem nova tentativa', () async {
    final feed = UnconfiguredAlertFeed();

    await expectLater(
      feed.start(microAreaId: 'micro-area', acsId: 'acs'),
      throwsA(isA<AlertFeedFailure>()
          .having((f) => f.kind, 'kind', AlertFeedFailureKind.certificateUnavailable)
          .having((f) => f.transient, 'transient', isFalse)),
    );
    expect(feed.isConnected, isFalse);
  });
}
