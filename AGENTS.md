# Repository Guidelines

## Project Structure

- `lib/` contains the public Flutter testing API and implementation modules in `lib/src/`.
- `lib/encode.dart` exposes pure-Dart media encoding for command-line tools.
- `test/` contains package tests for capture, GIF/MP4 output, goldens, and the CLI.
- `example/` is a runnable Flutter app with widget tests, local font assets, and an MP4 encoding tool.
- `.github/workflows/ci.yml` defines continuous integration. Generated captures belong under `assets/widget_test/` and should not be committed unless they are deliberate fixtures.

## Build, Test, and Development Commands

Run commands from the package root unless stated otherwise:

- `flutter pub get` resolves dependencies.
- `dart format lib test example` formats Dart sources.
- `flutter analyze` runs static analysis.
- `flutter test` runs the package test suite.
- `cd example && flutter test` runs the usage example tests and produces sample captures.
- `cd example && dart run tool/encode_video.dart` creates the sample MP4; it requires FFmpeg with an H.264 encoder.
- `dart run widget_test_capture:doctor` checks the optional FFmpeg backend.
- `dart pub publish --dry-run` checks package contents before release.

## Coding Style

Use Dart's formatter with two-space indentation. Follow `analysis_options.yaml` and the recommended Dart lints. Use `lowerCamelCase` for functions and variables, `UpperCamelCase` for types, and descriptive `snake_case` for test descriptions and generated artifact names. Keep Flutter-dependent APIs out of `lib/encode.dart` so Dart CLI commands can run without loading `dart:ui`.

## Testing Guidelines

Write focused tests under `test/` with filenames ending in `_test.dart`. Use `testWidgets` for widget rendering and validate produced files, dimensions, names, and failure behavior. Add coverage for public API changes and preserve platform independent host tests. Run `flutter test` and `flutter analyze` before submitting. Example changes should also be checked with `cd example && flutter test`.

## Commits and Pull Requests

The available history has only an initial commit, so no established commit format is present. Use a short imperative subject, such as `Add numbered capture folders`. Pull requests should explain the behavior change, list validation commands and results, link related issues when available, and include screenshots or generated report samples for visual changes. Keep generated test artifacts and machine-specific settings out of the change unless they are required fixtures.

## Configuration Notes

PNG capture and GIF export do not require FFmpeg. MP4 support uses the host's FFmpeg installation and must not download or bundle executables. Keep example tests self-contained and use local assets for deterministic rendering.
