import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Draft keys include the account so switching accounts cannot expose drafts.
class ChatDrafts {
  static final Map<String, Map<String, dynamic>> _pending = {};
  static Future<void> _writes = Future.value();

  static String _key(String userId, String conversationId) =>
      'chat_draft:$userId:$conversationId';

  static Future<Map<String, dynamic>> read(
      String userId, String conversationId) async {
    final key = _key(userId, conversationId);
    if (_pending.containsKey(key)) return _pending[key]!;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pending.containsKey(key)) return _pending[key]!;
      final value = prefs.getString(key);
      return value == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(String userId, String conversationId, String text,
      Map<String, dynamic>? reply) {
    if (userId.isEmpty) return Future.value();
    final key = _key(userId, conversationId);
    final value = <String, dynamic>{'text': text, 'reply': reply};
    _pending[key] = value;
    _writes = _writes.then((_) async {
      // Superseded keystrokes need no separate disk write.
      if (!identical(_pending[key], value)) return;
      final prefs = await SharedPreferences.getInstance();
      if (text.isEmpty && reply == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(value));
      }
    }).catchError((Object _) {});
    return _writes;
  }
}
