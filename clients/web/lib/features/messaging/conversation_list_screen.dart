/// ConnectHub — Conversation List Screen.
///
/// Features:
/// - List all active conversations (DMs and Groups)
/// - Start new Direct Message modal with user picker
/// - Display conversation title (Group name or recipient name)
/// - Tap to enter ChatScreen
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  @override
  ConsumerState<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends ConsumerState<ConversationListScreen> {
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);

      // 1. Fetch conversations
      final response = await api.dio.get(ApiEndpoints.conversations);
      final data = response.data;
      if (data is Map && data.containsKey('items')) {
        _conversations = List<Map<String, dynamic>>.from(data['items']);
      } else if (data is List) {
        _conversations = List<Map<String, dynamic>>.from(data);
      }

      // 2. Fetch users for DM creation
      try {
        final uRes = await api.dio.get(ApiEndpoints.directory);
        if (uRes.data is List) {
          _allUsers = List<Map<String, dynamic>>.from(uRes.data);
        } else if (uRes.data is Map && uRes.data.containsKey('items')) {
          _allUsers = List<Map<String, dynamic>>.from(uRes.data['items']);
        }
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  /// Start a new DM with selected user
  Future<void> _startDirectMessage() async {
    final currentUserId = ref.read(authProvider).userId;
    final otherUsers = _allUsers.where((u) => u['id'] != currentUserId).toList();

    final selectedUser = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start Direct Message'),
        content: SizedBox(
          width: 360,
          child: otherUsers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No other users available'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: otherUsers.length,
                  itemBuilder: (ctx, i) {
                    final u = otherUsers[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text((u['display_name']?.toString() ?? '?')[0].toUpperCase()),
                      ),
                      title: Text(u['display_name']?.toString() ?? ''),
                      subtitle: Text('@${u['username']}'),
                      onTap: () => Navigator.pop(ctx, u),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (selectedUser != null) {
      try {
        final api = ref.read(apiClientProvider);
        final res = await api.dio.post(
          '${ApiEndpoints.conversations}/direct',
          data: {'recipient_id': selectedUser['id']},
        );
        final convId = res.data['id'].toString();
        _load();
        if (mounted) context.go('/messages/$convId');
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to start conversation.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = ref.watch(authProvider).userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages & Chats'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _startDirectMessage,
            icon: const Icon(Icons.mark_unread_chat_alt, size: 18),
            label: const Text('New Direct Message'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 54, color: Color(0xFFD6D3D1)),
                      const SizedBox(height: 16),
                      const Text('No conversations yet', style: TextStyle(color: Color(0xFF78716C), fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _startDirectMessage,
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                        icon: const Icon(Icons.add),
                        label: const Text('Start a Message'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _conversations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final conv = _conversations[index];
                    final convType = conv['conversation_type'] ?? conv['type'] ?? 'direct';
                    final lastMsg = conv['last_message'] as Map<String, dynamic>?;

                    // Compute title and icon
                    IconData iconData = Icons.chat;
                    String title = 'Chat';

                    if (convType == 'channel') {
                      iconData = Icons.tag;
                      title = '# ${conv['name'] ?? conv['title'] ?? 'Channel'}';
                    } else if (convType == 'group') {
                      iconData = Icons.group;
                      title = '👥 ${conv['name'] ?? conv['title'] ?? 'Group Chat'}';
                    } else {
                      iconData = Icons.person;
                      String? targetId;
                      final participants = conv['participants'];
                      if (participants is List && participants.isNotEmpty) {
                        for (final p in participants) {
                          final pid = (p is Map ? (p['user_id'] ?? p['id']) : p)?.toString();
                          if (pid != null && pid != currentUserId) {
                            targetId = pid;
                            break;
                          }
                        }
                      }
                      targetId ??= conv['target_id']?.toString() ?? conv['recipient_id']?.toString();

                      final matchUser = targetId != null ? _allUsers.firstWhere((u) => u['id'].toString() == targetId, orElse: () => <String, dynamic>{}) : <String, dynamic>{};
                      if (matchUser.isNotEmpty && matchUser['id'].toString() != currentUserId) {
                        title = matchUser['display_name']?.toString() ?? matchUser['username']?.toString() ?? 'Direct Message';
                      } else if (conv['recipient_name'] != null && conv['recipient_name'].toString().isNotEmpty && conv['recipient_name'] != 'Direct Message') {
                        title = conv['recipient_name'].toString();
                      } else if (conv['display_name'] != null && conv['display_name'].toString().isNotEmpty && conv['display_name'] != 'Direct Message') {
                        title = conv['display_name'].toString();
                      } else {
                        final senderId = lastMsg?['sender_id']?.toString();
                        final lmUser = senderId != null ? _allUsers.firstWhere((u) => u['id'].toString() == senderId, orElse: () => <String, dynamic>{}) : <String, dynamic>{};
                        if (lmUser.isNotEmpty && senderId != currentUserId) {
                          title = lmUser['display_name']?.toString() ?? lmUser['username']?.toString() ?? 'Direct Message';
                        } else {
                          title = 'Direct Message';
                        }
                      }
                    }

                    String lastMsgPreview = 'Click to open chat';
                    if (lastMsg != null && lastMsg['content'] != null) {
                      final text = lastMsg['content'].toString();
                      final senderId = lastMsg['sender_id']?.toString();
                      final isSelf = (senderId != null && senderId == currentUserId) || lastMsg['is_self'] == true;
                      lastMsgPreview = isSelf ? 'You: $text' : text;
                    }

                    return Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE6E4E0)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFF0FDF9),
                          child: Icon(iconData, color: const Color(0xFF0F766E)),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1C1917)),
                        ),
                        subtitle: Text(
                          lastMsgPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF78716C), fontSize: 13),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFA8A29E)),
                        onTap: () => context.go('/messages/${conv['id']}'),
                      ),
                    );
                  },
                ),
    );
  }
}
