import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

enum GoldenMode { export, compare, update }

/// Compares a captured PNG with Flutter's approved golden baseline.
Future<void> expectCaptureMatchesGolden(
  WidgetTester tester,
  String name, {
  GoldenMode mode = GoldenMode.compare,
  String outputDirectory = 'assets/widget_test/goldens',
}) async {
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  final path = p.join(outputDirectory, '$safe.png');
  final absolutePath = p.absolute(path);
  final comparator = goldenFileComparator;
  final comparisonPath = comparator is LocalFileComparator
      ? p.relative(absolutePath, from: p.fromUri(comparator.basedir))
      : path;
  if (mode == GoldenMode.export) {
    final candidates = find.byType(RepaintBoundary).evaluate().toList();
    if (candidates.length != 1)
      throw StateError(
        'Golden export needs exactly one RepaintBoundary; found ${candidates.length}.',
      );
    final render = candidates.single.renderObject;
    if (render is! RenderRepaintBoundary)
      throw StateError('Golden export target is not a repaint boundary.');
    await tester.pump();
    final image = await tester.runAsync(() => render.toImage());
    if (image == null) throw StateError('Could not capture golden image.');
    final file = File(absolutePath);
    try {
      final data = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      );
      if (data == null) throw StateError('Could not encode golden as PNG.');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
    return;
  }
  if (mode == GoldenMode.update) {
    // matchesGoldenFile honors Flutter's --update-goldens flag.
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile(comparisonPath),
    );
    return;
  }
  // Flutter only updates baselines when --update-goldens is explicitly passed.
  await expectLater(
    find.byType(RepaintBoundary).first,
    matchesGoldenFile(comparisonPath),
  );
}
