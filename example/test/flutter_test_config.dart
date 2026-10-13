import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:widget_test_capture/widget_test_capture.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadCaptureFont('DemoRoboto', 'assets/fonts/Roboto-Regular.ttf');
  await testMain();
}
