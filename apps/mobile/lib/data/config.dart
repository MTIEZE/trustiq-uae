/// Where the app points, and the one key it is allowed to carry.
///
/// Supplied at build time so a binary is bound to a project rather than
/// deciding at runtime:
///
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
///
/// With neither set the app runs on demo data. That is the default on purpose:
/// a build with no configuration should be obviously a demo, not a broken app
/// pointed at nothing.
library;

import 'dart:convert';

/// The mistake this file exists to prevent.
class ServiceRoleKeyInAppError extends Error {
  ServiceRoleKeyInAppError(this.detail);
  final String detail;

  @override
  String toString() =>
      'SUPABASE_ANON_KEY looks like a service-role key ($detail).\n'
      '\n'
      'That key bypasses row level security completely. In a mobile build it '
      'is readable by anyone who downloads the app, and it grants read and '
      'write access to every contract, dispute and document belonging to every '
      'user of the system.\n'
      '\n'
      'Use the publishable key. If this key has already been in a build, treat '
      'it as compromised and rotate it in the Supabase dashboard now.';
}

class TrustIqConfig {
  const TrustIqConfig._({required this.url, required this.anonKey});

  /// Demo mode: no project, no network, no session.
  const TrustIqConfig.demo()
      : url = '',
        anonKey = '';

  final String url;
  final String anonKey;

  /// Where someone writes to be verified while UAE Pass is not connected.
  ///
  /// Empty by default and shown only when set. A placeholder address here
  /// would be worse than saying nothing: it would send a beta tester to a
  /// mailbox nobody reads, and they would conclude they had been ignored.
  static const verificationContact =
      String.fromEnvironment('TRUSTIQ_VERIFY_CONTACT');

  bool get isLive => url.isNotEmpty && anonKey.isNotEmpty;

  /// The project host, for showing which backend a build is talking to.
  String get label => isLive ? Uri.parse(url).host : 'demo data';

  /// Points at a project without going through the build flags.
  ///
  /// For tools and integration checks that already hold the values, and named
  /// the way LanguageController.forTests and OnboardingGate.forTests are, so
  /// nothing here looks like a second production path. It runs the same
  /// service-role refusal: a constructor that skipped it would be a way round
  /// the one check this file exists for.
  factory TrustIqConfig.of({required String url, required String anonKey}) {
    final complaint = describeServiceRoleKey(anonKey);
    if (complaint != null) throw ServiceRoleKeyInAppError(complaint);
    return TrustIqConfig._(url: url, anonKey: anonKey);
  }

  /// Reads the build-time configuration.
  ///
  /// Throws rather than falling back to demo mode when a service-role key is
  /// supplied. Quietly ignoring it would leave the key in the binary anyway,
  /// and the person who set it would never learn what they had done.
  factory TrustIqConfig.fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');

    if (url.isEmpty && key.isEmpty) return const TrustIqConfig.demo();
    if (url.isEmpty || key.isEmpty) {
      throw ArgumentError(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be given together. '
        'Give both to run against a project, or neither to run on demo data.',
      );
    }

    final complaint = describeServiceRoleKey(key);
    if (complaint != null) throw ServiceRoleKeyInAppError(complaint);

    return TrustIqConfig._(url: url, anonKey: key);
  }
}

/// Says why a key looks like a service-role key, or null if it does not.
///
/// Both key formats are checked because both are in circulation: newer
/// projects issue `sb_publishable_` and `sb_secret_`, older ones issue JWTs
/// whose payload carries the role. Getting these two the wrong way round is
/// the single most damaging configuration mistake available in this codebase,
/// and it produces an app that works perfectly until someone opens the bundle.
String? describeServiceRoleKey(String key) {
  if (key.startsWith('sb_secret_')) return 'it starts with sb_secret_';

  final parts = key.split('.');
  if (parts.length == 3) {
    final payload = _decodeSegment(parts[1]);
    if (payload != null && payload.contains('"service_role"')) {
      return 'its JWT payload names the service_role';
    }
  }
  return null;
}

String? _decodeSegment(String segment) {
  try {
    final normalised = segment.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalised.padRight((normalised.length + 3) ~/ 4 * 4, '=');
    return utf8.decode(base64.decode(padded), allowMalformed: true);
  } catch (_) {
    return null;
  }
}
