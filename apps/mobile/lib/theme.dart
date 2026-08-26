import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// The app's visual language.
///
/// TrustIQ is a record people reach for when a deal has gone wrong, so the
/// design is built for credibility rather than delight. Three rules follow
/// from that, and everything below is one of them applied.
///
/// **One saturated colour.** Petrol teal carries the brand and nothing else
/// competes with it. State colours are separate and deliberately duller: a
/// status must never read as a brand flourish, and a dispute must never look
/// festive.
///
/// **Structure by line, not by shadow.** Cards are separated with a hairline
/// and a whisper of lift. Heavy shadows make an interface feel like a stack of
/// floating cards; a record should feel like a page.
///
/// **A scale, not a guess.** Type, spacing and radius each come from a fixed
/// set. Arbitrary values are how an interface stops looking made by one
/// person.
abstract final class TrustIqColors {
  /// The brand. The only saturated colour on screen.
  static const accent = Color(0xFF0D5F66);
  static const accentStrong = Color(0xFF094248);
  static const accentSoft = Color(0xFFE3EFEF);
  static const accentGlow = Color(0xFFF3F8F8);

  static const ink = Color(0xFF0E1518);
  static const inkSoft = Color(0xFF4A575E);
  static const inkFaint = Color(0xFF7C8890);

  /// Hairlines. `rule` separates, `ruleStrong` divides.
  static const rule = Color(0xFFE4E9E9);
  static const ruleStrong = Color(0xFFD1DADA);

  static const ground = Color(0xFFF5F7F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSunken = Color(0xFFF7F9F9);

  static const ok = Color(0xFF3B6438);
  static const okSoft = Color(0xFFE7F0E5);
  static const caution = Color(0xFF8A6110);
  static const cautionSoft = Color(0xFFF8F1DE);
  static const critical = Color(0xFF9E3323);
  static const criticalSoft = Color(0xFFF8E9E6);
}

/// The spacing scale. Nothing between these values.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const section = 36.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

/// The type scale.
///
/// Tracking tightens as size grows and opens up as it shrinks, which is what
/// keeps a heading from looking loose and a caption from looking cramped.
/// Line height is generous on anything a person actually reads: these screens
/// carry contract terms and someone's account of what went wrong.
abstract final class Type {
  static const display = TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.15);
  static const title = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.2);
  static const heading = TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.3);
  static const body = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, height: 1.55);
  static const bodyStrong = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.4);
  static const small = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.5);
  static const caption = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, height: 1.4);

  /// Section labels. Small, spaced, upper case: they organise rather than say.
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    height: 1.2,
  );

  /// Money and fingerprints. Tabular so digits line up down a column, and a
  /// fingerprint has to be comparable character by character.
  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    height: 1.5,
    letterSpacing: -0.1,
  );

  static const amount = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const amountLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.9,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// The one shadow in the system, and it barely registers.
const kSoftLift = [
  BoxShadow(color: Color(0x0A0E1518), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0D0E1518), blurRadius: 10, offset: Offset(0, 4)),
];

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: TrustIqColors.accent,
      primary: TrustIqColors.accent,
      surface: TrustIqColors.surface,
      error: TrustIqColors.critical,
    ),
    scaffoldBackgroundColor: TrustIqColors.ground,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: TrustIqColors.ground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: TrustIqColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: TrustIqColors.ink, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      iconTheme: IconThemeData(color: TrustIqColors.inkSoft, size: 22),
    ),

    cardTheme: CardThemeData(
      color: TrustIqColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: const BorderSide(color: TrustIqColors.rule),
      ),
    ),

    dividerTheme: const DividerThemeData(color: TrustIqColors.rule, space: 1, thickness: 1),

    // Filled rather than underlined. An underline field reads as a form to be
    // processed; a filled one reads as a place to write, which is what these
    // are: someone's account of a job that went wrong.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TrustIqColors.surfaceSunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
      hintStyle: const TextStyle(color: TrustIqColors.inkFaint, fontSize: 14.5),
      labelStyle: const TextStyle(color: TrustIqColors.inkFaint, fontSize: 14.5),
      floatingLabelStyle: const TextStyle(
        color: TrustIqColors.accent,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      helperStyle: const TextStyle(color: TrustIqColors.inkFaint, fontSize: 12, height: 1.4),
      errorStyle: const TextStyle(color: TrustIqColors.critical, fontSize: 12, height: 1.4),
      border: _field(TrustIqColors.rule),
      enabledBorder: _field(TrustIqColors.rule),
      focusedBorder: _field(TrustIqColors.accent, width: 1.6),
      errorBorder: _field(TrustIqColors.critical),
      focusedErrorBorder: _field(TrustIqColors.critical, width: 1.6),
      disabledBorder: _field(TrustIqColors.rule),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: -0.1),
        ),
        // A disabled primary action should look like it is waiting, not like a
        // dead slab of grey. Tinted, not extinguished.
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ? TrustIqColors.accentSoft : TrustIqColors.accent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ? TrustIqColors.inkFaint : Colors.white),
        overlayColor: const WidgetStatePropertyAll(Color(0x1AFFFFFF)),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: TrustIqColors.ink,
        backgroundColor: TrustIqColors.surface,
        side: const BorderSide(color: TrustIqColors.ruleStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: -0.1),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: TrustIqColors.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: TrustIqColors.accent,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 3,
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      contentTextStyle: const TextStyle(fontSize: 13.5, height: 1.4, color: Colors.white),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: TrustIqColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      titleTextStyle: Type.heading.copyWith(color: TrustIqColors.ink),
    ),

    textTheme: base.textTheme.apply(
      bodyColor: TrustIqColors.ink,
      displayColor: TrustIqColors.ink,
    ),
  );
}

