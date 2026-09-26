/// ConnectHub — Group List Screen with Creation Gating, Visibility & Settings Dialog.
///
/// Features compliant with channels.md:
/// - Only Super Admin / Admin can create Groups (channels.md 2.1)
/// - Create Group modal with Name, auto-slug, description, and Visibility (Private vs Org-wide) with tooltips (channels.md 2.2)
/// - Opens created group in existing messaging experience immediately (channels.md 2.2)
/// - Group cards show privacy indicator, member count, and settings access (channels.md 2.17)
/// - Opens Discord-inspired GroupSettingsDialog for full member, role, and permission management
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';
import '../../shared/widgets/global_header.dart';
import 'widgets/group_settings_dialog.dart';

class GroupListScreen extends ConsumerStatefulWidget {
  const GroupListScreen({super.key});

  @override
  ConsumerState<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends ConsumerState<GroupListScreen> {
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.get(ApiEndpoints.groups);
      final data = res.data;
      if (data is Map && data.containsKey('items')) {
        _groups = List<Map<String, dynamic>>.from(data['items']);
      } else if (data is List) {
        _groups = List<Map<String, dynamic>>.from(data);
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to load groups.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool _canCreateGroup() {
    final user = ref.read(authProvider).user;
    return user != null;
  }

  /// Open group chat directly in messaging screen
  Future<void> _openGroupChat(Map<String, dynamic> group) async {
    final groupId = group['id'].toString();
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.get(ApiEndpoints.conversations);
      final items = (res.data is Map && res.data.containsKey('items'))
          ? res.data['items'] as List
          : (res.data is List ? res.data : []);

      for (final conv in items) {
        if (conv['conversation_type'] == 'group' && conv['target_id'] == groupId) {
          if (mounted) context.go('/messages/${conv['id']}');
          return;
        }
      }

      // Create group conversation
      final createRes = await api.dio.post(
        ApiEndpoints.conversations,
        data: {
          'conversation_type': 'group',
          'target_id': groupId,
        },
      );
      final convId = createRes.data['id'].toString();
      if (mounted) context.go('/messages/$convId');
    } catch (_) {
      if (mounted) context.go('/messages');
    }
  }

  /// Create Group Dialog (channels.md 2.2)
  Future<void> _createGroup() async {
    final authState = ref.read(authProvider);
    final isSuper = authState.isSuperAdmin;
    final isAdmin = authState.isAdmin;
    final currentUserId = authState.userId;

    if (!isSuper && !isAdmin && currentUserId != null) {
      final ownedCount = _groups.where((g) => g['created_by']?.toString() == currentUserId).length;
      if (ownedCount >= 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFEF4444),
              content: Text('You are limited to a maximum of 2 groups. Please contact an administrator.'),
            ),
          );
        }
        return;
      }
    }

    final nameCtrl = TextEditingController();
    final slugCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String visibility = 'private';
    bool isViewOnly = false;
    bool isCreating = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.groups, color: Color(0xFF0F766E), size: 24),
                SizedBox(width: 10),
                Text(
                  'Create New Group',
                  style: TextStyle(color: Color(0xFF1C1917), fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Color(0xFF1C1917)),
                      decoration: InputDecoration(
                        labelText: 'Group Name *',
                        labelStyle: const TextStyle(color: Color(0xFF4B5563)),
                        hintText: 'e.g. Design Team, Product Launch',
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5)),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          slugCtrl.text = val
                              .toLowerCase()
                              .replaceAll(RegExp(r'[^a-z0-9]'), '-')
                              .replaceAll(RegExp(r'-+'), '-')
                              .replaceAll(RegExp(r'^-|-$'), '');
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: slugCtrl,
                      style: const TextStyle(color: Color(0xFF1C1917)),
                      decoration: InputDecoration(
                        labelText: 'Group Slug *',
                        labelStyle: const TextStyle(color: Color(0xFF4B5563)),
                        hintText: 'unique-url-identifier',
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      style: const TextStyle(color: Color(0xFF1C1917)),
                      decoration: InputDecoration(
                        labelText: 'Description (Optional)',
                        labelStyle: const TextStyle(color: Color(0xFF4B5563)),
                        hintText: 'What is the purpose of this group?',
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5)),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    const Text('Visibility (channels.md 2.2)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1C1917))),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                            activeColor: const Color(0xFF0F766E),
                            value: 'private',
                            groupValue: visibility,
                            onChanged: (v) => setDialogState(() => visibility = v!),
                            title: const Row(
                              children: [
                                Text('Private 🔒', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1917))),
                                SizedBox(width: 6),
                                Tooltip(
                                  message: 'Only users explicitly added to this Group can access it.',
                                  child: Icon(Icons.info_outline, size: 14, color: Color(0xFF78716C)),
                                ),
                              ],
                            ),
                            subtitle: const Text('Only invited/added members can access the Group.', style: TextStyle(fontSize: 11, color: Color(0xFF78716C))),
                          ),
                          const Divider(height: 1, color: Color(0xFFE5E7EB)),
                          RadioListTile<String>(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                            activeColor: const Color(0xFF0F766E),
                            value: 'organization',
                            groupValue: visibility,
                            onChanged: (v) => setDialogState(() => visibility = v!),
                            title: const Row(
                              children: [
                                Text('Organization-wide 🌐', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1917))),
                                SizedBox(width: 6),
                                Tooltip(
                                  message: 'The Group can be available to users across the organization according to its access configuration.',
                                  child: Icon(Icons.info_outline, size: 14, color: Color(0xFF78716C)),
                                ),
                              ],
                            ),
                            subtitle: const Text('Available to all users in the organization.', style: TextStyle(fontSize: 11, color: Color(0xFF78716C))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isViewOnly ? const Color(0xFFF0FDF4) : const Color(0xFFF9FAFB),
                        border: Border.all(
                          color: isViewOnly ? const Color(0xFF0F766E).withValues(alpha: 0.4) : const Color(0xFFE5E7EB),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isViewOnly,
                        activeColor: const Color(0xFF0F766E),
                        title: const Row(
                          children: [
                            Text(
                              'View-Only Group by Default 👁️',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1C1917)),
                            ),
                          ],
                        ),
                        subtitle: const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'All members can only view messages by default. Only the group creator and members with elevated roles can post.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF78716C)),
                          ),
                        ),
                        onChanged: (v) => setDialogState(() => isViewOnly = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isCreating ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF78716C))),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
                onPressed: (nameCtrl.text.trim().isEmpty || isCreating)
                    ? null
                    : () async {
                        setDialogState(() => isCreating = true);
                        try {
                          final api = ref.read(apiClientProvider);
                          final res = await api.dio.post(
                            ApiEndpoints.groups,
                            data: {
                              'name': nameCtrl.text.trim(),
                              'slug': slugCtrl.text.trim().isNotEmpty
                                  ? slugCtrl.text.trim()
                                  : nameCtrl.text.trim().toLowerCase().replaceAll(' ', '-'),
                              'description': descCtrl.text.trim(),
                              'visibility': visibility,
                              'is_private': visibility == 'private',
                              'is_view_only': isViewOnly,
                            },
                          );

                          final createdGroup = Map<String, dynamic>.from(res.data);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadData();

                          // Automatically open the newly created group chat (channels.md 2.2)
                          _openGroupChat(createdGroup);
                        } catch (e) {
                          setDialogState(() => isCreating = false);
                          String errorMsg = 'Failed to create group.';
                          if (e is DioException && e.response?.data is Map) {
                            errorMsg = e.response?.data['message']?.toString() ?? e.response?.data['detail']?.toString() ?? errorMsg;
                          }
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(errorMsg), backgroundColor: Colors.red.shade700),
                            );
                          }
                        }
                      },
                child: isCreating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Group'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openSettings(Map<String, dynamic> group) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GroupSettingsDialog(
        group: group,
        onGroupUpdated: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _canCreateGroup();

    return Scaffold(
      appBar: GlobalHeader(
        title: 'Groups',
        description: 'Collaborative Workspaces, Custom Roles & Permissions',
        breadcrumbs: const ['ConnectHub', 'Groups'],
        primaryActionLabel: canCreate ? 'Create Group' : null,
        primaryActionIcon: canCreate ? LucideIcons.plus : null,
        onPrimaryAction: canCreate ? _createGroup : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Color(0xFF78716C))),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: _loadData, child: const Text('Retry')),
                    ],
                  ),
                )
              : _groups.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.groups, size: 48, color: Color(0xFFCBD5E1)),
                          const SizedBox(height: 12),
                          const Text('No groups found', style: TextStyle(color: Color(0xFF78716C), fontSize: 16)),
                          const SizedBox(height: 16),
                          if (canCreate)
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
                              onPressed: _createGroup,
                              child: const Text('Create First Group'),
                            ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _groups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final group = _groups[index];
                        final isPrivate = group['is_private'] == true || group['visibility'] == 'private';
                        final memberCount = group['member_count'] ?? (group['members'] is List ? (group['members'] as List).length : 0);

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1C1917).withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isCompact = constraints.maxWidth < 550;
                                final actions = [
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F766E),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => _openGroupChat(group),
                                    icon: const Icon(LucideIcons.message_square, size: 16),
                                    label: const Text('Open Chat'),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(LucideIcons.settings, size: 18, color: Color(0xFF78716C)),
                                    onPressed: () => _openSettings(group),
                                    tooltip: 'Group Settings & Roles',
                                  ),
                                ];

                                if (isCompact) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            radius: 22,
                                            backgroundColor: const Color(0xFFEEF2FF),
                                            child: Icon(
                                              isPrivate ? LucideIcons.lock : LucideIcons.users,
                                              color: isPrivate ? const Color(0xFFD97706) : const Color(0xFF4F46E5),
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  children: [
                                                    Text(
                                                      group['name']?.toString() ?? '',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1C1917)),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: isPrivate ? const Color(0xFFFEF3C7) : const Color(0xFFCCFBF1),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: isPrivate ? const Color(0xFFFDE68A) : const Color(0xFF99F6E4)),
                                                      ),
                                                      child: Text(
                                                        isPrivate ? 'Private 🔒' : 'Org-Wide 🌐',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                          color: isPrivate ? const Color(0xFFD97706) : const Color(0xFF0F766E),
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      '• $memberCount ${memberCount == 1 ? "member" : "members"}',
                                                      style: const TextStyle(fontSize: 12, color: Color(0xFF78716C)),
                                                    ),
                                                  ],
                                                ),
                                                if (group['description'] != null && group['description'].toString().isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    group['description'].toString(),
                                                    style: const TextStyle(color: Color(0xFF78716C), fontSize: 13),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: actions,
                                      ),
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: const Color(0xFFEEF2FF),
                                      child: Icon(
                                        isPrivate ? LucideIcons.lock : LucideIcons.users,
                                        color: isPrivate ? const Color(0xFFD97706) : const Color(0xFF4F46E5),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                group['name']?.toString() ?? '',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1C1917)),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isPrivate ? const Color(0xFFFEF3C7) : const Color(0xFFCCFBF1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: isPrivate ? const Color(0xFFFDE68A) : const Color(0xFF99F6E4)),
                                                ),
                                                child: Text(
                                                  isPrivate ? 'Private 🔒' : 'Org-Wide 🌐',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isPrivate ? const Color(0xFFD97706) : const Color(0xFF0F766E),
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '• $memberCount ${memberCount == 1 ? "member" : "members"}',
                                                style: const TextStyle(fontSize: 12, color: Color(0xFF78716C)),
                                              ),
                                            ],
                                          ),
                                          if (group['description'] != null && group['description'].toString().isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              group['description'].toString(),
                                              style: const TextStyle(color: Color(0xFF78716C), fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    ...actions,
                                  ],
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
