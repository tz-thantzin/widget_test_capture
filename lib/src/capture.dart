import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'config.dart';

/// State and helpers available inside [captureTest].
class TestCapture {
  TestCapture(this.tester, this.config, this.testName);

  final WidgetTester tester;
  final CaptureConfig config;
  final String testName;
  final List<CapturedFrame> _frames = [];
  final String _testRunId = _newCaptureTimestamp();
  int _artifactNumber = 0;

  /// Captures the whole Flutter view or the bounds of exactly one [finder].
  Future<File> png(String? name,
      {Finder? finder,
      Rect? bounds,
      double? pixelRatio,
      Duration? simulatedTime}) async {
    if (finder != null && bounds != null) {
      throw ArgumentError('Choose a Finder or explicit bounds, not both.');
    }
    Rect rect;
    final view = tester.view;
    if (finder != null) {
      final matches = finder.evaluate().toList();
      if (matches.length != 1) {
        throw StateError(
          'Screenshot target matched ${matches.length} widgets. '
          'Use a Finder that matches exactly one widget.',
        );
      }
      final element = matches.single;
      final render = element.renderObject;
      if (render is! RenderBox || !render.hasSize) {
        throw StateError('Screenshot target has no laid out RenderBox.');
      }
      rect = MatrixUtils.transformRect(
        render.getTransformTo(null),
        render.paintBounds,
      );
    } else {
      rect = bounds ??
          Rect.fromLTWH(
            0,
            0,
            view.physicalSize.width / view.devicePixelRatio,
            view.physicalSize.height / view.devicePixelRatio,
          );
    }
    if (rect.isEmpty || !rect.isFinite)
      throw StateError('Screenshot bounds are empty or invalid: $rect');

    final root = tester.binding.renderViews.single;
    // ignore: invalid_use_of_protected_member
    final layer = root.layer;
    if (layer is! OffsetLayer) {
      throw StateError(
        'The Flutter view has no paint layer. Pump the widget and ensure it has painted.',
      );
    }
    final ratio = pixelRatio ?? config.pixelRatio;
    if (ratio <= 0)
      throw ArgumentError.value(ratio, 'pixelRatio', 'Must be positive.');
    final viewBounds = Rect.fromLTWH(0, 0, root.size.width, root.size.height);
    final clipped = rect.intersect(viewBounds);
    if (clipped.isEmpty) {
      throw StateError('Screenshot bounds are outside the Flutter view: $rect');
    }
    // Crop Finder bounds from PNG bytes. A second engine scene can stall in
    // Flutter's fake-async test binding.
    // RenderView's root layer is already scaled into physical coordinates.
    // Capture its physical bounds, then scale by the requested logical pixel
    // ratio divided by DPR so the output size stays logicalSize * pixelRatio.
    final devicePixelRatio = view.devicePixelRatio;
    final physicalViewBounds = Rect.fromLTWH(
      0,
      0,
      viewBounds.width * devicePixelRatio,
      viewBounds.height * devicePixelRatio,
    );
    final layerPixelRatio = ratio / devicePixelRatio;
    final rawImage = await tester.runAsync(
      () => layer.toImage(physicalViewBounds, pixelRatio: layerPixelRatio),
    );
    if (rawImage == null)
      throw StateError('Flutter did not return a screenshot image.');
    ui.Image image = rawImage;
    try {
      if (config.backgroundColor != null) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
          ..drawColor(config.backgroundColor!, ui.BlendMode.src)
          ..drawImage(rawImage, ui.Offset.zero, ui.Paint());
        image = await recorder
            .endRecording()
            .toImage(rawImage.width, rawImage.height);
      }
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      );
      if (bytes == null)
        throw StateError('Could not encode screenshot as PNG.');
      var pngBytes = bytes.buffer.asUint8List();
      if (clipped != viewBounds) {
        final decoded = img.decodePng(pngBytes);
        if (decoded == null) throw StateError('Could not crop screenshot PNG.');
        final left = (clipped.left * ratio).floor().clamp(0, decoded.width - 1);
        final top = (clipped.top * ratio).floor().clamp(0, decoded.height - 1);
        final right =
            (clipped.right * ratio).ceil().clamp(left + 1, decoded.width);
        final bottom =
            (clipped.bottom * ratio).ceil().clamp(top + 1, decoded.height);
        pngBytes = img.encodePng(img.copyCrop(decoded,
            x: left, y: top, width: right - left, height: bottom - top));
      }
      final width =
          clipped == viewBounds ? image.width : (clipped.width * ratio).ceil();
      final height = clipped == viewBounds
          ? image.height
          : (clipped.height * ratio).ceil();
      final checkpointName = name ?? 'checkpoint';
      final file = _writeArtifact(
        checkpointName,
        pngBytes,
        width,
        height,
        simulatedTime: simulatedTime,
      );
      _frames.add(
        CapturedFrame(file, DateTime.now().toUtc(), width, height),
      );
      return file;
    } finally {
      if (!identical(image, rawImage)) image.dispose();
      rawImage.dispose();
    }
  }

  /// Captures a checkpoint with an automatically assigned name.
  Future<File> pngAuto({Finder? finder, Rect? bounds}) =>
      png(null, finder: finder, bounds: bounds);

  File _writeArtifact(
    String name,
    List<int> bytes,
    int width,
    int height, {
    Duration? simulatedTime,
  }) {
    final root = Directory(p.absolute(config.outputDirectory));
    final id = _newCaptureId();
    final folder = Directory(
      p.join(root.path, 'screenshots', '${safeName(testName)}_$_testRunId'),
    );
    folder.createSync(recursive: true);
    final number = ++_artifactNumber;
    final file = File(p.join(
      folder.path,
      '${safeName(testName)}_$number.png',
    ));
    final temporary = File('${file.path}.tmp');
    temporary.writeAsBytesSync(bytes, flush: true);
    temporary.renameSync(file.path);
    _appendManifest(root, <String, Object?>{
      'schemaVersion': 1,
      'artifactId': id,
      'testName': testName,
      'kind': 'screenshot',
      'name': name,
      'path': p.relative(file.path, from: root.path).replaceAll('\\', '/'),
      'width': width,
      'height': height,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'simulatedTimestampMicros': simulatedTime?.inMicroseconds,
      'metadata': config.metadata,
    });
    return file;
  }

  Future<void> step(String name, Future<void> Function() action) async {
    _writeEvent(name, 'before');
    await png('${name}_before');
    await action();
    await png('${name}_after');
    _writeEvent(name, 'after');
  }

  void _writeEvent(String name, String phase) {
    final root = Directory(p.absolute(config.outputDirectory));
    _appendManifest(root, <String, Object?>{
      'schemaVersion': 1,
      'testName': testName,
      'kind': 'interaction',
      'name': name,
      'phase': phase,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'metadata': config.metadata,
    });
  }

  /// Runs a deterministic, simulated-time frame sequence. Frames are PNG files.
  Future<List<File>> recordAnimation(
    String name, {
    required Duration duration,
    int fps = 15,
    Finder? finder,
    bool Function()? cancel,
  }) async {
    if (duration <= Duration.zero || fps <= 0)
      throw ArgumentError('Duration and fps must be positive.');
    final count =
        (duration.inMicroseconds * fps / Duration.microsecondsPerSecond).ceil();
    if (count > config.maxAnimationFrames) {
      throw StateError(
        'Animation needs $count frames; limit is ${config.maxAnimationFrames}.',
      );
    }
    final result = <File>[];
    for (var i = 0; i < count; i++) {
      if (cancel?.call() ?? false) break;
      final micros = ((i + 1) * Duration.microsecondsPerSecond / fps).round();
      await tester.pump(
        Duration(
          microseconds: min(micros, duration.inMicroseconds) -
              (i == 0
                  ? 0
                  : ((i) * Duration.microsecondsPerSecond / fps).round()),
        ),
      );
      final timestamp =
          Duration(microseconds: min(micros, duration.inMicroseconds));
      final logicalSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final frameRatio = min(
          config.pixelRatio,
          config.maxAnimationDimension /
              max(logicalSize.width, logicalSize.height));
      result.add(
        await png(
          '${name}_${(i + 1).toString().padLeft(4, '0')}',
          finder: finder,
          pixelRatio: frameRatio,
          simulatedTime: timestamp,
        ),
      );
    }
    return result;
  }
}

