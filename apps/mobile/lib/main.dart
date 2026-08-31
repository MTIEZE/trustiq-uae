import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


import 'app_state.dart';
import 'data/backend.dart';
import 'data/config.dart';
import 'data/demo_backend.dart';
import 'data/language.dart';
import 'data/onboarding.dart';
import 'data/service_status.dart';
import 'data/supabase_backend.dart';
import 'l10n/app_localizations.dart';
import 'screens/contracts_screen.dart';
import 'screens/held_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/splash_screen.dart';
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

  // Fired off, not awaited. The answer is almost always "carry on", and making
  // every launch wait for a file on a marketing site to say so would spend
  // everybody's time on the rare case. It lands during the launch sequence,
  // which is time the app was going to spend anyway.
  final status = ServiceStatusGate();
  unawaited(status.check());

  runApp(TrustIqApp(
    backend: backend,
    language: language,
    onboarding: onboarding,
    status: status,
    opensWithSplash: true,
  ));
}

class TrustIqApp extends StatefulWidget {
  TrustIqApp({
    super.key,
    required this.backend,
    LanguageController? language,
    OnboardingGate? onboarding,
    ServiceStatusGate? status,
    this.opensWithSplash = false,
  })  : language = language ?? LanguageController.forTests(),
        // A gate nobody has checked reports open, so a tree built without one
        // behaves exactly like a launch where the file said carry on.
        status = status ?? ServiceStatusGate(),
        // Tests and demo trees start past the introduction. A widget test that
        // has to dismiss four panels before it can look at a contract list is
        // a test about the wrong thing.
        onboarding = onboarding ?? OnboardingGate.forTests();

  final Backend backend;
  final LanguageController language;
  final OnboardingGate onboarding;
  final ServiceStatusGate status;

  /// Whether to play the launch sequence. Off by default for the same reason
  /// the introduction is skipped: a test about the contract list should not
  /// spend 1.2 seconds watching a seal land first. main() turns it on, and
  /// splash_test.dart turns it on deliberately.
  final bool opensWithSplash;

  @override
  State<TrustIqApp> createState() => _TrustIqAppState();
}

class _TrustIqAppState extends State<TrustIqApp> {
  late final AppState _state = AppState(backend: widget.backend);
  late bool _introduced = widget.onboarding.seen;

  /// The launch sequence runs once per process, not once per rebuild.
  late bool _opened = !widget.opensWithSplash;

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

    // The language is stored on the device, because it has to be readable
    // before there is an account. The server needs its own copy, because an
    // email is written to somebody who is not holding the phone. Wired here
    // rather than inside LanguageController, which has no business knowing a
    // backend exists.
    widget.language.addListener(_rememberLanguage);
    _rememberLanguage();
  }

  void _rememberLanguage() {
    final chosen = widget.language.locale;
    if (chosen != null) _state.rememberLocale(chosen.languageCode);
  }

  @override
  void dispose() {
    widget.language.removeListener(_rememberLanguage);
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
          listenable: Listenable.merge([_state, widget.status]),
          builder: (context, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: _home(),
          ),
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
    // Before anything else, and only at the start of a process. The session
    // restore in initState is already running underneath it, so most of this
    // is time the app was going to spend anyway.
    if (!_opened) {
      return SplashScreen(onDone: () => setState(() => _opened = true));
    }
    // Ahead of the introduction and the sign-in form both. Somebody meeting
    // TrustIQ for the first time during an incident should be told there is
    // one, not walked through four panels and then failed at the account step.
    if (widget.status.held) {
      return HeldScreen(gate: widget.status);
    }
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
