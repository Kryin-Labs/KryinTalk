/// ConnectHub — Real-Time User Presence Provider.
///
/// Manages client heartbeat transmission (every 25s) and user presence registry sync (every 15s).
/// Provides `isUserOnline(userId)` and `getLastSeen(userId)` across all UI components.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../auth/auth_provider.dart';

class PresenceState {
  final Map<String, Map<String, dynamic>> users;
  final bool isTracking;
  final String myStatus; // 'online', 'away', 'busy', 'focus'

  const PresenceState({
    this.users = const {},
    this.isTracking = false,
    this.myStatus = 'online',
  });

  PresenceState copyWith({
    Map<String, Map<String, dynamic>>? users,
    bool? isTracking,
    String? myStatus,
  }) {
    return PresenceState(
      users: users ?? this.users,
      isTracking: isTracking ?? this.isTracking,
      myStatus: myStatus ?? this.myStatus,
    );
  }
}

class PresenceNotifier extends StateNotifier<PresenceState> {
  final Ref _ref;
  Timer? _heartbeatTimer;
  Timer? _fetchTimer;

  PresenceNotifier(this._ref) : super(const PresenceState()) {
    _loadSavedStatus();

    // Listen for auth state changes to start/stop presence tracking
    _ref.listen<AuthState>(authProvider, (previous, authState) {
      if (previous?.userId != authState.userId || previous?.hasAppAccess != authState.hasAppAccess) stopTracking();
      if (authState.hasAppAccess) {
        startTracking();
      } else {
        stopTracking();
      }
    });

    final initialAuth = _ref.read(authProvider);
    if (initialAuth.hasAppAccess) {
      startTracking();
    }
  }

  Future<void> _loadSavedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('custom_user_presence_status') ?? 'online';
      state = state.copyWith(myStatus: saved);
    } catch (_) {}
  }

  void startTracking() {
    if (state.isTracking) return;
    state = state.copyWith(isTracking: true);

    // Initial heartbeat & sync
    sendHeartbeat();
    fetchPresence();

    // Periodic heartbeat every 25 seconds
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      sendHeartbeat();
    });

    // Periodic presence fetch every 5 seconds for real-time status updates
    _fetchTimer?.cancel();
    _fetchTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      fetchPresence();
    });
  }

  void stopTracking() {
    _heartbeatTimer?.cancel();
    _fetchTimer?.cancel();
    _heartbeatTimer = null;
    _fetchTimer = null;
    state = const PresenceState();
  }

  Future<void> setCustomStatus(String newStatus) async {
    state = state.copyWith(myStatus: newStatus);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_user_presence_status', newStatus);
    } catch (_) {}

    try {
      final auth = _ref.read(authProvider);
      if (!auth.hasAppAccess) return;
      final api = _ref.read(apiClientProvider);
      await api.dio.post(
        '/presence/status',
        data: {'status': newStatus},
      );
      await fetchPresence();
    } catch (_) {}
  }

  Future<void> sendHeartbeat() async {
    try {
      final auth = _ref.read(authProvider);
      if (!auth.hasAppAccess) return;
      final api = _ref.read(apiClientProvider);
      await api.dio.post(
        ApiEndpoints.presenceHeartbeat,
        data: {'status': state.myStatus},
      );
    } catch (e) {
      debugPrint('[Presence] Heartbeat failed: $e');
    }
  }

  Future<void> fetchPresence() async {
    try {
      final auth = _ref.read(authProvider);
      if (!auth.hasAppAccess) return;
      final api = _ref.read(apiClientProvider);
      final response = await api.dio.get(ApiEndpoints.presenceMap);
      if (!mounted || !_ref.read(authProvider).hasAppAccess || _ref.read(authProvider).userId != auth.userId) return;
      final data = response.data;

      if (data is Map && data.containsKey('users')) {
        final rawUsers = data['users'];
        if (rawUsers is Map) {
          final Map<String, Map<String, dynamic>> updated = {};
          rawUsers.forEach((key, val) {
            if (val is Map) {
              updated[key.toString()] = Map<String, dynamic>.from(val);
            }
          });
          state = state.copyWith(users: updated);
        }
      }
    } catch (e) {
      debugPrint('[Presence] Sync failed: $e');
    }
  }

  bool isOnline(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    final currentUserId = _ref.read(authProvider).userId;
    if (userId == currentUserId) return true; // Current user is active

    final u = state.users[userId];
    if (u == null) return false;
    final status = u['status']?.toString();
    return status != null && status != 'offline';
  }

  String getUserStatus(String? userId) {
    if (userId == null || userId.isEmpty) return 'offline';
    final currentUserId = _ref.read(authProvider).userId;
    if (userId == currentUserId) return state.myStatus;

    final u = state.users[userId];
    if (u == null) return 'offline';
    return u['status']?.toString() ?? 'offline';
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return const Color(0xFF10B981); // Emerald Green
      case 'away':
        return const Color(0xFFF59E0B); // Amber Orange
      case 'busy':
      case 'dnd':
        return const Color(0xFFEF4444); // Crimson Red
      case 'focus':
        return const Color(0xFF8B5CF6); // Purple
      default:
        return const Color(0xFF9CA3AF); // Gray
    }
  }

  Color getUserPresenceColor(String? userId) {
    if (!isOnline(userId)) return const Color(0xFF9CA3AF);
    final status = getUserStatus(userId);
    return getStatusColor(status);
  }

  String getLastSeenText(String? userId) {
    if (userId == null || userId.isEmpty) return 'Offline';
    final currentUserId = _ref.read(authProvider).userId;
    if (userId == currentUserId)
      return 'Online (${state.myStatus.toUpperCase()})';

    final u = state.users[userId];
    if (u == null) return 'Offline';
    final status = u['status']?.toString();
    if (status != null && status != 'offline') {
      return status.toUpperCase();
    }

    final lastSeenStr = u['last_seen_at']?.toString();
    if (lastSeenStr == null || lastSeenStr.isEmpty) return 'Offline';

    try {
      final dt = DateTime.parse(lastSeenStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Active just now';
      if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
      if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
      return 'Last seen ${dt.day}/${dt.month}/${dt.year.toString().substring(2)}';
    } catch (_) {
      return 'Offline';
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _fetchTimer?.cancel();
    super.dispose();
  }
}

final presenceProvider =
    StateNotifierProvider<PresenceNotifier, PresenceState>((ref) {
  return PresenceNotifier(ref);
});
