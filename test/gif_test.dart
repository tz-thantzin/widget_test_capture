import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:widget_test_capture/widget_test_capture.dart';

void main() {
  test('encodes decodable GIF frames with loop and delay options', () async {
    final directory = Directory.systemTemp.createTempSync('wtc-gif-');
    try {
      final frames = <File>[];
      for (final color in [0xffff0000, 0xff00ff00]) {
        final image = img.Image(width: 12, height: 8);
        img.fill(image,
            color: img.ColorUint8.rgba((color >> 16) & 0xff,
                (color >> 8) & 0xff, color & 0xff, (color >> 24) & 0xff));
        final file = File('${directory.path}/frame ${frames.length}.png');
        file.writeAsBytesSync(img.encodePng(image));
        frames.add(file);
      }
      final output = File('${directory.path}/story.gif');
      await encodeGif(frames, output,
          options: const GifOptions(
              loopCount: 2, frameDelay: Duration(milliseconds: 250)));
      final bytes = output.readAsBytesSync();
      final decoder = img.GifDecoder(bytes);
      expect(decoder.numFrames(), 2);
      // GIF stores delay in 10 ms units.
      expect(decoder.info!.frames.first.duration, 25);
      expect(String.fromCharCodes(bytes), contains('NETSCAPE2.0'));
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
