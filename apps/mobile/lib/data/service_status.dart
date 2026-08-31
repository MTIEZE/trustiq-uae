import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

/// The remote stop button, read at launch.
///
/// Once an app is in the stores a fix cannot ship in under a day, and an Apple
/// review takes several. This is the one thing that can be changed faster than
/// that: a static file on the marketing site, which every build fetches when
/// it opens.
///
/// It is not in the database on purpose. The schema tests hold an absolute
/// line that nothing in `public` is callable with the key that ships inside the
/// app, and a status readable before sign-in would have meant a hole in it.
/// More to the point, a stop button housed in the system it is meant to stop is
/// not a stop button: the day the backend has an incident is exactly when you
/// want to say so, and exactly when the database cannot be asked.
///
/// Every failure means open. Offline, 404, timeout, malformed JSON, a mode
/// nobody recognises: all of them let the app run. A switch that bricks the app
/// when the network is poor is worse than no switch, and this product already
/// has a tester on 3G in Cameroon.
@immutable
class ServiceStatus {
  const ServiceStatus({
    required this.mode,
    required this.minimumBuild,
    required this.noticeEn,
    required this.noticeAr,
  });

  /// What the app assumes, and what it falls back to from anywhere.
  static const open = ServiceStatus(mode: 'open', minimumBuild: 0, noticeEn: '', noticeAr: '');

  final String mode;
  final int minimumBuild;
  final String noticeEn;
  final String noticeAr;

  /// Only the exact word stops the app. An unrecognised mode is a file written
  /// wrongly, and the safe reading of a file written wrongly is "carry on".
  bool get paused => mode == 'maintenance';

  /// A build of 0 means the binary was not told its own number, which is every
  /// `flutter run`. Those are never held back: the alternative is a developer
  /// locked out of their own app by a file they cannot see.
  bool tooOld(int build) => build > 0 && build < minimumBuild;

  bool heldFor(int build) => paused || tooOld(build);

  String notice(String languageCode) {
    if (languageCode == 'ar' && noticeAr.trim().isNotEmpty) return noticeAr.trim();
    return noticeEn.trim();
  }

  static ServiceStatus parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return open;

    final notice = decoded['notice'];
    String text(String key) {
      if (notice is! Map) return '';
      final value = notice[key];
      return value is String ? value : '';
    }

    final minimum = decoded['minimumBuild'];
    return ServiceStatus(
      mode: decoded['mode'] is String ? decoded['mode'] as String : 'open',
      minimumBuild: minimum is int ? minimum : 0,
      noticeEn: text('en'),
      noticeAr: text('ar'),
    );
  }
}

/// Fetches it, and never throws.
Future<ServiceStatus> fetchServiceStatus({
  http.Client? client,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final url = TrustIqConfig.statusUrl;
  if (url.isEmpty) return ServiceStatus.open;

  final own = client == null;
  final c = client ?? http.Client();
  try {
    final response = await c.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode != 200) return ServiceStatus.open;
    return ServiceStatus.parse(response.body);
  } catch (e) {
    // Including a timeout. Three seconds is a long time on a bad connection
    // and still shorter than anyone will wait to be told nothing is wrong.
    debugPrint('TrustIQ: could not read the service status: $e');
    return ServiceStatus.open;
  } finally {
    if (own) c.close();
  }
}

/// Holds the answer, and lets a screen ask again.
class ServiceStatusGate extends ChangeNotifier {
  ServiceStatusGate({this.build = TrustIqConfig.buildNumber, this.fetch = fetchServiceStatus});

  final int build;
  final Future<ServiceStatus> Function({http.Client? client, Duration timeout}) fetch;

  ServiceStatus _status = ServiceStatus.open;
  ServiceStatus get status => _status;

  bool get held => _status.heldFor(build);
  bool get outdated => _status.tooOld(build);

  bool _checking = false;
  bool get checking => _checking;

  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    notifyListeners();

    _status = await fetch();

    _checking = false;
    notifyListeners();
  }
}
