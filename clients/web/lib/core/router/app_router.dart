/// ConnectHub — App Router (go_router).
///
/// Declarative routing with auth guards.
/// Unauthenticated users are redirected to login.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../supabase/supabase_service.dart';
import '../../features/auth/access_screen.dart';
import '../../features/auth/confirmation_screen.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/groups/group_invite_screen.dart';
import '../../features/groups/group_list_screen.dart';
import '../../features/messaging/messages_screen.dart';
import '../../features/files/file_list_screen.dart';
import '../../features/notifications/notification_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/admin/user_management_screen.dart';
import '../../features/admin/audit_log_screen.dart';
import '../../features/admin/stats_dashboard_screen.dart';
import '../../features/friends/friends_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/legal/terms_screen.dart';
import '../../features/legal/privacy_screen.dart';
import '../../shared/widgets/app_scaffold.dart';

String? accountRedirect(AuthState auth, Uri uri) {
  final path = uri.path;
  if (['/terms', '/privacy', '/auth/callback'].contains(path)) return null;
  final public = ['/login', '/register', '/check-email'].contains(path) ||
      path.startsWith('/join/');
  if (auth.isLoading)
    return public || ['/loading', '/access', '/consent'].contains(path)
        ? null
        : '/loading';
  if (!auth.isAuthenticated) return public ? null : '/login';
  if (auth.user == null) return path == '/access' ? null : '/access';
  if (auth.needsPolicyAcceptance) return path == '/consent' ? null : '/consent';
  if (!auth.hasAppAccess) return path == '/access' ? null : '/access';
  if (['/login', '/register', '/check-email', '/loading', '/consent', '/access']
      .contains(path)) return '/dashboard';
  if (path.startsWith('/admin/') && !auth.isAdmin) return '/dashboard';
  if (['/departments', '/teams', '/channels'].contains(path)) return '/groups';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen<AuthState>(authProvider, (_, __) => refresh.value++);
  Uri? pendingLocation;
  final router = GoRouter(
    initialLocation:
        SupabaseService.initialCallback ? '/auth/callback' : '/dashboard',
    overridePlatformDefaultLocation: SupabaseService.initialCallback,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final path = state.uri.path;
      if (auth.isLoading &&
          ![
            '/loading',
            '/login',
            '/register',
            '/check-email',
            '/auth/callback',
            '/access',
            '/consent',
            '/terms',
            '/privacy'
          ].contains(path)) {
        pendingLocation = state.uri;
      }
      if (path == '/loading' && auth.hasAppAccess && pendingLocation != null) {
        final destination = pendingLocation!;
        pendingLocation = null;
        return accountRedirect(auth, destination) ?? destination.toString();
      }
      return accountRedirect(auth, state.uri);
    },
    routes: [
      GoRoute(
          path: '/loading',
          builder: (context, state) =>
              const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(
          path: '/access', builder: (context, state) => const AccessScreen()),
      GoRoute(
          path: '/consent',
          builder: (context, state) => const AccountConsentScreen()),
      GoRoute(
          path: '/check-email',
          builder: (context, state) => CheckEmailScreen(
              email: state.extra is String ? state.extra as String : null)),
      GoRoute(
          path: '/auth/callback',
          builder: (context, state) => const AuthCallbackScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const TermsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/join/:token',
        builder: (context, state) =>
            GroupInviteScreen(token: state.pathParameters['token']!),
      ),
      ShellRoute(
        builder: (context, state, child) => AppScaffold(
            key: ValueKey(ref.read(authProvider).userId), child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/friends',
            builder: (context, state) => const FriendsScreen(),
          ),
          GoRoute(
            path: '/groups',
            builder: (context, state) => const GroupListScreen(),
          ),
          GoRoute(
            path: '/messages',
            builder: (context, state) {
              final convId = state.uri.queryParameters['conv'];
              final highlightMsgId = state.uri.queryParameters['messageId'] ??
                  state.uri.queryParameters['highlight'];
              final from = state.uri.queryParameters['from'];
              return MessagesScreen(
                initialConversationId: convId,
                highlightMessageId: highlightMsgId,
                fromRoute: from,
              );
            },
          ),
          GoRoute(
            path: '/messages/:conversationId',
            builder: (context, state) {
              final convId = state.pathParameters['conversationId']!;
              final highlightMsgId = state.uri.queryParameters['messageId'] ??
                  state.uri.queryParameters['highlight'];
              final from = state.uri.queryParameters['from'];
              return MessagesScreen(
                initialConversationId: convId,
                highlightMessageId: highlightMsgId,
                fromRoute: from,
              );
            },
          ),
          GoRoute(
            path: '/files',
            builder: (context, state) => const FileListScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationScreen(),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchScreen(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (context, state) => const UserManagementScreen(),
          ),
          GoRoute(
            path: '/admin/audit-logs',
            builder: (context, state) => const AuditLogScreen(),
          ),
          GoRoute(
            path: '/admin/stats',
            builder: (context, state) => const StatsDashboardScreen(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
