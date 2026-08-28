import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trustiq_core/trustiq_core.dart';

import 'app_state.dart';
import 'l10n/app_localizations.dart';

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
/// The palette, as a theme extension so it can differ by brightness.
///
/// The names are TrustIQ's own rather than Material's, because Material has no
/// slot for "caution" or "ok" and forcing them into tertiary and secondary
/// would make every call site lie about what it is asking for.
///
/// Read it as `context.c`. Doing that means most colours are no longer
/// compile-time constants, which is the real cost of supporting two themes and
/// is why `const` disappears from a lot of widgets below.
@immutable
class TrustIqPalette extends ThemeExtension<TrustIqPalette> {
  const TrustIqPalette({
    required this.isDark,
    required this.accent,
    required this.onAccent,
    required this.accentStrong,
    required this.accentSoft,
    required this.accentGlow,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.rule,
    required this.ruleStrong,
    required this.ground,
    required this.surface,
    required this.surfaceSunken,
    required this.ok,
    required this.okSoft,
    required this.caution,
    required this.cautionSoft,
    required this.critical,
    required this.criticalSoft,
  });

  /// Which side of the theme this is. Only the lift reads it: a shadow that
  /// works on white is invisible on near-black, and one that works on
  /// near-black is a smear on white.
  final bool isDark;

  final Color accent;

  /// What sits on top of the accent: a label in a filled button, a spinner, a
  /// FAB icon. White in the light theme and near-black in the dark one,
  /// because the dark accent is a light teal and white on it is unreadable.
  /// Every widget that paints something onto the accent must use this rather
  /// than assuming white, which is what four of them were doing.
  final Color onAccent;

  final Color accentStrong;
  final Color accentSoft;
  final Color accentGlow;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color rule;
  final Color ruleStrong;
  final Color ground;
  final Color surface;
  final Color surfaceSunken;
  final Color ok;
  final Color okSoft;
  final Color caution;
  final Color cautionSoft;
  final Color critical;
  final Color criticalSoft;

  /// Petrol teal on cool neutrals. The accent is the only saturated colour.
  static const light = TrustIqPalette(
    isDark: false,
    accent: Color(0xFF0D5F66),
    onAccent: Color(0xFFFFFFFF),
    accentStrong: Color(0xFF094248),
    accentSoft: Color(0xFFE3EFEF),
    accentGlow: Color(0xFFF3F8F8),
    ink: Color(0xFF0E1518),
    inkSoft: Color(0xFF4A575E),
    inkFaint: Color(0xFF7C8890),
    rule: Color(0xFFE4E9E9),
    ruleStrong: Color(0xFFD1DADA),
    ground: Color(0xFFF5F7F7),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF7F9F9),
    ok: Color(0xFF3B6438),
    okSoft: Color(0xFFE7F0E5),
    caution: Color(0xFF8A6110),
    cautionSoft: Color(0xFFF8F1DE),
    critical: Color(0xFF9E3323),
    criticalSoft: Color(0xFFF8E9E6),
  );

  /// Not an inversion.
  ///
  /// The light accent is too dark to read on a dark ground, so the accent
  /// lifts rather than flips, and `accentStrong` becomes lighter than `accent`
  /// instead of darker: on a dark surface, emphasis means more light.
  ///
  /// The ground is a desaturated blue-green rather than black. Pure black
  /// against light text is harsh for long reading, and these screens carry
  /// contract terms and someone's account of what went wrong.
  ///
  /// The state colours are lifted and desaturated together, so a dispute still
  /// reads as sober rather than as a neon warning.
  static const dark = TrustIqPalette(
    isDark: true,
    accent: Color(0xFF4FBFC7),
    onAccent: Color(0xFF06191B),
    accentStrong: Color(0xFF86D8DE),
    accentSoft: Color(0xFF10312F),
    accentGlow: Color(0xFF101A1B),
    ink: Color(0xFFE9EEEE),
    inkSoft: Color(0xFFA6B3B5),
    inkFaint: Color(0xFF78868A),
    rule: Color(0xFF222B2D),
    ruleStrong: Color(0xFF2F3B3D),
    ground: Color(0xFF0D1214),
    surface: Color(0xFF151C1E),
    surfaceSunken: Color(0xFF1A2325),
    ok: Color(0xFF7FBE7A),
    okSoft: Color(0xFF17281A),
    caution: Color(0xFFD9A94E),
    cautionSoft: Color(0xFF2A2314),
    critical: Color(0xFFE38878),
    criticalSoft: Color(0xFF2E1A17),
  );

  /// The one shadow in the system, and it barely registers.
  ///
  /// Heavier and tighter in the dark, where a soft wide shadow does nothing
  /// at all and only a close dark one reads as separation.
  List<BoxShadow> get lift => isDark
      ? const [
          BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 5)),
        ]
      : const [
          BoxShadow(color: Color(0x0A0E1518), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0D0E1518), blurRadius: 10, offset: Offset(0, 4)),
        ];

  @override
  TrustIqPalette copyWith({
    bool? isDark,
    Color? accent,
    Color? onAccent,
    Color? accentStrong,
    Color? accentSoft,
    Color? accentGlow,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? rule,
    Color? ruleStrong,
    Color? ground,
    Color? surface,
    Color? surfaceSunken,
    Color? ok,
    Color? okSoft,
    Color? caution,
    Color? cautionSoft,
    Color? critical,
    Color? criticalSoft,
  }) {
    return TrustIqPalette(
      isDark: isDark ?? this.isDark,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentStrong: accentStrong ?? this.accentStrong,
      accentSoft: accentSoft ?? this.accentSoft,
      accentGlow: accentGlow ?? this.accentGlow,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkFaint: inkFaint ?? this.inkFaint,
      rule: rule ?? this.rule,
      ruleStrong: ruleStrong ?? this.ruleStrong,
      ground: ground ?? this.ground,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      ok: ok ?? this.ok,
      okSoft: okSoft ?? this.okSoft,
      caution: caution ?? this.caution,
      cautionSoft: cautionSoft ?? this.cautionSoft,
      critical: critical ?? this.critical,
      criticalSoft: criticalSoft ?? this.criticalSoft,
    );
  }

  @override
  TrustIqPalette lerp(TrustIqPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return TrustIqPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentStrong: mix(accentStrong, other.accentStrong),
      accentSoft: mix(accentSoft, other.accentSoft),
      accentGlow: mix(accentGlow, other.accentGlow),
      ink: mix(ink, other.ink),
      inkSoft: mix(inkSoft, other.inkSoft),
      inkFaint: mix(inkFaint, other.inkFaint),
      rule: mix(rule, other.rule),
      ruleStrong: mix(ruleStrong, other.ruleStrong),
      ground: mix(ground, other.ground),
      surface: mix(surface, other.surface),
      surfaceSunken: mix(surfaceSunken, other.surfaceSunken),
      ok: mix(ok, other.ok),
      okSoft: mix(okSoft, other.okSoft),
      caution: mix(caution, other.caution),
      cautionSoft: mix(cautionSoft, other.cautionSoft),
      critical: mix(critical, other.critical),
      criticalSoft: mix(criticalSoft, other.criticalSoft),
    );
  }
}

