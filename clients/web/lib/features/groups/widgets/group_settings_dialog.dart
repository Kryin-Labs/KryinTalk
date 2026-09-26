/// ConnectHub — Discord-Inspired Group Settings & Roles Management Modal.
///
/// Features compliant with channels.md:
/// - Sidebar tabs: General, Members, Roles & Permissions, Notifications, Danger Zone
/// - Discord-inspired 2-column Roles layout: Role list on left (hierarchy ordered with badges & reorder), Role editor on right
/// - Categorized permissions: MESSAGES, MEMBERS, ROLES, GROUP, MENTIONS
/// - Plain-English `ⓘ` tooltips for every single permission
/// - `🔒` Lock indicators for permissions the current user cannot grant (Permission Ceiling)
/// - Group Owner protection (cannot be modified, demoted, removed, or deleted)
/// - Single Default Role toggle
/// - Safe role deletion with fallback member reassignment
/// - Unsaved changes bottom floating bar
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';

class GroupSettingsDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> group;
  final VoidCallback onGroupUpdated;

  const GroupSettingsDialog({
    super.key,
    required this.group,
    required this.onGroupUpdated,
  });

  @override
  ConsumerState<GroupSettingsDialog> createState() => _GroupSettingsDialogState();
}

class _GroupSettingsDialogState extends ConsumerState<GroupSettingsDialog> {
  int _selectedTab = 0; // 0: General, 1: Members, 2: Roles, 3: Notifications, 4: Danger Zone
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  String? _error;

  // Group Details
  late Map<String, dynamic> _groupData;
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late String _selectedVisibility;
  late String _selectedColor;
  late String _selectedIcon;
  bool _onlyAdminInvites = true;

  // Members
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _allDirectoryUsers = [];
  String _memberSearchQuery = '';

  // Roles
  List<Map<String, dynamic>> _roles = [];
  Map<String, dynamic>? _selectedRole;
  late TextEditingController _roleNameController;
  late TextEditingController _roleDescController;
  late String _roleColor;
  late bool _roleIsDefault;
  Map<String, bool> _rolePermissions = {};

  // Current user's effective role permissions in this group
  Map<String, dynamic>? _currentUserRole;
  bool _isCurrentUserOwner = false;

  final List<String> _colorPresets = [
    '#6366F1', // Indigo
    '#8B5CF6', // Purple
    '#EC4899', // Pink
    '#EF4444', // Red
    '#F59E0B', // Amber
    '#10B981', // Emerald
    '#06B6D4', // Cyan
    '#3B82F6', // Blue
    '#64748B', // Slate
  ];

