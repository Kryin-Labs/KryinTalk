/// ConnectHub — Friends & Connections Screen.
///
/// Features:
/// - Friends Tab (Message 💬, Remove ❌, Block 🚫)
/// - Pending Requests Tab (Accept ✔️, Reject ❌, Cancel ✖️)
/// - Blocked Users Tab (Unblock 🔓)
/// - Add Friend Dialog with user selection
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/presence/presence_provider.dart';
import '../../core/supabase/supabase_service.dart';
import '../../shared/widgets/global_header.dart';
import '../../shared/widgets/pulsing_status_dot.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allUsers = [];
  Set<String> _friendIds = {};
  Set<String> _pendingIncomingIds = {};
  Set<String> _pendingOutgoingIds = {};
  Set<String> _blockedIds = {};
  final Map<String, String> _relationshipIds = {};
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final currentUserId = ref.read(authProvider).userId;
    try {
      if (currentUserId == null || !SupabaseService.instance.hasSession) {
        throw StateError('Friend service is unavailable for this session');
      }
      final api = ref.read(apiClientProvider);
      final res = await api.dio.get(ApiEndpoints.directory);
      final items = (res.data is List)
          ? res.data as List
          : ((res.data is Map && res.data.containsKey('items'))
              ? res.data['items'] as List
              : []);

      _allUsers = List<Map<String, dynamic>>.from(items);

      _friendIds.clear();
      _pendingIncomingIds.clear();
      _pendingOutgoingIds.clear();
      _blockedIds.clear();
      _relationshipIds.clear();

      {
        final data = await SupabaseService.instance.client
            .from('friendships')
            .select()
            .or('requester_id.eq.$currentUserId,addressee_id.eq.$currentUserId');
        for (final raw in data) {
          final relation = Map<String, dynamic>.from(raw);
          final requesterId = relation['requester_id']?.toString() ?? '';
          final addresseeId = relation['addressee_id']?.toString() ?? '';
          final otherId =
              requesterId == currentUserId ? addresseeId : requesterId;
          if (otherId.isEmpty) continue;
          _relationshipIds[otherId] = relation['id']?.toString() ?? '';
          switch (relation['status']?.toString()) {
            case 'accepted':
              _friendIds.add(otherId);
              break;
            case 'blocked':
              _blockedIds.add(otherId);
              break;
            default:
              if (addresseeId == currentUserId) {
                _pendingIncomingIds.add(otherId);
              } else {
                _pendingOutgoingIds.add(otherId);
              }
              break;
          }
        }
      }
    } catch (error) {
      _loadError = 'Could not load friends and requests. Please try again.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _showError(String message, {VoidCallback? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        action: retry == null
            ? null
            : SnackBarAction(label: 'Retry', onPressed: retry),
      ),
    );
  }

  Future<bool> _sendFriendRequest(String userId) async {
    final currentUserId = ref.read(authProvider).userId;
    if (currentUserId == null || !SupabaseService.instance.hasSession) {
      _showError('Friend service is unavailable.');
      return false;
    }
    try {
      final row = await SupabaseService.instance.requestFriendship(userId);
      if (mounted) {
        setState(() {
          _pendingOutgoingIds.add(userId);
          _relationshipIds[userId] = row['id'].toString();
        });
      }
      return true;
    } catch (error) {
      _showError('Could not send friend request: $error');
      return false;
    }
  }

  Future<void> _setRelationshipStatus(String userId, String status) async {
    final relationId = _relationshipIds[userId];
    if (relationId == null ||
        relationId.isEmpty ||
        !SupabaseService.instance.hasSession) {
      _showError('Friend relationship is unavailable.');
      return;
    }
    try {
      if (status != 'accepted') {
        throw ArgumentError.value(status, 'status');
      }
      await SupabaseService.instance
          .respondToFriendship(relationId, accept: true);
      if (mounted && status == 'accepted') {
        setState(() {
          _pendingIncomingIds.remove(userId);
          _pendingOutgoingIds.remove(userId);
          _blockedIds.remove(userId);
          _friendIds.add(userId);
        });
      }
    } catch (error) {
      _showError('Could not update friend request: $error');
    }
  }

  Future<void> _removeRelationship(String userId) async {
    final relationId = _relationshipIds[userId];
    if (relationId == null ||
        relationId.isEmpty ||
        !SupabaseService.instance.hasSession) {
      _showError('Friend relationship is unavailable.');
      return;
    }
    try {
      await SupabaseService.instance.removeFriendship(relationId);
      if (mounted) {
        setState(() {
          _friendIds.remove(userId);
          _pendingIncomingIds.remove(userId);
          _pendingOutgoingIds.remove(userId);
          _blockedIds.remove(userId);
          _relationshipIds.remove(userId);
        });
      }
    } catch (error) {
      _showError('Could not update this relationship: $error');
    }
  }

  Future<void> _blockUser(String userId) async {
    if (!SupabaseService.instance.hasSession) {
      _showError('Friend service is unavailable.');
      return;
    }
    try {
      final row = await SupabaseService.instance.blockUser(userId);
      _relationshipIds[userId] = row['id'].toString();
      if (mounted) {
        setState(() {
          _friendIds.remove(userId);
          _pendingIncomingIds.remove(userId);
          _pendingOutgoingIds.remove(userId);
          _blockedIds.add(userId);
        });
      }
    } catch (error) {
      _showError('Could not block this user: $error');
    }
  }

  /// Add Friend Modal
  Future<void> _showAddFriendDialog() async {
    final currentUserId = ref.read(authProvider).userId;
    final candidates = _allUsers
        .where((u) =>
            u['id'].toString() != currentUserId &&
            !_friendIds.contains(u['id'].toString()))
        .toList();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a Friend'),
        content: SizedBox(
          width: 440,
          child: candidates.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'All organization members are already in your friends list!'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (ctx, i) {
                    final u = candidates[i];
                    final uid = u['id'].toString();

                    return ListTile(
                      leading: CircleAvatar(
                        child: Text((u['display_name']?.toString() ?? 'U')[0]
                            .toUpperCase()),
                      ),
                      title: Text(u['display_name']?.toString() ?? ''),
                      subtitle: Text('@${u['username']}'),
                      trailing: FilledButton.icon(
                        onPressed: () async {
                          if (await _sendFriendRequest(uid) && ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Friend request sent to ${u['display_name']}.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.person_add, size: 14),
                        label: const Text('Add Friend'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Open Direct Message Flow (Profile -> Message -> DM)
  Future<void> _startDM(Map<String, dynamic> user) async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.post(
        '${ApiEndpoints.conversations}/direct',
        data: {'recipient_id': user['id']},
      );
      final convId = res.data['id']?.toString();
      if (convId == null || convId.isEmpty) {
        throw const FormatException('Missing conversation ID');
      }
      if (mounted) context.go('/messages/$convId');
    } catch (_) {
      _showError('Could not open this conversation. Please try again.',
          retry: () => _startDM(user));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(presenceProvider);
    final theme = Theme.of(context);

    final friendUsers = _allUsers
        .where((u) => _friendIds.contains(u['id'].toString()))
        .toList();
    final pendingUsers = _allUsers
        .where((u) =>
            _pendingIncomingIds.contains(u['id'].toString()) ||
            _pendingOutgoingIds.contains(u['id'].toString()))
        .toList();
    final blockedUsers = _allUsers
        .where((u) => _blockedIds.contains(u['id'].toString()))
        .toList();

    return Scaffold(
      appBar: GlobalHeader(
        title: 'Friends',
        description: 'Direct Connections & Friend Requests',
        breadcrumbs: const ['ConnectHub', 'Friends'],
        primaryActionLabel: 'Add Friend',
        primaryActionIcon: Icons.person_add,
        onPrimaryAction:
            _isLoading || _loadError != null ? null : _showAddFriendDialog,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline),
                    const SizedBox(height: 12),
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry')),
                  ]),
                ))
              : Column(
                  children: [
                    TabBar(
                      controller: _tabController,
                      tabs: [
                        Tab(text: 'Friends (${friendUsers.length})'),
                        Tab(text: 'Pending (${pendingUsers.length})'),
                        Tab(text: 'Blocked (${blockedUsers.length})'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // 1. FRIENDS TAB
                          _buildFriendsList(friendUsers, theme),

                          // 2. PENDING TAB
                          _buildPendingList(pendingUsers, theme),

                          // 3. BLOCKED TAB
                          _buildBlockedList(blockedUsers, theme),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFriendsList(
      List<Map<String, dynamic>> friends, ThemeData theme) {
    if (friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 54, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('No friends added yet.',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _showAddFriendDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Your First Friend'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final u = friends[index];
        final uid = u['id'].toString();
        final isOnline = ref.watch(presenceProvider.notifier).isOnline(uid);
        final presenceColor =
            ref.watch(presenceProvider.notifier).getUserPresenceColor(uid);

        return Card(
          child: ListTile(
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.15),
                  child: Text(
                      (u['display_name']?.toString() ?? 'U')[0].toUpperCase()),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: PulsingStatusDot(
                    color: presenceColor,
                    size: 11,
                    isOnline: isOnline,
                  ),
                ),
              ],
            ),
            title: Text(u['display_name']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('@${u['username']}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => _startDM(u),
                  icon: const Icon(Icons.chat, size: 14),
                  label: const Text('Message'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.person_remove_outlined,
                      size: 18, color: Colors.white54),
                  onPressed: () => _removeRelationship(uid),
                  tooltip: 'Remove Friend',
                ),
                IconButton(
                  icon: const Icon(Icons.block,
                      size: 18, color: Colors.redAccent),
                  onPressed: () => _blockUser(uid),
                  tooltip: 'Block User',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingList(
      List<Map<String, dynamic>> pending, ThemeData theme) {
    if (pending.isEmpty) {
      return const Center(
        child: Text('No pending friend requests.',
            style: TextStyle(color: Colors.white54, fontSize: 16)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final u = pending[index];
        final uid = u['id'].toString();
        final isIncoming = _pendingIncomingIds.contains(uid);

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child:
                  Text((u['display_name']?.toString() ?? 'U')[0].toUpperCase()),
            ),
            title: Text(u['display_name']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle:
                Text(isIncoming ? 'Incoming Request' : 'Outgoing Request'),
            trailing: isIncoming
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            _setRelationshipStatus(uid, 'accepted'),
                        icon: const Icon(Icons.check, size: 14),
                        label: const Text('Accept'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _removeRelationship(uid),
                        child: const Text('Reject'),
                      ),
                    ],
                  )
                : OutlinedButton(
                    onPressed: () => _removeRelationship(uid),
                    child: const Text('Cancel Request'),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildBlockedList(
      List<Map<String, dynamic>> blocked, ThemeData theme) {
    if (blocked.isEmpty) {
      return const Center(
        child: Text('No blocked users.',
            style: TextStyle(color: Colors.white54, fontSize: 16)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: blocked.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final u = blocked[index];
        final uid = u['id'].toString();

        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.white12,
              child: Icon(Icons.block, color: Colors.redAccent),
            ),
            title: Text(u['display_name']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('@${u['username']}'),
            trailing: OutlinedButton.icon(
              onPressed: () => _removeRelationship(uid),
              icon: const Icon(Icons.lock_open, size: 14),
              label: const Text('Unblock'),
            ),
          ),
        );
      },
    );
  }
}
