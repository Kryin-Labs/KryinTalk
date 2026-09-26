import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_service.dart';
import 'auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _agreed = false, _busy = false, _hidden = true;
  bool get _canSubmit =>
      validAccountEmail(_email.text) &&
      _password.text.isNotEmpty &&
      _agreed &&
      !_busy;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(authProvider.notifier)
        .login(_email.text, _password.text, agreed: _agreed);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return AuthLayout(
        title: 'Welcome back',
        subtitle: 'Sign in with your email to continue to KryinTalk.',
        child: AutofillGroup(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              TextFormField(
                  key: const ValueKey('login-email'),
                  controller: _email,
                  enabled: !_busy,
                  autovalidateMode: AutovalidateMode.onUnfocus,
                  validator: (v) => validAccountEmail(v ?? '')
                      ? null
                      : 'Enter a valid email address.',
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email address'),
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.next),
              const SizedBox(height: 20),
              TextFormField(
                  key: const ValueKey('login-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _hidden,
                  autovalidateMode: AutovalidateMode.onUnfocus,
                  validator: (v) =>
                      v?.isNotEmpty == true ? null : 'Enter your password.',
                  autofillHints: const [AutofillHints.password],
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                          tooltip: _hidden ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _hidden = !_hidden),
                          icon: Icon(_hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined)))),
              const SizedBox(height: 16),
              PolicyAgreement(
                  value: _agreed,
                  onChanged: _busy ? null : (v) => setState(() => _agreed = v)),
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Text(auth.error!,
                    key: const ValueKey('auth-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
                if (auth.error!.toLowerCase().contains('confirm'))
                  TextButton(
                      onPressed: () =>
                          context.go('/check-email', extra: _email.text.trim()),
                      child: const Text('Resend confirmation'))
              ],
              const SizedBox(height: 16),
              FilledButton(
                  key: const ValueKey('login-submit'),
                  onPressed: _canSubmit ? _submit : null,
                  child: Text(_busy ? 'Signing in…' : 'Sign in')),
              const SizedBox(height: 10),
              if (!_agreed)
                const Text(
                    'Complete the fields and accept the agreement to sign in.',
                    textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                  onPressed: _busy ? null : () => context.go('/register'),
                  child: const Text('Create account')),
            ])));
  }
}
