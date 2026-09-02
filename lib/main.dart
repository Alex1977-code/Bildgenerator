import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/gallery_screen.dart';
import 'screens/generator_screen.dart';
import 'screens/run_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/three_d_screen.dart';
import 'services/credit_balance.dart';
import 'services/history_service.dart';
import 'services/image_relay.dart';
import 'services/model_relay.dart';
import 'services/prompt_relay.dart';
import 'services/roblox_specs_config.dart';
import 'services/run_queue.dart';
import 'services/settings_service.dart';
import 'widgets/app_header.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  final history = HistoryService();
  // Im Web bleibt ohnehin nichts über die Sitzung hinaus.
  final queue = RunQueue(persistent: !kIsWeb);
  await settings.init();
  await history.init();
  await queue.init();
  // Die Roblox-Vorgaben aus der Datei, nicht aus dem Code. Schlägt das
  // fehl, gelten die eingebauten Werte – der Grund steht danach in
  // den Einstellungen.
  await loadRobloxSpecs(rootBundle.loadString,
      override: settings.robloxSpecsOverride.isEmpty
          ? null
          : settings.robloxSpecsOverride);
  runApp(BildgeneratorApp(settings: settings, history: history, queue: queue));
}

class BildgeneratorApp extends StatelessWidget {
  const BildgeneratorApp({
    super.key,
    required this.settings,
    required this.history,
    this.queue,
    this.balances,
  });

  final SettingsService settings;
  final HistoryService history;

  /// Die Warteschlange – in Tests weglassen, dann entsteht eine ohne
  /// Speicher.
  final RunQueue? queue;
  final CreditBalances? balances;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<HistoryService>.value(value: history),
        ChangeNotifierProvider<PromptRelay>(create: (_) => PromptRelay()),
        ChangeNotifierProvider<ModelRelay>(create: (_) => ModelRelay()),
        ChangeNotifierProvider<ImageRelay>(create: (_) => ImageRelay()),
        if (queue != null)
          ChangeNotifierProvider<RunQueue>.value(value: queue!)
        else
          ChangeNotifierProvider<RunQueue>(
              create: (_) => RunQueue(persistent: false)),
        if (balances != null)
          ChangeNotifierProvider<CreditBalances>.value(value: balances!)
        else
          ChangeNotifierProvider<CreditBalances>(
              create: (_) => CreditBalances()),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) => MaterialApp(
          title: '3DGenerator',
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          supportedLocales: const [Locale('de'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: settings.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const HomeShell(),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  PromptRelay? _relay;
  ModelRelay? _modelRelay;
  ImageRelay? _imageRelay;
  bool _balancesFetched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final relay = context.read<PromptRelay>();
    if (!identical(_relay, relay)) {
      _relay?.removeListener(_onPromptRelay);
      _relay = relay..addListener(_onPromptRelay);
    }
    final models = context.read<ModelRelay>();
    if (!identical(_modelRelay, models)) {
      _modelRelay?.removeListener(_onModelRelay);
      _modelRelay = models..addListener(_onModelRelay);
    }
    final images = context.read<ImageRelay>();
    if (!identical(_imageRelay, images)) {
      _imageRelay?.removeListener(_onImageRelay);
      _imageRelay = images..addListener(_onImageRelay);
    }
    // Das Guthaben einmal beim Start holen – danach nur auf Klick und
    // nach einem Lauf.
    if (!_balancesFetched) {
      _balancesFetched = true;
      final settings = context.read<SettingsService>();
      final balances = context.read<CreditBalances>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) balances.refresh(settings);
      });
    }
  }

  void _onPromptRelay() {
    // Ein Prompt aus der Galerie wurde übernommen → zum Generator wechseln.
    if (mounted) setState(() => _index = 0);
  }

  void _onModelRelay() {
    // Eine Figur aus der Galerie soll Zubehör bekommen → in den 3D-Tab.
    if (mounted) setState(() => _index = 1);
  }

  void _onImageRelay() {
    // Ein Bild aus dem Bild-Tab wird zur Vorderansicht → in den 3D-Tab.
    if (mounted) setState(() => _index = 1);
  }

  @override
  void dispose() {
    _relay?.removeListener(_onPromptRelay);
    _modelRelay?.removeListener(_onModelRelay);
    _imageRelay?.removeListener(_onImageRelay);
    super.dispose();
  }

  static const _destinations = [
    (icon: Icons.auto_awesome_outlined, selected: Icons.auto_awesome, label: 'Bild'),
    (icon: Icons.view_in_ar_outlined, selected: Icons.view_in_ar, label: '3D'),
    (icon: Icons.collections_outlined, selected: Icons.collections, label: 'Galerie'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Einstellungen'),
  ];

  void _openRuns() {
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RunScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final queue = context.watch<RunQueue>();
    final body = IndexedStack(
      index: _index,
      children: [
        GeneratorScreen(
          onOpenSettings: () => setState(() => _index = 3),
          onOpenRuns: _openRuns,
          isActive: _index == 0,
        ),
        ThreeDScreen(
          onOpenSettings: () => setState(() => _index = 3),
          isActive: _index == 1,
        ),
        GalleryScreen(isActive: _index == 2),
        const SettingsScreen(),
      ],
    );

    return Scaffold(
      // Auf dem Handy trägt jeder Tab seine eigene Titelzeile; die
      // Kopfzeile mit Projekt und Guthaben gibt es ab der Breite, auf
      // der beides nebeneinander Platz hat.
      appBar: wide ? AppHeader(onOpenRuns: _openRuns) : null,
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selected),
                        label: Text(d.label),
                      ),
                  ],
                  // Unten in der Leiste: die Warteschlange. „1 Lauf"
                  // heißt, es rechnet etwas – egal, in welchem Tab man
                  // gerade steht.
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RunRailTile(
                            queue: queue, onTap: _openRuns),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : SafeArea(child: body),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    // „Mehr" statt „Einstellungen": Das Wort passt auf
                    // dem Handy nicht in die Leiste.
                    label: d.label == 'Einstellungen' ? 'Mehr' : d.label,
                  ),
              ],
            ),
    );
  }
}

/// Die Kachel unten in der Leiste: „1 Lauf" mit Ring, oder leer
/// gestrichelt, wenn nichts rechnet.
class _RunRailTile extends StatelessWidget {
  const _RunRailTile({required this.queue, required this.onTap});

  final RunQueue queue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = queue.openCount;
    return Tooltip(
      message: open == 0
          ? 'Warteschlange – nichts läuft'
          : 'Warteschlange: ${queue.summary}',
      child: Material(
        color: open == 0 ? Colors.transparent : scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: open == 0
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  open == 0
                      ? Icon(Icons.timer_outlined,
                          size: 18, color: scheme.outline)
                      : const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(height: 5),
                  Text(
                    open == 0 ? 'Lauf' : '$open ${open == 1 ? 'Lauf' : 'Läufe'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: open == 0
                            ? scheme.outline
                            : scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
