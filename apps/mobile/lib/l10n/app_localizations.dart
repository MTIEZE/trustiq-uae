import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// The product name. Not translated: it is the brand.
  ///
  /// In en, this message translates to:
  /// **'TrustIQ'**
  String get appName;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Each language names itself in its own script, so somebody who cannot read the current one can still find theirs.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// Contract states, in plain language. A party is never shown the wire value.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get stateDraft;

  /// No description provided for @stateAwaitingAcceptance.
  ///
  /// In en, this message translates to:
  /// **'Awaiting acceptance'**
  String get stateAwaitingAcceptance;

  /// No description provided for @stateInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get stateInProgress;

  /// No description provided for @stateAwaitingReview.
  ///
  /// In en, this message translates to:
  /// **'Awaiting review'**
  String get stateAwaitingReview;

  /// No description provided for @stateCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get stateCompleted;

  /// No description provided for @stateDisputed.
  ///
  /// In en, this message translates to:
  /// **'Disputed'**
  String get stateDisputed;

  /// No description provided for @stateResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get stateResolved;

  /// No description provided for @stateDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get stateDeclined;

  /// No description provided for @stateCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get stateCancelled;

  /// No description provided for @stateExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get stateExpired;

  /// Button labels, phrased for the person pressing them rather than after the enum member.
  ///
  /// In en, this message translates to:
  /// **'Send to the other party'**
  String get eventSubmit;

  /// No description provided for @eventWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get eventWithdraw;

  /// No description provided for @eventAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept the terms'**
  String get eventAccept;

  /// No description provided for @eventDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get eventDecline;

  /// No description provided for @eventExpire.
  ///
  /// In en, this message translates to:
  /// **'Expire'**
  String get eventExpire;

  /// No description provided for @eventMarkDelivered.
  ///
  /// In en, this message translates to:
  /// **'Mark as delivered'**
  String get eventMarkDelivered;

  /// No description provided for @eventRequestRevision.
  ///
  /// In en, this message translates to:
  /// **'Request changes'**
  String get eventRequestRevision;

  /// No description provided for @eventConfirmDelivery.
  ///
  /// In en, this message translates to:
  /// **'Confirm and close'**
  String get eventConfirmDelivery;

  /// No description provided for @eventOpenDispute.
  ///
  /// In en, this message translates to:
  /// **'Open a dispute'**
  String get eventOpenDispute;

  /// No description provided for @eventResolveDispute.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get eventResolveDispute;

  /// No description provided for @eventCancelByAgreement.
  ///
  /// In en, this message translates to:
  /// **'Cancel by agreement'**
  String get eventCancelByAgreement;

  /// No description provided for @disputeOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get disputeOpen;

  /// No description provided for @disputeBeingAnalysed.
  ///
  /// In en, this message translates to:
  /// **'Being analysed'**
  String get disputeBeingAnalysed;

  /// No description provided for @disputeProposalIssued.
  ///
  /// In en, this message translates to:
  /// **'Proposal issued'**
  String get disputeProposalIssued;

  /// No description provided for @disputeClosedByAgreement.
  ///
  /// In en, this message translates to:
  /// **'Closed by agreement'**
  String get disputeClosedByAgreement;

  /// No description provided for @disputeEscalated.
  ///
  /// In en, this message translates to:
  /// **'With a human reviewer'**
  String get disputeEscalated;

  /// No description provided for @disputeUnderHumanReview.
  ///
  /// In en, this message translates to:
  /// **'Under human review'**
  String get disputeUnderHumanReview;

  /// No description provided for @disputeDecidedByReviewer.
  ///
  /// In en, this message translates to:
  /// **'Decided by a reviewer'**
  String get disputeDecidedByReviewer;

  /// No description provided for @disputeWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get disputeWithdrawn;

  /// No description provided for @decisionReleaseToSeller.
  ///
  /// In en, this message translates to:
  /// **'Everything to the seller'**
  String get decisionReleaseToSeller;

  /// No description provided for @decisionRefundToBuyer.
  ///
  /// In en, this message translates to:
  /// **'Everything refunded to the buyer'**
  String get decisionRefundToBuyer;

  /// No description provided for @decisionSplit.
  ///
  /// In en, this message translates to:
  /// **'Split between both parties'**
  String get decisionSplit;

  /// No description provided for @roleBuyer.
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get roleBuyer;

  /// No description provided for @roleSeller.
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get roleSeller;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @unverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get unverified;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// No description provided for @signUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get signUpTitle;

  /// No description provided for @resetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get resetTitle;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your contracts and disputes, where you left them.'**
  String get signInSubtitle;

  /// No description provided for @signUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Two minutes, and the next handshake is on the record.'**
  String get signUpSubtitle;

  /// No description provided for @resetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We will send a link to set a new one.'**
  String get resetSubtitle;

  /// No description provided for @signInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInAction;

  /// No description provided for @signUpAction.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get signUpAction;

  /// No description provided for @resetAction.
  ///
  /// In en, this message translates to:
  /// **'Send the link'**
  String get resetAction;

  /// No description provided for @brandPromise.
  ///
  /// In en, this message translates to:
  /// **'The record two people can both rely on.'**
  String get brandPromise;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get fieldName;

  /// No description provided for @fieldNameHelper.
  ///
  /// In en, this message translates to:
  /// **'What the other party sees on a contract.'**
  String get fieldNameHelper;

  /// No description provided for @fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get fieldEmail;

  /// No description provided for @fieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters.'**
  String get passwordTooShort;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @createAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get createAnAccount;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get forgotPassword;

  /// No description provided for @backToSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Back to signing in'**
  String get backToSigningIn;

  /// No description provided for @privacyNote.
  ///
  /// In en, this message translates to:
  /// **'Your contracts are visible to you and to the other party, and to nobody else. That is enforced by the database, not by this app.'**
  String get privacyNote;

  /// No description provided for @confirmEmailNotice.
  ///
  /// In en, this message translates to:
  /// **'Account created. Open the link we sent to {email}, then sign in.'**
  String confirmEmailNotice(String email);

  /// Says the same thing whether or not the address has an account. The other answer turns the form into a way to find out who is a user.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for {email}, a reset link is on its way.'**
  String resetSentNotice(String email);

  /// No description provided for @couldNotSignIn.
  ///
  /// In en, this message translates to:
  /// **'Could not sign in.'**
  String get couldNotSignIn;

  /// No description provided for @contracts.
  ///
  /// In en, this message translates to:
  /// **'Contracts'**
  String get contracts;

  /// No description provided for @waitingOnYou.
  ///
  /// In en, this message translates to:
  /// **'Waiting on you'**
  String get waitingOnYou;

  /// No description provided for @yourContracts.
  ///
  /// In en, this message translates to:
  /// **'Your contracts'**
  String get yourContracts;

  /// No description provided for @everythingElse.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get everythingElse;

  /// No description provided for @newContract.
  ///
  /// In en, this message translates to:
  /// **'New contract'**
  String get newContract;

  /// No description provided for @noContractsYet.
  ///
  /// In en, this message translates to:
  /// **'No contracts yet'**
  String get noContractsYet;

  /// No description provided for @noContractsBlurb.
  ///
  /// In en, this message translates to:
  /// **'Write down what was agreed, who is doing it and for how much. Both sides sign, and from then on there is a record neither of you can quietly change.'**
  String get noContractsBlurb;

  /// No description provided for @demoDataNote.
  ///
  /// In en, this message translates to:
  /// **'Demo data. Nothing on this screen is stored anywhere, and no contract here exists outside this app.'**
  String get demoDataNote;

  /// No description provided for @noEscrowNote.
  ///
  /// In en, this message translates to:
  /// **'TrustIQ does not hold your money in v1. Payment happens directly between you and the other party; what is tracked here is the agreement, the delivery and the evidence.'**
  String get noEscrowNote;

  /// No description provided for @signOutOf.
  ///
  /// In en, this message translates to:
  /// **'Sign out of {backend}'**
  String signOutOf(String backend);

  /// No description provided for @viewAsBuyer.
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get viewAsBuyer;

  /// No description provided for @viewAsSeller.
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get viewAsSeller;

  /// No description provided for @demoRoleSwitchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Demo only: switch which side of the contracts you are viewing'**
  String get demoRoleSwitchTooltip;
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return LAr();
    case 'en':
      return LEn();
  }

  throw FlutterError(
    'L.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
