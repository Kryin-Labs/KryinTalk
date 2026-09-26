/// ConnectHub — Responsive Application Shell (Ultra-Smooth Sidebar & Lucide Icons).
///
/// Features:
/// - Light Cream #FAF9F6 Background
/// - Ultra-smooth 250ms width transition (288px -> 84px) with zero layout jump
/// - Official Lucide Icons Pack (flutter_lucide) matching SaaSSchool
/// - Top Collapse Toggle Button on Sidebar Header
/// - Menu Groups: MAIN MENU, YOU (SETTINGS), ADMINISTRATION
/// - "You (Settings)" navigation item leading to /settings
/// - Active Item Effect: White claymorphic background with soft shadow & #0F766E text
/// - Bottom User Profile Card with Avatar & Logout Button
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/notifications/notification_provider.dart';
import 'connect_hub_logo.dart';

/// Count unread messages separately from notifications. A missing count means
/// the backend cannot supply this badge; do not substitute notification totals.
final unreadMessageCountProvider =
    FutureProvider.autoDispose<int?>((ref) async {
  final auth = ref.watch(
      authProvider.select((state) => (state.hasAppAccess, state.userId)));
  if (!auth.$1) return 0;
  final timer = Timer(const Duration(seconds: 5), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final api = ref.watch(apiClientProvider);
  var count = 0;
  var offset = 0;
  while (true) {
    final response = await api.dio.get(ApiEndpoints.conversations,
        queryParameters: {'limit': 100, 'offset': offset});
    final data = response.data;
    final items = data is Map ? data['items'] : data;
    if (items is! List) return null;
    for (final item in items) {
      if (item is! Map || item['unread_count'] is! num) return null;
      final unread = (item['unread_count'] as num).toInt();
      if (unread > 0) count += unread;
    }
    offset += items.length;
    final total = data is Map ? data['total'] : null;
    if (items.isEmpty ||
        data is List ||
        (total is num ? offset >= total : items.length < 100)) {
      return count;
    }
  }
});

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.path,
    this.adminOnly = false,
  });

  final IconData icon;
  final String label;
  final String path;
  final bool adminOnly;
}

const _mainMenuItems = <_NavItem>[
  _NavItem(
      icon: LucideIcons.layout_dashboard,
      label: 'Dashboard',
      path: '/dashboard'),
  _NavItem(
      icon: LucideIcons.message_square, label: 'Messages', path: '/messages'),
  _NavItem(icon: LucideIcons.users, label: 'Groups', path: '/groups'),
  _NavItem(icon: LucideIcons.folder, label: 'Files', path: '/files'),
  _NavItem(icon: LucideIcons.search, label: 'Search', path: '/search'),
];

const _youMenuItems = <_NavItem>[
  _NavItem(
      icon: LucideIcons.settings, label: 'You (Settings)', path: '/settings'),
];

