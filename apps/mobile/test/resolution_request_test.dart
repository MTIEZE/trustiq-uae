import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/backend.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/demo_data.dart';
import 'package:trustiq_core/trustiq_core.dart';
import 'package:trustiq_app/data/language.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';
import 'package:trustiq_app/screens/dispute_screen.dart';
import 'package:trustiq_app/screens/verify_identity_screen.dart';
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_app/widgets/language_button.dart';

/// Asking the model, which nothing in the app could do until now.
///
/// The pipeline existed, was validated, was audited, and had run five times.
/// Every one of those runs was started by a script on a laptop. A dispute
/// opened in the app stayed open, and the thing that makes TrustIQ different
/// from a contract template was unreachable by the people it is for.
void main() {
  late L l;
  setUpAll(() async => l = await L.delegate.load(const Locale('en')));

  Widget host(AppState state, String contractId) => MaterialApp(
        theme: buildTheme(TrustIqPalette.light),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: LanguageScope(
          controller: LanguageController.forTests(),
          child: DisputeScreen(contractId: contractId, state: state),
        ),
      );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// A case that is open with both accounts in, which is the only moment the
  /// model can be asked. The demo's own dispute sits at `proposalIssued`,
  /// which is one step past this.
  Future<(AppState, String)> openCase(_Gate backend) async {
    final state = AppState(backend: backend);
    await state.start();
    final contract = state.contracts.firstWhere((c) => c.dispute != null);
    return (state, contract.id);
  }

  testWidgets('a verified party is offered the button', (tester) async {
    tall(tester);
    final backend = _Gate(const ResolutionEligibility.allowed());
    final (state, id) = await openCase(backend);

    await tester.pumpWidget(host(state, id));
    await tester.pumpAndSettle();

    expect(find.text(l.askResolutionAction), findsOneWidget);

    // Said before the press. Evidence filed afterwards is evidence nobody read.
    expect(find.text(l.askResolutionOnce), findsOneWidget);
  });

  testWidgets('pressing it asks, once', (tester) async {
    tall(tester);
    final backend = _Gate(const ResolutionEligibility.allowed());
    final (state, id) = await openCase(backend);

    await tester.pumpWidget(host(state, id));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l.askResolutionAction));
    await tester.pumpAndSettle();

    expect(backend.runs, [id]);
  });

  testWidgets('an unverified party is told why, and shown the way there', (tester) async {
    tall(tester);
    final backend = _Gate(
      const ResolutionEligibility.blocked(ResolutionBlock.notVerified));
    final (state, id) = await openCase(backend);

    await tester.pumpWidget(host(state, id));
    await tester.pumpAndSettle();

    expect(find.text(l.askResolutionAction), findsNothing,
        reason: 'offering a button the server refuses is worse than no button');
    expect(find.text(l.resolutionNeedsVerified), findsOneWidget);

    // The rule is a trust decision, not a technicality, so it says why.
    expect(find.text(l.resolutionNeedsVerifiedWhy), findsOneWidget);

    await tester.tap(find.text(l.resolutionVerifyAction));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyIdentityScreen), findsOneWidget,
        reason: 'a refusal that does not lead anywhere is a dead end');
    expect(backend.runs, isEmpty);
  });

  testWidgets('coming back verified clears the refusal', (tester) async {
    tall(tester);
    final backend = _Gate(
      const ResolutionEligibility.blocked(ResolutionBlock.notVerified));
    final (state, id) = await openCase(backend);

    await tester.pumpWidget(host(state, id));
    await tester.pumpAndSettle();
    expect(find.text(l.resolutionNeedsVerified), findsOneWidget);

    backend.verdict = const ResolutionEligibility.allowed();
    await tester.tap(find.text(l.resolutionVerifyAction));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(VerifyIdentityScreen))).pop();
    await tester.pumpAndSettle();

    expect(find.text(l.askResolutionAction), findsOneWidget,
        reason: 'coming back to the same refusal would be its own small insult');
  });

  testWidgets('a dispute already read offers nothing at all', (tester) async {
    tall(tester);
    final backend = _Gate(
      const ResolutionEligibility.blocked(ResolutionBlock.alreadyRun, 'proposal_issued'));
    final (state, id) = await openCase(backend);

    await tester.pumpWidget(host(state, id));
    await tester.pumpAndSettle();

    expect(find.text(l.askResolutionAction), findsNothing);
    expect(find.text(l.resolutionNeedsVerified), findsNothing);
  });

  group('when the check itself fails', () {
    test('the button is hidden rather than offered and refused', () async {
      // The harmless reading of not knowing. Offering it and failing after
      // somebody has got their hopes up is the other one.
      final state = AppState(backend: _CheckThrows());
      final may = await state.mayRequestResolution('anything');
      expect(may.allowed, isFalse);
      expect(may.block, ResolutionBlock.alreadyRun);
    });
  });
}

/// A backend whose verdict a test controls, and which records what it was
/// asked to run.
class _Gate extends DemoBackend {
  _Gate(this.verdict);

  ResolutionEligibility verdict;
  final List<String> runs = [];

  /// Rewinds the demo's dispute to `open` with both sides given. Everything
  /// else about the contract is the demo's, so the screen renders the same way
  /// it does for a real one.
  @override
  Future<List<Contract>> loadContracts() async {
    final contracts = await super.loadContracts();
    return [
      for (final c in contracts)
        if (c.dispute == null)
          c
        else
          Contract(
            id: c.id,
            reference: c.reference,
            state: c.state,
            description: c.description,
            terms: c.terms,
            totalAmount: c.totalAmount,
            buyer: c.buyer,
            seller: c.seller,
            createdAt: c.createdAt,
            acceptanceDeadline: c.acceptanceDeadline,
            milestones: c.milestones,
            timeline: c.timeline,
            evidence: c.evidence,
            dispute: Dispute(
              id: c.dispute!.id,
              state: DisputeState.open,
              openedByRole: c.dispute!.openedByRole,
              buyerClaim: c.dispute!.buyerClaim,
              sellerClaim: c.dispute!.sellerClaim,
            ),
          ),
    ];
  }

  @override
  Future<ResolutionEligibility> mayRequestResolution(String contractId) async => verdict;

  @override
  Future<ResolutionOutcome> requestResolution(String contractId) async {
    runs.add(contractId);
    return const ResolutionProposed();
  }
}

class _CheckThrows extends DemoBackend {
  @override
  Future<ResolutionEligibility> mayRequestResolution(String contractId) async =>
      throw Exception('Failed host lookup');
}
