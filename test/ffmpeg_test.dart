import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:widget_test_capture/widget_test_capture.dart';

void main() {
  test('reports a useful error when FFmpeg is missing', () async {
    await expectLater(
      doctorFfmpeg(executable: '/no/such/ffmpeg'),
      throwsA(isA<FfmpegException>()
          .having((e) => e.message, 'message', contains('Could not find'))),
    );
  });

  test('encodes MP4 with an odd source size and a Unicode path', () async {
    String executable;
    try {
      executable = await doctorFfmpeg();
    } on FfmpegException {
      markTestSkipped(
          'FFmpeg with an H.264 encoder is not installed on this host.');
      return;
    }
    final directory = Directory.systemTemp.createTempSync('wtc video café ');
    try {
      final frame = img.Image(width: 3, height: 5);
      img.fill(frame, color: img.ColorUint8.rgba(25, 140, 220, 255));
      final input = File('${directory.path}/frame with space.png')
        ..writeAsBytesSync(img.encodePng(frame));
      final second = File('${directory.path}/second frame.png')
        ..writeAsBytesSync(img.encodePng(frame));
      final output = File('${directory.path}/result café.mp4');
      await encodeMp4([input, second], output, executable: executable, fps: 5);
      expect(output.existsSync(), isTrue);
      final probe = await Process.run('ffprobe', [
        '-v',
        'error',
        '-select_streams',
        'v:0',
        '-show_entries',
        'stream=codec_name,pix_fmt,width,height,duration',
        '-of',
        'json',
        output.path,
      ]);
      expect(probe.exitCode, 0, reason: '${probe.stderr}');
      final stream = (jsonDecode('${probe.stdout}')
          as Map<String, dynamic>)['streams'] as List<dynamic>;
      final details = stream.single as Map<String, dynamic>;
      expect(details['codec_name'], 'h264');
      expect(details['pix_fmt'], 'yuv420p');
      expect(details['width'], 4);
      expect(details['height'], 6);
      expect(
          double.parse('${details['duration']}'), greaterThanOrEqualTo(0.35));
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
