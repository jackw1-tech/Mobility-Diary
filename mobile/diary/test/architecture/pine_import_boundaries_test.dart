import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presentation layers do not import network DTOs or services', () {
    final root = Directory('lib');
    final presentationRoots = [
      Directory('${root.path}/ui'),
      Directory('${root.path}/routers'),
      Directory('${root.path}/state_management'),
    ];

    final offenders = <String>[];
    for (final directory in presentationRoots) {
      if (!directory.existsSync()) continue;
      final files = directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final contents = file.readAsStringSync();
        if (contents.contains('package:diary/network/dto') ||
            contents.contains('package:diary/network/service')) {
          offenders.add(file.path);
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
