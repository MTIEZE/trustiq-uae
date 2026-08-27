import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


import 'app_state.dart';
import 'data/backend.dart';
import 'data/config.dart';
import 'data/demo_backend.dart';
import 'data/language.dart';
import 'data/onboarding.dart';
import 'data/supabase_backend.dart';
import 'l10n/app_localizations.dart';
import 'screens/contracts_screen.dart';
import 'screens/onboarding_screen.dart';
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
  final onboarding = await OnboardingGate.load();

  runApp(TrustIqApp(backend: backend, language: language, onboarding: onboarding));
}

class TrustIqApp extends StatefulWidget {
  TrustIqApp({
    super.key,
    required this.backend,
    LanguageController? language,
    OnboardingGate? onboarding,
  })  : language = language ?? LanguageController.forTests(),
        // Tests and demo trees start past the introduction. A widget test that
        // has to dismiss four panels before it can look at a contract list is
        // a test about the wrong thing.
        onboarding = onboarding ?? OnboardingGate.forTests();

  final Backend backend;
  final LanguageController language;
  final OnboardingGate onboarding;

  @override
  State<TrustIqApp> createState() => _TrustIqAppState();
}

class _TrustIqAppState extends State<TrustIqApp> {
  late final AppState _state = AppState(backend: widget.backend);
  late bool _introduced = widget.onboarding.seen;

  void _finishOnboarding() {
    widget.onboarding.markSeen();
    setState(() => _introduced = true);
  }

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
          builder: (context, _) => _home(),
        ),
      ),
    );
  }

  /// The introduction comes first, before the account form.
  ///
  /// Someone who installed this on a recommendation knows nothing about
  /// TrustIQ, and asking them for an email address before saying what the app
  /// does is asking for trust before offering any. Both buttons at the end
  /// lead to the same place today, because the sign-in screen is one form for
  /// signing in and signing up; they are kept apart so that stops being true
  /// without this screen having to change.
  Widget _home() {
    if (!_introduced) {
      return OnboardingScreen(
        onFinished: _finishOnboarding,
        onSignIn: _finishOnboarding,
      );
    }
    if (_state.isLive && !_state.signedIn) return SignInScreen(state: _state);
    return ContractsScreen(state: _state);
  }
}
