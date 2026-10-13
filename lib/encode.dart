/// Pure-Dart media encoders for use outside Flutter widget tests.
///
/// This entrypoint does not import `dart:ui` or Flutter libraries, so it can be
/// used by command-line tools that run after widget tests have finished.
export 'src/ffmpeg.dart';
export 'src/frame_recorder.dart';
