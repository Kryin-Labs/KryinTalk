/// ConnectHub — Messages Screen (Exact Match to Reference UI in SaaSSchool Light Theme).
///
/// Features:
/// - Top Greeting Header: "Hello, {UserName}" with circular outlined Search [ 🔍 ] and More [ ⋮ ] action buttons.
/// - Segmented Pill Control: "All Chats", "Groups", "Contacts" in a modern rounded capsule container.
/// - Rich Conversation List Items:
///   - Large 52x52 avatar with image/pastel initials & live online green dot
///   - Title row with contact/group name and accent Pushpin (📌) if pinned
///   - Subtitle snippet with typing status, voice message, sticker, or text preview
///   - Trailing meta with clean timestamps ("09:38 AM", "Yesterday", "26 May") and primary teal unread badge
/// - Floating Action Button (FAB): Bottom-right gradient circular button for quick DM / Group / Channel creation.
/// - Light-themed Master-Detail Chat Panel with responsive mobile & desktop views.
library;

import 'dart:async';
import 'chat_drafts.dart';
import 'message_sync.dart';
import 'message_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/notifications/notification_provider.dart';
import '../../core/presence/presence_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/notifications/notification_sound_service.dart';
import '../../core/notifications/web_notification_service.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/files/attachment_download.dart';
import '../../core/files/file_name_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide MultipartFile;
import '../../shared/widgets/rich_markdown_text.dart';
import '../../shared/widgets/pulsing_status_dot.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../groups/widgets/group_settings_dialog.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  final String? initialConversationId;
  final String? highlightMessageId;
  final String? fromRoute;

  const MessagesScreen({
    super.key,
    this.initialConversationId,
    this.highlightMessageId,
    this.fromRoute,
  });

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  final _searchConvController = TextEditingController();
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _scrollController = ScrollController();

  // Segmented Pill Tab Selection: 0 = All Chats, 1 = Groups, 2 = Contacts
  int _selectedTabIndex = 0;
  bool _isSearchExpanded = false;

  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, Map<String, dynamic>> _groupCache = {};
  final Map<String, GlobalKey> _messageKeys = {};
  Set<String> _pinnedMsgIds = {};

  // In-Memory Global Message & Detail Cache across chat switching for 0ms instant loading
  static final Map<String, List<Map<String, dynamic>>> _messagesCache = {};
  static final Map<String, Set<String>> _pinnedMessagesCache = {};
  static final Map<String, Map<String, dynamic>> _conversationDetailCache = {};
  static String? _cacheUserId;

  String? _selectedConvId;
  Map<String, dynamic>? _selectedConvDetail;
  Map<String, dynamic>? _replyingToMsg;
  Map<String, dynamic>? _editingMsg;

  // Hover Toolbar & Reaction Picker state
  String? _hoveredMsgId;
  String? _reactionPickerMsgId;

  // Jump-to-reply & notification highlight state
  String? _highlightedMsgId;
  String? _targetHighlightMsgId;
  Timer? _highlightTimer;

  // Mentions Autocomplete state
  bool _showMentionAutocomplete = false;
  List<Map<String, dynamic>> _mentionFilteredUsers = [];

  final List<String> _recentEmojis = [];

  bool _isConversationsLoading = true;
  bool _isMessagesLoading = false;
  bool _isUploadingAttachment = false;
  bool _hasNoPermissionToView = false;
  String? _permissionErrorMsg;
  Timer? _pollingTimer;
  final _conversationRefresh = MessageRefresh();
  final Map<String, MessageRefresh> _messageRefreshes = {};
  final Map<String, Timer> _typingTimers = {};
  bool _isSending = false;
  RealtimeChannel? _realtimeMessagesChannel;
  RealtimeChannel? _realtimeReactionsChannel;

  // SuperAdmin Force Message Override state
  int _forceMessageSecondsRemaining = 0;
  Timer? _forceMessageTimer;
  bool _isActivatingForceMessage = false;

  static const List<Color> _pastelBgPalette = [
    Color(0xFFE0F2FE), // Soft Sky
    Color(0xFFF0FDF4), // Soft Mint
    Color(0xFFFEF3C7), // Soft Amber
    Color(0xFFFCE7F3), // Soft Rose
    Color(0xFFEDE9FE), // Soft Violet
    Color(0xFFCCFBF1), // Soft Teal
    Color(0xFFFFEDD5), // Soft Orange
  ];

  static const List<Color> _pastelTextPalette = [
    Color(0xFF0369A1),
    Color(0xFF15803D),
    Color(0xFFB45309),
    Color(0xFFBE185D),
    Color(0xFF6D28D9),
    Color(0xFF0F766E),
    Color(0xFFC2410C),
  ];

  final List<String> _sampleEmojis = [
    '😀',
    '😃',
    '😄',
    '😁',
    '😆',
    '😅',
    '😂',
    '🤣',
    '😊',
    '😇',
    '🙂',
    '🙃',
    '😉',
    '😌',
    '😍',
    '🥰',
    '😘',
    '😗',
    '😙',
    '😚',
    '😋',
    '😛',
    '😝',
    '😜',
    '🤪',
    '🤨',
    '🧐',
    '🤓',
    '😎',
    '🤩',
    '🥳',
    '😏',
    '😒',
    '😞',
    '😔',
    '😟',
    '😕',
    '🙁',
    '☹️',
    '😣',
    '😖',
    '😫',
    '😩',
    '🥺',
    '😢',
    '😭',
    '😤',
    '😠',
    '😡',
    '🤬',
    '🤯',
    '😳',
    '🥵',
    '🥶',
    '😱',
    '😨',
    '😰',
    '😥',
    '😓',
    '🤗',
    '🤔',
    '🤭',
    '🤫',
    '🤥',
    '😶',
    '😐',
    '😑',
    '😬',
    '🙄',
    '😯',
    '👍',
    '👎',
    '👏',
    '🙌',
    '👐',
    '🤲',
    '🤝',
    '🙏',
    '✍️',
    '💅',
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🤍',
    '🤎',
    '💔',
    '🔥',
    '✨',
    '🌟',
    '💥',
    '🎉',
    '🎊',
    '🚀',
    '💡',
    '💯',
    '✅',
  ];

  static const Map<String, List<String>> _extraEmojiCategories = {
    'Gestures': [
      '👍',
      '👎',
      '👏',
      '🙌',
      '🙏',
      '🤝',
      '💪',
      '👀',
      '✋',
      '🤞',
      '👌',
      '👋',
      '🫶',
      '✍️',
      '🫡',
      '💯',
    ],
    'Work': [
      '✅',
      '❌',
      '⚠️',
      '📌',
      '📎',
      '📁',
      '📝',
      '📅',
      '💡',
      '🔍',
      '🚀',
      '🎯',
      '📈',
      '🔔',
      '🔒',
      '🧪',
    ],
    'Objects': [
      '❤️',
      '💚',
      '💙',
      '⭐',
      '🔥',
      '🎉',
      '🎊',
      '🏆',
      '☕',
      '🌟',
      '🌍',
      '⚡',
      '✨',
      '🎁',
      '📣',
      '🛠️',
    ],
  };

  static const Map<String, String> _emojiKeywords = {
    '❤️': 'heart love',
    '🔥': 'fire hot',
    '🎉': 'party celebrate congratulations',
    '🚀': 'rocket launch ship',
    '💡': 'idea light bulb',
    '✅': 'check done complete yes',
    '❌': 'cross no error',
    '⚠️': 'warning alert',
    '👍': 'thumb up like yes',
    '👎': 'thumb down dislike no',
    '👏': 'clap applause',
    '🙏': 'thanks please pray',
    '👀': 'eyes looking',
    '😂': 'laugh joy tears',
    '😊': 'smile happy',
    '😢': 'sad cry',
    '😡': 'angry mad',
    '🤔': 'think thinking',
    '📌': 'pin pinned',
    '📎': 'attachment paperclip',
    '🔍': 'search find',
    '🎯': 'target goal',
    '🏆': 'trophy winner',
    '☕': 'coffee break',
  };

  @override
  void initState() {
    super.initState();
    final userId = ref.read(authProvider).userId;
    if (_cacheUserId != userId) {
      _messagesCache.clear();
      _pinnedMessagesCache.clear();
      _conversationDetailCache.clear();
      _cacheUserId = userId;
    }
    _messageController.addListener(_onTextChanged);
    _selectedConvId = widget.initialConversationId;
    _targetHighlightMsgId = widget.highlightMessageId;
    _loadAll();
    _startPolling();
  }

  // User ids come from both the local API and Supabase. Normalize them before
  // looking users up so a UUID's casing/whitespace can never make us fall back
  // to the signed-in account (or a generic administrator label).
  String _normalizeUserId(dynamic id) =>
      id?.toString().trim().toLowerCase() ?? '';

  void _cacheUser(dynamic rawUser) {
    if (rawUser is! Map) return;
    final user = Map<String, dynamic>.from(rawUser);
    final id = _normalizeUserId(user['id'] ?? user['user_id']);
    if (id.isNotEmpty) _userCache[id] = user;
  }

  Map<String, dynamic> _userForId(dynamic id) {
    final normalized = _normalizeUserId(id);
    return normalized.isEmpty
        ? <String, dynamic>{}
        : (_userCache[normalized] ?? {});
  }

  String _senderDisplayName(Map<String, dynamic> message) {
    final senderId = _normalizeUserId(message['sender_id']);
    final currentUserId = _normalizeUserId(ref.read(authProvider).userId);
    if (senderId.isNotEmpty && senderId == currentUserId) {
      final ownName = ref.read(authProvider).displayName.trim();
      if (ownName.isNotEmpty && ownName != 'User') return ownName;
    }

    // Always resolve by sender_id first. A stale/embedded sender_name can be
    // from another account, while the directory entry is authoritative.
    final user = _userForId(senderId);
    final directoryName =
        (user['display_name'] ?? user['username'])?.toString().trim();
    if (directoryName != null && directoryName.isNotEmpty) return directoryName;

    final payloadName = message['sender_name']?.toString().trim();
    if (payloadName != null &&
        payloadName.isNotEmpty &&
        payloadName != 'User' &&
        payloadName != 'Super Administrator') {
      return payloadName;
    }
    return 'Member';
  }

  @override
  void didUpdateWidget(covariant MessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 768;

    if (widget.highlightMessageId != null &&
        widget.highlightMessageId != oldWidget.highlightMessageId) {
      _targetHighlightMsgId = widget.highlightMessageId;
      if (widget.initialConversationId != null &&
          widget.initialConversationId != _selectedConvId) {
        _selectConversation(widget.initialConversationId!);
      } else {
        _scrollToParentMessage(widget.highlightMessageId!);
      }
    } else if (widget.initialConversationId !=
        oldWidget.initialConversationId) {
      if (widget.initialConversationId != null) {
        _selectConversation(widget.initialConversationId!);
      } else if (isMobile) {
        setState(() {
          _selectedConvId = null;
          _selectedConvDetail = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _saveDraft();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _searchConvController.dispose();
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _pollingTimer?.cancel();
    _highlightTimer?.cancel();
    _forceMessageTimer?.cancel();
    _realtimeMessagesChannel?.unsubscribe();
    _realtimeReactionsChannel?.unsubscribe();
    super.dispose();
  }

  void _onTextChanged() {
    _saveDraft();
    final text = _messageController.text;
    final match = RegExp(r'@([^\s@]{0,40})$').firstMatch(text);
    if (match != null) {
      final query = match.group(1)?.toLowerCase() ?? '';
      final currentConvUserIds = <String>{};
      for (final m in _messages) {
        if (m['sender_id'] != null) {
          currentConvUserIds.add(m['sender_id'].toString());
        }
      }

      final matches = _allUsers.where((u) {
        final name = (u['display_name'] ?? '').toString().toLowerCase();
        final uname = (u['username'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        return query.isEmpty ||
            name.contains(query) ||
            uname.contains(query) ||
            email.contains(query);
      }).toList();

      matches.sort((a, b) {
        final aInChat = currentConvUserIds.contains(a['id'].toString());
        final bInChat = currentConvUserIds.contains(b['id'].toString());
        if (aInChat && !bInChat) return -1;
        if (!aInChat && bInChat) return 1;
        return (a['display_name'] ?? '').compareTo(b['display_name'] ?? '');
      });

      if (mounted) {
        setState(() {
          _showMentionAutocomplete = matches.isNotEmpty;
          _mentionFilteredUsers = matches.take(8).toList();
        });
      }
      return;
    }

    if (_showMentionAutocomplete && mounted) {
      setState(() => _showMentionAutocomplete = false);
    }
  }

  void _saveDraft() {
    final convId = _selectedConvId;
    if (convId == null || _editingMsg != null) return;
    ChatDrafts.save(ref.read(authProvider).userId ?? '', convId,
        _messageController.text, _replyingToMsg);
  }

  Future<void> _restoreDraft(String convId) async {
    final userId = ref.read(authProvider).userId ?? '';
    final draft = await ChatDrafts.read(userId, convId);
    if (!mounted ||
        _selectedConvId != convId ||
        ref.read(authProvider).userId != userId ||
        _messageController.text.isNotEmpty) return;
    setState(() {
      _replyingToMsg = draft['reply'] is Map
          ? Map<String, dynamic>.from(draft['reply'])
          : null;
      _messageController.text = draft['text']?.toString() ?? '';
    });
  }

  Future<void> _acknowledgeConversation(String convId) async {
    try {
      await ref.read(apiClientProvider).dio.put(ApiEndpoints.markRead(convId));
      if (!mounted) return;
      await ref
          .read(notificationProvider.notifier)
          .markConversationRead(convId);
      if (mounted) {
        setState(() {
          for (final conv in _conversations) {
            if (conv['id']?.toString() == convId) conv['unread_count'] = 0;
          }
        });
      }
    } catch (_) {}
  }

  void _selectMention(Map<String, dynamic> user) {
    final text = _messageController.text;
    final match = RegExp(r'@([^\s@]{0,40})$').firstMatch(text);
    if (match != null) {
      final prefix = text.substring(0, match.start);
      final newText = '$prefix@${user['username']} ';
      _messageController.text = newText;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
    }
    setState(() => _showMentionAutocomplete = false);
  }

  Future<void> _scrollToParentMessage(String parentId) async {
    if (!mounted) return;
    if (!_messages.any((m) => m['id']?.toString() == parentId)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'This message is outside the loaded history or was deleted.')));
      return;
    }
    _highlightTimer?.cancel();
    setState(() => _highlightedMsgId = parentId);
    final conversationId = _selectedConvId;
    final found = await revealMessage(
      controller: _scrollController,
      messageIds: _messages.map((m) => m['id'].toString()).toList(),
      keys: _messageKeys,
      targetId: parentId,
      isCurrent: () => mounted && _selectedConvId == conversationId,
    );
    if (!mounted || _selectedConvId != conversationId) return;
    if (!found) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not locate that message in the loaded chat.')));
      setState(() => _highlightedMsgId = null);
      return;
    }
    _highlightTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _highlightedMsgId = null);
    });
  }

  Widget _buildQuotedReplyCard(String parentId) {
    final parentMsg = _messages.firstWhere(
      (m) => m['id']?.toString() == parentId,
      orElse: () => <String, dynamic>{},
    );

    String parentAuthor = 'User';
    String parentContent = 'Original message';

    if (parentMsg.isNotEmpty) {
      final sid = _normalizeUserId(parentMsg['sender_id']);
      final currentUserId = _normalizeUserId(ref.read(authProvider).userId);
      parentAuthor = sid == currentUserId
          ? ref.read(authProvider).displayName
          : _senderDisplayName(parentMsg);
      parentContent = parentMsg['content']?.toString() ?? 'Message';
    }

    return GestureDetector(
      onTap: () => _scrollToParentMessage(parentId),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.emeraldLight,
            borderRadius: BorderRadius.circular(8),
            border: const Border(
              left: BorderSide(color: AppTheme.primaryTeal, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.reply,
                      size: 12, color: AppTheme.primaryTeal),
                  const SizedBox(width: 4),
                  Text(
                    parentAuthor,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryTeal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                parentContent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.charcoalForeground.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      if (_selectedConvId != null) {
        await _loadMessages(_selectedConvId!, silent: true);
      }
      if (!mounted) return;
      await _loadConversations(silent: true);
      if (mounted) _startPolling();
    });
  }

  Future<void> _loadAll() async {
    setState(() => _isConversationsLoading = true);
    await _loadUsers();
    await _loadGroups();
    await _loadConversations();
    if (_selectedConvId != null) {
      await _selectConversation(_selectedConvId!);
    }
    if (mounted) setState(() => _isConversationsLoading = false);
  }

  Future<void> _loadGroups() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.get(ApiEndpoints.groups);
      List<dynamic> list = [];
      if (res.data is List) {
        list = res.data;
      } else if (res.data is Map && res.data.containsKey('items')) {
        list = res.data['items'];
      }
      _groups = List<Map<String, dynamic>>.from(list);
      for (final g in _groups) {
        final id = g['id']?.toString();
        if (id != null) {
          _groupCache[id] = g;
        }
      }
    } catch (_) {}
  }

  void _fetchUserIfMissing(String userId) {
    final normalizedId = _normalizeUserId(userId);
    if (normalizedId.isEmpty || _userCache.containsKey(normalizedId)) return;
    final api = ref.read(apiClientProvider);
    api.dio.get('${ApiEndpoints.baseUrl}/auth/users/$normalizedId').then((res) {
      if (res.data is Map && mounted) {
        setState(() {
          _cacheUser(res.data);
        });
      }
    }).catchError((_) {});
  }

  Future<void> _loadUsers() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.get(ApiEndpoints.directory);
      List<dynamic> list = [];
      if (res.data is List) {
        list = res.data;
      } else if (res.data is Map && res.data.containsKey('items')) {
        list = res.data['items'];
      }
      _allUsers = List<Map<String, dynamic>>.from(list);
      for (final u in _allUsers) _cacheUser(u);
    } catch (_) {}
  }

  Future<void> _loadConversations({bool silent = false}) =>
      _conversationRefresh.run(() => _fetchConversations(silent: silent));

  Future<void> _fetchConversations({bool silent = false}) async {
    if (!mounted) return;
    if (!silent && mounted) setState(() => _isConversationsLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.get(ApiEndpoints.conversations);
      List<dynamic> list = [];
      if (res.data is List) {
        list = res.data;
      } else if (res.data is Map && res.data.containsKey('items')) {
        list = res.data['items'];
      }
      final newConvs = List<Map<String, dynamic>>.from(list);

      for (final conv in newConvs) {
        if (conv['participant_details'] is List) {
          for (final p in conv['participant_details']) {
            if (p is Map && p['id'] != null) {
              _cacheUser(p);
            }
          }
        }
        if (conv['recipient_id'] != null) {
          _cacheUser({
            'id': conv['recipient_id'],
            'username': conv['recipient_username'] ?? '',
            'display_name':
                conv['recipient_name'] ?? conv['recipient_username'] ?? '',
            'avatar_url': conv['recipient_avatar_url'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _conversations = newConvs;
          _isConversationsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isConversationsLoading = false);
    }
  }

  String? _getDMTargetUserId(Map<String, dynamic> conv) {
    final currentUserId = _normalizeUserId(ref.read(authProvider).userId);

    // Backend ConversationResponse already provides the other participant's
    // id for DMs. Prefer it over list ordering so the current account can
    // never be selected as its own recipient while auth state is settling.
    final directRecipientId = _normalizeUserId(conv['recipient_id']);
    if (directRecipientId.isNotEmpty && directRecipientId != currentUserId) {
      return directRecipientId;
    }

    final participants =
        conv['participants'] ?? _selectedConvDetail?['participants'];
    if (participants is List && participants.isNotEmpty) {
      for (final p in participants) {
        String? pid;
        if (p is Map) {
          pid = _normalizeUserId(p['user_id'] ?? p['id']);
        } else if (p != null) {
          pid = _normalizeUserId(p);
        }
        if (pid != null && pid.isNotEmpty && pid != currentUserId) {
          return pid;
        }
      }
    }

    final recipientId = _normalizeUserId(conv['recipient_id']);
    final targetId = _normalizeUserId(conv['target_id']);
    final detailRecipientId =
        _normalizeUserId(_selectedConvDetail?['recipient_id']);
    final tid = recipientId.isNotEmpty
        ? recipientId
        : (targetId.isNotEmpty ? targetId : detailRecipientId);
    if (tid.isNotEmpty && tid != currentUserId) {
      return tid;
    }

    final lm = conv['last_message'];
    if (lm is Map) {
      final senderId = _normalizeUserId(lm['sender_id']);
      if (senderId.isNotEmpty && senderId != currentUserId) {
        return senderId;
      }
    }

    // If chat with self or only 1 participant
    if (participants is List && participants.isNotEmpty) {
      final firstP = participants.first;
      final pid = _normalizeUserId(
          firstP is Map ? (firstP['user_id'] ?? firstP['id']) : firstP);
      if (pid.isNotEmpty) return pid;
    }

    return null;
  }

  String _getDMRecipientName(Map<String, dynamic> conv) {
    final type = conv['conversation_type'] ?? conv['type'] ?? 'direct';
    if (type == 'channel') {
      return '# ${conv['name'] ?? conv['title'] ?? 'Channel'}';
    }
    if (type == 'group') {
      if (conv['name'] != null &&
          conv['name'].toString().isNotEmpty &&
          conv['name'] != 'Group Chat') {
        return '👥 ${conv['name']}';
      }
      if (conv['title'] != null &&
          conv['title'].toString().isNotEmpty &&
          conv['title'] != 'Group Chat') {
        return '👥 ${conv['title']}';
      }
      final targetId = _normalizeUserId(conv['target_id']);
      if (targetId.isNotEmpty) {
        final g = _groupCache[targetId];
        if (g != null && g['name'] != null && g['name'].toString().isNotEmpty) {
          return '👥 ${g['name']}';
        }
        final match = _groups.firstWhere(
            (g) => _normalizeUserId(g['id']) == targetId,
            orElse: () => <String, dynamic>{});
        if (match.isNotEmpty &&
            match['name'] != null &&
            match['name'].toString().isNotEmpty) {
          return '👥 ${match['name']}';
        }
      }
      return '👥 Group';
    }

    // For direct messages, the participant id is authoritative. Resolve it
    // before trusting conversation display fields, which may be stale or may
    // accidentally contain the signed-in user's name.
    final targetUserId = _getDMTargetUserId(conv);
    if (targetUserId != null) {
      final user = _userForId(targetUserId);
      final canonicalName =
          (user['display_name'] ?? user['username'])?.toString().trim();
      if (canonicalName != null &&
          canonicalName.isNotEmpty &&
          canonicalName != 'Direct Message' &&
          canonicalName != 'Conversation') {
        return canonicalName;
      }
      if (user.isEmpty) _fetchUserIfMissing(targetUserId);
    }

    // 1. Check explicit recipient fields first (from backend ConversationResponse)
    final rName = conv['recipient_name']?.toString() ??
        conv['recipient_username']?.toString();
    if (rName != null &&
        rName.trim().isNotEmpty &&
        rName != 'Direct Message' &&
        rName != 'Conversation') {
      return rName.trim();
    }

    // 2. Check explicit display_name / title / name fields
    final dName = conv['display_name']?.toString() ??
        conv['title']?.toString() ??
        conv['name']?.toString();
    if (dName != null &&
        dName.trim().isNotEmpty &&
        dName != 'Direct Message' &&
        dName != 'Conversation') {
      return dName.trim();
    }

    // 2.5 Check participant_details list
    final pDetails = conv['participant_details'];
    if (pDetails is List && pDetails.isNotEmpty) {
      final currentUserId = _normalizeUserId(ref.read(authProvider).userId);
      for (final p in pDetails) {
        if (p is Map) {
          final pid = _normalizeUserId(p['id'] ?? p['user_id']);
          if (pid != null && pid.isNotEmpty && pid != currentUserId) {
            final name =
                p['display_name']?.toString() ?? p['username']?.toString();
            if (name != null &&
                name.trim().isNotEmpty &&
                name != 'Direct Message' &&
                name != 'Conversation') {
              return name.trim();
            }
          }
        }
      }
    }

    // 3. Resolve other participant user ID

    if (targetUserId != null) {
      final u = _userForId(targetUserId);
      if (u.isNotEmpty) {
        final name = u['display_name']?.toString() ?? u['username']?.toString();
        if (name != null &&
            name.trim().isNotEmpty &&
            name != 'Direct Message' &&
            name != 'Conversation') {
          return name.trim();
        }
      } else {
        _fetchUserIfMissing(targetUserId);
      }
      final match = _allUsers.firstWhere(
          (u) => _normalizeUserId(u['id']) == _normalizeUserId(targetUserId),
          orElse: () => <String, dynamic>{});
      if (match.isNotEmpty) {
        final name =
            match['display_name']?.toString() ?? match['username']?.toString();
        if (name != null &&
            name.trim().isNotEmpty &&
            name != 'Direct Message' &&
            name != 'Conversation') {
          return name.trim();
        }
      }
    }

    return 'Direct Message';
  }

  DateTime _parseToIST(dynamic timestamp) {
    if (timestamp == null)
      return DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    if (timestamp is DateTime) {
      return timestamp.toUtc().add(const Duration(hours: 5, minutes: 30));
    }
    String str = timestamp.toString().trim();
    if (str.isEmpty)
      return DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    if (!str.endsWith('Z') &&
        !str.contains('+') &&
        !RegExp(r'T\d{2}:\d{2}:\d{2}.*-\d{2}').hasMatch(str)) {
      str = '${str}Z';
    }
    try {
      final parsedUtc = DateTime.parse(str).toUtc();
      return parsedUtc.add(const Duration(hours: 5, minutes: 30));
    } catch (_) {
      return DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    }
  }

  String _formatConversationTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = _parseToIST(timestamp);
      final now =
          DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final diff = now.difference(dt);

      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return DateFormat('hh:mm a').format(dt);
      } else if (diff.inDays == 1 ||
          (diff.inDays == 0 && dt.day == now.day - 1)) {
        return 'Yesterday';
      } else if (dt.year == now.year) {
        return DateFormat('d MMM').format(dt);
      } else {
        return DateFormat('dd/MM/yy').format(dt);
      }
    } catch (_) {
      return '';
    }
  }

  String _formatWhatsAppDate(dynamic timestamp) {
    if (timestamp == null) return 'Today';
    try {
      final dt = _parseToIST(timestamp);
      final now =
          DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return 'Today';
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (dt.year == yesterday.year &&
          dt.month == yesterday.month &&
          dt.day == yesterday.day) {
        return 'Yesterday';
      }
      return DateFormat('dd/MM/yy').format(dt);
    } catch (_) {
      return 'Today';
    }
  }

  String _formatTimeIST(dynamic timestamp) {
    if (timestamp == null) return '';
    final dt = _parseToIST(timestamp);
    return DateFormat('hh:mm a').format(dt);
  }

  Color _getSenderNameColor(Map<String, dynamic> user) {
    if (user.isEmpty) return AppTheme.primaryTeal;
    final isSuper = user['is_super_admin'] == true;
    final sysRole = user['role']?.toString().toLowerCase() ?? '';
    if (isSuper || sysRole == 'super_admin' || sysRole == 'superadmin') {
      return const Color(0xFFF59E0B);
    }
    if (sysRole == 'admin') {
      return const Color(0xFFA855F7);
    }
    if (sysRole == 'manager') {
      return const Color(0xFF10B981);
    }
    return AppTheme.primaryTeal;
  }

  bool get _isSuperAdminNotAdded {
    final isSuper = ref.read(authProvider).isSuperAdmin;
    if (!isSuper) return false;
    if (_selectedConvDetail == null) return false;
    final convType = _selectedConvDetail!['conversation_type'] ??
        _selectedConvDetail!['type'];
    if (convType != 'group') return false;

    final targetId = _selectedConvDetail!['target_id']?.toString();
    final currentUserId = _normalizeUserId(ref.read(authProvider).userId);
    if (targetId == null) return false;

    final g = _groupCache[targetId];
    if (g != null) {
      if (g['created_by']?.toString() == currentUserId) return false;
      if (g['current_user_role'] != null) return false;
    }
    return true;
  }

  String _formatSeconds(int totalSec) {
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _checkForceMessageStatus(String groupId) async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio
          .get('${ApiEndpoints.groups}/$groupId/force-message-override');
      if (res.data is Map && res.data['active'] == true) {
        final rem = (res.data['remaining_seconds'] as num?)?.toInt() ?? 0;
        if (rem > 0) {
          _forceMessageTimer?.cancel();
          setState(() => _forceMessageSecondsRemaining = rem);
          _forceMessageTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) {
              t.cancel();
              return;
            }
            if (_forceMessageSecondsRemaining > 1) {
              setState(() => _forceMessageSecondsRemaining--);
            } else {
              t.cancel();
              setState(() => _forceMessageSecondsRemaining = 0);
            }
          });
        }
      } else {
        setState(() => _forceMessageSecondsRemaining = 0);
      }
    } catch (_) {}
  }

  Future<void> _activateForceMessageOverride() async {
    final targetId = _selectedConvDetail?['target_id']?.toString();
    if (targetId == null) return;
    setState(() => _isActivatingForceMessage = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio
          .post('${ApiEndpoints.groups}/$targetId/force-message-override');
      final data = res.data;
      final remaining = (data is Map && data['remaining_seconds'] is num)
          ? (data['remaining_seconds'] as num).toInt()
          : 120;

      _forceMessageTimer?.cancel();
      setState(() {
        _forceMessageSecondsRemaining = remaining;
        _isActivatingForceMessage = false;
      });

      _forceMessageTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_forceMessageSecondsRemaining > 1) {
          setState(() => _forceMessageSecondsRemaining--);
        } else {
          t.cancel();
          setState(() => _forceMessageSecondsRemaining = 0);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('⚡ Force Message override has expired.')),
          );
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF0F766E),
            content: Text('⚡ Force Message override active for 2 minutes!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActivatingForceMessage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to activate Force Message override.')),
        );
      }
    }
  }

  bool get _isCurrentConvViewOnly {
    if (_selectedConvDetail == null) return false;
    final convType = _selectedConvDetail!['conversation_type'] ??
        _selectedConvDetail!['type'];
    if (convType == 'group') {
      final targetId = _selectedConvDetail!['target_id']?.toString();
      final currentUserId = ref.read(authProvider).userId?.toString();
      final isSuper = ref.read(authProvider).isSuperAdmin;
      final isAdmin = ref.read(authProvider).isAdmin;

      if (targetId != null && _groupCache.containsKey(targetId)) {
        final g = _groupCache[targetId]!;
        final createdBy = g['created_by']?.toString();
        // Creator is Group Owner and can ALWAYS post
        if (createdBy != null && createdBy == currentUserId) return false;

        // SuperAdmin not added has dedicated Force Message banner instead
        if (isSuper) return false;
        if (isAdmin) return false;

        final role = g['current_user_role'];
        final perms = g['current_user_permissions'];

        // If explicit role is Owner or Admin or rank <= 50, can send
        if (role is Map) {
          final roleName = role['name']?.toString();
          final rank = role['hierarchy_rank'];
          if (roleName == 'Group Owner' ||
              roleName == 'Group Admin' ||
              (rank is num && rank <= 50)) {
            return false;
          }
          if (roleName == 'Group Viewer' || (rank is num && rank >= 200)) {
            return true;
          }
        }

        // If explicit permissions map exists
        if (perms is Map && perms.containsKey('send_messages')) {
          return perms['send_messages'] == false;
        }
      }
    }
    return false;
  }

  bool get _canCurrentPinMessage {
    final type = _selectedConvDetail?['conversation_type'] ?? 'direct';
    if (type == 'direct' || type == 'dm') return true;

    final currentU = ref.read(authProvider).user;
    if (currentU == null) return false;
    final isSuper = currentU['is_super_admin'] == true;
    final sysRole = currentU['role']?.toString().toLowerCase() ?? '';
    if (isSuper || sysRole == 'admin' || sysRole == 'super_admin') return true;

    if (type == 'group' && _selectedConvDetail?['target_id'] != null) {
      final targetId = _selectedConvDetail!['target_id'].toString();
      final g = _groupCache[targetId];
      if (g != null) {
        final createdBy = g['created_by']?.toString();
        final currentUserId = ref.read(authProvider).userId;
        if (createdBy != null && createdBy == currentUserId) return true;
        final perms = g['current_user_permissions'];
        if (perms is Map &&
            (perms['pin_messages'] == true || perms['pin_message'] == true))
          return true;
        final role = g['current_user_role'];
        if (role is Map &&
            (role['hierarchy_rank'] == 0 ||
                role['name'] == 'Group Owner' ||
                role['name'] == 'Group Admin')) return true;
      }
    }
    return false;
  }

  bool _canDeleteMessage(Map<String, dynamic> msg) {
    final currentU = ref.read(authProvider).user;
    if (currentU == null) return false;
    final isSuper = currentU['is_super_admin'] == true;
    final sysRole = currentU['role']?.toString().toLowerCase() ?? '';
    if (isSuper || sysRole == 'admin' || sysRole == 'super_admin') return true;

    final currentUserId = ref.read(authProvider).userId;
    if (msg['sender_id']?.toString() == currentUserId) return true;

    if (_selectedConvDetail?['conversation_type'] == 'group' &&
        _selectedConvDetail?['target_id'] != null) {
      final targetId = _selectedConvDetail!['target_id'].toString();
      final g = _groupCache[targetId];
      if (g != null) {
        final perms = g['current_user_permissions'];
        if (perms is Map &&
            (perms['delete_other_messages'] == true ||
                perms['delete_messages'] == true)) return true;
        final role = g['current_user_role'];
        if (role is Map &&
            (role['hierarchy_rank'] == 0 ||
                role['name'] == 'Group Owner' ||
                role['name'] == 'Group Admin')) return true;
      }
    }
    return false;
  }

  Future<void> _selectConversation(String convId) async {
    if (!mounted) return;
    if (_selectedConvId != convId) {
      _saveDraft();
      _messageController.removeListener(_onTextChanged);
      _messageController.clear();
      _messageController.addListener(_onTextChanged);
    }
    final cached = _messagesCache[convId];
    final cachedDetail = _conversationDetailCache[convId];
    final cachedPinned = _pinnedMessagesCache[convId];
    final hasCached = cached != null && cached.isNotEmpty;

    setState(() {
      _selectedConvId = convId;
      if (hasCached) {
        _messages = cached;
        _selectedConvDetail = cachedDetail;
        if (cachedPinned != null) _pinnedMsgIds = cachedPinned;
        _isMessagesLoading = false;
      } else {
        _isMessagesLoading = true;
        _messages = [];
        _selectedConvDetail = null;
        _pinnedMsgIds = {};
      }
      _hasNoPermissionToView = false;
      _permissionErrorMsg = null;
      _replyingToMsg = null;
      _editingMsg = null;
      _forceMessageSecondsRemaining = 0;
    });
    _forceMessageTimer?.cancel();
    _restoreDraft(convId);

    if (hasCached && _targetHighlightMsgId == null) {
      _scrollToBottom();
    }

    _subscribeToRealtimeMessages(convId);

    // Opening a conversation acknowledges its messages immediately so the
    // sidebar badge and notification center stay in sync without a reload.
    _acknowledgeConversation(convId);

    // Fetch conversation detail in background
    try {
      final api = ref.read(apiClientProvider);
      final detailRes =
          await api.dio.get('${ApiEndpoints.conversations}/$convId');
      if (detailRes.data is Map && mounted) {
        final detail = Map<String, dynamic>.from(detailRes.data);
        _conversationDetailCache[convId] = detail;
        if (_selectedConvId == convId) {
          setState(() => _selectedConvDetail = detail);
        }
        final convType = detail['conversation_type'] ?? detail['type'];
        final targetId = detail['target_id']?.toString();
        if (convType == 'group' && targetId != null) {
          try {
            final gRes = await api.dio.get('${ApiEndpoints.groups}/$targetId');
            if (gRes.data is Map) {
              _groupCache[targetId] = Map<String, dynamic>.from(gRes.data);
            }
            if (ref.read(authProvider).isSuperAdmin) {
              _checkForceMessageStatus(targetId);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Load messages (silent if we already displayed cached messages)
    await _loadMessages(convId, silent: hasCached);
    if (!mounted || _selectedConvId != convId) return;
    if (!hasCached) setState(() => _isMessagesLoading = false);

    if (_targetHighlightMsgId == null) _scrollToBottom();

    if (_targetHighlightMsgId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _selectedConvId != convId ||
            _targetHighlightMsgId == null) return;
        _scrollToParentMessage(_targetHighlightMsgId!);
        _targetHighlightMsgId = null;
      });
    }
  }

  void _subscribeToRealtimeMessages(String convId) {
    _realtimeMessagesChannel?.unsubscribe();
    _realtimeReactionsChannel?.unsubscribe();
    if (!SupabaseService.instance.hasSession) return;

    _realtimeMessagesChannel = SupabaseService.instance.client
        .channel('public:messages:$convId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (payload) {
            if (!mounted || _selectedConvId != convId) return;
            if (payload.eventType != PostgresChangeEvent.insert) {
              _loadMessages(convId, silent: true);
              return;
            }
            final newRecord = payload.newRecord;
            final newId = newRecord['id']?.toString();
            final currentUserId =
                _normalizeUserId(ref.read(authProvider).userId);

            final alreadyExists =
                _messages.any((m) => m['id']?.toString() == newId);
            if (!alreadyExists && newId != null) {
              final senderId = _normalizeUserId(newRecord['sender_id']);
              final enriched = {
                ...newRecord,
                'sender_name': _senderDisplayName(newRecord),
                'sender_username': _userForId(senderId)['username'] ?? '',
              };
              final updated = List<Map<String, dynamic>>.from(_messages)
                ..add(enriched);
              _messagesCache[convId] = updated;
              setState(() {
                _messages = updated;
              });
              _scrollToBottom();
              _acknowledgeConversation(convId);
              _loadConversations(silent: true);
              if (newRecord['metadata_json'] is Map ||
                  newRecord['metadata'] is Map) {
                _refreshRealtimeAttachment(convId, newId);
              }
            }
          },
        )
        .subscribe();

    _realtimeReactionsChannel = SupabaseService.instance.client
        .channel('public:message-reactions:$convId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) {
            if (!mounted || _selectedConvId != convId) return;
            final record = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            final messageId = record['message_id']?.toString();
            if (messageId != null &&
                _messages
                    .any((message) => message['id']?.toString() == messageId)) {
              _loadMessages(convId, silent: true);
            }
          },
        )
        .subscribe();
  }

  Future<void> _refreshRealtimeAttachment(
      String convId, String messageId) async {
    final current = _messages.firstWhere(
      (message) => message['id']?.toString() == messageId,
      orElse: () => <String, dynamic>{},
    );
    if (current.isEmpty) return;
    final resolved =
        await SupabaseService.instance.resolveMessageAttachment(current);
    if (!mounted || _selectedConvId != convId) return;
    final index = _messages.indexWhere(
      (message) => message['id']?.toString() == messageId,
    );
    if (index == -1) return;
    final updated = List<Map<String, dynamic>>.from(_messages)
      ..[index] = resolved;
    _messagesCache[convId] = updated;
    setState(() => _messages = updated);
  }

  Future<void> _loadMessages(String convId, {bool silent = false}) =>
      (_messageRefreshes[convId] ??= MessageRefresh())
          .run(() => _fetchMessages(convId, silent: silent));

  Future<void> _fetchMessages(String convId, {bool silent = false}) async {
    if (!mounted) return;
    final atRequestStart =
        List<Map<String, dynamic>>.from(_messagesCache[convId] ?? []);
    if (!silent && mounted) setState(() => _isMessagesLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.get(ApiEndpoints.conversationMessages(convId));
      List<dynamic> list = [];
      if (res.data is List) {
        list = res.data;
      } else if (res.data is Map && res.data.containsKey('items')) {
        list = res.data['items'];
      }
      final newMessages = reconcileMessages(
          List<Map<String, dynamic>>.from(list),
          _messagesCache[convId] ?? [],
          atRequestStart);
      if (!mounted) return;

      // REST responses intentionally contain only sender_id. Enrich every
      // message from the directory using that id so each author keeps their
      // own account name instead of inheriting the signed-in user's label.
      for (final message in newMessages) {
        final sender = _userForId(message['sender_id']);
        if (sender.isNotEmpty) {
          message['sender_name'] =
              sender['display_name'] ?? sender['username'] ?? 'Member';
          message['sender_username'] = sender['username'] ?? '';
          message['sender_avatar_url'] = sender['avatar_url'];
        } else {
          message['sender_name'] = _senderDisplayName(message);
        }
      }

      // Sort chronological: oldest at top, newest at bottom (so messages appear downwards)
      newMessages.sort((a, b) {
        final aSeq = a['sequence_num'] ?? a['sequence_number'] ?? 0;
        final bSeq = b['sequence_num'] ?? b['sequence_number'] ?? 0;
        if (aSeq != bSeq && aSeq != 0 && bSeq != 0) {
          return (aSeq as num).compareTo(bSeq as num);
        }
        final aCreated = a['created_at']?.toString() ?? '';
        final bCreated = b['created_at']?.toString() ?? '';
        return aCreated.compareTo(bCreated);
      });

      // Check pinned messages
      final pinnedSet = <String>{};
      for (final m in newMessages) {
        if (m['is_pinned'] == true) {
          pinnedSet.add(m['id'].toString());
        }
      }

      // Store in global memory cache
      _messagesCache[convId] = newMessages;
      _pinnedMessagesCache[convId] = pinnedSet;

      if (mounted && _selectedConvId == convId) {
        setState(() {
          _messages = newMessages;
          _pinnedMsgIds = pinnedSet;
          _isMessagesLoading = false;
          _hasNoPermissionToView = false;
          _permissionErrorMsg = null;
        });
      }
    } catch (e) {
      if (mounted && _selectedConvId == convId) {
        setState(() {
          _isMessagesLoading = false;
          if (e is DioException &&
              (e.response?.statusCode == 403 ||
                  e.response?.statusCode == 401)) {
            _hasNoPermissionToView = true;
            _permissionErrorMsg =
                e.response?.data?['detail']?.toString() ?? 'Access Restricted';
          }
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final content = _messageController.text.trim();
    if (content.isEmpty || _selectedConvId == null) return;

    if (_isCurrentConvViewOnly) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'You are in read-only mode in this group and cannot send messages.')),
        );
      }
      return;
    }

    if (_isSuperAdminNotAdded && _forceMessageSecondsRemaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'You cannot send messages as you are not added in this group. Click "Force Message" to activate 2-minute messaging.')),
        );
      }
      return;
    }

    final api = ref.read(apiClientProvider);

    // If Editing Message
    if (_editingMsg != null) {
      final msgId = _editingMsg!['id'].toString();
      final convId = _selectedConvId!;
      _isSending = true;
      try {
        await api.dio.put(
          '${ApiEndpoints.conversations}/$convId/messages/$msgId',
          data: {'content': content, 'message_type': 'text'},
        );
        if (mounted &&
            _selectedConvId == convId &&
            _messageController.text.trim() == content) {
          _messageController.clear();
          setState(() => _editingMsg = null);
        }
        await _loadMessages(convId, silent: true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update message: $e')),
          );
        }
      } finally {
        _isSending = false;
      }
      return;
    }

    // New Message or Reply
    final sendingConversationId = _selectedConvId!;
    _isSending = true;
    final reply = _replyingToMsg;
    _replyingToMsg = null;
    _messageController.clear();
    final parentId = reply?['id'];
    final currentUserId = _normalizeUserId(ref.read(authProvider).userId);
    final currentUserName = ref.read(authProvider).displayName.trim();
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final optimisticMsg = <String, dynamic>{
      'id': tempId,
      'conversation_id': _selectedConvId,
      'sender_id': currentUserId,
      'sender_name': currentUserName.isNotEmpty ? currentUserName : 'Member',
      'content': content,
      'message_type': 'text',
      if (parentId != null) 'parent_id': parentId,
      'created_at': nowIso,
      'updated_at': nowIso,
      'is_pinned': false,
      'reactions': <String, List<String>>{},
    };

    // 0ms instant local insertion
    final optimisticList = List<Map<String, dynamic>>.from(_messages)
      ..add(optimisticMsg);
    if (_selectedConvId != null) {
      _messagesCache[_selectedConvId!] = optimisticList;
    }
    setState(() {
      _messages = optimisticList;
      _replyingToMsg = null;
    });
    _scrollToBottom();

    // Instant sidebar snippet update
    final convIdx = _conversations
        .indexWhere((c) => c['id']?.toString() == _selectedConvId);
    if (convIdx != -1) {
      _conversations[convIdx]['last_message_content'] = content;
      _conversations[convIdx]['last_message_preview'] = content;
      _conversations[convIdx]['last_message_time'] = nowIso;
      _conversations[convIdx]['last_message'] = {
        'content': content,
        'sender_name': currentUserName.isNotEmpty ? currentUserName : 'Member',
        'created_at': nowIso,
      };
    }

    try {
      final res = await api.dio.post(
        ApiEndpoints.conversationMessages(sendingConversationId),
        data: {
          'content': content,
          'message_type': 'text',
          if (parentId != null) 'parent_id': parentId,
        },
      );
      NotificationSoundService.instance.playMessageSentSound();
      if (res.data is Map && res.data['id'] != null && mounted) {
        final realId = res.data['id'].toString();
        setState(() {
          final cached = List<Map<String, dynamic>>.from(
              _messagesCache[sendingConversationId] ?? []);
          cached.removeWhere((message) => message['id'] == realId);
          final idx = cached.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) {
            cached[idx] = {
              ...cached[idx],
              ...Map<String, dynamic>.from(res.data),
              'id': realId,
            };
          } else {
            cached.add(Map<String, dynamic>.from(res.data));
          }
          _messagesCache[sendingConversationId] = cached;
          if (_selectedConvId == sendingConversationId) _messages = cached;
        });
      }
      // Reconcile the optimistic row with the server immediately. This also
      // handles backends that return a minimal response envelope.
      await _loadMessages(sendingConversationId, silent: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final cached = _messagesCache[sendingConversationId] ?? [];
        cached.removeWhere((message) => message['id'] == tempId);
        _messagesCache[sendingConversationId] = cached;
        if (_selectedConvId == sendingConversationId) _messages = cached;
      });
      if (_selectedConvId == sendingConversationId &&
          _messageController.text.isEmpty) {
        _replyingToMsg = reply;
        _messageController.text = content;
        _messageController.selection =
            TextSelection.collapsed(offset: content.length);
      } else {
        await ChatDrafts.save(
            currentUserId, sendingConversationId, content, reply);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Message was not sent: $error'),
            backgroundColor: Colors.redAccent),
      );
    } finally {
      _isSending = false;
    }
  }

  Future<void> _attachFile() async {
    if (_selectedConvId == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file data.')),
          );
        }
        return;
      }

      const maxUploadBytes = 50 * 1024 * 1024; // 50MB
      if ((file.bytes?.length ?? file.size) > maxUploadBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File exceeds maximum upload limit of 50 MB.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      setState(() => _isUploadingAttachment = true);

      final authState = ref.read(authProvider);
      final uploaderId = authState.userId ?? '';
      final contentType = SupabaseService.getContentType(file.name);
      final cleanName = storageSafeFileName(file.name);
      final messageContent = attachmentMessageContent(file.name, file.bytes!);
      final storagePath =
          'conversations/$_selectedConvId/${DateTime.now().millisecondsSinceEpoch}/$cleanName';
      if (!SupabaseService.instance.hasSession) {
        throw StateError('Sign in to upload attachments.');
      }
      final fileUrl = await SupabaseService.instance.uploadFile(
        bucket: 'attachments',
        path: storagePath,
        bytes: file.bytes!,
        contentType: contentType,
      );
      if (fileUrl == null || fileUrl.isEmpty) {
        throw StateError('Supabase Storage upload failed.');
      }
      await SupabaseService.instance.recordFileAttachment(
        conversationId: _selectedConvId!,
        uploaderId: uploaderId,
        filename: file.name,
        sizeBytes: file.bytes!.length,
        storagePath: storagePath,
        publicUrl: fileUrl,
        contentType: contentType,
      );
      await SupabaseService.instance.sendMessage(
        conversationId: _selectedConvId!,
        senderId: uploaderId,
        content: messageContent,
        messageType: 'file',
        metadata: {
          'file_url': fileUrl,
          'file_name': file.name,
          'storage_path': storagePath,
          'size_bytes': file.bytes!.length,
          'content_type': contentType,
        },
      );

      await _loadMessages(_selectedConvId!, silent: true);
      _scrollToBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded ${file.name} successfully!'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload attachment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Message?',
            style: TextStyle(
                color: AppTheme.charcoalForeground,
                fontWeight: FontWeight.bold)),
        content: const Text(
            'Are you sure you want to delete this message? This action is permanent.',
            style: TextStyle(color: AppTheme.mutedText)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.mutedText))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Message'),
          ),
        ],
      ),
    );

    if (confirm == true && _selectedConvId != null) {
      try {
        final api = ref.read(apiClientProvider);
        await api.dio.delete(
            '${ApiEndpoints.conversations}/$_selectedConvId/messages/${msg['id']}');
        await _loadMessages(_selectedConvId!, silent: true);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Message could not be deleted: $error'),
                backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _togglePinMessage(String msgId, bool isCurrentlyPinned) async {
    if (_selectedConvId == null) return;
    try {
      final api = ref.read(apiClientProvider);
      if (isCurrentlyPinned) {
        await api.dio.delete(
            '${ApiEndpoints.conversations}/$_selectedConvId/messages/$msgId/pin');
        setState(() => _pinnedMsgIds.remove(msgId));
      } else {
        await api.dio.put(
            '${ApiEndpoints.conversations}/$_selectedConvId/messages/$msgId/pin');
        setState(() => _pinnedMsgIds.add(msgId));
      }
      await _loadMessages(_selectedConvId!, silent: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Pin could not be updated: $error'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _toggleReaction(String msgId, String emoji) async {
    if (_selectedConvId == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.put(
        '${ApiEndpoints.conversations}/$_selectedConvId/messages/$msgId/reactions/${Uri.encodeComponent(emoji)}',
      );
      await _loadMessages(_selectedConvId!, silent: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Reaction could not be updated: $error'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Start a New DM Conversation Modal
  Future<void> _startNewDM() async {
    final authState = ref.read(authProvider);
    final currentUserId = authState.userId;
    final otherUsers = _allUsers.where((u) {
      if (u['id'].toString() == currentUserId) return false;
      final isHidden = u['hide_from_direct_message'] == true ||
          u['preferences']?['hide_from_direct_message'] == true;
      if (isHidden && !authState.isSuperAdmin && !authState.isAdmin) {
        return false;
      }
      return true;
    }).toList();

    final selectedUser = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: const [
            Icon(LucideIcons.message_square_plus,
                color: AppTheme.primaryTeal, size: 22),
            SizedBox(width: 10),
            Text('Start Direct Message',
                style: TextStyle(
                    color: AppTheme.charcoalForeground,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: otherUsers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No other contacts found.',
                      style: TextStyle(color: AppTheme.mutedText)))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: otherUsers.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  itemBuilder: (ctx, i) {
                    final u = otherUsers[i];
                    final uId = u['id']?.toString() ?? '';
                    final isOnline =
                        ref.read(presenceProvider.notifier).isOnline(uId);
                    final presenceColor = ref
                        .read(presenceProvider.notifier)
                        .getUserPresenceColor(uId);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      leading: _buildAvatar(
                        name: u['display_name'] ?? u['username'] ?? 'User',
                        avatarUrl: u['avatar_url']?.toString(),
                        type: 'direct',
                        isOnline: isOnline,
                        presenceColor: presenceColor,
                        radius: 20,
                        colorIndex: i,
                      ),
                      title: Text(u['display_name'] ?? u['username'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text('@${u['username']}',
                          style: const TextStyle(
                              color: AppTheme.mutedText, fontSize: 12)),
                      onTap: () => Navigator.pop(ctx, u),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.mutedText))),
        ],
      ),
    );

    if (selectedUser != null) {
      try {
        final api = ref.read(apiClientProvider);
        final res = await api.dio.post(
          '${ApiEndpoints.conversations}/direct',
          data: {'recipient_id': selectedUser['id']},
        );
        final newConvId = res.data['id'].toString();
        await _loadAll();
        _selectConversation(newConvId);
      } catch (_) {}
    }
  }

  /// Create Group / Channel Modal
  Future<void> _showCreateGroupDialog() async {
    final authState = ref.read(authProvider);
    final isSuper = authState.isSuperAdmin;
    final isAdmin = authState.isAdmin;
    final currentUserId = authState.userId;

    if (!isSuper && !isAdmin && currentUserId != null) {
      final ownedCount = _groups
          .where((g) => g['created_by']?.toString() == currentUserId)
          .length;
      if (ownedCount >= 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFEF4444),
              content: Text(
                  'You are limited to a maximum of 2 groups. Please contact an administrator.'),
            ),
          );
        }
        return;
      }
    }

    final nameCtrl = TextEditingController();
    final slugCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String visibility = 'private';
    bool isViewOnly = false;
    bool isCreating = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.emeraldLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.users,
                      color: AppTheme.primaryTeal, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Create New Group',
                    style: TextStyle(
                        color: AppTheme.charcoalForeground,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Group Name *',
                        hintText: 'e.g. Engineering Team, Marketing Hub',
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          slugCtrl.text = val
                              .toLowerCase()
                              .replaceAll(RegExp(r'[^a-z0-9]'), '-')
                              .replaceAll(RegExp(r'-+'), '-')
                              .replaceAll(RegExp(r'^-|-$'), '');
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: slugCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Unique Identifier *',
                        hintText: 'engineering-team',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description (Optional)',
                        hintText: 'What is the purpose of this group?',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    const Text('Visibility',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.charcoalForeground)),
                    const SizedBox(height: 6),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'private',
                      groupValue: visibility,
                      activeColor: AppTheme.primaryTeal,
                      onChanged: (v) => setDialogState(() => visibility = v!),
                      title: const Text('Private 🔒',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Only invited members can access.',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.mutedText)),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'organization',
                      groupValue: visibility,
                      activeColor: AppTheme.primaryTeal,
                      onChanged: (v) => setDialogState(() => visibility = v!),
                      title: const Text('Organization-wide 🌐',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'Available to all users in the organization.',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.mutedText)),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isViewOnly
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFF9FAFB),
                        border: Border.all(
                          color: isViewOnly
                              ? AppTheme.primaryTeal.withValues(alpha: 0.4)
                              : const Color(0xFFE5E7EB),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isViewOnly,
                        activeColor: AppTheme.primaryTeal,
                        title: const Row(
                          children: [
                            Text(
                              'View-Only Group by Default 👁️',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.charcoalForeground),
                            ),
                          ],
                        ),
                        subtitle: const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'All members can only view messages by default. Only the group creator and members with elevated roles can post.',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.mutedText),
                          ),
                        ),
                        onChanged: (v) => setDialogState(() => isViewOnly = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isCreating ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.mutedText)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal),
                onPressed: (nameCtrl.text.trim().isEmpty || isCreating)
                    ? null
                    : () async {
                        setDialogState(() => isCreating = true);
                        try {
                          final api = ref.read(apiClientProvider);
                          final res = await api.dio.post(
                            ApiEndpoints.groups,
                            data: {
                              'name': nameCtrl.text.trim(),
                              'slug': slugCtrl.text.trim().isNotEmpty
                                  ? slugCtrl.text.trim()
                                  : nameCtrl.text
                                      .trim()
                                      .toLowerCase()
                                      .replaceAll(RegExp(r'[^a-z0-9]'), '-'),
                              'description': descCtrl.text.trim(),
                              'visibility': visibility,
                              'is_private': visibility == 'private',
                              'is_view_only': isViewOnly,
                            },
                          );

                          final createdGroup =
                              Map<String, dynamic>.from(res.data);
                          final groupId = createdGroup['id'].toString();
                          if (ctx.mounted) Navigator.pop(ctx);

                          // Create or find group conversation
                          final convRes = await api.dio.post(
                            ApiEndpoints.conversations,
                            data: {
                              'conversation_type': 'group',
                              'target_id': groupId,
                            },
                          );
                          final convId = convRes.data['id'].toString();
                          await _loadAll();
                          _selectConversation(convId);
                        } catch (e) {
                          setDialogState(() => isCreating = false);
                          String errorMsg = 'Failed to create group.';
                          if (e is DioException && e.response?.data is Map) {
                            errorMsg =
                                e.response?.data['message']?.toString() ??
                                    e.response?.data['detail']?.toString() ??
                                    errorMsg;
                          }
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                  content: Text(errorMsg),
                                  backgroundColor: Colors.red.shade700),
                            );
                          }
                        }
                      },
                child: isCreating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Create Group'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFabMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6E4E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.emeraldLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.message_square_plus,
                      color: AppTheme.primaryTeal, size: 22),
                ),
                title: const Text('Start Direct Message',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: const Text('Chat 1-on-1 with a team member',
                    style: TextStyle(color: AppTheme.mutedText, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _startNewDM();
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.users,
                      color: Color(0xFF6D28D9), size: 22),
                ),
                title: const Text('Create Group Chat',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: const Text('Collaborate with multiple members',
                    style: TextStyle(color: AppTheme.mutedText, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateGroupDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEmojiPicker({String? reactionMessageId}) async {
    final searchController = TextEditingController();
    var selectedCategory = _recentEmojis.isNotEmpty ? 'Recent' : 'Smileys';
    var searchQuery = '';

    List<String> emojisFor(String category) {
      if (category == 'Recent') return _recentEmojis;
      if (category == 'Smileys') return _sampleEmojis;
      return _extraEmojiCategories[category] ?? const [];
    }

    final selectedEmoji = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 580),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setPickerState) {
          final categories = <String>[
            if (_recentEmojis.isNotEmpty) 'Recent',
            'Smileys',
            ..._extraEmojiCategories.keys,
          ];
          final source = searchQuery.isEmpty
              ? emojisFor(selectedCategory)
              : categories.expand(emojisFor).toSet().where((emoji) {
                  final keywords = _emojiKeywords[emoji] ?? '';
                  return emoji.contains(searchQuery) ||
                      keywords.contains(searchQuery.toLowerCase());
                }).toList();

          return Padding(
            padding: EdgeInsets.fromLTRB(
                18, 0, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reactionMessageId == null
                            ? 'Choose an emoji'
                            : 'Add or remove reaction',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close emoji picker',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search emojis (try “heart” or “done”)',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) =>
                      setPickerState(() => searchQuery = value.trim()),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return ChoiceChip(
                        label: Text(category),
                        selected:
                            selectedCategory == category && searchQuery.isEmpty,
                        onSelected: (_) => setPickerState(() {
                          selectedCategory = category;
                          searchQuery = '';
                          searchController.clear();
                        }),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: source.isEmpty
                      ? const Center(child: Text('No matching emoji found.'))
                      : GridView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 58,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                          ),
                          itemCount: source.length,
                          itemBuilder: (context, index) {
                            final emoji = source[index];
                            return Tooltip(
                              message: _emojiKeywords[emoji] ?? 'Emoji $emoji',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.pop(sheetContext, emoji),
                                child: Center(
                                  child: Text(emoji,
                                      style: const TextStyle(fontSize: 25)),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
    searchController.dispose();

    if (selectedEmoji == null || !mounted) return;
    setState(() {
      _recentEmojis.remove(selectedEmoji);
      _recentEmojis.insert(0, selectedEmoji);
      if (_recentEmojis.length > 16) _recentEmojis.removeLast();
    });

    if (reactionMessageId != null) {
      await _toggleReaction(reactionMessageId, selectedEmoji);
      return;
    }

    final selection = _messageController.selection;
    final text = _messageController.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _messageController.text = text.replaceRange(start, end, selectedEmoji);
    _messageController.selection =
        TextSelection.collapsed(offset: start + selectedEmoji.length);
    _messageFocusNode.requestFocus();
  }

  Widget _buildMessageReactions(Map<String, dynamic> message) {
    final rawReactions = message['reactions'];
    if (rawReactions is! List || rawReactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        spacing: 6,
        runSpacing: 5,
        children: rawReactions.whereType<Map>().map((raw) {
          final reaction = Map<String, dynamic>.from(raw);
          final emoji = reaction['emoji']?.toString() ?? '';
          final count = reaction['count'] as int? ?? 0;
          final reacted = reaction['reacted'] == true;
          final userIds = reaction['user_ids'] is List
              ? List<dynamic>.from(reaction['user_ids'])
              : const <dynamic>[];
          final names = userIds.map((id) {
            final user = _userForId(id);
            return user['display_name'] ?? user['username'] ?? 'Member';
          }).join(', ');

          return Tooltip(
            message: names.isNotEmpty
                ? '$names reacted $emoji'
                : '$count ${count == 1 ? 'person' : 'people'} reacted',
            child: Semantics(
              button: true,
              label: reacted
                  ? 'Remove $emoji reaction, $count total'
                  : 'Add $emoji reaction, $count total',
              child: InkWell(
                onTap: () => _toggleReaction(message['id'].toString(), emoji),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: reacted
                        ? AppTheme.primaryTeal.withValues(alpha: .14)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: reacted
                          ? AppTheme.primaryTeal
                          : Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Text('$emoji  $count',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showPinnedMessagesDialog() {
    final pinnedMsgs = _messages
        .where((m) => _pinnedMsgIds.contains(m['id']?.toString()))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(LucideIcons.pin, color: AppTheme.primaryTeal, size: 20),
            const SizedBox(width: 8),
            Text('Pinned Messages (${pinnedMsgs.length})',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalForeground)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: pinnedMsgs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No pinned messages in this conversation.',
                          style: TextStyle(color: AppTheme.mutedText))),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: pinnedMsgs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  itemBuilder: (ctx, i) {
                    final m = pinnedMsgs[i];
                    final author = _senderDisplayName(m);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      title: Text(author,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.primaryTeal)),
                      subtitle: Text(m['content']?.toString() ?? '',
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.charcoalForeground),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(LucideIcons.pin_off,
                            size: 16, color: AppTheme.mutedText),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _togglePinMessage(m['id'].toString(), true);
                        },
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _scrollToParentMessage(m['id'].toString());
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close',
                  style: TextStyle(color: AppTheme.mutedText))),
        ],
      ),
    );
  }

  void _openConversationSettings() {
    final selectedConv = _conversations.firstWhere(
      (c) => c['id']?.toString() == _selectedConvId,
      orElse: () => _selectedConvDetail ?? <String, dynamic>{},
    );
    final convObj = selectedConv.isNotEmpty
        ? selectedConv
        : (_selectedConvDetail ?? <String, dynamic>{});
    if (convObj.isEmpty) return;
    final type = convObj['conversation_type'] ?? convObj['type'] ?? 'direct';
    final targetId = convObj['target_id']?.toString() ??
        _selectedConvDetail?['target_id']?.toString();
    if (targetId == null) return;

    final groupName = _getDMRecipientName(convObj);

    if (type == 'group' || type == 'channel') {
      showDialog(
        context: context,
        builder: (ctx) => GroupSettingsDialog(
          group: {'id': targetId, 'name': groupName},
          onGroupUpdated: () => _loadAll(),
        ),
      ).then((_) => _loadAll());
    }
  }

  Widget _buildAvatar({
    required String name,
    String? avatarUrl,
    required String type,
    bool isOnline = false,
    Color? presenceColor,
    double radius = 26,
    int colorIndex = 0,
  }) {
    final cleanName = name.trim().isNotEmpty ? name.trim() : 'U';
    final initial = cleanName[0].toUpperCase();
    final bg = _pastelBgPalette[colorIndex % _pastelBgPalette.length];
    final fg = _pastelTextPalette[colorIndex % _pastelTextPalette.length];

    Widget avatarContent;
    if (type == 'channel') {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFCCFBF1),
        child: Icon(LucideIcons.hash,
            color: AppTheme.primaryTeal, size: radius * 0.9),
      );
    } else if (type == 'group') {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFEDE9FE),
        child: Icon(LucideIcons.users,
            color: const Color(0xFF6D28D9), size: radius * 0.85),
      );
    } else if (avatarUrl != null &&
        avatarUrl.isNotEmpty &&
        avatarUrl.startsWith('http')) {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        backgroundImage: NetworkImage(avatarUrl),
      );
    } else {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(
          initial,
          style: GoogleFonts.plusJakartaSans(
            fontSize: radius * 0.8,
            fontWeight: FontWeight.bold,
            color: fg,
          ),
        ),
      );
    }

    return Stack(
      alignment: Alignment.bottomRight,
      clipBehavior: Clip.none,
      children: [
        avatarContent,
        if (type != 'group' && type != 'channel')
          Positioned(
            right: 0,
            bottom: 0,
            child: PulsingStatusDot(
              color: presenceColor ?? const Color(0xFF10B981),
              size: (radius * 0.46).clamp(8.0, 14.0),
              isOnline: isOnline,
            ),
          ),
      ],
    );
  }

  Widget _buildHoverToolbar(
      Map<String, dynamic> msg, String msgId, bool isOwn, String text) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6E4E0), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add_reaction_outlined,
                size: 16, color: AppTheme.charcoalForeground),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            tooltip: 'Add Reaction',
            onPressed: () => _showEmojiPicker(reactionMessageId: msgId),
          ),
          IconButton(
            icon: const Icon(Icons.reply_rounded,
                size: 16, color: AppTheme.charcoalForeground),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            tooltip: 'Reply',
            onPressed: () => setState(() => _replyingToMsg = msg),
          ),
          if (isOwn)
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 16, color: AppTheme.charcoalForeground),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              tooltip: 'Edit',
              onPressed: () {
                setState(() {
                  _editingMsg = msg;
                  _messageController.text = text;
                });
              },
            ),
          if (_canCurrentPinMessage)
            IconButton(
              icon: Icon(
                _pinnedMsgIds.contains(msgId)
                    ? LucideIcons.pin_off
                    : LucideIcons.pin,
                size: 16,
                color: _pinnedMsgIds.contains(msgId)
                    ? AppTheme.primaryTeal
                    : AppTheme.charcoalForeground,
              ),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              tooltip: _pinnedMsgIds.contains(msgId) ? 'Unpin' : 'Pin',
              onPressed: () =>
                  _togglePinMessage(msgId, _pinnedMsgIds.contains(msgId)),
            ),
          IconButton(
            icon: const Icon(Icons.copy_rounded,
                size: 16, color: AppTheme.charcoalForeground),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            tooltip: 'Copy Text',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
          if (_canDeleteMessage(msg))
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 16, color: Color(0xFFEF4444)),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              tooltip: 'Delete',
              onPressed: () => _deleteMessage(msg),
            ),
        ],
      ),
    );
  }

  Future<void> _startDMWithUser(Map<String, dynamic> user) async {
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) return;
    try {
      final response = await ref.read(apiClientProvider).dio.post(
        '${ApiEndpoints.conversations}/direct',
        data: {'recipient_id': userId},
      );
      final conversationId = response.data['id']?.toString();
      if (conversationId == null || conversationId.isEmpty) {
        throw StateError('Conversation was not created.');
      }
      await _loadConversations(silent: true);
      await _selectConversation(conversationId);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _messageFocusNode.requestFocus();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not start direct message: $error'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _findFriendship(String otherUserId) async {
    final currentUserId = ref.read(authProvider).userId?.toString();
    if (currentUserId == null ||
        !SupabaseService.instance.hasSession ||
        otherUserId.isEmpty) {
      return null;
    }
    try {
      final rows = await SupabaseService.instance.client
          .from('friendships')
          .select()
          .or('and(requester_id.eq.$currentUserId,addressee_id.eq.$otherUserId),and(requester_id.eq.$otherUserId,addressee_id.eq.$currentUserId)')
          .limit(1);
      if (rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);
    } catch (_) {
      // The profile remains usable when the optional friendship migration has
      // not yet been deployed.
    }
    return null;
  }

  Future<void> _changeFriendship(
      Map<String, dynamic> user, String action) async {
    final currentUserId = ref.read(authProvider).userId?.toString();
    final otherUserId = user['id']?.toString() ?? '';
    if (currentUserId == null ||
        otherUserId.isEmpty ||
        !SupabaseService.instance.hasSession) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend service is unavailable.')),
        );
      }
      return;
    }

    try {
      final existing = await _findFriendship(otherUserId);
      switch (action) {
        case 'add':
          if (existing == null) {
            await SupabaseService.instance.requestFriendship(otherUserId);
          }
          break;
        case 'block':
          await SupabaseService.instance.blockUser(otherUserId);
          break;
        case 'remove':
        case 'unblock':
          if (existing != null) {
            await SupabaseService.instance
                .removeFriendship(existing['id'].toString());
          }
          break;
      }
      if (mounted) {
        final name = user['display_name'] ?? user['username'] ?? 'Member';
        final message = switch (action) {
          'add' => 'Friend request sent to $name.',
          'block' => '$name was blocked.',
          'unblock' => '$name was unblocked.',
          _ => '$name was removed from your friends.',
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not update this relationship. Try again.'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _mentionUser(String username) {
    final mention = '@$username ';
    final selection = _messageController.selection;
    final text = _messageController.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _messageController.text = text.replaceRange(start, end, mention);
    _messageController.selection =
        TextSelection.collapsed(offset: start + mention.length);
    _messageFocusNode.requestFocus();
  }

  Future<void> _showUserProfile(Map<String, dynamic> user) async {
    if (user.isEmpty) return;
    final name = user['display_name']?.toString() ??
        user['username']?.toString() ??
        'Member';
    final username = user['username']?.toString() ?? 'member';
    final role = user['is_super_admin'] == true
        ? 'Super Administrator'
        : (user['role']?.toString() ?? 'Member');
    final userId = user['id']?.toString() ?? '';
    final isOnline = userId.isNotEmpty &&
        ref.read(presenceProvider.notifier).isOnline(userId);
    final shouldMessage = userId.isNotEmpty &&
        userId != ref.read(authProvider).userId?.toString();
    final relationship = shouldMessage ? await _findFriendship(userId) : null;
    final relationshipStatus = relationship?['status']?.toString();
    final currentUserId = ref.read(authProvider).userId?.toString();
    final blockedByMe = relationshipStatus == 'blocked' &&
        relationship?['blocked_by']?.toString() == currentUserId;
    final presenceLabel = (user['presence_status'] ?? user['status'])
            ?.toString()
            .replaceAll('_', ' ') ??
        (isOnline ? 'Online' : 'Offline');
    final customStatus = user['custom_status']?.toString();
    final about = user['about']?.toString() ?? user['bio']?.toString();
    final organizationLabels = <String>[
      if (user['department_name']?.toString().isNotEmpty == true)
        user['department_name'].toString(),
      if (user['team_name']?.toString().isNotEmpty == true)
        user['team_name'].toString(),
      if (user['group_name']?.toString().isNotEmpty == true)
        user['group_name'].toString(),
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                height: 92,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF155E75)]),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Close profile',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -38),
                child: Column(children: [
                  Stack(children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: AppTheme.primaryTeal,
                      child: Text(name.characters.first.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800)),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? const Color(0xFF10B981)
                              : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 3),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('@$username',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 3),
                  Text(presenceLabel,
                      style: TextStyle(
                          color: isOnline
                              ? const Color(0xFF059669)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  if (customStatus != null && customStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(customStatus,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13)),
                  ],
                  if (about != null && about.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Text(about,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Chip(
                      label: Text(role),
                      avatar: const Icon(LucideIcons.shield_check, size: 15)),
                  if (organizationLabels.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        children: organizationLabels
                            .map((label) => Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(label,
                                    style: const TextStyle(fontSize: 11))))
                            .toList(),
                      ),
                    ),
                  if (shouldMessage) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              _startDMWithUser(user);
                            },
                            icon: const Icon(LucideIcons.message_square,
                                size: 16),
                            label: const Text('Message'),
                          ),
                        ),
                        if (relationshipStatus == null ||
                            relationshipStatus == 'pending') ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: relationshipStatus == 'pending'
                                  ? null
                                  : () {
                                      Navigator.pop(dialogContext);
                                      _changeFriendship(user, 'add');
                                    },
                              icon: const Icon(LucideIcons.user_plus, size: 16),
                              label: Text(relationshipStatus == 'pending'
                                  ? 'Pending'
                                  : 'Add Friend'),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          tooltip: 'More profile actions',
                          onSelected: (action) {
                            Navigator.pop(dialogContext);
                            switch (action) {
                              case 'mention':
                                _mentionUser(username);
                                break;
                              case 'copy':
                                Clipboard.setData(
                                    ClipboardData(text: '@$username'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Username copied.')),
                                );
                                break;
                              case 'block':
                              case 'unblock':
                              case 'remove':
                                _changeFriendship(user, action);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                                value: 'mention', child: Text('Mention')),
                            const PopupMenuItem(
                                value: 'copy', child: Text('Copy username')),
                            if (relationshipStatus == 'accepted')
                              const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove friend')),
                            PopupMenuItem(
                              value: blockedByMe ? 'unblock' : 'block',
                              child: Text(blockedByMe ? 'Unblock' : 'Block'),
                            ),
                          ],
                          icon: const Icon(Icons.more_horiz),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadMessageAttachment(String url,String name) async {
    try {
      if (!await downloadAttachment(Uri.parse(url),cleanAttachmentName(name))) throw StateError('Unavailable');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not download this attachment. Check access and retry.')));
    }
  }
  Future<void> _openImageAttachment(String url,String name) async {
    try {
      final fresh=await freshAttachmentUri(Uri.parse(url));
      if (fresh==null) throw StateError('Unavailable');
      if (mounted) await _showImageViewer(fresh.toString(),name);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Image is unavailable. Check access and retry.')));
    }
  }
  Future<void> _showImageViewer(String url, String filename) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .9),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF090B10),
        child: Stack(children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: .6,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.image_off,
                          color: Colors.white54, size: 48),
                      SizedBox(height: 12),
                      Text('Image preview is unavailable.',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 18,
            child: Row(children: [
              Expanded(
                  child: Text(filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700))),
              IconButton.filledTonal(
                tooltip: 'Download image',
                onPressed: () => _downloadMessageAttachment(url,filename),
                icon: const Icon(LucideIcons.download),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Close image',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildAttachmentPreview(Map<String, dynamic> msg) {
    final type = msg['message_type']?.toString() ?? 'text';
    final metadata =
        msg['metadata_json'] is Map ? (msg['metadata_json'] as Map) : {};
    final attUrl = msg['attachment_url']?.toString().isNotEmpty == true
        ? msg['attachment_url'].toString()
        : (metadata['file_url']?.toString() ??
            metadata['public_url']?.toString() ??
            '');

    if (type != 'file' && attUrl.isEmpty) return const SizedBox.shrink();

    final fileName = cleanAttachmentName(
      metadata['file_name'] ??
          msg['file_name'] ??
          (msg['content']?.toString().isNotEmpty == true
              ? msg['content']
              : attUrl),
    );
    final isImage = RegExp(r'\.(png|jpe?g|webp|gif)$',caseSensitive:false).hasMatch(fileName);

    if (isImage && attUrl.isNotEmpty) {
      return InkWell(
        onTap: () => _openImageAttachment(attUrl, fileName),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 340),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE6E4E0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Image.network(
                attUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: TextButton.icon(onPressed:()=>_openImageAttachment(attUrl,fileName),
                    icon:const Icon(Icons.refresh),label:const Text('Retry image')),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_rounded,
                          color: Colors.white, size: 15),
                      SizedBox(width: 4),
                      Text('Download',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () async {
        if (attUrl.isNotEmpty) {
          await _downloadMessageAttachment(attUrl,fileName);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Attachment link not available.')),
          );
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE6E4E0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.file_text,
                size: 20, color: AppTheme.primaryTeal),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                fileName,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_rounded,
                      size: 14, color: AppTheme.primaryTeal),
                  SizedBox(width: 4),
                  Text('Download',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryTeal)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the Exact Conversation List matching the user mockup
  Widget _buildConversationListUI(bool isMobile) {
    final authState = ref.watch(authProvider);
    final userName = authState.displayName?.isNotEmpty == true
        ? authState.displayName!
        : (authState.user?['username']?.toString() ?? 'Johan');

    final query = _searchConvController.text.trim().toLowerCase();

    // Filter conversations by tab and search
    List<Map<String, dynamic>> filteredList = [];
    if (_selectedTabIndex == 0) {
      // All Chats
      filteredList = _conversations.where((c) {
        final t = c['conversation_type'] ?? c['type'] ?? 'direct';
        return t != 'channel';
      }).toList();
    } else if (_selectedTabIndex == 1) {
      // Groups
      filteredList = _conversations.where((c) {
        final t = c['conversation_type'] ?? c['type'] ?? 'direct';
        return t == 'group';
      }).toList();
    } else {
      // Contacts (DMs)
      filteredList = _conversations.where((c) {
        final t = c['conversation_type'] ?? c['type'] ?? 'direct';
        return t != 'group' && t != 'channel';
      }).toList();
    }

    if (query.isNotEmpty) {
      filteredList = filteredList.where((c) {
        final title = _getDMRecipientName(c).toLowerCase();
        final lm =
            c['last_message']?['content']?.toString().toLowerCase() ?? '';
        return title.contains(query) || lm.contains(query);
      }).toList();
    }

    return Container(
      width: isMobile ? double.infinity : 380,
      decoration: BoxDecoration(
        color: AppTheme.creamBackground,
        border: Border(
          right: BorderSide(
              color: const Color(0xFFE6E4E0), width: isMobile ? 0 : 1.2),
        ),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (Hello, Johan + Circular Action Buttons) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello,',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: AppTheme.mutedText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            userName,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              color: AppTheme.charcoalForeground,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Circular Outlined Search Button
                        InkWell(
                          onTap: () => setState(
                              () => _isSearchExpanded = !_isSearchExpanded),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFFE6E4E0), width: 1.5),
                            ),
                            child: const Icon(LucideIcons.search,
                                size: 16, color: AppTheme.charcoalForeground),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Circular Outlined More Options Button
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          onSelected: (val) {
                            if (val == 'new_dm') _startNewDM();
                            if (val == 'new_group') _showCreateGroupDialog();
                            if (val == 'refresh') _loadAll();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'new_dm',
                              child: Row(
                                children: [
                                  Icon(LucideIcons.message_square_plus,
                                      size: 18, color: AppTheme.primaryTeal),
                                  SizedBox(width: 10),
                                  Text('New Direct Message',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'new_group',
                              child: Row(
                                children: [
                                  Icon(LucideIcons.users,
                                      size: 18, color: Color(0xFF6D28D9)),
                                  SizedBox(width: 10),
                                  Text('Create Group',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'refresh',
                              child: Row(
                                children: [
                                  Icon(LucideIcons.refresh_cw,
                                      size: 18, color: AppTheme.mutedText),
                                  SizedBox(width: 10),
                                  Text('Refresh Chats',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFFE6E4E0), width: 1.5),
                            ),
                            child: const Icon(Icons.more_vert_rounded,
                                size: 18, color: AppTheme.charcoalForeground),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Expandable Search Bar
              if (_isSearchExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: TextField(
                    controller: _searchConvController,
                    autofocus: true,
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.charcoalForeground),
                    decoration: InputDecoration(
                      hintText: 'Search chats, contacts, messages...',
                      prefixIcon: const Icon(LucideIcons.search,
                          size: 16, color: AppTheme.mutedText),
                      suffixIcon: _searchConvController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () =>
                                  setState(() => _searchConvController.clear()),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Color(0xFFE6E4E0)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),

              // ── Segmented Pill Tab Bar (All Chats | Groups | Contacts) ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F0EC),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _buildPillTab(index: 0, label: 'All Chats'),
                      _buildPillTab(index: 1, label: 'Groups'),
                      _buildPillTab(index: 2, label: 'Contacts'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Conversation List ──
              Expanded(
                child: _isConversationsLoading
                    ? const SingleChildScrollView(
                        child: SkeletonConversationList(count: 8))
                    : (_selectedTabIndex == 2 && filteredList.isEmpty)
                        ? _buildContactsDirectoryView()
                        : filteredList.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.message_square,
                                        size: 48, color: Color(0xFFD6D3D1)),
                                    const SizedBox(height: 12),
                                    Text(
                                      _selectedTabIndex == 1
                                          ? 'No groups yet'
                                          : 'No conversations yet',
                                      style: const TextStyle(
                                          color: AppTheme.mutedText,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: _selectedTabIndex == 1
                                          ? _showCreateGroupDialog
                                          : _startNewDM,
                                      style: FilledButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.primaryTeal),
                                      icon: const Icon(LucideIcons.plus,
                                          size: 16),
                                      label: Text(_selectedTabIndex == 1
                                          ? 'Create Group'
                                          : 'Start Chat'),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                itemCount: filteredList.length,
                                itemBuilder: (ctx, index) {
                                  final conv = filteredList[index];
                                  final convId = conv['id'].toString();
                                  final isSelected =
                                      convId == _selectedConvId && !isMobile;
                                  final type = conv['conversation_type'] ??
                                      conv['type'] ??
                                      'direct';
                                  final displayTitle =
                                      _getDMRecipientName(conv);

                                  // Extract recipient/target details
                                  final targetUserId =
                                      (type != 'group' && type != 'channel')
                                          ? _getDMTargetUserId(conv)
                                          : null;
                                  final isOnline = targetUserId != null &&
                                      ref
                                          .read(presenceProvider.notifier)
                                          .isOnline(targetUserId);
                                  final presenceColor = targetUserId != null
                                      ? ref
                                          .read(presenceProvider.notifier)
                                          .getUserPresenceColor(targetUserId)
                                      : null;
                                  final targetUser = targetUserId != null
                                      ? _userForId(targetUserId)
                                      : <String, dynamic>{};

                                  // Check snippet text & typing / voice / sticker
                                  final lm = conv['last_message'];
                                  String snippet = 'Tap to chat';
                                  final isTyping =
                                      _typingTimers.containsKey(convId);
                                  bool isVoice = false;
                                  bool isSticker = false;
                                  dynamic rawTimestamp =
                                      conv['updated_at'] ?? conv['created_at'];

                                  if (lm is Map) {
                                    rawTimestamp =
                                        lm['created_at'] ?? rawTimestamp;
                                    final content =
                                        lm['content']?.toString() ?? '';
                                    final msgType =
                                        lm['message_type']?.toString();
                                    if (msgType == 'voice' ||
                                        content
                                            .toLowerCase()
                                            .contains('voice message')) {
                                      isVoice = true;
                                      snippet = 'Voice message';
                                    } else if (msgType == 'sticker' ||
                                        content
                                            .toLowerCase()
                                            .contains('sticker')) {
                                      isSticker = true;
                                      snippet = 'Sticker';
                                    } else if (content.isNotEmpty) {
                                      snippet = content;
                                    }
                                  }

                                  final timeStr = _formatConversationTimestamp(
                                      rawTimestamp);
                                  final unreadCount =
                                      (conv['unread_count'] as num?)?.toInt() ??
                                          0;
                                  final isPinned = conv['is_pinned'] == true;

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _selectConversation(convId),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppTheme.emeraldLight
                                              : (type == 'group'
                                                  ? const Color(0xFF3B82F6)
                                                      .withValues(alpha: 0.03)
                                                  : Colors.transparent),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: isSelected
                                              ? Border.all(
                                                  color: AppTheme.emeraldBorder,
                                                  width: 1.2)
                                              : (type == 'group'
                                                  ? Border.all(
                                                      color: const Color(
                                                              0xFF3B82F6)
                                                          .withValues(
                                                              alpha: 0.08),
                                                      width: 1.0)
                                                  : null),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            // Avatar
                                            _buildAvatar(
                                              name: displayTitle,
                                              avatarUrl:
                                                  targetUser?['avatar_url']
                                                      ?.toString(),
                                              type: type,
                                              isOnline: isOnline,
                                              presenceColor: presenceColor,
                                              radius: 26,
                                              colorIndex: index,
                                            ),
                                            const SizedBox(width: 14),
                                            // Title & Snippet
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          displayTitle,
                                                          style: GoogleFonts
                                                              .plusJakartaSans(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: AppTheme
                                                                .charcoalForeground,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      if (isPinned) ...[
                                                        const SizedBox(
                                                            width: 6),
                                                        const Icon(
                                                          Icons
                                                              .push_pin_rounded,
                                                          size: 14,
                                                          color:
                                                              Color(0xFF7C3AED),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      if (isVoice) ...[
                                                        const Icon(
                                                            LucideIcons.mic,
                                                            size: 14,
                                                            color: AppTheme
                                                                .mutedText),
                                                        const SizedBox(
                                                            width: 4),
                                                      ] else if (isSticker) ...[
                                                        const Icon(
                                                            LucideIcons.smile,
                                                            size: 14,
                                                            color: AppTheme
                                                                .mutedText),
                                                        const SizedBox(
                                                            width: 4),
                                                      ],
                                                      Expanded(
                                                        child: Text(
                                                          snippet,
                                                          style: GoogleFonts
                                                              .plusJakartaSans(
                                                            fontSize: 13,
                                                            color: isTyping
                                                                ? AppTheme
                                                                    .primaryTeal
                                                                : AppTheme
                                                                    .mutedText,
                                                            fontStyle: isTyping
                                                                ? FontStyle
                                                                    .italic
                                                                : FontStyle
                                                                    .normal,
                                                            fontWeight:
                                                                unreadCount > 0
                                                                    ? FontWeight
                                                                        .w600
                                                                    : FontWeight
                                                                        .w400,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            // Trailing Timestamp & Unread Badge
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  timeStr,
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                    fontSize: 12,
                                                    color:
                                                        const Color(0xFFA8A29E),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                if (unreadCount > 0)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 7,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppTheme.primaryTeal,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                    ),
                                                    child: Text(
                                                      unreadCount > 99
                                                          ? '99+'
                                                          : '$unreadCount',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  const SizedBox(height: 18),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),

          // ── Floating Action Button (Bottom Right) ──
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton(
              onPressed: () => _showFabMenu(context),
              backgroundColor: AppTheme.primaryTeal,
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(LucideIcons.message_square_plus,
                    color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillTab({required int index, required String label}) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.fastOutSlowIn,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : AppTheme.mutedText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsDirectoryView() {
    final currentUserId = ref.read(authProvider).userId;
    final otherUsers =
        _allUsers.where((u) => u['id'].toString() != currentUserId).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: otherUsers.length,
      itemBuilder: (ctx, i) {
        final u = otherUsers[i];
        final uid = u['id'].toString();
        final isOnline = ref.read(presenceProvider.notifier).isOnline(uid);
        final statusColor =
            ref.read(presenceProvider.notifier).getUserPresenceColor(uid);

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          leading: _buildAvatar(
            name: u['display_name'] ?? u['username'] ?? 'User',
            avatarUrl: u['avatar_url']?.toString(),
            type: 'direct',
            isOnline: isOnline,
            presenceColor: statusColor,
            radius: 24,
            colorIndex: i,
          ),
          title: Text(
            u['display_name'] ?? u['username'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text('@${u['username']}',
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 13)),
          trailing: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryTeal,
              side: const BorderSide(color: AppTheme.primaryTeal),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            ),
            icon: const Icon(LucideIcons.message_square, size: 14),
            label: const Text('Chat',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () async {
              try {
                final api = ref.read(apiClientProvider);
                final res = await api.dio.post(
                  '${ApiEndpoints.conversations}/direct',
                  data: {'recipient_id': u['id']},
                );
                final newConvId = res.data['id'].toString();
                await _loadAll();
                _selectConversation(newConvId);
              } catch (_) {}
            },
          ),
        );
      },
    );
  }

  /// Builds the Right Chat Panel in Light Theme
  Widget _buildChatPanelUI(bool isMobile) {
    if (_selectedConvId == null) {
      return Container(
        color: AppTheme.creamBackground,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(LucideIcons.messages_square,
                  size: 64, color: Color(0xFFD6D3D1)),
              SizedBox(height: 16),
              Text(
                'Select or start a conversation to begin messaging',
                style: TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    final selectedConv = _conversations.firstWhere(
      (c) => c['id']?.toString() == _selectedConvId,
      orElse: () => _selectedConvDetail ?? <String, dynamic>{},
    );
    final convObj = selectedConv.isNotEmpty
        ? selectedConv
        : (_selectedConvDetail ?? <String, dynamic>{});
    final selectedType =
        convObj['conversation_type'] ?? convObj['type'] ?? 'direct';
    final headerTitle = _getDMRecipientName(convObj);

    final targetUserId = (selectedType != 'group' && selectedType != 'channel')
        ? _getDMTargetUserId(convObj)
        : null;
    final isHeaderOnline = targetUserId != null &&
        ref.read(presenceProvider.notifier).isOnline(targetUserId);
    final headerPresenceColor = targetUserId != null
        ? ref.read(presenceProvider.notifier).getUserPresenceColor(targetUserId)
        : null;

    String headerSubtitle = 'Connected';
    if (selectedType == 'channel') {
      headerSubtitle = 'Workspace Channel';
    } else if (selectedType == 'group') {
      headerSubtitle = 'Collaboration Group';
    } else if (targetUserId != null) {
      final u = _userForId(targetUserId);
      final uName = u?['username']?.toString() ?? '';
      final userStatus =
          ref.read(presenceProvider.notifier).getUserStatus(targetUserId);
      final statusLabel = isHeaderOnline
          ? (userStatus == 'online' ? 'Active now' : userStatus.toUpperCase())
          : 'Offline';
      headerSubtitle =
          uName.isNotEmpty ? '@$uName • $statusLabel' : statusLabel;
    }

    final currentUserId = ref.watch(authProvider).userId;

    return Container(
      color: AppTheme.creamBackground,
      child: Column(
        children: [
          // ── Chat Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                  bottom: BorderSide(color: Color(0xFFE6E4E0), width: 1)),
            ),
            child: Row(
              children: [
                if (isMobile ||
                    (widget.fromRoute != null &&
                        widget.fromRoute!.isNotEmpty)) ...[
                  IconButton(
                    icon: const Icon(LucideIcons.arrow_left,
                        color: AppTheme.charcoalForeground, size: 20),
                    tooltip: widget.fromRoute != null ? 'Back' : 'Back',
                    onPressed: () {
                      if (widget.fromRoute != null &&
                          widget.fromRoute!.isNotEmpty) {
                        final dest = widget.fromRoute!.startsWith('/')
                            ? widget.fromRoute!
                            : '/${widget.fromRoute}';
                        context.go(dest);
                        return;
                      }
                      if (context.canPop()) {
                        context.pop();
                        return;
                      }
                      if (isMobile && _selectedConvId != null) {
                        setState(() {
                          _selectedConvId = null;
                          _selectedConvDetail = null;
                        });
                        context.go('/messages');
                        return;
                      }
                      context.go('/dashboard');
                    },
                  ),
                  const SizedBox(width: 4),
                ],
                _buildAvatar(
                  name: headerTitle,
                  avatarUrl: targetUserId != null
                      ? _userForId(targetUserId)['avatar_url']?.toString()
                      : null,
                  type: selectedType,
                  isOnline: isHeaderOnline,
                  presenceColor: headerPresenceColor,
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerTitle,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppTheme.charcoalForeground),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        headerSubtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.mutedText),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Badge(
                    isLabelVisible: _pinnedMsgIds.isNotEmpty,
                    label: Text('${_pinnedMsgIds.length}',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white)),
                    backgroundColor: AppTheme.primaryTeal,
                    child: Icon(
                      _pinnedMsgIds.isNotEmpty
                          ? LucideIcons.pin
                          : LucideIcons.pin_off,
                      size: 18,
                      color: _pinnedMsgIds.isNotEmpty
                          ? AppTheme.primaryTeal
                          : AppTheme.mutedText,
                    ),
                  ),
                  tooltip: 'Pinned Messages',
                  onPressed: _showPinnedMessagesDialog,
                ),
                IconButton(
                  icon: const Icon(LucideIcons.refresh_cw,
                      size: 18, color: AppTheme.mutedText),
                  tooltip: 'Refresh',
                  onPressed: () =>
                      _loadMessages(_selectedConvId!, silent: false),
                ),
                if (selectedType == 'group' || selectedType == 'channel')
                  IconButton(
                    icon: const Icon(LucideIcons.settings,
                        size: 18, color: AppTheme.mutedText),
                    tooltip: 'Settings',
                    onPressed: _openConversationSettings,
                  ),
              ],
            ),
          ),

          // ── Messages Stream ──
          Expanded(
            child: _isMessagesLoading
                ? const SkeletonChatView()
                : _hasNoPermissionToView
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEF4444)),
                          ),
                          child: const Text('Access Restricted',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFEF4444))),
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(LucideIcons.message_square,
                                    size: 48, color: Color(0xFFD6D3D1)),
                                SizedBox(height: 12),
                                Text(
                                    'No messages yet. Send a message to start!',
                                    style: TextStyle(
                                        color: AppTheme.mutedText,
                                        fontSize: 14)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (ctx, i) {
                              final msg = _messages[i];
                              final msgId =
                                  msg['id']?.toString() ?? i.toString();
                              final senderId =
                                  _normalizeUserId(msg['sender_id']);
                              final isOwn =
                                  senderId == _normalizeUserId(currentUserId);
                              final text = msg['content']?.toString() ?? '';
                              final parentId = msg['parent_id']?.toString();
                              final isPinned = _pinnedMsgIds.contains(msgId);
                              final isHighlighted = msgId == _highlightedMsgId;

                              final senderUser = _userForId(senderId);
                              final displayName = _senderDisplayName(msg);
                              final isHovered = _hoveredMsgId == msgId ||
                                  _reactionPickerMsgId == msgId;

                              // Date divider calculation
                              bool showDateDivider = false;
                              String dividerLabel = '';
                              if (i == 0) {
                                showDateDivider = true;
                                dividerLabel =
                                    _formatWhatsAppDate(msg['created_at']);
                              } else {
                                final prevDate = _formatWhatsAppDate(
                                    _messages[i - 1]['created_at']);
                                final currDate =
                                    _formatWhatsAppDate(msg['created_at']);
                                if (prevDate != currDate) {
                                  showDateDivider = true;
                                  dividerLabel = currDate;
                                }
                              }

                              final timeStr = _formatTimeIST(msg['created_at']);

                              return Column(
                                key: _messageKeys.putIfAbsent(
                                    msgId, () => GlobalKey()),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showDateDivider)
                                    Center(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F0EC),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                              color: const Color(0xFFE6E4E0)),
                                        ),
                                        child: Text(
                                          dividerLabel,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.mutedText),
                                        ),
                                      ),
                                    ),
                                  MouseRegion(
                                    onEnter: (_) =>
                                        setState(() => _hoveredMsgId = msgId),
                                    onExit: (_) => setState(() {
                                      if (_hoveredMsgId == msgId)
                                        _hoveredMsgId = null;
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Align(
                                        alignment: isOwn
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              constraints: const BoxConstraints(
                                                  maxWidth: 440, minWidth: 80),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isHighlighted
                                                    ? const Color(0xFFFEF08A)
                                                    : (isOwn
                                                        ? AppTheme.primaryTeal
                                                        : Colors.white),
                                                borderRadius: BorderRadius.only(
                                                  topLeft:
                                                      const Radius.circular(18),
                                                  topRight:
                                                      const Radius.circular(18),
                                                  bottomLeft: Radius.circular(
                                                      isOwn ? 18 : 4),
                                                  bottomRight: Radius.circular(
                                                      isOwn ? 4 : 18),
                                                ),
                                                border: Border.all(
                                                  color: isHighlighted
                                                      ? const Color(0xFFEAB308)
                                                      : (isOwn
                                                          ? Colors.transparent
                                                          : const Color(
                                                              0xFFE6E4E0)),
                                                  width: 1.2,
                                                ),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x0A000000),
                                                    blurRadius: 4,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (!isOwn &&
                                                      selectedType !=
                                                          'direct') ...[
                                                    InkWell(
                                                      onTap: () =>
                                                          _showUserProfile(
                                                              senderUser),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 2,
                                                                vertical: 1),
                                                        child: Text(
                                                          displayName,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 12.5,
                                                            color:
                                                                _getSenderNameColor(
                                                                    senderUser),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                  ],
                                                  if (parentId != null)
                                                    _buildQuotedReplyCard(
                                                        parentId),
                                                  RichMarkdownText(
                                                    text: text,
                                                    textStyle: TextStyle(
                                                      color: isOwn
                                                          ? Colors.white
                                                          : const Color(
                                                              0xFF0F172A),
                                                      fontSize: 14,
                                                      height: 1.45,
                                                      fontFamilyFallback:
                                                          kEmojiFontFallback,
                                                    ),
                                                    allUsers: _allUsers,
                                                    onMentionTap:
                                                        _showUserProfile,
                                                  ),
                                                  _buildAttachmentPreview(msg),
                                                  _buildMessageReactions(msg),
                                                  const SizedBox(height: 4),
                                                  Align(
                                                    alignment:
                                                        Alignment.bottomRight,
                                                    child: Text(
                                                      timeStr,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: isOwn
                                                            ? Colors.white70
                                                            : AppTheme
                                                                .mutedText,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isPinned)
                                              Positioned(
                                                top: -6,
                                                right: isOwn ? null : -6,
                                                left: isOwn ? -6 : null,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(3),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Color(0xFFEDE9FE),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                      Icons.push_pin_rounded,
                                                      size: 12,
                                                      color: Color(0xFF7C3AED)),
                                                ),
                                              ),
                                            if (isHovered)
                                              Positioned(
                                                top: -24,
                                                left: isOwn ? 0 : null,
                                                right: isOwn ? null : 0,
                                                child: _buildHoverToolbar(
                                                    msg, msgId, isOwn, text),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
          ),

          // ── Bottom Composer or View-Only / SuperAdmin Force Message Banner ──
          if (_isCurrentConvViewOnly)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.eye,
                        color: Color(0xFF475569), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'You have view-only access to this group',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'You can only view messages. Contact the group creator or an administrator for messaging permissions.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (_isSuperAdminNotAdded && _forceMessageSecondsRemaining <= 0)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.shield_alert,
                        color: Color(0xFFD97706), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'You cannot send messages as you are not added in this group.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Super Admin Override is available to temporarily send messages for 2 minutes.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isActivatingForceMessage
                        ? null
                        : _activateForceMessageOverride,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isActivatingForceMessage
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(LucideIcons.zap, size: 16),
                    label: const Text('Force Message',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ),
                ],
              ),
            )
          else ...[
            if (_isSuperAdminNotAdded && _forceMessageSecondsRemaining > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: const Color(0xFFFEF3C7),
                child: Row(
                  children: [
                    const Icon(LucideIcons.zap,
                        size: 15, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Text(
                      '⚡ Force Message Active: ${_formatSeconds(_forceMessageSecondsRemaining)} remaining',
                      style: const TextStyle(
                        color: Color(0xFFB45309),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'SuperAdmin Override (2m)',
                      style: TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            if (_replyingToMsg != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppTheme.emeraldLight,
                child: Row(
                  children: [
                    const Icon(Icons.reply,
                        size: 16, color: AppTheme.primaryTeal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying: "${_replyingToMsg!['content']}"',
                        style: const TextStyle(
                            color: AppTheme.primaryTeal,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: AppTheme.mutedText),
                      onPressed: () => setState(() => _replyingToMsg = null),
                    ),
                  ],
                ),
              ),
            if (_editingMsg != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFFFEF3C7),
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 16, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Editing message...',
                          style: TextStyle(
                              color: Color(0xFFB45309),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: AppTheme.mutedText),
                      onPressed: () => setState(() {
                        _editingMsg = null;
                        _messageController.clear();
                      }),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border:
                    Border(top: BorderSide(color: Color(0xFFE6E4E0), width: 1)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.paperclip,
                        color: AppTheme.mutedText),
                    onPressed: _attachFile,
                    tooltip: 'Attach File',
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.smile,
                        color: AppTheme.mutedText),
                    onPressed: _showEmojiPicker,
                    tooltip: 'Emoji Picker',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          _sendMessage();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: 5,
                        style:
                            const TextStyle(color: AppTheme.charcoalForeground),
                        decoration: InputDecoration(
                          hintText: 'Type a message or @mention...',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F4),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal),
                    onPressed: _sendMessage,
                    icon: const Icon(LucideIcons.send,
                        size: 18, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 768;

    return Scaffold(
      backgroundColor: AppTheme.creamBackground,
      body: isMobile
          ? (_selectedConvId == null
              ? _buildConversationListUI(true)
              : _buildChatPanelUI(true))
          : Row(
              children: [
                _buildConversationListUI(false),
                Expanded(child: _buildChatPanelUI(false)),
              ],
            ),
    );
  }
}
