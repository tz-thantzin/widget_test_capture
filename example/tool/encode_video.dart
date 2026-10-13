import 'dart:io';

import 'package:widget_test_capture/encode.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/encode_video.dart');
    stderr.writeln(
      'Run `flutter test` first. The tool converts panel animation frames '
      'into build/widget_test_capture/videos/panel_animation_1.mp4.',
    );
    exitCode = 64;
    return;
  }

  final screenshots = Directory('build/widget_test_capture/screenshots');
  final frameDirectories = screenshots.existsSync()
      ? screenshots
          .listSync()
          .whereType<Directory>()
          .where((directory) => directory.uri.pathSegments
              .any((part) => part.startsWith('panel_animation_')))
          .toList()
      : <Directory>[];
  if (frameDirectories.isEmpty) {
    stderr
        .writeln('Animation frames were not found. Run `flutter test` first.');
    exitCode = 1;
    return;
  }

  frameDirectories
      .sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  final frameDirectory = frameDirectories.first;
  final frames = frameDirectory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => _captureNumber(a).compareTo(_captureNumber(b)));
  if (frames.isEmpty) {
    stderr.writeln(
      'No PNG animation frames were found. Run `flutter test` first.',
    );
    exitCode = 1;
    return;
  }

  final output = File('build/widget_test_capture/videos/panel_animation_1.mp4');
  try {
    await encodeMp4(frames, output, fps: 15);
    stdout.writeln('Created ${output.path}');
  } on FfmpegException catch (error) {
    stderr.writeln('Could not create MP4: $error');
    exitCode = 1;
  }
}

int _captureNumber(File file) {
  final match = RegExp(r'_(\d+)\.png$').firstMatch(file.uri.pathSegments.last);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}
