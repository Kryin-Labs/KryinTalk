/// ConnectHub — Notification Center Dialog (SaaSSchool Light Claymorphism Engine).
///
/// Features:
/// - Exact SaaSSchool styling: #FAF9F6 cream background, pure white claymorphic cards
/// - Official Lucide Icons (flutter_lucide)
/// - Real-time unread alerts & live counters with Rose-500 (#F43F5E) badges
/// - Filter Tabs: All, @ Mentions, Unread, Direct Messages (capsule pills)
/// - 1-Click "Open Chat" navigation with auto-mark-read
/// - Single & batch "Mark all as read" actions
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/notifications/notification_provider.dart';

class NotificationCenterDialog extends ConsumerStatefulWidget {
  const NotificationCenterDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => const NotificationCenterDialog(),
    );
  }

  @override
  ConsumerState<NotificationCenterDialog> createState() => _NotificationCenterDialogState();
}

class _NotificationCenterDialogState extends ConsumerState<NotificationCenterDialog> {
  String _activeTab = 'all'; // 'all', 'mention', 'unread', 'message'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifState = ref.watch(notificationProvider);
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Filter items based on active tab
    final filteredItems = notifState.items.where((item) {
      if (_activeTab == 'mention') {
        return item['notification_type'] == 'mention';
      } else if (_activeTab == 'unread') {
        return item['is_read'] != true;
      } else if (_activeTab == 'message') {
        return item['notification_type'] == 'message';
      }
      return true;
    }).toList();

    final unreadCount = notifState.unreadCount;
    final mentionCount = notifState.items.where((i) => i['notification_type'] == 'mention' && i['is_read'] != true).length;
    final dmCount = notifState.items.where((i) => i['notification_type'] == 'message' && i['is_read'] != true).length;