const _adminMenuItems = <_NavItem>[
  _NavItem(
      icon: LucideIcons.users,
      label: 'Users',
      path: '/admin/users',
      adminOnly: true),
  _NavItem(
      icon: LucideIcons.file_text,
      label: 'Logs',
      path: '/admin/audit-logs',
      adminOnly: true),
  _NavItem(
      icon: LucideIcons.chart_bar,
      label: 'Stats',
      path: '/admin/stats',
      adminOnly: true),
];

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  bool _isCollapsed = false;

  void _toggleCollapse() {
    setState(() => _isCollapsed = !_isCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final path = GoRouterState.of(context).matchedLocation;
    final compact = MediaQuery.sizeOf(context).width < 900;
    final sidebarWidth = _isCollapsed ? 84.0 : 288.0;

    void navigate(String routePath) {
      if (compact) Navigator.of(context).maybePop();
      context.go(routePath);
    }

    final notifState = ref.watch(notificationProvider);
    final unreadNotifCount = notifState.unreadCount;
    final unreadMessageCount =
        ref.watch(unreadMessageCountProvider).valueOrNull ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sidebar = _SaaSSchoolSidebar(
      currentPath: path,
      isCollapsed: _isCollapsed,
      isSuperAdmin: authState.isSuperAdmin,
      canAdmin: authState.isSuperAdmin || authState.isAdmin,
      displayName: authState.displayName,
      email: authState.email,
      unreadNotifCount: unreadNotifCount,
      unreadMessageCount: unreadMessageCount,
      onNavigate: navigate,
      onToggleCollapse: _toggleCollapse,
      onLogout: () async {
        await ref.read(authProvider.notifier).logout();
        if (context.mounted) context.go('/login');
      },
    );

    final scaffoldBg =
        isDark ? const Color(0xFF111318) : const Color(0xFFFAF9F6);

    return Scaffold(
      backgroundColor: scaffoldBg,
      bottomNavigationBar: compact
          ? _MobileBottomNav(
              currentPath: path,
              onNavigate: navigate,
              canAdmin: authState.isSuperAdmin || authState.isAdmin,
              unreadMessageCount: unreadMessageCount,
            )
          : null,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Row(
          children: [
            if (!compact)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.fastOutSlowIn,
                width: sidebarWidth,
                child: ClipRect(child: sidebar),
              ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

class _SaaSSchoolSidebar extends StatelessWidget {
  const _SaaSSchoolSidebar({
    required this.currentPath,
    required this.isCollapsed,
    required this.isSuperAdmin,
    required this.canAdmin,
    required this.displayName,
    required this.email,
    required this.unreadNotifCount,
    required this.unreadMessageCount,
    required this.onNavigate,
    required this.onToggleCollapse,
    required this.onLogout,
  });

  final String currentPath;
  final bool isCollapsed;
  final bool isSuperAdmin;
  final bool canAdmin;
  final String displayName;
  final String email;
  final int unreadNotifCount;
  final int unreadMessageCount;
  final ValueChanged<String> onNavigate;
  final VoidCallback onToggleCollapse;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111318) : const Color(0xFFFAF9F6),
        border: Border(
          right: BorderSide(
              color: isDark ? const Color(0xFF2B303B) : const Color(0xFFE6E4E0),
              width: 1.0),
        ),
      ),
      child: Column(
        children: [
          // ── App Brand Header with Smooth Toggle Button ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                const KryinTalkLogo(
                  size: 42,
                ),
                Expanded(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isCollapsed ? 0.0 : 1.0,
                    child: isCollapsed
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Text(
                                'KryinTalks',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? const Color(0xFFF3F4F6)
                                      : const Color(0xFF1C1917),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                InkWell(
                  onTap: onToggleCollapse,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF191C23) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isDark
                              ? const Color(0xFF2B303B)
                              : const Color(0xFFE6E4E0)),
                    ),
                    child: Icon(
                      isCollapsed
                          ? LucideIcons.panel_left_open
                          : LucideIcons.panel_left_close,
                      size: 18,
                      color: const Color(0xFF0F766E),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Menu Navigation Groups ──────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                // 1. MAIN MENU Section Header
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isCollapsed ? 0.0 : 1.0,
                  child: isCollapsed
                      ? const SizedBox(height: 8)
                      : const Padding(
                          padding: EdgeInsets.only(left: 12, top: 8, bottom: 8),
                          child: Text(
                            'MAIN MENU',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF78716C),
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                ),
                ..._mainMenuItems.map((item) => _buildNavItem(item, isDark)),

                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE6E4E0), height: 1),
                const SizedBox(height: 12),

                // 2. YOU (SETTINGS) Section Header
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isCollapsed ? 0.0 : 1.0,
                  child: isCollapsed
                      ? const SizedBox.shrink()
                      : const Padding(
                          padding: EdgeInsets.only(left: 12, bottom: 8),
                          child: Text(
                            'YOU (SETTINGS)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF78716C),
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                ),
                ..._youMenuItems.map((item) => _buildNavItem(item, isDark)),

                if (canAdmin) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFE6E4E0), height: 1),
                  const SizedBox(height: 12),

                  // 3. ADMINISTRATION Section Header
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isCollapsed ? 0.0 : 1.0,
                    child: isCollapsed
                        ? const SizedBox.shrink()
                        : const Padding(
                            padding: EdgeInsets.only(left: 12, bottom: 8),
                            child: Text(
                              'ADMINISTRATION',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF78716C),
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                  ),
                  ..._adminMenuItems.map((item) => _buildNavItem(item, isDark)),
                ],
              ],
            ),
          ),

          // ── Bottom SaaSSchool Claymorphic User Card ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF191C23) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: isDark
                        ? const Color(0xFF2B303B)
                        : Colors.white.withValues(alpha: 0.5),
                    width: 1.5),
                boxShadow: isDark
                    ? null
                    : const [
                        BoxShadow(
                            color: Color(0xFFE6E4E0),
                            blurRadius: 20,
                            offset: Offset(10, 10)),
                        BoxShadow(
                            color: Colors.white,
                            blurRadius: 20,
                            offset: Offset(-10, -10)),
                      ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF1C1917),
                    child: Text(
                      (displayName.isNotEmpty ? displayName[0] : 'U')
                          .toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isCollapsed ? 0.0 : 1.0,
                      child: isCollapsed
                          ? const SizedBox.shrink()
                          : Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? const Color(0xFFF3F4F6)
                                              : const Color(0xFF1C1917),
                                          fontSize: 13),
                                    ),
                                    Text(
                                      isSuperAdmin ? 'Super Admin' : 'Member',
                                      style: const TextStyle(
                                          color: Color(0xFF78716C),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (!isCollapsed)
                    IconButton(
                      icon: const Icon(LucideIcons.log_out,
                          size: 18, color: Color(0xFF78716C)),
                      tooltip: 'Logout',
                      onPressed: onLogout,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(_NavItem item, bool isDark) {
    final badgeCount = item.path == '/messages'
        ? unreadMessageCount
        : item.path == '/notifications'
            ? unreadNotifCount
            : 0;
    final isActive =
        currentPath == item.path || currentPath.startsWith('${item.path}/');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onNavigate(item.path),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? (isDark ? const Color(0xFF20242D) : Colors.white)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isActive && !isDark
                  ? const [
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
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      item.icon,
                      size: 20,
                      color: isActive
                          ? (isDark
                              ? const Color(0xFF2DD4BF)
                              : const Color(0xFF0F766E))
                          : (isDark
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF78716C)),
                    ),
                    if (badgeCount > 0 && isCollapsed)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF43F5E), // Rose-500 dot
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isCollapsed ? 0.0 : 1.0,
                    child: isCollapsed
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    child: Text(
                                      item.label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isActive
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isActive
                                            ? (isDark
                                                ? const Color(0xFF2DD4BF)
                                                : const Color(0xFF0F766E))
                                            : (isDark
                                                ? const Color(0xFF9CA3AF)
                                                : const Color(0xFF78716C)),
                                      ),
                                    ),
                                  ),
                                ),
                                if (badgeCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF43F5E),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      badgeCount > 99 ? '99+' : '$badgeCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mobile Bottom Navigation Bar (Home, Messages, Groups, Profile)
