import 'package:shared_preferences/shared_preferences.dart';

/// Whether this person has been told what TrustIQ is.
///
/// Stored on the device rather than on the account, for the same reason the
/// language is: the explanation has to come before the account, so there is
/// nowhere else to keep it yet.
class OnboardingGate {
  OnboardingGate._(this._seen);

  static const _key = 'trustiq.onboarded';

  bool _seen;
  bool get seen => _seen;

  /// A gate with no storage behind it, for tests and for a widget tree that
  /// was handed nothing.
  factory OnboardingGate.forTests({bool seen = true}) => OnboardingGate._(seen);

  static Future<OnboardingGate> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return OnboardingGate._(prefs.getBool(_key) ?? false);
    } catch (_) {
      // A device that will not give us storage defaults to showing the
      // introduction, not to skipping it. Seeing it twice is a small
      // annoyance with a skip button on it. Never seeing it is the problem
      // this whole screen exists to fix.
      return OnboardingGate._(false);
    }
  }

  Future<void> markSeen() async {
    if (_seen) return;
    _seen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {
      // Same as above: worth showing again rather than failing to start.
    }
  }
}