    return Dialog(
      backgroundColor: const Color(0xFFFAF9F6), // SaaSSchool Light Cream
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0xFFE6E4E0), width: 1.5),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: isMobile ? 24 : 40,
      ),
      child: Container(
        width: 580,
        height: 660,
        decoration: BoxDecoration(
          color: const Color(0xFFFAF9F6),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFFE6E4E0),
              blurRadius: 30,
              offset: Offset(10, 10),
            ),
            BoxShadow(
              color: Colors.white,
              blurRadius: 30,
              offset: Offset(-10, -10),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── TOP HEADER ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE6E4E0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF9), // SaaSSchool bg-teal-50
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCCFBF1)),
                    ),
                    child: const Icon(LucideIcons.bell_ring, color: Color(0xFF0F766E), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C1917), // Charcoal
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (unreadCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF43F5E), // Rose-500
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Text(
                              '$unreadCount New',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (unreadCount > 0) ...[
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () => ref.read(notificationProvider.notifier).markAllAsRead(),
                      icon: const Icon(LucideIcons.check_check, size: 14, color: Color(0xFF0F766E)),
                      label: const Text(
                        'Mark all read',
                        style: TextStyle(color: Color(0xFF0F766E), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        backgroundColor: const Color(0xFFF0FDF9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9999),
                          side: const BorderSide(color: Color(0xFFCCFBF1)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Color(0xFF78716C), size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── FILTER TABS ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFAF9F6),
                border: Border(bottom: BorderSide(color: Color(0xFFE6E4E0))),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('all', 'All', notifState.items.length),
                    const SizedBox(width: 8),
                    _buildFilterChip('mention', '@ Mentions', mentionCount, isSpecial: true),
                    const SizedBox(width: 8),
                    _buildFilterChip('unread', 'Unread', unreadCount),
                    const SizedBox(width: 8),
                    _buildFilterChip('message', 'Direct Messages', dmCount),
                  ],
                ),
              ),
            ),

            // ── NOTIFICATIONS LIST ───────────────────────────────
            Expanded(
              child: notifState.isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
                  : filteredItems.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: filteredItems.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final id = item['id']?.toString() ?? '';
                            final title = item['title']?.toString() ?? '';
                            final body = item['body']?.toString() ?? '';
                            final isRead = item['is_read'] == true;
                            final type = item['notification_type']?.toString() ?? 'system';
                            final convId = item['conversation_id']?.toString();
                            final timeStr = _formatTimeAgo(item['created_at']);

                            final msgId = item['resource_id']?.toString() ?? item['message_id']?.toString();
                            final resourceType = item['resource_type']?.toString();
                            final resourceId = item['resource_id']?.toString();

                            return _buildNotificationCard(
                              id: id,
                              title: title,
                              body: body,
                              isRead: isRead,
                              type: type,
                              convId: convId,
                              msgId: msgId,
                              resourceType: resourceType,
                              resourceId: resourceId,
                              timeStr: timeStr,
                            );
                          },
                        ),
            ),

            // ── BOTTOM ACTION BAR ────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFFFAF9F6),
                border: Border(top: BorderSide(color: Color(0xFFE6E4E0))),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${filteredItems.length} alerts loaded',
                    style: const TextStyle(color: Color(0xFF78716C), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go('/notifications');
                    },
                    icon: const Icon(LucideIcons.external_link, size: 15, color: Color(0xFF0F766E)),
                    label: const Text('View Full Screen Page', style: TextStyle(color: Color(0xFF0F766E), fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                    fontSize: 10.5,
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

  Widget _buildNotificationCard({
    required String id,
    required String title,
    required String body,
    required bool isRead,
    required String type,
    required String? convId,
    required String? msgId,
    String? resourceType,
    String? resourceId,
    required String timeStr,
  }) {
    final isMention = type == 'mention';
    final isMessage = type == 'message';
    final isInvitation = type == 'invitation' || resourceType == 'group_invite';
    final groupId = resourceId ?? '';

    void openTarget() {
      ref.read(notificationProvider.notifier).markAsRead(id);
      Navigator.of(context).pop();
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
            Navigator.of(context).pop();
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: isRead ? Colors.white.withValues(alpha: 0.85) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isRead
                  ? const Color(0xFFE6E4E0)
                  : (isMention ? const Color(0xFFC7D2FE) : (isInvitation ? const Color(0xFF99F6E4) : const Color(0xFFCCFBF1))),
              width: isRead ? 1.0 : 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFFE6E4E0),
                blurRadius: 10,
                offset: Offset(4, 4),
              ),
              BoxShadow(
                color: Colors.white,
                blurRadius: 10,
                offset: Offset(-4, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isMention
                      ? const Color(0xFFEEF2FF)
                      : (isInvitation ? const Color(0xFFF0FDF4) : (isMessage ? const Color(0xFFF0FDF9) : const Color(0xFFFEF3C7))),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMention
                        ? const Color(0xFFC7D2FE)
                        : (isInvitation ? const Color(0xFF86EFAC) : (isMessage ? const Color(0xFFCCFBF1) : const Color(0xFFFDE68A))),
                  ),
                ),
                child: Icon(
                  isMention
                      ? LucideIcons.at_sign
                      : (isInvitation ? LucideIcons.user_plus : (isMessage ? LucideIcons.message_square : LucideIcons.bell)),
                  color: isMention
                      ? const Color(0xFF4F46E5)
                      : (isInvitation ? const Color(0xFF16A34A) : (isMessage ? const Color(0xFF0F766E) : const Color(0xFFD97706))),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),

              // Content
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
                            title,
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                              fontSize: 14.5,
                              color: const Color(0xFF1C1917), // Charcoal
                            ),
                          ),
                        ),
                        if (isMention) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFC7D2FE)),
                            ),
                            child: const Text(
                              '@Mention',
                              style: TextStyle(
                                color: Color(0xFF4F46E5),
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (isInvitation) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: const Text(
                              'Invite',
                              style: TextStyle(
                                color: Color(0xFF16A34A),
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Color(0xFF78716C),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: const TextStyle(
                          color: Color(0xFF78716C),
                          fontSize: 13,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (isInvitation && !isRead) ...[
                          OutlinedButton.icon(
                            icon: const Icon(LucideIcons.x, size: 13),
                            label: const Text('Decline', style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFFECACA)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                            ),
                            onPressed: () => respondInvite('reject'),
                          ),
                          FilledButton.icon(
                            icon: const Icon(LucideIcons.check, size: 13),
                            label: const Text('Join Group', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                              elevation: 0,
                            ),
                            onPressed: () => respondInvite('accept'),
                          ),
                        ] else ...[
                          if (!isRead)
                            TextButton.icon(
                              onPressed: () => ref.read(notificationProvider.notifier).markAsRead(id),
                              icon: const Icon(LucideIcons.check, size: 14, color: Color(0xFF78716C)),
                              label: const Text('Mark read', style: TextStyle(color: Color(0xFF78716C), fontSize: 12)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              ),
                            ),
                          if (convId != null && convId.isNotEmpty)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                                elevation: 0,
                              ),
                              onPressed: openTarget,
                              icon: const Icon(LucideIcons.message_circle, size: 14),
                              label: const Text('Open', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
  }

  Widget _buildEmptyState() {
    return Center(
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
            'All caught up!',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1C1917),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No notifications found in this category.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF78716C),
            ),
          ),
        ],
      ),
    );
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
