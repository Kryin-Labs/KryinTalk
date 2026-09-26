import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_service.dart';
import '../../core/supabase/supabase_service.dart';

bool canManageAppAccount(AuthState actor, Map<String, dynamic> target) =>
    actor.isAdmin &&
    actor.userId != target['id'] &&
    (actor.isSuperAdmin ||
        !['admin', 'super_admin', 'manager'].contains(target['role']));
List<String> accountReviewActions(Map<String, dynamic> target) {
  if (target['is_suspended'] == true) return ['restore', 'revoke'];
  switch (target['access_status']) {
    case 'pending':
      return ['approve', 'decline', 'revoke'];
    case 'approved':
      return ['suspend', 'revoke'];
    case 'rejected':
      return ['reopen', 'revoke'];
    case 'revoked':
      return ['reopen'];
    default:
      return [];
  }
}

String accessActionLabel(String action) =>
    const {
      'approve': 'Approve access',
      'decline': 'Decline request',
      'reopen': 'Reopen request',
      'suspend': 'Suspend access',
      'restore': 'Restore access',
      'revoke': 'Revoke access',
    }[action] ??
    action;

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});
  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _tab = 0, _offset = 0, _total = 0, _epoch = 0;
  String _status = 'pending';
  bool _loading = true, _mutating = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    ++_epoch;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) async {
    try {
      return await SupabaseService.instance.client
          .rpc(name, params: params ?? {});
    } on PostgrestException catch (e) {
      if (e.code == '42501')
        unawaited(ref.read(authProvider.notifier).refreshProfile());
      rethrow;
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });
    try {
      final result = await _rpc(
          _tab == 2 ? 'list_app_access_invites' : 'list_app_accounts',
          _tab == 2
              ? {'p_limit': 25, 'p_offset': _offset}
              : {
                  'p_status': _status,
                  'p_search': _search.text.trim(),
                  'p_limit': 25,
                  'p_offset': _offset
                });
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(result['items'] as List);
        _total = (result['total'] as num).toInt();
      });
    } catch (e) {
      if (mounted && epoch == _epoch)
        setState(() => _error = AuthService.errorMessage(e));
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  void _switchTab(int tab) {
    _debounce?.cancel();
    setState(() {
      _tab = tab;
      _offset = 0;
      _status = tab == 0 ? 'pending' : 'approved';
    });
    _load();
  }

  Future<void> _review(Map<String, dynamic> user) async {
    setState(() => _mutating = true);
    try {
      final review =
          await _rpc('get_app_account_review', {'p_user_id': user['id']});
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text('Review ' + user['display_name'].toString()),
                  content: SizedBox(
                      width: 540,
                      child: SingleChildScrollView(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(user['email'].toString()),
                            Text('@' + user['username'].toString()),
                            Text(user['email_confirmed'] == true
                                ? 'Email confirmed'
                                : 'Email not confirmed'),
                            Text('Requested: ' +
                                (user['created_at']?.toString() ?? '—')),
                            Text('Status: ' + user['access_status'].toString()),
                            Text('Roles: ' +
                                (user['roles'] as List? ?? []).join(', ')),
                            const SizedBox(height: 16),
                            const Text('Access history'),
                            const SizedBox(height: 8),
                            for (final event
                                in review['history'] as List? ?? [])
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(event['action'].toString() +
                                      ' · ' +
                                      event['created_at'].toString() +
                                      '\n' +
                                      jsonEncode(event['details']))),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'))
                  ]));
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _action(Map<String, dynamic> user, String action) async {
    if (_mutating || !canManageAppAccount(ref.read(authProvider), user)) return;
    final reason = TextEditingController();
    final needsReason =
        ['decline', 'reopen', 'suspend', 'revoke'].contains(action);
    final label = accessActionLabel(action);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: Text(label),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(action == 'approve'
                              ? 'Allow ' +
                                  user['display_name'].toString() +
                                  ' to use KryinTalk as a member?'
                              : label +
                                  ' for ' +
                                  user['display_name'].toString() +
                                  ' (' +
                                  (user['role']?.toString() ??
                                      'pending account') +
                                  ')?'),
                          if (needsReason) ...[
                            const SizedBox(height: 16),
                            TextField(
                                controller: reason,
                                maxLength: 500,
                                decoration: InputDecoration(
                                    labelText: action == 'decline'
                                        ? 'Public reason (shown to this user)'
                                        : 'Reason'),
                                onChanged: (_) => update(() {}))
                          ],
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed:
                              !needsReason || reason.text.trim().isNotEmpty
                                  ? () => Navigator.pop(ctx, true)
                                  : null,
                          child: Text(label)),
                    ])));
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      await _rpc('review_app_access', {
        'p_user_id': user['id'],
        'p_action': action,
        'p_reason': text.isEmpty ? null : text
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _changeRole(Map<String, dynamic> user) async {
    if (_mutating ||
        !ref.read(authProvider).isSuperAdmin ||
        user['id'] == ref.read(authProvider).userId) return;
    final role = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
                title:
                    Text('Change role for ' + user['display_name'].toString()),
                children: [
                  for (final role in ['member', 'admin'])
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, role),
                        child: Text(role == 'admin' ? 'Admin' : 'Member'))
                ]));
    if (role == null || !mounted) return;
    setState(() => _mutating = true);
    try {
      await _rpc(
          'set_app_account_role', {'p_user_id': user['id'], 'p_role': role});
      await _load();
    } catch (e) {
      if (mounted)
        setState(() => _error =
            'Role change failed. The server may protect this account. Refresh and retry.');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _createInvite() async {
    final email = TextEditingController();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: const Text('Create app access code'),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text(
                              'Member access · single use · expires in 7 days'),
                          const SizedBox(height: 16),
                          TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                  labelText: 'Recipient email'),
                              onChanged: (_) => update(() {})),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: validAccountEmail(email.text)
                              ? () => Navigator.pop(ctx, true)
                              : null,
                          child: const Text('Create code'))
                    ])));
    final recipient = email.text.trim();
    email.dispose();
    if (accepted != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      final invite = Map<String, dynamic>.from(
          await _rpc('create_app_access_invite', {'p_email': recipient})
              as Map);
      if (!mounted) {
        invite.remove('code');
        return;
      }
      String? code = invite.remove('code') as String?;
      await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Copy this code now'),
                  content: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Assigned to ' + recipient),
                        const SizedBox(height: 16),
                        SelectableText(code ?? ''),
                        const SizedBox(height: 16),
                        const Text(
                            'This code is shown once. Share it only with the recipient.'),
                        Text('Expires: ' + invite['expires_at'].toString()),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: code ?? ''));
                        },
                        child: const Text('Copy code')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'))
                  ]));
      code = null;
      await _load();
    } catch (e) {
      if (mounted)
        setState(() => _error =
            'Could not create invite. Refresh before retrying; a code may have been created.');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _revokeInvite(Map<String, dynamic> invite) async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Revoke invite?'),
                content: Text('Invalidate the unused code for ' +
                    invite['recipient_email'].toString() +
                    '?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Revoke invite'))
                ]));
    if (accepted != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      await _rpc('revoke_app_access_invite', {'p_invite_id': invite['id']});
      await _load();
    } catch (e) {
      if (mounted)
        setState(() => _error = 'Could not revoke invite. Refresh and retry.');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authProvider);
    if (!actor.isAdmin)
      return const Center(child: Text('Administrator access required.'));
    return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('User access',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Review personal accounts and grant access to KryinTalk.'),
          const SizedBox(height: 20),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (index, title)
                in ['Access requests', 'Members', 'Invites'].indexed)
              ChoiceChip(
                  label: Text(title),
                  selected: _tab == index,
                  onSelected: _mutating ? null : (_) => _switchTab(index)),
          ]),
          const SizedBox(height: 20),
          Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_tab != 2)
                  SizedBox(
                      width: 260,
                      child: TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                              labelText: 'Search name, username or email',
                              prefixIcon: Icon(Icons.search)),
                          onChanged: (_) {
                            _debounce?.cancel();
                            _debounce =
                                Timer(const Duration(milliseconds: 350), () {
                              _offset = 0;
                              _load();
                            });
                          })),
                if (_tab != 2)
                  DropdownButton<String>(
                      value: _status,
                      onChanged: _mutating
                          ? null
                          : (v) {
                              setState(() {
                                _status = v!;
                                _offset = 0;
                              });
                              _load();
                            },
                      items: [
                        for (final s in _tab == 0
                            ? ['pending', 'rejected', 'revoked', 'all']
                            : ['approved', 'suspended'])
                          DropdownMenuItem(
                              value: s,
                              child: Text(s[0].toUpperCase() + s.substring(1)))
                      ]),
                OutlinedButton.icon(
                    onPressed: _loading || _mutating ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh')),
                if (_tab == 2)
                  FilledButton.icon(
                      onPressed: _mutating ? null : _createInvite,
                      icon: const Icon(Icons.add),
                      label: const Text('Create invite')),
              ]),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_items.isEmpty)
            Text(_error == null
                ? 'No ' +
                    (_tab == 0
                        ? 'access requests'
                        : _tab == 1
                            ? 'members'
                            : 'invites') +
                    ' found.'
                : 'Could not load this list. Use Refresh to retry.')
          else
            for (final item in _items)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                (_tab == 2
                                        ? item['recipient_email']
                                        : item['display_name'])
                                    .toString(),
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 6),
                            if (_tab != 2) ...[
                              Text('@' +
                                  item['username'].toString() +
                                  ' · ' +
                                  item['email'].toString()),
                              Text((item['email_confirmed'] == true
                                      ? 'Email confirmed'
                                      : 'Email not confirmed') +
                                  ' · ' +
                                  (item['is_suspended'] == true
                                      ? 'Suspended'
                                      : item['access_status'].toString()) +
                                  ' · ' +
                                  (item['role']?.toString() ??
                                      'No member access')),
                              Text('Requested: ' +
                                  (item['created_at']?.toString() ?? '—')),
                              const SizedBox(height: 12),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                OutlinedButton(
                                    onPressed:
                                        _mutating ? null : () => _review(item),
                                    child: const Text('Review')),
                                if (canManageAppAccount(actor, item)) ...[
                                  for (final action
                                      in accountReviewActions(item))
                                    OutlinedButton(
                                        onPressed: _mutating ||
                                                (action == 'approve' &&
                                                    item['email_confirmed'] !=
                                                        true)
                                            ? null
                                            : () => _action(item, action),
                                        child: Text(accessActionLabel(action))),
                                  if (actor.isSuperAdmin &&
                                      item['access_status'] == 'approved' &&
                                      item['is_suspended'] != true)
                                    OutlinedButton(
                                        onPressed: _mutating
                                            ? null
                                            : () => _changeRole(item),
                                        child: const Text('Change role')),
                                ],
                              ]),
                            ] else ...[
                              Text('Created: ' + item['created_at'].toString()),
                              Text('Expires: ' + item['expires_at'].toString()),
                              Text(item['redeemed_at'] != null
                                  ? 'Used'
                                  : item['revoked_at'] != null
                                      ? 'Revoked'
                                      : DateTime.tryParse(item['expires_at']
                                                      .toString())
                                                  ?.isBefore(DateTime.now()) ==
                                              true
                                          ? 'Expired'
                                          : 'Unused'),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                  onPressed: _mutating ||
                                          item['redeemed_at'] != null ||
                                          item['revoked_at'] != null ||
                                          DateTime.tryParse(item['expires_at']
                                                      .toString())
                                                  ?.isBefore(DateTime.now()) !=
                                              false
                                      ? null
                                      : () => _revokeInvite(item),
                                  child: const Text('Revoke invite')),
                            ],
                          ]))),
          const SizedBox(height: 16),
          Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_total.toString() + ' results'),
                TextButton(
                    onPressed: _loading || _offset == 0
                        ? null
                        : () {
                            _offset -= 25;
                            _load();
                          },
                    child: const Text('Previous')),
                TextButton(
                    onPressed: _loading || _offset + 25 >= _total
                        ? null
                        : () {
                            _offset += 25;
                            _load();
                          },
                    child: const Text('Next')),
              ]),
        ]));
  }
}
