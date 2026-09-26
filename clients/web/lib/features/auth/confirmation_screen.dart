import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/supabase/supabase_service.dart';
import 'auth_widgets.dart';

class CheckEmailScreen extends StatefulWidget {
  const CheckEmailScreen({super.key, this.email});
  final String? email;
  @override
  State<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends State<CheckEmailScreen> {
  late final _email = TextEditingController(text: widget.email ?? '');
  Timer? _timer;
  int _seconds = 0;
  bool _busy = false;
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    if (widget.email?.isNotEmpty == true) _cooldown();
  }

  void _cooldown() {
    _seconds = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _seconds--);
      if (_seconds == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    if (_busy || _seconds > 0 || !validAccountEmail(_email.text)) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await SupabaseService.instance.resendConfirmation(_email.text);
      if (mounted)
        setState(() {
          _notice =
              'If this address can receive a confirmation, a new link has been sent.';
          _cooldown();
        });
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
      title: 'Check your email',
      subtitle:
          "If this address can receive a new account confirmation, we've sent a link. Confirm your email, then sign in.",
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email address'),
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
        const Text('Check spam or junk folders.'),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error))
        ],
        if (_notice != null) ...[const SizedBox(height: 16), Text(_notice!)],
        const SizedBox(height: 24),
        FilledButton(
            onPressed: !_busy && _seconds == 0 && validAccountEmail(_email.text)
                ? _resend
                : null,
            child: Text(_busy
                ? 'Sending…'
                : _seconds > 0
                    ? 'Resend in ' + _seconds.toString() + 's'
                    : 'Resend confirmation')),
        TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to sign in')),
        TextButton(
            onPressed: _busy ? null : () => context.go('/register'),
            child: const Text('Use another email')),
        const Text(
            'Changing the signup input does not change an account already created.',
            textAlign: TextAlign.center),
      ]));
}

class AuthCallbackScreen extends ConsumerWidget {
  const AuthCallbackScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ok = SupabaseService.callbackSucceeded;
    return AuthLayout(
        title: ok
            ? 'Email confirmed'
            : 'This confirmation link is invalid or has expired.',
        subtitle: ok
            ? 'Your email is confirmed. Sign in to request app access.'
            : 'Request another email to continue.',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!ok)
            FilledButton(
                onPressed: () => context.go('/check-email'),
                child: const Text('Request another email')),
          TextButton(
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
              child: Text(ok ? 'Sign in' : 'Back to sign in')),
        ]));
  }
}
