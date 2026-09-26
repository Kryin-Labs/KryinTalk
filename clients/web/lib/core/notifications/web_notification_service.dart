/// ConnectHub — Web Desktop & In-App Notification Dispatcher.
///
/// Dispatches Chrome / Desktop notifications and plays audio chimes
/// for incoming messages, mentions, and system notifications.
library;

import 'package:flutter/foundation.dart';
import 'notification_sound_service.dart';
import 'web_notification_bridge.dart' as web_notifications;

class WebNotificationService {
  WebNotificationService._();
  static final WebNotificationService instance = WebNotificationService._();

  bool _notificationsEnabled = true;
  bool _accountAccess = false;
  void setAccountAccess(bool allowed) => _accountAccess = allowed;
  bool get notificationsEnabled => _notificationsEnabled;

  void setEnabled(bool enabled) => _notificationsEnabled = enabled;

  /// Request browser notification permission (Chrome / Edge / Firefox)
  Future<void> requestBrowserPermission() async {
    if (!kIsWeb || !_accountAccess) return;
    try {
      web_notifications.requestPermission();
    } catch (_) {}
  }

  /// Show a desktop notification in Chrome/browser and play notification sound
  void showMessageNotification({
    required String senderName,
    required String messageText,
    String? conversationTitle,
    String? conversationId,
    bool playSound = true,
  }) {
    if (!_notificationsEnabled || !_accountAccess) return;

    if (playSound) {
      NotificationSoundService.instance.playMessageReceivedSound();
    }

    if (kIsWeb) {
      final title = conversationTitle != null && conversationTitle.isNotEmpty
          ? '$senderName in $conversationTitle'
          : senderName;
      final cleanText = messageText.length > 120
          ? '${messageText.substring(0, 117)}...'
          : messageText;

      final tag = conversationId ?? 'connecthub-msg';
      final safeTitle = title.replaceAll("'", "\\'").replaceAll('"', '\\"');
      final safeBody = cleanText.replaceAll("'", "\\'").replaceAll('"', '\\"');

      web_notifications.show(safeTitle, safeBody, tag, 'favicon.png');
    }
  }
}
