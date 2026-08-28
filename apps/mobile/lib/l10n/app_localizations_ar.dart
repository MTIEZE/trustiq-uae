// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class LAr extends L {
  LAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'TrustIQ';

  @override
  String get language => 'اللغة';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get stateDraft => 'مسودة';

  @override
  String get stateAwaitingAcceptance => 'بانتظار الموافقة';

  @override
  String get stateInProgress => 'قيد التنفيذ';

  @override
  String get stateAwaitingReview => 'بانتظار المراجعة';

  @override
  String get stateCompleted => 'مكتمل';

  @override
  String get stateDisputed => 'قيد النزاع';

  @override
  String get stateResolved => 'تمت التسوية';

  @override
  String get stateDeclined => 'مرفوض';

  @override
  String get stateCancelled => 'ملغى';

  @override
  String get stateExpired => 'منتهي الصلاحية';

  @override
  String get eventSubmit => 'إرسال إلى الطرف الآخر';

  @override
  String get eventWithdraw => 'سحب';

  @override
  String get eventAccept => 'قبول الشروط';

  @override
  String get eventDecline => 'رفض';

  @override
  String get eventExpire => 'إنهاء المدة';

  @override
  String get eventMarkDelivered => 'تحديد كمُسلَّم';

  @override
  String get eventRequestRevision => 'طلب تعديلات';

  @override
  String get eventConfirmDelivery => 'تأكيد وإغلاق';

  @override
  String get eventOpenDispute => 'فتح نزاع';

  @override
  String get eventResolveDispute => 'تسوية';

  @override
  String get eventCancelByAgreement => 'إلغاء بالتراضي';

  @override
  String get disputeOpen => 'مفتوح';

  @override
  String get disputeBeingAnalysed => 'قيد التحليل';

  @override
  String get disputeProposalIssued => 'صدر اقتراح';

  @override
  String get disputeClosedByAgreement => 'أُغلق بالتراضي';

  @override
  String get disputeEscalated => 'لدى مراجع بشري';

  @override
  String get disputeUnderHumanReview => 'قيد المراجعة البشرية';

  @override
  String get disputeDecidedByReviewer => 'بتّ فيه مراجع';

  @override
  String get disputeWithdrawn => 'مسحوب';

  @override
  String get decisionReleaseToSeller => 'المبلغ كاملاً للبائع';

  @override
  String get decisionRefundToBuyer => 'المبلغ كاملاً يُعاد للمشتري';

  @override
  String get decisionSplit => 'تقسيم بين الطرفين';

  @override
  String get roleBuyer => 'المشتري';

  @override
  String get roleSeller => 'البائع';

  @override
  String get verified => 'موثّق';

  @override
  String get unverified => 'غير موثّق';

  @override
  String get signInTitle => 'تسجيل الدخول';

  @override
  String get signUpTitle => 'أنشئ حسابك';

  @override
  String get resetTitle => 'إعادة تعيين كلمة المرور';

  @override
  String get signInSubtitle => 'عقودك ونزاعاتك، حيث تركتها.';

  @override
  String get signUpSubtitle => 'دقيقتان، ويصبح الاتفاق القادم موثّقاً.';

  @override
  String get resetSubtitle => 'سنرسل رابطاً لتعيين كلمة مرور جديدة.';

  @override
  String get signInAction => 'تسجيل الدخول';

  @override
  String get signUpAction => 'إنشاء حساب';

  @override
  String get resetAction => 'إرسال الرابط';

  @override
  String get brandPromise => 'سجلٌّ يثق به الطرفان معاً.';

  @override
  String get fieldName => 'اسمك';

  @override
  String get fieldNameHelper => 'هذا ما يراه الطرف الآخر في العقد.';

  @override
  String get fieldEmail => 'البريد الإلكتروني';

  @override
  String get fieldPassword => 'كلمة المرور';

  @override
  String get passwordTooShort => 'ثمانية أحرف على الأقل.';

  @override
  String get showPassword => 'إظهار كلمة المرور';

  @override
  String get hidePassword => 'إخفاء كلمة المرور';

  @override
  String get createAnAccount => 'إنشاء حساب';

  @override
  String get forgotPassword => 'نسيت كلمة المرور';

  @override
  String get backToSigningIn => 'العودة لتسجيل الدخول';

  @override
  String get privacyNote =>
      'عقودك مرئية لك وللطرف الآخر فقط، ولا أحد سواكما. قاعدة البيانات هي التي تفرض ذلك، لا هذا التطبيق.';

  @override
  String confirmEmailNotice(String email) {
    return 'تم إنشاء الحساب. افتح الرابط الذي أرسلناه إلى $email، ثم سجّل الدخول.';
  }

  @override
  String resetSentNotice(String email) {
    return 'إن كان هناك حساب مرتبط بـ $email، فرابط إعادة التعيين في طريقه إليه.';
  }

  @override
  String get couldNotSignIn => 'تعذّر تسجيل الدخول.';

  @override
  String get contracts => 'العقود';

  @override
  String get waitingOnYou => 'بانتظارك';

  @override
  String get yourContracts => 'عقودك';

  @override
  String get everythingElse => 'كل ما تبقّى';

  @override
  String get newContract => 'عقد جديد';

  @override
  String get noContractsYet => 'لا توجد عقود بعد';

  @override
  String get noContractsBlurb =>
      'دوّن ما تم الاتفاق عليه، ومن ينفّذه، وبكم. يوقّع الطرفان، ومن تلك اللحظة يوجد سجل لا يستطيع أيٌّ منكما تغييره بهدوء.';

  @override
  String get demoDataNote =>
      'بيانات تجريبية. لا شيء في هذه الشاشة محفوظ في أي مكان، ولا يوجد أي عقد هنا خارج هذا التطبيق.';

  @override
  String get noEscrowNote =>
      'لا تحتفظ TrustIQ بأموالك في الإصدار الأول. الدفع يتم مباشرة بينك وبين الطرف الآخر؛ ما يُوثَّق هنا هو الاتفاق والتسليم والأدلة.';

  @override
  String signOutOf(String backend) {
    return 'تسجيل الخروج من $backend';
  }

  @override
  String get viewAsBuyer => 'مشترٍ';

  @override
  String get viewAsSeller => 'بائع';

  @override
  String get demoRoleSwitchTooltip =>
      'للعرض التجريبي فقط: بدّل الطرف الذي تعرض العقود من جهته';

  @override
  String get you => 'أنت';

  @override
  String get otherParty => 'الطرف الآخر';

  @override
  String get amountAgreed => 'المبلغ المتفق عليه';

  @override
  String get youAreTheBuyer => 'أنت المشتري';

  @override
  String get youAreTheSeller => 'أنت البائع';

  @override
  String get agreedTerms => 'الشروط المتفق عليها';

  @override
  String get milestones => 'المراحل';

  @override
  String get whatYouCanDo => 'ما يمكنك فعله';

  @override
  String get history => 'السجل';

  @override
  String get contractClosedNote =>
      'هذا العقد مغلق. يبقى سجله متاحاً للطرفين، ولا يستطيع أيٌّ منكما تعديله.';

  @override
  String nothingToDoNote(String name) {
    return 'لا شيء عليك فعله الآن. الخطوة التالية على $name.';
  }

  @override
  String get movesRuleNote =>
      'هذه هي الإجراءات الوحيدة المسموح بها من هذه الحالة لدورك. جدول القواعد نفسه يعمل على الخادم وفي قاعدة البيانات، فأي إجراء لا يُعرض هنا سيُرفض هناك أيضاً.';

  @override
  String get historyNote =>
      'كل سطر يُكتب مرة واحدة ولا يمكن تعديله أو حذفه، لا من أي طرف ولا من TrustIQ.';

  @override
  String get proposalWaitingForYou => 'هناك اقتراح ينتظر ردّك';

  @override
  String get dispute => 'النزاع';

  @override
  String get noDisputeOnContract => 'لا يوجد نزاع على هذا العقد.';

  @override
  String get status => 'الحالة';

  @override
  String get inDispute => 'محل النزاع';

  @override
  String get whatTheBuyerSays => 'ما يقوله المشتري';

  @override
  String get whatTheSellerSays => 'ما يقوله البائع';

  @override
  String get noAccountGivenYet => 'لم يُقدَّم أي بيان بعد.';

  @override
  String get youShort => 'أنت';

  @override
  String evidenceCount(int count) {
    return 'الأدلة ($count)';
  }

  @override
  String get addEvidence => 'إضافة دليل';

  @override
  String get yourTurn => 'دورك';

  @override
  String get yourTurnBlurb =>
      'قدّم الطرف الآخر بيانه. لا يبدأ أي تحليل قبل أن تقدّم بيانك، فالقضية بانتظارك.';

  @override
  String get giveYourAccount => 'قدّم بيانك';

  @override
  String get bothAccountsIn =>
      'وصل بيان الطرفين. تنتقل القضية إلى وكيل التسوية، الذي يقرأهما مقابل الأدلة ويقترح نتيجة. سيُطلب منك قبولها أو رفضها.';

  @override
  String get needsAPerson => 'هذه القضية تحتاج إلى شخص ينظر فيها.';

  @override
  String get reviewerWillRead =>
      'سيقرأ المراجع البشري البيانات والأدلة نفسها التي تراها هنا، وسيتواصل معكما قبل البتّ.';

  @override
  String get fingerprintsNote =>
      'البصمة أسفل كل ملف تحسبها TrustIQ من البايتات التي خزّنتها، لا يقدّمها من رفع الملف. ولا يستطيع أي طرف استبدال ملف بعد إيداعه.';

  @override
  String get unreadableUnsupported =>
      'لا يستطيع التحليل قراءة هذا النوع من الملفات، لذا سيعتمد على الملاحظة أعلاه بدل المحتوى.';

  @override
  String get unreadableFailed =>
      'كان يُفترض أن يكون هذا الملف قابلاً للقراءة ولم يكن. إن كان محتواه مهماً، أودعه كنص أيضاً.';

  @override
  String get filedBeforeExtraction => 'أُودع قبل أن تُقرأ المستندات.';

  @override
  String get decisionByReviewer => 'قرار من مراجع في TrustIQ';

  @override
  String get proposedResolution => 'التسوية المقترحة';

  @override
  String confidencePercent(int percent) {
    return 'درجة ثقة $percent٪';
  }

  @override
  String get whatThisIsBasedOn => 'على ماذا يستند هذا';

  @override
  String get groundedNote =>
      'كل عبارة أعلاه كان عليها أن تستشهد بمستند أُودع فعلاً. أي استنتاج بلا سند يُرفض قبل أن تراه.';

  @override
  String toParty(String name) {
    return 'إلى $name';
  }

  @override
  String get splitDoesNotAddUp =>
      'هذا التقسيم لا يساوي المبلغ محل النزاع. لا تتصرّف بناءً عليه؛ تواصل مع الدعم.';

  @override
  String get acceptThisResolution => 'قبول هذه التسوية';

  @override
  String get refuseAndAskForHuman => 'الرفض وطلب مراجع بشري';

  @override
  String get youHaveAccepted =>
      'لقد قبلت. لا يسري شيء حتى يقبل الطرف الآخر أيضاً.';

  @override
  String get proposalNotDecisionNote =>
      'هذا اقتراح وليس قراراً. لا يسري إلا إذا قبلتماه معاً، والرفض يحيل القضية إلى مراجع بشري دون أي تكلفة عليك.';

  @override
  String get refuseThisProposal => 'رفض هذا الاقتراح؟';

  @override
  String get refuseConfirmBody =>
      'تنتقل القضية إلى مراجع بشري، سيقرأ البيانات والأدلة نفسها ويتواصل معكما.\n\nرفض واحد يكفي: لا يلزم أن يوافق الطرف الآخر.';

  @override
  String get goBack => 'رجوع';

  @override
  String get refuse => 'رفض';

  @override
  String get bothPartiesAccepted => 'قبل الطرفان. أُغلق النزاع.';

  @override
  String get whoHasAccepted => 'من قَبِل';

  @override
  String get hasAccepted => 'قَبِل';

  @override
  String get notYet => 'ليس بعد';

  @override
  String get openADispute => 'فتح نزاع';

  @override
  String get yourResponse => 'ردّك';

  @override
  String get theContract => 'العقد';

  @override
  String get amount => 'المبلغ';

  @override
  String whatPartySays(String name) {
    return 'ما يقوله $name';
  }

  @override
  String get yourAccount => 'بيانك';

  @override
  String get claimHint =>
      'اذكر ما حدث وكيف يختلف عن الشروط أعلاه. أشِر إلى تواريخ ومخرجات محددة بدل النوايا: هذه هي ما يمكن التحقق منه مقابل الأدلة.';

  @override
  String get claimExample =>
      'سُلّم مفهومان فقط من الثلاثة، والثالث تنويع لوني للثاني.';

  @override
  String claimMinimum(int min) {
    return '$min حرفاً على الأقل. بيان من سطر واحد لا يترك للمراجع ما يعمل عليه.';
  }

  @override
  String get submitYourResponse => 'إرسال ردّك';

  @override
  String get openTheDispute => 'فتح النزاع';

  @override
  String get disputeFlowNote =>
      'يذهب بيان الطرفين وكل الأدلة إلى المكان نفسه. يقرأها وكيل ذكاء اصطناعي ويقترح تسوية، لا تسري إلا إذا قبلتماها معاً. ويستطيع أيٌّ منكما الرفض وطلب شخص.';

  @override
  String get claimVisibilityNote =>
      'ما تكتبه هنا يُعرض على الطرف الآخر كاملاً. ولا يمكن تعديله بعد الإرسال.';

  @override
  String get theFile => 'الملف';

  @override
  String get chooseAFile => 'اختر ملفاً';

  @override
  String get readingTheFile => 'جارٍ قراءة الملف';

  @override
  String get fileTypesShort => 'PDF أو صورة أو مستند أو نص أو أرشيف مضغوط';

  @override
  String get fileTypesNote =>
      'ملفات PDF والصور والمستندات والنص العادي والأرشيفات المضغوطة، حتى 50 ميغابايت. يرى الطرف الآخر كل ما تودعه هنا.';

  @override
  String get noteOptional => 'ملاحظة (اختيارية)';

  @override
  String get noteHint => 'ما الذي يُظهره هذا، ولماذا يهم.';

  @override
  String get fileThisEvidence => 'إيداع هذا الدليل';

  @override
  String get evidencePermanentNote =>
      'بعد الإيداع، لا يمكن تعديل المستند ولا سحبه. تُسجَّل بصمة له ليستطيع أيٌّ منكما أن يثبت لاحقاً أنه الملف الذي قُدّم.';

  @override
  String get change => 'تغيير';

  @override
  String get filed => 'تم الإيداع';

  @override
  String get done => 'تم';

  @override
  String get fingerprintRecorded => 'البصمة التي سجّلتها TrustIQ';

  @override
  String get fingerprintNote =>
      'حُسبت من البايتات التي جرى تخزينها، لا مما أبلغ عنه جهازك. وهذا ما يجعلها ذات قيمة لاحقاً.';

  @override
  String fileCouldNotBeRead(String error) {
    return 'تعذّرت قراءة هذا الملف: $error';
  }

  @override
  String get verifyYourIdentity => 'وثّق هويتك';

  @override
  String get bindingBetweenVerified =>
      'لا يصبح العقد ملزماً إلا بين هويتين موثّقتين.';

  @override
  String get canDraftWithoutVerifying =>
      'يمكنك صياغة عقد وإرساله وإيداع الأدلة دون توثيق. ما لا يمكنك فعله هو قبول عقد، لأن الطرف الآخر لن يعرف من وافق.';

  @override
  String get whatTrustIqKeeps => 'ما تحتفظ به TrustIQ';

  @override
  String get keepsName => 'اسمك';

  @override
  String get keepsNameDetail =>
      'يُعرض على الطرف الآخر في العقود التي تكون طرفاً فيها.';

  @override
  String get keepsReference => 'مُعرِّف من الهوية الرقمية';

  @override
  String get keepsReferenceDetail => 'مُعرِّف لا يعني شيئاً خارج TrustIQ.';

  @override
  String get notKeptEmiratesId => 'رقم هويتك الإماراتية';

  @override
  String get notKeptEmiratesIdDetail =>
      'يكون متاحاً لنا أثناء التوثيق فقط ولا يُخزَّن. فهو يعرّفك في كل أنظمة الدولة، والاحتفاظ به يجعل قاعدة البيانات هذه هدفاً جديراً بالهجوم لأسباب لا علاقة لها بـ TrustIQ.';

  @override
  String get notKeptPersonal => 'عنوانك وجنسيتك وتاريخ ميلادك';

  @override
  String get notKeptPersonalDetail => 'لا تُطلب ولا تُخزَّن.';

  @override
  String continueWith(String provider) {
    return 'المتابعة عبر $provider';
  }

  @override
  String get uaePassNotConnected =>
      'الهوية الرقمية غير موصولة في هذه النسخة. يجب أولاً تسجيل TrustIQ كمزوّد خدمة، وهي خطوة إدارية لا برمجية. المتابعة هنا تعلّمك كموثَّق محلياً فقط لتتمكن من استخدام بقية التطبيق؛ وهي لا تتحقق من شيء.';

  @override
  String get uaePassHandoffNote =>
      'ستُحوَّل إلى الهوية الرقمية لتسجيل الدخول. ولا ترى TrustIQ كلمة مرورك هناك أبداً.';

  @override
  String get cannotBeAcceptedYet => 'لا يمكن قبوله بعد';

  @override
  String get identityGateNote =>
      'لم توثّق هويتك بعد. ولا يصبح العقد ملزماً إلا بين هويتين موثّقتين.';

  @override
  String get verifyMyIdentity => 'توثيق هويتي';

  @override
  String get verifiedByHand => 'التوثيق يتم بواسطة شخص، مؤقتاً';

  @override
  String get verifiedByHandBody =>
      'الهوية الرقمية غير موصولة بعد. خلال النسخة التجريبية المغلقة، يتحقق أحد العاملين في TrustIQ من هويتك الإماراتية بنفسه ويسجّل ما رآه.';

  @override
  String get verifiedByHandWorthLess =>
      'هذا أقل قيمة من التوثيق عبر الهوية الرقمية، وملفك يقول ذلك: يُحفظ كتحقق يدوي لا كتحقق عبر الهوية الرقمية. ومن يقرأه لاحقاً يستطيع التمييز بينهما.';

  @override
  String verifiedByHandContact(String contact) {
    return 'راسل $contact واطلب توثيق هويتك.';
  }

  @override
  String get verifiedByHandNoContact =>
      'يُرتَّب التوثيق مع TrustIQ مباشرة خلال النسخة التجريبية المغلقة.';

  @override
  String get verifiedByHandRecord =>
      'على من يوثّق هويتك أن يدوّن ما اطّلع عليه. تُحفظ هذه الملاحظة ولا يمكن تعديلها ولا حذفها لاحقاً، ولا حتى من TrustIQ.';

  @override
  String get verifiedByHandNothingToDo =>
      'لا يوجد ما تفعله في هذه الشاشة. هي هنا لتعرف ما الذي يجب أن يحدث قبل أن يمكن قبول أي عقد، ولماذا ليس تلقائياً بعد.';

  @override
  String get onboardingSkip => 'تخطٍّ';

  @override
  String get onboardingNext => 'التالي';

  @override
  String get onboardingBack => 'السابق';

  @override
  String onboardingStep(int current, int total) {
    return 'الخطوة $current من $total';
  }

  @override
  String get onboarding1Title => 'سجلّ يستطيع كلاكما الرجوع إليه';

  @override
  String get onboarding1Body =>
      'قبل أن يبدأ العمل، تكتبان معاً ما تم الاتفاق عليه. وبمجرد قبولكما له، لا يستطيع أيٌّ منكما تغيير الشروط. وكل ما يحدث بعد ذلك يُسجَّل بوقته، ولا يستطيع أي طرف تعديله لاحقاً في صمت.';

  @override
  String get onboarding1Aside =>
      'للعمل الحر، أو بيع بين أفراد، أو أي صفقة لا تقف خلفها منصة.';

  @override
  String get onboarding2Title => 'إن ساءت الأمور، فلن تكون كلمتك مقابل كلمته';

  @override
  String get onboarding2Body =>
      'يقدّم كلٌّ منكما بيانه عمّا حدث ويودع المستندات التي تسنده. يقرأ وكيل ذكاء اصطناعي البيانين مقابل الأدلة ويقترح تسوية.';

  @override
  String get onboarding2Aside =>
      'لا يسري الاقتراح إلا إذا قبلتماه معاً. ويستطيع أيٌّ منكما رفضه وطلب شخص بدلاً منه، ورفض واحد يكفي.';

  @override
  String get onboarding3Title => 'لا تحتفظ TrustIQ بأموالك أبداً';

  @override
  String get onboarding3Body =>
      'تدفعان لبعضكما مباشرة، كما تفعلان اليوم. الاحتفاظ بأموال الغير نشاط منظَّم في الإمارات، وTrustIQ غير مرخّصة له، فهي لا تدّعي ذلك.';

  @override
  String get onboarding3Aside =>
      'ما تحتفظ به TrustIQ هو السجل. لا شيء في هذا التطبيق يستطيع تحريك درهم واحد.';

  @override
  String get onboarding4Title => 'ما يُطلب منك';

  @override
  String get onboarding4Body =>
      'حساب، وتوثيق للهوية قبل أن يصبح العقد ملزماً. لا يلزم العقد إلا هويتين موثّقتين، ليعرف الطرف الآخر من وافق.';

  @override
  String get onboarding4Aside =>
      'صياغة العقد وإرساله وإيداع الأدلة لا تحتاج إلى توثيق. القبول وحده هو الذي يحتاجه.';

  @override
  String get onboardingCreateAccount => 'إنشاء حساب';

  @override
  String get onboardingHaveAccount => 'لديّ حساب بالفعل';

  @override
  String get onboardingDone => 'فهمت';

  @override
  String get whatIsTrustIq => 'ما هي TrustIQ؟';

  @override
  String get howItWorks => 'كيف تعمل TrustIQ';

  @override
  String get yourIdentity => 'هويتك';

  @override
  String identityVerifiedOn(String date) {
    return 'موثّقة في $date';
  }

  @override
  String get identityNotVerifiedYet =>
      'غير موثّقة بعد. يمكنك صياغة العقود وإرسالها، لكن لا يمكنك قبول عقد.';

  @override
  String get noAccountTitle => 'ليس لديه حساب في TrustIQ';

  @override
  String noAccountBody(String email) {
    return 'لا أحد يملك $email. يمكنك إرسال دعوة له بدلاً من ذلك: يحصل على رمز، وعندما ينضم يجد هذا العقد بانتظاره ومُرسلاً بالفعل.';
  }

  @override
  String get sendAnInvitation => 'إرسال دعوة';

  @override
  String get cancel => 'إلغاء';

  @override
  String get invitationSent => 'الدعوة جاهزة';

  @override
  String get invitationCodeIs => 'رمزه';

  @override
  String get invitationShareNote =>
      'لا ترسل TrustIQ إليه بريداً. أرسل هذا بنفسك، بالوسيلة التي تتواصلان بها أصلاً.';

  @override
  String get copyTheMessage => 'نسخ الرسالة';

  @override
  String get copied => 'تم النسخ';

  @override
  String invitationMessage(
    String description,
    String amount,
    String email,
    String code,
  ) {
    return 'أعددتُ اتفاقنا على TrustIQ: $description، $amount. حمّل TrustIQ، وسجّل بـ $email، وأدخل الرمز $code لرؤيته.';
  }

  @override
  String invitationBoundNote(String email) {
    return 'الرمز يعمل لـ $email فقط. ولا يستطيع أي شخص آخر يراه استخدامه.';
  }

  @override
  String get invitationExpiryNote =>
      'يتوقف عن العمل بعد ٣٠ يوماً، ويمكنك سحبه قبل ذلك.';

  @override
  String get invitations => 'الدعوات';

  @override
  String get invitationsSent => 'المُرسَلة';

  @override
  String get noInvitationsYet => 'لم تدعُ أحداً بعد.';

  @override
  String get noInvitationsYetBody =>
      'عندما توجّه عقداً إلى شخص بلا حساب، تظهر الدعوة هنا.';

  @override
  String get haveACode => 'لديّ رمز';

  @override
  String get enterTheCode => 'أدخل الرمز';

  @override
  String get codeHint => 'ABCD-EFGH';

  @override
  String get useTheCode => 'فتح العقد';

  @override
  String get codeNote =>
      'أعطاك الرمز من كتب العقد. وهو يعمل فقط للعنوان المسجّل في حسابك.';

  @override
  String get invitationClaimed => 'مستخدَم';

  @override
  String get invitationRevoked => 'مسحوب';

  @override
  String get invitationExpired => 'منتهي';

  @override
  String get invitationOpen => 'بانتظار';

  @override
  String get withdraw => 'سحب';

  @override
  String get withdrawInvitation => 'سحب هذه الدعوة؟';

  @override
  String get withdrawInvitationBody =>
      'يتوقف الرمز عن العمل. لم يُتفق على شيء بعد، فلا شيء يُلغى.';

  @override
  String theyWillBe(String role) {
    return 'سيكون $role';
  }

  @override
  String get buyerWord => 'المشتري';

  @override
  String get sellerWord => 'البائع';

  @override
  String get whoBuyer => 'المشتري';

  @override
  String get whoSeller => 'البائع';

  @override
  String get whoSystem => 'TrustIQ';

  @override
  String evSubmit(String who) {
    return 'أرسل $who العقد';
  }

  @override
  String evAccept(String who) {
    return 'قبل $who الشروط';
  }

  @override
  String evDecline(String who) {
    return 'رفض $who الشروط';
  }

  @override
  String evWithdraw(String who) {
    return 'سحب $who العقد';
  }

  @override
  String evMarkDelivered(String who) {
    return 'سجّل $who أن العمل سُلّم';
  }

  @override
  String evRequestRevision(String who) {
    return 'طلب $who تعديلات';
  }

  @override
  String evConfirmDelivery(String who) {
    return 'أكّد $who التسليم';
  }

  @override
  String evOpenDispute(String who) {
    return 'فتح $who نزاعاً';
  }

  @override
  String evResolveDispute(String who) {
    return 'أنهى $who النزاع';
  }

  @override
  String evCancelByAgreement(String who) {
    return 'ألغى $who العقد';
  }

  @override
  String get evExpire => 'انتهت صلاحية العقد';

  @override
  String get devSubmitForAi => 'وصل بيان الطرفين، وانتقلت القضية إلى الوكيل';

  @override
  String get devIssueProposal => 'اقتُرحت تسوية';

  @override
  String devAcceptProposal(String who) {
    return 'قبل $who التسوية';
  }

  @override
  String devRejectProposal(String who) {
    return 'رفضها $who وطلب شخصاً';
  }

  @override
  String get devEscalate => 'أُحيلت القضية إلى مراجع بشري';

  @override
  String get devAssignReviewer => 'تولّى مراجع القضية';

  @override
  String get devIssueHumanResolution => 'بتّ مراجع في القضية';

  @override
  String devWithdrawDispute(String who) {
    return 'سحب $who النزاع';
  }

  @override
  String get notifications => 'النشاط';

  @override
  String get nothingWaiting => 'لا شيء ينتظرك.';

  @override
  String get nothingWaitingBody =>
      'عندما يتحرّك الطرف الآخر في أحد عقودك، يظهر ذلك هنا.';

  @override
  String get needsYou => 'يحتاجك';

  @override
  String get markAllRead => 'تعليم الكل كمقروء';

  @override
  String get activityNote =>
      'تُبنى هذه القائمة من سجل العقد نفسه، فهي تقول ما حدث بالضبط ولا شيء غير ذلك.';

  @override
  String get stages => 'المراحل';

  @override
  String get stageWaiting => 'لم تبدأ';

  @override
  String get stageDelivered => 'سُلّمت';

  @override
  String get stageAccepted => 'مقبولة';

  @override
  String get markStageDelivered => 'تسجيل التسليم';

  @override
  String get acceptStage => 'قبول هذه المرحلة';

  @override
  String get sendStageBack => 'إعادة';

  @override
  String get sendStageBackTitle => 'إعادة هذه المرحلة؟';

  @override
  String get sendStageBackBody =>
      'سيُبلَّغ البائع بأنها تحتاج عملاً إضافياً. وتبقى المحاولة في السجل: مرحلة استغرقت ثلاث محاولات تُقرأ كثلاث محاولات.';

  @override
  String get stagesNote =>
      'يُتفق على كل مرحلة عند وصولها، لا على الكل في النهاية. وقبول المرحلة الأخيرة يُغلق العقد، فلا يُطلب من أحد التوقيع مرتين على الشيء نفسه.';

  @override
  String stagesTotal(int done, int total) {
    return 'قُبلت $done من $total';
  }

  @override
  String get addAStage => 'إضافة مرحلة';

  @override
  String get stageTitle => 'ما تشمله هذه المرحلة';

  @override
  String get stageAmount => 'مبلغ هذه المرحلة';

  @override
  String get stageExample => 'ثلاثة مفاهيم';

  @override
  String get removeStage => 'حذف';

  @override
  String get stagesOptional =>
      'اختياري. بدون مراحل يكون العقد تسليماً واحداً يُؤكَّد مرة واحدة. ومعها يوافق العميل على كل جزء عند وصوله.';

  @override
  String get stagesOverTotal => 'مجموع المراحل يتجاوز قيمة العقد.';

  @override
  String stagesRemainder(String amount) {
    return '$amount من العقد ليست ضمن أي مرحلة.';
  }

  @override
  String get stagesFixedAfter =>
      'لا يمكن إضافة المراحل أو تعديلها بعد إرسال العقد.';

  @override
  String mvDeliver(String who) {
    return 'سلّم $who مرحلة';
  }

  @override
  String mvAccept(String who) {
    return 'قبل $who مرحلة';
  }

  @override
  String mvRequestRevision(String who) {
    return 'أعاد $who مرحلة';
  }

  @override
  String counterpartyNotVerified(String name) {
    return 'لم يوثّق $name هويته بعد. ولا يصبح العقد ملزماً إلا بين هويتين موثّقتين، فلا يمكن قبول أي شيء قبل أن يفعل.';
  }

  @override
  String get youAreNotVerified => 'هويتك غير موثّقة';

  @override
  String get youAreNotVerifiedBody =>
      'يمكنك صياغة العقود وإرسالها وإيداع الأدلة. أما قبول عقد فيحتاج إلى توثيق هويتك، لأن الطرف الآخر لا سبيل له لمعرفة من وافق.';

  @override
  String get getVerified => 'وثّق هويتك';

  @override
  String get formNeedsVerifiedNote =>
      'أرسله الآن إن شئت. لا يستطيع أيٌّ منكما قبوله قبل توثيق الهويتين، وهويتك ليست موثّقة.';

  @override
  String get amountMustBePositive => 'يجب أن يكون المبلغ أكبر من صفر.';

  @override
  String get amountTwoDecimals =>
      'المبالغ تُكتب بمنزلتين عشريتين. الدرهم الواحد 100 فلس، ولا يوجد أصغر من ذلك.';

  @override
  String get amountFormat => 'أدخل مبلغاً بالدرهم، مثل 500 أو 1250.50.';

  @override
  String get stepWhoWith => 'مع من هذا العقد';

  @override
  String get stepWhoWithBlurb =>
      'سيرى كلاكما العقد نفسه، ولا يستطيع أيٌّ منكما تغييره بعد قبوله.';

  @override
  String get iAmPaying => 'أنا أدفع';

  @override
  String get iAmDelivering => 'أنا أسلّم';

  @override
  String get emailOfDeliverer => 'بريد الشخص الذي يسلّم';

  @override
  String get emailOfPayer => 'بريد الشخص الذي يدفع';

  @override
  String get counterpartyHelper =>
      'يجب أن يكون لديه حساب في TrustIQ مسبقاً. دعوة شخص بلا حساب غير مدعومة بعد.';

  @override
  String get stepWhatAgreed => 'ما تم الاتفاق عليه';

  @override
  String get stepWhatAgreedBlurb =>
      'هذا هو النص الذي سيُحكم عليه أي نزاع، فكن دقيقاً في تحديد ما يُعدّ تسليماً.';

  @override
  String get whatIsBeingDone => 'ما الذي سيُنجَز';

  @override
  String get exampleDescription => 'تصميم شعار لشركة ناشئة';

  @override
  String get exampleTerms =>
      'تسليم ثلاثة مفاهيم مختلفة خلال سبعة أيام. جولتا تعديل. الملفات النهائية بصيغتي SVG و PNG.';

  @override
  String get stepHowMuch => 'بكم';

  @override
  String get stepHowMuchBlurb => 'يُسجَّل حتى الفلس. لا شيء هنا يُقرَّب.';

  @override
  String recordedAs(String amount) {
    return 'سُجّل بـ $amount';
  }

  @override
  String get noEscrowShort =>
      'لا تأخذ TrustIQ هذا المال. هي تسجّل ما اتفقتما عليه ليكون هناك ما يُشار إليه لاحقاً؛ وتدفعان لبعضكما مباشرة.';

  @override
  String get createAsDraft => 'إنشاء كمسودة';

  @override
  String get draftNote =>
      'المسودة لك وحدك حتى ترسلها. وبمجرد قبول الطرف الآخر، لا يستطيع أيٌّ منكما تغيير الشروط.';

  @override
  String get contractCouldNotBeCreated => 'تعذّر إنشاء العقد.';

  @override
  String characterCount(int count) {
    return '$count حرفاً';
  }
}
