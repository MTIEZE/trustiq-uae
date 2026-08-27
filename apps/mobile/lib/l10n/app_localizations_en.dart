// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'TrustIQ';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get stateDraft => 'Draft';

  @override
  String get stateAwaitingAcceptance => 'Awaiting acceptance';

  @override
  String get stateInProgress => 'In progress';

  @override
  String get stateAwaitingReview => 'Awaiting review';

  @override
  String get stateCompleted => 'Completed';

  @override
  String get stateDisputed => 'Disputed';

  @override
  String get stateResolved => 'Resolved';

  @override
  String get stateDeclined => 'Declined';

  @override
  String get stateCancelled => 'Cancelled';

  @override
  String get stateExpired => 'Expired';

  @override
  String get eventSubmit => 'Send to the other party';

  @override
  String get eventWithdraw => 'Withdraw';

  @override
  String get eventAccept => 'Accept the terms';

  @override
  String get eventDecline => 'Decline';

  @override
  String get eventExpire => 'Expire';

  @override
  String get eventMarkDelivered => 'Mark as delivered';

  @override
  String get eventRequestRevision => 'Request changes';

  @override
  String get eventConfirmDelivery => 'Confirm and close';

  @override
  String get eventOpenDispute => 'Open a dispute';

  @override
  String get eventResolveDispute => 'Resolve';

  @override
  String get eventCancelByAgreement => 'Cancel by agreement';

  @override
  String get disputeOpen => 'Open';

  @override
  String get disputeBeingAnalysed => 'Being analysed';

  @override
  String get disputeProposalIssued => 'Proposal issued';

  @override
  String get disputeClosedByAgreement => 'Closed by agreement';

  @override
  String get disputeEscalated => 'With a human reviewer';

  @override
  String get disputeUnderHumanReview => 'Under human review';

  @override
  String get disputeDecidedByReviewer => 'Decided by a reviewer';

  @override
  String get disputeWithdrawn => 'Withdrawn';

  @override
  String get decisionReleaseToSeller => 'Everything to the seller';

  @override
  String get decisionRefundToBuyer => 'Everything refunded to the buyer';

  @override
  String get decisionSplit => 'Split between both parties';

  @override
  String get roleBuyer => 'Buyer';

  @override
  String get roleSeller => 'Seller';

  @override
  String get verified => 'Verified';

  @override
  String get unverified => 'Unverified';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get signUpTitle => 'Create your account';

  @override
  String get resetTitle => 'Reset your password';

  @override
  String get signInSubtitle =>
      'Your contracts and disputes, where you left them.';

  @override
  String get signUpSubtitle =>
      'Two minutes, and the next handshake is on the record.';

  @override
  String get resetSubtitle => 'We will send a link to set a new one.';

  @override
  String get signInAction => 'Sign in';

  @override
  String get signUpAction => 'Create account';

  @override
  String get resetAction => 'Send the link';

  @override
  String get brandPromise => 'The record two people can both rely on.';

  @override
  String get fieldName => 'Your name';

  @override
  String get fieldNameHelper => 'What the other party sees on a contract.';

  @override
  String get fieldEmail => 'Email';

  @override
  String get fieldPassword => 'Password';

  @override
  String get passwordTooShort => 'At least 8 characters.';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get createAnAccount => 'Create an account';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String get backToSigningIn => 'Back to signing in';

  @override
  String get privacyNote =>
      'Your contracts are visible to you and to the other party, and to nobody else. That is enforced by the database, not by this app.';

  @override
  String confirmEmailNotice(String email) {
    return 'Account created. Open the link we sent to $email, then sign in.';
  }

  @override
  String resetSentNotice(String email) {
    return 'If an account exists for $email, a reset link is on its way.';
  }

  @override
  String get couldNotSignIn => 'Could not sign in.';

  @override
  String get contracts => 'Contracts';

  @override
  String get waitingOnYou => 'Waiting on you';

  @override
  String get yourContracts => 'Your contracts';

  @override
  String get everythingElse => 'Everything else';

  @override
  String get newContract => 'New contract';

  @override
  String get noContractsYet => 'No contracts yet';

  @override
  String get noContractsBlurb =>
      'Write down what was agreed, who is doing it and for how much. Both sides sign, and from then on there is a record neither of you can quietly change.';

  @override
  String get demoDataNote =>
      'Demo data. Nothing on this screen is stored anywhere, and no contract here exists outside this app.';

  @override
  String get noEscrowNote =>
      'TrustIQ does not hold your money in v1. Payment happens directly between you and the other party; what is tracked here is the agreement, the delivery and the evidence.';

  @override
  String signOutOf(String backend) {
    return 'Sign out of $backend';
  }

  @override
  String get viewAsBuyer => 'Buyer';

  @override
  String get viewAsSeller => 'Seller';

  @override
  String get demoRoleSwitchTooltip =>
      'Demo only: switch which side of the contracts you are viewing';
}
