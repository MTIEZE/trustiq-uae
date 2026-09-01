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
  String get findingRestsOnTerms => 'the agreed terms';

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
  String get verifiedByHand => 'Verified by a person, for now';

  @override
  String get verifiedByHandBody =>
      'UAE Pass is not connected yet. During the closed beta someone at TrustIQ checks your Emirates ID themselves and records what they saw.';

  @override
  String get verifiedByHandWorthLess =>
      'This is worth less than UAE Pass, and your profile says so: it is stored as a manual check, not as a UAE Pass one. Anyone reading it later can tell the difference.';

  @override
  String verifiedByHandContact(String contact) {
    return 'Write to $contact and ask to be verified.';
  }

  @override
  String get verifiedByHandNoContact =>
      'Verification is arranged with TrustIQ directly during the closed beta.';

  @override
  String get verifiedByHandRecord =>
      'Whoever verifies you has to write down what they looked at. That note is kept, and it cannot be edited or removed afterwards, including by TrustIQ.';

  @override
  String get verifiedByHandNothingToDo =>
      'There is nothing to do on this screen. It is here so you know what has to happen before a contract can be accepted, and why it is not automatic yet.';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingBack => 'Back';

  @override
  String onboardingStep(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboarding1Title => 'A record you can both point at';

  @override
  String get onboarding1Body =>
      'Before the work starts, you and the other person write down what was agreed. Once you both accept it, neither of you can change the terms. Everything that happens after that is timestamped, and neither side can quietly rewrite it later.';

  @override
  String get onboarding1Aside =>
      'For freelance work, a private sale, any deal with no platform standing behind it.';

  @override
  String get onboarding2Title =>
      'If it goes wrong, it is not your word against theirs';

  @override
  String get onboarding2Body =>
      'Each of you gives your account of what happened and files the documents behind it. An AI agent reads both against the evidence and proposes a resolution.';

  @override
  String get onboarding2Aside =>
      'The proposal only takes effect if you both accept it. Either of you can refuse and ask for a person instead, and one refusal is enough.';

  @override
  String get onboarding3Title => 'TrustIQ never holds your money';

  @override
  String get onboarding3Body =>
      'You pay each other directly, the way you already do. Holding other people’s funds is a regulated activity in the UAE and TrustIQ is not licensed for it, so it does not pretend to be.';

  @override
  String get onboarding3Aside =>
      'What TrustIQ holds is the record. Nothing on this app can move a dirham.';

  @override
  String get onboarding4Title => 'What it asks of you';

  @override
  String get onboarding4Body =>
      'An account, and an identity check before a contract becomes binding. A contract only binds two verified identities, so the other party knows who agreed.';

  @override
  String get onboarding4Aside =>
      'Drafting a contract, sending it and filing evidence need no verification. Only accepting one does.';

  @override
  String get onboardingCreateAccount => 'Create an account';

  @override
  String get onboardingHaveAccount => 'I already have one';

  @override
  String get onboardingDone => 'Got it';

  @override
  String get whatIsTrustIq => 'What is TrustIQ?';

  @override
  String get howItWorks => 'How TrustIQ works';

  @override
  String get yourIdentity => 'Your identity';

  @override
  String identityVerifiedOn(String date) {
    return 'Verified on $date';
  }

  @override
  String get identityNotVerifiedYet =>
      'Not verified yet. You can draft and send contracts, but not accept one.';

  @override
  String get noAccountTitle => 'They have no TrustIQ account';

  @override
  String noAccountBody(String email) {
    return 'Nobody holds $email. You can send them an invitation instead: they get a code, and when they join, this contract is waiting for them already sent.';
  }

  @override
  String get sendAnInvitation => 'Send an invitation';

  @override
  String get cancel => 'Cancel';

  @override
  String get invitationSent => 'Invitation ready';

  @override
  String get invitationCodeIs => 'Their code';

  @override
  String get invitationShareNote =>
      'TrustIQ does not email them. Send this yourself, however you already talk to them.';

  @override
  String get copyTheMessage => 'Copy the message';

  @override
  String get copied => 'Copied';

  @override
  String invitationMessage(
    String description,
    String amount,
    String email,
    String code,
  ) {
    return 'I have set up our agreement on TrustIQ: $description, $amount. Download TrustIQ, sign up with $email, and enter code $code to see it.';
  }

  @override
  String invitationBoundNote(String email) {
    return 'The code only works for $email. Anyone else who sees it cannot use it.';
  }

  @override
  String get invitationExpiryNote =>
      'It stops working after 30 days, and you can withdraw it before then.';

  @override
  String get invitations => 'Invitations';

  @override
  String get invitationsSent => 'Sent';

  @override
  String get noInvitationsYet => 'You have not invited anyone.';

  @override
  String get noInvitationsYetBody =>
      'When you address a contract to someone with no account, the invitation appears here.';

  @override
  String get haveACode => 'I have a code';

  @override
  String get enterTheCode => 'Enter the code';

  @override
  String get codeHint => 'ABCD-EFGH';

  @override
  String get useTheCode => 'Open the contract';

  @override
  String get codeNote =>
      'The code was given to you by whoever wrote the contract. It only works for the address on your account.';

  @override
  String get invitationClaimed => 'Used';

  @override
  String get invitationRevoked => 'Withdrawn';

  @override
  String get invitationExpired => 'Expired';

  @override
  String get invitationOpen => 'Waiting';

  @override
  String get withdraw => 'Withdraw';

  @override
  String get withdrawInvitation => 'Withdraw this invitation?';

  @override
  String get withdrawInvitationBody =>
      'The code stops working. Nothing has been agreed yet, so there is nothing to undo.';

  @override
  String theyWillBe(String role) {
    return 'They will be the $role';
  }

  @override
  String get buyerWord => 'buyer';

  @override
  String get sellerWord => 'seller';

  @override
  String get whoBuyer => 'The buyer';

  @override
  String get whoSeller => 'The seller';

  @override
  String get whoSystem => 'TrustIQ';

  @override
  String evSubmit(String who) {
    return '$who sent the contract';
  }

  @override
  String evAccept(String who) {
    return '$who accepted the terms';
  }

  @override
  String evDecline(String who) {
    return '$who declined the terms';
  }

  @override
  String evWithdraw(String who) {
    return '$who withdrew the contract';
  }

  @override
  String evMarkDelivered(String who) {
    return '$who marked the work delivered';
  }

  @override
  String evRequestRevision(String who) {
    return '$who requested changes';
  }

  @override
  String evConfirmDelivery(String who) {
    return '$who confirmed the delivery';
  }

  @override
  String evOpenDispute(String who) {
    return '$who opened a dispute';
  }

  @override
  String evResolveDispute(String who) {
    return '$who resolved the dispute';
  }

  @override
  String evCancelByAgreement(String who) {
    return '$who cancelled the contract';
  }

  @override
  String get evExpire => 'The contract expired';

  @override
  String get devSubmitForAi =>
      'Both accounts are in, and the case went to the agent';

  @override
  String get devIssueProposal => 'A resolution was proposed';

  @override
  String devAcceptProposal(String who) {
    return '$who accepted the resolution';
  }

  @override
  String devRejectProposal(String who) {
    return '$who refused it and asked for a person';
  }

  @override
  String get devEscalate => 'The case went to a human reviewer';

  @override
  String get devAssignReviewer => 'A reviewer took the case';

  @override
  String get devIssueHumanResolution => 'A reviewer decided the case';

  @override
  String devWithdrawDispute(String who) {
    return '$who withdrew the dispute';
  }

  @override
  String get notifications => 'Activity';

  @override
  String get nothingWaiting => 'Nothing is waiting on you.';

  @override
  String get nothingWaitingBody =>
      'When the other party moves on one of your contracts, it appears here.';

  @override
  String get needsYou => 'Needs you';

  @override
  String get markAllRead => 'Mark all as read';

  @override
  String get activityNote =>
      'This list is built from the contract record itself, so it says exactly what happened and nothing else.';

  @override
  String get stages => 'Stages';

  @override
  String get stageWaiting => 'Not started';

  @override
  String get stageDelivered => 'Delivered';

  @override
  String get stageAccepted => 'Accepted';

  @override
  String get markStageDelivered => 'Mark delivered';

  @override
  String get acceptStage => 'Accept this stage';

  @override
  String get sendStageBack => 'Send back';

  @override
  String get sendStageBackTitle => 'Send this stage back?';

  @override
  String get sendStageBackBody =>
      'The seller will be told it needs more work. The attempt stays on the record: a stage that took three tries reads as three tries.';

  @override
  String get stagesNote =>
      'Each stage is agreed as it lands, not all at the end. The last one accepted closes the contract, so nobody is asked to sign for the same thing twice.';

  @override
  String stagesTotal(int done, int total) {
    return '$done of $total accepted';
  }

  @override
  String get addAStage => 'Add a stage';

  @override
  String get stageTitle => 'What this stage covers';

  @override
  String get stageAmount => 'Amount for this stage';

  @override
  String get stageExample => 'Three concepts';

  @override
  String get removeStage => 'Remove';

  @override
  String get stagesOptional =>
      'Optional. Without stages the contract is one delivery, confirmed once. With them, the client agrees to each piece as it arrives.';

  @override
  String get stagesOverTotal => 'The stages add up to more than the contract.';

  @override
  String stagesRemainder(String amount) {
    return '$amount of the contract is not in any stage.';
  }

  @override
  String get stagesFixedAfter =>
      'Stages cannot be added or changed once the contract is sent.';

  @override
  String mvDeliver(String who) {
    return '$who delivered a stage';
  }

  @override
  String mvAccept(String who) {
    return '$who accepted a stage';
  }

  @override
  String mvRequestRevision(String who) {
    return '$who sent a stage back';
  }

  @override
  String counterpartyNotVerified(String name) {
    return '$name has not verified their identity yet. A contract only becomes binding between verified identities, so nothing can be accepted until they do.';
  }

  @override
  String get youAreNotVerified => 'Your identity is not verified';

  @override
  String get youAreNotVerifiedBody =>
      'You can draft contracts, send them and file evidence. Accepting one needs your identity, because the other party has no way of knowing who agreed.';

  @override
  String get getVerified => 'Get verified';

  @override
  String get formNeedsVerifiedNote =>
      'Send it now if you like. Neither of you can accept it until both identities are verified, and yours is not.';

  @override
  String get signedInAs => 'Signed in as';

  @override
  String get signOut => 'Sign out';

  @override
  String get closeAccount => 'Close your account';

  @override
  String get closeAccountBlurb =>
      'Everything that identifies you is erased. What the other party to a contract needs is kept, attached to a record that no longer names you.';

  @override
  String get closeAccountTitle => 'Close this account?';

  @override
  String get closeAccountBody =>
      'Your name, your email and your identity check are erased and you will not be able to sign in again.\n\nContracts you are party to stay, because they belong to the other person as much as to you. They will see a closed account where your name was.\n\nThis cannot be undone.';

  @override
  String get closeAccountConfirm => 'Close it';

  @override
  String get accountClosed => 'Your account is closed';

  @override
  String get accountDeletedBody =>
      'Nothing pointed at it, so it was deleted entirely.';

  @override
  String accountKeptBody(String kept) {
    return 'What was kept, and only this: $kept.';
  }

  @override
  String get closeAccountFailed =>
      'The account could not be closed. Nothing has changed.';

  @override
  String get noConnection => 'TrustIQ could not reach the internet.';

  @override
  String get noConnectionBody =>
      'Check your connection and try again. Nothing was sent, so nothing has changed.';

  @override
  String get somethingWentWrong => 'Something went wrong.';

  @override
  String get somethingWentWrongBody =>
      'Try again. If it keeps happening, tell us what you were doing.';

  @override
  String get heldPausedTitle => 'TrustIQ is paused';

  @override
  String get heldPausedBody =>
      'The service is briefly unavailable. Nothing you have already agreed is affected, and no contract can change while it is paused.';

  @override
  String get heldOutdatedTitle => 'This version is too old to use';

  @override
  String get heldOutdatedBody =>
      'Update TrustIQ from the store you installed it from. Your contracts and documents are untouched and will be there when you come back.';

  @override
  String get heldRetry => 'Check again';

  @override
  String get heldChecking => 'Checking';

  @override
  String get verifyStartTitle => 'Start your verification';

  @override
  String get verifyStartBody =>
      'One request, checked by a person. You are told the outcome either way, and if it is no, you are told what to change.';

  @override
  String get verifyStartAction => 'Start verification';

  @override
  String get verifyLegalName => 'Name as it appears on your document';

  @override
  String get verifyLegalNameHelp =>
      'It does not have to match the name on your account. If it differs, that is fine and we will see both.';

  @override
  String get verifyLegalNameMissing => 'Enter the name on your document.';

  @override
  String get verifyDocumentKind => 'What you can show';

  @override
  String get verifyDocEmiratesId => 'Emirates ID';

  @override
  String get verifyDocPassport => 'Passport';

  @override
  String get verifyDocTradeLicence => 'Trade licence';

  @override
  String get verifyHow => 'How you would rather do it';

  @override
  String get verifyHowHint =>
      'In person, a video call, whatever suits you. Optional.';

  @override
  String get verifyNoDocumentUpload =>
      'Nothing is uploaded here. Your document is looked at directly, so no copy of it is stored on our servers.';

  @override
  String get verifySubmit => 'Send my request';

  @override
  String get verifyPendingTitle => 'Your request is with us';

  @override
  String verifyPendingBody(String when) {
    return 'Sent $when. Someone will look at it and you will be told the outcome. You can keep using TrustIQ in the meantime; only making a contract binding needs this.';
  }

  @override
  String verifyPendingShowing(String document) {
    return 'You said you can show: $document';
  }

  @override
  String get verifyWithdraw => 'Withdraw my request';

  @override
  String get verifyWithdrawn => 'Your request has been withdrawn.';

  @override
  String get verifyRejectedTitle => 'Your request was not accepted';

  @override
  String verifyRejectedBody(String when) {
    return 'Answered $when. You can send a new request as soon as you have dealt with this.';
  }

  @override
  String get verifyRejectedWhy => 'What needs to change';

  @override
  String get verifyAskAgain => 'Send a new request';

  @override
  String get verifyDoneTitle => 'Your identity is verified';

  @override
  String verifyDoneBody(String when) {
    return 'Verified $when. Nothing else is needed from you.';
  }

  @override
  String get verifySent => 'Request sent.';

  @override
  String get askResolutionTitle => 'Both accounts are in';

  @override
  String get askResolutionBody =>
      'An AI agent reads both sides against the documents filed and proposes a resolution. It only ends the dispute if you both accept it, and either of you can refuse and ask for a person instead.';

  @override
  String get askResolutionAction => 'Ask for a resolution';

  @override
  String get askResolutionRunning => 'Reading the case';

  @override
  String get askResolutionOnce =>
      'This runs once. Add anything else you want read before you ask.';

  @override
  String get resolutionNeedsVerified =>
      'Your account needs to be verified before you can ask for a resolution.';

  @override
  String get resolutionNeedsVerifiedWhy =>
      'A resolution is a document both of you can point at afterwards, so it is only issued between identities that were checked.';

  @override
  String get resolutionVerifyAction => 'Verify my account';

  @override
  String get resolutionFailed =>
      'The analysis could not be started. Nothing has changed, and you can try again.';

  @override
  String get resolutionStarted => 'The case has been read.';

  @override
  String get stepHowLong => 'How long it runs';

  @override
  String get stepHowLongBlurb =>
      'Most work is one job with no period. Say otherwise only if this is an arrangement that runs for a stretch of time.';

  @override
  String get periodOneOff => 'One piece of work';

  @override
  String get periodOverTime => 'It runs for a period';

  @override
  String get periodStarts => 'Starts';

  @override
  String get periodEnds => 'Ends';

  @override
  String get periodPickDate => 'Choose a date';

  @override
  String get periodOpenEnded => 'No end date';

  @override
  String get periodEndsBeforeStarts => 'The end has to come after the start.';

  @override
  String get periodRenewal => 'When it ends';

  @override
  String get renewalNone => 'It just ends';

  @override
  String get renewalManual => 'We decide together';

  @override
  String get renewalAutomatic => 'It renews itself';

  @override
  String get renewalNeedsBothDates =>
      'Set both dates to choose what happens at the end.';

  @override
  String get renewalAutomaticNote =>
      'On the end date the period rolls forward by the same length, and you are both told. It is on the record either way.';

  @override
  String get renewalManualNote =>
      'You are both warned two weeks before. Nothing renews unless you agree.';

  @override
  String get periodFixedAfterSending =>
      'Like the rest of the terms, this can only be changed while the contract is a draft.';

  @override
  String get contractPeriod => 'Period';

  @override
  String contractPeriodFrom(String from, String to) {
    return '$from to $to';
  }

  @override
  String contractPeriodFromOpen(String from) {
    return 'From $from, no end date';
  }

  @override
  String contractRenewsOn(String when) {
    return 'Renews $when';
  }

  @override
  String contractEndsOn(String when) {
    return 'Ends $when, and does not renew';
  }

  @override
  String contractDecideBy(String when) {
    return 'You both decide by $when';
  }

  @override
  String get whatComesLater => 'Not yet';

  @override
  String laterOnce(String action, String state) {
    return '$action — once the contract is $state';
  }

  @override
  String get laterNote =>
      'Read from the same table the app checks before it lets anything happen, so this cannot promise something the rules do not.';

  @override
  String theirMove(String name) {
    return 'Waiting on $name';
  }

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

  @override
  String get reportAction => 'Report a problem';

  @override
  String get reportTitle => 'Report a problem';

  @override
  String get reportLead =>
      'This goes to a person at TrustIQ, not to the other party. They are not told you reported it.';

  @override
  String get reportReasonAbusive => 'Abusive or threatening';

  @override
  String get reportReasonFraud => 'Fraud or a scam';

  @override
  String get reportReasonImpersonation => 'Pretending to be somebody else';

  @override
  String get reportReasonIllegal => 'Illegal';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonOther => 'Something else';

  @override
  String get reportDetailHint => 'What happened (optional)';

  @override
  String get reportSend => 'Send the report';

  @override
  String get reportSent => 'Sent. Somebody will read it.';

  @override
  String get reportAlready =>
      'You have already reported this. It is still with us.';

  @override
  String get blockAction => 'Refuse future contracts';

  @override
  String get blockTitle => 'Refuse future contracts from this person?';

  @override
  String get blockLead =>
      'They will not be able to start anything new with you, and you will not be able to start anything with them. This contract stays exactly as it is, and so does everything filed on it.';

  @override
  String get blockConfirm => 'Refuse future contracts';

  @override
  String get blockDone => 'They cannot start anything new with you.';

  @override
  String get unblockAction => 'Allow contracts again';

  @override
  String get unblockDone => 'They can reach you again.';

  @override
  String get legalTerms => 'Terms of use';

  @override
  String get legalPrivacy => 'Privacy';

  @override
  String get legalHeading => 'The small print';

  @override
  String get verifyMoreTitle => 'One more thing is needed';

  @override
  String get verifyMoreBody =>
      'Your request is still open. Somebody read it and needs a little more before they can finish.';

  @override
  String get verifyMoreWhat => 'What they asked for';

  @override
  String get verifyMoreSend => 'Send it';
}
