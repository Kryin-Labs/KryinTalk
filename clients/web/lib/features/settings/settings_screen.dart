/// ConnectHub — You (Settings) Screen.
///
/// Account preferences, profile configuration, notifications, and security.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/theme/theme_provider.dart';
import '../../shared/widgets/global_header.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _emailNotifications = true;
  bool _desktopNotifications = true;
  bool _soundEnabled = true;
  bool _hideFromDirectMessage = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.get(ApiEndpoints.me);
      if (mounted && res.data is Map) {
        setState(() {
          _hideFromDirectMessage = res.data['hide_from_dm'] == true;
        });
        return;
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _hideFromDirectMessage =
              prefs.getBool('hide_from_direct_message') ?? false;
        });
      }
    } catch (_) {}
  }

  void _showActiveSessionsNotice() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAF9F6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(LucideIcons.shield_alert, color: Color(0xFF0F766E), size: 22),
            SizedBox(width: 10),
            Text('Active Sessions & Devices',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1C1917))),
          ],
        ),
        content: const Text(
          'Disabled Currently — Contact Administrator to enable it (Coming in next update)',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openChangePasswordDialog() async {
    final currPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAF9F6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
        contentPadding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
        actionsPadding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(LucideIcons.key,
                  color: Color(0xFF0F766E), size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Change Password',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1C1917))),
                  Text('Update your account security credentials',
                      style: TextStyle(fontSize: 12, color: Color(0xFF78716C))),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text('Current Password *',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1C1917))),
              const SizedBox(height: 6),
              TextField(
                controller: currPassCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Enter current password',
                  prefixIcon: const Icon(LucideIcons.lock,
                      size: 18, color: Color(0xFF78716C)),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE6E4E0))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE6E4E0))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFF0F766E), width: 2)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('New Password *',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1C1917))),
              const SizedBox(height: 6),
              TextField(
                controller: newPassCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Minimum 6 characters',
                  prefixIcon: const Icon(LucideIcons.key_round,
                      size: 18, color: Color(0xFF78716C)),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE6E4E0))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE6E4E0))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFF0F766E), width: 2)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Confirm New Password *',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1C1917))),
              const SizedBox(height: 6),
              TextField(
                controller: confirmPassCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Re-enter new password',
                  prefixIcon: const Icon(LucideIcons.shield_check,
                      size: 18, color: Color(0xFF78716C)),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE6E4E0))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE6E4E0))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFF0F766E), width: 2)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(
                    color: Color(0xFF78716C), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 4,
            ),
            icon: const Icon(LucideIcons.save, size: 16),
            label: const Text('Update Password',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              if (newPassCtrl.text != confirmPassCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('New passwords do not match.')),
                );
                return;
              }
              if (newPassCtrl.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Password must be at least 6 characters.')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
          ),
        ],
      ),
    );

    if (updated == true) {
      try {
        final api = ref.read(apiClientProvider);
        await api.dio.post(
          ApiEndpoints.changePassword,
          data: {
            'current_password': currPassCtrl.text,
            'new_password': newPassCtrl.text,
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0F766E),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              content: const Row(
                children: [
                  Icon(LucideIcons.circle_check, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Password updated successfully!'),
                ],
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              content: Text('Failed to update password: $e'),
            ),
          );
        }
      }
    }
  }

  Future<void> _openEditProfileDialog() async {
    final user = ref.read(authProvider).user ?? const <String, dynamic>{};
    final nameCtrl = TextEditingController(
        text: user['display_name']?.toString() ?? '');
    final usernameCtrl = TextEditingController(
        text: user['username']?.toString() ?? '');
    try {
      final changes = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit profile'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameCtrl,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final displayName = nameCtrl.text.trim();
                final username = usernameCtrl.text.trim().replaceFirst('@', '');
                if (displayName.isEmpty ||
                    !RegExp(r'^[a-zA-Z0-9_]{3,100}$').hasMatch(username)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Use a display name and a 3–100 character username with letters, numbers, or underscores.')),
                  );
                  return;
                }
                Navigator.pop(ctx, {
                  'display_name': displayName,
                  'username': username,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (changes == null || !mounted) return;
      await ref.read(apiClientProvider).dio.put(ApiEndpoints.me, data: changes);
      await ref.read(authProvider.notifier).refreshProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile could not be updated.')),
        );
      }
    } finally {
      nameCtrl.dispose();
      usernameCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const GlobalHeader(
        title: 'You (Settings)',
        description:
            'Manage profile details, account security, and notification preferences.',
        breadcrumbs: ['ConnectHub', 'Settings'],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Card
            _buildClayCard(
              padding: EdgeInsets.all(isMobile ? 18 : 24),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: const Color(0xFF0F766E),
                              child: Text(
                                (authState.displayName.isNotEmpty
                                        ? authState.displayName[0]
                                        : 'U')
                                    .toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          authState.displayName,
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1C1917)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () async {
                                          await ref
                                              .read(authProvider.notifier)
                                              .logout();
                                          if (context.mounted)
                                            context.go('/login');
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF2F2),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: const Color(0xFFFECACA)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(LucideIcons.log_out,
                                                  size: 12,
                                                  color: Colors.redAccent),
                                              SizedBox(width: 4),
                                              Text(
                                                'Log out',
                                                style: TextStyle(
                                                  color: Colors.redAccent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    authState.email,
                                    style: const TextStyle(
                                        color: Color(0xFF78716C), fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF9),
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(color: const Color(0xFFCCFBF1)),
                          ),
                          child: Text(
                            authState.isSuperAdmin
                                ? 'Super Administrator'
                                : 'Standard Member',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F766E)),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: const Color(0xFF0F766E),
                          child: Text(
                            (authState.displayName.isNotEmpty
                                    ? authState.displayName[0]
                                    : 'U')
                                .toUpperCase(),
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                authState.displayName,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1C1917)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                authState.email,
                                style: const TextStyle(
                                    color: Color(0xFF78716C), fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF9),
                                  borderRadius: BorderRadius.circular(9999),
                                  border: Border.all(
                                      color: const Color(0xFFCCFBF1)),
                                ),
                                child: Text(
                                  authState.isSuperAdmin
                                      ? 'Super Administrator'
                                      : 'Standard Member',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F766E)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _openEditProfileDialog,
                icon: const Icon(LucideIcons.pencil, size: 16),
                label: const Text('Edit profile'),
              ),
            ),
            const SizedBox(height: 20),

            _buildClayCard(
              padding: EdgeInsets.all(isMobile ? 18 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Appearance',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: const Color(0xFF2DD4BF),
                    title: const Text('Dark mode',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text(
                        'Use the focused dark workspace theme across ConnectHub.'),
                    secondary: Icon(themeMode == ThemeMode.dark
                        ? LucideIcons.moon_star
                        : LucideIcons.sun),
                    value: themeMode == ThemeMode.dark,
                    onChanged: ref.read(themeModeProvider.notifier).setDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Notification Settings Card
            _buildClayCard(
              padding: EdgeInsets.all(isMobile ? 18 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notification Preferences',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1C1917)),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    activeThumbColor: const Color(0xFF0F766E),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Email Notifications',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C1917),
                            fontSize: 14)),
                    subtitle: const Text(
                        'Receive digest emails for unread mentions & announcements',
                        style:
                            TextStyle(color: Color(0xFF78716C), fontSize: 12)),
                    value: _emailNotifications,
                    onChanged: (val) =>
                        setState(() => _emailNotifications = val),
                  ),
                  const Divider(color: Color(0xFFE6E4E0)),
                  SwitchListTile(
                    activeThumbColor: const Color(0xFF0F766E),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Desktop Push Notifications',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C1917),
                            fontSize: 14)),
                    subtitle: const Text(
                        'Receive real-time desktop popups when new direct messages arrive',
                        style:
                            TextStyle(color: Color(0xFF78716C), fontSize: 12)),
                    value: _desktopNotifications,
                    onChanged: (val) =>
                        setState(() => _desktopNotifications = val),
                  ),
                  const Divider(color: Color(0xFFE6E4E0)),
                  SwitchListTile(
                    activeThumbColor: const Color(0xFF0F766E),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notification Sound Effects',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C1917),
                            fontSize: 14)),
                    subtitle: const Text(
                        'Play sound chime when receiving instant messages',
                        style:
                            TextStyle(color: Color(0xFF78716C), fontSize: 12)),
                    value: _soundEnabled,
                    onChanged: (val) => setState(() => _soundEnabled = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Account Security & Privacy Card
            _buildClayCard(
              padding: EdgeInsets.all(isMobile ? 18 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account & Privacy',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1C1917)),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    activeThumbColor: const Color(0xFF0F766E),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hide From Direct Message',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C1917),
                            fontSize: 14)),
                    subtitle: const Text(
                      'When enabled, your account will not appear automatically in Start Direct Message searches or Contacts directory for other users.',
                      style: TextStyle(color: Color(0xFF78716C), fontSize: 12),
                    ),
                    value: _hideFromDirectMessage,
                    onChanged: (val) async {
                      setState(() => _hideFromDirectMessage = val);
                      try {
                        final api = ref.read(apiClientProvider);
                        await api.dio.put(
                          ApiEndpoints.me,
                          data: {'hide_from_dm': val},
                        );
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('hide_from_direct_message', val);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF0F766E),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              content: Text(
                                val
                                    ? 'You are now hidden from Direct Messages & Contacts directory.'
                                    : 'You are now visible in Direct Messages & Contacts directory.',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() => _hideFromDirectMessage = !val);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.redAccent,
                              content: Text('Failed to update setting: $e'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const Divider(color: Color(0xFFE6E4E0)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF9),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(LucideIcons.lock,
                          color: Color(0xFF0F766E), size: 18),
                    ),
                    title: const Text('Password Security',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C1917),
                            fontSize: 14)),
                    subtitle: const Text(
                        'Click to update your credentials and password.',
                        style:
                            TextStyle(color: Color(0xFF78716C), fontSize: 12)),
                    trailing: const Icon(LucideIcons.chevron_right,
                        size: 16, color: Color(0xFF78716C)),
                    onTap: _openChangePasswordDialog,
                  ),
                  const Divider(color: Color(0xFFE6E4E0)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF9),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.security_outlined,
                          color: Color(0xFF0F766E), size: 18),
                    ),
                    title: const Text('Active Sessions & Devices',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C1917),
                            fontSize: 14)),
                    subtitle: const Text(
                        'Currently signed in on active device session',
                        style:
                            TextStyle(color: Color(0xFF78716C), fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios,
                        size: 12, color: Color(0xFF78716C)),
                    onTap: _showActiveSessionsNotice,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClayCard({required Widget child, EdgeInsetsGeometry? padding}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191C23) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF2B303B) : const Color(0xFFE6E4E0),
          width: 1.0,
        ),
      ),
      child: child,
    );
  }
}
