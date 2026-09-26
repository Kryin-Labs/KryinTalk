/// ConnectHub — Unified Global Header Widget (Lucide Icons & SaaSSchool Header).
///
/// Clean Light Cream Header (#FAF9F6 / #E6E4E0) with 100% Overflow-Proof Mobile Constraints:
/// - LEFT: Brand Logo (on mobile) & Truncated Page Title with Ellipsis
/// - MIDDLE: Global Search Bar (on desktop/tablet)
/// - RIGHT: Role Badge (desktop), Notification Bell with Red Badge & Debug Diagnostics Button
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/notifications/notification_provider.dart';
import '../../core/debug/debug_inspector.dart';
import '../../core/theme/theme_provider.dart';
import '../../features/notifications/notification_center_dialog.dart';
import 'connect_hub_logo.dart';

class GlobalHeader extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final String? description;
  final List<String>? breadcrumbs;
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final List<Widget>? actions;
  final bool showSearch;
  final bool showNotifications;

  const GlobalHeader({
    super.key,
    required this.title,
    this.description,
    this.breadcrumbs,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryAction,
    this.actions,
    this.showSearch = true,
    this.showNotifications = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final notifState = ref.watch(notificationProvider);
    final unreadCount = notifState.unreadCount;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 900;
    final isMobile = screenWidth < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleLabel = authState.isSuperAdmin
        ? 'Administrator · KryinTalks'
        : 'Workspace Member';

    return Container(
      height: isMobile ? 54 : preferredSize.height,
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24, vertical: isMobile ? 6 : 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111318) : const Color(0xFFFAF9F6),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2B303B) : const Color(0xFFE6E4E0),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          // ── LEFT: Brand Logo + Page Title (guaranteed to fit inside Expanded) ──
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (compact) ...[
                  KryinTalkLogo(
                    size: 32,
                    onTap: () => context.go('/dashboard'),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: isMobile ? 17 : 20,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFFF3F4F6)
                          : const Color(0xFF1C1917),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),

          // ── MIDDLE: Centered Search Bar (Desktop / Large Screens only) ──
          if (showSearch && !compact)
            Expanded(
              flex: 2,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF20242D) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE6E4E0)),
                  ),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          LucideIcons.search,
                          size: 16,
                          color: isDark
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF78716C),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          readOnly: true,
                          onTap: () => context.go('/search'),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? const Color(0xFFF3F4F6)
                                : const Color(0xFF1C1917),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search conversations, files, team...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF78716C),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color:
                              isDark ? const Color(0xFF191C23) : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE6E4E0)),
                        ),
                        child: Text(
                          '⌘K',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFF9CA3AF)
                                : const Color(0xFF78716C),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(width: 8),

          // ── RIGHT: Role Pill (Desktop) ─────────────────────
          if (screenWidth >= 1050) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF9),
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: const Color(0xFFCCFBF1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.shield_check,
                      size: 14, color: Color(0xFF0F766E)),
                  const SizedBox(width: 6),
                  Text(
                    roleLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],

          // ── Actions / Primary Action Icon (e.g. Create Group) ──
          if (actions != null && actions!.isNotEmpty) ...[
            ...actions!,
            const SizedBox(width: 8),
          ] else if (onPrimaryAction != null) ...[
            if (screenWidth >= 700 && primaryActionLabel != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: onPrimaryAction,
                icon: Icon(primaryActionIcon ?? LucideIcons.plus, size: 16),
                label: Text(
                  primaryActionLabel!,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
              )
            else
              Tooltip(
                message: primaryActionLabel ?? 'Action',
                child: InkWell(
                  onTap: onPrimaryAction,
                  borderRadius: BorderRadius.circular(9999),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF0F766E).withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      primaryActionIcon ?? LucideIcons.plus,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],

          // Notification Bell Icon with Zero-Glow Crisp Badge
          if (showNotifications) ...[
            InkWell(
              onTap: () => NotificationCenterDialog.show(context),
              borderRadius: BorderRadius.circular(9999),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF191C23) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE6E4E0)),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      unreadCount > 0
                          ? LucideIcons.bell_ring
                          : LucideIcons.bell,
                      size: 17,
                      color: unreadCount > 0
                          ? (isDark
                              ? const Color(0xFF2DD4BF)
                              : const Color(0xFF0F766E))
                          : (isDark
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF78716C)),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          PopupMenuButton<String>(
            tooltip: 'Account menu',
            onSelected: (value) async {
              if (value == 'friends') {
                context.go('/friends');
              } else if (value == 'settings') {
                context.go('/settings');
              } else if (value == 'theme') {
                await ref.read(themeModeProvider.notifier).toggle();
              } else if (value == 'logout') {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'friends',
                child: ListTile(
                    leading: Icon(LucideIcons.user_round_check),
                    title: Text('Friends')),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                    leading: Icon(LucideIcons.settings),
                    title: Text('Settings')),
              ),
              PopupMenuItem(
                value: 'theme',
                child: ListTile(
                    leading: Icon(LucideIcons.moon_star),
                    title: Text('Toggle dark mode')),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                    leading: Icon(LucideIcons.log_out),
                    title: Text('Sign out')),
              ),
            ],
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              child: Text(
                authState.displayName.isEmpty
                    ? 'U'
                    : authState.displayName.characters.first.toUpperCase(),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ),

          // In-App Diagnostics & Dynamic Server Switcher Button (hidden by default, toggle in DebugTopButton.enabled)
          if (DebugTopButton.enabled) DebugTopButton(compact: compact),
        ],
      ),
    );
  }
}
