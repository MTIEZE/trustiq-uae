import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// The app's visual language.
///
/// Petrol teal carries the brand; everything else is a cool neutral so the
/// accent is the only saturated thing on screen. State colours are separate
/// from the accent on purpose: a status must never read as a brand flourish.
abstract final class TrustIqColors {
  static const accent = Color(0xFF0D5F66);
  static const accentSoft = Color(0xFFE1EDED);

  static const ink = Color(0xFF10171B);
  static const inkSoft = Color(0xFF4A575E);
  static const inkFaint = Color(0xFF7C8890);
  static const rule = Color(0xFFD5DCDC);
  static const ground = Color(0xFFF4F6F6);
  static const surface = Color(0xFFFFFFFF);

  static const ok = Color(0xFF3B6438);
  static const okSoft = Color(0xFFE5EEE3);
  static const caution = Color(0xFF8A6110);
  static const cautionSoft = Color(0xFFF7EFDC);
  static const critical = Color(0xFF9E3323);
  static const criticalSoft = Color(0xFFF7E7E4);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: TrustIqColors.accent,
      primary: TrustIqColors.accent,
      surface: TrustIqColors.surface,
    ),
    scaffoldBackgroundColor: TrustIqColors.ground,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: TrustIqColors.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: TrustIqColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: TrustIqColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TrustIqColors.rule),
      ),
    ),
    dividerTheme: const DividerThemeData(color: TrustIqColors.rule, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: TrustIqColors.ink,
        side: const BorderSide(color: TrustIqColors.rule),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: TrustIqColors.ink,
      displayColor: TrustIqColors.ink,
    ),
  );
}

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
