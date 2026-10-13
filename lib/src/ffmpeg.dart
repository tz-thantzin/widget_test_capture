import 'dart:io';

import 'package:path/path.dart' as p;

class FfmpegException implements Exception {
  FfmpegException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Checks that FFmpeg is runnable and includes an H.264 video encoder.
Future<String> doctorFfmpeg({String? executable}) async {
  final bin = executable ?? 'ffmpeg';
  ProcessResult result;
  try {
    result = await Process.run(bin, ['-hide_banner', '-encoders']);
  } on ProcessException catch (error) {
    throw FfmpegException('Could not find or run $bin: ${error.message}');
  }
  if (result.exitCode != 0)
    throw FfmpegException('Could not run $bin: ${result.stderr}');
  final output = '${result.stdout}\n${result.stderr}';
  if (_availableH264Encoder(output) == null) {
    throw FfmpegException(
      '$bin is available, but no supported H.264 encoder was found. Install an FFmpeg build with an H.264 encoder.',
    );
  }
  return bin;
}

/// Encodes an ordered list of PNG frames as silent H.264 MP4.
Future<File> encodeMp4(
  List<File> frames,
  File output, {
  String? executable,
  int fps = 15,
  int? width,
  int? height,
  String paddingColor = 'black',
}) async {
  if (frames.isEmpty) throw ArgumentError('At least one frame is required.');
  if (fps <= 0) throw ArgumentError.value(fps, 'fps', 'Must be positive.');
  if ((width == null) != (height == null) ||
      (width != null && (width <= 0 || height! <= 0))) {
    throw ArgumentError('Set both output width and height to positive values.');
  }
  final bin = executable ?? await _findFfmpeg();
  ProcessResult probe;
  try {
    probe = await Process.run(bin, ['-hide_banner', '-encoders']);
  } on ProcessException catch (error) {
    throw FfmpegException(
        'Could not run FFmpeg at "$bin": ${error.message}. Captured frames were preserved.');
  }
  final encoder = _availableH264Encoder('${probe.stdout}\n${probe.stderr}');
  if (probe.exitCode != 0 || encoder == null) {
    throw FfmpegException(
      'FFmpeg has no supported H.264 encoder. Captured frames were preserved.',
    );
  }
  final parent = output.absolute.parent;
  parent.createSync(recursive: true);
  final concat = File(
    p.join(parent.path, '.${output.uri.pathSegments.last}.frames.txt'),
  );
  String quote(File file) =>
      "'${file.absolute.path.replaceAll('\\', '/').replaceAll("'", "'\\''")}'";
  concat.writeAsStringSync(
    frames.map((f) => "file ${quote(f)}\nduration ${1 / fps}").join('\n') +
        '\nfile ${quote(frames.last)}\n',
  );
  try {
    final evenWidth = width == null ? null : (width + 1) & ~1;
    final evenHeight = height == null ? null : (height + 1) & ~1;
    final scale = evenWidth != null && evenHeight != null
        ? 'scale=$evenWidth:$evenHeight:force_original_aspect_ratio=decrease,pad=$evenWidth:$evenHeight:(ow-iw)/2:(oh-ih)/2:$paddingColor'
        : 'pad=ceil(iw/2)*2:ceil(ih/2)*2:0:0:$paddingColor';
    final result = await Process.run(bin, [
      '-hide_banner',
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      concat.path,
      '-fps_mode',
      'vfr',
      '-vf',
      scale,
      '-an',
      '-c:v',
      encoder,
      '-pix_fmt',
      'yuv420p',
      output.absolute.path,
    ]);
    if (result.exitCode != 0)
      throw FfmpegException(
        'FFmpeg MP4 encoding failed (exit ${result.exitCode}):\n${result.stderr}',
      );
    File('${output.path}.wtc-owner')
        .writeAsStringSync('widget_test_capture:media:v1\n', flush: true);
    return output;
  } finally {
    if (concat.existsSync()) concat.deleteSync();
  }
}

String? _availableH264Encoder(String output) {
  final match = RegExp(
    r'^\s*V\S*\s+(libx264|h264_videotoolbox|h264_nvenc|h264_qsv|h264_amf)\b',
    multiLine: true,
  ).firstMatch(output);
  return match?.group(1);
}

Future<String> _findFfmpeg() async {
  try {
    return await doctorFfmpeg();
  } on ProcessException catch (_) {
    throw FfmpegException(
      'FFmpeg was not found on PATH. Install FFmpeg or pass executable: "/path/to/ffmpeg". Captured frames are preserved.',
    );
  }
}
