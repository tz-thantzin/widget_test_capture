# Architecture

## Package layers

- `config.dart` defines output, pixel, and animation limits.
- `capture.dart` contains the Flutter test API, `captureTest`, checkpoints,
  interaction events, and deterministic frame timing.
- `matrix.dart` simulates view size, device pixel ratio, theme, locale, text
  scale, and text direction. It restores view settings during teardown.
- `assets.dart` loads local fonts and image providers.
- `golden.dart` delegates pixel comparison and baseline updates to Flutter's
  standard golden comparator.
- `frame_recorder.dart` encodes PNG frames to GIF with the pure Dart `image`
  package.
- `ffmpeg.dart` starts a host FFmpeg process for optional MP4 output.
- `cli.dart` is pure Dart. It reads manifests, creates HTML, encodes artifacts,
  and launches `flutter test` without importing Flutter or `dart:ui`.

## Capture flow

The Flutter test binding renders a full view image. Finder bounds are clipped
and cropped from the resulting PNG bytes. Engine image creation and PNG
conversion run through `WidgetTester.runAsync`. Small files and JSONL records
are written synchronously to avoid fake-async file futures that can stall a
widget test.

Each PNG name has a timestamp and random suffix. JSONL manifests are split by
process and isolate. Records contain schema version `1`, test name, capture
name, dimensions, wall-clock time, optional simulated timestamp, and user
metadata. Interaction records use the same schema and manifest stream.

The CLI reads all manifest files after a run. The HTML report links to portable
relative artifact paths. The test command preserves Flutter's exit code. It can
create a gallery after the run with `--capture-report`.

## Ownership and overwrite rules

- PNG captures always use new names.
- GIF and MP4 encoders replace a file at the requested output path. They write
  a `.wtc-owner` sidecar after a successful encode.
- The report refuses to replace an unowned `reports/index.html`.
- `clean` removes package-shaped PNG artifacts and manifest records. It removes
  GIFs, MP4s, and the report only when their ownership marker matches this
  package. Other files remain.
- Golden baselines change only through Flutter's `--update-goldens` behavior.

## Runtime boundaries

PNG and GIF encoding need no native plugin. MP4 needs a host FFmpeg build with
`libx264`. Tests capture Flutter-rendered view pixels, not desktop UI, audio,
browser surfaces, native platform views, or real devices. Test outcomes come
from Flutter's process exit code; manifests only describe captures.
