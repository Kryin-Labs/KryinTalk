/// ConnectHub — Dio HTTP Client with JWT Auth Interceptor.
///
/// Centralized HTTP client that attaches the auth token to every request,
/// maintains an instant in-memory token cache, and provides clean error mapping.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_endpoints.dart';
import 'bridge_routes.dart';
import '../presence/presence_status.dart';
import '../debug/debug_inspector.dart';
import '../supabase/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared Dio instance provider.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

class ApiClient {
  late final Dio dio;
  String? _inMemoryToken;

  /// Callback to invoke on auth failure (e.g., redirect to login).
  void Function()? onAuthFailure;
  void Function()? onAccessDenied;

  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.instance.currentBaseUrl.isNotEmpty
            ? AppConfig.instance.currentBaseUrl
            : ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    AppConfig.instance.attachDio(dio);

    dio.interceptors.add(_AuthInterceptor(this));
    dio.interceptors.add(_SupabaseBridgeInterceptor());
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) {}, // Suppress in production
    ));
    _initToken();
  }

  Future<void> _initToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _inMemoryToken = prefs.getString('auth_token');
    } catch (_) {}
  }

  /// Set the auth token for all future requests (instant in-memory + async storage).
  Future<void> setToken(String token) async {
    _inMemoryToken = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
    } catch (_) {}
  }

  /// Get the stored auth token instantly from in-memory cache or SharedPreferences.
  Future<String?> getToken() async {
    if (SupabaseService.instance.isInitialized) {
      return SupabaseService.instance.client.auth.currentSession?.accessToken;
    }
    if (_inMemoryToken != null && _inMemoryToken!.isNotEmpty) {
      return _inMemoryToken;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _inMemoryToken = prefs.getString('auth_token');
    } catch (_) {}
    return _inMemoryToken;
  }

  /// Clear the stored auth token (logout).
  Future<void> clearToken() async {
    _inMemoryToken = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    } catch (_) {}
  }

  /// Check if user has a valid token.
  Future<bool> get isAuthenticated async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}

/// Interceptor that attaches JWT token to every request
/// and handles session expiration responses.
class _AuthInterceptor extends Interceptor {
  final ApiClient _client;

  _AuthInterceptor(this._client);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _client.getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    DebugLogger.instance.logNetwork(
      'HTTP ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.path}',
      details:
          '${response.requestOptions.baseUrl}${response.requestOptions.path}',
      statusCode: response.statusCode,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final path = err.requestOptions.path;
    final statusCode = err.response?.statusCode;
    if (statusCode == 403) _client.onAccessDenied?.call();

    DebugLogger.instance.logError(
      'HTTP ${statusCode ?? "ERR"} ${err.requestOptions.method} $path',
      details:
          '${err.requestOptions.baseUrl}$path -> ${err.message ?? err.error}',
      statusCode: statusCode,
    );

    // Only trigger token clearance & auth failure if /auth/me returns 401 (explicit session expiry)
    // Never trigger on /auth/login or general background data requests
    if (err.response?.statusCode == 401 && path.endsWith('/auth/me')) {
      _client.clearToken();
      _client.onAuthFailure?.call();
    }
    handler.next(err);
  }
}

/// Parsed API error.
class ApiError {
  final int statusCode;
  final String message;
  final String? detail;

  const ApiError({
    required this.statusCode,
    required this.message,
    this.detail,
  });

  factory ApiError.fromDioException(DioException e) {
    final data = e.response?.data;
    return ApiError(
      statusCode: e.response?.statusCode ?? 0,
      message: data is Map
          ? (data['detail'] ?? data['message'] ?? 'Unknown error')
          : 'Network error',
      detail: e.message,
    );
  }

  @override
  String toString() => 'ApiError($statusCode): $message';
}

