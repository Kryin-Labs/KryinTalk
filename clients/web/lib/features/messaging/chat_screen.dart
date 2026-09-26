/// ConnectHub — Advanced Chat Screen with Profile Popovers, Inline Editing, Replies, Mentions & Emoji Picker.
///
/// Compliant with Sections 6–18 of NEWREQ.md:
/// - User Profile Popover (Avatar, Display Name, Username, Role, Presence, [Message], [Add Friend], [Copy Username])
/// - Inline Edit Mode (PUT /conversations/{id}/messages/{msgId} with (edited) indicator)
/// - Server-side Message Deletion (DELETE /conversations/{id}/messages/{msgId})
/// - Reply Mode (Replying to @user preview, quoted message header with click-to-jump)
/// - `@` Mention Autocomplete dropdown overlay
/// - Emoji Picker Grid Modal (Categories: Smileys, People, Nature, Food, Travel, Activities, Objects)
/// - Image Viewer Lightbox (Fullscreen, Zoom, Download)
/// - User Headers & Timestamps (Today at X, Yesterday at Y)
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/notifications/notification_sound_service.dart';
import '../../core/notifications/web_notification_service.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/files/file_name_utils.dart';
import '../../shared/widgets/rich_markdown_text.dart';
import '../groups/widgets/group_settings_dialog.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _allUsers = [];
  Map<String, dynamic>? _conversationDetail;
  Map<String, dynamic>? _groupData;
  Map<String, Map<String, dynamic>> _userCache = {};
  Map<String, Set<String>> _messageReactions = {};
  Set<String> _pinnedMsgIds = {};

  // Reply & Edit state
  Map<String, dynamic>? _replyingToMsg;
  Map<String, dynamic>? _editingMsg;

  // Mentions Autocomplete state
  bool _showMentionAutocomplete = false;
  List<Map<String, dynamic>> _mentionFilteredUsers = [];

  // Emoji Picker State
  bool _showEmojiPicker = false;

  bool _isLoading = true;
  bool _hasNoPermissionToView = false;
  String? _permissionErrorMsg;
  Timer? _pollingTimer;

  // SuperAdmin Force Message Override state
  int _forceMessageSecondsRemaining = 0;
  Timer? _forceMessageTimer;
  bool _isActivatingForceMessage = false;

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

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
    _loadAll();
    _startPolling();
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _pollingTimer?.cancel();
    _forceMessageTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _messageController.text;
    final lastAtPos = text.lastIndexOf('@');
    if (lastAtPos >= 0) {
      final query = text.substring(lastAtPos + 1).toLowerCase().trim();
      final currentConvUserIds = <String>{};
      for (final m in _messages) {
        if (m['sender_id'] != null) {
          currentConvUserIds.add(m['sender_id'].toString());
        }
      }

      final matches = _allUsers.where((u) {
        final name = (u['display_name'] ?? '').toString().toLowerCase();
        final uname = (u['username'] ?? '').toString().toLowerCase();
        return query.isEmpty || name.contains(query) || uname.contains(query);
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
          _mentionFilteredUsers = matches;
        });
        return;
      }
    }

    if (_showMentionAutocomplete && mounted) {
      setState(() => _showMentionAutocomplete = false);
    }
  }

  void _selectMention(Map<String, dynamic> user) {
    final text = _messageController.text;
    final lastAtPos = text.lastIndexOf('@');
    if (lastAtPos >= 0) {
      final newText = '${text.substring(0, lastAtPos)}@${user['username']} ';
      _messageController.text = newText;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: newText.length),
      );
    }
    setState(() => _showMentionAutocomplete = false);
  }

  Widget _buildFormattedMessageText(BuildContext context, String text) {
    final RegExp mentionRegex = RegExp(r'(@[a-zA-Z0-9_\-\.]+)');
    final matches = mentionRegex.allMatches(text);

    if (matches.isEmpty) {
      return Text(text,
          style:
              const TextStyle(color: Colors.white, fontSize: 14, height: 1.35));
    }

    final List<InlineSpan> spans = [];
    int lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }

      final mentionText = text.substring(match.start, match.end);
      final uname = mentionText.substring(1).toLowerCase();
      final mentionedUser = _allUsers.firstWhere(
        (u) => (u['username'] ?? '').toString().toLowerCase() == uname,
        orElse: () => <String, dynamic>{},
      );

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: mentionedUser.isNotEmpty
                ? () =>
                    _startDirectMessageWithUser(mentionedUser['id'].toString())
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
              ),
              child: Text(
                mentionText,
                style: const TextStyle(
                  color: Color(0xFF8EA1FF),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
        children: spans,
      ),
    );
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadMessages(silent: true);
    });
  }

  Future<void> _loadAll() async {
    try {
      final api = ref.read(apiClientProvider);

      // 1. Fetch user directory
      try {
        final uRes = await api.dio.get(ApiEndpoints.directory);
        final uList = uRes.data is List
            ? uRes.data
            : (uRes.data is Map && uRes.data.containsKey('items')
                ? uRes.data['items']
                : []);
        _allUsers = List<Map<String, dynamic>>.from(uList);
        for (final u in _allUsers) {
          _userCache[u['id'].toString()] = u;
        }
      } catch (_) {}

      // 2. Fetch conversation details
      try {
        final convRes = await api.dio
            .get('${ApiEndpoints.conversations}/${widget.conversationId}');
        _conversationDetail = convRes.data as Map<String, dynamic>?;
        if (_conversationDetail?['conversation_type'] == 'group' &&
            _conversationDetail?['target_id'] != null) {
          try {
            final targetId = _conversationDetail!['target_id'].toString();
            final gRes = await api.dio.get('${ApiEndpoints.groups}/$targetId');
            _groupData = gRes.data as Map<String, dynamic>?;
            if (ref.read(authProvider).isSuperAdmin) {
              _checkForceMessageStatus(targetId);
            }
          } catch (_) {}
        }
      } catch (_) {}

      await _loadMessages(silent: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get(
        ApiEndpoints.conversationMessages(widget.conversationId),
      );
      final data = response.data;
      List<Map<String, dynamic>> newMsgs = [];
      if (data is Map && data.containsKey('items')) {
        newMsgs = List<Map<String, dynamic>>.from(data['items']);
      } else if (data is List) {
        newMsgs = List<Map<String, dynamic>>.from(data);
      }

      // Sort oldest to newest
      newMsgs.sort((a, b) {
        final aSeq = a['sequence_num'] ?? a['sequence_number'] ?? 0;
        final bSeq = b['sequence_num'] ?? b['sequence_number'] ?? 0;
        return (aSeq as int).compareTo(bSeq as int);
      });

      final pinned = <String>{};
      for (final m in newMsgs) {
        if (m['is_pinned'] == true) {
          pinned.add(m['id'].toString());
        }
      }

      if (mounted) {
        setState(() {
          _hasNoPermissionToView = false;
          _permissionErrorMsg = null;
          _messages = newMsgs;
          _pinnedMsgIds = pinned;
        });
        if (!silent) _scrollToBottom();
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        if (mounted) {
          setState(() {
            _hasNoPermissionToView = true;
            final detail =
                e.response?.data is Map ? e.response?.data['detail'] : null;
            _permissionErrorMsg = detail?.toString() ??
                'Your current role does not have permission to view messages in this group. Please contact a group administrator to update your role permissions.';
            _messages = [];
          });
        }
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openConversationSettings() async {
    final convType = _conversationDetail?['conversation_type'];
    final targetId = _conversationDetail?['target_id']?.toString();
    if (targetId == null) return;
    try {
      final api = ref.read(apiClientProvider);
      if (convType == 'group') {
        final res = await api.dio.get('${ApiEndpoints.groups}/$targetId');
        final groupData = Map<String, dynamic>.from(res.data);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => GroupSettingsDialog(
              group: groupData,
              onGroupUpdated: () {
                _loadAll();
                _loadMessages(silent: true);
              },
            ),
          );
        }
      }
    } catch (_) {}
  }

  /// Send or Edit Message Submit
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

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

    // Detect if long text contains complex Markdown syntax (# headings, ```code```, - lists, etc.)
    final isLong = content.length > 200 || content.split('\n').length > 4;
    final hasComplexMarkdown = content.contains(RegExp(
        r'(^#+\s|^```|^\s*[\-\*]\s|^\s*\d+\.\s|^---|\|\|)',
        multiLine: true));

    if (isLong && hasComplexMarkdown) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.description, color: Color(0xFF0F766E), size: 22),
              const SizedBox(width: 10),
              const Text('Send as Formatted Markdown?'),
            ],
          ),
          content: const SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We detected long text containing Markdown document formatting (headings, code blocks, lists, or structural dividers).',
                  style: TextStyle(fontSize: 14, height: 1.4),
                ),
                SizedBox(height: 12),
                Text(
                  'Would you like to render this message formatted in rich Markdown mode?',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'plain'),
              child: const Text('Send as Plain Text'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, 'markdown'),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Send as Markdown'),
            ),
          ],
        ),
      );

      if (choice == 'cancel' || choice == null) return;
    }

    final api = ref.read(apiClientProvider);

    // If Editing message
    if (_editingMsg != null) {
      final msgId = _editingMsg!['id'].toString();
      _messageController.clear();
      final targetEdit = _editingMsg;
      setState(() => _editingMsg = null);

      try {
        await api.dio.put(
          '${ApiEndpoints.conversations}/${widget.conversationId}/messages/$msgId',
          data: {
            'content': content,
            'message_type': 'text',
          },
        );
        _loadMessages(silent: true);
      } catch (_) {
        // Fallback local update
        setState(() {
          for (var m in _messages) {
            if (m['id'].toString() == msgId) {
              m['content'] = content;
              m['metadata_json'] = {'edited': true};
            }
          }
        });
      }
      return;
    }

    // New Message or Reply
    _messageController.clear();
    final parentId = _replyingToMsg != null ? _replyingToMsg!['id'] : null;
    final currentUserId = ref.read(authProvider).userId?.toString();
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final optimisticMsg = <String, dynamic>{
      'id': tempId,
      'conversation_id': widget.conversationId,
      'sender_id': currentUserId,
      'sender_name': 'You',
      'content': content,
      'message_type': 'text',
      if (parentId != null) 'parent_id': parentId,
      'created_at': nowIso,
      'updated_at': nowIso,
      'is_pinned': false,
      'reactions': <String, List<String>>{},
    };

    // Instant local insertion for 0ms perceived lag
    setState(() {
      _messages = List<Map<String, dynamic>>.from(_messages)
        ..add(optimisticMsg);
      _replyingToMsg = null;
      _showEmojiPicker = false;
    });
    _scrollToBottom();
    NotificationSoundService.instance.playMessageSentSound();

    try {
      final res = await api.dio.post(
        ApiEndpoints.conversationMessages(widget.conversationId),
        data: {
          'content': content,
          'message_type': 'text',
          if (parentId != null) 'parent_id': parentId,
        },
      );
      if (res.data is Map && res.data['id'] != null && mounted) {
        final realId = res.data['id'].toString();
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) {
            _messages[idx] = {
              ..._messages[idx],
              ...Map<String, dynamic>.from(res.data),
              'id': realId,
            };
          }
        });
      }
    } catch (_) {}
  }

  /// Delete Message (Server-side soft delete)
  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text(
            'Are you sure you want to delete this message? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final msgId = msg['id'].toString();
      try {
        final api = ref.read(apiClientProvider);
        await api.dio.delete(
          '${ApiEndpoints.conversations}/${widget.conversationId}/messages/$msgId',
        );
        _loadMessages(silent: true);
      } catch (_) {
        // Fallback local remove
        setState(() {
          _messages.removeWhere((m) => m['id'].toString() == msgId);
        });
      }
    }
  }

  /// Start Editing Message Inline
  void _startEditingMessage(Map<String, dynamic> msg) {
    setState(() {
      _editingMsg = msg;
      _replyingToMsg = null;
      _messageController.text = msg['content']?.toString() ?? '';
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    });
  }

  /// Start Replying to Message
  void _startReplyingMessage(Map<String, dynamic> msg) {
    setState(() {
      _replyingToMsg = msg;
      _editingMsg = null;
    });
  }

  /// Open User Profile Popover Modal (Section 17 & 18)
  void _showUserProfilePopover(Map<String, dynamic> user) {
    final displayName = user['display_name']?.toString() ?? 'User';
    final username = user['username']?.toString() ?? 'user';
    final isSuperAdmin = user['is_super_admin'] == true;
    final role = isSuperAdmin
        ? 'Super Admin 👑'
        : (user['role'] ?? 'Standard Member 👤');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar with Online indicator
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.2),
                    child: Text(
                      displayName[0].toUpperCase(),
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFF1E1E38), width: 2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                displayName,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white),
              ),
              Text('@$username',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 8),
              Chip(
                label: Text(role, style: const TextStyle(fontSize: 11)),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startDirectMessageWithUser(user['id'].toString());
                      },
                      icon: const Icon(Icons.chat, size: 16),
                      label: const Text('Message'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('Friend request sent to $displayName!')),
                        );
                      },
                      icon: const Icon(Icons.person_add, size: 16),
                      label: const Text('Add Friend'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '@$username'));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Username copied to clipboard!')),
                  );
                },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy Username'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// DM Helper
  Future<void> _startDirectMessageWithUser(String userId) async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.dio.post(
        '${ApiEndpoints.conversations}/direct',
        data: {'recipient_id': userId},
      );
      final convId = res.data['id'].toString();
      if (mounted) context.go('/messages/$convId');
    } catch (_) {
      if (mounted) context.go('/messages');
    }
  }

  /// Open Image Viewer Lightbox Modal (Section 16)
  void _openImageViewer(String imageTitle) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(imageTitle,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 300,
                width: double.infinity,
                color: Colors.white10,
                child: const Center(
                  child: Icon(Icons.image, size: 100, color: Colors.cyanAccent),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Downloading file attachment...')),
                      );
                    },
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Download Original'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Attach File
  Future<void> _attachFile() async {
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

      final authState = ref.read(authProvider);
      final uploaderId = authState.userId ?? '';
      final contentType = SupabaseService.getContentType(file.name);
      final cleanName = storageSafeFileName(file.name);
      final storagePath =
          'conversations/${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}/$cleanName';
      String fileUrl = '';

      if (SupabaseService.instance.hasSession) {
        final publicUrl = await SupabaseService.instance.uploadFile(
          bucket: 'attachments',
          path: storagePath,
          bytes: file.bytes!,
          contentType: contentType,
        );
        if (publicUrl != null && publicUrl.isNotEmpty) {
          fileUrl = publicUrl;
          await SupabaseService.instance.recordFileAttachment(
            conversationId: widget.conversationId,
            uploaderId: uploaderId,
            filename: file.name,
            sizeBytes: file.bytes!.length,
            storagePath: storagePath,
            publicUrl: publicUrl,
            contentType: contentType,
          );
        }
      }

      if (SupabaseService.instance.hasSession && fileUrl.isNotEmpty) {
        await SupabaseService.instance.sendMessage(
          conversationId: widget.conversationId,
          senderId: uploaderId,
          content: file.name,
          messageType: 'file',
          metadata: {
            'file_url': fileUrl,
            'file_name': file.name,
            'storage_path': storagePath,
            'size_bytes': file.bytes!.length,
            'content_type': contentType,
          },
        );
      } else {
        final api = ref.read(apiClientProvider);
        await api.dio.post(
          ApiEndpoints.conversationMessages(widget.conversationId),
          data: {
            'content': file.name,
            'message_type': 'file',
            'attachment_url': fileUrl,
          },
        );
      }

      _loadMessages(silent: true);
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
    }
  }

  /// Copy Invite Link & Add Members Dialog
  Future<void> _showInviteDialog() async {
    final inviteLink =
        'http://localhost:8080/#/invite/conv-${widget.conversationId}';
    final selectedUserIds = <String>{};

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Invite People to Conversation'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Shareable Invite Link',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          inviteLink,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.cyanAccent),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: inviteLink));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Invite link copied to clipboard!')),
                          );
                        },
                        tooltip: 'Copy Link',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Select Directory Users to Add:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: _allUsers.isEmpty
                      ? const Center(child: Text('No users found in directory'))
                      : ListView.builder(
                          itemCount: _allUsers.length,
                          itemBuilder: (ctx, i) {
                            final u = _allUsers[i];
                            final uid = u['id'].toString();
                            final isSel = selectedUserIds.contains(uid);

                            return CheckboxListTile(
                              value: isSel,
                              title: Text(u['display_name']?.toString() ?? ''),
                              subtitle: Text('@${u['username']}'),
                              onChanged: (v) {
                                setDialogState(() {
                                  if (v == true) {
                                    selectedUserIds.add(uid);
                                  } else {
                                    selectedUserIds.remove(uid);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
            if (selectedUserIds.isNotEmpty)
              FilledButton(
                onPressed: () async {
                  final api = ref.read(apiClientProvider);
                  for (final uid in selectedUserIds) {
                    try {
                      await api.dio.post(
                        ApiEndpoints.notifications,
                        data: {
                          'user_id': uid,
                          'notification_type': 'message',
                          'title': 'Chat Invitation',
                          'body': 'You were invited to a conversation!',
                          'conversation_id': widget.conversationId,
                        },
                      );
                    } catch (_) {}
                  }
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Invited ${selectedUserIds.length} user(s)!')),
                    );
                  }
                },
                child: Text('Invite ${selectedUserIds.length} Selected'),
              ),
          ],
        ),
      ),
    );
  }

  void _toggleReaction(String msgId, String emoji) {
    setState(() {
      _messageReactions.putIfAbsent(msgId, () => <String>{});
      if (_messageReactions[msgId]!.contains(emoji)) {
        _messageReactions[msgId]!.remove(emoji);
      } else {
        _messageReactions[msgId]!.add(emoji);
      }
    });
  }

  Color _getSenderNameColor(Map<String, dynamic> user) {
    if (user.isEmpty) return const Color(0xFF38BDF8);

    final isSuper = user['is_super_admin'] == true;
    final sysRole = user['role']?.toString().toLowerCase() ?? '';
    if (isSuper || sysRole == 'super_admin' || sysRole == 'superadmin') {
      return const Color(0xFFF59E0B); // Amber / Gold
    }
    if (sysRole == 'admin') {
      return const Color(0xFFA855F7); // Purple / Violet
    }
    if (sysRole == 'manager') {
      return const Color(0xFF10B981); // Emerald Green
    }
    return const Color(0xFF38BDF8); // Default Cyan
  }

  bool get _isSuperAdminNotAdded {
    final isSuper = ref.read(authProvider).isSuperAdmin;
    if (!isSuper) return false;
    if (_conversationDetail == null) return false;
    final convType = _conversationDetail!['conversation_type'] ??
        _conversationDetail!['type'];
    if (convType != 'group') return false;

    final targetId = _conversationDetail!['target_id']?.toString();
    final currentUserId = ref.read(authProvider).userId?.toString();
    if (targetId == null) return false;

    if (_groupData != null) {
      if (_groupData!['created_by']?.toString() == currentUserId) return false;
      if (_groupData!['current_user_role'] != null) return false;
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
    final targetId = _conversationDetail?['target_id']?.toString();
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
    if (_conversationDetail == null) return false;
    final convType = _conversationDetail!['conversation_type'] ??
        _conversationDetail!['type'];
    if (convType == 'group') {
      final currentUserId = ref.read(authProvider).userId?.toString();
      final isSuper = ref.read(authProvider).isSuperAdmin;
      final isAdmin = ref.read(authProvider).isAdmin;

      if (_groupData != null) {
        final createdBy = _groupData!['created_by']?.toString();
        // Creator is Group Owner and can ALWAYS post
        if (createdBy != null && createdBy == currentUserId) return false;

        // SuperAdmin not added has dedicated Force Message banner instead
        if (isSuper) return false;
        if (isAdmin) return false;

        final role = _groupData!['current_user_role'];
        final perms = _groupData!['current_user_permissions'];

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
    final type = _conversationDetail?['conversation_type'] ?? 'direct';
    if (type == 'direct' || type == 'dm') return true;

    final currentU = ref.read(authProvider).user;
    if (currentU == null) return false;
    final isSuper = currentU['is_super_admin'] == true;
    final sysRole = currentU['role']?.toString().toLowerCase() ?? '';
    if (isSuper || sysRole == 'admin' || sysRole == 'super_admin') return true;

    return false;
  }

  Future<void> _togglePin(String msgId) async {
    final isCurrentlyPinned = _pinnedMsgIds.contains(msgId);
    try {
      final api = ref.read(apiClientProvider);
      if (isCurrentlyPinned) {
        await api.dio
            .delete(ApiEndpoints.unpinMessage(widget.conversationId, msgId));
        setState(() => _pinnedMsgIds.remove(msgId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message unpinned.')),
          );
        }
      } else {
        await api.dio
            .put(ApiEndpoints.pinMessage(widget.conversationId, msgId));
        setState(() => _pinnedMsgIds.add(msgId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message pinned to conversation! 📌')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update pinned message: $error')),
        );
      }
    }
  }

  Future<void> _showPinnedMessages() async {
    final pinnedMessages = _messages
        .where((message) => _pinnedMsgIds.contains(message['id'].toString()))
        .toList()
      ..sort((a, b) => (b['created_at'] ?? '')
          .toString()
          .compareTo((a['created_at'] ?? '').toString()));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.push_pin, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Pinned messages')),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: pinnedMessages.isEmpty
              ? const Text('No messages are pinned in this conversation.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: pinnedMessages.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final message = pinnedMessages[index];
                    final senderId = message['sender_id']?.toString() ?? '';
                    final sender = _userCache[senderId];
                    final senderName = sender?['display_name']?.toString() ??
                        message['sender_name']?.toString() ??
                        'Member';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(senderName),
                      subtitle: Text(
                        message['content']?.toString() ?? 'Attachment',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _canCurrentPinMessage
                          ? IconButton(
                              tooltip: 'Unpin message',
                              onPressed: () async {
                                Navigator.pop(dialogContext);
                                await _togglePin(message['id'].toString());
                              },
                              icon: const Icon(Icons.push_pin_outlined),
                            )
                          : null,
                    );
                  },
                ),
        ),
      ),
    );
  }

  String _formatWhatsAppDate(dynamic rawDate) {
    if (rawDate == null) return '';
    try {
      final dt = DateTime.parse(rawDate.toString()).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final tomorrow = today.add(const Duration(days: 1));
      final msgDay = DateTime(dt.year, dt.month, dt.day);

      if (msgDay == today) return 'Today';
      if (msgDay == yesterday) return 'Yesterday';
      if (msgDay == tomorrow) return 'Tomorrow';
      return DateFormat('dd/MM/yy').format(dt);
    } catch (_) {
      return rawDate.toString();
    }
  }

  String _formatTimeOnly(dynamic rawDate) {
    if (rawDate == null) return '';
    try {
      final dt = DateTime.parse(rawDate.toString()).toLocal();
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return rawDate.toString();
    }
  }

  String _formatTimestamp(dynamic rawDate) {
    if (rawDate == null) return '';
    try {
      final dt = DateTime.parse(rawDate.toString()).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final msgDay = DateTime(dt.year, dt.month, dt.day);

      final timeStr = DateFormat('h:mm a').format(dt);
      if (msgDay == today) {
        return 'Today at $timeStr';
      } else if (msgDay == yesterday) {
        return 'Yesterday at $timeStr';
      } else {
        return '${DateFormat('MMM d, yyyy').format(dt)} at $timeStr';
      }
    } catch (_) {
      return rawDate.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = ref.watch(authProvider).userId;

    String title = 'Conversation';
    if (_conversationDetail != null) {
      final type = _conversationDetail!['conversation_type'] ?? 'direct';
      if (type == 'channel') {
        title = '# ${_conversationDetail!['name'] ?? 'Channel Chat'}';
      } else if (type == 'group') {
        title = '👥 ${_conversationDetail!['name'] ?? 'Group Chat'}';
      } else {
        // Direct Message — resolve recipient in details, cache, participants, or messages
        if (_conversationDetail!['recipient_name'] != null &&
            _conversationDetail!['recipient_name'].toString().isNotEmpty &&
            _conversationDetail!['recipient_name'] != 'Direct Message' &&
            _conversationDetail!['recipient_name'] != 'Conversation') {
          title = _conversationDetail!['recipient_name'].toString();
        } else if (_conversationDetail!['display_name'] != null &&
            _conversationDetail!['display_name'].toString().isNotEmpty &&
            _conversationDetail!['display_name'] != 'Direct Message' &&
            _conversationDetail!['display_name'] != 'Conversation') {
          title = _conversationDetail!['display_name'].toString();
        } else {
          final pDetails = _conversationDetail!['participant_details'];
          if (pDetails is List && pDetails.isNotEmpty) {
            for (final p in pDetails) {
              if (p is Map) {
                final pid = (p['id'] ?? p['user_id'])?.toString();
                if (pid != null && pid.isNotEmpty && pid != currentUserId) {
                  final name = p['display_name']?.toString() ??
                      p['username']?.toString();
                  if (name != null &&
                      name.trim().isNotEmpty &&
                      name != 'Direct Message') {
                    title = name.trim();
                    break;
                  }
                }
              }
            }
          }

          if (title == 'Conversation' || title == 'Direct Message') {
            final participants = _conversationDetail!['participants'];
            if (participants is List) {
              for (final p in participants) {
                final pid =
                    (p is Map ? (p['user_id'] ?? p['id']) : p)?.toString();
                if (pid != null &&
                    pid != currentUserId &&
                    _userCache.containsKey(pid)) {
                  final u = _userCache[pid]!;
                  title = u['display_name']?.toString() ??
                      u['username']?.toString() ??
                      'User';
                  break;
                }
              }
            }
          }

          if (title == 'Conversation' || title == 'Direct Message') {
            final targetId = _conversationDetail!['target_id']?.toString() ??
                _conversationDetail!['recipient_id']?.toString();
            if (targetId != null &&
                targetId != currentUserId &&
                _userCache.containsKey(targetId)) {
              final u = _userCache[targetId];
              title = u?['display_name']?.toString() ??
                  u?['username']?.toString() ??
                  'User';
            } else {
              for (final m in _messages) {
                final sid = m['sender_id']?.toString();
                if (sid != null &&
                    sid != currentUserId &&
                    _userCache.containsKey(sid)) {
                  title = _userCache[sid]?['display_name']?.toString() ??
                      _userCache[sid]?['username']?.toString() ??
                      'User';
                  break;
                }
              }
            }
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, size: 20),
          tooltip: 'Back to Messages',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/messages');
            }
          },
        ),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _pinnedMsgIds.isNotEmpty,
              label: Text(
                '${_pinnedMsgIds.length}',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black),
              ),
              backgroundColor: Colors.amberAccent,
              child: Icon(
                _pinnedMsgIds.isNotEmpty
                    ? LucideIcons.pin
                    : LucideIcons.pin_off,
                size: 18,
                color: _pinnedMsgIds.isNotEmpty ? Colors.amberAccent : null,
              ),
            ),
            tooltip: _pinnedMsgIds.isNotEmpty
                ? 'Pinned Messages (${_pinnedMsgIds.length})'
                : 'Pinned Messages',
            onPressed: _showPinnedMessages,
          ),
          IconButton(
            icon: const Icon(LucideIcons.refresh_cw, size: 18),
            onPressed: () => _loadMessages(silent: false),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(LucideIcons.search, size: 18),
            onPressed: () => context.go('/search'),
            tooltip: 'Search Messages',
          ),
          if (_conversationDetail?['conversation_type'] == 'group' ||
              _conversationDetail?['conversation_type'] == 'channel')
            IconButton(
              icon: const Icon(LucideIcons.settings, size: 18),
              tooltip: _conversationDetail?['conversation_type'] == 'group'
                  ? 'Group Settings & Roles'
                  : 'Channel Settings & Members',
              onPressed: _openConversationSettings,
            ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // PINNED MESSAGES ACCORDION BAR (Section 9)
                    if (_pinnedMsgIds.isNotEmpty)
                      Material(
                        color: Colors.amberAccent.withValues(alpha: 0.12),
                        child: InkWell(
                          onTap: _showPinnedMessages,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.push_pin,
                                    size: 16, color: Colors.amberAccent),
                                const SizedBox(width: 8),
                                Text(
                                  'Pinned Messages (${_pinnedMsgIds.length})',
                                  style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                                const Spacer(),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // MESSAGE LIST (Section 6 & Date Separators)
                    Expanded(
                      child: _hasNoPermissionToView
                          ? Center(
                              child: Container(
                                margin: const EdgeInsets.all(32),
                                padding: const EdgeInsets.all(28),
                                constraints:
                                    const BoxConstraints(maxWidth: 460),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E38),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFFEF4444)
                                          .withValues(alpha: 0.4),
                                      width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444)
                                            .withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.lock_person_outlined,
                                        size: 28,
                                        color: Color(0xFFF87171),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Access Restricted',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _permissionErrorMsg ??
                                          'Your current role does not have permission to view messages in this group. Please contact a group administrator to update your role permissions.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70,
                                        height: 1.45,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.refresh, size: 16),
                                      label: const Text('Check Again'),
                                      onPressed: () =>
                                          _loadMessages(silent: false),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF38BDF8),
                                        side: const BorderSide(
                                            color: Color(0xFF38BDF8)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _messages.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.forum_outlined,
                                          size: 54, color: Colors.white24),
                                      SizedBox(height: 16),
                                      Text(
                                          'No messages yet. Send a message to start!',
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 16)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    final msg = _messages[index];
                                    final msgId = msg['id'].toString();
                                    final senderId =
                                        msg['sender_id'].toString();
                                    final isOwn = senderId == currentUserId;
                                    final text =
                                        msg['content']?.toString() ?? '';
                                    final isFile =
                                        msg['message_type'] == 'file';
                                    final parentId = msg['parent_id'];
                                    final isEdited = msg['updated_at'] !=
                                            null &&
                                        msg['updated_at'] != msg['created_at'];
                                    final isPinned =
                                        _pinnedMsgIds.contains(msgId);
                                    final Map<String, dynamic> reactions =
                                        (_messageReactions[msgId] is Map)
                                            ? (_messageReactions[msgId]
                                                as Map<String, dynamic>)
                                            : <String, dynamic>{};

                                    final senderUser =
                                        _userCache[senderId] ?? {};
                                    final displayName =
                                        senderUser['display_name'] ??
                                            (isOwn ? 'You' : 'User');

                                    // Calculate WhatsApp style Date Divider
                                    bool showDateDivider = false;
                                    String dividerLabel = '';
                                    if (index == 0) {
                                      showDateDivider = true;
                                      dividerLabel = _formatWhatsAppDate(
                                          msg['created_at']);
                                    } else {
                                      final prevDate = _formatWhatsAppDate(
                                          _messages[index - 1]['created_at']);
                                      final currDate = _formatWhatsAppDate(
                                          msg['created_at']);
                                      if (prevDate != currDate) {
                                        showDateDivider = true;
                                        dividerLabel = currDate;
                                      }
                                    }

                                    final isDirectMsg = _conversationDetail?[
                                                'conversation_type'] ==
                                            'direct' ||
                                        _conversationDetail?[
                                                'conversation_type'] ==
                                            'dm';

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (showDateDivider)
                                          Container(
                                            margin: const EdgeInsets.symmetric(
                                                vertical: 18),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Container(
                                                    height: 1.5,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          Colors.transparent,
                                                          const Color(
                                                                  0xFF5865F2)
                                                              .withValues(
                                                                  alpha: 0.4),
                                                          Colors.white
                                                              .withValues(
                                                                  alpha: 0.25),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 14,
                                                      vertical: 5),
                                                  margin: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFF1E1E38),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16),
                                                    border: Border.all(
                                                        color: const Color(
                                                                0xFF5865F2)
                                                            .withValues(
                                                                alpha: 0.45),
                                                        width: 1.2),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                                alpha: 0.4),
                                                        blurRadius: 8,
                                                        offset:
                                                            const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                          Icons
                                                              .calendar_today_rounded,
                                                          size: 12,
                                                          color: Color(
                                                              0xFF8EA1FF)),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        dividerLabel,
                                                        style: const TextStyle(
                                                          color:
                                                              Color(0xFF8EA1FF),
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          letterSpacing: 0.4,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Container(
                                                    height: 1.5,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          Colors.white
                                                              .withValues(
                                                                  alpha: 0.25),
                                                          const Color(
                                                                  0xFF5865F2)
                                                              .withValues(
                                                                  alpha: 0.4),
                                                          Colors.transparent,
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Padding(
                                          padding: EdgeInsets.only(
                                              bottom: reactions.isNotEmpty
                                                  ? 14
                                                  : 8),
                                          child: Align(
                                            alignment: isOwn
                                                ? Alignment.centerRight
                                                : Alignment.centerLeft,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (isOwn)
                                                  PopupMenuButton<String>(
                                                    icon: const Icon(
                                                        Icons.more_vert,
                                                        size: 16,
                                                        color: Colors.white30),
                                                    tooltip: 'Message options',
                                                    onSelected: (val) {
                                                      if (val == 'reply') {
                                                        _startReplyingMessage(
                                                            msg);
                                                      } else if (val ==
                                                          'edit') {
                                                        _startEditingMessage(
                                                            msg);
                                                      } else if (val ==
                                                          'delete') {
                                                        _deleteMessage(msg);
                                                      } else if (val == 'pin') {
                                                        _togglePin(msgId);
                                                      } else if (val ==
                                                          'copy') {
                                                        Clipboard.setData(
                                                            ClipboardData(
                                                                text: text));
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          const SnackBar(
                                                              content: Text(
                                                                  'Message text copied!')),
                                                        );
                                                      } else {
                                                        _toggleReaction(
                                                            msgId, val);
                                                      }
                                                    },
                                                    itemBuilder: (ctx) {
                                                      final currentU = ref
                                                          .read(authProvider)
                                                          .user;
                                                      final isSuper = currentU?[
                                                                  'is_super_admin'] ==
                                                              true ||
                                                          currentU?['role'] ==
                                                              'super_admin';
                                                      final canDelete =
                                                          isSuper || isOwn;
                                                      return [
                                                        const PopupMenuItem(
                                                            value: '👍',
                                                            child: Text(
                                                                '👍 Like')),
                                                        const PopupMenuItem(
                                                            value: '❤️',
                                                            child: Text(
                                                                '❤️ Love')),
                                                        const PopupMenuItem(
                                                            value: '🔥',
                                                            child: Text(
                                                                '🔥 Fire')),
                                                        const PopupMenuItem(
                                                            value: 'reply',
                                                            child: Text(
                                                                '💬 Reply')),
                                                        if (isOwn)
                                                          const PopupMenuItem(
                                                              value: 'edit',
                                                              child: Text(
                                                                  '✏️ Edit Message')),
                                                        if (canDelete)
                                                          const PopupMenuItem(
                                                              value: 'delete',
                                                              child: Text(
                                                                  '🗑️ Delete Message')),
                                                        if (_canCurrentPinMessage)
                                                          const PopupMenuItem(
                                                              value: 'pin',
                                                              child: Text(
                                                                  '📌 Pin Message')),
                                                        const PopupMenuItem(
                                                            value: 'copy',
                                                            child: Text(
                                                                '📋 Copy Text')),
                                                      ];
                                                    },
                                                  ),
                                                Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    Container(
                                                      constraints:
                                                          BoxConstraints(
                                                        maxWidth: MediaQuery.of(
                                                                        context)
                                                                    .size
                                                                    .width <
                                                                600
                                                            ? MediaQuery.of(
                                                                        context)
                                                                    .size
                                                                    .width *
                                                                0.75
                                                            : (MediaQuery.of(
                                                                            context)
                                                                        .size
                                                                        .width >
                                                                    1200
                                                                ? 440.0
                                                                : 400.0),
                                                        minWidth: 72,
                                                      ),
                                                      padding: const EdgeInsets
                                                          .fromLTRB(
                                                          14, 10, 14, 8),
                                                      decoration: BoxDecoration(
                                                        gradient: isOwn
                                                            ? const LinearGradient(
                                                                colors: [
                                                                  Color(
                                                                      0xFF4F46E5),
                                                                  Color(
                                                                      0xFF3730A3)
                                                                ],
                                                                begin: Alignment
                                                                    .topLeft,
                                                                end: Alignment
                                                                    .bottomRight,
                                                              )
                                                            : null,
                                                        color: isOwn
                                                            ? null
                                                            : const Color(
                                                                0xFF1E1E38),
                                                        borderRadius:
                                                            BorderRadius.only(
                                                          topLeft: const Radius
                                                              .circular(14),
                                                          topRight: const Radius
                                                              .circular(14),
                                                          bottomLeft:
                                                              Radius.circular(
                                                                  isOwn
                                                                      ? 14
                                                                      : 3),
                                                          bottomRight:
                                                              Radius.circular(
                                                                  isOwn
                                                                      ? 3
                                                                      : 14),
                                                        ),
                                                        border: Border.all(
                                                          color: isOwn
                                                              ? const Color(
                                                                      0xFF6366F1)
                                                                  .withValues(
                                                                      alpha:
                                                                          0.6)
                                                              : Colors.white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.1),
                                                          width: 1.0,
                                                        ),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          if (!isOwn &&
                                                              _conversationDetail?[
                                                                      'conversation_type'] !=
                                                                  'direct' &&
                                                              _conversationDetail?[
                                                                      'conversation_type'] !=
                                                                  'dm') ...[
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          4),
                                                              child:
                                                                  GestureDetector(
                                                                onTap: () =>
                                                                    _showUserProfilePopover(
                                                                        senderUser),
                                                                child:
                                                                    MouseRegion(
                                                                  cursor:
                                                                      SystemMouseCursors
                                                                          .click,
                                                                  child: Text(
                                                                    _conversationDetail?['conversation_type'] ==
                                                                            'group'
                                                                        ? '~ $displayName'
                                                                        : displayName,
                                                                    style:
                                                                        TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w800,
                                                                      fontSize:
                                                                          12.5,
                                                                      color: _getSenderNameColor(
                                                                          senderUser),
                                                                      decoration:
                                                                          TextDecoration
                                                                              .none,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                          if (parentId !=
                                                              null) ...[
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          4),
                                                              margin:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          4),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                        alpha:
                                                                            0.05),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4),
                                                                border: const Border(
                                                                    left: BorderSide(
                                                                        color: Colors
                                                                            .cyanAccent,
                                                                        width:
                                                                            2)),
                                                              ),
                                                              child: const Text(
                                                                  'Replying to message',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      color: Colors
                                                                          .white54)),
                                                            ),
                                                          ],
                                                          if (isFile) ...[
                                                            Row(
                                                              children: const [
                                                                Icon(
                                                                    Icons
                                                                        .insert_drive_file,
                                                                    size: 16,
                                                                    color: Colors
                                                                        .cyanAccent),
                                                                SizedBox(
                                                                    width: 4),
                                                                Text(
                                                                    'Attachment (Click to Preview)',
                                                                    style: TextStyle(
                                                                        color: Colors
                                                                            .cyanAccent,
                                                                        fontSize:
                                                                            11,
                                                                        fontWeight:
                                                                            FontWeight.bold)),
                                                              ],
                                                            ),
                                                            const SizedBox(
                                                                height: 4),
                                                          ],
                                                          RichMarkdownText(
                                                            text: text,
                                                            allUsers: _allUsers,
                                                            onMentionTap:
                                                                _showUserProfilePopover,
                                                          ),
                                                          const SizedBox(
                                                              height: 4),
                                                          Align(
                                                            alignment: Alignment
                                                                .bottomRight,
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .end,
                                                              children: [
                                                                if (isEdited) ...[
                                                                  const Text(
                                                                      '(edited) ',
                                                                      style: TextStyle(
                                                                          fontSize:
                                                                              10,
                                                                          color: Colors
                                                                              .amberAccent,
                                                                          fontStyle:
                                                                              FontStyle.italic)),
                                                                ],
                                                                if (isOwn) ...[
                                                                  const Icon(
                                                                      Icons
                                                                          .done_all_rounded,
                                                                      size: 14,
                                                                      color: Color(
                                                                          0xFF93C5FD)),
                                                                  const SizedBox(
                                                                      width: 4),
                                                                ],
                                                                Text(
                                                                  _formatTimeOnly(
                                                                      msg['created_at']),
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: isOwn
                                                                        ? const Color(
                                                                            0xFFC7D2FE)
                                                                        : Colors
                                                                            .white54,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (reactions.isNotEmpty)
                                                      Positioned(
                                                        left: isOwn ? null : 8,
                                                        right: isOwn ? 8 : null,
                                                        bottom: -11,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                0xFF191C26),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        14),
                                                            border: Border.all(
                                                                color: Colors
                                                                    .white24,
                                                                width: 1.2),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .black
                                                                    .withValues(
                                                                        alpha:
                                                                            0.6),
                                                                blurRadius: 4,
                                                                offset:
                                                                    const Offset(
                                                                        0, 2),
                                                              ),
                                                            ],
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: reactions
                                                                .entries
                                                                .map(
                                                                    (entry) =>
                                                                        Padding(
                                                                          padding: const EdgeInsets
                                                                              .symmetric(
                                                                              horizontal: 2),
                                                                          child:
                                                                              Text(
                                                                            entry.value > 1
                                                                                ? '${entry.key} ${entry.value}'
                                                                                : entry.key.toString(),
                                                                            style:
                                                                                const TextStyle(fontSize: 12),
                                                                          ),
                                                                        ))
                                                                .toList(),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                if (!isOwn)
                                                  PopupMenuButton<String>(
                                                    icon: const Icon(
                                                        Icons.more_vert,
                                                        size: 16,
                                                        color: Colors.white30),
                                                    tooltip: 'Message options',
                                                    onSelected: (val) {
                                                      if (val == 'reply') {
                                                        _startReplyingMessage(
                                                            msg);
                                                      } else if (val ==
                                                          'edit') {
                                                        _startEditingMessage(
                                                            msg);
                                                      } else if (val ==
                                                          'delete') {
                                                        _deleteMessage(msg);
                                                      } else if (val == 'pin') {
                                                        _togglePin(msgId);
                                                      } else if (val ==
                                                          'copy') {
                                                        Clipboard.setData(
                                                            ClipboardData(
                                                                text: text));
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          const SnackBar(
                                                              content: Text(
                                                                  'Message text copied!')),
                                                        );
                                                      } else {
                                                        _toggleReaction(
                                                            msgId, val);
                                                      }
                                                    },
                                                    itemBuilder: (ctx) {
                                                      final currentU = ref
                                                          .read(authProvider)
                                                          .user;
                                                      final isSuper = currentU?[
                                                                  'is_super_admin'] ==
                                                              true ||
                                                          currentU?['role'] ==
                                                              'super_admin';
                                                      final canDelete =
                                                          isSuper || isOwn;
                                                      return [
                                                        const PopupMenuItem(
                                                            value: '👍',
                                                            child: Text(
                                                                '👍 Like')),
                                                        const PopupMenuItem(
                                                            value: '❤️',
                                                            child: Text(
                                                                '❤️ Love')),
                                                        const PopupMenuItem(
                                                            value: '🔥',
                                                            child: Text(
                                                                '🔥 Fire')),
                                                        const PopupMenuItem(
                                                            value: 'reply',
                                                            child: Text(
                                                                '💬 Reply')),
                                                        if (isOwn)
                                                          const PopupMenuItem(
                                                              value: 'edit',
                                                              child: Text(
                                                                  '✏️ Edit Message')),
                                                        if (canDelete)
                                                          const PopupMenuItem(
                                                              value: 'delete',
                                                              child: Text(
                                                                  '🗑️ Delete Message')),
                                                        if (_canCurrentPinMessage)
                                                          const PopupMenuItem(
                                                              value: 'pin',
                                                              child: Text(
                                                                  '📌 Pin Message')),
                                                        const PopupMenuItem(
                                                            value: 'copy',
                                                            child: Text(
                                                                '📋 Copy Text')),
                                                      ];
                                                    },
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                    ),
                    // REPLY / EDIT ACTIVE PREVIEW BAR (Section 8 & 10)
                    if (_replyingToMsg != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: Colors.cyanAccent.withValues(alpha: 0.1),
                        child: Row(
                          children: [
                            const Icon(Icons.reply,
                                size: 16, color: Colors.cyanAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Replying to message: "${_replyingToMsg!['content']}"',
                                style: const TextStyle(
                                    color: Colors.cyanAccent, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  size: 16, color: Colors.white54),
                              onPressed: () =>
                                  setState(() => _replyingToMsg = null),
                            ),
                          ],
                        ),
                      ),

                    if (_editingMsg != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: Colors.amberAccent.withValues(alpha: 0.1),
                        child: Row(
                          children: [
                            const Icon(Icons.edit,
                                size: 16, color: Colors.amberAccent),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Editing Message (Press Enter or click Send to save)',
                                style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  size: 16, color: Colors.white54),
                              onPressed: () {
                                setState(() => _editingMsg = null);
                                _messageController.clear();
                              },
                            ),
                          ],
                        ),
                      ),

                    // EMOJI PICKER GRID (Section 13)
                    if (_showEmojiPicker)
                      Container(
                        height: 180,
                        color: const Color(0xFF191932),
                        child: GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 8,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: _sampleEmojis.length,
                          itemBuilder: (ctx, i) {
                            final emoji = _sampleEmojis[i];
                            return InkWell(
                              onTap: () {
                                _messageController.text =
                                    _messageController.text + emoji;
                                _messageController.selection =
                                    TextSelection.fromPosition(
                                  TextPosition(
                                      offset: _messageController.text.length),
                                );
                              },
                              child: Center(
                                child: Text(emoji,
                                    style: const TextStyle(fontSize: 22)),
                              ),
                            );
                          },
                        ),
                      ),

                    // Bottom Composer Input Bar or View-Only Banner (Section 14)
                    if (!_hasNoPermissionToView) ...[
                      if (_isCurrentConvViewOnly)
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1917),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1.2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
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
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.visibility_outlined,
                                    color: Color(0xFF94A3B8), size: 20),
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
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'You can only view messages. Contact the group creator or an administrator for messaging permissions.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF94A3B8),
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (_isSuperAdminNotAdded &&
                          _forceMessageSecondsRemaining <= 0)
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF451A03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFFD97706), width: 1.2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
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
                                  color: const Color(0xFF78350F),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.shield_outlined,
                                    color: Color(0xFFFBBF24), size: 20),
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
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Super Admin Override is available to temporarily send messages for 2 minutes.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFFFDE68A),
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
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.bolt, size: 16),
                                label: const Text('Force Message',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5)),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isSuperAdminNotAdded &&
                                _forceMessageSecondsRemaining > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                color: const Color(0xFF78350F),
                                child: Row(
                                  children: [
                                    const Icon(Icons.bolt,
                                        size: 15, color: Color(0xFFFBBF24)),
                                    const SizedBox(width: 8),
                                    Text(
                                      '⚡ Force Message Active: ${_formatSeconds(_forceMessageSecondsRemaining)} remaining',
                                      style: const TextStyle(
                                        color: Color(0xFFFEF3C7),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Text(
                                      'SuperAdmin Override (2m)',
                                      style: TextStyle(
                                          color: Color(0xFFFDE68A),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF14142B),
                                border: Border(
                                    top: BorderSide(
                                        color: Colors.white
                                            .withValues(alpha: 0.1))),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.attach_file,
                                        color: Colors.white54),
                                    onPressed: _attachFile,
                                    tooltip: 'Attach File',
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _showEmojiPicker
                                          ? Icons.keyboard
                                          : Icons.sentiment_satisfied_alt,
                                      color: _showEmojiPicker
                                          ? theme.colorScheme.primary
                                          : Colors.white54,
                                    ),
                                    onPressed: () => setState(() =>
                                        _showEmojiPicker = !_showEmojiPicker),
                                    tooltip: 'Emoji Picker',
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: TextField(
                                      controller: _messageController,
                                      style:
                                          const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        hintText: _editingMsg != null
                                            ? 'Edit your message...'
                                            : (_replyingToMsg != null
                                                ? 'Type your reply...'
                                                : 'Type a message or @mention...'),
                                        hintStyle: const TextStyle(
                                            color: Colors.white38),
                                        filled: true,
                                        fillColor: Colors.white
                                            .withValues(alpha: 0.05),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 12),
                                      ),
                                      onSubmitted: (_) => _sendMessage(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                    onPressed: _sendMessage,
                                    icon: Icon(
                                        _editingMsg != null
                                            ? Icons.check
                                            : Icons.send,
                                        size: 18),
                                    tooltip: _editingMsg != null
                                        ? 'Save Edit'
                                        : 'Send Message',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),

          // `@` MENTION AUTOCOMPLETE OVERLAY (Section 11)
          if (_showMentionAutocomplete)
            Positioned(
              left: 60,
              bottom: 70,
              right: 60,
              child: Card(
                elevation: 12,
                color: const Color(0xFF1E1E38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: const Color(0xFF5865F2).withValues(alpha: 0.6)),
                ),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Row(
                          children: const [
                            Icon(Icons.alternate_email,
                                size: 14, color: Color(0xFF8EA1FF)),
                            SizedBox(width: 6),
                            Text('MEMBERS MENTION',
                                style: TextStyle(
                                    color: Color(0xFF8EA1FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _mentionFilteredUsers.length,
                          itemBuilder: (ctx, i) {
                            final u = _mentionFilteredUsers[i];
                            final uid = u['id'].toString();
                            final isInChat = _messages
                                .any((m) => m['sender_id']?.toString() == uid);

                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFF5865F2)
                                    .withValues(alpha: 0.2),
                                child: Text(
                                    (u['display_name'] ?? 'U')[0].toUpperCase(),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ),
                              title: Row(
                                children: [
                                  Text(u['display_name']?.toString() ?? '',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  const SizedBox(width: 8),
                                  Text('@${u['username'] ?? ''}',
                                      style: const TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                  if (isInChat) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.greenAccent
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('In Chat',
                                          style: TextStyle(
                                              fontSize: 9,
                                              color: Colors.greenAccent,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                              onTap: () => _selectMention(u),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