/// What to show a person when a call failed.
///
/// One place, because the alternative is each screen deciding for itself
/// whether a raw exception is fit to display, and the answer is always no.
({String title, String? detail})? describeFailure(AppState state, L l) {
  final message = state.error;
  if (message != null) return (title: message, detail: null);

  return switch (state.failure) {
    Failure.network => (title: l.noConnection, detail: l.noConnectionBody),
    Failure.unexpected => (title: l.somethingWentWrong, detail: l.somethingWentWrongBody),
    null => null,
  };
}

/// A date and time, in the reader's language and calendar conventions.
///
/// This replaced a hardcoded list of English month abbreviations. The drift
/// guard never saw it: it looks for quoted strings of seven characters or
/// more, and 'Jan' is three, so an Arabic reader got Arabic everywhere except
/// the one place a contract records when something happened.
String formatMoment(DateTime at, Locale locale) =>
    DateFormat.yMMMd(locale.toLanguageTag()).add_Hm().format(at.toLocal());

/// The same, without the time, for a line that only needs the day.
String formatDay(DateTime at, Locale locale) =>
    DateFormat.yMMMd(locale.toLanguageTag()).format(at.toLocal());

/// Plain words for one recorded transition, in the reader's language.
///
/// Written from the actor rather than from a name, because the event log
/// records who acted as a role and the person reading it may be either side.
///
/// This used to build an English sentence at the moment a row was parsed,
/// before there was a locale to build it in, so the contract history stayed in
/// English no matter what the rest of the app was doing. The drift guard did
/// not catch it because it only reads lib/screens, and this lived in lib/data.
String describeEvent(TransactionEvent event, Actor actor, L l) {
  final who = switch (actor) {
    Actor.buyer => l.whoBuyer,
    Actor.seller => l.whoSeller,
    Actor.system => l.whoSystem,
  };
  return switch (event) {
    TransactionEvent.submit => l.evSubmit(who),
    TransactionEvent.accept => l.evAccept(who),
    TransactionEvent.decline => l.evDecline(who),
    TransactionEvent.withdraw => l.evWithdraw(who),
    TransactionEvent.markDelivered => l.evMarkDelivered(who),
    TransactionEvent.requestRevision => l.evRequestRevision(who),
    TransactionEvent.confirmDelivery => l.evConfirmDelivery(who),
    TransactionEvent.openDispute => l.evOpenDispute(who),
    TransactionEvent.resolveDispute => l.evResolveDispute(who),
    TransactionEvent.cancelByAgreement => l.evCancelByAgreement(who),
    // Nobody expired it, so no actor appears.
    TransactionEvent.expire => l.evExpire,
  };
}

