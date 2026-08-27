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

  @override
  String get you => 'You';

  @override
  String get otherParty => 'Other party';

  @override
  String get amountAgreed => 'Amount agreed';

  @override
  String get youAreTheBuyer => 'You are the buyer';

  @override
  String get youAreTheSeller => 'You are the seller';

  @override
  String get agreedTerms => 'Agreed terms';

  @override
  String get milestones => 'Milestones';

  @override
  String get whatYouCanDo => 'What you can do';

  @override
  String get history => 'History';

  @override
  String get contractClosedNote =>
      'This contract is closed. Its record stays available to both parties and cannot be edited by either of you.';

  @override
  String nothingToDoNote(String name) {
    return 'Nothing for you to do right now. The next move belongs to $name.';
  }

  @override
  String get movesRuleNote =>
      'These are the only moves allowed from this state for your role. The same rule table runs on the server and in the database, so a move that is not offered here would be refused there too.';

  @override
  String get historyNote =>
      'Every entry is written once and cannot be edited or removed, by either party or by TrustIQ.';

  @override
  String get proposalWaitingForYou => 'A proposal is waiting for your answer';

  @override
  String get dispute => 'Dispute';

  @override
  String get noDisputeOnContract => 'No dispute on this contract.';

  @override
  String get status => 'Status';

  @override
  String get inDispute => 'In dispute';

  @override
  String get whatTheBuyerSays => 'What the buyer says';

  @override
  String get whatTheSellerSays => 'What the seller says';

  @override
  String get noAccountGivenYet => 'No account given yet.';

  @override
  String get youShort => 'YOU';

  @override
  String evidenceCount(int count) {
    return 'Evidence ($count)';
  }

  @override
  String get addEvidence => 'Add evidence';

  @override
  String get yourTurn => 'Your turn';

  @override
  String get yourTurnBlurb =>
      'The other party has given their account. Nothing is analysed until you give yours, so the case is waiting on you.';

  @override
  String get giveYourAccount => 'Give your account';

  @override
  String get bothAccountsIn =>
      'Both accounts are in. The case goes to the resolution agent, which reads them against the evidence and proposes an outcome. You will be asked to accept or refuse it.';

  @override
  String get needsAPerson => 'This case needs a person to look at it.';

  @override
  String get reviewerWillRead =>
      'A reviewer will read the same claims and evidence you can see here, and will contact you both before deciding.';

  @override
  String get fingerprintsNote =>
      'The fingerprint under each file is calculated by TrustIQ from the bytes it stored, not supplied by whoever uploaded it. Neither party can replace a file after filing it.';

  @override
  String get unreadableUnsupported =>
      'The analysis cannot read this kind of file, so it will weigh the note above rather than the contents.';

  @override
  String get unreadableFailed =>
      'This file should have been readable and was not. If its contents matter, file them as text as well.';

  @override
  String get filedBeforeExtraction => 'Filed before documents were read.';

  @override
  String get decisionByReviewer => 'Decision by a TrustIQ reviewer';

  @override
  String get proposedResolution => 'Proposed resolution';

  @override
  String confidencePercent(int percent) {
    return '$percent% confidence';
  }

  @override
  String get whatThisIsBasedOn => 'What this is based on';

  @override
  String get groundedNote =>
      'Every statement above had to cite a document that was actually filed. A finding with nothing behind it is refused before you ever see it.';

  @override
  String toParty(String name) {
    return 'To $name';
  }

  @override
  String get splitDoesNotAddUp =>
      'This split does not add up to the amount in dispute. Do not act on it; contact support.';

  @override
  String get acceptThisResolution => 'Accept this resolution';

  @override
  String get refuseAndAskForHuman => 'Refuse and ask for a human';

  @override
  String get youHaveAccepted =>
      'You have accepted. Nothing takes effect until the other party accepts as well.';

  @override
  String get proposalNotDecisionNote =>
      'This is a proposal, not a decision. It only takes effect if you both accept it, and refusing sends the case to a human reviewer at no cost to you.';

  @override
  String get refuseThisProposal => 'Refuse this proposal?';

  @override
  String get refuseConfirmBody =>
      'The case goes to a human reviewer, who will read the same claims and evidence and contact you both.\n\nOne refusal is enough: the other party does not have to agree.';

  @override
  String get goBack => 'Go back';

  @override
  String get refuse => 'Refuse';

  @override
  String get bothPartiesAccepted =>
      'Both parties accepted. The dispute is closed.';

  @override
  String get whoHasAccepted => 'Who has accepted';

  @override
  String get hasAccepted => 'Accepted';

  @override
  String get notYet => 'Not yet';

  @override
  String get openADispute => 'Open a dispute';

  @override
  String get yourResponse => 'Your response';

  @override
  String get theContract => 'The contract';

  @override
  String get amount => 'Amount';

  @override
  String whatPartySays(String name) {
    return 'What $name says';
  }

  @override
  String get yourAccount => 'Your account';

  @override
  String get claimHint =>
      'Say what happened and how it differs from the terms above. Point at dates and deliverables rather than intentions: those are what can be checked against the evidence.';

  @override
  String get claimExample =>
      'Only two of the three concepts were delivered, and the third is a colour variation of the second.';

  @override
  String claimMinimum(int min) {
    return 'At least $min characters. A one-line claim gives the reviewer nothing to work with.';
  }

  @override
  String get submitYourResponse => 'Submit your response';

  @override
  String get openTheDispute => 'Open the dispute';

  @override
  String get disputeFlowNote =>
      'Both accounts and all the evidence go to the same place. An AI agent reads them and proposes a resolution, which takes effect only if you both accept it. Either of you can refuse and ask for a person.';

  @override
  String get claimVisibilityNote =>
      'What you write here is shown to the other party in full. It cannot be edited once submitted.';

  @override
  String get theFile => 'The file';

  @override
  String get chooseAFile => 'Choose a file';

  @override
  String get readingTheFile => 'Reading the file';

  @override
  String get fileTypesShort => 'PDF, image, document, text or zip';

  @override
  String get fileTypesNote =>
      'PDFs, images, documents, plain text and zip archives, up to 50 MB. The other party sees everything you file here.';

  @override
  String get noteOptional => 'Note (optional)';

  @override
  String get noteHint => 'What this shows, and why it matters.';

  @override
  String get fileThisEvidence => 'File this evidence';

  @override
  String get evidencePermanentNote =>
      'Once filed, a document cannot be edited or withdrawn. A fingerprint of it is recorded so either of you can prove, later, that it is the file that was submitted.';

  @override
  String get change => 'Change';

  @override
  String get filed => 'Filed';

  @override
  String get done => 'Done';

  @override
  String get fingerprintRecorded => 'Fingerprint recorded by TrustIQ';

  @override
  String get fingerprintNote =>
      'This was calculated from the bytes that were stored, not from anything your device reported. That is what makes it worth something later.';

  @override
  String fileCouldNotBeRead(String error) {
    return 'That file could not be read: $error';
  }

  @override
  String get verifyYourIdentity => 'Verify your identity';

  @override
  String get bindingBetweenVerified =>
      'A contract only becomes binding between verified identities.';

  @override
  String get canDraftWithoutVerifying =>
      'You can draft a contract, send it, and file evidence without verifying. What you cannot do is accept one, because the other party has no way of knowing who agreed.';

  @override
  String get whatTrustIqKeeps => 'What TrustIQ keeps';

  @override
  String get keepsName => 'Your name';

  @override
  String get keepsNameDetail =>
      'Shown to the other party on contracts you are on.';

  @override
  String get keepsReference => 'A reference from UAE Pass';

  @override
  String get keepsReferenceDetail =>
      'An identifier that means nothing outside TrustIQ.';

  @override
  String get notKeptEmiratesId => 'Your Emirates ID number';

  @override
  String get notKeptEmiratesIdDetail =>
      'Available to us during verification, and not stored. It identifies you across every system in the country, so keeping it would make this database worth attacking for reasons that have nothing to do with TrustIQ.';

  @override
  String get notKeptPersonal => 'Your address, nationality and date of birth';

  @override
  String get notKeptPersonalDetail => 'Not requested and not stored.';

  @override
  String continueWith(String provider) {
    return 'Continue with $provider';
  }

  @override
  String get uaePassNotConnected =>
      'UAE Pass is not connected in this build. TrustIQ has to be registered as a Service Provider first, which is a paperwork step, not a software one. Continuing here marks you verified locally so the rest of the app can be used; it checks nothing.';

  @override
  String get uaePassHandoffNote =>
      'You will be handed to UAE Pass to sign in. TrustIQ never sees your UAE Pass password.';

  @override
  String get cannotBeAcceptedYet => 'Cannot be accepted yet';

  @override
  String get identityGateNote =>
      'You have not verified your identity yet. A contract only becomes binding between verified identities.';

  @override
  String get verifyMyIdentity => 'Verify my identity';

  @override
  String get amountMustBePositive => 'The amount must be more than zero.';

  @override
  String get amountTwoDecimals =>
      'Amounts go to two decimal places. 1 AED is 100 fils, and there is nothing smaller.';

  @override
  String get amountFormat => 'Enter an amount in AED, like 500 or 1250.50.';

  @override
  String get stepWhoWith => 'Who this is with';

  @override
  String get stepWhoWithBlurb =>
      'Both of you will see the same contract, and neither can change it once it is accepted.';

  @override
  String get iAmPaying => 'I am paying';

  @override
  String get iAmDelivering => 'I am delivering';

  @override
  String get emailOfDeliverer => 'Email of the person delivering';

  @override
  String get emailOfPayer => 'Email of the person paying';

  @override
  String get counterpartyHelper =>
      'They need a TrustIQ account already. Inviting someone who has none is not supported yet.';

  @override
  String get stepWhatAgreed => 'What was agreed';

  @override
  String get stepWhatAgreedBlurb =>
      'This is the text a dispute would be judged against, so be specific about what counts as delivered.';

  @override
  String get whatIsBeingDone => 'What is being done';

  @override
  String get exampleDescription => 'Logo design for a startup';

  @override
  String get exampleTerms =>
      'Deliver three distinct concepts within seven days. Two rounds of revision. Final files as SVG and PNG.';

  @override
  String get stepHowMuch => 'How much';

  @override
  String get stepHowMuchBlurb => 'Recorded to the fil. Nothing here rounds.';

  @override
  String recordedAs(String amount) {
    return 'Recorded as $amount';
  }

  @override
  String get noEscrowShort =>
      'TrustIQ does not take this money. It records what you agreed so there is something to point at later; you pay each other directly.';

  @override
  String get createAsDraft => 'Create as a draft';

  @override
  String get draftNote =>
      'A draft is yours alone until you send it. Once the other party accepts, neither of you can change the terms.';

  @override
  String get contractCouldNotBeCreated => 'The contract could not be created.';

  @override
  String characterCount(int count) {
    return '$count characters';
  }
}
