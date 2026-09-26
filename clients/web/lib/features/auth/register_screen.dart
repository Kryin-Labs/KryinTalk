import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_service.dart';
import 'auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController(),
      _username = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _agreed = false, _busy = false, _hidden = true, _confirmHidden = true;
  String? _error;
  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _name.text.trim().length <= 100 &&
      RegExp(r'^[a-z0-9_]{3,100}$')
          .hasMatch(normalizeUsername(_username.text)) &&
      validAccountEmail(_email.text) &&
      _password.text.length >= 8 &&
      _confirm.text == _password.text;
  bool get _canSubmit => _valid && _agreed && !_busy;
  @override
  void dispose() {
    for (final c in [_name, _username, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(authProvider.notifier).register(
        email: _email.text,
        username: _username.text,
        displayName: _name.text,
        password: _password.text,
        agreed: _agreed);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
    });
    if (result.success) {
      _password.clear();
      _confirm.clear();
      context.go('/check-email', extra: _email.text.trim());
    }
  }

  Widget _field(String id, TextEditingController c, String label,
          {bool password = false,
          bool confirm = false,
          String? helper,
          int? maxLength}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
              key: ValueKey('register-' + id),
              autovalidateMode: AutovalidateMode.onUnfocus,
              validator: (value) {
                final text = value ?? '';
                if (id == 'name' &&
                    (text.trim().isEmpty || text.trim().length > 100))
                  return 'Use a display name of 1–100 characters.';
                if (id == 'username' &&
                    !RegExp(r'^[a-z0-9_]{3,100}$')
                        .hasMatch(normalizeUsername(text)))
                  return 'Use 3–100 letters, digits or underscores.';
                if (id == 'email' && !validAccountEmail(text))
                  return 'Enter a valid email address.';
                if (id == 'password' && text.length < 8)
                  return 'Use at least 8 characters.';
                if (id == 'confirm' && text != _password.text)
                  return 'Passwords must match.';
                return null;
              },
              controller: c,
              enabled: !_busy,
              maxLength: maxLength,
              obscureText: password && (confirm ? _confirmHidden : _hidden),
              autofillHints: password
                  ? const [AutofillHints.newPassword]
                  : id == 'email'
                      ? const [AutofillHints.email]
                      : id == 'name'
                          ? const [AutofillHints.name]
                          : null,
              keyboardType: id == 'email'
                  ? TextInputType.emailAddress
                  : TextInputType.text,
              textInputAction:
                  confirm ? TextInputAction.done : TextInputAction.next,
              onChanged: (_) => setState(() {}),
              onFieldSubmitted: confirm ? (_) => _submit() : null,
              decoration: InputDecoration(
                  labelText: label,
                  helperText: helper,
                  counterText: '',
                  suffixIcon: password
                      ? IconButton(
                          tooltip: (confirm ? _confirmHidden : _hidden)
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(() {
                                if (confirm) {
                                  _confirmHidden = !_confirmHidden;
                                } else {
                                  _hidden = !_hidden;
                                }
                              }),
                          icon: Icon((confirm ? _confirmHidden : _hidden)
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined))
                      : null)));
  @override
  Widget build(BuildContext context) => AuthLayout(
      title: 'Create your account',
      switchLabel: 'Sign in',
      onSwitch: _busy ? null : () => context.go('/login'),
      subtitle:
          'Get started with KryinTalk. Confirm your email, then request access.',
      child: AutofillGroup(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _field('name', _name, 'Display name', maxLength: 100),
        _field('username', _username, 'Username',
            maxLength: 101,
            helper: '@' +
                normalizeUsername(_username.text) +
                ' · 3–100 letters, digits or underscores'),
        _field('email', _email, 'Email address', maxLength: 254),
        _field('password', _password, 'Password', password: true),
        Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: AuthLayout.blue.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              _requirement('At least 8 characters', _password.text.length >= 8),
              const SizedBox(height: 8),
              _requirement('Passwords match',
                  _confirm.text.isNotEmpty && _password.text == _confirm.text)
            ])),
        _field('confirm', _confirm, 'Confirm password',
            password: true, confirm: true),
        PolicyAgreement(
            value: _agreed,
            onChanged: _busy ? null : (v) => setState(() => _agreed = v)),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              key: const ValueKey('auth-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error))
        ],
        const SizedBox(height: 16),
        FilledButton(
            key: const ValueKey('register-submit'),
            onPressed: _canSubmit ? _submit : null,
            child: Text(_busy ? 'Creating account…' : 'Create account')),
        const SizedBox(height: 12),
        const Text(
            'Confirm your email, then request access or enter a code from an admin.',
            textAlign: TextAlign.center),
      ])));
  Widget _requirement(String label, bool met) => Row(children: [
        Icon(met ? Icons.check_circle_outline : Icons.circle_outlined,
            size: 18, color: met ? AuthLayout.blue : null),
        const SizedBox(width: 8),
        Expanded(child: Text(label))
      ]);
}
