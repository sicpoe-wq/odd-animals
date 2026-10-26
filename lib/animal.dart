import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Animal {
  final String name;
  final String scientific;
  final String wiki;
  final String habitat;
  final List<String> facts;
  final String img;
  final String thumb;

  const Animal({
    required this.name,
    required this.scientific,
    required this.wiki,
    required this.habitat,
    required this.facts,
    required this.img,
    required this.thumb,
  });

  factory Animal.fromJson(Map<String, dynamic> j) => Animal(
        name: j['name'] as String,
        scientific: j['scientific'] as String,
        wiki: j['wiki'] as String,
        habitat: (j['habitat'] as String?) ?? '',
        facts: (j['facts'] as List).cast<String>(),
        img: j['img'] as String,
        thumb: (j['thumb'] as String?) ?? (j['img'] as String),
      );

  String get wikiUrl =>
      'https://en.wikipedia.org/wiki/${Uri.encodeComponent(wiki.replaceAll(' ', '_'))}';

  String get summaryUrl =>
      'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(wiki.replaceAll(' ', '_'))}';
}

Future<List<Animal>> loadAnimals([AssetBundle? bundle]) async {
  final raw = await (bundle ?? rootBundle).loadString('assets/animals.json');
  final list = jsonDecode(raw) as List;
  return list.map((e) => Animal.fromJson(e as Map<String, dynamic>)).toList();
}

/// A "shuffle bag": every animal is shown once before any repeats, and the
/// last animal of one round never starts the next round. State survives
/// app restarts via SharedPreferences.
class AnimalDeck {
  AnimalDeck(this.animals, {Random? random}) : _rng = random ?? Random();

  final List<Animal> animals;
  final Random _rng;
  List<int> _order = [];
  int _pos = -1;
  int round = 1;
  SharedPreferences? _prefs;

  static const _kOrder = 'deck_order';
  static const _kPos = 'deck_pos';
  static const _kRound = 'deck_round';

  int get seenThisRound => _pos + 1;
  int get total => animals.length;
  Animal get current => animals[_order[_pos]];
  bool get canGoBack => _pos > 0;

  Future<void> restore(SharedPreferences prefs) async {
    _prefs = prefs;
    final saved = prefs.getStringList(_kOrder);
    final pos = prefs.getInt(_kPos) ?? -1;
    if (saved != null && saved.length == animals.length) {
      final order = saved.map(int.tryParse).whereType<int>().toList();
      if (order.length == animals.length &&
          order.toSet().length == animals.length &&
          order.every((i) => i >= 0 && i < animals.length)) {
        _order = order;
        _pos = pos.clamp(-1, animals.length - 1);
        round = prefs.getInt(_kRound) ?? 1;
      }
    }
    if (_order.isEmpty) _reshuffle(avoidFirst: null);
    if (_pos < 0) _pos = 0;
    _save();
  }

  void _reshuffle({int? avoidFirst}) {
    _order = List<int>.generate(animals.length, (i) => i)..shuffle(_rng);
    if (avoidFirst != null && _order.length > 1 && _order.first == avoidFirst) {
      final swap = 1 + _rng.nextInt(_order.length - 1);
      final t = _order[0];
      _order[0] = _order[swap];
      _order[swap] = t;
    }
    _pos = -1;
  }

  Animal next() {
    if (_order.isEmpty) _reshuffle();
    if (_pos >= _order.length - 1) {
      final last = _order.isEmpty || _pos < 0 ? null : _order[_pos];
      _reshuffle(avoidFirst: last);
      round++;
    }
    _pos++;
    _save();
    return current;
  }

  Animal back() {
    if (_pos > 0) _pos--;
    _save();
    return current;
  }

  /// Peek at the upcoming animal (for image precaching) without advancing.
  Animal? peekNext() => _pos + 1 < _order.length ? animals[_order[_pos + 1]] : null;

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setStringList(_kOrder, _order.map((e) => '$e').toList());
    p.setInt(_kPos, _pos);
    p.setInt(_kRound, round);
  }
}
