/// ConnectHub — Professional Minimalist Light-Theme Home & Activity Hub.
///
/// Features:
/// - Official App Light Cream Theme (#FAF9F6) & Crisp White Minimalist Cards (#FFFFFF).
/// - Clean Typography, High Contrast Dark Charcoal Text (#1C1917), and Deep Teal Accents (#0F766E).
/// - Minimalist User Header: Avatar, Name, Handle, Role, Status Switcher (🟢, 🟡, 🔴, 🟣), and Quick Actions.
/// - Metrics Ribbon: Online Teammates, Unread Messages, Active Groups.
/// - Active Now Friends Strip: Clean horizontal teammate avatars with live presence indicators.
/// - Recent Conversations: WhatsApp-style clean cards with unread badges, snippets, and 1-click navigation to `/messages`.
/// - Groups & Squads Hub: Clean squad cards with member counters and 1-click launch.
/// - Community Bulletin: Minimalist announcements card.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/presence/presence_provider.dart';
import '../../core/updater/app_updater.dart';
import '../../shared/widgets/global_header.dart';
import '../../shared/widgets/pulsing_status_dot.dart';
import '../../shared/widgets/skeleton_loader.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _recentNotifications = [];
  final Map<String, Map<String, dynamic>> _userCache = {};

  String _userStatus = 'online'; // 'online', 'away', 'busy', 'focus'
  bool _isLoading = true;
  Timer? _pollingTimer;

  // Minimalist Light Theme Color Tokens
  static const _bgCream = Color(0xFFFAF9F6);
  static const _cardWhite = Colors.white;
  static const _borderMuted = Color(0xFFE6E4E0);
  static const _textDark = Color(0xFF1C1917);
  static const _textMuted = Color(0xFF78716C);
  static const _primaryTeal = Color(0xFF0F766E);
  static const _tealLight = Color(0xFFF0FDF9);
  static const _onlineGreen = Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _loadDashboardData(isSilent: true);
      }
    });
  }

  Future<void> _loadDashboardData({bool isSilent = false}) async {
    final authState = ref.read(authProvider);
    if (!authState.hasAppAccess) {
      if (mounted && !isSilent) setState(() => _isLoading = false);
      return;
    }

    if (!isSilent) setState(() => _isLoading = true);
    final api = ref.read(apiClientProvider);

    try {
      Future<void> loadUsers() async {
        try {
          final uRes = await api.dio.get(ApiEndpoints.directory);
          final uList = uRes.data is List
              ? uRes.data
              : (uRes.data is Map && uRes.data.containsKey('items')
                  ? uRes.data['items']
                  : []);
          _allUsers = List<Map<String, dynamic>>.from(uList);
          for (final u in _allUsers) {
            if (u['id'] != null) {
              _userCache[u['id'].toString()] = u;
            }
          }
        } catch (e) {
          debugPrint('[Dashboard] Error fetching directory: $e');
        }
      }

      Future<void> loadConversations() async {
        try {
          final convRes = await api.dio.get(ApiEndpoints.conversations);
          final items =
              (convRes.data is Map && convRes.data.containsKey('items'))
                  ? convRes.data['items'] as List
                  : (convRes.data is List ? convRes.data : []);
          _conversations = List<Map<String, dynamic>>.from(items);
          for (final conv in _conversations) {
            if (conv['participant_details'] is List) {
              for (final p in conv['participant_details']) {
                if (p is Map && p['id'] != null) {
                  _userCache[p['id'].toString()] = Map<String, dynamic>.from(p);
                }
              }
            }
            if (conv['recipient_id'] != null) {
              _userCache[conv['recipient_id'].toString()] = {
                'id': conv['recipient_id'],
                'username': conv['recipient_username'] ?? '',
                'display_name':
                    conv['recipient_name'] ?? conv['recipient_username'] ?? '',
                'avatar_url': conv['recipient_avatar_url'],
              };
            }
          }
        } catch (e) {
          debugPrint('[Dashboard] Error fetching conversations: $e');
        }
      }

      Future<void> loadGroups() async {
        try {
          final grpRes = await api.dio.get(ApiEndpoints.groups);
          final items = (grpRes.data is Map && grpRes.data.containsKey('items'))
              ? grpRes.data['items'] as List
              : (grpRes.data is List ? grpRes.data : []);
          _groups = List<Map<String, dynamic>>.from(items);
        } catch (e) {
          debugPrint('[Dashboard] Error fetching groups: $e');
        }
      }

      Future<void> loadNotifications() async {
        try {
          final notifRes = await api.dio.get(ApiEndpoints.notifications);
          final items =
              (notifRes.data is Map && notifRes.data.containsKey('items'))
                  ? notifRes.data['items'] as List
                  : (notifRes.data is List ? notifRes.data : []);
          _recentNotifications = List<Map<String, dynamic>>.from(items);
        } catch (e) {
          debugPrint('[Dashboard] Error fetching notifications: $e');
        }
      }

      await Future.wait([
        loadUsers(),
        loadConversations(),
        loadGroups(),
        loadNotifications(),
      ]);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startDirectMessageWithUser(String targetUserId) async {
    final api = ref.read(apiClientProvider);
    try {
      final res = await api.dio.post(
        '${ApiEndpoints.conversations}/direct',
        data: {'recipient_id': targetUserId},
      );
      if (res.data is Map && res.data['id'] != null) {
        final convId = res.data['id'].toString();
        if (mounted) {
          context.go('/messages?conv=$convId&from=dashboard');
        }
        return;
      }
    } catch (e) {
      final existing = _conversations.firstWhere(
        (c) {
          if (c['conversation_type'] != 'direct' && c['type'] != 'direct')
            return false;
          final participants = c['participants'];
          if (participants is List) {
            for (final p in participants) {
              final pid = (p is Map ? p['user_id'] ?? p['id'] : p)?.toString();
              if (pid == targetUserId) return true;
            }
          }
          return c['target_id']?.toString() == targetUserId ||
              c['recipient_id']?.toString() == targetUserId;
        },
        orElse: () => <String, dynamic>{},
      );
      if (existing.isNotEmpty && existing['id'] != null) {
        if (mounted) {
          context.go('/messages?conv=${existing['id']}&from=dashboard');
        }
        return;
      }
    }
    if (mounted) context.go('/messages?from=dashboard');
  }

  Future<void> _openCreateGroupDialog() async {
    final authState = ref.read(authProvider);
    final isSuper = authState.isSuperAdmin;
    final isAdmin = authState.isAdmin;
    final currentUserId = authState.userId;

    if (!isSuper && !isAdmin && currentUserId != null) {
      final ownedCount = _groups
          .where((g) => g['created_by']?.toString() == currentUserId)
          .length;
      if (ownedCount >= 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFEF4444),
              content: Text(
                  'You are limited to a maximum of 2 groups. Please contact an administrator.'),
            ),
          );
        }
        return;
      }
    }

    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isViewOnly = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _cardWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: _borderMuted),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _tealLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.users,
                    color: _primaryTeal, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Create New Group',
                style: TextStyle(
                    color: _textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Group Name *',
                    style: TextStyle(
                        color: _textDark,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: _textDark),
                  decoration: InputDecoration(
                    hintText: 'e.g. Design Squad, Engineering',
                    hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
                    filled: true,
                    fillColor: _bgCream,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderMuted)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderMuted)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _primaryTeal, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Description',
                    style: TextStyle(
                        color: _textDark,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: _textDark),
                  decoration: InputDecoration(
                    hintText: 'Group mission and purpose...',
                    hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
                    filled: true,
                    fillColor: _bgCream,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderMuted)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderMuted)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _primaryTeal, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isViewOnly
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFF9FAFB),
                    border: Border.all(
                      color: isViewOnly
                          ? _primaryTeal.withValues(alpha: 0.4)
                          : _borderMuted,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isViewOnly,
                    activeColor: _primaryTeal,
                    title: const Row(
                      children: [
                        Text(
                          'View-Only Group by Default 👁️',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _textDark),
                        ),
                      ],
                    ),
                    subtitle: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'All members can only view messages by default. Only the group creator and members with elevated roles can post.',
                        style: TextStyle(fontSize: 11, color: _textMuted),
                      ),
                    ),
                    onChanged: (v) => setDialogState(() => isViewOnly = v),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: _textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Create Group'),
            ),
          ],
        ),
      ),
    );

    if (created == true) {
      try {
        final api = ref.read(apiClientProvider);
        await api.dio.post(
          ApiEndpoints.groups,
          data: {
            'name': nameCtrl.text.trim(),
            'slug': nameCtrl.text
                .trim()
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]'), '-'),
            'description': descCtrl.text.trim(),
            'is_view_only': isViewOnly,
          },
        );
        await _loadDashboardData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: _primaryTeal,
              content: Text('Group created successfully!'),
            ),
          );
        }
      } catch (e) {
        String msg = 'Failed to create group.';
        if (e is DioException && e.response?.data is Map) {
          msg = e.response?.data['message']?.toString() ??
              e.response?.data['detail']?.toString() ??
              msg;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: Text(msg),
            ),
          );
        }
      }
    }
  }

  void _openNewChatDialog() {
    final searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = searchCtrl.text.toLowerCase();
          final authState = ref.read(authProvider);
          final currentUserId = authState.userId;
          final filtered = _allUsers.where((u) {
            if (u['id'].toString() == currentUserId) return false;
            final isHidden = u['hide_from_direct_message'] == true ||
                u['preferences']?['hide_from_direct_message'] == true;
            if (isHidden && !authState.isSuperAdmin && !authState.isAdmin) {
              return false;
            }
            final name = (u['display_name'] ?? '').toString().toLowerCase();
            final username = (u['username'] ?? '').toString().toLowerCase();
            return name.contains(query) || username.contains(query);
          }).toList();

          return AlertDialog(
            backgroundColor: _cardWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: _borderMuted),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _tealLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.message_square_plus,
                      color: _primaryTeal, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Start Direct Message',
                  style: TextStyle(
                      color: _textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setModalState(() {}),
                    style: const TextStyle(color: _textDark),
                    decoration: InputDecoration(
                      hintText: 'Search teammates by name or username...',
                      hintStyle:
                          const TextStyle(color: _textMuted, fontSize: 13),
                      prefixIcon: const Icon(LucideIcons.search,
                          color: _textMuted, size: 18),
                      filled: true,
                      fillColor: _bgCream,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderMuted),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderMuted),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _primaryTeal, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No teammates found',
                              style: TextStyle(color: _textMuted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: _borderMuted, height: 1),
                            itemBuilder: (context, idx) {
                              final u = filtered[idx];
                              final uId = u['id']?.toString() ?? '';
                              final name =
                                  u['display_name'] ?? u['username'] ?? 'User';
                              final username = u['username'] ?? '';
                              final role = u['role'] ?? 'member';
                              final isOnline = ref
                                  .read(presenceProvider.notifier)
                                  .isOnline(uId);

                              final statusColor = ref
                                  .read(presenceProvider.notifier)
                                  .getUserPresenceColor(uId);

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: _primaryTeal,
                                      child: Text(
                                        (name.isNotEmpty ? name[0] : 'U')
                                            .toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: PulsingStatusDot(
                                        color: statusColor,
                                        size: 10,
                                        isOnline: isOnline,
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                      color: _textDark,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                                subtitle: Text(
                                  '@$username • ${role.toUpperCase()}',
                                  style: const TextStyle(
                                      color: _textMuted, fontSize: 11),
                                ),
                                trailing: const Icon(LucideIcons.send,
                                    size: 16, color: _primaryTeal),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _startDirectMessageWithUser(uId);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: _textMuted)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openStatusDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _borderMuted),
        ),
        title: const Text('Set Presence Status',
            style: TextStyle(
                color: _textDark, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusOption(ctx, 'online', 'Online',
                'Available to collaborate', const Color(0xFF10B981)),
            _buildStatusOption(
                ctx, 'away', 'Away', 'Stepped away', const Color(0xFFF59E0B)),
            _buildStatusOption(ctx, 'busy', 'Do Not Disturb',
                'Focus mode active', const Color(0xFFEF4444)),
            _buildStatusOption(ctx, 'focus', 'Deep Focus',
                'Working on high-priority tasks', const Color(0xFF8B5CF6)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOption(BuildContext dialogCtx, String key, String title,
      String subtitle, Color color) {
    final isSelected = _userStatus == key;
    return ListTile(
      leading: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
      title: Text(title,
          style: TextStyle(
              color: isSelected ? _primaryTeal : _textDark,
              fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: _textMuted, fontSize: 11)),
      trailing: isSelected
          ? const Icon(LucideIcons.check, color: _primaryTeal, size: 18)
          : null,
      onTap: () {
        setState(() => _userStatus = key);
        ref.read(presenceProvider.notifier).setCustomStatus(key);
        Navigator.pop(dialogCtx);
      },
    );
  }

  Color _getStatusColor() {
    return ref.read(presenceProvider.notifier).getStatusColor(_userStatus);
  }

  String _resolveConvTitle(Map<String, dynamic> conv, String? currentUserId) {
    final type = conv['conversation_type']?.toString() ?? 'direct';
    if (type == 'group') {
      if (conv['name'] != null &&
          conv['name'].toString().isNotEmpty &&
          conv['name'] != 'Group Chat') {
        return '👥 ${conv['name']}';
      }
      if (conv['title'] != null &&
          conv['title'].toString().isNotEmpty &&
          conv['title'] != 'Group Chat') {
        return '👥 ${conv['title']}';
      }
      final targetId = conv['target_id']?.toString();
      if (targetId != null) {
        final match = _groups.firstWhere((g) => g['id']?.toString() == targetId,
            orElse: () => <String, dynamic>{});
        if (match.isNotEmpty &&
            match['name'] != null &&
            match['name'].toString().isNotEmpty) {
          return '👥 ${match['name']}';
        }
      }
      return '👥 Group';
    } else if (type == 'channel') {
      return '# ${conv['name'] ?? conv['title'] ?? 'Channel'}';
    } else {
      // 1. Check explicit recipient fields first (from backend ConversationResponse)
      final rName = conv['recipient_name']?.toString() ??
          conv['recipient_username']?.toString();
      if (rName != null &&
          rName.trim().isNotEmpty &&
          rName != 'Direct Message' &&
          rName != 'Conversation') {
        return rName.trim();
      }

      // 2. Check explicit display_name / title / name fields
      final dName = conv['display_name']?.toString() ??
          conv['title']?.toString() ??
          conv['name']?.toString();
      if (dName != null &&
          dName.trim().isNotEmpty &&
          dName != 'Direct Message' &&
          dName != 'Conversation') {
        return dName.trim();
      }

      // 3. Check participant_details if present
      final pDetails = conv['participant_details'];
      if (pDetails is List && pDetails.isNotEmpty) {
        for (final p in pDetails) {
          if (p is Map) {
            final pid = (p['id'] ?? p['user_id'])?.toString();
            if (pid != null && pid.isNotEmpty && pid != currentUserId) {
              final name =
                  p['display_name']?.toString() ?? p['username']?.toString();
              if (name != null &&
                  name.trim().isNotEmpty &&
                  name != 'Direct Message' &&
                  name != 'Conversation') {
                return name.trim();
              }
            }
          }
        }
      }

      // 4. Check participants list in cache
      final participants = conv['participants'];
      if (participants is List && participants.isNotEmpty) {
        for (final p in participants) {
          String? pid;
          if (p is Map) {
            pid = (p['user_id'] ?? p['id'])?.toString();
          } else if (p != null) {
            pid = p.toString();
          }
          if (pid != null &&
              pid.isNotEmpty &&
              pid != currentUserId &&
              _userCache.containsKey(pid)) {
            final u = _userCache[pid];
            final name =
                u?['display_name']?.toString() ?? u?['username']?.toString();
            if (name != null &&
                name.isNotEmpty &&
                name != 'Direct Message' &&
                name != 'Conversation') return name;
          }
        }
      }

      // 5. Check target_id / recipient_id in cache
      final targetId =
          conv['target_id']?.toString() ?? conv['recipient_id']?.toString();
      if (targetId != null &&
          targetId != currentUserId &&
          _userCache.containsKey(targetId)) {
        final u = _userCache[targetId];
        final name =
            u?['display_name']?.toString() ?? u?['username']?.toString();
        if (name != null &&
            name.isNotEmpty &&
            name != 'Direct Message' &&
            name != 'Conversation') return name;
      }

      return 'Direct Message';
    }
  }

  String _resolveLastMessageSnippet(Map<String, dynamic> conv) {
    final lm = conv['last_message'];
    if (lm is Map) {
      final senderName = lm['sender_name'] ?? lm['sender_username'];
      final content = lm['content']?.toString() ?? 'Attachment';
      if (senderName != null &&
          senderName.toString().isNotEmpty &&
          senderName != 'Member') {
        return '$senderName: $content';
      }
      return content;
    }
    if (conv['last_message_content'] != null &&
        conv['last_message_content'].toString().isNotEmpty) {
      return conv['last_message_content'].toString();
    }
    if (conv['last_message_preview'] != null &&
        conv['last_message_preview'].toString().isNotEmpty) {
      return conv['last_message_preview'].toString();
    }
    return 'No messages yet';
  }

  DateTime _parseToIST(dynamic timestamp) {
    if (timestamp == null)
      return DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    if (timestamp is DateTime) {
      return timestamp.toUtc().add(const Duration(hours: 5, minutes: 30));
    }
    String str = timestamp.toString().trim();
    if (str.isEmpty)
      return DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    if (!str.endsWith('Z') &&
        !str.contains('+') &&
        !RegExp(r'T\d{2}:\d{2}:\d{2}.*-\d{2}').hasMatch(str)) {
      str = '${str}Z';
    }
    try {
      final parsedUtc = DateTime.parse(str).toUtc();
      return parsedUtc.add(const Duration(hours: 5, minutes: 30));
    } catch (_) {
      return DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    }
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';
    try {
      final dt = _parseToIST(timestamp);
      final now =
          DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final diff = now.difference(dt);

      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        if (diff.inMinutes < 1) return 'Just now';
        if (diff.inHours < 1) return '${diff.inMinutes}m ago';
        return DateFormat('h:mm a').format(dt);
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (dt.year == yesterday.year &&
          dt.month == yesterday.month &&
          dt.day == yesterday.day) {
        return 'Yesterday';
      }
      if (diff.inDays < 7) return DateFormat('E').format(dt);
      return DateFormat('dd/MM/yy').format(dt);
    } catch (_) {
      return '';
    }
  }

  Widget _buildSkeletonDashboard() {
    return SkeletonLoader(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User header skeleton
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderMuted),
              ),
              child: Row(
                children: [
                  const SkeletonCircle(radius: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 140, height: 18, borderRadius: 4),
                        SizedBox(height: 8),
                        SkeletonBox(width: 100, height: 12, borderRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Metrics Ribbon Skeleton (3 Cards)
            Row(
              children: const [
                Expanded(child: SkeletonDashboardCard()),
                SizedBox(width: 14),
                Expanded(child: SkeletonDashboardCard()),
                SizedBox(width: 14),
                Expanded(child: SkeletonDashboardCard()),
              ],
            ),
            const SizedBox(height: 24),
            // Recent Conversations & Activity Skeleton
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _borderMuted),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 160, height: 16, borderRadius: 4),
                        SizedBox(height: 16),
                        SkeletonConversationItem(),
                        SkeletonConversationItem(),
                        SkeletonConversationItem(),
                        SkeletonConversationItem(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _borderMuted),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 120, height: 16, borderRadius: 4),
                        SizedBox(height: 16),
                        SkeletonUserCard(),
                        SizedBox(height: 10),
                        SkeletonUserCard(),
                        SizedBox(height: 10),
                        SkeletonUserCard(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final currentUserId = authState.userId;
    ref.watch(presenceProvider);
    final presenceNotifier = ref.read(presenceProvider.notifier);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bgCream,
        appBar: const GlobalHeader(
          title: 'Dashboard',
          description: 'Workspace Activity & Community Hub',
          breadcrumbs: ['ConnectHub', 'Dashboard'],
        ),
        body: _buildSkeletonDashboard(),
      );
    }

    final onlineUsers = _allUsers.where((u) {
      final uId = u['id']?.toString();
      if (uId == null || uId == currentUserId) return false;
      return presenceNotifier.isOnline(uId);
    }).toList();

    final unreadCount = _conversations.fold<int>(
      0,
      (acc, c) =>
          acc +
          ((c['unread_count'] is num) ? (c['unread_count'] as num).toInt() : 0),
    );

    return Scaffold(
      backgroundColor: _bgCream,
      appBar: GlobalHeader(
        title: 'Dashboard',
        description: 'Workspace Activity & Community Hub',
        breadcrumbs: const ['ConnectHub', 'Dashboard'],
        primaryActionLabel: 'Start DM',
        primaryActionIcon: LucideIcons.message_square_plus,
        onPrimaryAction: _openNewChatDialog,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. CLEAN MINIMALIST USER HEADER ──
              _buildCleanHeader(authState),
              const SizedBox(height: 20),

              // ── 2. METRICS & ACTIVE TEAMMATES CARDS ──
              _buildStatsRibbon(onlineUsers, unreadCount),
              const SizedBox(height: 24),

              // ── 3. TWO-COLUMN SPLIT (Recent Conversations & Groups Hub) ──
              LayoutBuilder(
                builder: (context, constraints) {
                  final isSplit = constraints.maxWidth >= 900;
                  if (!isSplit) {
                    return Column(
                      children: [
                        _buildRecentConversationsCard(currentUserId),
                        const SizedBox(height: 24),
                        _buildGroupsCard(),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _buildRecentConversationsCard(currentUserId),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 4,
                        child: _buildGroupsCard(),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // ── 1. CLEAN MINIMALIST HEADER CARD
  // ──────────────────────────────────────────────

  Widget _buildCleanHeader(AuthState authState) {
    final name = authState.displayName;
    final username = authState.user?['username']?.toString() ??
        (authState.email.isNotEmpty
            ? authState.email.split('@').first
            : 'user');
    final email = authState.email;
    final isSuper = authState.isSuperAdmin;
    final isAdmin = authState.isAdmin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 740;

          final profileInfo = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Interactive Avatar with Status Dot ──
              Tooltip(
                message: 'Change status: ${_userStatus.toUpperCase()}',
                child: InkWell(
                  onTap: _openStatusDialog,
                  borderRadius: BorderRadius.circular(9999),
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _primaryTeal.withValues(alpha: 0.25),
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 27,
                          backgroundColor: _primaryTeal,
                          child: Text(
                            (name.isNotEmpty ? name[0] : 'U').toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: PulsingStatusDot(
                          color: _getStatusColor(),
                          size: 14,
                          isOnline: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),

              // ── User Information & Details ──
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: Name + Role Badge
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Role Pill Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSuper
                                ? const Color(0xFFFEF3C7)
                                : (isAdmin
                                    ? const Color(0xFFF3E8FF)
                                    : const Color(0xFFF0FDF4)),
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(
                              color: isSuper
                                  ? const Color(0xFFFCD34D)
                                  : (isAdmin
                                      ? const Color(0xFFD8B4FE)
                                      : const Color(0xFFBBF7D0)),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSuper
                                    ? LucideIcons.crown
                                    : (isAdmin
                                        ? LucideIcons.shield_check
                                        : LucideIcons.user),
                                size: 12,
                                color: isSuper
                                    ? const Color(0xFFB45309)
                                    : (isAdmin
                                        ? const Color(0xFF7E22CE)
                                        : const Color(0xFF15803D)),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isSuper
                                    ? 'Super Admin'
                                    : (isAdmin ? 'Admin' : 'Member'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSuper
                                      ? const Color(0xFFB45309)
                                      : (isAdmin
                                          ? const Color(0xFF7E22CE)
                                          : const Color(0xFF15803D)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Row 2: Username & Email & Interactive Status Pill
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          '@$username',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (email.isNotEmpty) ...[
                          const Text('•',
                              style: TextStyle(
                                  color: Color(0xFFCBD5E1), fontSize: 12)),
                          Text(
                            email,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const Text('•',
                            style: TextStyle(
                                color: Color(0xFFCBD5E1), fontSize: 12)),
                        // Status Pill with Edit prompt
                        InkWell(
                          onTap: _openStatusDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _userStatus.toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF475569),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(LucideIcons.chevron_down,
                                    size: 10, color: Color(0xFF94A3B8)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final actionButtons = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _openNewChatDialog,
                icon: const Icon(LucideIcons.message_square_plus, size: 15),
                label: const Text('Start DM'),
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryTeal,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _openCreateGroupDialog,
                icon: const Icon(LucideIcons.users,
                    size: 15, color: _primaryTeal),
                label: const Text('New Group',
                    style: TextStyle(
                        color: _textDark, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _cardWhite,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                profileInfo,
                const SizedBox(height: 16),
                actionButtons,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: profileInfo),
              const SizedBox(width: 16),
              actionButtons,
            ],
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // ── 2. STATS RIBBON & ACTIVE TEAMMATES
  // ──────────────────────────────────────────────

  Widget _buildStatsRibbon(
      List<Map<String, dynamic>> onlineUsers, int unreadCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 680;
        if (isMobile) {
          return Column(
            children: [
              _buildActiveTeammatesStatCard(onlineUsers),
              const SizedBox(height: 12),
              _buildCleanStatCard(
                icon: LucideIcons.message_square,
                iconColor: _primaryTeal,
                value: '${_conversations.length}',
                label:
                    unreadCount > 0 ? '$unreadCount Unread' : 'Conversations',
                badgeText: unreadCount > 0 ? '$unreadCount New' : null,
                onTap: () => context.go('/messages'),
              ),
              const SizedBox(height: 12),
              _buildCleanStatCard(
                icon: LucideIcons.users,
                iconColor: const Color(0xFF6366F1),
                value: '${_groups.length}',
                label: 'Active Groups',
                onTap: () => context.go('/groups'),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _buildActiveTeammatesStatCard(onlineUsers),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildCleanStatCard(
                icon: LucideIcons.message_square,
                iconColor: _primaryTeal,
                value: '${_conversations.length}',
                label:
                    unreadCount > 0 ? '$unreadCount Unread' : 'Conversations',
                badgeText: unreadCount > 0 ? '$unreadCount New' : null,
                onTap: () => context.go('/messages'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildCleanStatCard(
                icon: LucideIcons.users,
                iconColor: const Color(0xFF6366F1),
                value: '${_groups.length}',
                label: 'Active Groups',
                onTap: () => context.go('/groups'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActiveTeammatesStatCard(List<Map<String, dynamic>> onlineUsers) {
    return InkWell(
      onTap: onlineUsers.isEmpty
          ? null
          : () => _openAllOnlineTeammatesModal(onlineUsers),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: _cardWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _borderMuted, width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left UI Icon with Blinking Live Dot
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _onlineGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.activity,
                      color: _onlineGreen, size: 20),
                ),
                const Positioned(
                  top: -2,
                  right: -2,
                  child: _BlinkingOnlineDot(size: 8),
                ),
              ],
            ),
            const SizedBox(width: 14),

            // Right content
            Expanded(
              child: onlineUsers.isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '0 Online',
                              style: TextStyle(
                                color: _textDark,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: _onlineGreen.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                    color: _onlineGreen,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'No teammates online',
                          style: TextStyle(
                              color: _textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'ACTIVE TEAMMATES',
                              style: TextStyle(
                                color: _onlineGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                            Text(
                              '${onlineUsers.length} ONLINE',
                              style: const TextStyle(
                                color: _onlineGreen,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...onlineUsers.take(3).map((u) {
                                final uId = u['id']?.toString() ?? '';
                                final name = u['display_name'] ??
                                    u['username'] ??
                                    'User';
                                final firstName =
                                    name.toString().split(' ').first;

                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Tooltip(
                                    message: '$name (Online - Tap to chat)',
                                    child: InkWell(
                                      onTap: () =>
                                          _startDirectMessageWithUser(uId),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Logo (Avatar on top)
                                          Stack(
                                            children: [
                                              CircleAvatar(
                                                radius: 13,
                                                backgroundColor: _primaryTeal,
                                                child: Text(
                                                  (name.isNotEmpty
                                                          ? name[0]
                                                          : 'U')
                                                      .toUpperCase(),
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 9),
                                                ),
                                              ),
                                              Positioned(
                                                bottom: 0,
                                                right: 0,
                                                child: PulsingStatusDot(
                                                  color: ref
                                                      .read(presenceProvider
                                                          .notifier)
                                                      .getUserPresenceColor(
                                                          uId),
                                                  size: 7.5,
                                                  isOnline: true,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          // Name underneath
                                          SizedBox(
                                            width: 40,
                                            child: Text(
                                              firstName,
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: _textDark,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),

                              // Plus icon button to see all
                              Tooltip(
                                message: 'See all online teammates',
                                child: InkWell(
                                  onTap: () =>
                                      _openAllOnlineTeammatesModal(onlineUsers),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: _onlineGreen.withValues(
                                              alpha: 0.12),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: _onlineGreen.withValues(
                                                  alpha: 0.3)),
                                        ),
                                        child: const Icon(LucideIcons.plus,
                                            color: _onlineGreen, size: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        onlineUsers.length > 3
                                            ? '+${onlineUsers.length - 3}'
                                            : 'All',
                                        style: const TextStyle(
                                            color: _onlineGreen,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: _cardWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _borderMuted, width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                            color: _textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF43F5E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAllOnlineTeammatesModal(List<Map<String, dynamic>> onlineUsers) {
    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final q = searchCtrl.text.toLowerCase().trim();
          final filtered = onlineUsers.where((u) {
            final name = (u['display_name'] ?? '').toString().toLowerCase();
            final uname = (u['username'] ?? '').toString().toLowerCase();
            return name.contains(q) || uname.contains(q);
          }).toList();

          return AlertDialog(
            backgroundColor: _cardWhite,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: _borderMuted),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _onlineGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(LucideIcons.activity,
                          color: _onlineGreen, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Teammates',
                          style: TextStyle(
                            color: _textDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          '${onlineUsers.length} teammates online now',
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18, color: _textMuted),
                  onPressed: () => Navigator.pop(ctx),
                  style: IconButton.styleFrom(
                    backgroundColor: _bgCream,
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            content: SizedBox(
              width: 440,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setModalState(() {}),
                    style: const TextStyle(color: _textDark, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search active teammates...',
                      hintStyle:
                          const TextStyle(color: _textMuted, fontSize: 13),
                      prefixIcon: const Icon(LucideIcons.search,
                          color: _textMuted, size: 16),
                      filled: true,
                      fillColor: _bgCream,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _borderMuted),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _borderMuted),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: _primaryTeal, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No matching teammates online',
                              style: TextStyle(color: _textMuted, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: _borderMuted, height: 1),
                            itemBuilder: (ctx, i) {
                              final u = filtered[i];
                              final uId = u['id']?.toString() ?? '';
                              final name =
                                  u['display_name'] ?? u['username'] ?? 'User';
                              final username = u['username'] ?? '';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: _primaryTeal,
                                      child: Text(
                                        (name.isNotEmpty ? name[0] : 'U')
                                            .toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _onlineGreen,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                      color: _textDark,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                                subtitle: Text(
                                  '@$username',
                                  style: const TextStyle(
                                      color: _textMuted, fontSize: 11),
                                ),
                                trailing: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _startDirectMessageWithUser(uId);
                                  },
                                  icon: const Icon(LucideIcons.message_square,
                                      size: 13),
                                  label: const Text('Chat',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _tealLight,
                                    foregroundColor: _primaryTeal,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                          color: _primaryTeal.withValues(
                                              alpha: 0.2)),
                                    ),
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _startDirectMessageWithUser(uId);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // ── 4. RECENT CONVERSATIONS CARD (WhatsApp Style)
  // ──────────────────────────────────────────────

  Widget _buildRecentConversationsCard(String? currentUserId) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxRecent = screenWidth < 600 ? 2 : (screenWidth < 1000 ? 4 : 6);
    final convs = _conversations
        .where((c) => c['conversation_type'] != 'channel')
        .take(maxRecent)
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderMuted, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.message_square,
                      color: _primaryTeal, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Recent Conversations',
                    style: TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              InkWell(
                onTap: () => context.go('/messages?from=dashboard'),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    'View All →',
                    style: TextStyle(
                        color: _primaryTeal,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (convs.isEmpty)
            _buildEmptyCard(
                'No conversations yet. Start a direct message or join a group!')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: convs.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: _borderMuted, height: 1),
              itemBuilder: (context, idx) {
                final c = convs[idx];
                final cId = c['id']?.toString() ?? '';
                final title = _resolveConvTitle(c, currentUserId);
                final snippet = _resolveLastMessageSnippet(c);
                final unread = (c['unread_count'] is num)
                    ? (c['unread_count'] as num).toInt()
                    : 0;
                final timestamp =
                    _formatTimestamp(c['last_message_at'] ?? c['updated_at']);
                final type = c['conversation_type']?.toString() ?? 'direct';

                final targetId =
                    c['target_id']?.toString() ?? c['recipient_id']?.toString();
                final isOnline = (type == 'direct' && targetId != null)
                    ? ref.read(presenceProvider.notifier).isOnline(targetId)
                    : false;
                final presenceColor = targetId != null
                    ? ref
                        .read(presenceProvider.notifier)
                        .getUserPresenceColor(targetId)
                    : const Color(0xFF9CA3AF);

                return InkWell(
                  onTap: () => context.go('/messages?conv=$cId&from=dashboard'),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    child: Row(
                      children: [
                        // Avatar
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: type == 'group'
                                  ? const Color(0xFF3B82F6)
                                      .withValues(alpha: 0.15)
                                  : _primaryTeal,
                              child: Icon(
                                type == 'group'
                                    ? LucideIcons.users
                                    : LucideIcons.user,
                                color: type == 'group'
                                    ? const Color(0xFF2563EB)
                                    : Colors.white,
                                size: 18,
                              ),
                            ),
                            if (type != 'group')
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: PulsingStatusDot(
                                  color: presenceColor,
                                  size: 10,
                                  isOnline: isOnline,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 14),

                        // Title & Snippet
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _textDark,
                                        fontSize: 14,
                                        fontWeight: unread > 0
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (timestamp.isNotEmpty)
                                    Text(
                                      timestamp,
                                      style: TextStyle(
                                        color: unread > 0
                                            ? _primaryTeal
                                            : _textMuted,
                                        fontSize: 11,
                                        fontWeight: unread > 0
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      snippet,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            unread > 0 ? _textDark : _textMuted,
                                        fontSize: 12,
                                        fontWeight: unread > 0
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (unread > 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _primaryTeal,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        unread > 99 ? '99+' : '$unread',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // ── 5. GROUPS & SQUADS CARD
  // ──────────────────────────────────────────────

  Widget _buildGroupsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderMuted, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.users, color: Color(0xFF6366F1), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Groups & Squads',
                    style: TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              InkWell(
                onTap: () => context.go('/groups'),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    'Manage →',
                    style: TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_groups.isEmpty)
            _buildEmptyCard(
                'No groups created yet. Create a squad to start chatting!')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _groups.take(4).length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final grp = _groups[idx];
                final grpId = grp['id']?.toString() ?? '';
                final grpName = grp['name'] ?? 'Group';
                final grpDesc = grp['description'] ?? 'Team collaboration';
                final memberCount =
                    grp['member_count'] ?? grp['members_count'] ?? 1;

                return InkWell(
                  onTap: () {
                    final conv = _conversations.firstWhere(
                      (c) =>
                          c['name'] == grpName ||
                          c['target_id']?.toString() == grpId,
                      orElse: () => <String, dynamic>{},
                    );
                    if (conv.isNotEmpty && conv['id'] != null) {
                      context.go('/messages?conv=${conv['id']}');
                    } else {
                      context.go('/groups');
                    }
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _bgCream,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _borderMuted),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(LucideIcons.users,
                              color: Color(0xFF6366F1), size: 16),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                grpName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: _textDark,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                              Text(
                                grpDesc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _cardWhite,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _borderMuted),
                          ),
                          child: Text(
                            '👥 $memberCount',
                            style: const TextStyle(
                                color: _textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderMuted),
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: _textMuted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _BlinkingOnlineDot extends StatefulWidget {
  final double size;
  const _BlinkingOnlineDot({this.size = 8});

  @override
  State<_BlinkingOnlineDot> createState() => _BlinkingOnlineDotState();
}

class _BlinkingOnlineDotState extends State<_BlinkingOnlineDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacityAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnim.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color:
                  const Color(0xFF10B981).withValues(alpha: _opacityAnim.value),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981)
                      .withValues(alpha: _opacityAnim.value * 0.75),
                  blurRadius: 6,
                  spreadRadius: 1.5,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
