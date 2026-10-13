import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:widget_test_capture/widget_test_capture.dart';

void main() {
  late Directory output;
  setUp(() {
    output = Directory.systemTemp.createTempSync('wtc-test-');
  });
  tearDown(() {
    if (output.existsSync()) output.deleteSync(recursive: true);
  });

  testWidgets('captures multiple checkpoints and exact Finder bounds',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
      child: SizedBox(
          key: Key('target'),
          width: 40,
          height: 20,
          child: ColoredBox(color: Colors.red)),
    ))));
    final capture = TestCapture(tester,
        CaptureConfig(outputDirectory: output.path), 'Nested / café test');
    final first = await capture.png('first');
    final target =
        await capture.png('target', finder: find.byKey(const Key('target')));
    expect(first.existsSync(), isTrue);
    expect(target.existsSync(), isTrue);
    final bytes = first.readAsBytesSync();
    expect(bytes, isNotNull);
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final targetImage = img.decodePng(target.readAsBytesSync());
    expect(targetImage, isNotNull);
    expect(targetImage!.width, 40);
    expect(targetImage.height, 20);
    expect(targetImage.getPixel(1, 1).r, greaterThan(200));
    expect(first.uri.pathSegments.last, 'Nested_café_test_1.png');
    expect(target.uri.pathSegments.last, 'Nested_café_test_2.png');
    expect(
      p.basename(first.parent.path),
      matches(RegExp(r'^Nested_café_test_\d{12}$')),
    );
    expect(Directory('${output.path}/manifests').listSync(), isNotEmpty);
  });

  testWidgets('captures the full logical view at a device pixel ratio above 1',
      (tester) async {
    final oldPhysicalSize = tester.view.physicalSize;
    final oldPixelRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = oldPhysicalSize;
      tester.view.devicePixelRatio = oldPixelRatio;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 3;

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SizedBox(
            width: 40,
            height: 20,
            child: ColoredBox(color: Colors.red),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final file = await TestCapture(
      tester,
      CaptureConfig(outputDirectory: output.path),
      'high dpr view',
    ).png('whole-view');
    final image = img.decodePng(file.readAsBytesSync())!;
    expect(image.width, 400);
    expect(image.height, 300);
    expect(image.getPixel(200, 150).r, greaterThan(200));
    expect(image.getPixel(200, 150).g, lessThan(100));
    expect(image.getPixel(10, 10).g, greaterThan(200));
  });

  testWidgets('rejects missing and ambiguous screenshot targets',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Column(children: [Text('same'), Text('same')])));
    final capture = TestCapture(tester,
        CaptureConfig(outputDirectory: output.path), 'target validation');
    await expectLater(
        capture.png('missing', finder: find.text('absent')), throwsStateError);
    await expectLater(
        capture.png('ambiguous', finder: find.text('same')), throwsStateError);
  });

  testWidgets('records simulated animation frames with bounded count',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: SizedBox(width: 100, height: 100)));
    final capture = TestCapture(
        tester, CaptureConfig(outputDirectory: output.path), 'animation');
    final frames = await capture.recordAnimation('movement',
        duration: const Duration(milliseconds: 400), fps: 10);
    expect(frames, hasLength(4));
    expect(frames.every((file) => file.existsSync()), isTrue);
    final manifest =
        Directory('${output.path}/manifests').listSync().single as File;
    final timestamps = manifest
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .map((item) => item['simulatedTimestampMicros'])
        .whereType<int>()
        .toList();
    expect(timestamps, [100000, 200000, 300000, 400000]);
  });

  testWidgets('restores simulated device view settings at teardown',
      (tester) async {
    final oldSize = tester.view.physicalSize;
    final oldRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      expect(tester.view.physicalSize, oldSize);
      expect(tester.view.devicePixelRatio, oldRatio);
    });
    await withCaptureDevice(tester,
        const CaptureDevice(name: 'small', size: Size(320, 640), pixelRatio: 2),
        () async {
      expect(tester.view.physicalSize, const Size(640, 1280));
      expect(tester.view.devicePixelRatio, 2);
    });
  });
}