/// Matches ConnectHub Light Cream & Teal Theme (#FAF9F6 / #0F766E) with Zero Glow.
class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.currentPath,
    required this.onNavigate,
    required this.canAdmin,
    required this.unreadMessageCount,
  });

  final String currentPath;
  final ValueChanged<String> onNavigate;
  final bool canAdmin;
  final int unreadMessageCount;

  Future<void> _showMoreMenu(BuildContext context) async {
    final items = <_NavItem>[
      const _NavItem(icon: LucideIcons.folder, label: 'Files', path: '/files'),
      const _NavItem(
          icon: LucideIcons.search, label: 'Search', path: '/search'),
      const _NavItem(
          icon: LucideIcons.user_round_check,
          label: 'Friends',
          path: '/friends'),
      const _NavItem(
          icon: LucideIcons.bell,
          label: 'Notifications',
          path: '/notifications'),
      const _NavItem(
          icon: LucideIcons.settings, label: 'Settings', path: '/settings'),
      if (canAdmin) ..._adminMenuItems,
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final active = currentPath == item.path ||
                currentPath.startsWith('${item.path}/');
            return InkWell(
              onTap: () {
                Navigator.pop(sheetContext);
                onNavigate(item.path);
              },
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon,
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : null),
                      const SizedBox(height: 8),
                      Text(item.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ]),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final navItems = [
      (
        label: 'Home',
        path: '/dashboard',
        icon: LucideIcons.layout_dashboard,
        isActive: currentPath == '/dashboard' || currentPath == '/'
      ),
      (
        label: 'Messages',
        path: '/messages',
        icon: LucideIcons.message_square,
        isActive: currentPath.startsWith('/messages')
      ),
      (
        label: 'Groups',
        path: '/groups',
        icon: LucideIcons.users,
        isActive: currentPath.startsWith('/groups')
      ),
      (
        label: 'More',
        path: '_more',
        icon: LucideIcons.menu,
        isActive: !currentPath.startsWith('/dashboard') &&
            !currentPath.startsWith('/messages') &&
            !currentPath.startsWith('/groups')
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111318) : const Color(0xFFFAF9F6),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2B303B) : const Color(0xFFE6E4E0),
            width: 1.0,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        top: 6,
        bottom: bottomPadding > 0 ? bottomPadding : 6,
        left: 8,
        right: 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: navItems.map((item) {
          final activeBgColor =
              isDark ? const Color(0xFF115E59) : const Color(0xFF0F766E);
          final activeTextColor =
              isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
          final inactiveColor =
              isDark ? const Color(0xFF9CA3AF) : const Color(0xFF78716C);

          return Expanded(
            child: InkWell(
              onTap: () => item.path == '_more'
                  ? _showMoreMenu(context)
                  : onNavigate(item.path),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 5),
                          decoration: BoxDecoration(
                            color: item.isActive
                                ? activeBgColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            item.icon,
                            size: 20,
                            color: item.isActive ? Colors.white : inactiveColor,
                          ),
                        ),
                        if (item.label == 'Messages' && unreadMessageCount > 0)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 16),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF43F5E),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                unreadMessageCount > 99
                                    ? '99+'
                                    : '$unreadMessageCount',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            item.isActive ? FontWeight.w700 : FontWeight.w500,
                        color: item.isActive ? activeTextColor : inactiveColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
