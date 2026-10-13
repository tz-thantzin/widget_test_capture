import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small explicit view configuration for a widget-test scenario.
class CaptureDevice {
  const CaptureDevice({
    required this.name,
    required this.size,
    this.pixelRatio = 1,
  });
  final String name;
  final Size size;
  final double pixelRatio;
}

/// Applies simulated logical size and DPR for [body], then restores both.
Future<void> withCaptureDevice(
  WidgetTester tester,
  CaptureDevice device,
  Future<void> Function() body,
) async {
  final oldSize = tester.view.physicalSize;
  final oldRatio = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = device.pixelRatio;
  tester.view.physicalSize = Size(
    device.size.width * device.pixelRatio,
    device.size.height * device.pixelRatio,
  );
  addTearDown(() {
    tester.view.physicalSize = oldSize;
    tester.view.devicePixelRatio = oldRatio;
  });
  await body();
}

/// Builds a widget under a known theme, locale, text scale, and direction.
Widget captureScenario({
  required Widget child,
  ThemeMode themeMode = ThemeMode.light,
  Locale locale = const Locale('en'),
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) =>
    MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      locale: locale,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(textDirection: direction, child: child),
      ),
    );
