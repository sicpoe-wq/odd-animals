import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'animal.dart';

const kUserAgent = 'OddAnimals/1.0 (Android app; https://github.com/sicpoe-wq/odd-animals)';
const kImageHeaders = {'User-Agent': kUserAgent};

const _bg = Color(0xFF0E1A14);
const _card = Color(0xFF16261D);
const _accent = Color(0xFF7BD389);
const _accent2 = Color(0xFFF2C14E);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OddAnimalsApp());
}

class OddAnimalsApp extends StatelessWidget {
  const OddAnimalsApp({super.key, this.home});
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.dark,
    ).copyWith(surface: _bg, primary: _accent, secondary: _accent2);
    return MaterialApp(
      title: 'Odd Animals',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: _bg,
        useMaterial3: true,
      ),
      home: home ?? const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.deck, this.loadSummaries = true, this.imageBuilder});

  /// Injected for tests.
  final AnimalDeck? deck;
  final bool loadSummaries;
  final Widget Function(Animal)? imageBuilder;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AnimalDeck? _deck;
  Animal? _animal;
  String? _error;
  final _scroll = ScrollController();
  final Map<String, Future<String?>> _summaries = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      var deck = widget.deck;
      if (deck == null) {
        final animals = await loadAnimals();
        deck = AnimalDeck(animals);
        await deck.restore(await SharedPreferences.getInstance());
      }
      if (!mounted) return;
      setState(() {
        _deck = deck;
        _animal = deck!.current;
      });
      _precacheNext();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _precacheNext() {
    final n = _deck?.peekNext();
    if (n == null || widget.imageBuilder != null || !mounted) return;
    precacheImage(NetworkImage(n.img, headers: kImageHeaders), context, onError: (_, _) {});
  }

  void _go(Animal Function(AnimalDeck d) step) {
    final d = _deck;
    if (d == null) return;
    setState(() => _animal = step(d));
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    _precacheNext();
  }

  Future<String?> _summary(Animal a) {
    return _summaries.putIfAbsent(a.wiki, () async {
      try {
        final r = await http
            .get(Uri.parse(a.summaryUrl), headers: {'User-Agent': kUserAgent})
            .timeout(const Duration(seconds: 10));
        if (r.statusCode != 200) return null;
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        return j['extract'] as String?;
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _animal;
    return Scaffold(
      body: SafeArea(
        child: _error != null
            ? Center(child: Text('Could not load animals: $_error'))
            : a == null
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(context, a),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Animal a) {
    final d = _deck!;
    final t = Theme.of(context).textTheme;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.pets_rounded, color: _accent, size: 26),
                const SizedBox(width: 10),
                Text('Odd Animals',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${d.seenThisRound} / ${d.total}',
                      key: const Key('counter'),
                      style: t.labelMedium?.copyWith(color: _accent)),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _AnimalCard(
              key: ValueKey(a.name),
              animal: a,
              image: widget.imageBuilder?.call(a) ?? _AnimalImage(animal: a),
              canGoBack: d.canGoBack,
              onNext: () => _go((d) => d.next()),
              onBack: () => _go((d) => d.back()),
              summary: widget.loadSummaries ? _summary(a) : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimalImage extends StatelessWidget {
  const _AnimalImage({required this.animal});
  final Animal animal;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      animal.img,
      headers: kImageHeaders,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _Placeholder(loading: true);
      },
      errorBuilder: (context, _, _) => Image.network(
        animal.thumb,
        headers: kImageHeaders,
        fit: BoxFit.cover,
        errorBuilder: (context, _, _) => const _Placeholder(loading: false),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F3A2B), Color(0xFF12241A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: loading
            ? const CircularProgressIndicator(color: _accent)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.white.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),
                  Text('Photo unavailable offline',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                ],
              ),
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  const _AnimalCard({
    super.key,
    required this.animal,
    required this.image,
    required this.onNext,
    required this.onBack,
    required this.canGoBack,
    this.summary,
  });

  final Animal animal;
  final Widget image;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final bool canGoBack;
  final Future<String?>? summary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = animal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.55, 1],
                        colors: [Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: t.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800, color: Colors.white)),
                        Text(a.scientific,
                            style: t.titleSmall?.copyWith(
                                fontStyle: FontStyle.italic, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                height: 56,
                width: 56,
                child: IconButton.filledTonal(
                  tooltip: 'Previous animal',
                  onPressed: canGoBack ? onBack : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    key: const Key('newAnimal'),
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: const Color(0xFF0B2414),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      textStyle: t.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('New Animal'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (a.habitat.isNotEmpty)
            _Panel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.public_rounded, color: _accent2, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WHERE IT LIVES',
                            style: t.labelSmall?.copyWith(color: _accent2, letterSpacing: 1.2)),
                        const SizedBox(height: 2),
                        Text(a.habitat, style: t.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome_rounded, color: _accent, size: 20),
                  const SizedBox(width: 8),
                  Text('DID YOU KNOW?',
                      style: t.labelSmall?.copyWith(color: _accent, letterSpacing: 1.2)),
                ]),
                const SizedBox(height: 10),
                for (var i = 0; i < a.facts.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          margin: const EdgeInsets.only(right: 10, top: 1),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Text('${i + 1}',
                              style: t.labelMedium?.copyWith(
                                  color: _accent, fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                            child: Text(a.facts[i],
                                style: t.bodyLarge?.copyWith(height: 1.35))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<String?>(
              future: summary,
              builder: (context, snap) {
                final text = snap.data;
                if (text == null || text.isEmpty) {
                  return const SizedBox.shrink();
                }
                return _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FROM WIKIPEDIA',
                          style: t.labelSmall?.copyWith(color: Colors.white60, letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      Text(text,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium?.copyWith(color: Colors.white70, height: 1.35)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => launchUrl(Uri.parse(a.wikiUrl),
                              mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Read more'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          Text('Photo: Wikimedia Commons',
              textAlign: TextAlign.center,
              style: t.labelSmall?.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }
}
