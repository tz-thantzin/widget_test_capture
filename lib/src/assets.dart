import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final Set<String> _loadedFontFamilies = <String>{};
final Map<String, Future<void>> _fontLoads = <String, Future<void>>{};
Future<bool>? _manifestFontLoad;
const _defaultRobotoAsset =
    'packages/widget_test_capture/assets/fonts/Roboto-Regular.ttf';

/// Loads a font before a widget test paints text.
///
/// With no arguments, app-declared fonts are loaded automatically. Bundled
/// Roboto is used only when the app has no declared text font. Pass a family
/// and asset path to load a specific local font.
Future<void> loadCaptureFont([String? family, String? assetPath]) {
  if (family == null && assetPath == null) {
    return loadCaptureFontsFromManifest().then<void>((_) {});
  }
  if (family == null || assetPath == null) {
    throw ArgumentError('Provide both a font family and an asset path.');
  }
  if (_loadedFontFamilies.contains(family)) return Future<void>.value();
  return _fontLoads.putIfAbsent(family, () async {
    await _registerFont(family, [assetPath]);
    _loadedFontFamilies.add(family);
  });
}

/// Loads the app's declared font families from `FontManifest.json`.
///
/// Capture and golden helpers call this automatically. The package does not
/// change the app's selected font family. Bundled Roboto is loaded only when
/// no app text font is declared or explicitly registered.
Future<bool> loadCaptureFontsFromManifest() {
  final inFlight = _manifestFontLoad;
  if (inFlight != null) return inFlight;

  final load = _loadManifestFonts();
  _manifestFontLoad = load;
  return load.whenComplete(() {
    if (identical(_manifestFontLoad, load)) _manifestFontLoad = null;
  });
}

/// Loads a fallback font for text families that are used by the widget tree
/// but are not declared in the app's font manifest.
///
/// This covers families supplied at runtime by packages such as Google Fonts
/// when those fonts cannot be fetched in a widget test. Declared app fonts
/// continue to use their own font files.
Future<bool> loadCaptureFontsForWidgets(WidgetTester tester) async {
  final loadedFromManifest = await loadCaptureFontsFromManifest();
  final families = <String>{};
  families.add('Roboto');
  for (final element in tester.allElements) {
    final widget = element.widget;
    if (widget is DefaultTextStyle) {
      _collectFontFamilies(widget.style, families);
    } else if (widget is Text) {
      final inherited = DefaultTextStyle.of(element).style;
      final style = widget.style;
      _collectFontFamilies(
        style == null || style.inherit ? inherited.merge(style) : style,
        families,
      );
    } else if (widget is RichText) {
      _collectFontFamilies(widget.text.style, families);
      _collectSpanFontFamilies(widget.text, families);
    } else if (widget is EditableText) {
      _collectFontFamilies(widget.style, families);
    }
  }
  var loadedFallback = false;
  for (final family in families) {
    if (_loadedFontFamilies.contains(family)) continue;
    try {
      await _registerFont(family, [_defaultRobotoAsset]);
      _loadedFontFamilies.add(family);
      loadedFallback = true;
    } on StateError {
      // A font package may have registered the family directly with Flutter.
    }
  }
  final normalizedText = _setDefaultFontOnRenderTree(tester);
  return loadedFromManifest || loadedFallback || normalizedText;
}

bool _setDefaultFontOnRenderTree(WidgetTester tester) {
  var changed = false;
  void visit(RenderObject object) {
    if (object is RenderParagraph) {
      final current = object.text;
      final updated = _withDefaultFont(current);
      if (updated != current) {
        object.text = updated;
        changed = true;
      }
    } else if (object is RenderEditable) {
      final current = object.text;
      if (current != null) {
        final updated = _withDefaultFont(current);
        if (updated != current) {
          object.text = updated;
          changed = true;
        }
      }
    }
    object.visitChildren(visit);
  }

  for (final renderView in tester.binding.renderViews) {
    visit(renderView);
  }
  return changed;
}

InlineSpan _withDefaultFont(InlineSpan span) {
  if (span is! TextSpan) return span;
  final style = span.style;
  final effectiveStyle = style == null || style.fontFamily == null
      ? (style ?? const TextStyle()).copyWith(fontFamily: 'Roboto')
      : style;
  return TextSpan(
    text: span.text,
    style: effectiveStyle,
    children: span.children?.map(_withDefaultFont).toList(),
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel,
    semanticsIdentifier: span.semanticsIdentifier,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

void _collectFontFamilies(TextStyle? style, Set<String> families) {
  final family = style?.fontFamily;
  if (family != null && family.isNotEmpty && family != 'MaterialIcons') {
    families.add(family);
  }
}

void _collectSpanFontFamilies(InlineSpan span, Set<String> families) {
  if (span is TextSpan) {
    _collectFontFamilies(span.style, families);
    for (final child in span.children ?? const <InlineSpan>[]) {
      _collectSpanFontFamilies(child, families);
    }
  }
}

Future<bool> _loadManifestFonts() async {
  var manifest = <Object?>[];
  try {
    final manifestText = await rootBundle.loadString('FontManifest.json');
    final decoded = jsonDecode(manifestText);
    if (decoded is List) manifest = decoded;
  } on FlutterError {
    // Some test asset bundles have no font manifest.
  }

  var loadedAny = false;
  var hasDeclaredTextFont = false;
  for (final entry in manifest.whereType<Map>()) {
    final family = entry['family'];
    final fontEntries = entry['fonts'];
    if (family is! String || fontEntries is! List) continue;

    final assets = fontEntries
        .whereType<Map>()
        .map((font) => font['asset'])
        .whereType<String>()
        .toList();
    if (assets.isEmpty) continue;
    if (family != 'MaterialIcons') hasDeclaredTextFont = true;
    if (!_loadedFontFamilies.contains(family)) {
      await _registerFont(family, assets);
      _loadedFontFamilies.add(family);
      loadedAny = true;
    }
  }

  final hasRegisteredTextFont =
      _loadedFontFamilies.any((family) => family != 'MaterialIcons');
  if (!hasDeclaredTextFont && !hasRegisteredTextFont) {
    await _registerFont('Roboto', [_defaultRobotoAsset]);
    _loadedFontFamilies.add('Roboto');
    loadedAny = true;
  }
  return loadedAny;
}

Future<void> _registerFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
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
