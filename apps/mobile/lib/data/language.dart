import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which language the app is in, and remembering it.
///
/// Two, and only two: English and Arabic. TrustIQ is built for the UAE, where
/// both are working languages, and a half-supported third would be worse than
/// none.
///
/// The choice is stored on the device rather than on the account, because
/// somebody has to be able to read the sign-in screen before they have an
/// account to store anything on.
class LanguageController extends ChangeNotifier {
  LanguageController._(this._locale);

  static const supported = [Locale('en'), Locale('ar')];
  static const _key = 'trustiq.locale';

  Locale? _locale;

  /// Null means follow the device. That is the default: a phone set to Arabic
  /// should open in Arabic without anyone being asked.
  Locale? get locale => _locale;

  /// What the app is actually showing, once the device has been consulted.
  Locale resolved(Locale? deviceLocale) {
    if (_locale != null) return _locale!;
    final device = deviceLocale?.languageCode;
    return device == 'ar' ? const Locale('ar') : const Locale('en');
  }

  /// A controller with no storage behind it, for tests and for the widget
  /// tree when nobody passed one in.
  factory LanguageController.forTests([Locale? locale]) => LanguageController._(locale);

  static Future<LanguageController> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      return LanguageController._(_parse(saved));
    } catch (_) {
      // A device that will not give us storage is not a reason to fail to
      // start. It just means the choice does not survive a restart.
      return LanguageController._(null);
    }
  }

  static Locale? _parse(String? code) {
    if (code == null) return null;
    for (final locale in supported) {
      if (locale.languageCode == code) return locale;
    }
    return null;
  }

  Future<void> set(Locale? locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, locale.languageCode);
      }
    } catch (_) {
      // Already switched on screen; only the remembering failed.
    }
  }
}
