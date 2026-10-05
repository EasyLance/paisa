import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_service.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets.dart';
import 'request_access_sheet.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _message;
  bool _messageIsError = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authServiceProvider).signIn(_email.text, _password.text);
    } on AuthFailure catch (failure) {
      _say(failure.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message, {required bool error}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (!_looksLikeEmail(email)) {
      _say('Enter your email address first, then choose reset.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      // Firebase answers the same whether or not the address has an account, so
      // this must not claim that it does.
      _say('If $email has an account, a reset link is on its way.', error: false);
    } on AuthFailure catch (failure) {
      _say(failure.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _looksLikeEmail(String value) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [PaisaMark(), SizedBox(width: 10), Text('Paisa')]),
                  const SizedBox(height: 28),
                  Text('PRIVATE FINANCIAL WORKSPACE', style: text.labelSmall),
                  const SizedBox(height: 6),
                  Text('Your finances, clearly shared.', style: text.headlineMedium),
                  const SizedBox(height: 8),
                  Text('Sign in to your private book, household workspace, or CA review view.', style: text.bodyMedium?.copyWith(color: context.paisa.muted)),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    decoration: InputDecoration(labelText: 'Email', helperText: AppConfig.devAuth ? 'Development: type a dev user id such as user_owner' : null),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      final v = (value ?? '').trim();
                      if (AppConfig.devAuth) return v.isEmpty ? 'Enter a dev user id' : null;
                      return _looksLikeEmail(v) ? null : 'Enter a valid email address';
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _hidePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _signIn(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _hidePassword ? 'Show password' : 'Hide password',
                        icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hidePassword = !_hidePassword),
                      ),
                    ),
                    validator: (value) => AppConfig.devAuth || (value ?? '').isNotEmpty ? null : 'Enter your password',
                  ),
                  if (_message != null) ...[const SizedBox(height: 12), Notice(_message!, isError: _messageIsError)],
                  const SizedBox(height: 18),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _signIn, child: Text(_busy ? 'Please wait…' : 'Sign in'))),
                  const SizedBox(height: 4),
                  // A Wrap, not a Row: on a 360dp phone both labels do not fit on one line.
                  Wrap(alignment: WrapAlignment.spaceBetween, children: [
                    TextButton(onPressed: _busy ? null : _reset, child: const Text('Forgot your password?')),
                    TextButton(onPressed: _busy ? null : () => showRequestAccess(context, email: _email.text.trim()), child: const Text('Request access')),
                  ]),
                  const SizedBox(height: 12),
                  Text('Access is available only to users invited by a workspace owner.', style: text.bodySmall),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
