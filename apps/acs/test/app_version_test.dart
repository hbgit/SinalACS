import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/telemetry/app_version.dart';

void main() {
  test('acsAppVersion igual ao pubspec', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final v = line.substring('version:'.length).trim().split('+').first;
    expect(acsAppVersion, v);
  });
}
