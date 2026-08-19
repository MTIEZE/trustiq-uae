import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/contracts_screen.dart';
import 'theme.dart';

void main() => runApp(const TrustIqApp());

class TrustIqApp extends StatefulWidget {
  const TrustIqApp({super.key});

  @override
  State<TrustIqApp> createState() => _TrustIqAppState();
}

class _TrustIqAppState extends State<TrustIqApp> {
  final AppState _state = AppState();

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
        builder: (context, _) => ContractsScreen(state: _state),
      ),
    );
  }
}
