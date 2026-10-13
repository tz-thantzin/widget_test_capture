import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:widget_test_capture/src/cli.dart';

void main() {
  test('report escapes user text and uses portable relative artifact links',
      () async {
    final root = Directory.systemTemp.createTempSync('wtc-report-');
    try {
      final manifests = Directory('${root.path}/manifests')..createSync();
      final manifest = File('${manifests.path}/capture_1.jsonl');
      manifest.writeAsStringSync(jsonEncode({
        'schemaVersion': 1,
        'testName': '<script>alert("x")</script>',
        'name': 'one & two',
        'path': 'screenshots/café #1.png',
      }));
      expect(await runCli(['report', root.path]), 0);
      final html = File('${root.path}/reports/index.html').readAsStringSync();
      expect(
          html, contains('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;'));
      expect(html, contains('../screenshots/caf%C3%A9%20%231.png'));
      expect(html, isNot(contains('<script>alert')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('clean deletes only screenshot files indexed by its manifests',
      () async {
    final root = Directory.systemTemp.createTempSync('wtc-clean-');
    try {
      final screenshots = Directory('${root.path}/screenshots')..createSync();
      final owned = File('${screenshots.path}/owned_123456_abcd.png')
        ..writeAsStringSync('owned');
      final unrelated = File('${screenshots.path}/notes.txt')
        ..writeAsStringSync('keep');
      final gifs = Directory('${root.path}/gifs')..createSync();
      final ownedGif = File('${gifs.path}/owned.gif')..writeAsStringSync('gif');
      File('${ownedGif.path}.wtc-owner')
          .writeAsStringSync('widget_test_capture:media:v1');
      final unrelatedGif = File('${gifs.path}/manual.gif')
        ..writeAsStringSync('keep');
      final reports = Directory('${root.path}/reports')..createSync();
      final ownedReport = File('${reports.path}/index.html')
        ..writeAsStringSync('report');
      File('${ownedReport.path}.wtc-owner')
          .writeAsStringSync('widget_test_capture:report:v1');
      final unrelatedReport = File('${reports.path}/manual.html')
        ..writeAsStringSync('keep');
      final manifests = Directory('${root.path}/manifests')..createSync();
      File('${manifests.path}/capture_123_456.jsonl').writeAsStringSync(
          jsonEncode({'path': 'screenshots/owned_123456_abcd.png'}) +
              '\n' +
              jsonEncode({'path': '../../outside.txt'}));
      expect(await runCli(['clean', root.path]), 0);
      expect(owned.existsSync(), isFalse);
      expect(unrelated.readAsStringSync(), 'keep');
      expect(ownedGif.existsSync(), isFalse);
      expect(unrelatedGif.readAsStringSync(), 'keep');
      expect(ownedReport.existsSync(), isFalse);
      expect(unrelatedReport.readAsStringSync(), 'keep');
      expect(File('${root.path}/outside.txt').existsSync(), isFalse);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('test command returns the Flutter runner exit code and forwards args',
      () async {
    List<String>? received;
    final exit = await runCli(['test', '--reporter', 'expanded'],
        testRunner: (args) async {
      received = args;
      return 23;
    });
    expect(received, ['--reporter', 'expanded']);
    expect(exit, 23);
  });
}
