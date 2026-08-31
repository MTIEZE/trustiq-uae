import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trustiq_app/data/demo_backend.dart';
import 'package:trustiq_app/data/service_status.dart';
import 'package:trustiq_app/main.dart';
import 'package:trustiq_app/screens/held_screen.dart';
import 'package:trustiq_app/screens/onboarding_screen.dart';

/// The remote stop button, and the one property that matters more than whether
/// it works: that it cannot go off by accident.
void main() {
  group('reading the file', () {
    test('a paused service is paused', () {
      final s = ServiceStatus.parse('{"mode":"maintenance"}');
      expect(s.paused, isTrue);
      expect(s.heldFor(12), isTrue);
    });

    test('an old build is held back', () {
      final s = ServiceStatus.parse('{"mode":"open","minimumBuild":9}');
      expect(s.tooOld(8), isTrue);
      expect(s.tooOld(9), isFalse);
      expect(s.tooOld(10), isFalse);
    });

    test('a build that does not know its own number is never held back', () {
      // Every `flutter run`. Locking a developer out of their own app with a
      // file they cannot see would be worse than the failure this prevents.
      final s = ServiceStatus.parse('{"mode":"open","minimumBuild":9999}');
      expect(s.tooOld(0), isFalse);
      expect(s.heldFor(0), isFalse);
    });

    test('the notice follows the reader', () {
      final s = ServiceStatus.parse(
        '{"notice":{"en":"Back at six.","ar":"نعود في السادسة."}}',
      );
      expect(s.notice('en'), 'Back at six.');
      expect(s.notice('ar'), 'نعود في السادسة.');
    });

    test('an empty Arabic notice falls back rather than showing nothing', () {
      final s = ServiceStatus.parse('{"notice":{"en":"Back at six.","ar":"  "}}');
      expect(s.notice('ar'), 'Back at six.');
    });

    // Everything below is a file written wrongly, and the safe reading of a
    // file written wrongly is "carry on".
    for (final entry in {
      'a mode nobody recognises': '{"mode":"closed"}',
      'a mode of the wrong type': '{"mode":42}',
      'no mode at all': '{"minimumBuild":3}',
      'a build number that is not a number': '{"minimumBuild":"nine"}',
      'a notice that is not an object': '{"notice":"soon"}',
      'an empty object': '{}',
      'an array': '[]',
      'a bare string': '"maintenance"',
    }.entries) {
      test('${entry.key} means open', () {
        final s = ServiceStatus.parse(entry.value);
        expect(s.heldFor(5), isFalse, reason: entry.value);
      });
    }
  });

  group('fetching it', () {
    Future<ServiceStatus> against(MockClient client) =>
        fetchServiceStatus(client: client, timeout: const Duration(milliseconds: 200));

    test('a served file is read', () async {
      final s = await against(MockClient((_) async =>
          http.Response('{"mode":"maintenance"}', 200)));
      expect(s.paused, isTrue);
    });

    test('a 404 means open', () async {
      final s = await against(MockClient((_) async => http.Response('nope', 404)));
      expect(s.heldFor(5), isFalse);
    });

    test('a 500 means open', () async {
      final s = await against(MockClient((_) async =>
          http.Response('{"mode":"maintenance"}', 500)));
      expect(s.heldFor(5), isFalse);
    });

    test('malformed JSON means open', () async {
      final s = await against(MockClient((_) async => http.Response('{oh dear', 200)));
      expect(s.heldFor(5), isFalse);
    });

    test('no connection means open', () async {
      final s = await against(MockClient((_) async {
        throw const SocketException('Failed host lookup');
      }));
      expect(s.heldFor(5), isFalse);
    });

    test('a server that never answers means open', () async {
      // The one a tester on 3G will actually hit.
      final s = await against(MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response('{"mode":"maintenance"}', 200);
      }));
      expect(s.heldFor(5), isFalse);
    });
  });

  group('the file that actually ships', () {
    // The dangerous failure is not the app breaking, it is the switch being
    // silently inoperative: a typo in status.json leaves every app failing
    // open, which looks exactly like everything being fine. This reads the real
    // file with the real parser so that cannot ship.
    final file = File('../web/public/status.json');

    test('it exists where the app will look for it', () {
      expect(file.existsSync(), isTrue,
          reason: 'apps/web/public/status.json is what the app fetches at launch');
    });

    test('it is valid JSON and the app can read it', () {
      final body = file.readAsStringSync();
      expect(() => jsonDecode(body), returnsNormally);
      final status = ServiceStatus.parse(body);
      expect(status.mode, anyOf('open', 'maintenance'),
          reason: 'any other word silently means open');
    });

    test('as committed it lets everybody in', () {
      // If this fails on main, somebody paused the service and did not put it
      // back. That is worth failing a build over.
      final status = ServiceStatus.parse(file.readAsStringSync());
      expect(status.heldFor(1), isFalse);
      expect(status.heldFor(999999), isFalse);
    });
  });

  group('what somebody sees', () {
    ServiceStatusGate gate(String body, {int build = 5}) {
      final g = ServiceStatusGate(
        build: build,
        fetch: ({http.Client? client, Duration timeout = Duration.zero}) async =>
            ServiceStatus.parse(body),
      );
      return g;
    }

    testWidgets('a paused service is said so before anything else', (tester) async {
      final g = gate('{"mode":"maintenance","notice":{"en":"Back at six."}}');
      await g.check();

      await tester.pumpWidget(TrustIqApp(backend: DemoBackend(), status: g));
      await tester.pumpAndSettle();

      expect(find.byType(HeldScreen), findsOneWidget);
      expect(find.text('Back at six.'), findsOneWidget,
          reason: 'the incident note is what says what is actually happening');
    });

    testWidgets('and it comes before the introduction, not after it', (tester) async {
      // Somebody meeting TrustIQ during an incident should be told there is
      // one, not walked through four panels and failed at the account step.
      final g = gate('{"mode":"maintenance"}');
      await g.check();

      await tester.pumpWidget(TrustIqApp(
        backend: DemoBackend(),
        onboarding: null,
        status: g,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(HeldScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('an open service is not mentioned at all', (tester) async {
      final g = gate('{"mode":"open"}');
      await g.check();

      await tester.pumpWidget(TrustIqApp(backend: DemoBackend(), status: g));
      await tester.pumpAndSettle();

      expect(find.byType(HeldScreen), findsNothing);
    });

    testWidgets('a tree with no gate at all behaves like an open service', (tester) async {
      await tester.pumpWidget(TrustIqApp(backend: DemoBackend()));
      await tester.pumpAndSettle();
      expect(find.byType(HeldScreen), findsNothing);
    });

    testWidgets('checking again can lift it', (tester) async {
      var body = '{"mode":"maintenance"}';
      final g = ServiceStatusGate(
        build: 5,
        fetch: ({http.Client? client, Duration timeout = Duration.zero}) async =>
            ServiceStatus.parse(body),
      );
      await g.check();

      await tester.pumpWidget(TrustIqApp(backend: DemoBackend(), status: g));
      await tester.pumpAndSettle();
      expect(find.byType(HeldScreen), findsOneWidget);

      body = '{"mode":"open"}';
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.byType(HeldScreen), findsNothing,
          reason: 'nobody should have to kill the app to find out it is back');
    });
  });
}
