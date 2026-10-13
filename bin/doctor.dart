import 'dart:io';

import 'package:widget_test_capture/src/cli.dart';

void main(List<String> args) =>
    runCli(['doctor', ...args]).then((code) => exitCode = code);
