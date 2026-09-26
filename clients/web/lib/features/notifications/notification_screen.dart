/// ConnectHub — Notification Screen (SaaSSchool Light Claymorphism Engine).
///
/// Features:
/// - Light Cream #FAF9F6 Background
/// - Official Lucide Icons (flutter_lucide)
/// - Category filter tabs: All, @ Mentions, Unread, Direct Messages
/// - Centered SaaSSchool Search Bar with clay depth shadows
/// - Pure white claymorphic notification cards with Rose-500 (#F43F5E) unread indicators
/// - Direct "Open Chat" action buttons with auto-mark-read
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/notifications/notification_provider.dart';
import '../../shared/widgets/global_header.dart';

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  final _searchController = TextEditingController();
  String _activeTab = 'all'; // 'all', 'mention', 'unread', 'message'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifState = ref.watch(notificationProvider);
    final notifNotifier = ref.read(notificationProvider.notifier);
    final searchQuery = _searchController.text.trim().toLowerCase();

    final filteredList = notifState.items.where((notif) {
      // 1. Tab filter
      if (_activeTab == 'mention' && notif['notification_type'] != 'mention') return false;
      if (_activeTab == 'unread' && notif['is_read'] == true) return false;
      if (_activeTab == 'message' && notif['notification_type'] != 'message') return false;

      // 2. Search query
      if (searchQuery.isNotEmpty) {
        final title = (notif['title'] ?? '').toString().toLowerCase();
        final body = (notif['body'] ?? '').toString().toLowerCase();
        if (!title.contains(searchQuery) && !body.contains(searchQuery)) return false;
      }

      return true;
    }).toList();

    final totalCount = notifState.items.length;
    final unreadCount = notifState.unreadCount;
    final mentionCount = notifState.items.where((i) => i['notification_type'] == 'mention' && i['is_read'] != true).length;
    final dmCount = notifState.items.where((i) => i['notification_type'] == 'message' && i['is_read'] != true).length;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      appBar: GlobalHeader(
        title: 'Notifications',
        description: 'Workspace Alerts & Activity Updates',
        breadcrumbs: const ['ConnectHub', 'Notifications'],
        primaryActionLabel: unreadCount > 0 ? 'Mark all read' : null,
        primaryActionIcon: unreadCount > 0 ? LucideIcons.check_check : null,
        onPrimaryAction: unreadCount > 0 ? () => notifNotifier.markAllAsRead() : null,
      ),
      body: Column(
        children: [
          // ── FILTER TABS & SEARCH BAR ─────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFAF9F6),
              border: Border(bottom: BorderSide(color: Color(0xFFE6E4E0))),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 650;
                final filterTabs = SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All', totalCount),
                      const SizedBox(width: 8),
                      _buildFilterChip('mention', '@ Mentions', mentionCount, isSpecial: true),
                      const SizedBox(width: 8),
                      _buildFilterChip('unread', 'Unread', unreadCount),
                      const SizedBox(width: 8),
                      _buildFilterChip('message', 'Direct Messages', dmCount),
                    ],
                  ),
                );

                final searchField = Container(
                  width: isCompact ? double.infinity : 260,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE6E4E0)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Color(0xFF1C1917), fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search alerts...',
                      hintStyle: TextStyle(color: Color(0xFF78716C), fontSize: 12.5),
                      prefixIcon: Icon(LucideIcons.search, size: 16, color: Color(0xFF78716C)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      isDense: true,
                    ),
                  ),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      filterTabs,
                      const SizedBox(height: 10),
                      searchField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: filterTabs),
                    const SizedBox(width: 16),
                    searchField,
                  ],
                );
              },
            ),
          ),

          // ── NOTIFICATIONS LIST ───────────────────────────────
          Expanded(
            child: notifState.isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
                : filteredList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF9),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFCCFBF1)),
                              ),
                              child: const Icon(LucideIcons.bell_off, size: 32, color: Color(0xFF0F766E)),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No notifications found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1C1917),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'You are completely up to date.',
                              style: TextStyle(color: Color(0xFF78716C), fontSize: 13.5),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        itemCount: filteredList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final notif = filteredList[index];
                          final id = notif['id']?.toString() ?? '';
                          final isRead = notif['is_read'] == true;
                          final convId = notif['conversation_id']?.toString();
                          final msgId = notif['resource_id']?.toString() ?? notif['message_id']?.toString();
                          final type = notif['notification_type']?.toString();
                          final isMention = type == 'mention';
                          final isMessage = type == 'message';
                          final isInvitation = type == 'invitation' || notif['resource_type'] == 'group_invite';
                          final groupId = notif['resource_id']?.toString() ?? '';
                          final timeStr = _formatTimeAgo(notif['created_at']);

                          void openTarget() {
                            notifNotifier.markAsRead(id);
                            if (convId != null && convId.isNotEmpty) {
                              final route = (msgId != null && msgId.isNotEmpty && msgId != convId)
                                  ? '/messages/$convId?from=notifications&highlight=$msgId'
                                  : '/messages/$convId?from=notifications';
                              context.go(route);
                            } else {
                              context.go('/messages?from=notifications');
                            }
                          }

                          Future<void> respondInvite(String action) async {
                            try {
                              final api = ref.read(apiClientProvider);
                              final res = await api.dio.post(
                                '${ApiEndpoints.groups}/$groupId/invitations/respond',
                                data: {'action': action, 'notification_id': id},
                              );
                              await ref.read(notificationProvider.notifier).refresh();
                              if (context.mounted) {
                                if (action == 'accept') {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('You have successfully joined the group! 🎉')),
                                  );
                                  final targetConv = res.data?['conversation_id']?.toString() ?? convId;
                                  if (targetConv != null && targetConv.isNotEmpty) {
                                    context.go('/messages/$targetConv?from=notifications');
                                  }
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Invitation declined.')),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Failed to respond to invitation.')),
                                );
                              }
                            }
                          }

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: isInvitation ? null : openTarget,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isRead ? Colors.white.withValues(alpha: 0.9) : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isRead
                                        ? const Color(0xFFE6E4E0)
                                        : (isMention ? const Color(0xFFC7D2FE) : (isInvitation ? const Color(0xFF99F6E4) : const Color(0xFFCCFBF1))),
                                    width: isRead ? 1.0 : 1.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0xFFE6E4E0),
                                      blurRadius: 12,
                                      offset: Offset(4, 4),
                                    ),
                                    BoxShadow(
                                      color: Colors.white,
                                      blurRadius: 12,
                                      offset: Offset(-4, -4),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(18),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Icon Avatar
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: isMention
                                            ? const Color(0xFFEEF2FF)
                                            : (isInvitation ? const Color(0xFFF0FDF4) : (isMessage ? const Color(0xFFF0FDF9) : const Color(0xFFFEF3C7))),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isMention
                                              ? const Color(0xFFC7D2FE)
                                              : (isInvitation ? const Color(0xFF86EFAC) : (isMessage ? const Color(0xFFCCFBF1) : const Color(0xFFFDE68A))),
                                        ),
                                      ),
                                      child: Icon(
                                        _iconForType(type),
                                        color: isMention
                                            ? const Color(0xFF4F46E5)
                                            : (isInvitation ? const Color(0xFF16A34A) : (isMessage ? const Color(0xFF0F766E) : const Color(0xFFD97706))),
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    // Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              if (!isRead) ...[
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  margin: const EdgeInsets.only(right: 8),
                                                  decoration: BoxDecoration(
                                                    color: isMention ? const Color(0xFF4F46E5) : const Color(0xFFF43F5E),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  notif['title']?.toString() ?? '',
                                                  style: TextStyle(
                                                    fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                                    fontSize: 15,
                                                    color: const Color(0xFF1C1917),
                                                  ),
                                                ),
                                              ),
                                              if (isMention) ...[
                                                Container(
                                                  margin: const EdgeInsets.only(left: 8),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEEF2FF),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFFC7D2FE)),
                                                  ),
                                                  child: const Text(
                                                    '@Mention',
                                                    style: TextStyle(
                                                      color: Color(0xFF4F46E5),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              if (isInvitation) ...[
                                                Container(
                                                  margin: const EdgeInsets.only(left: 8),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF0FDF4),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                                  ),
                                                  child: const Text(
                                                    'Invitation',
                                                    style: TextStyle(
                                                      color: Color(0xFF16A34A),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              Text(
                                                timeStr,
                                                style: const TextStyle(color: Color(0xFF78716C), fontSize: 12, fontWeight: FontWeight.w500),
                                              ),
                                            ],
                                          ),
                                          if (notif['body'] != null && notif['body'].toString().isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              notif['body'].toString(),
                                              style: const TextStyle(color: Color(0xFF78716C), fontSize: 13.5, height: 1.4),
                                            ),
                                          ],
                                          const SizedBox(height: 12),
                                          Wrap(
                                            alignment: WrapAlignment.end,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: [
                                              if (isInvitation && !isRead) ...[
                                                OutlinedButton.icon(
                                                  icon: const Icon(LucideIcons.x, size: 14),
                                                  label: const Text('Reject', style: TextStyle(fontSize: 12.5)),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: const Color(0xFFEF4444),
                                                    side: const BorderSide(color: Color(0xFFFECACA)),
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                                                  ),
                                                  onPressed: () => respondInvite('reject'),
                                                ),
                                                FilledButton.icon(
                                                  icon: const Icon(LucideIcons.check, size: 14),
                                                  label: const Text('Join Group', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: const Color(0xFF0F766E),
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                                                    elevation: 0,
                                                  ),
                                                  onPressed: () => respondInvite('accept'),
                                                ),
                                              ] else ...[
                                                if (!isRead)
                                                  TextButton.icon(
                                                    icon: const Icon(LucideIcons.check, size: 14, color: Color(0xFF78716C)),
                                                    label: const Text('Mark read', style: TextStyle(color: Color(0xFF78716C), fontSize: 12.5)),
                                                    onPressed: () => notifNotifier.markAsRead(id),
                                                    style: TextButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    ),
                                                  ),
                                                if (convId != null && convId.isNotEmpty)
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF0F766E),
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                                                      elevation: 0,
                                                    ),
                                                    onPressed: openTarget,
                                                    icon: const Icon(LucideIcons.message_square, size: 14),
                                                    label: const Text('Open', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                                  ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, int count, {bool isSpecial = false}) {
    final isSelected = _activeTab == key;
    return InkWell(
      borderRadius: BorderRadius.circular(9999),
      onTap: () => setState(() => _activeTab = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isSpecial ? const Color(0xFFEEF2FF) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: isSelected
                ? (isSpecial ? const Color(0xFFC7D2FE) : const Color(0xFF0F766E))
                : const Color(0xFFE6E4E0),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0xFFE6E4E0),
                    blurRadius: 6,
                    offset: Offset(2, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? (isSpecial ? const Color(0xFF4F46E5) : const Color(0xFF0F766E))
                    : const Color(0xFF78716C),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isSpecial ? const Color(0xFF4F46E5) : const Color(0xFF0F766E))
                      : (isSpecial ? const Color(0xFFEEF2FF) : const Color(0xFFF43F5E)),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (isSpecial ? const Color(0xFF4F46E5) : Colors.white),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'message': return LucideIcons.message_square;
      case 'file': return LucideIcons.file_text;
      case 'mention': return LucideIcons.at_sign;
      case 'invitation': return LucideIcons.user_plus;
      case 'system': return LucideIcons.info;
      default: return LucideIcons.bell;
    }
  }

  String _formatTimeAgo(dynamic raw) {
    if (raw == null) return 'Just now';
    try {
      final dt = DateTime.parse(raw.toString());
      final diff = DateTime.now().toUtc().difference(dt.toUtc());
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Recent';
    }
  }
}
