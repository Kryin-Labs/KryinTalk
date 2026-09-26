/// ConnectHub — Notification State & Sync Provider.
///
/// Handles real-time polling of unread counts and notifications list,
/// providing global badge counters and instant read-state synchronization.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../auth/auth_provider.dart';
import '../supabase/supabase_service.dart';
import 'notification_sound_service.dart';

class NotificationState {
  final int unreadCount;
  final List<Map<String, dynamic>> items;
  final bool isLoading;
  final String activeFilter; // 'all', 'mention', 'message', 'unread'

  const NotificationState({
    this.unreadCount = 0,
    this.items = const [],
    this.isLoading = false,
    this.activeFilter = 'all',
  });

  NotificationState copyWith({
    int? unreadCount,
    List<Map<String, dynamic>>? items,
    bool? isLoading,
    String? activeFilter,
  }) {
    return NotificationState(
      unreadCount: unreadCount ?? this.unreadCount,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      activeFilter: activeFilter ?? this.activeFilter,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  final Ref _ref;
  Timer? _recoveryTimer;
  Timer? _retryTimer;
  RealtimeChannel? _realtimeChannel;
  int _retrySeconds = 2;
  Future<void>? _countRequest;
  Future<void>? _itemsRequest;
  int _epoch = 0;
  bool _hasCountBaseline = false;

  NotificationNotifier(this._ref) : super(const NotificationState()) {
    _ref.listen<AuthState>(authProvider, (previous, authState) {
      if (previous?.userId != authState.userId ||
          previous?.hasAppAccess != authState.hasAppAccess) {
        stopPolling();
      }
      if (authState.hasAppAccess && _recoveryTimer == null) {
        startPolling();
      }
    });

    final initialAuth = _ref.read(authProvider);
    if (initialAuth.hasAppAccess) {
      startPolling();
    }
  }

  void startPolling() {
    refresh();
    _startRealtime();
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _startRealtime();
      fetchUnreadCount();
      fetchNotifications(silent: true);
    });
  }

