// Renders phone-sized screenshots of the app into screenshots/.
// Run: flutter test test/screenshot_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odd_animals/animal.dart';
import 'package:odd_animals/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  final fonts = '${Platform.environment['FLUTTER_ROOT'] ?? '/workspace/flutter'}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold', 'Roboto-Black', 'Roboto-Italic']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$fonts/$f.ttf').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screenshots', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final animals = await tester.runAsync(loadAnimals);
    final deck = AnimalDeck(animals!, random: Random(7));
    await tester.runAsync(() async => deck.restore(await SharedPreferences.getInstance()));

    final imgDir = Platform.environment['SHOT_IMG_DIR'] ?? '/tmp/shot_imgs';
    final cache = <String, MemoryImage>{};
    Widget imageFor(Animal a) {
      final p = cache[a.name];
      if (p == null) return Container(color: Colors.black26);
      return Image(image: p, fit: BoxFit.cover);
    }

    Future<void> prep() async {
      for (final a in [deck.current, if (deck.peekNext() != null) deck.peekNext()!]) {
        final f = File('$imgDir/${a.name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.jpg');
        if (cache.containsKey(a.name) || !f.existsSync()) continue;
        final img = MemoryImage(f.readAsBytesSync());
        cache[a.name] = img;
      }
    }

    final key = GlobalKey();
    await tester.runAsync(prep);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: OddAnimalsApp(
        home: HomePage(deck: deck, loadSummaries: false, imageBuilder: imageFor),
      ),
    ));
    Future<void> shot(String name) async {
      for (final p in cache.values) {
        await tester.runAsync(() => precacheImage(p, tester.element(find.byType(HomePage))));
      }
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('screenshots').createSync();
        File('screenshots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await tester.pumpAndSettle();
    await shot('screen1');
    await tester.runAsync(prep);
    await tester.tap(find.byKey(const Key('newAnimal')));
    await tester.runAsync(prep);
    await tester.pumpAndSettle();
    expect(find.text('2 / ${animals.length}'), findsOneWidget);
    await shot('screen2');
  });
}
