/// ConnectHub — Supabase Client & Realtime Data Engine.
///
/// Direct client integration for Serverless Supabase Backend.
/// Project ID: mujhkmuhlmuqbansrdwp
library;

import 'dart:async';
import '../auth/callback_history.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const callbackOrigin = String.fromEnvironment('AUTH_CALLBACK_ORIGIN',
      defaultValue: 'https://kryintalks.vercel.app');
  static const adminContactEmail =
      String.fromEnvironment('KRYINTALK_ADMIN_CONTACT_EMAIL');
  static String get callbackUrl => '$callbackOrigin/auth/callback';
  SupabaseConfig._();

  static const String projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mujhkmuhlmuqbansrdwp.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_DynSSVBOhrg7pIwspvUT8w_ebavdq28',
  );
}

class SupabaseService {
  static bool initialCallback = false;
  static bool callbackSucceeded = false;
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  void Function()? onAccessDenied;
  int _cacheEpoch = 0;
  void _reportDataError(Object error) {
    if (error is PostgrestException && error.code == '42501')
      onAccessDenied?.call();
  }

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  bool get hasSession => _isInitialized && client.auth.currentSession != null;

  SupabaseClient get client => Supabase.instance.client;

  /// Returns the current profile with authority derived server-side from
  /// user_roles and roles. Never read a nonexistent users.role column.
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    if (!hasSession) return null;
    final result = await client.rpc('get_current_user_profile');
    if (result is! Map) return null;
    final profile = Map<String, dynamic>.from(result)..remove('password_hash');
    final authUser = client.auth.currentUser;
    if (profile['id']?.toString() != authUser?.id ||
        profile['email']?.toString().toLowerCase() !=
            authUser?.email?.toLowerCase()) {
      debugPrint('[Supabase] Auth account and profile identity do not match');
      return null;
    }
    return profile;
  }

  /// Initialize Supabase Client at App Startup.
  static Future<void> initialize() async {
    if (instance._isInitialized) return;
    final callbackUri = Uri.base;
    initialCallback = callbackUri.path == '/auth/callback' ||
        callbackUri.fragment.startsWith('/auth/callback');
    try {
      await Supabase.initialize(
        url: SupabaseConfig.projectUrl,
        publishableKey: SupabaseConfig.anonKey,
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            detectSessionInUri: false, authFlowType: AuthFlowType.implicit),
      );
      instance._isInitialized = true;
      if (initialCallback) {
        final temporary = SupabaseClient(
            SupabaseConfig.projectUrl, SupabaseConfig.anonKey,
            authOptions: const AuthClientOptions(
                authFlowType: AuthFlowType.implicit, autoRefreshToken: false));
        try {
          final result = await temporary.auth.getSessionFromUrl(callbackUri);
          callbackSucceeded = result.redirectType == 'signup' &&
              result.session.user.emailConfirmedAt != null;
          await temporary.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          callbackSucceeded = false;
        } finally {
          await temporary.dispose();
          clearCallbackHistory();
        }
      }
      debugPrint(
          '[Supabase] Initialized successfully with ${SupabaseConfig.projectUrl}');
    } catch (e) {
      instance._reportDataError(e);
      debugPrint('[Supabase] Init error: $e');
    }
  }

  // ── Auth Methods ────────────────────────────

  Future<Map<String, dynamic>?> signIn(
      {required String email, required String password}) async {
    final response = await client.auth
        .signInWithPassword(email: email.trim(), password: password);
    if (response.session == null) return null;
    return {'id': response.user?.id};
  }

  Future<Map<String, dynamic>?> signUp(
      {required String email,
      required String username,
      required String displayName,
      required String password}) async {
    final response = await client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: SupabaseConfig.callbackUrl,
        data: {
          'username': username,
          'display_name': displayName.trim(),
          'agreement': true,
          'policy_version': '2026-09-26',
        });
    if (response.user == null)
      throw const AuthException('Registration unavailable');
    // Even when server confirmation settings change, signup never logs into chats.
    if (response.session != null)
      await client.auth.signOut(scope: SignOutScope.local);
    return {'_requires_confirmation': true};
  }

  Future<void> resendConfirmation(String email) => client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: SupabaseConfig.callbackUrl);

  Future<Map<String, dynamic>> updateCurrentProfile(
          Map<String, dynamic> changes) async =>
      Map<String, dynamic>.from(
          await client.rpc('update_kryintalk_profile', params: {
        'p_display_name': changes['display_name'],
        'p_username': changes['username'],
        'p_hide_from_dm': changes['hide_from_dm'],
      }) as Map);

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw StateError(
          'Your signed-in email is unavailable. Please sign in again.');
    }
    await client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  // ── Realtime Messaging ──────────────────────

  /// Fetch Messages for a conversation
  Future<List<Map<String, dynamic>>> getMessages(String conversationId,
      {int limit = 50}) async {
    try {
      final data = await client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: true)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] getMessages error: $e');
      return [];
    }
  }

  /// Send Message to a conversation
  Future<Map<String, dynamic>?> sendMessage({
    required String conversationId,
    String? senderId,
    required String content,
    String messageType = 'text',
    String? parentId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final res = await client.rpc('send_conversation_message', params: {
        'p_conversation_id': conversationId,
        'p_content': content,
        'p_message_type': messageType,
        'p_parent_id': parentId,
        'p_metadata': metadata ?? <String, dynamic>{},
      });
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] sendMessage error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> requestFriendship(String userId) async {
    final result = await client.rpc(
      'request_friendship',
      params: {'p_addressee_id': userId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> respondToFriendship(
    String friendshipId, {
    required bool accept,
  }) async {
    final result = await client.rpc(
      'respond_to_friendship',
      params: {'p_friendship_id': friendshipId, 'p_accept': accept},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> removeFriendship(String friendshipId) async {
    await client.rpc(
      'remove_friendship',
      params: {'p_friendship_id': friendshipId},
    );
  }

  Future<Map<String, dynamic>> blockUser(String userId) async {
    final result =
        await client.rpc('block_user', params: {'p_user_id': userId});
    return Map<String, dynamic>.from(result as Map);
  }

  /// Subscribe to Realtime messages for a conversation
  RealtimeChannel subscribeToConversation({
    required String conversationId,
    required void Function(Map<String, dynamic> newMessage) onMessage,
  }) {
    final channel = client.channel('public:messages:$conversationId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            onMessage(payload.newRecord);
          },
        )
        .subscribe();

    return channel;
  }

  // ── High Performance Memory Caches ───────────────────────
  static List<Map<String, dynamic>>? _cachedUsers;
  static Map<String, Map<String, dynamic>> _cachedUsersMap = {};
  static DateTime? _usersCacheTime;

  static List<Map<String, dynamic>>? _cachedConversations;
  static DateTime? _conversationsCacheTime;

  /// Invalidate conversation cache
  void invalidateConversationsCache() {
    ++_cacheEpoch;
    _cachedConversations = null;
  }

  /// Invalidate user cache
  void invalidateUsersCache() {
    ++_cacheEpoch;
    _cachedUsers = null;
    _cachedUsersMap.clear();
  }

  /// Fetch all users / directory from Supabase (Cached in memory with 5-minute TTL)
  Future<List<Map<String, dynamic>>> getUsers(
      {bool forceRefresh = false}) async {
    final epoch = _cacheEpoch;
    if (!forceRefresh &&
        _cachedUsers != null &&
        _usersCacheTime != null &&
        DateTime.now().difference(_usersCacheTime!).inMinutes < 5) {
      return _cachedUsers!;
    }
    try {
      final data = await client
          .from('users')
          .select(
              'id, username, display_name, email, avatar_url, presence_status, last_login_at')
          .isFilter('deleted_at', null)
          .order('display_name');
      final list = List<Map<String, dynamic>>.from(data);
      if (epoch != _cacheEpoch) return [];
      _cachedUsers = list;
      _cachedUsersMap = {
        for (final u in list) u['id'].toString().trim().toLowerCase(): u,
      };
      _usersCacheTime = DateTime.now();
      return list;
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] getUsers error: $e');
      return _cachedUsers ?? [];
    }
  }

  /// Get cached users map for instant O(1) user profile lookups
  Future<Map<String, Map<String, dynamic>>> getUsersMap(
      {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedUsersMap.isNotEmpty &&
        _usersCacheTime != null &&
        DateTime.now().difference(_usersCacheTime!).inMinutes < 5) {
      return _cachedUsersMap;
    }
    final epoch = _cacheEpoch;
    await getUsers(forceRefresh: forceRefresh);
    return epoch == _cacheEpoch ? _cachedUsersMap : {};
  }

  Future<Map<String, dynamic>?> getUserById(String userId) async {
    final epoch = _cacheEpoch;
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty) return null;
    final cached = _cachedUsersMap[normalizedId.toLowerCase()];
    if (cached != null) return cached;
    final result = await client
        .from('users')
        .select(
            'id, username, display_name, email, avatar_url, presence_status, last_login_at')
        .eq('id', normalizedId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (result == null || epoch != _cacheEpoch) return null;
    final user = Map<String, dynamic>.from(result);
    _cachedUsersMap[normalizedId.toLowerCase()] = user;
    return user;
  }

  /// Fetch all conversations enriched with participants, recipient info, and last message in parallel
  Future<List<Map<String, dynamic>>> getConversations(
      {String? currentUserId, bool forceRefresh = false}) async {
    final epoch = _cacheEpoch;
    if (!forceRefresh &&
        _cachedConversations != null &&
        _conversationsCacheTime != null &&
        DateTime.now().difference(_conversationsCacheTime!).inSeconds < 8) {
      return _cachedConversations!;
    }
    try {
      String? myId = currentUserId;
      if (myId == null || myId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        myId = prefs.getString('sp_user_id') ?? prefs.getString('user_id');
      }
      // The bridge often calls this method without an explicit id. Always
      // fall back to the authenticated Supabase user before resolving the
      // "other" participant, otherwise the first participant (the signed-in
      // account) is incorrectly displayed as every DM recipient.
      myId ??= client.auth.currentUser?.id;
      myId = myId?.trim().toLowerCase();

      // Execute all 4 queries in parallel
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        client
            .from('conversations')
            .select()
            .order('updated_at', ascending: false),
        client.from('conversation_participants').select(),
        getUsersMap(),
        client
            .from('messages')
            .select()
            .order('created_at', ascending: false)
            .limit(80),
        getConversationState(),
      ]);

      final convData = results[0] as List<dynamic>;
      final partData = results[1] as List<dynamic>;
      final usersMap = results[2] as Map<String, Map<String, dynamic>>;
      final msgsData = results[3] as List<dynamic>;
      final stateRows = results[4] as List<Map<String, dynamic>>;

      if (convData.isEmpty) return [];

      final partsByConv = <String, List<Map<String, dynamic>>>{};
      for (final p in partData) {
        final cid = p['conversation_id']?.toString().toLowerCase() ?? '';
        partsByConv
            .putIfAbsent(cid, () => [])
            .add(Map<String, dynamic>.from(p));
      }

      final lastMsgByConv = <String, Map<String, dynamic>>{};
      for (final m in msgsData) {
        final cid = m['conversation_id']?.toString().toLowerCase() ?? '';
        if (!lastMsgByConv.containsKey(cid)) {
          lastMsgByConv[cid] = Map<String, dynamic>.from(m);
        }
      }

      final stateByConv = {
        for (final state in stateRows)
          state['conversation_id']?.toString().toLowerCase(): state,
      };

      final List<Map<String, dynamic>> enriched = [];

      for (final c in convData) {
        final cid = c['id']?.toString().toLowerCase() ?? '';
        final convParts = partsByConv[cid] ?? [];

        final List<Map<String, dynamic>> participantDetails = [];
        Map<String, dynamic>? otherUser;

        for (final p in convParts) {
          final uid = p['user_id']?.toString().toLowerCase() ?? '';
          final u = usersMap[uid];
          if (u != null) {
            participantDetails.add(u);
            if (uid != myId?.toLowerCase() && otherUser == null) {
              otherUser = u;
            }
          }
        }

        if (otherUser == null && participantDetails.isNotEmpty) {
          otherUser = participantDetails.first;
        }

        final lastMsg = lastMsgByConv[cid];
        final state = stateByConv[cid];
        final convType =
            (c['conversation_type']?.toString().toLowerCase() ?? 'direct');

        final recipientName = otherUser != null
            ? (otherUser['display_name']?.toString() ??
                otherUser['username']?.toString() ??
                'User')
            : (c['name'] ?? c['title'] ?? 'Direct Message');

        final recipientUsername =
            otherUser != null ? (otherUser['username']?.toString() ?? '') : '';
        final recipientAvatar = otherUser != null
            ? (otherUser['avatar_url']?.toString() ?? '')
            : '';
        final recipientPresence = otherUser != null
            ? (otherUser['presence_status']?.toString() ?? 'offline')
            : 'offline';

        Map<String, dynamic>? enrichedLastMsg;
        if (lastMsg != null) {
          final senderId = lastMsg['sender_id']?.toString().toLowerCase();
          final senderUser = senderId != null ? usersMap[senderId] : null;
          final senderName = senderUser != null
              ? (senderUser['display_name']?.toString() ??
                  senderUser['username']?.toString() ??
                  'Member')
              : 'Member';
          enrichedLastMsg = {
            ...lastMsg,
            'sender_name': senderName,
            'sender_username': senderUser?['username'] ?? '',
          };
        }

        enriched.add({
          ...Map<String, dynamic>.from(c),
          'type': convType,
          'conversation_type': convType,
          'participants': convParts,
          'participant_details': participantDetails,
          'recipient_id': otherUser?['id']?.toString(),
          'recipient_name': recipientName,
          'recipient_username': recipientUsername,
          'recipient_avatar_url': recipientAvatar,
          'recipient_presence': recipientPresence,
          'display_name': recipientName,
          'title': recipientName,
          'name': recipientName,
          'last_message': enrichedLastMsg ?? lastMsg,
          'last_message_content': lastMsg?['content'],
          'last_message_preview': lastMsg?['content'],
          'last_message_time': lastMsg?['created_at'] ?? c['updated_at'],
          'unread_count': state?['unread_count'] ?? 0,
          'is_muted': state?['is_muted'] ?? false,
          'is_archived': state?['is_archived'] ?? false,
          'notifications_enabled': state?['notifications_enabled'] ?? true,
        });
      }

      if (epoch != _cacheEpoch) return [];
      _cachedConversations = enriched;
      _conversationsCacheTime = DateTime.now();
      return enriched;
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] getConversations error: $e');
      return _cachedConversations ?? [];
    }
  }

  /// Fetch all groups for an organization
  Future<List<Map<String, dynamic>>> getGroups() async {
    try {
      final data = await client.rpc('list_kryintalk_groups');
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] getGroups error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getGroup(String groupId) async =>
      Map<String, dynamic>.from(await client.rpc('kryintalk_group_summary',
          params: {'p_group_id': groupId}) as Map);

  Future<Map<String, dynamic>> createGroup(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(
          await client.rpc('create_kryintalk_group', params: {
        'p_name': data['name'],
        'p_slug': data['slug'],
        'p_description': data['description'],
        'p_icon': data['icon'],
        'p_color': data['color'],
        'p_visibility': data['visibility'] ??
            (data['is_private'] == false ? 'organization' : 'private'),
        'p_is_view_only': data['is_view_only'] == true,
        'p_only_admin_invites': data['only_admin_invites'] != false,
        'p_member_ids': data['member_ids'] ?? <String>[],
      }) as Map);

  Future<Map<String, dynamic>> updateGroup(
          String groupId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(await client.rpc('update_kryintalk_group',
          params: {'p_group_id': groupId, 'p_changes': data}) as Map);

  Future<void> deleteGroup(String groupId) =>
      client.rpc('delete_kryintalk_group', params: {'p_group_id': groupId});

  Future<List<Map<String, dynamic>>> getGroupRoles(String groupId) async =>
      List<Map<String, dynamic>>.from(await client
              .rpc('get_kryintalk_group_roles', params: {'p_group_id': groupId})
          as List);

  Future<Map<String, dynamic>> createGroupRole(
          String groupId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(
          await client.rpc('create_kryintalk_group_role', params: {
        'p_group_id': groupId,
        'p_name': data['name'],
        'p_color': data['color'],
        'p_description': data['description'],
        'p_permissions': data['permissions'],
        'p_is_default': data['is_default'] == true,
      }) as Map);

  Future<Map<String, dynamic>> updateGroupRole(
          String groupId, String roleId, Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(await client.rpc('update_kryintalk_group_role',
          params: {
            'p_group_id': groupId,
            'p_role_id': roleId,
            'p_changes': data
          }) as Map);

  Future<void> deleteGroupRole(String groupId, String roleId,
          {String? fallbackRoleId}) =>
      client.rpc('delete_kryintalk_group_role', params: {
        'p_group_id': groupId,
        'p_role_id': roleId,
        'p_fallback_role_id': fallbackRoleId
      });

  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async =>
      List<Map<String, dynamic>>.from(await client.rpc(
          'get_kryintalk_group_members',
          params: {'p_group_id': groupId}) as List);

  Future<Map<String, dynamic>> addGroupMembers(
          String groupId, List<dynamic> userIds, {String? roleId}) async =>
      Map<String, dynamic>.from(await client.rpc('add_kryintalk_group_members',
          params: {
            'p_group_id': groupId,
            'p_user_ids': userIds,
            'p_role_id': roleId
          }) as Map);

  Future<Map<String, dynamic>> assignGroupMemberRole(
          String groupId, String userId, String roleId) async =>
      Map<String, dynamic>.from(await client
          .rpc('assign_kryintalk_group_member_role', params: {
        'p_group_id': groupId,
        'p_user_id': userId,
        'p_role_id': roleId
      }) as Map);

  Future<void> removeGroupMember(String groupId, String userId) =>
      client.rpc('remove_kryintalk_group_member',
          params: {'p_group_id': groupId, 'p_user_id': userId});

  Future<Map<String, dynamic>> findOrCreateGroupConversation(
      String groupId) async {
    final result = await client.rpc(
        'find_or_create_kryintalk_group_conversation',
        params: {'p_group_id': groupId});
    invalidateConversationsCache();
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> createGroupInvite(String groupId,
          {int expiresHours = 24, int maxUses = 1}) async =>
      Map<String, dynamic>.from(
          await client.rpc('create_kryintalk_group_invite', params: {
        'p_group_id': groupId,
        'p_expires_hours': expiresHours,
        'p_max_uses': maxUses,
      }) as Map);

  Future<Map<String, dynamic>> getGroupInvite(String token) async =>
      Map<String, dynamic>.from(await client.rpc('get_kryintalk_group_invite',
          params: {'p_token': token}) as Map);

  Future<Map<String, dynamic>> acceptGroupInvite(String token) async =>
      Map<String, dynamic>.from(await client
              .rpc('accept_kryintalk_group_invite', params: {'p_token': token})
          as Map);

  Future<Map<String, dynamic>> inviteGroupUser(
      String groupId, Map<String, dynamic> data) async {
    var userId = data['user_id']?.toString().trim();
    if (userId == null || userId.isEmpty) {
      final username =
          data['username']?.toString().trim().replaceFirst('@', '');
      final users = await getUsers();
      for (final user in users) {
        if (user['username']?.toString().toLowerCase() ==
            username?.toLowerCase()) {
          userId = user['id']?.toString();
          break;
        }
      }
    }
    if (userId == null || userId.isEmpty) throw StateError('User not found.');
    return Map<String, dynamic>.from(
        await client.rpc('invite_kryintalk_group_user', params: {
      'p_group_id': groupId,
      'p_user_id': userId,
      'p_role_id': data['role_id'],
    }) as Map);
  }

  Future<Map<String, dynamic>> respondGroupInvitation(
          String groupId, String action, String? notificationId) async =>
      Map<String, dynamic>.from(
          await client.rpc('respond_kryintalk_group_invitation', params: {
        'p_group_id': groupId,
        'p_action': action,
        'p_notification_id': notificationId,
      }) as Map);

  // ── File Storage ────────────────────────────

  /// Helper to determine MIME type from filename
  static String getContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return 'text/markdown';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.apk')) {
      return 'application/vnd.android.package-archive';
    }
    return 'application/octet-stream';
  }

  /// Upload file to Supabase Storage
  Future<String?> uploadFile({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      await client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true,
            ),
          );
      // Attachments are stored in a private bucket. Return a short-lived
      // signed URL for the immediate message/file response; callers refresh
      // it from storage_path when loading later.
      return await createSignedUrl(bucket: bucket, path: path);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] uploadFile error: $e');
      return null;
    }
  }

  /// Create a short-lived URL for a private storage object.
  Future<String?> createSignedUrl({
    required String bucket,
    required String path,
    int expiresIn = 60,
  }) async {
    try {
      return await client.storage.from(bucket).createSignedUrl(path, expiresIn);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] createSignedUrl error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _resolveMessageAttachment(dynamic raw) async {
    final message = Map<String, dynamic>.from(raw as Map);
    final metadata = message['metadata_json'] is Map
        ? Map<String, dynamic>.from(message['metadata_json'] as Map)
        : <String, dynamic>{};
    final rawUrl = message['attachment_url']?.toString() ??
        metadata['file_url']?.toString() ??
        metadata['public_url']?.toString() ??
        '';
    final storagePath = metadata['storage_path']?.toString().isNotEmpty == true
        ? metadata['storage_path'].toString()
        : _storagePathFromUrl(rawUrl);
    if (storagePath == null || storagePath.isEmpty) return message;

    final signedUrl = await createSignedUrl(
      bucket: 'attachments',
      path: storagePath,
    );
    if (signedUrl == null || signedUrl.isEmpty) return message;

    message['attachment_url'] = signedUrl;
    metadata['file_url'] = signedUrl;
    metadata['public_url'] = signedUrl;
    metadata['storage_path'] = storagePath;
    message['metadata_json'] = metadata;
    return message;
  }

  /// Resolve an attachment URL on a realtime message before it is rendered.
  Future<Map<String, dynamic>> resolveMessageAttachment(dynamic raw) {
    return _resolveMessageAttachment(raw);
  }

  static String? _storagePathFromUrl(String rawUrl) {
    if (rawUrl.isEmpty) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return null;
    const markers = [
      '/storage/v1/object/public/attachments/',
      '/storage/v1/object/sign/attachments/',
    ];
    for (final marker in markers) {
      final index = uri.path.indexOf(marker);
      if (index >= 0) {
        final encodedPath = uri.path.substring(index + marker.length);
        return Uri.decodeComponent(encodedPath);
      }
    }
    return null;
  }

  /// Record file attachment in public.file_attachments table
  Future<void> recordFileAttachment({
    required String conversationId,
    required String uploaderId,
    required String filename,
    required int sizeBytes,
    required String storagePath,
    required String publicUrl,
    required String contentType,
  }) async {
    await client.from('file_attachments').insert({
      'conversation_id': conversationId,
      'uploader_id': uploaderId,
      'original_filename': filename,
      'stored_filename': storagePath,
      'content_type': contentType,
      'size_bytes': sizeBytes,
      'storage_path': storagePath,
      'public_url': publicUrl,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ── Messaging & Realtime Chat Operations ────────────────────────────

  /// Fetch all messages for a conversation with sender details and reactions (Ultra-fast parallel query)
  Future<List<Map<String, dynamic>>> getConversationMessages(
      String conversationId) async {
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        client
            .from('messages')
            .select()
            .eq('conversation_id', conversationId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: true),
        getUsersMap(),
      ]);

      final msgsData = results[0] as List<dynamic>;
      final usersMap = results[1] as Map<String, Map<String, dynamic>>;

      if (msgsData.isEmpty) return [];

      // Private storage URLs expire, so refresh attachment links while the
      // message batch is loaded instead of persisting a stale signed URL.
      final resolvedMessages = await Future.wait<Map<String, dynamic>>(
        msgsData.map(_resolveMessageAttachment),
      );

      final msgIds = resolvedMessages.map((m) => m['id'].toString()).toList();

      // Targeted reactions query only for this conversation's messages
      List<dynamic> reactionsData = [];
      if (msgIds.isNotEmpty) {
        reactionsData = await client
            .from('message_reactions')
            .select()
            .inFilter('message_id', msgIds);
      }

      final reactionsByMsg = <String, List<Map<String, dynamic>>>{};
      final currentUserId = client.auth.currentUser?.id;
      for (final r in reactionsData) {
        final mid = r['message_id']?.toString() ?? '';
        reactionsByMsg
            .putIfAbsent(mid, () => [])
            .add(Map<String, dynamic>.from(r));
      }

      final List<Map<String, dynamic>> enriched = [];
      for (final m in resolvedMessages) {
        final mid = m['id']?.toString() ?? '';
        final senderId = m['sender_id']?.toString().trim().toLowerCase();
        final senderUser = senderId != null ? usersMap[senderId] : null;

        final rawReactions = reactionsByMsg[mid] ?? [];
        final Map<String, List<String>> reactionsMap = {};
        for (final r in rawReactions) {
          final emoji = r['emoji']?.toString() ?? '';
          final uid = r['user_id']?.toString() ?? '';
          if (emoji.isNotEmpty) {
            reactionsMap.putIfAbsent(emoji, () => []).add(uid);
          }
        }

        enriched.add({
          ...Map<String, dynamic>.from(m),
          'sender_name':
              senderUser?['display_name'] ?? senderUser?['username'] ?? 'User',
          'sender_username': senderUser?['username'] ?? '',
          'sender_avatar_url': senderUser?['avatar_url'],
          'reactions': reactionsMap.entries
              .map((entry) => {
                    'emoji': entry.key,
                    'count': entry.value.toSet().length,
                    'reacted': entry.value.contains(currentUserId),
                    'user_ids': entry.value.toSet().toList(),
                  })
              .toList(),
          'reactions_list': rawReactions,
        });
      }

      return enriched;
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] getConversationMessages error: $e');
      rethrow;
    }
  }

  /// Fetch a single conversation with recipient info & participants
  Future<Map<String, dynamic>> getConversationDetail(
      String conversationId) async {
    try {
      final convs = await getConversations();
      final match = convs.firstWhere(
        (c) =>
            c['id']?.toString().toLowerCase() == conversationId.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );
      if (match.isNotEmpty) return match;

      final res = await client
          .from('conversations')
          .select()
          .eq('id', conversationId)
          .single();
      return Map<String, dynamic>.from(res);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] getConversationDetail error: $e');
      rethrow;
    }
  }

  /// Create or find a direct conversation with a recipient user
  Future<Map<String, dynamic>> createConversation(
      Map<String, dynamic> data) async {
    try {
      final targetUserId = data['recipient_id']?.toString() ??
          data['target_id']?.toString() ??
          data['user_id']?.toString();
      final type = data['conversation_type']?.toString().toLowerCase() ??
          data['type']?.toString().toLowerCase() ??
          'direct';

      if (type == 'direct' && targetUserId != null) {
        final res = await client.rpc('create_direct_conversation', params: {
          'p_recipient_id': targetUserId,
        });
        invalidateConversationsCache();
        return Map<String, dynamic>.from(res as Map);
      }

      if (type == 'group' && targetUserId != null) {
        return findOrCreateGroupConversation(targetUserId);
      }

      throw StateError('A conversation target is required.');
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] createConversation error: $e');
      rethrow;
    }
  }

  /// Record an authenticated user's read receipt for a conversation.
  Future<Map<String, dynamic>> markConversationRead(
    String conversationId, {
    String? messageId,
  }) async {
    final res = await client.rpc('mark_conversation_read', params: {
      'p_conversation_id': conversationId,
      'p_message_id': messageId,
    });
    invalidateConversationsCache();
    return Map<String, dynamic>.from(res as Map);
  }

  /// Get unread, mute, archive, and notification state for this session.
  Future<List<Map<String, dynamic>>> getConversationState() async {
    try {
      final res = await client.rpc('get_conversation_state');
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] getConversationState error: $e');
      return [];
    }
  }

  /// Add emoji reaction
  Future<void> addReaction(String messageId, String emoji) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      await client.from('message_reactions').insert({
        'message_id': messageId,
        'user_id': userId,
        'emoji': emoji,
      });
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] addReaction error: $e');
      rethrow;
    }
  }

  /// Remove emoji reaction
  Future<void> removeReaction(String messageId, String? emoji) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      var q = client
          .from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', userId);
      if (emoji != null && emoji.isNotEmpty) {
        q = q.eq('emoji', emoji);
      }
      await q;
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] removeReaction error: $e');
      rethrow;
    }
  }

  /// Edit message content
  Future<void> editMessage(String messageId, String newContent) async {
    try {
      await client.from('messages').update({
        'content': newContent,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', messageId);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] editMessage error: $e');
      rethrow;
    }
  }

  /// Delete message (soft delete)
  Future<void> deleteMessage(String messageId) async {
    try {
      await client.from('messages').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', messageId);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] deleteMessage error: $e');
      rethrow;
    }
  }

  /// Toggle pin on message
  Future<void> togglePinMessage(String messageId) async {
    try {
      final msg = await client
          .from('messages')
          .select('is_pinned')
          .eq('id', messageId)
          .single();
      final currentPinned = msg['is_pinned'] == true;
      await client.from('messages').update({
        'is_pinned': !currentPinned,
        'pinned_at':
            !currentPinned ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', messageId);
    } catch (e) {
      _reportDataError(e);
      debugPrint('[Supabase] togglePinMessage error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> toggleReaction(
      String messageId, String emoji) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to react.');
    final existing = await client
        .from('message_reactions')
        .select('id')
        .eq('message_id', messageId)
        .eq('user_id', userId)
        .eq('emoji', emoji)
        .maybeSingle();
    if (existing == null) {
      await client.from('message_reactions').insert({
        'message_id': messageId,
        'user_id': userId,
        'emoji': emoji,
      });
    } else {
      await client
          .from('message_reactions')
          .delete()
          .eq('id', existing['id'])
          .eq('user_id', userId);
    }
    final remaining = await client
        .from('message_reactions')
        .select('id')
        .eq('message_id', messageId)
        .eq('emoji', emoji);
    return {
      'emoji': emoji,
      'active': existing == null,
      'count': remaining.length
    };
  }

  Future<Map<String, dynamic>> setMessagePinned(
      String messageId, bool pinned) async {
    return await client
        .from('messages')
        .update({
          'is_pinned': pinned,
          'pinned_at': pinned ? DateTime.now().toUtc().toIso8601String() : null,
          'pinned_by': pinned ? client.auth.currentUser!.id : null,
        })
        .eq('id', messageId)
        .select()
        .single();
  }
}
