import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/backend.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/demo_data.dart';
import 'package:trustiq_app/data/language.dart';
import 'package:trustiq_app/l10n/app_localizations.dart';
import 'package:trustiq_app/screens/new_contract_screen.dart';
import 'package:trustiq_app/theme.dart';
import 'package:trustiq_app/widgets/language_button.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// How long a contract runs.
///
/// There was no vocabulary for this at all: no start, no end, no duration, no
/// renewal. Fine for one job, useless for the arrangement a freelancer actually
/// has with a regular client.
void main() {
  late L l;
  setUpAll(() async => l = await L.delegate.load(const Locale('en')));

  group('the rules, before anything is drawn', () {
    // The same three the database holds. Kept here so the form can refuse
    // against the field somebody got wrong, rather than discovering it in a
    // snackbar after an insert failed.

    test('one-off work carries no period and no promise', () {
      expect(ContractPeriod.oneOff.hasDates, isFalse);
      expect(ContractPeriod.oneOff.renewal, RenewalPolicy.none);
      expect(ContractPeriod.oneOff.isCoherent, isTrue);
    });

    test('an end before a start is refused', () {
      const p = ContractPeriod(
        startsOn: null,
        endsOn: null,
      );
      expect(p.isCoherent, isTrue);

      final backwards = ContractPeriod(
        startsOn: DateTime(2027, 6, 1),
        endsOn: DateTime(2027, 1, 1),
      );
      expect(backwards.isCoherent, isFalse);
    });

    test('an open-ended contract cannot promise to renew', () {
      // Nothing could ever keep that promise: there is no date for it to
      // happen on and no length to roll forward by.
      final open = ContractPeriod(
        startsOn: DateTime(2027, 1, 1),
        renewal: RenewalPolicy.automatic,
      );
      expect(open.isOpenEnded, isTrue);
      expect(open.isCoherent, isFalse);
    });

    test('nothing is due on a contract that just ends', () {
      final ends = ContractPeriod(
        startsOn: DateTime(2027, 1, 1),
        endsOn: DateTime(2028, 1, 1),
      );
      expect(ends.renewsOn, isNull);

      final renews = ContractPeriod(
        startsOn: DateTime(2027, 1, 1),
        endsOn: DateTime(2028, 1, 1),
        renewal: RenewalPolicy.automatic,
      );
      expect(renews.renewsOn, DateTime(2028, 1, 1));
    });
  });

  group('the form', () {
    Widget host(AppState state) => MaterialApp(
          theme: buildTheme(TrustIqPalette.light),
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          home: LanguageScope(
            controller: LanguageController.forTests(),
            child: NewContractScreen(state: state),
          ),
        );

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('it asks for nothing by default', (tester) async {
      tall(tester);
      await tester.pumpWidget(host(AppState(backend: DemoBackend())));
      await tester.pumpAndSettle();

      // Most work is one job. A form that asks everybody for dates is a form
      // most people answer wrongly.
      expect(find.text(l.periodOneOff), findsOneWidget);
      expect(find.text(l.periodStarts.toUpperCase()), findsNothing);
    });

    testWidgets('choosing a period reveals the dates', (tester) async {
      tall(tester);
      await tester.pumpWidget(host(AppState(backend: DemoBackend())));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l.periodOverTime));
      await tester.pumpAndSettle();

      // Uppercased by SectionLabel, which is why this looks for it that way.
      expect(find.text(l.periodStarts.toUpperCase()), findsOneWidget);
      expect(find.text(l.periodEnds.toUpperCase()), findsOneWidget);
    });

    testWidgets('renewal is offered but not selectable without both dates', (tester) async {
      tall(tester);
      await tester.pumpWidget(host(AppState(backend: DemoBackend())));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l.periodOverTime));
      await tester.pumpAndSettle();

      // Greyed rather than hidden: somebody looking for it should see it, and
      // see why it is not available.
      expect(find.text(l.renewalAutomatic), findsOneWidget);
      expect(find.text(l.renewalNeedsBothDates), findsOneWidget);

      final chip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text(l.renewalAutomatic),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(chip.onSelected, isNull,
          reason: 'a chip that does nothing when pressed is worse than a disabled one');
    });

    testWidgets('a one-off contract is sent with no period', (tester) async {
      tall(tester);
      final backend = _Records();
      await tester.pumpWidget(host(AppState(backend: backend)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'someone@example.ae');
      await tester.enterText(find.byType(TextField).at(1), 'A logo');
      await tester.enterText(find.byType(TextField).at(2), 'Three concepts, two rounds.');
      await tester.enterText(find.byType(TextField).at(3), '500');
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.byType(FilledButton).last, 400,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      expect(backend.made, hasLength(1));
      expect(backend.made.single.hasDates, isFalse,
          reason: 'nothing was asked for, so nothing should have been sent');
      expect(backend.made.single.renewal, RenewalPolicy.none);
    });
  });
}

class _Records extends DemoBackend {
  final List<ContractPeriod> made = [];

  @override
  Future<Contract> createContract({
    required String description,
    required String terms,
    required Fils amount,
    required Role youAre,
    required String counterpartyEmail,
    List<DraftStage> stages = const [],
    ContractPeriod period = ContractPeriod.oneOff,
  }) async {
    made.add(period);
    return super.createContract(
      description: description,
      terms: terms,
      amount: amount,
      youAre: youAre,
      counterpartyEmail: counterpartyEmail,
      stages: stages,
      period: period,
    );
  }
}
