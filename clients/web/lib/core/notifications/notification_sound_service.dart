/// ConnectHub — Notification Sound & Audio Engine.
///
/// Provides synthesizer audio chimes for message sending and receiving
/// across Web (Web Audio API) and Mobile (Haptic / System feedback).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'web_audio_bridge.dart' as web_audio;

class NotificationSoundService {
  NotificationSoundService._();
  static final NotificationSoundService instance = NotificationSoundService._();

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  void toggleMute() {
    _isMuted = !_isMuted;
  }

  void setMuted(bool muted) {
    _isMuted = muted;
  }

  /// Play pleasant subtle chime when sending a message
  void playMessageSentSound() {
    if (_isMuted) return;
    if (kIsWeb) {
      _playWebAudio('sent');
    } else {
      HapticFeedback.lightImpact();
    }
  }

  /// Play crisp dual-bell chime when receiving a message or notification
  void playMessageReceivedSound() {
    if (_isMuted) return;
    if (kIsWeb) {
      _playWebAudio('received');
    } else {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.alert);
    }
  }

  void _playWebAudio(String type) {
    try {
      if (type == 'sent') {
        // Invoke JS connectHubAudio.playSentChime()
        _callJs('playSentChime');
      } else {
        // Invoke JS connectHubAudio.playReceivedChime()
        _callJs('playReceivedChime');
      }
    } catch (_) {}
  }

  void _callJs(String method) {
    try {
      web_audio.invoke(method);
    } catch (_) {}
  }
}
