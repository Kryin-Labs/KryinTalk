/// ConnectHub — WebSocket Client Manager.
///
/// Manages a persistent WebSocket connection for real-time messaging.
/// Reconnects automatically on disconnect.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'api_endpoints.dart';

/// WebSocket connection state.
enum WsState { disconnected, connecting, connected }

/// WebSocket client provider.
final wsClientProvider = Provider<WsClient>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final client = WsClient(apiClient);
  ref.onDispose(client.dispose);
  return client;
});

/// Real-time message from WebSocket.
class WsMessage {
  final String type;
  final Map<String, dynamic> data;

  const WsMessage({required this.type, required this.data});

  factory WsMessage.fromJson(Map<String, dynamic> json) {
    // The FastAPI websocket sends event fields at the top level
    // (for example `{type: "new_message", message: {...}}`). Keep
    // supporting wrapped `{type, data}` events for older clients, but do
    // not drop the top-level payload or realtime messages become no-ops.
    final rawData = json['data'];
    final payload = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : Map<String, dynamic>.from(json)
      ..remove('type');
    return WsMessage(
      type: json['type'] as String? ?? 'unknown',
      data: payload,
    );
  }
}

class WsClient {
  final ApiClient _apiClient;
  WebSocketChannel? _channel;
  WsState _state = WsState.disconnected;
  Timer? _reconnectTimer;
  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;
  bool _shouldReconnect = false;
  int _generation = 0;
  int _retryAttempt = 0;

  final _messageController = StreamController<WsMessage>.broadcast();
  final _stateController = StreamController<WsState>.broadcast();

  /// Stream of incoming WebSocket messages.
  Stream<WsMessage> get messages => _messageController.stream;

  /// Stream of connection state changes.
  Stream<WsState> get stateChanges => _stateController.stream;

  /// Current connection state.
  WsState get state => _state;

  WsClient(this._apiClient);

  /// Connect to the WebSocket server.
  Future<void> connect() async {
    if (_disposed) return;
    if (_state == WsState.connecting || _state == WsState.connected) return;
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    final generation = ++_generation;
    _setState(WsState.connecting);
    try {
      final token = await _apiClient.getToken();
      if (_disposed || generation != _generation) return;
      if (token == null || token.isEmpty) {
        _setState(WsState.disconnected);
        _scheduleReconnect();
        return;
      }
      final uri = Uri.parse(ApiEndpoints.websocket(token));
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        (data) {
          if (_disposed || generation != _generation) return;
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(WsMessage.fromJson(json));
          } catch (_) {}
        },
        onDone: () {
          _connectionLost(generation);
        },
        onError: (_) {
          _connectionLost(generation);
        },
        cancelOnError: true,
      );
      await channel.ready.timeout(const Duration(seconds: 15));
      if (_disposed || generation != _generation) return;
      _setState(WsState.connected);
      _retryAttempt = 0;
    } catch (_) {
      _connectionLost(generation);
    }
  }

  void _connectionLost(int generation) {
    if (_disposed || generation != _generation) return;
    ++_generation;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _setState(WsState.disconnected);
    _scheduleReconnect();
  }

  /// Send a message over the WebSocket.
  void send(Map<String, dynamic> data) {
    if (!_disposed && _state == WsState.connected) {
      try {
        _channel?.sink.add(jsonEncode(data));
      } catch (_) {
        _connectionLost(_generation);
      }
    }
  }

  /// Disconnect from the WebSocket server.
  void disconnect() {
    _shouldReconnect = false;
    ++_generation;
    _retryAttempt = 0;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _setState(WsState.disconnected);
  }

  void _setState(WsState newState) {
    if (_disposed || newState == _state) return;
    _state = newState;
    _stateController.add(newState);
  }

  void _scheduleReconnect() {
    if (_disposed || !_shouldReconnect) return;
    _reconnectTimer?.cancel();
    final seconds = (1 << _retryAttempt.clamp(0, 5)).clamp(1, 30);
    _retryAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), connect);
  }

  void dispose() {
    if (_disposed) return;
    disconnect();
    _disposed = true;
    _messageController.close();
    _stateController.close();
  }
}
