import 'package:integration_test/integration_test_driver.dart';

/// Driver do `flutter drive`, usado por `scripts/qa/acs_gps_e2e.sh` (só ele
/// aceita `--use-application-binary`, preciso para manter a permissão de
/// localização concedida por `pm grant`).
Future<void> main() => integrationDriver();
