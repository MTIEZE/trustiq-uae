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
}