  final Map<String, List<Map<String, String>>> _permissionCategories = {
    'MESSAGES': [
      {'key': 'view_messages', 'label': 'View Messages', 'desc': 'Allows members with this role to view messages in the Group.'},
      {'key': 'send_messages', 'label': 'Send Messages', 'desc': 'Allows members with this role to send new messages.'},
      {'key': 'edit_own_messages', 'label': 'Edit Own Messages', 'desc': 'Allows members to edit their own sent messages.'},
      {'key': 'edit_other_messages', 'label': 'Edit Other Members\' Messages', 'desc': 'Allows members to edit messages sent by other members.'},
      {'key': 'delete_own_messages', 'label': 'Delete Own Messages', 'desc': 'Allows members to delete their own messages.'},
      {'key': 'delete_other_messages', 'label': 'Delete Other Members\' Messages', 'desc': 'Allows members to delete messages sent by other members.'},
      {'key': 'reply_messages', 'label': 'Reply to Messages', 'desc': 'Allows members to quote and reply to messages.'},
      {'key': 'add_reactions', 'label': 'Add Reactions', 'desc': 'Allows members to react to messages with emojis.'},
      {'key': 'remove_reactions', 'label': 'Remove Reactions', 'desc': 'Allows members to remove emoji reactions.'},
      {'key': 'pin_messages', 'label': 'Pin Messages', 'desc': 'Allows members to pin important messages in the Group.'},
      {'key': 'unpin_messages', 'label': 'Unpin Messages', 'desc': 'Allows members to unpin pinned messages.'},
      {'key': 'send_links', 'label': 'Send Links', 'desc': 'Allows members to post web links and URLs in messages.'},
      {'key': 'send_attachments', 'label': 'Send Attachments', 'desc': 'Allows members to upload and send attachments.'},
      {'key': 'send_images', 'label': 'Send Images', 'desc': 'Allows members to upload and send images/photos.'},
      {'key': 'send_files', 'label': 'Send Files', 'desc': 'Allows members to upload document files.'},
    ],
    'MEMBERS': [
      {'key': 'view_members', 'label': 'View Members', 'desc': 'Allows members to see the full list of Group members.'},
      {'key': 'add_members', 'label': 'Add Members', 'desc': 'Allows members to invite and add new users to the Group.'},
      {'key': 'remove_members', 'label': 'Remove Members', 'desc': 'Allows members to remove users below their hierarchy rank.'},
      {'key': 'manage_members', 'label': 'Manage Members', 'desc': 'Full member management capabilities within the Group.'},
      {'key': 'view_member_profiles', 'label': 'View Member Profiles', 'desc': 'Allows viewing profiles of other Group members.'},
    ],
    'ROLES': [
      {'key': 'view_roles', 'label': 'View Roles', 'desc': 'Allows members to view Group roles and hierarchy structure.'},
      {'key': 'create_roles', 'label': 'Create Roles', 'desc': 'Allows creating new custom roles below the user\'s rank.'},
      {'key': 'edit_roles', 'label': 'Edit Roles', 'desc': 'Allows editing custom roles strictly below the user\'s rank.'},
      {'key': 'delete_roles', 'label': 'Delete Roles', 'desc': 'Allows deleting custom roles strictly below the user\'s rank.'},
      {'key': 'assign_roles', 'label': 'Assign Roles', 'desc': 'Allows assigning roles below the user\'s rank to other members.'},
      {'key': 'manage_role_hierarchy', 'label': 'Manage Role Hierarchy', 'desc': 'Allows reordering roles below the user\'s authority level.'},
      {'key': 'manage_role_permissions', 'label': 'Manage Role Permissions', 'desc': 'Allows modifying permission flags on assignable roles.'},
    ],
    'GROUP': [
      {'key': 'view_group', 'label': 'View Group', 'desc': 'Allows members to access the Group workspace.'},
      {'key': 'edit_group_name', 'label': 'Edit Group Name', 'desc': 'Allows changing the Group title.'},
      {'key': 'edit_group_description', 'label': 'Edit Group Description', 'desc': 'Allows editing the Group description text.'},
      {'key': 'change_group_icon', 'label': 'Change Group Icon', 'desc': 'Allows changing the Group avatar icon.'},
      {'key': 'change_group_visibility', 'label': 'Change Group Visibility', 'desc': 'Allows toggling between Private and Organization-wide.'},
      {'key': 'manage_group_settings', 'label': 'Manage Group Settings', 'desc': 'Allows full access to configure Group settings.'},
      {'key': 'delete_group', 'label': 'Delete Group', 'desc': 'Allows permanently deleting the Group workspace.'},
    ],
    'MENTIONS': [
      {'key': 'mention_users', 'label': 'Mention Users', 'desc': 'Allows mentioning individual users with @username.'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _groupData = Map<String, dynamic>.from(widget.group);
    _nameController = TextEditingController(text: _groupData['name']?.toString() ?? '');
    _descController = TextEditingController(text: _groupData['description']?.toString() ?? '');
    _selectedVisibility = _groupData['visibility']?.toString() ?? (_groupData['is_private'] == true ? 'private' : 'organization');
    _selectedColor = _groupData['color']?.toString() ?? '#6366F1';
    _selectedIcon = _groupData['icon']?.toString() ?? 'group';
    _onlyAdminInvites = _groupData['only_admin_invites'] ?? true;

    _roleNameController = TextEditingController();
    _roleDescController = TextEditingController();
    _roleColor = '#64748B';
    _roleIsDefault = false;

    _loadInitialData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _roleNameController.dispose();
    _roleDescController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final groupId = _groupData['id'].toString();

      // 1. Fetch group detail & current user's role
      final gRes = await api.dio.get('${ApiEndpoints.groups}/$groupId');
      _groupData = Map<String, dynamic>.from(gRes.data);
      _onlyAdminInvites = _groupData['only_admin_invites'] ?? true;
      _currentUserRole = _groupData['current_user_role'];
      _isCurrentUserOwner = _currentUserRole?['hierarchy_rank'] == 0 || _groupData['created_by'] == ref.read(authProvider).userId;

      // 2. Fetch roles
      final rolesRes = await api.dio.get(ApiEndpoints.groupRoles(groupId));
      _roles = List<Map<String, dynamic>>.from(rolesRes.data is List ? rolesRes.data : []);

      if (_roles.isNotEmpty) {
        _selectRole(_roles.first);
      }

      // 3. Fetch members
      try {
        final membersRes = await api.dio.get(ApiEndpoints.groupMembers(groupId));
        final mData = membersRes.data;
        if (mData is Map && mData.containsKey('items')) {
          _members = List<Map<String, dynamic>>.from(mData['items']);
        } else if (mData is List) {
          _members = List<Map<String, dynamic>>.from(mData);
        }
      } catch (_) {}

      // 4. Fetch directory users for add-member picker
      try {
        final uRes = await api.dio.get(ApiEndpoints.directory);
        final uList = uRes.data is List ? uRes.data : (uRes.data is Map && uRes.data.containsKey('items') ? uRes.data['items'] : []);
        _allDirectoryUsers = List<Map<String, dynamic>>.from(uList);
      } catch (_) {}

      _error = null;
    } catch (e) {
      _error = 'Failed to load group settings.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _selectRole(Map<String, dynamic> role) {
    setState(() {
      _selectedRole = role;
      _roleNameController.text = role['name']?.toString() ?? '';
      _roleDescController.text = role['description']?.toString() ?? '';
      _roleColor = role['color']?.toString() ?? '#64748B';
      _roleIsDefault = role['is_default'] == true;

      final rawPerms = role['permissions'];
      _rolePermissions = {};
      if (rawPerms is Map) {
        rawPerms.forEach((k, v) => _rolePermissions[k.toString()] = v == true);
      }
      _hasUnsavedChanges = false;
    });
  }

  bool _canManageRole(Map<String, dynamic> role) {
    if (_isCurrentUserOwner) return true;
    if (role['hierarchy_rank'] == 0 || role['name'] == 'Group Owner') return false;
    final myRank = _currentUserRole?['hierarchy_rank'] ?? 1000;
    final targetRank = role['hierarchy_rank'] ?? 1000;
    return myRank < targetRank;
  }

  bool _canGrantPermission(String permKey) {
    if (_isCurrentUserOwner) return true;
    final myPerms = _currentUserRole?['permissions'];
    if (myPerms is Map) {
      return myPerms[permKey] == true;
    }
    return false;
  }

  // ── General Save ──────────────────────────

  Future<void> _saveGeneralSettings() async {
    setState(() => _isSaving = true);
    try {
      final api = ref.read(apiClientProvider);
      final groupId = _groupData['id'].toString();

      await api.dio.put(
        '${ApiEndpoints.groups}/$groupId',
        data: {
          'name': _nameController.text.trim(),
          'description': _descController.text.trim(),
          'visibility': _selectedVisibility,
          'color': _selectedColor,
          'icon': _selectedIcon,
          'is_private': _selectedVisibility == 'private',
          'only_admin_invites': _onlyAdminInvites,
        },
      );

      _groupData['name'] = _nameController.text.trim();
      _groupData['description'] = _descController.text.trim();
      _groupData['visibility'] = _selectedVisibility;
      _groupData['color'] = _selectedColor;
      _groupData['only_admin_invites'] = _onlyAdminInvites;

      widget.onGroupUpdated();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('General settings saved successfully!')),
        );
        setState(() {
          _hasUnsavedChanges = false;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save general settings.')),
        );
      }
    }
  }

  // ── Role Save & Create ────────────────────

