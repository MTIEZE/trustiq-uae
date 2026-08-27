import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/language_button.dart';

/// What TrustIQ is, before anyone is asked for an email address.
///
/// Somebody who downloaded this on a recommendation knows nothing about it,
/// and the first thing the app used to do was ask them to create an account.
/// A sign-in form is a request for trust, and it was being made before a
/// single sentence had been offered in return.
///
/// Four panels, in the order the questions actually arrive: what is this, what
/// happens if it goes wrong, what does it not do, and what does it want from
/// me. The third one is the one that earns the account: a product that says
/// plainly what it cannot do is easier to believe about what it can.
///
/// Reachable again afterwards, from the sign-in screen and from the contract
/// list. An explanation you can only ever see once is not documentation.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onFinished, this.onSignIn});

  /// Called when the person is done and wants to get on with it. Null when the
  /// screen was opened for reference rather than as the first launch, in which
  /// case it simply pops.
  final VoidCallback? onFinished;

  /// Called instead of [onFinished] by "I already have one". Both currently
  /// lead to the same place, but the two are different intentions and the
  /// screen should not decide they are the same.
  final VoidCallback? onSignIn;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Panel {
  const _Panel({
    required this.icon,
    required this.title,
    required this.body,
    required this.aside,
  });

  final IconData icon;
  final String title;
  final String body;
  final String aside;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _at = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<_Panel> _panels(L l) => [
        _Panel(
          icon: Icons.handshake_outlined,
          title: l.onboarding1Title,
          body: l.onboarding1Body,
          aside: l.onboarding1Aside,
        ),
        _Panel(
          icon: Icons.balance_outlined,
          title: l.onboarding2Title,
          body: l.onboarding2Body,
          aside: l.onboarding2Aside,
        ),
        _Panel(
          // Crossed out on purpose. This panel is about an absence, and an
          // icon of a wallet would say the opposite of the sentence under it.
          icon: Icons.money_off_outlined,
          title: l.onboarding3Title,
          body: l.onboarding3Body,
          aside: l.onboarding3Aside,
        ),
        _Panel(
          icon: Icons.badge_outlined,
          title: l.onboarding4Title,
          body: l.onboarding4Body,
          aside: l.onboarding4Aside,
        ),
      ];

  void _finish() {
    if (widget.onFinished != null) {
      widget.onFinished!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goToSignIn() {
    if (widget.onSignIn != null) {
      widget.onSignIn!();
    } else {
      _finish();
    }
  }

  void _next(int count) {
    if (_at >= count - 1) {
      _finish();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    final panels = _panels(l);
    final last = _at == panels.length - 1;
    // Opened for reference rather than at first launch. The closing buttons
    // should then say "got it", not "create an account".
    final reference = widget.onFinished == null && widget.onSignIn == null;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.accentGlow, c.ground],
            stops: const [0, 0.55],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(
                showSkip: !last && !reference,
                onSkip: _finish,
                onClose: reference ? _finish : null,
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _at = i),
                  itemCount: panels.length,
                  itemBuilder: (_, i) => _PanelView(panel: panels[i]),
                ),
              ),
              _Dots(count: panels.length, at: _at),
              const SizedBox(height: Space.lg),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: last
                      ? _Finish(reference: reference, onDone: _finish, onSignIn: _goToSignIn)
                      : SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => _next(panels.length),
                            child: Text(l.onboardingNext),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showSkip, required this.onSkip, this.onClose});

  final bool showSkip;
  final VoidCallback onSkip;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.sm, Space.sm, 0),
      child: Row(
        children: [
          const TrustIqBar(),
          const Spacer(),
          // Before the account exists, this is the only way an Arabic reader
          // can reach a sentence they can read. It belongs on the first screen,
          // not behind one.
          const LanguageButton(compact: true),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, size: IconSize.lg),
            )
          else if (showSkip)
            TextButton(onPressed: onSkip, child: Text(l.onboardingSkip))
          else
            const SizedBox(width: Space.lg),
        ],
      ),
    );
  }
}

class _PanelView extends StatelessWidget {
  const _PanelView({required this.panel});
  final _Panel panel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                child: Icon(panel.icon, size: IconSize.hero, color: c.accent),
              ),
              const SizedBox(height: Space.xl),
              Text(
                panel.title,
                style: TextStyle(
                  fontSize: 25,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: Space.md),
              Text(
                panel.body,
                style: TextStyle(fontSize: 15.5, height: 1.6, color: c.inkSoft),
              ),
              const SizedBox(height: Space.lg),
              RuleNote(panel.aside),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.at});
  final int count;
  final int at;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    return Semantics(
      // The dots are decoration. A screen reader gets the sentence instead.
      label: l.onboardingStep(at + 1, count),
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 6,
                width: i == at ? 22 : 6,
                decoration: BoxDecoration(
                  color: i == at ? c.accent : c.ruleStrong,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Finish extends StatelessWidget {
  const _Finish({required this.reference, required this.onDone, required this.onSignIn});

  final bool reference;
  final VoidCallback onDone;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    if (reference) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: onDone, child: Text(l.onboardingDone)),
      );
    }
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onDone,
            child: Text(l.onboardingCreateAccount),
          ),
        ),
        const SizedBox(height: Space.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onSignIn,
            child: Text(l.onboardingHaveAccount),
          ),
        ),
      ],
    );
  }
}