/// The same for the dispute machine.
String describeDisputeEvent(DisputeEvent event, Actor actor, L l) {
  final who = switch (actor) {
    Actor.buyer => l.whoBuyer,
    Actor.seller => l.whoSeller,
    Actor.system => l.whoSystem,
  };
  return switch (event) {
    DisputeEvent.submitForAi => l.devSubmitForAi,
    DisputeEvent.issueProposal => l.devIssueProposal,
    DisputeEvent.acceptProposal => l.devAcceptProposal(who),
    DisputeEvent.rejectProposal => l.devRejectProposal(who),
    DisputeEvent.escalate => l.devEscalate,
    DisputeEvent.assignReviewer => l.devAssignReviewer,
    DisputeEvent.issueHumanResolution => l.devIssueHumanResolution,
    DisputeEvent.withdrawDispute => l.devWithdrawDispute(who),
  };
}

extension TrustIqPaletteContext on BuildContext {
  /// The palette for the current theme. Short because it appears everywhere.
  TrustIqPalette get c =>
      Theme.of(this).extension<TrustIqPalette>() ?? TrustIqPalette.light;
}

/// The spacing scale. Nothing between these values.
abstract final class Space {
  static const xs = 4.0;

  /// The gap between an icon and the word next to it. Small enough that they
  /// read as one thing, which 8 does not.
  static const inline = 6.0;

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const section = 36.0;
}

/// Icon sizes.
///
/// There were ten of these across the screens: 13, 14, 15, 16, 17, 18, 19, 20,
/// 26 and 40. The differences between most of them are invisible and the
/// inconsistency is not, so they collapse to five, chosen by what the icon sits
/// next to rather than by eye.
abstract final class IconSize {
  /// Beside a caption or a label.
  static const sm = 14.0;

  /// Beside body text. The workhorse.
  static const md = 17.0;

  /// In a button or a header, where it stands alone.
  static const lg = 20.0;

  /// The subject of its own block, like a file picker.
  static const xl = 26.0;

  /// An empty state, where the icon is the only thing on screen.
  static const hero = 40.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

/// The typeface.
///
/// IBM Plex Sans, bundled in assets rather than fetched at runtime. Two
/// reasons, and neither is taste. A font downloaded on first launch means a
/// flash of a different face and a request to a third party, which is a poor
/// look for a product whose pitch is that it does not leak anything. And IBM
/// Plex Sans Arabic exists and is drawn as its companion, so the day TrustIQ
/// ships in Arabic the typography extends instead of being redone.
const kFontFamily = 'IBMPlexSans';

/// The Arabic companion. Reached through the fallback chain rather than
/// selected by locale, so it also covers an Arabic name inside an English
/// sentence, which is the common case here.
const kFontFamilyArabic = 'IBMPlexSansArabic';

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

  /// Fingerprints. The platform monospace rather than a second bundled family:
  /// a hash has to be comparable character by character, and any monospace
  /// does that for 200 KB less.
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

ThemeData buildTheme([TrustIqPalette palette = TrustIqPalette.light]) {
  final c = palette;
  final brightness = c.isDark ? Brightness.dark : Brightness.light;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    // Set once, here. Every text style in the app inherits it, so there is no
    // second place where a family could be forgotten.
    fontFamily: kFontFamily,
    // Arabic glyphs fall through to the companion face automatically, per
    // glyph. That means a sentence mixing both scripts renders correctly
    // without the theme having to know which language is on, and the two faces
    // are drawn to sit at the same weight and rhythm.
    fontFamilyFallback: const [kFontFamilyArabic],
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      primary: c.accent,
      surface: c.surface,
      error: c.critical,
    ),
    scaffoldBackgroundColor: c.ground,
    splashFactory: InkSparkle.splashFactory,
    extensions: [c],
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: c.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      iconTheme: IconThemeData(color: c.inkSoft, size: 22),
    ),

    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: c.rule),
      ),
    ),

    dividerTheme: DividerThemeData(color: c.rule, space: 1, thickness: 1),

    // Filled rather than underlined. An underline field reads as a form to be
    // processed; a filled one reads as a place to write, which is what these
    // are: someone's account of a job that went wrong.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceSunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
      hintStyle: TextStyle(color: c.inkFaint, fontSize: 14.5),
      labelStyle: TextStyle(color: c.inkFaint, fontSize: 14.5),
      floatingLabelStyle: TextStyle(color: c.accent, fontSize: 13, fontWeight: FontWeight.w600),
      helperStyle: TextStyle(color: c.inkFaint, fontSize: 12, height: 1.4),
      errorStyle: TextStyle(color: c.critical, fontSize: 12, height: 1.4),
      border: _field(c.rule),
      enabledBorder: _field(c.rule),
      focusedBorder: _field(c.accent, width: 1.6),
      errorBorder: _field(c.critical),
      focusedErrorBorder: _field(c.critical, width: 1.6),
      disabledBorder: _field(c.rule),
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
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? c.accentSoft : c.accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? c.inkFaint : c.onAccent,
        ),
        overlayColor: WidgetStatePropertyAll(
          (c.isDark ? Colors.black : Colors.white).withValues(alpha: 0.12),
        ),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: c.ink,
        backgroundColor: c.surface,
        side: BorderSide(color: c.ruleStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: -0.1),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.onAccent,
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
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      titleTextStyle: Type.heading.copyWith(color: c.ink),
    ),

    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
  );
}