  void _startRealtime() {
    if (_realtimeChannel != null || !SupabaseService.instance.hasSession) return;
    final userId = _ref.read(authProvider).userId;
    if (userId == null || userId.isEmpty) return;
    late final RealtimeChannel channel;
    channel = SupabaseService.instance.client
        .channel('public:notification-items:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notification_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => refresh(),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _retrySeconds = 2;
          } else if (identical(_realtimeChannel, channel)) {
            _realtimeChannel = null;
            _scheduleReconnect();
          }
        });
    _realtimeChannel = channel;
  }

  void _scheduleReconnect() {
    if (_retryTimer != null || !mounted) return;
    final delay = Duration(seconds: _retrySeconds);
    _retrySeconds = (_retrySeconds * 2).clamp(2, 60);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _startRealtime();
    });
  }

  void stopPolling() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _retrySeconds = 2;
    ++_epoch;
    _hasCountBaseline = false;
    state = const NotificationState();
  }

  Future<void> refresh() async {
    await Future.wait([
      fetchUnreadCount(),
      fetchNotifications(),
    ]);
  }

  Future<void> fetchUnreadCount() => _countRequest ??=
      _fetchUnreadCount().whenComplete(() => _countRequest = null);

  Future<void> _fetchUnreadCount() async {
    final epoch = _epoch;
    try {
      final auth = _ref.read(authProvider);
      if (!auth.hasAppAccess) return;
      final api = _ref.read(apiClientProvider);
      final response = await api.dio.get(ApiEndpoints.unreadCount);
      if (!mounted || epoch != _epoch) return;
      final data = response.data;
      if (data is Map && data.containsKey('count')) {
        final count = (data['count'] as num?)?.toInt() ?? 0;
        final oldCount = state.unreadCount;
        if (_hasCountBaseline && count > oldCount) {
          NotificationSoundService.instance.playMessageReceivedSound();
        }
        state = state.copyWith(unreadCount: count);
        _hasCountBaseline = true;
      }
    } catch (_) {}
  }

  Future<void> fetchNotifications({bool silent = false}) => _itemsRequest ??=
      _fetchNotifications(silent: silent).whenComplete(() {
        _itemsRequest = null;
      });

  Future<void> _fetchNotifications({bool silent = false}) async {
    final epoch = _epoch;
    final filter = state.activeFilter;
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final auth = _ref.read(authProvider);
      if (!auth.hasAppAccess) return;
      final api = _ref.read(apiClientProvider);

      final queryParams = <String, dynamic>{'limit': 50};
      if (state.activeFilter == 'mention') {
        queryParams['type'] = 'mention';
      } else if (state.activeFilter == 'message') {
        queryParams['type'] = 'message';
      } else if (state.activeFilter == 'unread') {
        queryParams['unread_only'] = true;
      }

      final response = await api.dio.get(
        ApiEndpoints.notifications,
        queryParameters: queryParams,
      );
      if (!mounted || epoch != _epoch || filter != state.activeFilter) return;
      final data = response.data;
      List<Map<String, dynamic>> items = [];
      if (data is Map && data.containsKey('items')) {
        items = List<Map<String, dynamic>>.from(data['items']);
      } else if (data is List) {
        items = List<Map<String, dynamic>>.from(data);
      }
      state = state.copyWith(items: items);
    } catch (_) {
    } finally {
      if (mounted && epoch == _epoch && !silent) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void setFilter(String filter) {
    if (state.activeFilter == filter) return;
    state = state.copyWith(activeFilter: filter);
    // Wait for the previous filter's request before fetching the new one.
    final pending = _itemsRequest;
    () async {
      await pending;
      if (mounted && state.activeFilter == filter) {
        await fetchNotifications();
      }
    }();
  }

  Future<void> markAsRead(String notificationId) async {
    final epoch = _epoch;
    try {
      final api = _ref.read(apiClientProvider);
      await api.dio.put(ApiEndpoints.markNotifRead(notificationId));
      if (!mounted || epoch != _epoch) return;
      ++_epoch; // Discard read snapshots started before this write completed.
      final wasUnread = state.items.any((item) =>
          item['id']?.toString() == notificationId && item['is_read'] != true);

      final updated = state.items.map((item) {
        if (item['id']?.toString() == notificationId) {
          final copy = Map<String, dynamic>.from(item);
          copy['is_read'] = true;
          return copy;
        }
        return item;
      }).toList();

      final newCount = (state.unreadCount - (wasUnread ? 1 : 0)).clamp(0, 9999);
      state = state.copyWith(items: _visibleItems(updated), unreadCount: newCount);
      await _refreshAfterRead();
    } catch (_) {}
  }

  Future<void> markConversationRead(String conversationId) async {
    final epoch = _epoch;
    try {
      final api = _ref.read(apiClientProvider);
      await api.dio
          .put(ApiEndpoints.markConversationNotifsRead(conversationId));
      if (!mounted || epoch != _epoch) return;
      ++_epoch;

      final updated = state.items.map((item) {
        if (item['conversation_id']?.toString() == conversationId) {
          final copy = Map<String, dynamic>.from(item);
          copy['is_read'] = true;
          return copy;
        }
        return item;
      }).toList();

      state = state.copyWith(items: _visibleItems(updated));
      await _refreshAfterRead();
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    final epoch = _epoch;
    try {
      final api = _ref.read(apiClientProvider);
      await api.dio.put(ApiEndpoints.markAllRead);
      if (!mounted || epoch != _epoch) return;
      ++_epoch;

      final updated = state.items.map((item) {
        final copy = Map<String, dynamic>.from(item);
        copy['is_read'] = true;
        return copy;
      }).toList();

      state = state.copyWith(items: _visibleItems(updated), unreadCount: 0);
      await _refreshAfterRead();
    } catch (_) {}
  }

  List<Map<String, dynamic>> _visibleItems(List<Map<String, dynamic>> items) =>
      state.activeFilter == 'unread'
          ? items.where((item) => item['is_read'] != true).toList()
          : items;

  Future<void> _refreshAfterRead() async {
    await Future.wait([if (_countRequest != null) _countRequest!,
      if (_itemsRequest != null) _itemsRequest!]);
    if (mounted) await refresh();
  }

  @override
  void dispose() {
    ++_epoch;
    _recoveryTimer?.cancel();
    _retryTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }
}

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier(ref);
});
