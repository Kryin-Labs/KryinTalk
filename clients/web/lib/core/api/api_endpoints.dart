/// ConnectHub — API Endpoint Constants.
///
/// All backend REST endpoint URLs in one place.
library;

import '../debug/debug_inspector.dart';
import '../supabase/supabase_service.dart';

class ApiEndpoints {
  ApiEndpoints._();

  /// Production requests are handled by the Supabase bridge, never FastAPI.
  static const baseUrl = SupabaseConfig.projectUrl;

  // ── Auth ───────────────────────────────────
  static const login = '/auth/login';
  static const register = '/auth/register';
  static const refreshToken = '/auth/refresh';
  static const me = '/auth/me';
  static const directory = '/auth/directory';
  static const changePassword = '/auth/change-password';

  // ── Organizations ─────────────────────────
  static const orgSettings = '/org-settings';

  // ── Groups ────────────────────────────────
  static const groups = '/groups';
  static String group(String id) => '/groups/$id';
  static String groupMembers(String id) => '/groups/$id/members';
  static String groupMember(String id, String userId) =>
      '/groups/$id/members/$userId';
  static String groupMemberRole(String id, String userId) =>
      '/groups/$id/members/$userId/role';
  static String groupRoles(String id) => '/groups/$id/roles';
  static String groupRole(String id, String roleId) =>
      '/groups/$id/roles/$roleId';
  static String groupRolesReorder(String id) => '/groups/$id/roles/reorder';
  static String groupInvites(String id) => '/groups/$id/invites';
  static String groupInvite(String token) => '/groups/invites/$token';
  static String groupInviteAccept(String token) =>
      '/groups/invites/$token/accept';
  static String groupInviteUser(String id) => '/groups/$id/invite-user';
  static String groupInvitationResponse(String id) =>
      '/groups/$id/invitations/respond';

  // ── Messaging ─────────────────────────────
  static const conversations = '/messaging/conversations';
  static String conversation(String id) => '/messaging/conversations/$id';
  static String conversationMessages(String id) =>
      '/messaging/conversations/$id/messages';
  static String directMessage(String userId) => '/messaging/dm/$userId';
  static String markRead(String convId) =>
      '/messaging/conversations/$convId/read';
  static String markUnread(String convId) =>
      '/messaging/conversations/$convId/unread';
  static String conversationPins(String convId) =>
      '/messaging/conversations/$convId/pins';
  static String pinMessage(String convId, String msgId) =>
      '/messaging/conversations/$convId/messages/$msgId/pin';
  static String unpinMessage(String convId, String msgId) =>
      '/messaging/conversations/$convId/messages/$msgId/pin';

  // ── Files ─────────────────────────────────
  static const files = '/files';
  static const fileUpload = '/files/upload';
  static String fileInfo(String id) => '/files/$id';
  static String fileDownload(String id) => '/files/$id/download';
  static String conversationFiles(String convId) =>
      '/files/conversation/$convId';

  // ── Notifications ─────────────────────────
  static const notifications = '/notifications';
  static const unreadCount = '/notifications/unread-count';
  static String markNotifRead(String id) => '/notifications/$id/read';
  static String markConversationNotifsRead(String convId) =>
      '/notifications/conversation/$convId/read';
  static const markAllRead = '/notifications/read-all';

  // ── Presence ──────────────────────────────
  static const presenceHeartbeat = '/presence/heartbeat';
  static const presenceMap = '/presence';
  static String userPresence(String userId) => '/presence/$userId';

  // ── Search ────────────────────────────────
  static const search = '/search';

  // ── Admin ─────────────────────────────────
  static const adminUsers = '/admin/users';
  static String adminUser(String id) => '/admin/users/$id';
  static String adminDeactivate(String id) => '/admin/users/$id/deactivate';
  static String adminResetPassword(String id) =>
      '/admin/users/$id/reset-password';
  static const adminAuditLogs = '/admin/audit-logs';
  static const adminStats = '/admin/stats';
  static const adminBackup = '/admin/backup';
  static String adminRestoreBackup(String id) => '/admin/backup/$id/restore';
  static String adminDeleteBackup(String id) => '/admin/backup/$id';

  // ── WebSocket ─────────────────────────────
  static String websocket(String token) {
    String base = baseUrl;
    try {
      if (AppConfig.instance.currentBaseUrl.isNotEmpty) {
        base = AppConfig.instance.currentBaseUrl;
      }
    } catch (_) {}
    return '${base.replaceFirst('http', 'ws')}/ws?token=$token';
  }
}
