import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/gallery_screen.dart';
import 'screens/generator_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/three_d_screen.dart';
import 'services/history_service.dart';
import 'services/model_relay.dart';
import 'services/prompt_relay.dart';
import 'services/roblox_specs_config.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  final history = HistoryService();
  await settings.init();
  await history.init();
  // Die Roblox-Vorgaben aus der Datei, nicht aus dem Code. Schlägt das
  // fehl, gelten die eingebauten Werte – der Grund steht danach in
  // den Einstellungen.
  await loadRobloxSpecs(rootBundle.loadString,
      override: settings.robloxSpecsOverride.isEmpty
          ? null
          : settings.robloxSpecsOverride);
  runApp(BildgeneratorApp(settings: settings, history: history));
}

class BildgeneratorApp extends StatelessWidget {
  const BildgeneratorApp({
    super.key,
    required this.settings,
    required this.history,
  });

  final SettingsService settings;
  final HistoryService history;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<HistoryService>.value(value: history),
        ChangeNotifierProvider<PromptRelay>(create: (_) => PromptRelay()),
        ChangeNotifierProvider<ModelRelay>(create: (_) => ModelRelay()),
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
  }

  void _onPromptRelay() {
    // Ein Prompt aus der Galerie wurde übernommen → zum Generator wechseln.
    if (mounted) setState(() => _index = 0);
  }

  void _onModelRelay() {
    // Eine Figur aus der Galerie soll Zubehör bekommen → in den 3D-Tab.
    if (mounted) setState(() => _index = 1);
  }

  @override
  void dispose() {
    _relay?.removeListener(_onPromptRelay);
    _modelRelay?.removeListener(_onModelRelay);
    super.dispose();
  }

  static const _destinations = [
    (icon: Icons.auto_awesome_outlined, selected: Icons.auto_awesome, label: 'Bild'),
    (icon: Icons.view_in_ar_outlined, selected: Icons.view_in_ar, label: '3D'),
    (icon: Icons.collections_outlined, selected: Icons.collections, label: 'Galerie'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Einstellungen'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final body = IndexedStack(
      index: _index,
      children: [
        GeneratorScreen(
          onOpenSettings: () => setState(() => _index = 3),
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
      appBar: AppBar(
        title: const Text('3DGenerator'),
        centerTitle: false,
      ),
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
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
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
                    label: d.label,
                  ),
              ],
            ),
    );
  }
}
