import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/demo_data.dart';
import 'package:trustiq_app/data/language.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';
import 'package:trustiq_app/screens/contract_detail_screen.dart';
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_app/widgets/language_button.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// Saying why an action is not there.
///
/// The screen listed what was possible and nothing else, so somebody looking
/// for "open a dispute" on a contract nobody had accepted concluded the button
/// had been removed. It had not: the transition table allows it from `active`
/// and `delivered` and from nowhere else, which is correct and which no user
/// can be expected to guess.
void main() {
  late L l;
  setUpAll(() async => l = await L.delegate.load(const Locale('en')));

  Widget host(AppState state, String id) => MaterialApp(
        theme: buildTheme(TrustIqPalette.light),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: LanguageScope(
          controller: LanguageController.forTests(),
          child: ContractDetailScreen(contractId: id, state: state),
        ),
      );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('a contract nobody has accepted says the dispute comes later', (tester) async {
    tall(tester);
    final backend = _At(TransactionState.pendingAcceptance);
    final state = AppState(backend: backend);
    await state.start();

    await tester.pumpWidget(host(state, state.contracts.first.id));
    await tester.pumpAndSettle();

    expect(find.text(l.whatComesLater.toUpperCase()), findsOneWidget);
    expect(
      find.text(l.laterOnce(
        transactionEventLabel(TransactionEvent.openDispute, l),
        l.stateInProgress.toLowerCase(),
      )),
      findsOneWidget,
      reason: 'the answer to "where is the button" is a sentence, not silence',
    );
  });

  testWidgets('a finished contract promises nothing', (tester) async {
    tall(tester);
    final backend = _At(TransactionState.completed);
    final state = AppState(backend: backend);
    await state.start();

    await tester.pumpWidget(host(state, state.contracts.first.id));
    await tester.pumpAndSettle();

    // There is no later on a contract that is over, and inventing one would be
    // the same failure in the other direction.
    expect(find.text(l.whatComesLater.toUpperCase()), findsNothing);
  });

  testWidgets('what the other side has to do is named, not left blank', (tester) async {
    tall(tester);
    // Active, viewed by the buyer: marking delivery is the seller's move and
    // nobody else's, which the screen used to express by showing nothing.
    final backend = _At(TransactionState.active);
    final state = AppState(backend: backend);
    await state.start();
    final contract = state.contracts.first;

    await tester.pumpWidget(host(state, contract.id));
    await tester.pumpAndSettle();

    expect(find.text(l.theirMove(contract.seller.name).toUpperCase()), findsOneWidget);
    expect(find.textContaining(transactionEventLabel(TransactionEvent.markDelivered, l)),
        findsWidgets);
  });
}

/// One contract, parked in whatever state a test needs.
class _At extends DemoBackend {
  _At(this.parked);

  final TransactionState parked;

  @override
  Future<List<Contract>> loadContracts() async {
    final all = await super.loadContracts();
    final c = all.firstWhere((x) => x.dispute == null);
    return [
      Contract(
        id: c.id,
        reference: c.reference,
        state: parked,
        description: c.description,
        terms: c.terms,
        totalAmount: c.totalAmount,
        buyer: c.buyer,
        seller: c.seller,
        createdAt: c.createdAt,
      ),
    ];
  }
}
