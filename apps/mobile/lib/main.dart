import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


import 'app_state.dart';
import 'data/backend.dart';
import 'data/config.dart';
import 'data/demo_backend.dart';
import 'data/language.dart';
import 'data/supabase_backend.dart';
import 'l10n/app_localizations.dart';
import 'screens/contracts_screen.dart';
import 'screens/sign_in_screen.dart';
import 'widgets/language_button.dart';
import 'theme.dart';

/// Reads the build-time configuration and starts against whatever it names.
///
/// With no configuration the app runs on demo data. That is the default so a
/// build with nothing set is obviously a demo rather than an app pointed at
/// nothing. `TrustIqConfig` refuses a service-role key outright, because an
/// app that carries one works perfectly until somebody opens the bundle.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = TrustIqConfig.fromEnvironment();

  Backend backend;
  if (config.isLive) {
    // `publishableKey` is what the SDK calls it now. Our own field keeps the
    // role-based name, because what matters about this key is what it grants.
    await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
    backend = SupabaseBackend(Supabase.instance.client, config);
  } else {
    backend = DemoBackend();
  }

  final language = await LanguageController.load();

  runApp(TrustIqApp(backend: backend, language: language));
}

class TrustIqApp extends StatefulWidget {
  TrustIqApp({super.key, required this.backend, LanguageController? language})
      : language = language ?? LanguageController.forTests();

  final Backend backend;
  final LanguageController language;

  @override
  State<TrustIqApp> createState() => _TrustIqAppState();
}

class _TrustIqAppState extends State<TrustIqApp> {
  late final AppState _state = AppState(backend: widget.backend);

  @override
  void initState() {
    super.initState();
    // Loads whatever is already there and keeps watching. A session restored
    // from storage arrives without anyone pressing sign in, and a screen that
    // waits for the button shows a returning person an empty list.
    _state.start();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.language,
      builder: (context, _) => _app(),
    );
  }

  Widget _app() {
    return MaterialApp(
      title: 'TrustIQ',
      debugShowCheckedModeBanner: false,
      // Follows the device. Nobody wants to set this twice, and a trust
      // product opening bright white at midnight is its own small betrayal.
      theme: buildTheme(TrustIqPalette.light),
      darkTheme: buildTheme(TrustIqPalette.dark),
      themeMode: ThemeMode.system,
      // Right to left comes with the Arabic locale; nothing else has to ask.
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: widget.language.locale,
      home: LanguageScope(
        controller: widget.language,
        child: ListenableBuilder(
          listenable: _state,
          builder: (context, _) => _state.isLive && !_state.signedIn
              ? SignInScreen(state: _state)
              : ContractsScreen(state: _state),
        ),
      ),
    );
  }
}