String _newCaptureId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32).toRadixString(16)}';

String _newCaptureTimestamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}'
      '${two(now.hour)}${two(now.minute)}';
}

/// Registers a widget test with opt-in capture around the callback.
void captureTest(
  String description,
  Future<void> Function(WidgetTester, TestCapture) callback, {
  CaptureConfig config = const CaptureConfig(),
  bool skip = false,
  Timeout? timeout,
  TestVariant<Object?>? variant,
}) {
  testWidgets(
    description,
    (tester) async {
      final capture = TestCapture(tester, config, description);
      Object? originalError;
      try {
        await callback(tester, capture);
      } catch (error, stack) {
        originalError = error;
        if (config.captureOnFailure) {
          try {
            await capture.png('failure');
          } catch (_) {
            /* Preserve the test failure. */
          }
        }
        Error.throwWithStackTrace(error, stack);
      } finally {
        if (originalError == null && config.captureAtEnd)
          await capture.png('final');
      }
    },
    skip: skip,
    timeout: timeout,
    variant: variant ?? const DefaultTestVariant(),
  );
}

String safeName(String input) {
  var cleaned = input
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'[ .]+$'), '');
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') cleaned = 'capture';
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$', caseSensitive: false)
      .hasMatch(cleaned)) {
    cleaned = '_$cleaned';
  }
  return String.fromCharCodes(
      cleaned.runes.take(min(cleaned.runes.length, 100)));
}

void _appendManifest(Directory root, Map<String, Object?> item) {
  // One append-only JSONL file per isolate avoids shared JSON read-modify-write races.
  final dir = Directory(p.join(root.path, 'manifests'));
  final file = File(
    p.join(dir.path, 'capture_${pid}_${Isolate.current.hashCode}.jsonl'),
  );
  dir.createSync(recursive: true);
  file.writeAsStringSync('${jsonEncode(item)}\n',
      mode: FileMode.append, flush: true);
}

class CapturedFrame {
  const CapturedFrame(this.file, this.capturedAt, this.width, this.height);
  final File file;
  final DateTime capturedAt;
  final int width;
  final int height;
}