OutlineInputBorder _field(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      borderSide: BorderSide(color: color, width: width),
    );

/// How a state looks and reads to a person.
///
/// The label is the plain-language one, not the wire value: a party should
/// never be shown `pending_acceptance`.
({String label, Color fg, Color bg}) transactionStateStyle(TransactionState state) {
  return switch (state) {
    TransactionState.draft =>
      (label: 'Draft', fg: TrustIqColors.inkFaint, bg: TrustIqColors.ground),
    TransactionState.pendingAcceptance =>
      (label: 'Awaiting acceptance', fg: TrustIqColors.caution, bg: TrustIqColors.cautionSoft),
    TransactionState.active =>
      (label: 'In progress', fg: TrustIqColors.accent, bg: TrustIqColors.accentSoft),
    TransactionState.delivered =>
      (label: 'Awaiting review', fg: TrustIqColors.caution, bg: TrustIqColors.cautionSoft),
    TransactionState.completed =>
      (label: 'Completed', fg: TrustIqColors.ok, bg: TrustIqColors.okSoft),
    TransactionState.disputed =>
      (label: 'Disputed', fg: TrustIqColors.critical, bg: TrustIqColors.criticalSoft),
    TransactionState.resolved =>
      (label: 'Resolved', fg: TrustIqColors.ok, bg: TrustIqColors.okSoft),
    TransactionState.declined =>
      (label: 'Declined', fg: TrustIqColors.inkFaint, bg: TrustIqColors.ground),
    TransactionState.cancelled =>
      (label: 'Cancelled', fg: TrustIqColors.inkFaint, bg: TrustIqColors.ground),
    TransactionState.expired =>
      (label: 'Expired', fg: TrustIqColors.inkFaint, bg: TrustIqColors.ground),
  };
}

/// The label on the button that fires an event, phrased for the person
/// pressing it rather than after the enum member.
String transactionEventLabel(TransactionEvent event) {
  return switch (event) {
    TransactionEvent.submit => 'Send to the other party',
    TransactionEvent.withdraw => 'Withdraw',
    TransactionEvent.accept => 'Accept the terms',
    TransactionEvent.decline => 'Decline',
    TransactionEvent.expire => 'Expire',
    TransactionEvent.markDelivered => 'Mark as delivered',
    TransactionEvent.requestRevision => 'Request changes',
    TransactionEvent.confirmDelivery => 'Confirm and close',
    TransactionEvent.openDispute => 'Open a dispute',
    TransactionEvent.resolveDispute => 'Resolve',
    TransactionEvent.cancelByAgreement => 'Cancel by agreement',
  };
}

/// Whether an action is the encouraged one, the neutral one, or the one that
/// should look like a last resort.
enum ActionTone { primary, neutral, destructive }

ActionTone transactionEventTone(TransactionEvent event) {
  return switch (event) {
    TransactionEvent.accept ||
    TransactionEvent.confirmDelivery ||
    TransactionEvent.markDelivered ||
    TransactionEvent.submit =>
      ActionTone.primary,
    TransactionEvent.openDispute ||
    TransactionEvent.decline ||
    TransactionEvent.withdraw =>
      ActionTone.destructive,
    _ => ActionTone.neutral,
  };
}

String disputeStateLabel(DisputeState state) {
  return switch (state) {
    DisputeState.open => 'Open',
    DisputeState.aiReview => 'Being analysed',
    DisputeState.proposalIssued => 'Proposal issued',
    DisputeState.accepted => 'Closed by agreement',
    DisputeState.escalated => 'With a human reviewer',
    DisputeState.humanReview => 'Under human review',
    DisputeState.resolvedByHuman => 'Decided by a reviewer',
    DisputeState.withdrawn => 'Withdrawn',
  };
}

String decisionLabel(ResolutionDecision decision) {
  return switch (decision) {
    ResolutionDecision.releaseToSeller => 'Everything to the seller',
    ResolutionDecision.refundToBuyer => 'Everything refunded to the buyer',
    ResolutionDecision.split => 'Split between both parties',
  };
}
