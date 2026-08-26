import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'data/backend.dart';
import 'data/config.dart';
import 'data/demo_backend.dart';
import 'data/supabase_backend.dart';
import 'screens/contracts_screen.dart';
import 'screens/sign_in_screen.dart';
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

  runApp(TrustIqApp(backend: backend));
}

class TrustIqApp extends StatefulWidget {
  const TrustIqApp({super.key, required this.backend});
  final Backend backend;

  @override
  State<TrustIqApp> createState() => _TrustIqAppState();
}

class _TrustIqAppState extends State<TrustIqApp> {
  late final AppState _state = AppState(backend: widget.backend);

  @override
  void initState() {
    super.initState();
    // Demo data is already there; a live backend has nothing until someone
    // signs in, and the sign-in screen loads it.
    if (!widget.backend.isLive) _state.refresh();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrustIQ',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => _state.isLive && !_state.signedIn
            ? SignInScreen(state: _state)
            : ContractsScreen(state: _state),
      ),
    );
  }
}
