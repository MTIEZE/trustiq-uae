import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Signing in to a real project.
///
/// Email and password, because that is what the schema's auth supports today.
/// UAE Pass is a separate integration and does not replace this: it verifies
/// who someone is, it is not how they hold a session.
///
/// Never shown in demo mode. A sign-in form for data that is not stored
/// anywhere would be theatre.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && _email.text.trim().contains('@') && _password.text.isNotEmpty;

  Future<void> _submit() async {
    setState(() => _busy = true);
    final ok = await widget.state.signIn(
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.state.error ?? 'Could not sign in.'),
          backgroundColor: TrustIqColors.critical,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('TrustIQ', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Signing in to ${widget.state.backendLabel}',
                    style: const TextStyle(color: TrustIqColors.inkFaint),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _canSubmit ? _submit() : null,
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 20),
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
