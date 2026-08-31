// Renders the app's own screens to PNGs, for the website.
//
//   flutter test tool/capture_screens.dart --update-goldens
//   node ../../scripts/collect-screens.mjs
//
// The site is about to show the app, and the honest way to do that is to show
// the app. A mockup drawn in a design tool is a picture of what somebody hoped
// it looks like; these are the widgets, the real theme, the real fonts and the
// real copy, rendered by the same code that runs on a phone.
//
// Demo data throughout. Nothing here has ever belonged to anybody: the names,
// the amounts and the dispute are the fixtures in lib/data/demo_data.dart.
//
// Not part of the suite. It writes files and proves nothing.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/language.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';
import 'package:trustiq_app/screens/contract_detail_screen.dart';
import 'package:trustiq_app/screens/contracts_screen.dart';
import 'package:trustiq_app/screens/dispute_screen.dart';
import 'package:trustiq_app/screens/new_contract_screen.dart';
import 'package:trustiq_app/screens/verify_identity_screen.dart';
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_app/widgets/language_button.dart';

/// Every font the app declares, including the one it does not declare.
///
/// A test binding ships with no fonts at all, so the first version of this
/// loaded IBM Plex by hand and produced screens where every single icon was an
/// empty square. Material Icons is not in pubspec because `uses-material-design`
/// puts it in the bundle, and the bundle is where this now reads from, so
/// nothing has to be listed twice.
Future<void> loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

void main() {
  setUp(() async => loadFonts());

  Widget host(AppState state, Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(TrustIqPalette.dark),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: LanguageScope(
          controller: LanguageController.forTests(),
          child: child,
        ),
      );

  /// A phone, at a density the web can carry.
  ///
  /// 390 by 800 logical, which is the size of the phone most people reading
  /// this will be holding, at 2x. Rendered at 3x first and the five images came
  /// to 904 KB, which is most of a second on a hotel connection for pictures
  /// nobody zooms into.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(780, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  // Reports itself as a live project while still serving demo fixtures. Three
  // things follow, and all three are what the site should show: no "demo data"
  // banner, no role switch, and therefore no app bar overflow. The switch is
  // offered only in the demo, and with it the top row is 34 pixels too wide at
  // 390pt, which is an iPhone.
  Future<AppState> ready() async {
    final state = AppState(backend: _Liveish());
    await state.start();
    return state;
  }

  testWidgets('contracts', (tester) async {
    phone(tester);
    final state = await ready();
    await tester.pumpWidget(host(state, ContractsScreen(state: state)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/contracts.png'));
  });

  testWidgets('detail', (tester) async {
    phone(tester);
    final state = await ready();
    final contract = state.contracts.firstWhere((c) => c.dispute == null);
    await tester.pumpWidget(
      host(state, ContractDetailScreen(contractId: contract.id, state: state)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/detail.png'));
  });

  testWidgets('dispute', (tester) async {
    phone(tester);
    final state = await ready();
    final contract = state.contracts.firstWhere((c) => c.dispute != null);
    await tester.pumpWidget(
      host(state, DisputeScreen(contractId: contract.id, state: state)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/dispute.png'));
  });

  testWidgets('new contract', (tester) async {
    phone(tester);
    final state = await ready();
    await tester.pumpWidget(host(state, NewContractScreen(state: state)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/new.png'));
  });

  testWidgets('verification', (tester) async {
    phone(tester);
    final state = await ready();
    await tester.pumpWidget(host(state, VerifyIdentityScreen(state: state)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/verify.png'));
  });
}

/// The demo's data, wearing a live project's face.
class _Liveish extends DemoBackend {
  @override
  bool get isLive => true;
}
