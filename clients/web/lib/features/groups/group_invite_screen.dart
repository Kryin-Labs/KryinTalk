import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/supabase/supabase_service.dart';

class GroupInviteScreen extends ConsumerStatefulWidget {
  const GroupInviteScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<GroupInviteScreen> createState() => _GroupInviteScreenState();
}

class _GroupInviteScreenState extends ConsumerState<GroupInviteScreen> {
  Map<String, dynamic>? _invite;
  String? _error;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final invite =
          await SupabaseService.instance.getGroupInvite(widget.token);
      if (mounted) {
        setState(() => _invite = invite);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'This group invite is invalid or unavailable.');
      }
    }
  }

  Future<void> _join() async {
    if (!ref.read(authProvider).hasAppAccess) { context.go('/access'); return; }
    setState(() => _joining = true);
    try {
      final result =
          await SupabaseService.instance.acceptGroupInvite(widget.token);
      if (!mounted) return;
      context.go('/messages/${result['conversation_id']}');
    } catch (error) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    final expired = invite?['is_expired'] == true;
    final authenticated = ref.watch(authProvider).hasAppAccess;
    final groupName = invite?['group_name']?.toString() ?? 'Group';
    final createdBy =
        invite?['created_by_name']?.toString() ?? 'a group member';
    final creatorUsername = invite?['created_by_username']?.toString();
    final memberCount = invite?['member_count']?.toString() ?? '0';
    final remaining = ((invite?['max_uses'] as num?)?.toInt() ?? 0) -
        ((invite?['uses_count'] as num?)?.toInt() ?? 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(24),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: _error != null && invite == null
                  ? _ErrorState(message: _error!, onRetry: _load)
                  : invite == null
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: const Color(0xFFCCFBF1),
                              child: Text(
                                (invite['group_icon']?.toString().isNotEmpty ??
                                        false)
                                    ? invite['group_icon'].toString()
                                    : groupName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('Join $groupName',
                                textAlign: TextAlign.center,
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text(
                                '${creatorUsername?.isNotEmpty == true ? '$createdBy (@$creatorUsername)' : createdBy} invited you to this group.',
                                textAlign: TextAlign.center,
                                style:
                                    const TextStyle(color: Color(0xFF475569))),
                            if ((invite['group_description']
                                        ?.toString()
                                        .trim() ??
                                    '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(invite['group_description'].toString(),
                                  textAlign: TextAlign.center),
                            ],
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDFA),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$memberCount members · ${remaining < 0 ? 0 : remaining} invite spots remaining',
                                textAlign: TextAlign.center,
                                style:
                                    const TextStyle(color: Color(0xFF0F766E)),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Color(0xFFB91C1C))),
                            ],
                            const SizedBox(height: 24),
                            if (expired)
                              const Text(
                                  'This invite has expired or reached its join limit.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFFB91C1C)))
                            else if (!authenticated)
                              Column(
                                children: [
                                  FilledButton(
                                    onPressed: () => context.go('/login'),
                                    child: const Text('Sign in to join'),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'Sign in, then open this invite link again.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 12)),
                                ],
                              )
                            else
                              FilledButton(
                                onPressed: _joining ? null : _join,
                                child:
                                    Text(_joining ? 'Joining…' : 'Join Group'),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off, size: 40, color: Color(0xFFB91C1C)),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      );
}
