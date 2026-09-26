import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_service.dart';
import '../../core/supabase/supabase_service.dart';
import 'auth_widgets.dart';

class AccessScreen extends ConsumerStatefulWidget {
  const AccessScreen({super.key});
  @override
  ConsumerState<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends ConsumerState<AccessScreen>
    with WidgetsBindingObserver {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error, _notice;
  DateTime? get _lastCheck => ref.read(authProvider.notifier).lastAccessCheck;
  Timer? _cooldown;
  bool get _canCheck =>
      !_busy &&
      !ref.read(authProvider).isLoading &&
      (_lastCheck == null ||
          DateTime.now().difference(_lastCheck!).inSeconds >= 10);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldown?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _canCheck) _check();
  }

  Future<void> _check() async {
    if (!_canCheck) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      ref.read(authProvider.notifier).lastAccessCheck = DateTime.now();
    });
    await ref.read(authProvider.notifier).refreshProfile();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = 'Status checked. Access still requires admin approval.';
    });
    _cooldown = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _activate() async {
    final auth = ref.read(authProvider);
    if (_busy ||
        _code.text.trim().isEmpty ||
        auth.user?['access_status'] != 'pending' ||
        auth.user?['is_suspended'] != false) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await SupabaseService.instance.client.rpc(
          'redeem_app_access_invite',
          params: {'p_code': _code.text.trim()});
      if (result is Map && result['ok'] == true) {
        _code.clear();
        await ref.read(authProvider.notifier).refreshProfile();
      } else if (mounted)
        setState(() => _error = result is Map &&
                result['error_code'] == 'rate_limited'
            ? 'Too many attempts. Please wait 15 minutes before trying again.'
            : "This code is invalid, expired, already used, or isn't assigned to this email.");
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contact() async {
    final auth = ref.read(authProvider);
    final details = 'Please approve my KryinTalks account: ' +
        auth.email +
        ', @' +
        (auth.user?['username']?.toString() ?? '') +
        '. My email is confirmed.';
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Request admin access'),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      SelectableText(details),
                      const SizedBox(height: 16),
                      Text(SupabaseConfig.adminContactEmail.isEmpty
                          ? 'Ask the person who invited you to contact an administrator.'
                          : 'Contact: ' + SupabaseConfig.adminContactEmail),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: details));
                        if (ctx.mounted)
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Request details copied.')));
                      },
                      child: const Text('Copy request details')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close')),
                ]));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider), user = auth.user;
    final setup = user == null,
        restricted = user?['is_suspended'] == true ||
            user?['is_active'] != true ||
            ['rejected', 'revoked'].contains(user?['access_status']);
    return AuthLayout(
        title: setup
            ? 'Account setup needs attention'
            : restricted
                ? 'Your access is restricted.'
                : 'Your account is ready. Access is pending.',
        subtitle: setup
            ? 'Retry loading your account or contact an admin.'
            : user['access_status'] == 'rejected'
                ? 'Your access request was declined. Contact an admin if you think this is a mistake.'
                : restricted
                    ? 'Contact an admin for help.'
                    : 'Please contact an admin to allow access to KryinTalks, or enter an invite code.',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(auth.email),
          const SizedBox(height: 16),
          if (!setup && !restricted) ...[
            const Text(
                'Account created ✓\nEmail confirmed ✓\nApp access pending'),
            const SizedBox(height: 24),
            TextField(
                key: const ValueKey('access-code'),
                controller: _code,
                maxLength: 128,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'App access code'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _activate()),
            FilledButton(
                onPressed:
                    !_busy && _code.text.trim().isNotEmpty ? _activate : null,
                child: Text(_busy ? 'Checking code…' : 'Activate access')),
          ],
          if (user?['access_status'] == 'rejected' &&
              user?['access_reason'] != null)
            Text(user!['access_reason'].toString()),
          if (_error ?? auth.error case final String error) ...[
            const SizedBox(height: 16),
            Text(error,
                style: TextStyle(color: Theme.of(context).colorScheme.error))
          ],
          if (_notice != null) Text(_notice!),
          const SizedBox(height: 16),
          OutlinedButton(
              onPressed: _busy ? null : _contact,
              child: const Text('Contact admin')),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: _canCheck ? _check : null,
              child: Text(_busy ? 'Checking status…' : 'Check status')),
          TextButton(
              onPressed:
                  _busy ? null : () => ref.read(authProvider.notifier).logout(),
              child: const Text('Sign out')),
        ]));
  }
}

class AccountConsentScreen extends ConsumerStatefulWidget {
  const AccountConsentScreen({super.key});
  @override
  ConsumerState<AccountConsentScreen> createState() =>
      _AccountConsentScreenState();
}

class _AccountConsentScreenState extends ConsumerState<AccountConsentScreen> {
  bool _agreed = false, _busy = false;
  String? _error;
  Future<void> _continue() async {
    if (!_agreed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).acceptPolicies();
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
      title: 'Review the account terms',
      subtitle:
          'Accept the current Terms and acknowledge the Privacy Policy to continue.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PolicyAgreement(
            value: _agreed,
            onChanged: _busy ? null : (v) => setState(() => _agreed = v)),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: _agreed && !_busy ? _continue : null,
            child: Text(_busy
                ? 'Saving…'
                : _error == null
                    ? 'Continue'
                    : 'Retry')),
        TextButton(
            onPressed:
                _busy ? null : () => ref.read(authProvider.notifier).logout(),
            child: const Text('Sign out')),
      ]));
}
