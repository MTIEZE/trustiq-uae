import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
    if (_mode == _Mode.reset) return null;
    if (_password.text.isEmpty) return null;
    if (_mode == _Mode.signUp && _password.text.length < 8) {
      return 'At least 8 characters.';
    }
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
            _notice = 'Account created. Open the link we sent to '
                '${_email.text.trim()}, then sign in.';
            _mode = _Mode.signIn;
          });
        }
      case _Mode.reset:
        final sent = await widget.state.sendPasswordReset(_email.text);
        if (sent && mounted) {
          // Says the same thing whether or not the address has an account. The
          // other answer turns this form into a way to find out who is a user.
          setState(() {
            _notice = 'If an account exists for ${_email.text.trim()}, a reset '
                'link is on its way.';
            _mode = _Mode.signIn;
          });
        }
    }

    if (!mounted) return;
    setState(() => _busy = false);

    final error = widget.state.error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: TrustIqColors.critical),
      );
    }
  }

  String get _title => switch (_mode) {
        _Mode.signIn => 'Sign in',
        _Mode.signUp => 'Create your account',
        _Mode.reset => 'Reset your password',
      };

  String get _action => switch (_mode) {
        _Mode.signIn => 'Sign in',
        _Mode.signUp => 'Create account',
        _Mode.reset => 'Send the link',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'TrustIQ',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.6),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.state.backendLabel,
                    style: const TextStyle(fontSize: 12.5, color: TrustIqColors.inkFaint),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    _title,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),

                  if (_notice != null) ...[
                    _Notice(_notice!),
                    const SizedBox(height: 16),
                  ],

                  if (_mode == _Mode.signUp) ...[
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        helperText: 'What the other party sees on a contract.',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                  ],

                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    onChanged: (_) => setState(() {}),
                  ),

                  if (_mode != _Mode.reset) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: [
                        _mode == _Mode.signUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        errorText: _passwordComplaint,
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Hide password' : 'Show password',
                          icon: Icon(
                            _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 19,
                          ),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _canSubmit ? _submit() : null,
                    ),
                  ],

                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_action),
                  ),
                  const SizedBox(height: 14),

                  if (_mode == _Mode.signIn) ...[
                    _Link('Create an account', () => _switchTo(_Mode.signUp)),
                    _Link('I forgot my password', () => _switchTo(_Mode.reset)),
                  ] else
                    _Link('Back to signing in', () => _switchTo(_Mode.signIn)),

                  const SizedBox(height: 24),
                  const RuleNote(
                    'Your contracts are visible to you and to the other party, '
                    'and to nobody else. That is enforced by the database, not '
                    'by this app.',
                  ),
                ],
              ),
            ),
          ),
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
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: TrustIqColors.accent,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TrustIqColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: TrustIqColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mark_email_unread_outlined, size: 18, color: TrustIqColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
