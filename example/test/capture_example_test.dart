import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widget_test_capture/widget_test_capture.dart';
import 'package:widget_test_capture_example/main.dart';

const _captureConfig = CaptureConfig(
  outputDirectory: 'build/widget_test_capture',
);

void main() {
  captureTest(
    'counter demo',
    config: const CaptureConfig(
      outputDirectory: 'build/widget_test_capture',
      captureAtEnd: true,
      captureOnFailure: true,
    ),
    (tester, capture) async {
      await tester.pumpWidget(const DemoApp());
      await tester.pumpAndSettle();
      await capture.png('initial');
      await capture.step('increment', () async {
        await tester.tap(find.byKey(const Key('increment')));
        await tester.pumpAndSettle();
      });
      for (var count = 1; count < 10; count++) {
        await tester.tap(find.byKey(const Key('increment')));
        await tester.pump();
      }
      expect(find.text('10'), findsOneWidget);
      await capture.png('count-10');
      await capture.png('value-only',
          finder: find.byKey(const Key('counter-value')));
    },
  );

  captureTest(
    'panel animation',
    (tester, capture) async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const AnimatedPanelDemo(),
      ));
      await tester.tap(find.byKey(const Key('animate')));
      final frames = await capture.recordAnimation('panel',
          duration: const Duration(seconds: 2), fps: 15);
      await encodeAnimationGif(
          frames, File('build/widget_test_capture/gifs/panel_animation_1.gif'),
          fps: 15);
    },
    config: _captureConfig,
  );

  captureTest(
    'storyboard',
    (tester, capture) async {
      await tester.pumpWidget(const MaterialApp(home: DemoApp()));
      final initial = await capture.png('initial');
      await tester.tap(find.byKey(const Key('increment')));
      await tester.pumpAndSettle();
      final updated = await capture.png('updated');
      await encodeStoryboard([initial, updated],
          'build/widget_test_capture/gifs/storyboard_1.gif');
    },
    config: _captureConfig,
  );
}

class AnimatedPanelDemo extends StatefulWidget {
  const AnimatedPanelDemo({super.key});

  @override
  State<AnimatedPanelDemo> createState() => _AnimatedPanelDemoState();
}

class _AnimatedPanelDemoState extends State<AnimatedPanelDemo> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(seconds: 2),
              width: expanded ? 220 : 80,
              height: 80,
              color: Colors.blue,
            ),
            TextButton(
              key: const Key('animate'),
              onPressed: () => setState(() => expanded = !expanded),
              child: const Text('Animate'),
            ),
          ]),
        ),
      );
}
