import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:widget_test_capture/widget_test_capture.dart';

void main() {
  testWidgets('exports and compares a golden baseline', (tester) async {
    final directory = Directory.systemTemp.createTempSync('wtc-golden-');
    addTearDown(() => directory.deleteSync(recursive: true));

    await tester.pumpWidget(const RepaintBoundary(
        child: SizedBox(
            width: 24, height: 16, child: ColoredBox(color: Colors.red))));
    await expectCaptureMatchesGolden(tester, 'sample',
        mode: GoldenMode.export, outputDirectory: directory.path);
    await expectCaptureMatchesGolden(tester, 'sample',
        outputDirectory: directory.path);
    expect(File('${directory.path}/sample.png').existsSync(), isTrue);

    final blue = img.Image(width: 1, height: 1);
    img.fill(blue, color: img.ColorUint8.rgba(0, 0, 255, 255));
    final comparison = await tester.runAsync(() =>
        GoldenFileComparator.compareLists(
            File('${directory.path}/sample.png').readAsBytesSync(),
            img.encodePng(blue)));
    try {
      expect(comparison, isNotNull);
      expect(comparison!.passed, isFalse);
      expect(comparison.diffPercent, greaterThan(0));
      expect(comparison.diffs, isNotNull);
    } finally {
      comparison?.dispose();
      final failures = Directory('test/failures');
      if (failures.existsSync()) {
        for (final file in failures.listSync().whereType<File>()) {
          if (file.uri.pathSegments.last.startsWith('sample_')) {
            file.deleteSync();
          }
        }
        if (failures.listSync().isEmpty) failures.deleteSync();
      }
    }
  });
}
