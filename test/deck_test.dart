import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:odd_animals/animal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled animal list is valid', () async {
    final animals = await loadAnimals();
    expect(animals.length, greaterThanOrEqualTo(150));
    expect(animals.map((a) => a.name).toSet().length, animals.length);
    for (final a in animals) {
      expect(a.facts.length, inInclusiveRange(3, 5), reason: a.name);
      expect(a.img, startsWith('https://'), reason: a.name);
      expect(a.scientific, isNotEmpty);
    }
  });

  test('deck shows every animal once before repeating and never repeats back-to-back', () async {
    SharedPreferences.setMockInitialValues({});
    final animals = await loadAnimals();
    for (var seed = 0; seed < 20; seed++) {
      final deck = AnimalDeck(animals, random: Random(seed));
      await deck.restore(await SharedPreferences.getInstance());
      final seen = <String>{deck.current.name};
      var prev = deck.current.name;
      for (var i = 1; i < animals.length; i++) {
        final a = deck.next();
        expect(seen.add(a.name), isTrue, reason: 'repeat before pool exhausted');
        expect(a.name, isNot(prev));
        prev = a.name;
      }
      expect(seen.length, animals.length);
      for (var i = 0; i < animals.length * 2; i++) {
        final a = deck.next();
        expect(a.name, isNot(prev), reason: 'immediate repeat across rounds');
        prev = a.name;
      }
      SharedPreferences.setMockInitialValues({});
    }
  });

  test('deck state persists across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final animals = await loadAnimals();
    final prefs = await SharedPreferences.getInstance();
    final d1 = AnimalDeck(animals, random: Random(1));
    await d1.restore(prefs);
    d1.next();
    d1.next();
    final name = d1.current.name;
    final d2 = AnimalDeck(animals, random: Random(99));
    await d2.restore(prefs);
    expect(d2.current.name, name);
    expect(d2.seenThisRound, 3);
  });
}
