import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/backend.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/language_button.dart';
import 'onboarding_screen.dart';

/// Getting into a real project: signing in, signing up, and getting back in
/// after forgetting a password.
///
/// One screen for all three because they are the same two fields and a person
/// arriving here often does not know which one they need. Switching between
/// them keeps what has already been typed.
///
/// Never shown in demo mode. A sign-in form for data that is not stored
/// anywhere would be theatre.
enum _Mode { signIn, signUp, reset }

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _showPassword = false;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _emailLooksReal {
    final at = _email.text.trim();
    return at.length > 3 && at.contains('@') && at.split('@').last.contains('.');
  }

  /// Long enough to be worth having, and no rule the person cannot see.
  ///
  /// Supabase enforces its own minimum and will refuse a short one anyway;
  /// saying so here means they find out while typing rather than after a round
  /// trip that reads like a failure.
  String? get _passwordComplaint {
    if (_mode != _Mode.signUp) return null;
    if (_password.text.isEmpty) return null;
    if (_password.text.length < 8) return _l.passwordTooShort;
    return null;
  }

  bool get _canSubmit {
    if (_busy || !_emailLooksReal) return false;
    switch (_mode) {
      case _Mode.reset:
        return true;
      case _Mode.signIn:
        return _password.text.isNotEmpty;
      case _Mode.signUp:
        return _password.text.length >= 8 && _name.text.trim().length >= 2;
    }
  }

  void _switchTo(_Mode mode) {
    setState(() {
      _mode = mode;
      _notice = null;
    });
    widget.state.clearError();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _notice = null;
    });

    switch (_mode) {
      case _Mode.signIn:
        await widget.state.signIn(email: _email.text, password: _password.text);
      case _Mode.signUp:
        final outcome = await widget.state.signUp(
          email: _email.text,
          password: _password.text,
          fullName: _name.text,
        );
        if (outcome == SignUpOutcome.confirmationRequired && mounted) {
          setState(() {
            _notice = _l.confirmEmailNotice(_email.text.trim());
            _mode = _Mode.signIn;
          });
        }
      case _Mode.reset:
        final sent = await widget.state.sendPasswordReset(_email.text);
        if (sent && mounted) {
          // Says the same thing whether or not the address has an account. The
          // other answer turns this form into a way to find out who is a user.
          setState(() {
            _notice = _l.resetSentNotice(_email.text.trim());
            _mode = _Mode.signIn;
          });
        }
    }

    if (!mounted) return;
    setState(() => _busy = false);

    // A tester in Cameroon saw the raw Dart exception here, project URL and
    // all, because a DNS failure is not an AuthException and nothing caught it.
    final failed = describeFailure(widget.state, context.l);
    if (failed != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed.detail == null ? failed.title : '${failed.title} ${failed.detail}',
          ),
          backgroundColor: context.c.critical,
        ),
      );
    }
  }

  L get _l => context.l;

  String get _title {
    final l = _l;
    return switch (_mode) {
        _Mode.signIn => l.signInTitle,
        _Mode.signUp => l.signUpTitle,
        _Mode.reset => l.resetTitle,
    };
  }

  String get _action {
    final l = _l;
    return switch (_mode) {
        _Mode.signIn => l.signInAction,
        _Mode.signUp => l.signUpAction,
        _Mode.reset => l.resetAction,
    };
  }

  String get _subtitle {
    final l = _l;
    return switch (_mode) {
        _Mode.signIn => l.signInSubtitle,
        _Mode.signUp => l.signUpSubtitle,
        _Mode.reset => l.resetSubtitle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    return Scaffold(
      // A quiet wash behind the card rather than flat grey. It gives the form
      // somewhere to sit on a wide screen, where a bare column just floats.
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.accentGlow, c.ground],
            stops: [0, 0.55],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.xl,
                vertical: Space.section,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TrustIqLockup(subtitle: l.brandPromise),
                    const SizedBox(height: Space.md),
                    const LanguageButton(),
                    const SizedBox(height: Space.lg),
                    _card(context),
                    const SizedBox(height: Space.md),
                    // The introduction is skippable and skipped, and a person
                    // who did that still has to be able to find out what they
                    // are signing up to.
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OnboardingScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.help_outline, size: IconSize.md),
                      label: Text(l.whatIsTrustIq),
                    ),
                    const SizedBox(height: Space.md),
                    RuleNote(l.privacyNote, icon: Icons.lock_outline),
                    const SizedBox(height: Space.lg),
                    Text(
                      widget.state.backendLabel,
                      textAlign: TextAlign.center,
                      style: Type.caption.copyWith(color: c.inkFaint),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final c = context.c;
    final l = context.l;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: c.lift,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.rule),
        ),
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_title, style: Type.heading),
            const SizedBox(height: Space.xs),
            Text(_subtitle, style: Type.small.copyWith(color: c.inkFaint)),
            const SizedBox(height: Space.xl),
            if (_notice != null) ...[
              _Notice(_notice!),
              const SizedBox(height: Space.lg),
            ],
            if (_mode == _Mode.signUp) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(
                  labelText: l.fieldName,
                  helperText: l.fieldNameHelper,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Space.lg),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: l.fieldEmail),
              onChanged: (_) => setState(() {}),
            ),
            if (_mode != _Mode.reset) ...[
              const SizedBox(height: Space.lg),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                autofillHints: [
                  _mode == _Mode.signUp ? AutofillHints.newPassword : AutofillHints.password,
                ],
                decoration: InputDecoration(
                  labelText: l.fieldPassword,
                  errorText: _passwordComplaint,
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? l.hidePassword : l.showPassword,
                    icon: Icon(
                      _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: IconSize.md,
                      color: c.inkFaint,
                    ),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _canSubmit ? _submit() : null,
              ),
            ],
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: _busy
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                    )
                  : Text(_action),
            ),
            const SizedBox(height: Space.sm),
            if (_mode == _Mode.signIn)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Link(l.createAnAccount, () => _switchTo(_Mode.signUp)),
                  _Link(l.forgotPassword, () => _switchTo(_Mode.reset)),
                ],
              )
            else
              Center(child: _Link(l.backToSigningIn, () => _switchTo(_Mode.signIn))),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
        foregroundColor: c.accent,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

/// Something that went right, or at least not wrong, said where it happened.
class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mark_email_unread_outlined, size: IconSize.md, color: c.accent),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              message,
              style: Type.small.copyWith(fontSize: 12.5, color: c.accentStrong),
            ),
          ),
        ],
      ),
    );
  }
}
