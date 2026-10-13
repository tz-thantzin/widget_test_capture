# Example project

From this directory, run the widget tests:

```sh
flutter test
```

The tests write numbered PNG checkpoints under
`build/widget_test_capture/screenshots/`. A test named `counter demo` produces files
such as `counter_demo_1.png`, `counter_demo_2.png`, and so on. Each test run
uses its own folder to prevent repeated or parallel runs from overwriting files.
The tests also create `build/widget_test_capture/gifs/panel_animation_1.gif`
and `build/widget_test_capture/gifs/storyboard_1.gif`.

The example app has Android, iOS, and web project files. To launch the app,
list available targets and choose a device:

```sh
flutter devices
flutter run -d DEVICE_ID
```

For a browser, run `flutter run -d chrome`. App launches do not create widget
test captures; run `flutter test` to create screenshots and GIFs.

The `panel animation` example starts an animation and records a frame sequence:

```dart
final frames = await capture.recordAnimation(
  'panel',
  duration: const Duration(seconds: 2),
  fps: 15,
);
```

The `storyboard` example saves two checkpoints as a GIF.

MP4 is a separate step because it needs FFmpeg with H.264 support. Install
FFmpeg, run the tests, then encode the recorded animation frames:

```sh
dart run tool/encode_video.dart
```

The tool creates `build/widget_test_capture/videos/panel_animation_1.mp4`. It preserves
PNG frames if FFmpeg is missing or encoding fails.
