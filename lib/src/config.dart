import 'dart:ui';

/// Settings for artifacts created by a widget test.
class CaptureConfig {
  const CaptureConfig({
    this.outputDirectory = 'assets/widget_test',
    this.captureAtEnd = false,
    this.captureOnFailure = false,
    this.pixelRatio = 1,
    this.backgroundColor,
    this.maxAnimationFrames = 300,
    this.maxAnimationDimension = 2048,
    this.metadata = const <String, Object?>{},
  })  : assert(pixelRatio > 0),
        assert(maxAnimationFrames > 0),
        assert(maxAnimationDimension > 0);

  /// Relative to the Flutter test process working directory (the project root).
  final String outputDirectory;
  final bool captureAtEnd;
  final bool captureOnFailure;
  final double pixelRatio;
  final Color? backgroundColor;
  final int maxAnimationFrames;
  final int maxAnimationDimension;

  /// Optional device, theme, locale, and scenario labels for the manifest.
  final Map<String, Object?> metadata;
}