OutlineInputBorder _field(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      borderSide: BorderSide(color: color, width: width),
    );

/// How a state looks and reads to a person.
///
/// The label is the plain-language one in the reader's language, never the
/// wire value: a party should not be shown `pending_acceptance` in any script.
({String label, Color fg, Color bg}) transactionStateStyle(
  TransactionState state,
  TrustIqPalette c,
  L l,
) {
  return switch (state) {
    TransactionState.draft => (label: l.stateDraft, fg: c.inkFaint, bg: c.surfaceSunken),
    TransactionState.pendingAcceptance =>
      (label: l.stateAwaitingAcceptance, fg: c.caution, bg: c.cautionSoft),
    TransactionState.active => (label: l.stateInProgress, fg: c.accent, bg: c.accentSoft),
    TransactionState.delivered =>
      (label: l.stateAwaitingReview, fg: c.caution, bg: c.cautionSoft),
    TransactionState.completed => (label: l.stateCompleted, fg: c.ok, bg: c.okSoft),
    TransactionState.disputed => (label: l.stateDisputed, fg: c.critical, bg: c.criticalSoft),
    TransactionState.resolved => (label: l.stateResolved, fg: c.ok, bg: c.okSoft),
    TransactionState.declined => (label: l.stateDeclined, fg: c.inkFaint, bg: c.surfaceSunken),
    TransactionState.cancelled => (label: l.stateCancelled, fg: c.inkFaint, bg: c.surfaceSunken),
    TransactionState.expired => (label: l.stateExpired, fg: c.inkFaint, bg: c.surfaceSunken),
  };
}

/// The label on the button that fires an event, phrased for the person
/// pressing it rather than after the enum member.
String transactionEventLabel(TransactionEvent event, L l) {
  return switch (event) {
    TransactionEvent.submit => l.eventSubmit,
    TransactionEvent.withdraw => l.eventWithdraw,
    TransactionEvent.accept => l.eventAccept,
    TransactionEvent.decline => l.eventDecline,
    TransactionEvent.expire => l.eventExpire,
    TransactionEvent.markDelivered => l.eventMarkDelivered,
    TransactionEvent.requestRevision => l.eventRequestRevision,
    TransactionEvent.confirmDelivery => l.eventConfirmDelivery,
    TransactionEvent.openDispute => l.eventOpenDispute,
    TransactionEvent.resolveDispute => l.eventResolveDispute,
    TransactionEvent.cancelByAgreement => l.eventCancelByAgreement,
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

String disputeStateLabel(DisputeState state, L l) {
  return switch (state) {
    DisputeState.open => l.disputeOpen,
    DisputeState.aiReview => l.disputeBeingAnalysed,
    DisputeState.proposalIssued => l.disputeProposalIssued,
    DisputeState.accepted => l.disputeClosedByAgreement,
    DisputeState.escalated => l.disputeEscalated,
    DisputeState.humanReview => l.disputeUnderHumanReview,
    DisputeState.resolvedByHuman => l.disputeDecidedByReviewer,
    DisputeState.withdrawn => l.disputeWithdrawn,
  };
}

String decisionLabel(ResolutionDecision decision, L l) {
  return switch (decision) {
    ResolutionDecision.releaseToSeller => l.decisionReleaseToSeller,
    ResolutionDecision.refundToBuyer => l.decisionRefundToBuyer,
    ResolutionDecision.split => l.decisionSplit,
  };
}

/// The localisations for the current context.
///
/// Paired with `context.c` for the palette, so a build method opens with the
/// two things that vary by who is looking: their theme and their language.
extension TrustIqL10nContext on BuildContext {
  L get l => L.of(this);
}
