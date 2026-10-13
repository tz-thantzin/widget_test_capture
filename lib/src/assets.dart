import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads a declared font asset before a widget test paints text.
Future<void> loadCaptureFont(String family, String assetPath) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(assetPath));
  await loader.load();
}

/// Loads Flutter's local Material icon font for deterministic icon screenshots.
Future<void> loadCaptureMaterialIcons() => loadCaptureFont(
    'MaterialIcons', 'packages/flutter/lib/fonts/MaterialIcons-Regular.otf');

/// Resolves and precaches an image provider in a widget test.
Future<void> precacheCaptureImage(
  WidgetTester tester,
  ImageProvider<Object> provider,
) async {
  await precacheImage(provider, tester.element(find.byType(WidgetsApp).first));
}

/// A deterministic placeholder for network image tests; no network is accessed.
class MockNetworkImage extends ImageProvider<MockNetworkImage> {
  const MockNetworkImage(this.bytes, {this.scale = 1});
  final Uint8List bytes;
  final double scale;
  @override
  Future<MockNetworkImage> obtainKey(ImageConfiguration configuration) async =>
      this;
  @override
  ImageStreamCompleter loadImage(
    MockNetworkImage key,
    ImageDecoderCallback decode,
  ) =>
      OneFrameImageStreamCompleter(_decode(decode));
  Future<ImageInfo> _decode(ImageDecoderCallback decode) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image, scale: scale);
  }
}
