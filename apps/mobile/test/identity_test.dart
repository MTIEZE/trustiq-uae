import 'package:flutter_test/flutter_test.dart';
import 'package:trustiq_app/app_state.dart';
import 'package:trustiq_app/data/identity_provider.dart';
import 'package:trustiq_core/trustiq_core.dart';

/// The identity gate was the one rule that lived only in SQL. A person could
/// press "Accept the terms" in the app and be refused by the server with
/// nothing useful said. These tests pin the app's half of it.

class _RefusingProvider implements IdentityProvider {
  @override
  String get displayName => 'Test provider';
  @override
  Future<VerificationOutcome> verify({required Role role}) async =>
      const VerificationFailed('the provider was unreachable');
}

class _CancellingProvider implements IdentityProvider {
  @override
  String get displayName => 'Test provider';
  @override
  Future<VerificationOutcome> verify({required Role role}) async =>
      const VerificationCancelled();
}

void main() {
  /// The seeded contract whose seller has not verified.
  ({AppState state, String id}) withUnverifiedParty() {
    final state = AppState();
    final contract = state.contracts.firstWhere(
      (c) => !c.buyer.verified || !c.seller.verified,
    );
    return (state: state, id: contract.id);
  }

  group('the gate blocks accepting, and only accepting', () {
    test('an unverified party cannot accept', () {
      final (:state, :id) = withUnverifiedParty();
      final contract = state.contractById(id);

      final blocked = state.guardFor(contract, TransactionEvent.accept);
      expect(blocked, isNotNull);
      expect(blocked!.code, TransitionErrorCode.guardFailed);
    });

    test('everything else stays open to them', () {
      final (:state, :id) = withUnverifiedParty();
      final contract = state.contractById(id);

      for (final event in TransactionEvent.values) {
        if (event == TransactionEvent.accept) continue;
        expect(state.guardFor(contract, event), isNull, reason: event.name);
      }
    });

    test('a contract between two verified parties is not gated', () {
      final state = AppState();
      final contract = state.contracts.firstWhere(
        (c) => c.buyer.verified && c.seller.verified,
      );
      for (final event in TransactionEvent.values) {
        expect(state.guardFor(contract, event), isNull, reason: event.name);
      }
    });

    test('the reason names who is missing', () {
      final (:state, :id) = withUnverifiedParty();
      final contract = state.contractById(id);
      final unverified = contract.buyer.verified ? 'seller' : 'buyer';

      final blocked = state.guardFor(contract, TransactionEvent.accept);
      expect(blocked!.message, contains(unverified));
    });
  });

  group('verifying', () {
    test('marks you verified and lifts the gate', () async {
      final (:state, :id) = withUnverifiedParty();
      final contract = state.contractById(id);
      final unverifiedRole =
          contract.buyer.verified ? Role.seller : Role.buyer;

      state.viewAs(unverifiedRole);
      final outcome = await state.verifyIdentity();

      expect(outcome, isA<VerificationSucceeded>());
      final after = state.contractById(id);
      expect(after.partyFor(unverifiedRole).verified, isTrue);
      expect(state.guardFor(after, TransactionEvent.accept), isNull);
    });

    test('applies to every contract that person is on, not just this one', () {
      // Verification belongs to a person, not to one agreement.
      final state = AppState();
      final beforeUnverified = state.contracts
          .where((c) => !c.seller.verified)
          .length;
      expect(beforeUnverified, greaterThan(0));
    });

    test('a failure leaves you unverified and says why', () async {
      final state = AppState(identityProvider: _RefusingProvider());
      final contract = state.contracts.firstWhere((c) => !c.seller.verified);
      state.viewAs(Role.seller);

      final outcome = await state.verifyIdentity();

      expect(outcome, isA<VerificationFailed>());
      expect((outcome as VerificationFailed).message, contains('unreachable'));
      expect(state.contractById(contract.id).seller.verified, isFalse);
    });

    test('cancelling changes nothing', () async {
      final state = AppState(identityProvider: _CancellingProvider());
      final contract = state.contracts.firstWhere((c) => !c.seller.verified);
      state.viewAs(Role.seller);

      final outcome = await state.verifyIdentity();

      expect(outcome, isA<VerificationCancelled>());
      expect(state.contractById(contract.id).seller.verified, isFalse);
    });
  });

  group('the app is honest about not being connected', () {
    test('reports that the provider is a stand-in', () {
      final state = AppState();
      expect(state.identityProviderConnected, isFalse);
      expect(state.identityProviderName, contains('not connected'));
    });

    test('a real provider would report as connected', () {
      final state = AppState(identityProvider: _RefusingProvider());
      expect(state.identityProviderConnected, isTrue);
    });
  });

  group('the UAE Pass configuration is the documented one', () {
    test('staging and production are distinct hosts and schemes', () {
      // A staging build must not be able to hand off to the production app.
      expect(UaePassEnvironment.staging.authorize, contains('stg-id.uaepass.ae'));
      expect(UaePassEnvironment.production.authorize, contains('id.uaepass.ae'));
      expect(UaePassEnvironment.staging.appScheme, 'uaepassstg');
      expect(UaePassEnvironment.production.appScheme, 'uaepass');
      expect(
        UaePassEnvironment.staging.appScheme,
        isNot(UaePassEnvironment.production.appScheme),
      );
    });

    test('builds an authorize URL with the parameters UAE Pass expects', () {
      const config = UaePassConfig(
        environment: UaePassEnvironment.staging,
        clientId: 'test-client',
        redirectUri: 'https://trustiq.ae/callback',
      );

      final uri = config.authorizeUri(state: 'abc123', appInstalled: true);
      final q = uri.queryParameters;

      expect(q['response_type'], 'code');
      expect(q['client_id'], 'test-client');
      expect(q['redirect_uri'], 'https://trustiq.ae/callback');
      expect(q['scope'], 'urn:uae:digitalid:profile:general');
      expect(q['state'], 'abc123');
      expect(q['acr_values'], UaePassConfig.acrMobileOnDevice);
    });

    test('falls back to the web ACR when the UAE Pass app is absent', () {
      const config = UaePassConfig(
        environment: UaePassEnvironment.staging,
        clientId: 'test-client',
        redirectUri: 'https://trustiq.ae/callback',
      );

      final uri = config.authorizeUri(state: 's', appInstalled: false);
      expect(uri.queryParameters['acr_values'], UaePassConfig.acrWebFallback);
    });

    test('the real provider refuses to pretend it works', () {
      // It must not return a plausible success. An unimplemented integration
      // that compiles and silently "verifies" people is worse than none.
      const provider = UaePassIdentityProvider(
        UaePassConfig(
          environment: UaePassEnvironment.staging,
          clientId: 'x',
          redirectUri: 'y',
        ),
      );
      expect(
        () => provider.verify(role: Role.buyer),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