/// Supabase Cloud Bridge Interceptor: Resolves REST requests directly via Supabase
class _SupabaseBridgeInterceptor extends Interceptor {
  _SupabaseBridgeInterceptor();

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (SupabaseService.instance.hasSession) {
      final path = Uri.parse(options.path).path;
      final method = options.method.toUpperCase();

      try {
        // 1. Health check
        if (method == 'GET' && path == '/health') {
          await SupabaseService.instance.client
              .from('users')
              .select('id')
              .limit(1);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'status': 'healthy',
              'backend': 'supabase',
              'database': 'connected'
            },
          ));
        }

        // 2. /auth/directory -> Supabase users
        if (method == 'GET' && path == '/auth/directory') {
          final users = await SupabaseService.instance.getUsers();
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: users,
          ));
        }

        if (method == 'GET' && path == '/admin/users') {
          final profile =
              await SupabaseService.instance.getCurrentUserProfile();
          if (profile?['is_super_admin'] != true &&
              profile?['role'] != 'admin') {
            throw StateError('Administrator access is required.');
          }
          final client = SupabaseService.instance.client;
          final results = await Future.wait<dynamic>([
            client.from('users').select(
                'id,email,username,display_name,is_active,is_suspended,role,organization_id'),
            client.from('roles').select('id,code'),
            client.from('user_roles').select('user_id,role_id'),
          ]);
          String key(dynamic value) =>
              value.toString().replaceAll('-', '').toLowerCase();
          final roleCodes = <String, String>{
            for (final role in results[1] as List)
              key(role['id']): role['code'].toString(),
          };
          final users = (results[0] as List)
              .map((raw) => Map<String, dynamic>.from(raw as Map))
              .toList();
          for (final user in users) {
            final codes = (results[2] as List)
                .where((assignment) =>
                    key(assignment['user_id']) == key(user['id']))
                .map((assignment) => roleCodes[key(assignment['role_id'])])
                .whereType<String>()
                .toSet();
            for (final code in [
              'super_admin',
              'admin',
              'manager',
              'member',
              'user'
            ]) {
              if (codes.contains(code)) {
                user['role'] = code;
                break;
              }
            }
            user['is_super_admin'] = codes.contains('super_admin');
          }
          return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'items': users, 'total': users.length}));
        }

        if (method == 'GET' && path == '/admin/audit-logs') {
          final rows = await SupabaseService.instance.client
              .from('audit_logs')
              .select(
                  'id,user_id,action,resource_type,resource_id,details,changes,created_at')
              .order('created_at', ascending: false)
              .limit(200);
          final action =
              options.queryParameters['action']?.toString().toLowerCase();
          final resource = options.queryParameters['resource_type']
              ?.toString()
              .toLowerCase();
          final logs = rows
              .where((row) =>
                  (action == null ||
                      row['action']
                          .toString()
                          .toLowerCase()
                          .contains(action)) &&
                  (resource == null ||
                      row['resource_type'].toString().toLowerCase() ==
                          resource))
              .toList();
          return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'items': logs, 'total': logs.length}));
        }

        final directoryUserMatch =
            RegExp(r'^/auth/users/([^/]+)$').firstMatch(path);
        if (method == 'GET' && directoryUserMatch != null) {
          final user = await SupabaseService.instance
              .getUserById(Uri.decodeComponent(directoryUserMatch.group(1)!));
          if (user == null) {
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 404),
              type: DioExceptionType.badResponse,
              message: 'User not found.',
            ));
          }
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: user,
          ));
        }

        if (method == 'POST' && path == '/auth/change-password') {
          final data = options.data is Map
              ? Map<String, dynamic>.from(options.data)
              : <String, dynamic>{};
          await SupabaseService.instance.changePassword(
            currentPassword: data['current_password']?.toString() ?? '',
            newPassword: data['new_password']?.toString() ?? '',
          );
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 204,
          ));
        }

        if ((method == 'PUT' || method == 'PATCH') && path == '/auth/me') {
          final data = options.data is Map
              ? Map<String, dynamic>.from(options.data)
              : <String, dynamic>{};
          final user =
              await SupabaseService.instance.updateCurrentProfile(data);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: user,
          ));
        }

        if (method == 'POST' && path == '/messaging/conversations/direct') {
          final data = Map<String, dynamic>.from(options.data as Map);
          final conversation =
              await SupabaseService.instance.createConversation({
            ...data,
            'conversation_type': 'direct',
          });
          return handler.resolve(Response(
              requestOptions: options, statusCode: 200, data: conversation));
        }

        final readMatch =
            RegExp(r'^/messaging/conversations/([^/]+)/read$').firstMatch(path);
        if (method == 'PUT' && readMatch != null) {
          final receipt = await SupabaseService.instance.markConversationRead(
            readMatch.group(1)!,
            messageId: options.data is Map
                ? options.data['message_id']?.toString()
                : null,
          );
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: receipt,
          ));
        }

        final actionMatch = BridgeRoutes.messageAction.firstMatch(path);
        if (actionMatch != null) {
          final convId = actionMatch.group(1)!;
          final msgId = actionMatch.group(2)!;
          final action = actionMatch.group(3);
          // Scope every write to the conversation in the request. Database
          // policies still enforce the authenticated user's permissions.
          await SupabaseService.instance.client
              .from('messages')
              .select('id')
              .eq('id', msgId)
              .eq('conversation_id', convId)
              .single();
          if (action == 'reactions' &&
              method == 'PUT' &&
              actionMatch.group(4) != null) {
            final result = await SupabaseService.instance.toggleReaction(
                msgId, Uri.decodeComponent(actionMatch.group(4)!));
            return handler.resolve(Response(
                requestOptions: options, statusCode: 200, data: result));
          }
          if (action == 'pin' && ['PUT', 'POST', 'DELETE'].contains(method)) {
            final result = await SupabaseService.instance
                .setMessagePinned(msgId, method != 'DELETE');
            return handler.resolve(Response(
                requestOptions: options, statusCode: 200, data: result));
          }
          if (action == null && method == 'PUT') {
            final content = (options.data as Map)['content']?.toString() ?? '';
            await SupabaseService.instance.editMessage(msgId, content);
            return handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {'id': msgId, 'content': content}));
          }
          if (action == null && method == 'DELETE') {
            await SupabaseService.instance.deleteMessage(msgId);
            return handler
                .resolve(Response(requestOptions: options, statusCode: 204));
          }
        }

        final convMessagesMatch =
            BridgeRoutes.messageCollection.firstMatch(path);
        if (convMessagesMatch != null && ['GET', 'POST'].contains(method)) {
          final convId = convMessagesMatch.group(1)!;
          if (method == 'POST') {
            final data = options.data is Map
                ? Map<String, dynamic>.from(options.data)
                : <String, dynamic>{};
            final msg = await SupabaseService.instance.sendMessage(
              conversationId: convId,
              content: data['content']?.toString() ?? '',
              messageType: data['message_type']?.toString() ?? 'text',
              parentId: data['parent_id']?.toString(),
              metadata: data['metadata_json'] is Map
                  ? Map<String, dynamic>.from(data['metadata_json'])
                  : null,
            );
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: msg,
            ));
          } else {
            final msgs =
                await SupabaseService.instance.getConversationMessages(convId);
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: msgs,
            ));
          }
        }

        // 4. /messaging/conversations/:id (GET single conversation detail)
        final convDetailMatch =
            RegExp(r'/messaging/conversations/([^/]+)$').firstMatch(path);
        if (convDetailMatch != null && method == 'GET') {
          final convId = convDetailMatch.group(1)!;
          final detail =
              await SupabaseService.instance.getConversationDetail(convId);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: detail,
          ));
        }

        // 5. /messaging/conversations (GET all conversations, POST create new conversation)
        if (path.endsWith('/messaging/conversations') ||
            path == '/messaging/conversations' ||
            path.endsWith('/conversations') ||
            path == '/conversations') {
          if (method == 'POST') {
            final data = options.data is Map
                ? Map<String, dynamic>.from(options.data)
                : <String, dynamic>{};
            final newConv =
                await SupabaseService.instance.createConversation(data);
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: newConv,
            ));
          } else {
            final convs = await SupabaseService.instance.getConversations();
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: convs,
            ));
          }
        }

        // 6. /messaging/messages/:id/reactions (POST reaction, DELETE reaction)
        final reactionMatch =
            RegExp(r'/messaging/messages/([^/]+)/reactions').firstMatch(path);
        if (reactionMatch != null) {
          final msgId = reactionMatch.group(1)!;
          final emoji =
              options.data is Map ? options.data['emoji']?.toString() : null;
          if (method == 'POST' && emoji != null) {
            await SupabaseService.instance.addReaction(msgId, emoji);
          } else if (method == 'DELETE') {
            await SupabaseService.instance.removeReaction(msgId, emoji);
          }
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'status': 'ok'},
          ));
        }

        // 7. /messaging/messages/:id/pin (POST toggle pin)
        final pinMatch =
            RegExp(r'/messaging/messages/([^/]+)/pin').firstMatch(path);
        if (pinMatch != null) {
          final msgId = pinMatch.group(1)!;
          await SupabaseService.instance.togglePinMessage(msgId);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'status': 'ok'},
          ));
        }

        // 8. /messaging/messages/:id (PUT edit message, DELETE delete message)
        final msgActionMatch =
            RegExp(r'/messaging/messages/([^/]+)$').firstMatch(path);
        if (msgActionMatch != null) {
          final msgId = msgActionMatch.group(1)!;
          if (method == 'PUT') {
            final newContent = options.data is Map
                ? options.data['content']?.toString() ?? ''
                : '';
            await SupabaseService.instance.editMessage(msgId, newContent);
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'status': 'ok', 'id': msgId, 'content': newContent},
            ));
          } else if (method == 'DELETE') {
            await SupabaseService.instance.deleteMessage(msgId);
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'status': 'ok'},
            ));
          }
        }

        // 9. Group lifecycle, roles, and membership.
        if (path == '/groups') {
          final data = options.data is Map
              ? Map<String, dynamic>.from(options.data)
              : <String, dynamic>{};
          final result = method == 'GET'
              ? await SupabaseService.instance.getGroups()
              : method == 'POST'
                  ? await SupabaseService.instance.createGroup(data)
                  : null;
          if (result != null) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: method == 'POST' ? 201 : 200,
              data: result,
            ));
          }
        }

        final groupInviteMatch =
            RegExp(r'^/groups/invites/([^/]+)$').firstMatch(path);
        if (groupInviteMatch != null && method == 'GET') {
          final invite = await SupabaseService.instance
              .getGroupInvite(groupInviteMatch.group(1)!);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: invite,
          ));
        }
        final groupInviteAcceptMatch =
            RegExp(r'^/groups/invites/([^/]+)/accept$').firstMatch(path);
        if (groupInviteAcceptMatch != null && method == 'POST') {
          final invite = await SupabaseService.instance
              .acceptGroupInvite(groupInviteAcceptMatch.group(1)!);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: invite,
          ));
        }

        final groupInviteCreateMatch =
            RegExp(r'^/groups/([^/]+)/invites$').firstMatch(path);
        if (groupInviteCreateMatch != null && method == 'POST') {
          final data = options.data is Map
              ? Map<String, dynamic>.from(options.data)
              : <String, dynamic>{};
          final invite = await SupabaseService.instance.createGroupInvite(
            groupInviteCreateMatch.group(1)!,
            expiresHours:
                int.tryParse(data['expires_hours']?.toString() ?? '') ?? 24,
            maxUses: int.tryParse(data['max_uses']?.toString() ?? '') ?? 1,
          );
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 201,
            data: invite,
          ));
        }

        final groupUserInviteMatch =
            RegExp(r'^/groups/([^/]+)/invite-user$').firstMatch(path);
        if (groupUserInviteMatch != null && method == 'POST') {
          final data = options.data is Map
              ? Map<String, dynamic>.from(options.data)
              : <String, dynamic>{};
          final invite = await SupabaseService.instance
              .inviteGroupUser(groupUserInviteMatch.group(1)!, data);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 201,
            data: invite,
          ));
        }

        final groupInvitationResponseMatch =
            RegExp(r'^/groups/([^/]+)/invitations/respond$').firstMatch(path);
        if (groupInvitationResponseMatch != null && method == 'POST') {
          final data = options.data is Map
              ? Map<String, dynamic>.from(options.data)
              : <String, dynamic>{};
          final invitation =
              await SupabaseService.instance.respondGroupInvitation(
            groupInvitationResponseMatch.group(1)!,
            data['action']?.toString() ?? '',
            data['notification_id']?.toString(),
          );
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: invitation,
          ));
        }

        final groupMatch = RegExp(r'^/groups/([^/]+)$').firstMatch(path);
        if (groupMatch != null && method == 'DELETE') {
          await SupabaseService.instance.deleteGroup(groupMatch.group(1)!);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 204,
          ));
        }
        if (groupMatch != null && (method == 'GET' || method == 'PUT')) {
          final data = options.data is Map
              ? Map<String, dynamic>.from(options.data)
              : <String, dynamic>{};
          final group = method == 'GET'
              ? await SupabaseService.instance.getGroup(groupMatch.group(1)!)
              : await SupabaseService.instance
                  .updateGroup(groupMatch.group(1)!, data);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: group,
          ));
        }

        final groupRolesMatch =
            RegExp(r'^/groups/([^/]+)/roles$').firstMatch(path);
        if (groupRolesMatch != null) {
          final groupId = groupRolesMatch.group(1)!;
          final data = options.data is Map
              ? Map<String, dynamic>.from(options.data)
              : <String, dynamic>{};
          final roles = method == 'GET'
              ? await SupabaseService.instance.getGroupRoles(groupId)
              : method == 'POST'
                  ? await SupabaseService.instance
                      .createGroupRole(groupId, data)
                  : null;
          if (roles != null) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: method == 'POST' ? 201 : 200,
              data: roles,
            ));
          }
        }

        final groupRoleMatch =
            RegExp(r'^/groups/([^/]+)/roles/([^/]+)$').firstMatch(path);
        if (groupRoleMatch != null) {
          final groupId = groupRoleMatch.group(1)!;
          final roleId = groupRoleMatch.group(2)!;
          if (method == 'PUT') {
            final data = options.data is Map
                ? Map<String, dynamic>.from(options.data)
                : <String, dynamic>{};
            final role = await SupabaseService.instance
                .updateGroupRole(groupId, roleId, data);
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: role,
            ));
          }
          if (method == 'DELETE') {
            await SupabaseService.instance.deleteGroupRole(groupId, roleId,
                fallbackRoleId:
                    options.queryParameters['fallback_role_id']?.toString());
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 204,
            ));
          }
        }

        final groupMembersMatch =
            RegExp(r'^/groups/([^/]+)/members$').firstMatch(path);
        if (groupMembersMatch != null) {
          final groupId = groupMembersMatch.group(1)!;
          if (method == 'GET') {
            final members =
                await SupabaseService.instance.getGroupMembers(groupId);
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'items': members, 'total': members.length},
            ));
          }
          if (method == 'POST') {
            final data = options.data is Map
                ? Map<String, dynamic>.from(options.data)
                : <String, dynamic>{};
            final group = await SupabaseService.instance.addGroupMembers(
              groupId,
              List<dynamic>.from(data['user_ids'] ?? const <dynamic>[]),
              roleId: data['role_id']?.toString(),
            );
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: group,
            ));
          }
        }

        final groupMemberRoleMatch =
            RegExp(r'^/groups/([^/]+)/members/([^/]+)/role$').firstMatch(path);
        if (groupMemberRoleMatch != null && method == 'PUT') {
          final data = options.data is Map
              ? Map<String, dynamic>.from(options.data)
              : <String, dynamic>{};
          final member = await SupabaseService.instance.assignGroupMemberRole(
            groupMemberRoleMatch.group(1)!,
            groupMemberRoleMatch.group(2)!,
            data['role_id'].toString(),
          );
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: member,
          ));
        }

        final groupMemberMatch =
            RegExp(r'^/groups/([^/]+)/members/([^/]+)$').firstMatch(path);
        if (groupMemberMatch != null && method == 'DELETE') {
          await SupabaseService.instance.removeGroupMember(
            groupMemberMatch.group(1)!,
            groupMemberMatch.group(2)!,
          );
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 204,
          ));
        }

        // 10. /notifications/unread-count
        if (method == 'GET' && path == '/notifications/unread-count') {
          final prefs = await SharedPreferences.getInstance();
          final spId = prefs.getString('sp_user_id');
          int count = 0;
          if (spId != null) {
            final res = await SupabaseService.instance.client
                .from('notification_items')
                .select('id')
                .eq('user_id', spId)
                .eq('is_read', false);
            count = res.length;
          }
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'count': count},
          ));
        }

        // 12. /notifications
        if (method == 'GET' && path == '/notifications') {
          final spId = SupabaseService.instance.client.auth.currentUser?.id;
          List<Map<String, dynamic>> items = [];
          if (spId != null) {
            final res = await SupabaseService.instance.client
                .from('notification_items')
                .select()
                .eq('user_id', spId)
                .order('created_at', ascending: false)
                .limit(50);
            items = List<Map<String, dynamic>>.from(res);
          }
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: items,
          ));
        }

        final notificationReadMatch =
            RegExp(r'^/notifications/([^/]+)/read$').firstMatch(path);
        if (method == 'PUT' && notificationReadMatch != null) {
          await SupabaseService.instance.client
              .from('notification_items')
              .update({
            'is_read': true,
            'updated_at': DateTime.now().toUtc().toIso8601String()
          }).eq('id', notificationReadMatch.group(1)!);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'status': 'ok'},
          ));
        }

        final conversationNotificationsMatch =
            RegExp(r'^/notifications/conversation/([^/]+)/read$')
                .firstMatch(path);
        if (method == 'PUT' && conversationNotificationsMatch != null) {
          await SupabaseService.instance
              .markConversationRead(conversationNotificationsMatch.group(1)!);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'status': 'ok'},
          ));
        }

        if (method == 'PUT' && path == '/notifications/read-all') {
          final userId = SupabaseService.instance.client.auth.currentUser!.id;
          await SupabaseService.instance.client
              .from('notification_items')
              .update({
            'is_read': true,
            'updated_at': DateTime.now().toUtc().toIso8601String()
          }).eq('user_id', userId);
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'status': 'ok'},
          ));
        }

        // 13. /presence / /presence/heartbeat
        if (path.contains('/presence')) {
          if (method == 'POST') {
            final spId = SupabaseService.instance.client.auth.currentUser?.id;
            if (spId != null) {
              final data = options.data is Map
                  ? Map<String, dynamic>.from(options.data)
                  : const <String, dynamic>{};
              final status = data['status']?.toString().trim();
              await SupabaseService.instance.client.from('users').update({
                'presence_status':
                    status == null || status.isEmpty ? 'online' : status,
                'last_active_at': DateTime.now().toUtc().toIso8601String(),
              }).eq('id', spId);
            }
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'status': 'ok'},
            ));
          } else {
            final users = await SupabaseService.instance.client
                .from('users')
                .select('id, presence_status, last_active_at');
            final Map<String, dynamic> usersMap = {};
            for (final u in users) {
              usersMap[u['id'].toString()] = {
                ...Map<String, dynamic>.from(u),
                'status': effectivePresenceStatus(Map<String, dynamic>.from(u)),
                'last_seen_at': u['last_active_at'],
              };
            }
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'users': usersMap},
            ));
          }
        }

        // 14. /auth/me -> current Supabase profile
        if (path.endsWith('/auth/me')) {
          final user = await SupabaseService.instance.getCurrentUserProfile();
          if (user != null) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: user,
            ));
          }
        }
      } catch (e) {
        debugPrint(
            '[SupabaseBridge] Direct onRequest handling error for $path: $e');
        // Do not retry a failed cloud write against a different database.
        return handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          response: e is PostgrestException && e.code == '42501'
              ? Response(requestOptions: options, statusCode: 403)
              : null,
          error: e,
          message: 'The request could not be completed. Please try again.',
        ));
      }
    }

    final status = SupabaseService.instance.hasSession ? 501 : 401;
    final message = status == 401
        ? 'Please sign in to continue.'
        : 'This action is not available in KryinTalk cloud yet.';
    handler.reject(DioException(
      requestOptions: options,
      response: Response(
          requestOptions: options,
          statusCode: status,
          data: {'message': message}),
      type: DioExceptionType.badResponse,
      message: message,
    ));
  }
}