  Future<void> _saveRoleChanges() async {
    if (_selectedRole == null) return;
    setState(() => _isSaving = true);
    try {
      final api = ref.read(apiClientProvider);
      final groupId = _groupData['id'].toString();
      final roleId = _selectedRole!['id'].toString();

      final res = await api.dio.put(
        ApiEndpoints.groupRole(groupId, roleId),
        data: {
          'name': _roleNameController.text.trim(),
          'description': _roleDescController.text.trim(),
          'color': _roleColor,
          'is_default': _roleIsDefault,
          'permissions': _rolePermissions,
        },
      );

      final updatedRole = Map<String, dynamic>.from(res.data);
      final idx = _roles.indexWhere((r) => r['id'].toString() == roleId);
      if (idx != -1) {
        _roles[idx] = updatedRole;
      }
      if (_roleIsDefault) {
        for (var r in _roles) {
          if (r['id'].toString() != roleId) {
            r['is_default'] = false;
          }
        }
      }
      _selectedRole = updatedRole;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role "${updatedRole['name']}" updated successfully!')),
        );
        setState(() {
          _hasUnsavedChanges = false;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update role.')),
        );
      }
    }
  }

  Future<void> _createRoleDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String color = '#0F766E';
    bool isDefault = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          title: const Text('Create Custom Role', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Role Name (e.g. Moderator, Editor, Support)',
                    labelStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    labelStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Role Color', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _colorPresets.map((hex) {
                    final c = _parseHexColor(hex);
                    final isSel = color == hex;
                    return GestureDetector(
                      onTap: () => setDState(() => color = hex),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSel ? const Color(0xFF0F172A) : Colors.transparent, width: 2),
                        ),
                        child: isSel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Make Default Role', style: TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('New members automatically receive this role', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  activeTrackColor: const Color(0xFF0F766E),
                  value: isDefault,
                  onChanged: (v) {
                    if (v == true) {
                      final existingDefault = _roles.firstWhere(
                        (r) => r['is_default'] == true,
                        orElse: () => {},
                      );
                      if (existingDefault.isNotEmpty) {
                        final existingName = existingDefault['name'] ?? 'another role';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFFDC2626),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            content: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "In this group, '$existingName' is set as default. Disable it first.",
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                        return;
                      }
                    }
                    setDState(() => isDefault = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create Role'),
            ),
          ],
        ),
      ),
    );

    if (created == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        final api = ref.read(apiClientProvider);
        final groupId = _groupData['id'].toString();

        final res = await api.dio.post(
          ApiEndpoints.groupRoles(groupId),
          data: {
            'name': nameCtrl.text.trim(),
            'description': descCtrl.text.trim(),
            'color': color,
            'is_default': isDefault,
          },
        );

        final newRole = Map<String, dynamic>.from(res.data);
        _roles.add(newRole);
        _roles.sort((a, b) => (a['hierarchy_rank'] as int).compareTo(b['hierarchy_rank'] as int));
        _selectRole(newRole);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Created role "${newRole['name']}"!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create role.')),
          );
        }
      }
    }
  }

  Future<void> _deleteRoleDialog(Map<String, dynamic> role) async {
    final isSystemRole = role['is_system'] == true ||
        role['hierarchy_rank'] == 0 ||
        ['Group Owner', 'Group Admin', 'Group Member', 'Group Viewer'].contains(role['name']);

    if (isSystemRole) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${role['name']}" is a built-in system role and cannot be deleted.')),
        );
      }
      return;
    }

    final fallbackCandidates = _roles.where((r) => r['id'] != role['id'] && r['hierarchy_rank'] != 0).toList();
    String? fallbackRoleId = fallbackCandidates.firstWhere(
      (r) => r['is_default'] == true,
      orElse: () => fallbackCandidates.isNotEmpty ? fallbackCandidates.first : <String, dynamic>{},
    )['id']?.toString();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          title: Text('Delete Role: ${role['name']}?', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Members currently assigned to this role will lose this role. Choose what should happen to those members:',
                  style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: fallbackRoleId,
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Move members to:',
                    labelStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                    ),
                  ),
                  items: fallbackCandidates.map((r) {
                    return DropdownMenuItem<String>(
                      value: r['id'].toString(),
                      child: Text('${r['name']}${r['is_default'] == true ? ' (Default)' : ''}', style: const TextStyle(color: Color(0xFF0F172A))),
                    );
                  }).toList(),
                  onChanged: (v) => setDState(() => fallbackRoleId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete Role'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        final api = ref.read(apiClientProvider);
        final groupId = _groupData['id'].toString();
        final roleId = role['id'].toString();

        await api.dio.delete(
          ApiEndpoints.groupRole(groupId, roleId),
          queryParameters: fallbackRoleId != null ? {'fallback_role_id': fallbackRoleId} : null,
        );

        _roles.removeWhere((r) => r['id'].toString() == roleId);
        if (_roles.isNotEmpty) {
          _selectRole(_roles.first);
        } else {
          setState(() => _selectedRole = null);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Role "${role['name']}" deleted.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete role.')),
          );
        }
      }
    }
  }

  // ── Member Role Change ────────────────────

  Future<void> _changeMemberRole(Map<String, dynamic> member, String newRoleId) async {
    try {
      final api = ref.read(apiClientProvider);
      final groupId = _groupData['id'].toString();
      final userId = member['user_id'].toString();

      final res = await api.dio.put(
        ApiEndpoints.groupMemberRole(groupId, userId),
        data: {'role_id': newRoleId},
      );

      final updated = Map<String, dynamic>.from(res.data);
      setState(() {
        final idx = _members.indexWhere((m) => m['user_id'].toString() == userId);
        if (idx != -1) {
          _members[idx] = updated;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated role for @${member['username']}!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to assign role to member.')),
        );
      }
    }
  }

  Future<void> _removeMemberDialog(Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        title: Text('Remove @${member['username']} from Group?', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        content: const Text('They will lose access to this group and its messages.', style: TextStyle(color: Color(0xFF475569))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final api = ref.read(apiClientProvider);
        final groupId = _groupData['id'].toString();
        final userId = member['user_id'].toString();

        await api.dio.delete(ApiEndpoints.groupMember(groupId, userId));

        setState(() {
          _members.removeWhere((m) => m['user_id'].toString() == userId);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed @${member['username']} from group.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to remove member.')),
          );
        }
      }
    }
  }



  Future<void> _openInviteModal() async {
    final groupId = _groupData['id'].toString();
    final api = ref.read(apiClientProvider);
    String? inviteToken;
    String? inviteUrl;
    int expiresHours = 24;
    int maxUses = 1;
    bool isGenerating = false;
    String? generateError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCCFBF1)),
                  ),
                  child: const Icon(Icons.link, color: Color(0xFF0F766E), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Group Invite Link',
                    style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFD97706)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$maxUses ${maxUses == 1 ? 'join' : 'joins'} • Expires in $expiresHours hour${expiresHours == 1 ? '' : 's'}',
                            style: const TextStyle(color: Color(0xFFB45309), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Choose when this link expires and how many people may join. People see the group and inviter before joining.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: expiresHours,
                          decoration: const InputDecoration(labelText: 'Expires after'),
                          items: const [1, 24, 72, 168, 720].map((hours) => DropdownMenuItem(value: hours, child: Text(hours == 1 ? '1 hour' : '$hours hours'))).toList(),
                          onChanged: isGenerating ? null : (value) => setDState(() => expiresHours = value ?? 24),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: '$maxUses',
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Join limit (1–10,000)'),
                          onChanged: (value) {
                            final parsed = int.tryParse(value);
                            if (parsed != null && parsed >= 1 && parsed <= 10000) {
                              setDState(() => maxUses = parsed);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isGenerating)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFF0F766E))))
                  else if (generateError != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Text(generateError!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                    )
                  else if (inviteUrl != null) ...[
                    TextField(
                      controller: TextEditingController(text: inviteUrl ?? inviteToken ?? ''),
                      readOnly: true,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        labelText: 'Invite Link',
                        labelStyle: const TextStyle(color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.copy, size: 18, color: Color(0xFF0F766E)),
                          tooltip: 'Copy to Clipboard',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: inviteUrl ?? inviteToken ?? ''));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Invite link copied to clipboard.')),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.link, size: 16),
                label: Text(inviteUrl == null ? 'Generate Link' : 'Regenerate'),
                onPressed: isGenerating ? null : () async {
                  setDState(() {
                    isGenerating = true;
                    generateError = null;
                  });
                  try {
                    final res = await api.dio.post(
                      ApiEndpoints.groupInvites(groupId),
                      data: {'expires_hours': expiresHours, 'max_uses': maxUses},
                    );
                    final token = res.data?['token']?.toString() ?? '';
                    if (token.isEmpty) throw StateError('The server returned no invite token.');
                    setDState(() {
                      inviteToken = token;
                      inviteUrl = '${Uri.base.origin}/#/join/$token';
                      isGenerating = false;
                    });
                  } catch (_) {
                    setDState(() {
                      generateError = 'Failed to generate invite link. Only group admins can invite.';
                      isGenerating = false;
                    });
                  }
                },
              ),
              if (inviteUrl != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Invite Link'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: inviteUrl!));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite link copied to clipboard.')),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addMembersDialog() async {
    final existingUserIds = _members.map((m) => m['user_id']?.toString() ?? m['id']?.toString()).toSet();
    final availableUsers = _allDirectoryUsers.where((u) => !existingUserIds.contains(u['id']?.toString())).toList();
    final selectedIds = <String>{};
    String? initialRoleId = _roles.firstWhere(
      (r) => r['is_default'] == true,
      orElse: () => _roles.isNotEmpty ? _roles.last : <String, dynamic>{},
    )['id']?.toString();

    final searchCtrl = TextEditingController();
    String searchQuery = '';
    final Set<String> invitedUsernames = {};
    bool isSendingDirectInvite = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          final q = searchQuery.trim().toLowerCase();
          final cleanQuery = q.startsWith('@') ? q.substring(1) : q;

          // Filter available directory users
          final filteredUsers = availableUsers.where((u) {
            if (cleanQuery.isEmpty) return true;
            final dName = (u['display_name'] ?? '').toString().toLowerCase();
            final uName = (u['username'] ?? '').toString().toLowerCase();
            final email = (u['email'] ?? '').toString().toLowerCase();
            return dName.contains(cleanQuery) || uName.contains(cleanQuery) || email.contains(cleanQuery);
          }).toList();

          final isSearchingExact = q.isNotEmpty;
          final isNotFound = isSearchingExact && filteredUsers.isEmpty;

          Future<void> sendDirectInvite(String targetHandle, [String? targetUserId]) async {
            setDState(() => isSendingDirectInvite = true);
            try {
              final api = ref.read(apiClientProvider);
              final groupId = _groupData['id'].toString();
              await api.dio.post(
                '${ApiEndpoints.groups}/$groupId/invite-user',
                data: {
                  if (targetUserId != null) 'user_id': targetUserId,
                  'username': targetHandle.startsWith('@') ? targetHandle : '@$targetHandle',
                  'role_id': initialRoleId,
                },
              );
              setDState(() {
                invitedUsernames.add(targetHandle.toLowerCase().replaceAll('@', ''));
                isSendingDirectInvite = false;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Invitation sent to $targetHandle! They will receive a notification.')),
                );
              }
            } catch (e) {
              setDState(() => isSendingDirectInvite = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to invite $targetHandle. User may not exist or cannot be invited.')),
                );
              }
            }
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCCFBF1)),
                  ),
                  child: const Icon(Icons.person_add_alt_1, color: Color(0xFF0F766E), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Add & Invite Members', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 17)),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_roles.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: initialRoleId,
                      dropdownColor: Colors.white,
                      style: const TextStyle(color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        labelText: 'Assign Role:',
                        labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        isDense: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                        ),
                      ),
                      items: _roles.where((r) => r['hierarchy_rank'] != 0).map((r) {
                        final isViewer = r['name'] == 'Group Viewer';
                        return DropdownMenuItem<String>(
                          value: r['id'].toString(),
                          child: Text(
                            '${r['name']}${r['is_default'] == true ? ' (Default)' : ''}${isViewer ? ' (View-Only)' : ''}',
                            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setDState(() => initialRoleId = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Search & @ Autocomplete Field
                  TextField(
                    controller: searchCtrl,
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Search user or type @username',
                      hintText: 'e.g. @bob or Alice...',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                      prefixIcon: const Icon(Icons.alternate_email, size: 18, color: Color(0xFF0F766E)),
                      suffixIcon: searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                searchCtrl.clear();
                                setDState(() => searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      isDense: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5)),
                    ),
                    onChanged: (v) => setDState(() => searchQuery = v),
                  ),
                  const SizedBox(height: 12),

                  // Not found banner if exact handle is missing
                  if (isNotFound) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFFEF4444), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'User "$searchQuery" not found or not available in your organization.',
                              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // User List with Checkbox & Direct Invite Button
                  const Text('Select or Invite Users:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 220,
                    child: filteredUsers.isEmpty && !isNotFound
                        ? const Center(child: Text('All organization users are already in this group.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)))
                        : ListView.separated(
                            itemCount: filteredUsers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (ctx, i) {
                              final u = filteredUsers[i];
                              final uid = u['id'].toString();
                              final isSel = selectedIds.contains(uid);
                              final dName = (u['display_name'] ?? u['username'] ?? 'Member').toString().trim();
                              final uName = (u['username'] ?? 'user').toString().trim();
                              final uEmail = (u['email'] ?? '').toString().trim();
                              final isInvited = invitedUsernames.contains(uName.toLowerCase());

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                leading: Checkbox(
                                  value: isSel,
                                  activeColor: const Color(0xFF0F766E),
                                  onChanged: (v) {
                                    setDState(() {
                                      if (v == true) {
                                        selectedIds.add(uid);
                                      } else {
                                        selectedIds.remove(uid);
                                      }
                                    });
                                  },
                                ),
                                title: Text('~ $dName', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 13)),
                                subtitle: Text('@$uName • $uEmail', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
                                trailing: isInvited
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF0FDF4),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF86EFAC)),
                                        ),
                                        child: const Text('Invited ✓', style: TextStyle(color: Color(0xFF16A34A), fontSize: 11, fontWeight: FontWeight.bold)),
                                      )
                                    : OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF0F766E),
                                          side: const BorderSide(color: Color(0xFF0F766E)),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(Icons.send_rounded, size: 12),
                                        label: const Text('Send Invite', style: TextStyle(fontSize: 11)),
                                        onPressed: isSendingDirectInvite ? null : () => sendDirectInvite('@$uName', uid),
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Color(0xFF64748B)))),
              if (selectedIds.isNotEmpty)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
                  onPressed: () async {
                    try {
                      final api = ref.read(apiClientProvider);
                      final groupId = _groupData['id'].toString();

                      await api.dio.post(
                        ApiEndpoints.groupMembers(groupId),
                        data: {
                          'user_ids': selectedIds.toList(),
                          'role_id': initialRoleId,
                        },
                      );

                      Navigator.pop(ctx);
                      _loadInitialData();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added ${selectedIds.length} member(s) to group!')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to add members.')),
                        );
                      }
                    }
                  },
                  child: Text('Add ${selectedIds.length} User(s) Directly'),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Delete Group ──────────────────────────

  Future<void> _deleteGroupDialog() async {
    final confirmCtrl = TextEditingController();
    final groupName = _groupData['name']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          title: Text('Delete Group "$groupName"?', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This action is irreversible. All group messages, files, and role assignments will be permanently deleted.',
                  style: TextStyle(color: Color(0xFF475569), fontSize: 13),
                ),
                const SizedBox(height: 16),
                Text('Type "$groupName" to confirm:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  style: const TextStyle(color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: groupName,
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                    ),
                  ),
                  onChanged: (_) => setDState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: confirmCtrl.text.trim() == groupName ? () => Navigator.pop(ctx, true) : null,
              child: const Text('I understand, delete this group'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiClientProvider);
        final groupId = _groupData['id'].toString();

        await api.dio.delete('${ApiEndpoints.groups}/$groupId');
        Navigator.pop(context); // Close dialog
        widget.onGroupUpdated();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group deleted successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete group.')),
          );
        }
      }
    }
  }

  Color _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF0F766E);
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return const Color(0xFF0F766E);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.sizeOf(context);
    final isMobile = mediaQuery.width < 768;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 16)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: isMobile ? double.infinity : 980,
          height: isMobile ? mediaQuery.height * 0.92 : 680,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
              : isMobile
                  ? Column(
                      children: [
                        // Mobile Header
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const Icon(Icons.groups, color: Color(0xFF0F766E), size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _groupData['name']?.toString() ?? 'Group Settings',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 20),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                        // Mobile Horizontal Tab Pills
                        Container(
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            children: [
                              _buildMobileTabChip(0, Icons.settings_outlined, 'General'),
                              _buildMobileTabChip(1, Icons.people_outline, 'Members (${_members.length})'),
                              _buildMobileTabChip(2, Icons.security_outlined, 'Roles & Permissions (${_roles.length})'),
                              _buildMobileTabChip(3, Icons.notifications_none, 'Notifications'),
                            ],
                          ),
                        ),
                        // Mobile Tab Content
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(16),
                                  child: _buildSelectedTabContent(theme, isMobile: true),
                                ),
                              ),
                              // Unsaved Changes Bottom Floating Bar
                              if (_hasUnsavedChanges && _selectedTab == 2)
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                                      ],
                                      border: Border.all(color: const Color(0xFF334155)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 18),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text('Unsaved changes!', style: TextStyle(fontSize: 12, color: Colors.white)),
                                        ),
                                        FilledButton(
                                          onPressed: _isSaving ? null : _saveRoleChanges,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF0F766E),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          ),
                                          child: _isSaving
                                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                              : const Text('Save', style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        // ── LEFT SIDEBAR TABS ──────────
                        Container(
                          width: 220,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Text(
                                  _groupData['name']?.toString().toUpperCase() ?? 'GROUP SETTINGS',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF64748B),
                                    letterSpacing: 0.8,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildTabItem(0, Icons.settings_outlined, 'General'),
                              _buildTabItem(1, Icons.people_outline, 'Members (${_members.length})'),
                              _buildTabItem(2, Icons.security_outlined, 'Roles & Permissions (${_roles.length})'),
                              _buildTabItem(3, Icons.notifications_none, 'Notifications'),
                              const Spacer(),
                              const Divider(color: Color(0xFFE2E8F0)),
                              _buildTabItem(4, Icons.delete_forever_outlined, 'Danger Zone', isDestructive: true),
                            ],
                          ),
                        ),

                        // ── RIGHT CONTENT AREA ─────────
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(24),
                                  child: _buildSelectedTabContent(theme),
                                ),
                              ),

                              // Unsaved Changes Bottom Floating Bar
                              if (_hasUnsavedChanges && _selectedTab == 2)
                                Positioned(
                                  left: 20,
                                  right: 20,
                                  bottom: 16,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                                      ],
                                      border: Border.all(color: const Color(0xFF334155)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
                                        const SizedBox(width: 12),
                                        const Text('Careful — you have unsaved changes!', style: TextStyle(fontSize: 13, color: Colors.white)),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: () {
                                            if (_selectedRole != null) _selectRole(_selectedRole!);
                                          },
                                          child: const Text('Reset', style: TextStyle(color: Color(0xFF94A3B8))),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton(
                                          onPressed: _isSaving ? null : _saveRoleChanges,
                                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
                                          child: _isSaving
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                              : const Text('Save Changes'),
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
      ),
    );
  }

  Widget _buildMobileTabChip(int index, IconData icon, String title, {bool isDestructive = false}) {
    final isSelected = _selectedTab == index;
    final color = isDestructive
        ? (isSelected ? Colors.redAccent : Colors.redAccent.withValues(alpha: 0.8))
        : (isSelected ? const Color(0xFF0F766E) : const Color(0xFF475569));

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        avatar: Icon(icon, size: 15, color: isSelected ? Colors.white : color),
        label: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : color,
          ),
        ),
        selectedColor: isDestructive ? Colors.redAccent : const Color(0xFF0F766E),
        backgroundColor: isSelected ? const Color(0xFF0F766E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isSelected ? Colors.transparent : const Color(0xFFE2E8F0)),
        ),
        onSelected: (_) => setState(() => _selectedTab = index),
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String title, {bool isDestructive = false}) {
    final isSelected = _selectedTab == index;
    final color = isDestructive
        ? (isSelected ? Colors.redAccent : Colors.redAccent.withValues(alpha: 0.8))
        : (isSelected ? const Color(0xFF0F766E) : const Color(0xFF475569));

    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDestructive ? Colors.redAccent.withValues(alpha: 0.1) : const Color(0xFF0F766E).withValues(alpha: 0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent(ThemeData theme, {bool isMobile = false}) {
    switch (_selectedTab) {
      case 0:
        return _buildGeneralTab(theme, isMobile: isMobile);
      case 1:
        return _buildMembersTab(theme, isMobile: isMobile);
      case 2:
        return _buildRolesTab(theme, isMobile: isMobile);
      case 3:
        return _buildNotificationsTab(theme);
      case 4:
        return _buildDangerZoneTab(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── 1. General Tab ────────────────────────

  Widget _buildGeneralTab(ThemeData theme, {bool isMobile = false}) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('General Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              if (!isMobile)
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              labelText: 'Group Name',
              labelStyle: const TextStyle(color: Color(0xFF64748B)),
              hintText: 'Enter group name',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            style: const TextStyle(color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              labelText: 'Group Description',
              labelStyle: const TextStyle(color: Color(0xFF64748B)),
              hintText: 'Describe the purpose and mission of this group...',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5)),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          const Text('Group Visibility', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('Private Group 🔒', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF0F172A))),
                  subtitle: const Text('Only invited/added members can access this group.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  value: 'private',
                  groupValue: _selectedVisibility,
                  activeColor: const Color(0xFF0F766E),
                  onChanged: (v) {
                    setState(() => _selectedVisibility = v!);
                  },
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                RadioListTile<String>(
                  title: const Text('Organization-Wide Group 🌐', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF0F172A))),
                  subtitle: const Text('All users in your organization can view and join.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  value: 'organization',
                  groupValue: _selectedVisibility,
                  activeColor: const Color(0xFF0F766E),
                  onChanged: (v) {
                    setState(() => _selectedVisibility = v!);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xFFF8FAFC),
            ),
            child: SwitchListTile(
              title: const Text('Only Owner and Admins Can Invite', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Color(0xFF0F172A))),
              subtitle: const Text('When enabled, standard group members cannot invite new users or generate invite links.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              value: _onlyAdminInvites,
              activeColor: const Color(0xFF0F766E),
              onChanged: (v) => setState(() => _onlyAdminInvites = v),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _openInviteModal,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  side: const BorderSide(color: Color(0xFF0F766E)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Invite Link'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _isSaving ? null : _saveGeneralSettings,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes'),
              ),
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 28),
            const Divider(color: Color(0xFFE2E8F0)),
            const SizedBox(height: 16),
            _buildDangerZoneCard(theme),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  // ── 2. Members Tab ────────────────────────

  Widget _buildMembersTab(ThemeData theme, {bool isMobile = false}) {
    final filteredMembers = _members.where((m) {
      final name = (m['display_name'] ?? m['username'] ?? '').toString().toLowerCase();
      final uname = (m['username'] ?? '').toString().toLowerCase();
      final q = _memberSearchQuery.toLowerCase();
      return name.contains(q) || uname.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Group Members (${_members.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.link, size: 20, color: Color(0xFF0F766E)),
                  tooltip: 'Generate Expiring Invite Link',
                  onPressed: _openInviteModal,
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _addMembersDialog,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.person_add_alt_1, size: 15),
                  label: const Text('Add', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search members...',
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
            prefixIcon: const Icon(Icons.search, size: 17, color: Color(0xFF94A3B8)),
            filled: true,
            isDense: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onChanged: (v) => setState(() => _memberSearchQuery = v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filteredMembers.isEmpty
              ? const Center(child: Text('No members found.', style: TextStyle(color: Color(0xFF64748B))))
              : ListView.separated(
                  itemCount: filteredMembers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  itemBuilder: (ctx, i) {
                    final member = filteredMembers[i];
                    final dName = (member['display_name'] ?? member['username'] ?? 'User').toString();
                    final uName = (member['username'] ?? '').toString();
                    final memberRole = member['role'];
                    final roleName = memberRole is Map
                        ? (memberRole['name']?.toString() ?? 'Group Member')
                        : (member['role_name'] ?? member['role'] ?? 'Group Member').toString();
                    final isOwner = (memberRole is Map && (memberRole['hierarchy_rank'] == 0 || memberRole['name'] == 'Group Owner')) ||
                        member['is_owner'] == true ||
                        roleName == 'Group Owner';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      leading: CircleAvatar(
                        radius: 17,
                        backgroundColor: const Color(0xFFCCFBF1),
                        child: Text(
                          (dName.isNotEmpty ? dName[0] : 'U').toUpperCase(),
                          style: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              dName,
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A), fontSize: 13.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isOwner) ...[
                            const SizedBox(width: 4),
                            const Text('👑', style: TextStyle(fontSize: 11)),
                          ],
                        ],
                      ),
                      subtitle: Text('@$uName', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isOwner && _isCurrentUserOwner)
                            PopupMenuButton<String>(
                              tooltip: 'Change Role',
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      roleName,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Icon(Icons.arrow_drop_down, size: 13, color: Color(0xFF64748B)),
                                  ],
                                ),
                              ),
                              itemBuilder: (ctx) => _roles.where((r) => r['hierarchy_rank'] != 0).map((r) {
                                final isCurrent = r['name'] == roleName;
                                final isViewer = r['name'] == 'Group Viewer';
                                return PopupMenuItem<String>(
                                  value: r['id'].toString(),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${r['name']}${isViewer ? ' (View-Only)' : ''}',
                                        style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: const Color(0xFF0F172A), fontSize: 13),
                                      ),
                                      if (isCurrent) ...[
                                        const Spacer(),
                                        const Icon(Icons.check, size: 16, color: Color(0xFF0F766E)),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(),
                              onSelected: (roleId) async {
                                await _changeMemberRole(member, roleId);
                              },
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isOwner ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isOwner ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                roleName,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: isOwner ? const Color(0xFFD97706) : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          if (!isOwner) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 17, color: Colors.redAccent),
                              tooltip: 'Remove',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () => _removeMemberDialog(member),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── 3. Roles & Permissions Tab ─────────────

  Widget _buildRolesTab(ThemeData theme, {bool isMobile = false}) {
    if (isMobile) {
      if (_selectedRole != null) {
        return Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF0F766E)),
                  onPressed: () => setState(() => _selectedRole = null),
                ),
                Text('Role: ${_selectedRole!['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildRoleEditor(theme)),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Roles & Permissions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Role', style: TextStyle(fontSize: 12)),
                onPressed: _createRoleDialog,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _roles.length,
              itemBuilder: (ctx, i) {
                final role = _roles[i];
                final rColor = _parseHexColor(role['color']);
                final isOwner = role['hierarchy_rank'] == 0;
                final isViewer = role['name'] == 'Group Viewer' || role['hierarchy_rank'] == 200;
                final isDefault = role['is_default'] == true;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: ListTile(
                    leading: isOwner
                        ? const Text('👑', style: TextStyle(fontSize: 18))
                        : Container(width: 14, height: 14, decoration: BoxDecoration(color: rColor, shape: BoxShape.circle)),
                    title: Text(role['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF0F172A))),
                    subtitle: Text(
                      isDefault ? 'Default role for new members' : (isViewer ? 'Read-only viewer role' : 'Tap to edit permissions'),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                    onTap: () => _selectRole(role),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Roles & Permissions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF64748B))),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT: Roles Hierarchy List
              Container(
                width: 260,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('ROLES HIERARCHY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18, color: Color(0xFF0F766E)),
                            tooltip: 'Create Custom Role',
                            onPressed: _createRoleDialog,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _roles.length,
                        itemBuilder: (ctx, i) {
                          final role = _roles[i];
                          final isSelected = _selectedRole?['id'] == role['id'];
                          final rColor = _parseHexColor(role['color']);
                          final isOwner = role['hierarchy_rank'] == 0;
                          final isViewer = role['name'] == 'Group Viewer' || role['hierarchy_rank'] == 200;
                          final isDefault = role['is_default'] == true;
                          final isSystem = role['is_system'] == true ||
                              ['Group Owner', 'Group Admin', 'Group Member', 'Group Viewer'].contains(role['name']);

                          return InkWell(
                            onTap: () => _selectRole(role),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF0F766E).withValues(alpha: 0.08) : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected ? const Color(0xFF0F766E) : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (isOwner)
                                    const Text('👑', style: TextStyle(fontSize: 14))
                                  else if (isViewer)
                                    const Icon(Icons.visibility_outlined, size: 14, color: Color(0xFF0369A1))
                                  else
                                    Container(width: 10, height: 10, decoration: BoxDecoration(color: rColor, shape: BoxShape.circle)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      role['name']?.toString() ?? '',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isDefault)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: const Color(0xFFCCFBF1), borderRadius: BorderRadius.circular(4)),
                                      child: const Text('DEFAULT', style: TextStyle(fontSize: 9, color: Color(0xFF0F766E), fontWeight: FontWeight.bold)),
                                    )
                                  else if (isViewer)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(4)),
                                      child: const Text('VIEW-ONLY', style: TextStyle(fontSize: 9, color: Color(0xFF0369A1), fontWeight: FontWeight.bold)),
                                    )
                                  else if (isSystem)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(4)),
                                      child: const Text('SYSTEM', style: TextStyle(fontSize: 9, color: Color(0xFF7E22CE), fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // RIGHT: Selected Role Editor
              Expanded(
                child: _selectedRole == null
                    ? const Center(child: Text('Select a role on the left to edit.', style: TextStyle(color: Color(0xFF64748B))))
                    : _buildRoleEditor(theme),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoleEditor(ThemeData theme) {
    final isOwnerRole = _selectedRole?['hierarchy_rank'] == 0;
    final isViewerRole = _selectedRole?['name'] == 'Group Viewer' || _selectedRole?['hierarchy_rank'] == 200;
    final isSystemRole = _selectedRole?['is_system'] == true ||
        ['Group Owner', 'Group Admin', 'Group Member', 'Group Viewer'].contains(_selectedRole?['name']);
    final isDefaultRole = _selectedRole?['is_default'] == true;
    final canEdit = _canManageRole(_selectedRole!);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: _parseHexColor(_roleColor), shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(_selectedRole?['name']?.toString() ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                if (isSystemRole) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(4)),
                    child: const Text('🔒 System Role', style: TextStyle(fontSize: 10, color: Color(0xFF7E22CE), fontWeight: FontWeight.bold)),
                  ),
                ],
                const Spacer(),
                if (!isSystemRole && canEdit)
                  TextButton.icon(
                    onPressed: () => _deleteRoleDialog(_selectedRole!),
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                    label: const Text('Delete Role', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
              ],
            ),
          ),

          // Scrollable Editor Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isOwnerRole)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield, color: Color(0xFFB45309), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Group Owner is permanent and has absolute management authority. Permissions cannot be modified.',
                              style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isViewerRole)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBAE6FD)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.visibility_outlined, color: Color(0xFF0369A1), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Group Viewer is a built-in view-only role. Members in this role can view the group and read messages, but cannot post messages, upload attachments, add reactions, or manage settings.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF0369A1)),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Role Name & Description
                  TextField(
                    controller: _roleNameController,
                    enabled: !isSystemRole && canEdit,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      labelText: 'Role Name',
                      labelStyle: const TextStyle(color: Color(0xFF64748B)),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5)),
                    ),
                    onChanged: (_) => setState(() => _hasUnsavedChanges = true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _roleDescController,
                    enabled: !isOwnerRole && canEdit,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      labelText: 'Description (Optional)',
                      labelStyle: const TextStyle(color: Color(0xFF64748B)),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5)),
                    ),
                    onChanged: (_) => setState(() => _hasUnsavedChanges = true),
                  ),
                  const SizedBox(height: 16),

                  // Color Picker
                  if (!isOwnerRole && canEdit) ...[
                    const Text('Role Color', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _colorPresets.map((hex) {
                        final c = _parseHexColor(hex);
                        final isSel = _roleColor == hex;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _roleColor = hex;
                              _hasUnsavedChanges = true;
                            });
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(color: isSel ? const Color(0xFF0F172A) : Colors.transparent, width: 2),
                            ),
                            child: isSel ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Default Role Toggle
                  if (!isOwnerRole && canEdit)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor: const Color(0xFF0F766E),
                      title: const Row(
                        children: [
                          Text('Make this the default role', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                          SizedBox(width: 8),
                          Tooltip(
                            message: 'New members joining the Group will automatically receive this role.',
                            child: Icon(Icons.info_outline, size: 15, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                      value: _roleIsDefault,
                      onChanged: (v) {
                        if (v == true) {
                          final currentRoleId = _selectedRole?['id']?.toString();
                          final existingDefault = _roles.firstWhere(
                            (r) => r['is_default'] == true && r['id']?.toString() != currentRoleId,
                            orElse: () => {},
                          );
                          if (existingDefault.isNotEmpty) {
                            final existingName = existingDefault['name'] ?? 'another role';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFFDC2626),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                content: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "In this group, '$existingName' is set as default. Disable it first.",
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            return;
                          }
                        }
                        setState(() {
                          _roleIsDefault = v;
                          _hasUnsavedChanges = true;
                        });
                      },
                    ),

                  const Divider(color: Color(0xFFE2E8F0), height: 28),

                  // Categorized Permissions
                  const Text('PERMISSIONS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F766E), letterSpacing: 0.8)),
                  const SizedBox(height: 12),

                  ..._permissionCategories.entries.map((cat) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(cat.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        ),
                        ...cat.value.map((perm) {
                          final pKey = perm['key']!;
                          final pLabel = perm['label']!;
                          final pDesc = perm['desc']!;
                          final isEnabled = isOwnerRole ? true : (_rolePermissions[pKey] == true);
                          final canGrant = isOwnerRole ? false : _canGrantPermission(pKey);

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(pLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
                                          const SizedBox(width: 6),
                                          Tooltip(
                                            message: pDesc,
                                            child: const Icon(Icons.info_outline, size: 15, color: Color(0xFF94A3B8)),
                                          ),
                                          if (!canGrant && !isOwnerRole) ...[
                                            const SizedBox(width: 6),
                                            const Tooltip(
                                              message: '🔒 You cannot grant this permission because your current role does not have this authority.',
                                              child: Icon(Icons.lock_outline, size: 14, color: Color(0xFFD97706)),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: isEnabled,
                                  activeTrackColor: const Color(0xFF0F766E),
                                  onChanged: (!canEdit || isOwnerRole || !canGrant)
                                      ? null
                                      : (val) {
                                          setState(() {
                                            _rolePermissions[pKey] = val;
                                            _hasUnsavedChanges = true;
                                          });
                                        },
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. Notifications Tab ──────────────────

  Widget _buildNotificationsTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Notification Preferences', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF64748B))),
          ],
        ),
        const SizedBox(height: 16),
        RadioListTile<String>(
          value: 'all',
          groupValue: 'all',
          activeColor: const Color(0xFF0F766E),
          onChanged: (_) {},
          title: const Text('All Messages', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
          subtitle: const Text('Get notified for every message in this group.', style: TextStyle(color: Color(0xFF64748B))),
        ),
        RadioListTile<String>(
          value: 'mentions',
          groupValue: 'all',
          activeColor: const Color(0xFF0F766E),
          onChanged: (_) {},
          title: const Text('@Mentions Only', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
          subtitle: const Text('Get notified only when you are directly mentioned.', style: TextStyle(color: Color(0xFF64748B))),
        ),
        RadioListTile<String>(
          value: 'nothing',
          groupValue: 'all',
          activeColor: const Color(0xFF0F766E),
          onChanged: (_) {},
          title: const Text('Nothing (Mute)', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
          subtitle: const Text('Mute all notifications from this group.', style: TextStyle(color: Color(0xFF64748B))),
        ),
      ],
    );
  }

  Widget _buildDangerZoneTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Danger Zone', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF64748B))),
          ],
        ),
        const SizedBox(height: 16),
        _buildDangerZoneCard(theme),
      ],
    );
  }

  Widget _buildDangerZoneCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Delete Group', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
          const SizedBox(height: 6),
          const Text(
            'Once deleted, this Group and all its messages, roles, and files cannot be recovered. Please be certain.',
            style: TextStyle(fontSize: 13, color: Color(0xFF7F1D1D), height: 1.35),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: _deleteGroupDialog,
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Delete This Group'),
          ),
        ],
      ),
    );
  }
}
