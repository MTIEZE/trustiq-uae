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

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @otherParty.
  ///
  /// In en, this message translates to:
  /// **'Other party'**
  String get otherParty;

  /// No description provided for @amountAgreed.
  ///
  /// In en, this message translates to:
  /// **'Amount agreed'**
  String get amountAgreed;

  /// No description provided for @youAreTheBuyer.
  ///
  /// In en, this message translates to:
  /// **'You are the buyer'**
  String get youAreTheBuyer;

  /// No description provided for @youAreTheSeller.
  ///
  /// In en, this message translates to:
  /// **'You are the seller'**
  String get youAreTheSeller;

  /// No description provided for @agreedTerms.
  ///
  /// In en, this message translates to:
  /// **'Agreed terms'**
  String get agreedTerms;

  /// No description provided for @milestones.
  ///
  /// In en, this message translates to:
  /// **'Milestones'**
  String get milestones;

  /// No description provided for @whatYouCanDo.
  ///
  /// In en, this message translates to:
  /// **'What you can do'**
  String get whatYouCanDo;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @contractClosedNote.
  ///
  /// In en, this message translates to:
  /// **'This contract is closed. Its record stays available to both parties and cannot be edited by either of you.'**
  String get contractClosedNote;

  /// No description provided for @nothingToDoNote.
  ///
  /// In en, this message translates to:
  /// **'Nothing for you to do right now. The next move belongs to {name}.'**
  String nothingToDoNote(String name);

  /// No description provided for @movesRuleNote.
  ///
  /// In en, this message translates to:
  /// **'These are the only moves allowed from this state for your role. The same rule table runs on the server and in the database, so a move that is not offered here would be refused there too.'**
  String get movesRuleNote;

  /// No description provided for @historyNote.
  ///
  /// In en, this message translates to:
  /// **'Every entry is written once and cannot be edited or removed, by either party or by TrustIQ.'**
  String get historyNote;

  /// No description provided for @proposalWaitingForYou.
  ///
  /// In en, this message translates to:
  /// **'A proposal is waiting for your answer'**
  String get proposalWaitingForYou;

  /// No description provided for @dispute.
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get dispute;

  /// No description provided for @noDisputeOnContract.
  ///
  /// In en, this message translates to:
  /// **'No dispute on this contract.'**
  String get noDisputeOnContract;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @inDispute.
  ///
  /// In en, this message translates to:
  /// **'In dispute'**
  String get inDispute;

  /// No description provided for @whatTheBuyerSays.
  ///
  /// In en, this message translates to:
  /// **'What the buyer says'**
  String get whatTheBuyerSays;

  /// No description provided for @whatTheSellerSays.
  ///
  /// In en, this message translates to:
  /// **'What the seller says'**
  String get whatTheSellerSays;

  /// No description provided for @noAccountGivenYet.
  ///
  /// In en, this message translates to:
  /// **'No account given yet.'**
  String get noAccountGivenYet;

  /// No description provided for @youShort.
  ///
  /// In en, this message translates to:
  /// **'YOU'**
  String get youShort;

  /// No description provided for @evidenceCount.
  ///
  /// In en, this message translates to:
  /// **'Evidence ({count})'**
  String evidenceCount(int count);

  /// No description provided for @addEvidence.
  ///
  /// In en, this message translates to:
  /// **'Add evidence'**
  String get addEvidence;

  /// No description provided for @yourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get yourTurn;

  /// No description provided for @yourTurnBlurb.
  ///
  /// In en, this message translates to:
  /// **'The other party has given their account. Nothing is analysed until you give yours, so the case is waiting on you.'**
  String get yourTurnBlurb;

  /// No description provided for @giveYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Give your account'**
  String get giveYourAccount;

  /// No description provided for @bothAccountsIn.
  ///
  /// In en, this message translates to:
  /// **'Both accounts are in. The case goes to the resolution agent, which reads them against the evidence and proposes an outcome. You will be asked to accept or refuse it.'**
  String get bothAccountsIn;

  /// No description provided for @needsAPerson.
  ///
  /// In en, this message translates to:
  /// **'This case needs a person to look at it.'**
  String get needsAPerson;

  /// No description provided for @reviewerWillRead.
  ///
  /// In en, this message translates to:
  /// **'A reviewer will read the same claims and evidence you can see here, and will contact you both before deciding.'**
  String get reviewerWillRead;

  /// No description provided for @fingerprintsNote.
  ///
  /// In en, this message translates to:
  /// **'The fingerprint under each file is calculated by TrustIQ from the bytes it stored, not supplied by whoever uploaded it. Neither party can replace a file after filing it.'**
  String get fingerprintsNote;

  /// No description provided for @unreadableUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The analysis cannot read this kind of file, so it will weigh the note above rather than the contents.'**
  String get unreadableUnsupported;

  /// No description provided for @unreadableFailed.
  ///
  /// In en, this message translates to:
  /// **'This file should have been readable and was not. If its contents matter, file them as text as well.'**
  String get unreadableFailed;

  /// No description provided for @filedBeforeExtraction.
  ///
  /// In en, this message translates to:
  /// **'Filed before documents were read.'**
  String get filedBeforeExtraction;

  /// No description provided for @decisionByReviewer.
  ///
  /// In en, this message translates to:
  /// **'Decision by a TrustIQ reviewer'**
  String get decisionByReviewer;

  /// No description provided for @proposedResolution.
  ///
  /// In en, this message translates to:
  /// **'Proposed resolution'**
  String get proposedResolution;

  /// No description provided for @confidencePercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% confidence'**
  String confidencePercent(int percent);

  /// No description provided for @whatThisIsBasedOn.
  ///
  /// In en, this message translates to:
  /// **'What this is based on'**
  String get whatThisIsBasedOn;

  /// No description provided for @groundedNote.
  ///
  /// In en, this message translates to:
  /// **'Every statement above had to cite a document that was actually filed. A finding with nothing behind it is refused before you ever see it.'**
  String get groundedNote;

  /// No description provided for @toParty.
  ///
  /// In en, this message translates to:
  /// **'To {name}'**
  String toParty(String name);

  /// No description provided for @splitDoesNotAddUp.
  ///
  /// In en, this message translates to:
  /// **'This split does not add up to the amount in dispute. Do not act on it; contact support.'**
  String get splitDoesNotAddUp;

  /// No description provided for @acceptThisResolution.
  ///
  /// In en, this message translates to:
  /// **'Accept this resolution'**
  String get acceptThisResolution;

  /// No description provided for @refuseAndAskForHuman.
  ///
  /// In en, this message translates to:
  /// **'Refuse and ask for a human'**
  String get refuseAndAskForHuman;

  /// No description provided for @youHaveAccepted.
  ///
  /// In en, this message translates to:
  /// **'You have accepted. Nothing takes effect until the other party accepts as well.'**
  String get youHaveAccepted;

  /// No description provided for @proposalNotDecisionNote.
  ///
  /// In en, this message translates to:
  /// **'This is a proposal, not a decision. It only takes effect if you both accept it, and refusing sends the case to a human reviewer at no cost to you.'**
  String get proposalNotDecisionNote;

  /// No description provided for @refuseThisProposal.
  ///
  /// In en, this message translates to:
  /// **'Refuse this proposal?'**
  String get refuseThisProposal;

  /// No description provided for @refuseConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The case goes to a human reviewer, who will read the same claims and evidence and contact you both.\n\nOne refusal is enough: the other party does not have to agree.'**
  String get refuseConfirmBody;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// No description provided for @refuse.
  ///
  /// In en, this message translates to:
  /// **'Refuse'**
  String get refuse;

  /// No description provided for @bothPartiesAccepted.
  ///
  /// In en, this message translates to:
  /// **'Both parties accepted. The dispute is closed.'**
  String get bothPartiesAccepted;

  /// No description provided for @whoHasAccepted.
  ///
  /// In en, this message translates to:
  /// **'Who has accepted'**
  String get whoHasAccepted;

  /// No description provided for @hasAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get hasAccepted;

  /// No description provided for @notYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get notYet;

  /// No description provided for @openADispute.
  ///
  /// In en, this message translates to:
  /// **'Open a dispute'**
  String get openADispute;

  /// No description provided for @yourResponse.
  ///
  /// In en, this message translates to:
  /// **'Your response'**
  String get yourResponse;

  /// No description provided for @theContract.
  ///
  /// In en, this message translates to:
  /// **'The contract'**
  String get theContract;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @whatPartySays.
  ///
  /// In en, this message translates to:
  /// **'What {name} says'**
  String whatPartySays(String name);

  /// No description provided for @yourAccount.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get yourAccount;

  /// No description provided for @claimHint.
  ///
  /// In en, this message translates to:
  /// **'Say what happened and how it differs from the terms above. Point at dates and deliverables rather than intentions: those are what can be checked against the evidence.'**
  String get claimHint;

  /// No description provided for @claimExample.
  ///
  /// In en, this message translates to:
  /// **'Only two of the three concepts were delivered, and the third is a colour variation of the second.'**
  String get claimExample;

  /// No description provided for @claimMinimum.
  ///
  /// In en, this message translates to:
  /// **'At least {min} characters. A one-line claim gives the reviewer nothing to work with.'**
  String claimMinimum(int min);

  /// No description provided for @submitYourResponse.
  ///
  /// In en, this message translates to:
  /// **'Submit your response'**
  String get submitYourResponse;

  /// No description provided for @openTheDispute.
  ///
  /// In en, this message translates to:
  /// **'Open the dispute'**
  String get openTheDispute;

  /// No description provided for @disputeFlowNote.
  ///
  /// In en, this message translates to:
  /// **'Both accounts and all the evidence go to the same place. An AI agent reads them and proposes a resolution, which takes effect only if you both accept it. Either of you can refuse and ask for a person.'**
  String get disputeFlowNote;

  /// No description provided for @claimVisibilityNote.
  ///
  /// In en, this message translates to:
  /// **'What you write here is shown to the other party in full. It cannot be edited once submitted.'**
  String get claimVisibilityNote;

  /// No description provided for @theFile.
  ///
  /// In en, this message translates to:
  /// **'The file'**
  String get theFile;

  /// No description provided for @chooseAFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get chooseAFile;

  /// No description provided for @readingTheFile.
  ///
  /// In en, this message translates to:
  /// **'Reading the file'**
  String get readingTheFile;

  /// No description provided for @fileTypesShort.
  ///
  /// In en, this message translates to:
  /// **'PDF, image, document, text or zip'**
  String get fileTypesShort;

  /// No description provided for @fileTypesNote.
  ///
  /// In en, this message translates to:
  /// **'PDFs, images, documents, plain text and zip archives, up to 50 MB. The other party sees everything you file here.'**
  String get fileTypesNote;

  /// No description provided for @noteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteOptional;

  /// No description provided for @noteHint.
  ///
  /// In en, this message translates to:
  /// **'What this shows, and why it matters.'**
  String get noteHint;

  /// No description provided for @fileThisEvidence.
  ///
  /// In en, this message translates to:
  /// **'File this evidence'**
  String get fileThisEvidence;

  /// No description provided for @evidencePermanentNote.
  ///
  /// In en, this message translates to:
  /// **'Once filed, a document cannot be edited or withdrawn. A fingerprint of it is recorded so either of you can prove, later, that it is the file that was submitted.'**
  String get evidencePermanentNote;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @filed.
  ///
  /// In en, this message translates to:
  /// **'Filed'**
  String get filed;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @fingerprintRecorded.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint recorded by TrustIQ'**
  String get fingerprintRecorded;

  /// No description provided for @fingerprintNote.
  ///
  /// In en, this message translates to:
  /// **'This was calculated from the bytes that were stored, not from anything your device reported. That is what makes it worth something later.'**
  String get fingerprintNote;

  /// No description provided for @fileCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'That file could not be read: {error}'**
  String fileCouldNotBeRead(String error);

  /// No description provided for @verifyYourIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity'**
  String get verifyYourIdentity;

  /// No description provided for @bindingBetweenVerified.
  ///
  /// In en, this message translates to:
  /// **'A contract only becomes binding between verified identities.'**
  String get bindingBetweenVerified;

  /// No description provided for @canDraftWithoutVerifying.
  ///
  /// In en, this message translates to:
  /// **'You can draft a contract, send it, and file evidence without verifying. What you cannot do is accept one, because the other party has no way of knowing who agreed.'**
  String get canDraftWithoutVerifying;

  /// No description provided for @whatTrustIqKeeps.
  ///
  /// In en, this message translates to:
  /// **'What TrustIQ keeps'**
  String get whatTrustIqKeeps;

  /// No description provided for @keepsName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get keepsName;

  /// No description provided for @keepsNameDetail.
  ///
  /// In en, this message translates to:
  /// **'Shown to the other party on contracts you are on.'**
  String get keepsNameDetail;

  /// No description provided for @keepsReference.
  ///
  /// In en, this message translates to:
  /// **'A reference from UAE Pass'**
  String get keepsReference;

  /// No description provided for @keepsReferenceDetail.
  ///
  /// In en, this message translates to:
  /// **'An identifier that means nothing outside TrustIQ.'**
  String get keepsReferenceDetail;

  /// No description provided for @notKeptEmiratesId.
  ///
  /// In en, this message translates to:
  /// **'Your Emirates ID number'**
  String get notKeptEmiratesId;

  /// No description provided for @notKeptEmiratesIdDetail.
  ///
  /// In en, this message translates to:
  /// **'Available to us during verification, and not stored. It identifies you across every system in the country, so keeping it would make this database worth attacking for reasons that have nothing to do with TrustIQ.'**
  String get notKeptEmiratesIdDetail;

  /// No description provided for @notKeptPersonal.
  ///
  /// In en, this message translates to:
  /// **'Your address, nationality and date of birth'**
  String get notKeptPersonal;

  /// No description provided for @notKeptPersonalDetail.
  ///
  /// In en, this message translates to:
  /// **'Not requested and not stored.'**
  String get notKeptPersonalDetail;

  /// No description provided for @continueWith.
  ///
  /// In en, this message translates to:
  /// **'Continue with {provider}'**
  String continueWith(String provider);

  /// No description provided for @uaePassNotConnected.
  ///
  /// In en, this message translates to:
  /// **'UAE Pass is not connected in this build. TrustIQ has to be registered as a Service Provider first, which is a paperwork step, not a software one. Continuing here marks you verified locally so the rest of the app can be used; it checks nothing.'**
  String get uaePassNotConnected;

  /// No description provided for @uaePassHandoffNote.
  ///
  /// In en, this message translates to:
  /// **'You will be handed to UAE Pass to sign in. TrustIQ never sees your UAE Pass password.'**
  String get uaePassHandoffNote;

  /// No description provided for @cannotBeAcceptedYet.
  ///
  /// In en, this message translates to:
  /// **'Cannot be accepted yet'**
  String get cannotBeAcceptedYet;

  /// No description provided for @identityGateNote.
  ///
  /// In en, this message translates to:
  /// **'You have not verified your identity yet. A contract only becomes binding between verified identities.'**
  String get identityGateNote;

  /// No description provided for @verifyMyIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify my identity'**
  String get verifyMyIdentity;

  /// No description provided for @amountMustBePositive.
  ///
  /// In en, this message translates to:
  /// **'The amount must be more than zero.'**
  String get amountMustBePositive;

  /// No description provided for @amountTwoDecimals.
  ///
  /// In en, this message translates to:
  /// **'Amounts go to two decimal places. 1 AED is 100 fils, and there is nothing smaller.'**
  String get amountTwoDecimals;

  /// No description provided for @amountFormat.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount in AED, like 500 or 1250.50.'**
  String get amountFormat;

  /// No description provided for @stepWhoWith.
  ///
  /// In en, this message translates to:
  /// **'Who this is with'**
  String get stepWhoWith;

  /// No description provided for @stepWhoWithBlurb.
  ///
  /// In en, this message translates to:
  /// **'Both of you will see the same contract, and neither can change it once it is accepted.'**
  String get stepWhoWithBlurb;

  /// No description provided for @iAmPaying.
  ///
  /// In en, this message translates to:
  /// **'I am paying'**
  String get iAmPaying;

  /// No description provided for @iAmDelivering.
  ///
  /// In en, this message translates to:
  /// **'I am delivering'**
  String get iAmDelivering;

  /// No description provided for @emailOfDeliverer.
  ///
  /// In en, this message translates to:
  /// **'Email of the person delivering'**
  String get emailOfDeliverer;

  /// No description provided for @emailOfPayer.
  ///
  /// In en, this message translates to:
  /// **'Email of the person paying'**
  String get emailOfPayer;

  /// No description provided for @counterpartyHelper.
  ///
  /// In en, this message translates to:
  /// **'They need a TrustIQ account already. Inviting someone who has none is not supported yet.'**
  String get counterpartyHelper;

  /// No description provided for @stepWhatAgreed.
  ///
  /// In en, this message translates to:
  /// **'What was agreed'**
  String get stepWhatAgreed;

  /// No description provided for @stepWhatAgreedBlurb.
  ///
  /// In en, this message translates to:
  /// **'This is the text a dispute would be judged against, so be specific about what counts as delivered.'**
  String get stepWhatAgreedBlurb;

  /// No description provided for @whatIsBeingDone.
  ///
  /// In en, this message translates to:
  /// **'What is being done'**
  String get whatIsBeingDone;

  /// No description provided for @exampleDescription.
  ///
  /// In en, this message translates to:
  /// **'Logo design for a startup'**
  String get exampleDescription;

  /// No description provided for @exampleTerms.
  ///
  /// In en, this message translates to:
  /// **'Deliver three distinct concepts within seven days. Two rounds of revision. Final files as SVG and PNG.'**
  String get exampleTerms;

  /// No description provided for @stepHowMuch.
  ///
  /// In en, this message translates to:
  /// **'How much'**
  String get stepHowMuch;

  /// No description provided for @stepHowMuchBlurb.
  ///
  /// In en, this message translates to:
  /// **'Recorded to the fil. Nothing here rounds.'**
  String get stepHowMuchBlurb;

  /// No description provided for @recordedAs.
  ///
  /// In en, this message translates to:
  /// **'Recorded as {amount}'**
  String recordedAs(String amount);

  /// No description provided for @noEscrowShort.
  ///
  /// In en, this message translates to:
  /// **'TrustIQ does not take this money. It records what you agreed so there is something to point at later; you pay each other directly.'**
  String get noEscrowShort;

  /// No description provided for @createAsDraft.
  ///
  /// In en, this message translates to:
  /// **'Create as a draft'**
  String get createAsDraft;

  /// No description provided for @draftNote.
  ///
  /// In en, this message translates to:
  /// **'A draft is yours alone until you send it. Once the other party accepts, neither of you can change the terms.'**
  String get draftNote;

  /// No description provided for @contractCouldNotBeCreated.
  ///
  /// In en, this message translates to:
  /// **'The contract could not be created.'**
  String get contractCouldNotBeCreated;

  /// No description provided for @characterCount.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String characterCount(int count);
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
