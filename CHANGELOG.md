## 0.2.0

- Render captured text with a bundled fallback font when the app's font is unavailable in widget tests.
- Load app-declared fonts before PNG and golden captures.
- Handle unavailable runtime Google Fonts without flooding capture test output.

## 0.1.2

- Automatically load app-declared fonts for widget capture and golden helpers.
- Use bundled Roboto as a fallback when no app text font is declared.
- Save example captures under `build/widget_test_capture/`.

## 0.1.1

- Fix the library documentation comment in the pure-Dart encoder entrypoint.

## 0.1.0

- Initial host widget-test capture API.
- PNG checkpoints, simulated animation frame capture, GIF and optional FFmpeg MP4.
- Golden helper, view configuration, manifest gallery, and CLI commands.
