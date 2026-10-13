import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ffmpeg.dart';
import 'frame_recorder.dart';

Future<int> runCli(List<String> args,
    {Future<int> Function(List<String>)? testRunner}) async {
  final command = args.isEmpty ? 'help' : args.first;
  final rest = args.skip(1).toList();
  final directoryPath = switch (command) {
    'clean' ||
    'report' when rest.isNotEmpty && !rest.first.startsWith('-') =>
      rest.first,
    'test'
        when rest.contains('--capture-directory') &&
            rest.indexOf('--capture-directory') + 1 < rest.length =>
      rest[rest.indexOf('--capture-directory') + 1],
    _ => 'assets/widget_test',
  };
  final directory = Directory(directoryPath);
  try {
    switch (command) {
      case 'doctor':
        try {
          stdout.writeln(
              'FFmpeg: ${await doctorFfmpeg()} (H.264 encoder available)');
        } on FfmpegException catch (e) {
          stderr.writeln(e);
          return 1;
        }
        return 0;
      case 'test':
        final forwardArgs = [...rest]..remove('--capture-report');
        final directoryFlag = forwardArgs.indexOf('--capture-directory');
        if (directoryFlag >= 0 && directoryFlag + 1 < forwardArgs.length) {
          forwardArgs.removeRange(directoryFlag, directoryFlag + 2);
        }
        final generateReport = rest.contains('--capture-report');
        final int exitCode;
        if (testRunner != null) {
          exitCode = await testRunner(forwardArgs);
        } else {
          final result = await Process.start(
              'flutter', ['test', ...forwardArgs],
              mode: ProcessStartMode.inheritStdio);
          exitCode = await result.exitCode;
        }
        if (generateReport) {
          try {
            await _report(directory);
          } catch (error) {
            stderr.writeln('Capture report failed: $error');
          }
        }
        return exitCode;
      case 'clean':
        final root = directory.absolute;
        final manifests = Directory(p.join(root.path, 'manifests'));
        if (await manifests.exists()) {
          await for (final entry in manifests.list()) {
            if (entry is! File ||
                !RegExp(r'^capture_\d+_\d+\.jsonl$')
                    .hasMatch(p.basename(entry.path))) continue;
            for (final line in await entry.readAsLines()) {
              try {
                final record = jsonDecode(line) as Map<String, dynamic>;
                final relative = record['path'];
                if (relative is String && relative.startsWith('screenshots/')) {
                  final artifact =
                      File(p.normalize(p.join(root.path, relative)));
                  if (p.isWithin(root.path, artifact.path) &&
                      RegExp(r'.+_\d+_[0-9a-f]+\.png$')
                          .hasMatch(p.basename(artifact.path)) &&
                      await artifact.exists()) await artifact.delete();
                }
              } catch (_) {/* Ignore incomplete or invalid manifest lines. */}
            }
            await entry.delete();
          }
        }
        final screenshots = Directory(p.join(root.path, 'screenshots'));
        if (await screenshots.exists()) {
          await for (final entry in screenshots.list(recursive: true)) {
            if (entry is File &&
                RegExp(r'.+_\d+_[0-9a-f]+\.png$')
                    .hasMatch(p.basename(entry.path))) {
              await entry.delete();
            }
          }
        }
        for (final folder in ['gifs', 'videos']) {
          final media = Directory(p.join(root.path, folder));
          if (!await media.exists()) continue;
          await for (final entry in media.list(recursive: true)) {
            if (entry is! File || !entry.path.endsWith('.wtc-owner')) continue;
            if ((await entry.readAsString()).trim() !=
                'widget_test_capture:media:v1') continue;
            final artifact = File(entry.path
                .substring(0, entry.path.length - '.wtc-owner'.length));
            if (await artifact.exists()) await artifact.delete();
            await entry.delete();
          }
        }
        final report = File(p.join(root.path, 'reports', 'index.html'));
        final reportOwner = File('${report.path}.wtc-owner');
        if (await reportOwner.exists() &&
            (await reportOwner.readAsString()).trim() ==
                'widget_test_capture:report:v1') {
          if (await report.exists()) await report.delete();
          await reportOwner.delete();
        }
        stdout.writeln(
            'Removed package-owned screenshot and media artifacts under ${root.path}');
        return 0;
      case 'report':
        return await _report(directory);
      case 'encode':
        final formatIndex = rest.indexOf('--format');
        if (formatIndex < 0 || formatIndex + 1 >= rest.length)
          throw ArgumentError('Use --format gif or --format mp4.');
        final outputIndex = rest.indexOf('--output');
        if (outputIndex < 0 || outputIndex + 1 >= rest.length)
          throw ArgumentError(
              'Use --output FILE followed by one or more PNG frames.');
        final format = rest[formatIndex + 1];
        final output = File(rest[outputIndex + 1]);
        final frames = rest
            .skip(outputIndex + 2)
            .where((a) => !a.startsWith('--'))
            .map(File.new)
            .toList();
        if (frames.isEmpty)
          throw ArgumentError(
              'Provide one or more PNG frame paths after --output.');
        if (format == 'gif') {
          await encodeGif(frames, output);
        } else if (format == 'mp4') {
          await encodeMp4(frames, output);
        } else {
          throw ArgumentError('Unknown format "$format". Use gif or mp4.');
        }
        stdout.writeln('Wrote ${output.absolute.path}');
        return 0;
      default:
        stdout.writeln(
            'widget_test_capture commands: doctor, report, encode, clean, test');
        return command == 'help' ? 0 : 64;
    }
  } on ProcessException catch (e) {
    stderr.writeln('Could not start process: ${e.message}');
    return 127;
  } catch (e) {
    stderr.writeln(e);
    return 1;
  }
}

