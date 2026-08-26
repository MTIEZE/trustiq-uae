/// Identity verification.
///
/// TrustIQ verifies identity through **UAE Pass**, the national digital
/// identity. This file holds the shape of that integration and a stand-in that
/// lets the app run without it. It does not hold a working connection, and it
/// does not pretend to: UAE Pass requires registration as a Service Provider,
/// which is a business process, not a code change.
///
/// What is real here is the OIDC flow's shape and the staging endpoints, taken
/// from the UAE Pass integration documentation rather than from memory:
///
///   authorize  https://stg-id.uaepass.ae/idshub/authorize
///   token      https://stg-id.uaepass.ae/idshub/token
///   userinfo   https://stg-id.uaepass.ae/idshub/userinfo
///   logout     https://stg-id.uaepass.ae/idshub/logout
///
/// What is deliberately absent: a client id, a client secret, and the exact
/// claim names for the profile. Those come with SP onboarding, and guessing
/// them would put fiction in the codebase.
library;

import 'package:trustiq_core/trustiq_core.dart';

/// Which UAE Pass environment a build talks to.
enum UaePassEnvironment {
  /// Staging, used for the proof of concept before SP approval.
  staging(
    authorize: 'https://stg-id.uaepass.ae/idshub/authorize',
    token: 'https://stg-id.uaepass.ae/idshub/token',
    userinfo: 'https://stg-id.uaepass.ae/idshub/userinfo',
    logout: 'https://stg-id.uaepass.ae/idshub/logout',
    // The staging app registers a distinct scheme from production, so a
    // staging build cannot hand off to a production app or the reverse.
    appScheme: 'uaepassstg',
  ),

  /// Production. The host is the documented one; confirm the paths against the
  /// onboarding pack before a release, rather than assuming they mirror staging.
  production(
    authorize: 'https://id.uaepass.ae/idshub/authorize',
    token: 'https://id.uaepass.ae/idshub/token',
    userinfo: 'https://id.uaepass.ae/idshub/userinfo',
    logout: 'https://id.uaepass.ae/idshub/logout',
    appScheme: 'uaepass',
  );

  const UaePassEnvironment({
    required this.authorize,
    required this.token,
    required this.userinfo,
    required this.logout,
    required this.appScheme,
  });

  final String authorize;
  final String token;
  final String userinfo;
  final String logout;

  /// The scheme the UAE Pass app answers on, used for the app-to-app handoff.
  final String appScheme;
}

/// The values that only exist once TrustIQ is an approved Service Provider.
class UaePassConfig {
  const UaePassConfig({
    required this.environment,
    required this.clientId,
    required this.redirectUri,
  });

  final UaePassEnvironment environment;

  /// Issued at SP onboarding. Never hardcoded in the app.
  final String clientId;

  /// Must match the value registered with UAE Pass exactly.
  final String redirectUri;

  /// The general profile scope. Visitor flows add profileType and unifiedId
  /// scopes on top; that is a separate onboarding decision.
  static const String scope = 'urn:uae:digitalid:profile:general';

  /// Used when the UAE Pass app is installed and the handoff can happen
  /// device-to-device.
  static const String acrMobileOnDevice =
      'urn:digitalid:authentication:flow:mobileondevice';

  /// Used when it is not, and the person authenticates in a web view.
  static const String acrWebFallback =
      'urn:safelayer:tws:policies:authentication:level:low';

  Uri authorizeUri({required String state, required bool appInstalled}) {
    return Uri.parse(environment.authorize).replace(queryParameters: {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': scope,
      'state': state,
      'acr_values': appInstalled ? acrMobileOnDevice : acrWebFallback,
    });
  }
}

/// What TrustIQ keeps after a successful verification.
///
/// Deliberately small. UAE Pass can return around eighteen attributes for a
/// full profile; TrustIQ needs a stable identifier and a display name, so that
/// is what the model holds. Every extra field is a field to secure, justify to
/// a regulator, and delete on request.
class VerifiedIdentity {
  const VerifiedIdentity({
    required this.subject,
    required this.fullName,
    required this.verifiedAt,
  });

  /// The stable per-user identifier from the provider. Not the Emirates ID.
  ///
  /// The Emirates ID number is available from the profile and TrustIQ does not
  /// store it: it identifies a person across every system in the country, and
  /// holding it would make this database worth attacking for reasons that have
  /// nothing to do with TrustIQ.
  final String subject;

  final String fullName;
  final DateTime verifiedAt;
}

sealed class VerificationOutcome {
  const VerificationOutcome();
}

final class VerificationSucceeded extends VerificationOutcome {
  const VerificationSucceeded(this.identity);
  final VerifiedIdentity identity;
}

final class VerificationCancelled extends VerificationOutcome {
  const VerificationCancelled();
}

final class VerificationFailed extends VerificationOutcome {
  const VerificationFailed(this.message);
  final String message;
}

/// Starting a verification and getting its result.
abstract interface class IdentityProvider {
  /// A name for what the person is about to be sent to.
  String get displayName;

  Future<VerificationOutcome> verify({required Role role});
}

/// The real one, once TrustIQ is an approved Service Provider.
///
/// Left unimplemented on purpose. Writing a plausible-looking body here would
/// produce something that compiles, reads as finished, and does not work, and
/// the failure would surface at the worst possible moment: a real person
/// trying to verify.
class UaePassIdentityProvider implements IdentityProvider {
  const UaePassIdentityProvider(this.config);

  final UaePassConfig config;

  @override
  String get displayName => 'UAE Pass';

  @override
  Future<VerificationOutcome> verify({required Role role}) {
    throw UnimplementedError(
      'UAE Pass is not connected yet. It needs a Service Provider registration '
      'and a client id before this can do anything real. The flow: open '
      '${config.environment.authorize} in a web view, watch for a '
      '${config.environment.appScheme}:// deep link and rewrite its successURL '
      'and failureURL to this app, exchange the returned code at '
      '${config.environment.token}, then read the profile from '
      '${config.environment.userinfo}.',
    );
  }
}

/// The stand-in the app runs on today.
///
/// It is not a mock of UAE Pass. It verifies nothing and checks nothing; it
/// exists so the screens either side of verification can be built and used
/// before the real integration lands, and it is named so nobody mistakes it
/// for the real thing.
class DemoIdentityProvider implements IdentityProvider {
  const DemoIdentityProvider();

  @override
  String get displayName => 'UAE Pass (not connected)';

  @override
  Future<VerificationOutcome> verify({required Role role}) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return VerificationSucceeded(
      VerifiedIdentity(
        subject: 'demo-subject-${role.wireName}',
        fullName: role == Role.buyer ? 'Ahmed Al-Rashid' : 'Sara Design Studio',
        verifiedAt: DateTime.now(),
      ),
    );
  }
}
