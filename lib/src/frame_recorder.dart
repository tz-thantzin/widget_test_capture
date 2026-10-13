import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// GIF export options. GIF delays have a 10 ms unit; values are rounded.
class GifOptions {
  const GifOptions({
    this.loopCount = 0,
    this.frameDelay = const Duration(milliseconds: 100),
    this.background = 0xffffffff,
    this.paletteColors = 256,
  });

  /// Zero repeats forever; positive values are repeat counts.
  final int loopCount;
  final Duration frameDelay;

  /// ARGB canvas fill. GIF has binary transparency only; this exporter flattens it.
  final int background;

  /// GIF palette size, from 2 to 256 colors.
  final int paletteColors;
}

/// Encodes PNG frames into an animated GIF using a common canvas.
/// The canvas uses the largest frame dimensions. Smaller frames start at the
/// top-left; the configured background fills the remaining area.
Future<File> encodeGif(
  List<File> frames,
  File output, {
  GifOptions options = const GifOptions(),
}) async {
  if (frames.isEmpty) throw ArgumentError('At least one frame is required.');
  if (options.loopCount < 0 ||
      options.frameDelay <= Duration.zero ||
      options.paletteColors < 2 ||
      options.paletteColors > 256)
    throw ArgumentError('Loop and delay values must be valid.');
  var width = 0;
  var height = 0;
  for (final file in frames) {
    final source = img.decodeImage(file.readAsBytesSync());
    if (source == null)
      throw FormatException('Could not decode PNG frame: ${file.path}');
    if (source.width > width) width = source.width;
    if (source.height > height) height = source.height;
  }
  final encoder = img.GifEncoder(
      repeat: options.loopCount, numColors: options.paletteColors);
  final delayCentiseconds =
      (options.frameDelay.inMilliseconds / 10).round().clamp(1, 65535);
  // Decode and submit one image at a time to keep peak memory bounded by a few frames.
  for (final file in frames) {
    final frame = img.decodeImage(file.readAsBytesSync());
    if (frame == null)
      throw FormatException('Could not decode PNG frame: ${file.path}');
    final canvas = img.Image(width: width, height: height);
    final color = options.background;
    img.fill(canvas,
        color: img.ColorUint8.rgba(
            (color >> 16) & 0xff, (color >> 8) & 0xff, color & 0xff, 255));
    img.compositeImage(canvas, frame, dstX: 0, dstY: 0);
    encoder.addFrame(canvas, duration: delayCentiseconds);
  }
  final bytes = encoder.finish();
  if (bytes == null) throw StateError('GIF encoder did not produce output.');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(bytes, flush: true);
  File('${output.path}.wtc-owner')
      .writeAsStringSync('widget_test_capture:media:v1\n', flush: true);
  return output;
}

/// Creates a storyboard GIF from named screenshot files.
Future<File> encodeStoryboard(
  List<File> checkpoints,
  String outputPath, {
  GifOptions options = const GifOptions(),
}) =>
    encodeGif(checkpoints, File(p.absolute(outputPath)), options: options);

/// Encodes deterministic animation frames with one GIF delay derived from FPS.
Future<File> encodeAnimationGif(
  List<File> frames,
  File output, {
  required int fps,
  int loopCount = 0,
  int paletteColors = 256,
  int background = 0xffffffff,
}) {
  if (fps <= 0) throw ArgumentError.value(fps, 'fps', 'Must be positive.');
  final delay = Duration(microseconds: Duration.microsecondsPerSecond ~/ fps);
  return encodeGif(frames, output,
      options: GifOptions(
          loopCount: loopCount,
          frameDelay: delay,
          paletteColors: paletteColors,
          background: background));
}