Future<int> _report(Directory root) async {
  final rootPath = root.absolute.path;
  final records = <Map<String, dynamic>>[];
  final manifests = Directory(p.join(root.path, 'manifests'));
  if (await manifests.exists()) {
    await for (final file in manifests.list()) {
      if (file is! File || !file.path.endsWith('.jsonl')) continue;
      for (final line in await file.readAsLines()) {
        try {
          records.add(jsonDecode(line) as Map<String, dynamic>);
        } catch (_) {/* Ignore a partial final line. */}
      }
    }
  }
  records.sort((a, b) =>
      '${a['capturedAt'] ?? ''}'.compareTo('${b['capturedAt'] ?? ''}'));
  final images = records
      .where((r) =>
          _isSafeScreenshotPath(rootPath, r['path']) &&
          '${r['path']}'.toLowerCase().endsWith('.png'))
      .map((r) {
    final title =
        _escape('${r['testName'] ?? 'Test'} — ${r['name'] ?? 'capture'}');
    final artifact = _escapeAttr(_relativeUrl('../${r['path']}'));
    final metadata = r['metadata'] == null
        ? ''
        : '<p>${_escape(jsonEncode(r['metadata']))}</p>';
    return '<article class="artifact" data-search="$title $artifact"><h2>$title</h2>$metadata<a href="$artifact" download><img loading="lazy" src="$artifact"></a></article>';
  }).join('\n');
  final events = records
      .where((r) => r['kind'] == 'interaction')
      .map((r) =>
          '<li>${_escape('${r['testName'] ?? 'Test'} — ${r['name'] ?? 'step'} (${r['phase'] ?? 'event'})')}</li>')
      .join();
  final extraMedia = StringBuffer();
  for (final folder in ['gifs', 'videos']) {
    final media = Directory(p.join(root.path, folder));
    if (!await media.exists()) continue;
    await for (final entry in media.list(recursive: true)) {
      if (entry is! File ||
          !(entry.path.toLowerCase().endsWith('.gif') ||
              entry.path.toLowerCase().endsWith('.mp4'))) continue;
      final relative = p
          .relative(entry.path, from: p.join(root.path, 'reports'))
          .replaceAll('\\', '/');
      final href = _escapeAttr(_relativeUrl(relative));
      final title = _escape(p.basename(entry.path));
      final player = entry.path.toLowerCase().endsWith('.gif')
          ? '<img loading="lazy" src="$href">'
          : '<video controls preload="metadata" src="$href"></video>';
      extraMedia.write(
          '<article class="artifact" data-search="$title"><h2>$title</h2><a href="$href" download>Download</a>$player</article>');
    }
  }
  final html =
      '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Widget test captures</title><style>body{font:16px system-ui;margin:2rem;background:#f4f5f8}article{display:inline-block;vertical-align:top;width:min(30rem,95%);padding:1rem;margin:.5rem;background:white;border-radius:1rem}img,video{max-width:100%;height:auto}input{padding:.7rem;width:min(30rem,90%)}</style><h1>Widget test captures</h1><label>Search <input id="search" type="search"></label><section id="gallery">$images$extraMedia</section><h2>Interaction timeline</h2><ol>$events</ol><script>const q=document.querySelector("#search");q.addEventListener("input",()=>{for(const card of document.querySelectorAll(".artifact")){card.hidden=!card.dataset.search.toLowerCase().includes(q.value.toLowerCase())}})</script>';
  final report = File(p.join(root.path, 'reports', 'index.html'));
  final owner = File('${report.path}.wtc-owner');
  if (await report.exists() &&
      (!await owner.exists() ||
          (await owner.readAsString()).trim() !=
              'widget_test_capture:report:v1')) {
    throw StateError(
        'Refusing to overwrite an unowned report file: ${report.path}');
  }
  await report.parent.create(recursive: true);
  final temporary =
      File('${report.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}');
  await temporary.writeAsString(html, flush: true);
  File? previous;
  if (await report.exists()) {
    previous = File(
        '${report.path}.old-$pid-${DateTime.now().microsecondsSinceEpoch}');
    await report.rename(previous.path);
  }
  try {
    await temporary.rename(report.path);
    if (previous != null && await previous.exists()) await previous.delete();
  } catch (_) {
    if (previous != null && await previous.exists()) {
      await previous.rename(report.path);
    }
    rethrow;
  }
  await owner.writeAsString('widget_test_capture:report:v1\n', flush: true);
  stdout.writeln('Report: ${report.path}');
  return 0;
}

bool _isSafeScreenshotPath(String root, Object? value) {
  if (value is! String ||
      p.isAbsolute(value) ||
      !value.startsWith('screenshots/')) {
    return false;
  }
  final absolute = p.normalize(p.join(root, value));
  return p.isWithin(root, absolute);
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
String _relativeUrl(String path) =>
    path.split('/').map(Uri.encodeComponent).join('/');
String _escapeAttr(String s) => _escape(s);
