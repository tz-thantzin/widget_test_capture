import 'package:flutter/material.dart';

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(title: const Text('Capture demo')),
          body: const Center(child: DemoCounter()),
        ),
      );
}

class DemoCounter extends StatefulWidget {
  const DemoCounter({super.key});

  @override
  State<DemoCounter> createState() => _DemoCounterState();
}

class _DemoCounterState extends State<DemoCounter> {
  int value = 0;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value', key: const Key('counter-value')),
          FilledButton(
            key: const Key('increment'),
            onPressed: () => setState(() => value++),
            child: const Text('Increment'),
          ),
        ],
      );
}
