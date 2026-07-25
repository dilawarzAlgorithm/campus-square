import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/core/services/secure_storage_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String chatTitle;
  final String? initialText;
  final bool isGroup;
  final bool initialOnline;
  final String? initialLastSeen;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.chatTitle,
    this.initialText,
    this.isGroup = false,
    this.initialOnline = false,
    this.initialLastSeen,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ApiClient _apiClient;
  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;

  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isOtherTyping = false;
  bool _isDisposing = false;
  bool _showScrollToBottom = false;

  late bool _isOnline;
  String? _lastSeen;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  String? _currentUserId;

  PlatformFile? _selectedAttachment;
  bool _isUploadingAttachment = false;

  Map<String, dynamic>? _replyingTo;
  Map<String, dynamic>? _editingMessage;
  final Set<String> _selectedMessageIds = {};
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMsgId;
  bool _isParticipantBlocked = false;

  bool _isSearching = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _messageController.text = widget.initialText!;
    }
    _isOnline = widget.initialOnline;
    _lastSeen = widget.initialLastSeen;
    final auth = context.read<CampusSquareAuth>();
    _currentUserId = auth.user?['id'];
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _scrollController.addListener(_scrollListener);
    _loadDraft();
    _initializeChat();
  }

  void _scrollListener() {
    if (_scrollController.offset > 500 && !_showScrollToBottom) {
      setState(() => _showScrollToBottom = true);
    } else if (_scrollController.offset <= 500 && _showScrollToBottom) {
      setState(() => _showScrollToBottom = false);
    }
  }

  Future<void> _loadDraft() async {
    if (widget.initialText != null) return;
    final draft = await SecureStorageService().getDraftMessage(
      widget.conversationId,
    );
    if (draft != null && draft.isNotEmpty && mounted) {
      setState(() {
        _messageController.text = draft;
      });
    }
  }

  Future<List<String>> _getLocalDeletedIds() async {
    final data = await SecureStorageService().getDraftMessage(
      '${widget.conversationId}_deleted',
    );
    if (data != null && data.isNotEmpty) {
      return List<String>.from(jsonDecode(data));
    }
    return [];
  }

  Future<void> _persistLocalDeletedId(String id) async {
    final deletedIds = await _getLocalDeletedIds();
    if (!deletedIds.contains(id)) {
      deletedIds.add(id);
      await SecureStorageService().saveDraftMessage(
        '${widget.conversationId}_deleted',
        jsonEncode(deletedIds),
      );
    }
  }

  Future<void> _initializeChat() async {
    await _fetchMessageHistory();
    await _connectWebSocket();
  }

  Future<void> _fetchMessageHistory() async {
    try {
      final convRes = await _apiClient.authenticatedRequest(
        context,
        "/api/chat/conversations",
        method: "GET",
      );
      if (convRes.statusCode == 200 && mounted && !_isDisposing) {
        final convs = jsonDecode(convRes.body) as List<dynamic>;
        final currentConv = convs
            .where((c) => c['id'] == widget.conversationId)
            .firstOrNull;
        if (currentConv != null) {
          final participants = currentConv['participants'] as List<dynamic>;
          final myParticipant = participants
              .where((p) => p['user']['id'] == _currentUserId)
              .firstOrNull;
          if (myParticipant != null && myParticipant['is_blocked'] == true) {
            setState(() => _isParticipantBlocked = true);
          }
        }
      }

      if (!mounted) return;

      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/chat/conversations/${widget.conversationId}/messages",
        method: "GET",
      );
      if (response.statusCode == 200) {
        final apiMessages = jsonDecode(response.body) as List<dynamic>;
        final failedMsgs = await SecureStorageService().getFailedMessages(
          widget.conversationId,
        );
        final localDeleted = await _getLocalDeletedIds();

        if (mounted && !_isDisposing) {
          setState(() {
            _messages = [
              ...failedMsgs,
              ...apiMessages,
            ].where((m) => !localDeleted.contains(m['id'])).toList();
            _isLoading = false;
          });
          _markMessagesAsRead();
        }
      }
    } catch (e) {
      debugPrint("Error fetching messages: $e");
      if (mounted && !_isDisposing) setState(() => _isLoading = false);
    }
  }

  Future<void> _connectWebSocket() async {
    final storage = SecureStorageService();
    final token = await storage.getAccessToken();
    if (token == null) return;
    if (!mounted || _isDisposing) return;

    final auth = context.read<CampusSquareAuth>();
    String wsBaseUrl = auth.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final wsUrl = Uri.parse(
      '$wsBaseUrl/api/chat/ws/${widget.conversationId}?token=$token',
    );

    try {
      _channel = WebSocketChannel.connect(wsUrl);

      if (mounted && !_isDisposing) {
        setState(() => _isConnected = true);
      }

      _channel!.sink.add(jsonEncode({"type": "mark_delivered"}));
      _markMessagesAsRead();

      _wsSubscription = _channel!.stream.listen(
        (data) {
          final payload = jsonDecode(data);
          final type = payload['type'];

          if (type == 'new_message') {
            final msg = payload['message'];
            final localId = payload['local_id'];
            if (mounted && !_isDisposing) {
              setState(() {
                if (localId != null) {
                  _messages.removeWhere((m) => m['local_id'] == localId);
                }
                _messages.insert(0, msg);
              });
              _syncFailedMessages();

              if (msg['sender']['id'] != _currentUserId) {
                _channel!.sink.add(jsonEncode({"type": "mark_delivered"}));
                _markMessagesAsRead();
              }

              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  0.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            }
          } else if (type == 'message_edited') {
            final editedMsg = payload['message'];
            if (mounted && !_isDisposing) {
              setState(() {
                final idx = _messages.indexWhere(
                  (m) => m['id'] == editedMsg['id'],
                );
                if (idx != -1) {
                  _messages[idx]['content'] = editedMsg['content'];
                  _messages[idx]['is_edited'] = editedMsg['is_edited'] ?? true;
                }
              });
            }
          } else if (type == 'typing_status') {
            if (payload['user_id'] != _currentUserId &&
                mounted &&
                !_isDisposing) {
              setState(() => _isOtherTyping = payload['is_typing']);
            }
          } else if (type == 'messages_delivered') {
            if (payload['user_id'] != _currentUserId &&
                mounted &&
                !_isDisposing) {
              setState(() {
                for (var m in _messages) {
                  if (m['sender']['id'] == _currentUserId) {
                    m['is_delivered'] = true;
                  }
                }
              });
            }
          } else if (type == 'messages_read') {
            if (payload['user_id'] != _currentUserId &&
                mounted &&
                !_isDisposing) {
              setState(() {
                for (var m in _messages) {
                  if (m['sender']['id'] == _currentUserId) m['is_read'] = true;
                }
              });
            }
          } else if (type == 'message_deleted') {
            if (mounted && !_isDisposing) {
              setState(() {
                final idx = _messages.indexWhere(
                  (m) => m['id'] == payload['message_id'],
                );
                if (idx != -1) {
                  _messages[idx]['is_deleted'] = true;
                  _messages[idx]['content'] = "This message was deleted";
                }
              });
            }
          } else if (type == 'user_presence') {
            if (payload['user_id'] != _currentUserId &&
                mounted &&
                !_isDisposing &&
                !widget.isGroup) {
              setState(() {
                _isOnline = payload['is_online'];
                _lastSeen = payload['last_seen'];
              });
            }
          } else if (type == 'participant_blocked') {
            if (payload['user_id'] == _currentUserId &&
                mounted &&
                !_isDisposing) {
              setState(
                () => _isParticipantBlocked = payload['is_blocked'] == true,
              );
            }
          }
        },
        onError: (error) {
          if (mounted && !_isDisposing) setState(() => _isConnected = false);
        },
        onDone: () {
          if (mounted && !_isDisposing) setState(() => _isConnected = false);
        },
      );
    } catch (e) {
      if (mounted && !_isDisposing) setState(() => _isConnected = false);
    }
  }

  void _markMessagesAsRead() {
    if (_channel != null && _isConnected && !_isDisposing) {
      _channel!.sink.add(jsonEncode({"type": "mark_read"}));
    }
  }

  void _onTyping(String value) {
    bool isTyping = true;
    if (value.trim().isEmpty) {
      SecureStorageService().clearDraftMessage(widget.conversationId);
      isTyping = false;
    } else {
      SecureStorageService().saveDraftMessage(widget.conversationId, value);
    }
    setState(() {});

    if (_channel == null || !_isConnected || _isDisposing) return;
    _channel!.sink.add(jsonEncode({"type": "typing", "is_typing": isTyping}));

    _typingTimer?.cancel();
    if (isTyping) {
      _typingTimer = Timer(const Duration(seconds: 2), () {
        if (!_isDisposing) {
          _channel!.sink.add(
            jsonEncode({"type": "typing", "is_typing": false}),
          );
        }
      });
    }
  }

  Future<void> _syncFailedMessages() async {
    final failedMsgs = _messages
        .where((m) => m['status'] == 'failed' || m['status'] == 'sending')
        .toList();
    final toSave = failedMsgs
        .map((m) => {...m as Map<String, dynamic>, 'status': 'failed'})
        .toList();
    await SecureStorageService().saveFailedMessages(
      widget.conversationId,
      toSave,
    );
  }

  Future<void> _pickAttachment(FileType type) async {
    Navigator.pop(context);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: type,
      );
      if (!mounted) return;
      if (result != null) {
        setState(() => _selectedAttachment = result.files.first);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to pick file.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.withValues(alpha: 0.1),
                  child: const Icon(Icons.image, color: Colors.blue),
                ),
                title: const Text(
                  'Photo or Video',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Share media from gallery',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => _pickAttachment(FileType.media),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.insert_drive_file,
                    color: Colors.orange,
                  ),
                ),
                title: const Text(
                  'Document',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Share PDF, DOCX, or other files',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => _pickAttachment(FileType.any),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendMessage({String? retryText, String? retryLocalId}) async {
    if (_isUploadingAttachment) return;
    final text = retryText ?? _messageController.text.trim();
    final file = _selectedAttachment;
    if (text.isEmpty && file == null) return;

    HapticFeedback.lightImpact();

    if (_editingMessage != null) {
      final payload = {
        "type": "edit_message",
        "message_id": _editingMessage!['id'],
        "content": text,
      };
      if (_isConnected) {
        _channel!.sink.add(jsonEncode(payload));
      }
      setState(() {
        final idx = _messages.indexWhere(
          (m) => m['id'] == _editingMessage!['id'],
        );
        if (idx != -1) {
          _messages[idx]['content'] = text;
          _messages[idx]['is_edited'] = true;
        }
        _editingMessage = null;
      });
      _messageController.clear();
      return;
    }

    setState(() => _isUploadingAttachment = true);

    String? attachmentString;
    if (file != null) {
      try {
        final uploadRes = await _apiClient.authenticatedMultipartRequest(
          context,
          "/api/vault/upload-file",
          filePath: file.path!,
          fileField: "file",
        );
        if (!mounted) return;
        if (uploadRes.statusCode == 200) {
          final url = jsonDecode(uploadRes.body)['file_url'];
          final ext = file.extension?.toLowerCase() ?? 'file';
          final name = file.name.replaceAll('|', '-');
          attachmentString = '[ATTACHMENT|$ext|$name|$url]';
        } else {
          throw Exception('Upload failed');
        }
      } catch (e) {
        setState(() => _isUploadingAttachment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to upload attachment.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final finalContent = attachmentString != null
        ? (text.isNotEmpty ? '$attachmentString\n$text' : attachmentString)
        : text;

    setState(() {
      _selectedAttachment = null;
      _isUploadingAttachment = false;
    });

    SecureStorageService().clearDraftMessage(widget.conversationId);
    final localId =
        retryLocalId ?? DateTime.now().millisecondsSinceEpoch.toString();

    String? replyToId;
    if (retryLocalId != null) {
      final existingMsg = _messages.firstWhere(
        (m) => m['local_id'] == localId,
        orElse: () => <String, dynamic>{},
      );
      replyToId = existingMsg['reply_to']?['id'];
    } else {
      replyToId = _replyingTo?['id'];
    }

    if (retryLocalId == null) {
      final currentUser = context.read<CampusSquareAuth>().user;
      final localMsg = {
        "id": "local_$localId",
        "local_id": localId,
        "content": finalContent,
        "created_at": DateTime.now().toUtc().toIso8601String(),
        "is_read": false,
        "is_delivered": false,
        "is_deleted": false,
        "status": "sending",
        "reply_to": _replyingTo,
        "sender": {
          "id": _currentUserId,
          "first_name": currentUser?['first_name'] ?? "",
          "last_name": currentUser?['last_name'] ?? "",
          "role": currentUser?['role'] ?? "STUDENT",
        },
      };

      setState(() {
        _messages.insert(0, localMsg);
        _replyingTo = null;
      });
      _messageController.clear();
      _syncFailedMessages();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } else {
      setState(() {
        final idx = _messages.indexWhere((m) => m['local_id'] == localId);
        if (idx != -1) _messages[idx]['status'] = 'sending';
      });
      _syncFailedMessages();
    }

    if (!_isConnected) {
      setState(() {
        final idx = _messages.indexWhere((m) => m['local_id'] == localId);
        if (idx != -1) _messages[idx]['status'] = 'failed';
      });
      _syncFailedMessages();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No Internet Connection. Message failed to send.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final payload = {
      "type": "message",
      "content": finalContent,
      "reply_to_id": replyToId,
      "local_id": localId,
    };
    _channel!.sink.add(jsonEncode(payload));

    Timer(const Duration(seconds: 5), () {
      if (mounted && !_isDisposing) {
        setState(() {
          final idx = _messages.indexWhere(
            (m) => m['local_id'] == localId && m['status'] == 'sending',
          );
          if (idx != -1) {
            _messages[idx]['status'] = 'failed';
            _syncFailedMessages();
          }
        });
      }
    });
  }

  bool _isWithin15Minutes(String isoTime) {
    try {
      final msgTime = DateTime.parse(isoTime).toLocal();
      return DateTime.now().difference(msgTime).inMinutes <= 15;
    } catch (e) {
      return false;
    }
  }

  void _deleteMessageAPI(String msgId, {bool forEveryone = false}) async {
    try {
      final queryParam = forEveryone ? "?for_everyone=true" : "";
      await _apiClient.authenticatedRequest(
        context,
        "/api/chat/messages/$msgId$queryParam",
        method: "DELETE",
      );
    } catch (_) {}
  }

  void _showDeleteDialog() {
    bool canDeleteForEveryone = true;
    for (String id in _selectedMessageIds) {
      final msg = _messages.firstWhere((m) => (m['id'] ?? m['local_id']) == id);
      if (msg['sender']['id'] != _currentUserId ||
          !_isWithin15Minutes(msg['created_at'])) {
        canDeleteForEveryone = false;
        break;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selectedMessageIds.length} message(s)?'),
        content: const Text('This action cannot be undone.'),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (canDeleteForEveryone)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.1),
                foregroundColor: Colors.red,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _executeDelete(forEveryone: true);
              },
              child: const Text('Delete for Everyone'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _executeDelete(forEveryone: false);
            },
            child: const Text('Delete for Me'),
          ),
        ],
      ),
    );
  }

  void _executeDelete({required bool forEveryone}) {
    for (String id in _selectedMessageIds) {
      final msg = _messages.firstWhere((m) => (m['id'] ?? m['local_id']) == id);
      if (msg['status'] == 'failed' || msg['status'] == 'sending') {
        setState(() => _messages.removeWhere((m) => m['local_id'] == id));
        _syncFailedMessages();
      } else {
        if (!forEveryone) {
          setState(() {
            final idx = _messages.indexWhere((m) => m['id'] == id);
            if (idx != -1) _messages.removeAt(idx);
          });
          _persistLocalDeletedId(id);
        } else {
          _deleteMessageAPI(id, forEveryone: true);
        }
      }
    }
    setState(() => _selectedMessageIds.clear());
  }

  void _copySelected() {
    final textsToCopy = _messages
        .where((m) => _selectedMessageIds.contains(m['id'] ?? m['local_id']))
        .map((m) {
          String content = m['content'];
          final regex = RegExp(
            r'^\[ATTACHMENT\|[^\|]+\|[^\|]+\|([^\]]+)\]\n?(.*)',
            dotAll: true,
          );
          final match = regex.firstMatch(content);
          if (match != null) {
            final text = match.group(2);
            content = text != null && text.trim().isNotEmpty
                ? text.trim()
                : '[Attachment]';
          }
          return "[${_formatDateTimeForCopy(m['created_at'])}] ${m['sender']['first_name']}: $content";
        })
        .toList()
        .reversed
        .join('\n\n');

    Clipboard.setData(ClipboardData(text: textsToCopy));
    setState(() => _selectedMessageIds.clear());
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _shareSelected() {
    final textsToShare = _messages
        .where((m) => _selectedMessageIds.contains(m['id'] ?? m['local_id']))
        .map((m) {
          String content = m['content'];
          final regex = RegExp(
            r'^\[ATTACHMENT\|[^\|]+\|[^\|]+\|([^\]]+)\]\n?(.*)',
            dotAll: true,
          );
          final match = regex.firstMatch(content);
          if (match != null) {
            final url = match.group(1);
            final text = match.group(2);
            return '${text != null && text.trim().isNotEmpty ? "${text.trim()}\n" : ""}$url';
          }
          return content;
        })
        .toList()
        .reversed
        .join('\n\n');

    if (textsToShare.isNotEmpty) {
      SharePlus.instance.share(ShareParams(text: textsToShare));
    }
    setState(() => _selectedMessageIds.clear());
  }

  void _forwardSelected() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/chat/conversations",
        method: "GET",
      );

      if (response.statusCode == 200) {
        final convs = jsonDecode(response.body) as List<dynamic>;
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => _ForwardSheet(
            conversations: convs,
            selectedMessageIds: _selectedMessageIds.toList(),
            messages: _messages,
            apiClient: _apiClient,
            currentUserId: _currentUserId!,
          ),
        ).then((_) {
          if (mounted) setState(() => _selectedMessageIds.clear());
        });
      }
    } catch (e) {
      debugPrint("Error fetching conversations for forward: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scrollToMessage(String msgId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final targetIndex = _messages.indexWhere(
      (m) => (m['id'] ?? m['local_id']) == msgId,
    );
    if (targetIndex == -1) return;

    bool found = false;
    int attempts = 0;

    while (!found && attempts < 20) {
      attempts++;
      if (_messageKeys[msgId]?.currentContext != null) {
        found = true;
        await Scrollable.ensureVisible(
          _messageKeys[msgId]!.currentContext!,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
        if (!mounted) return;
        setState(() => _highlightedMsgId = msgId);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _highlightedMsgId = null);
        });
        break;
      }
      if (!_scrollController.hasClients) break;

      final currentOffset = _scrollController.offset;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final roughTargetOffset = targetIndex * 200.0;

      double nextOffset = currentOffset;
      if (currentOffset < roughTargetOffset) {
        nextOffset += 800;
      } else {
        nextOffset -= 800;
      }
      nextOffset = nextOffset.clamp(0.0, maxScroll);
      _scrollController.jumpTo(nextOffset);
      await Future.delayed(const Duration(milliseconds: 50));

      if ((nextOffset == 0.0 || nextOffset == maxScroll) && attempts > 3) {
        if (attempts > 5) break;
      }
    }

    if (!found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message not found or too old.')),
      );
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  String _formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(date.year, date.month, date.day);

    if (msgDate == today) return "Today";
    if (msgDate == yesterday) return "Yesterday";
    final months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${date.day} ${months[date.month - 1]} ${date.year}";
  }

  String _formatMessageTime(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      final hour = date.hour > 12
          ? date.hour - 12
          : (date.hour == 0 ? 12 : date.hour);
      final period = date.hour >= 12 ? 'PM' : 'AM';
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period';
    } catch (_) {
      return '';
    }
  }

  String _formatDateTimeForCopy(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();

      final hour = date.hour > 12
          ? date.hour - 12
          : (date.hour == 0 ? 12 : date.hour);
      final period = date.hour >= 12 ? 'PM' : 'AM';
      final minute = date.minute.toString().padLeft(2, '0');
      final timeStr = '$hour:$minute $period';

      if (date.year == now.year) {
        return '$day/$month, $timeStr';
      } else {
        return '$day/$month/$year, $timeStr';
      }
    } catch (_) {
      return '';
    }
  }

  String _formatLastSeen(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final msgDate = DateTime(date.year, date.month, date.day);

      String timeStr = "";
      final hour = date.hour > 12
          ? date.hour - 12
          : (date.hour == 0 ? 12 : date.hour);
      final period = date.hour >= 12 ? 'PM' : 'AM';
      final minute = date.minute.toString().padLeft(2, '0');
      timeStr = '$hour:$minute $period';

      if (msgDate == today) return "today at $timeStr";
      if (msgDate == yesterday) return "yesterday at $timeStr";
      final months = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ];
      return "${date.day} ${months[date.month - 1]} at $timeStr";
    } catch (_) {
      return '';
    }
  }

  String _stripAttachmentTags(String rawContent) {
    final regex = RegExp(
      r'^\[ATTACHMENT\|([^\|]+)\|([^\|]+)\|([^\]]+)\]\n?(.*)',
      dotAll: true,
    );
    final match = regex.firstMatch(rawContent);
    if (match != null) {
      return match.group(4) ?? '';
    }
    return rawContent;
  }

  Widget _buildSearchResults() {
    final query = _searchQuery.trim().toLowerCase();
    final results = _messages.where((m) {
      final cleanContent = _stripAttachmentTags(
        m['content']?.toString() ?? '',
      ).toLowerCase();
      return cleanContent.contains(query);
    }).toList();

    if (results.isEmpty) {
      return Center(
        child: Text(
          'No messages found for "$_searchQuery"',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final msg = results[index];
        final cleanContent = _stripAttachmentTags(
          msg['content']?.toString() ?? '',
        );
        final isMe = msg['sender']['id'] == _currentUserId;
        final lowerContent = cleanContent.toLowerCase();
        final startIndex = lowerContent.indexOf(query);

        Widget contentWidget = Text(
          cleanContent,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );

        if (startIndex != -1 && query.isNotEmpty) {
          contentWidget = RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              children: [
                TextSpan(text: cleanContent.substring(0, startIndex)),
                TextSpan(
                  text: cleanContent.substring(
                    startIndex,
                    startIndex + query.length,
                  ),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    backgroundColor: Color(0xFFFFF59D),
                  ),
                ),
                TextSpan(
                  text: cleanContent.substring(startIndex + query.length),
                ),
              ],
            ),
          );
        }

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            child: Text(
              msg['sender']['first_name'][0].toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isMe ? 'You' : msg['sender']['first_name'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                '${_formatDateSeparator(DateTime.parse(msg['created_at']))}, ${_formatMessageTime(msg['created_at'])}',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: contentWidget,
          ),
          onTap: () {
            setState(() {
              _isSearching = false;
              _searchQuery = "";
              _searchController.clear();
            });
            _scrollToMessage(msg['id'] ?? msg['local_id']);
          },
        );
      },
    );
  }

  Widget _buildReplyPreviewWidget(String rawContent, Color textColor) {
    String text = rawContent;
    IconData? icon;

    final attachmentRegex = RegExp(
      r'^\[ATTACHMENT\|([^\|]+)\|([^\|]+)\|([^\]]+)\]\n?(.*)',
      dotAll: true,
    );
    final match = attachmentRegex.firstMatch(rawContent);
    if (match != null) {
      final ext = match.group(1)!.toLowerCase();
      final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
      icon = isImage ? Icons.image : Icons.insert_drive_file;
      text = match.group(4)!;
      if (text.trim().isEmpty) {
        text = isImage ? 'Photo' : 'Document';
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text.replaceAll('\n', ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(Map<String, dynamic> msg) {
    if (msg['status'] == 'sending') {
      return const Icon(Icons.access_time, size: 14, color: Colors.white70);
    } else if (msg['status'] == 'failed') {
      return GestureDetector(
        onTap: () => _sendMessage(
          retryText: msg['content'],
          retryLocalId: msg['local_id'],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 14, color: Colors.redAccent),
            SizedBox(width: 4),
            Text(
              'Retry',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    bool isRead = msg['is_read'] == true;
    bool isDelivered = msg['is_delivered'] == true || isRead;

    return Icon(
      isRead ? Icons.done_all : (isDelivered ? Icons.done_all : Icons.check),
      color: isRead ? Colors.blue.shade200 : Colors.white70,
      size: 14,
    );
  }

  @override
  void dispose() {
    _isDisposing = true;
    _wsSubscription?.cancel();
    _channel?.sink.close();
    _typingTimer?.cancel();
    _messageController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inSelectionMode = _selectedMessageIds.isNotEmpty;

    return Scaffold(
      appBar: _isSearching
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = "";
                    _searchController.clear();
                  });
                },
              ),
              title: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: "Search messages...",
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
              actions: [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = "");
                    },
                  ),
              ],
            )
          : AppBar(
              leading: inSelectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          setState(() => _selectedMessageIds.clear()),
                    )
                  : null,
              title: inSelectionMode
                  ? Text(
                      '${_selectedMessageIds.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatDetailsScreen(
                              conversationId: widget.conversationId,
                              chatTitle: widget.chatTitle,
                              isGroup: widget.isGroup,
                            ),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            widget.chatTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          if (!widget.isGroup)
                            Text(
                              _isOnline
                                  ? "Online"
                                  : (_lastSeen != null
                                        ? "Last seen ${_formatLastSeen(_lastSeen!)}"
                                        : "Offline"),
                              style: TextStyle(
                                fontSize: 12,
                                color: _isOnline
                                    ? Colors.greenAccent
                                    : const Color.fromARGB(179, 129, 128, 128),
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                        ],
                      ),
                    ),
              actions: [
                if (inSelectionMode) ...[
                  if (_selectedMessageIds.length == 1) ...[
                    Builder(
                      builder: (context) {
                        final id = _selectedMessageIds.first;
                        final msg = _messages.firstWhere(
                          (m) => (m['id'] ?? m['local_id']) == id,
                        );
                        if (msg['sender']['id'] == _currentUserId &&
                            _isWithin15Minutes(msg['created_at'])) {
                          return IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Edit Message',
                            onPressed: () {
                              setState(() {
                                _editingMessage = msg;
                                _messageController.text = msg['content'];
                                _selectedMessageIds.clear();
                              });
                            },
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.reply),
                      tooltip: 'Reply',
                      onPressed: () {
                        final id = _selectedMessageIds.first;
                        setState(() {
                          _replyingTo = _messages.firstWhere(
                            (m) => (m['id'] ?? m['local_id']) == id,
                          );
                          _selectedMessageIds.clear();
                        });
                      },
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Share',
                    onPressed: _shareSelected,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy',
                    onPressed: _copySelected,
                  ),
                  IconButton(
                    icon: const Icon(Icons.turn_right_outlined),
                    tooltip: 'Forward',
                    onPressed: _forwardSelected,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete',
                    onPressed: _showDeleteDialog,
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search',
                    onPressed: () {
                      setState(() {
                        _isSearching = true;
                      });
                      _searchFocusNode.requestFocus();
                    },
                  ),
                  if (!_isConnected && !_isLoading)
                    const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: Icon(Icons.wifi_off, color: Colors.red, size: 20),
                    ),
                ],
              ],
            ),
      body: Stack(
        children: [
          Column(
            children: [
              if (!_isConnected && !_isLoading)
                Container(
                  width: double.infinity,
                  color: Colors.red.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: const Text(
                    'Waiting for network...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Expanded(
                child: _isSearching
                    ? _buildSearchResults()
                    : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _messages.length + (_isOtherTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isOtherTyping && index == 0) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TypingIndicator(),
                              ),
                            );
                          }

                          final actualIndex = _isOtherTyping
                              ? index - 1
                              : index;

                          final msg = _messages[actualIndex];
                          final msgId = msg['id'] ?? msg['local_id'];
                          final isMe = msg['sender']['id'] == _currentUserId;
                          final isDeleted = msg['is_deleted'] == true;
                          final replyTo = msg['reply_to'];
                          final isSelected = _selectedMessageIds.contains(
                            msgId,
                          );
                          final isHighlighted = _highlightedMsgId == msgId;
                          _messageKeys.putIfAbsent(msgId, () => GlobalKey());

                          final currentMsgDate = DateTime.parse(
                            msg['created_at'],
                          ).toLocal();

                          bool isFirstOfDay = false;
                          if (actualIndex == _messages.length - 1) {
                            isFirstOfDay = true;
                          } else {
                            final previousMsgDate = DateTime.parse(
                              _messages[actualIndex + 1]['created_at'],
                            ).toLocal();
                            if (!_isSameDay(currentMsgDate, previousMsgDate)) {
                              isFirstOfDay = true;
                            }
                          }

                          bool isGroupedWithOlder = false;
                          if (!isFirstOfDay &&
                              actualIndex < _messages.length - 1) {
                            isGroupedWithOlder =
                                msg['sender']['id'] ==
                                _messages[actualIndex + 1]['sender']['id'];
                          }
                          if (replyTo != null) isGroupedWithOlder = false;

                          bool isGroupedWithNewer = false;
                          if (actualIndex > 0) {
                            final newerMsgDate = DateTime.parse(
                              _messages[actualIndex - 1]['created_at'],
                            ).toLocal();
                            if (_isSameDay(currentMsgDate, newerMsgDate)) {
                              isGroupedWithNewer =
                                  msg['sender']['id'] ==
                                  _messages[actualIndex - 1]['sender']['id'];
                            }
                            if (_messages[actualIndex - 1]['reply_to'] !=
                                null) {
                              isGroupedWithNewer = false;
                            }
                          }

                          final double bottomMargin = isGroupedWithNewer
                              ? 2.0
                              : 12.0;

                          return Column(
                            key: _messageKeys[msgId],
                            children: [
                              if (isFirstOfDay)
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _formatDateSeparator(currentMsgDate),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                color: isSelected
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.2,
                                      )
                                    : (isHighlighted
                                          ? const Color.fromARGB(
                                              255,
                                              157,
                                              185,
                                              220,
                                            ).withValues(alpha: 0.3)
                                          : Colors.transparent),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress: () {
                                    if (isDeleted) return;
                                    setState(() {
                                      if (isSelected) {
                                        _selectedMessageIds.remove(msgId);
                                      } else {
                                        _selectedMessageIds.add(msgId);
                                      }
                                    });
                                  },
                                  onTap: () {
                                    if (inSelectionMode) {
                                      if (isDeleted) return;
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        if (isSelected) {
                                          _selectedMessageIds.remove(msgId);
                                        } else {
                                          _selectedMessageIds.add(msgId);
                                        }
                                      });
                                    }
                                  },
                                  child: Dismissible(
                                    key: ValueKey('swipe_$msgId'),
                                    direction: DismissDirection.startToEnd,
                                    confirmDismiss: (direction) async {
                                      if (!isDeleted) {
                                        setState(() => _replyingTo = msg);
                                      }
                                      return false;
                                    },
                                    background: Container(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.only(left: 20),
                                      child: Icon(
                                        Icons.reply,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    child: Align(
                                      alignment: isMe
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        margin: EdgeInsets.only(
                                          bottom: bottomMargin,
                                          left: 16,
                                          right: 16,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.04,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                          color: isDeleted
                                              ? theme
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.5)
                                              : (isMe
                                                    ? theme.colorScheme.primary
                                                    : theme
                                                          .colorScheme
                                                          .surfaceContainerHighest),
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(
                                              !isMe
                                                  ? (isGroupedWithOlder
                                                        ? 6
                                                        : 20)
                                                  : 20,
                                            ),
                                            topRight: Radius.circular(
                                              isMe
                                                  ? (isGroupedWithOlder
                                                        ? 6
                                                        : 20)
                                                  : 20,
                                            ),
                                            bottomLeft: Radius.circular(
                                              !isMe ? 6 : 20,
                                            ),
                                            bottomRight: Radius.circular(
                                              isMe ? 6 : 20,
                                            ),
                                          ),
                                        ),
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.of(
                                                context,
                                              ).size.width *
                                              0.80,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (replyTo != null &&
                                                !isDeleted) ...[
                                              GestureDetector(
                                                onTap: () => inSelectionMode
                                                    ? null
                                                    : _scrollToMessage(
                                                        replyTo['id'],
                                                      ),
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  margin: const EdgeInsets.only(
                                                    bottom: 8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isMe
                                                        ? Colors.white
                                                              .withValues(
                                                                alpha: 0.2,
                                                              )
                                                        : Colors.black
                                                              .withValues(
                                                                alpha: 0.05,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border(
                                                      left: BorderSide(
                                                        color: isMe
                                                            ? Colors.white
                                                            : theme
                                                                  .colorScheme
                                                                  .primary,
                                                        width: 4,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              replyTo['sender']['first_name'],
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: isMe
                                                                    ? Colors
                                                                          .white70
                                                                    : theme
                                                                          .colorScheme
                                                                          .primary,
                                                              ),
                                                            ),
                                                            _buildReplyPreviewWidget(
                                                              replyTo['content'],
                                                              isMe
                                                                  ? Colors.white
                                                                  : (theme
                                                                            .textTheme
                                                                            .bodyMedium
                                                                            ?.color ??
                                                                        Colors
                                                                            .black87),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (!isMe &&
                                                !isDeleted &&
                                                !isGroupedWithOlder) ...[
                                              Text(
                                                msg['sender']['first_name'],
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                            ],
                                            ExpandableMessageText(
                                              text: msg['content'],
                                              isMe: isMe,
                                              isDeleted: isDeleted,
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                if (msg['is_edited'] == true &&
                                                    !isDeleted) ...[
                                                  Text(
                                                    'Edited ',
                                                    style: TextStyle(
                                                      color: isMe
                                                          ? Colors.white70
                                                          : (theme
                                                                    .textTheme
                                                                    .bodySmall
                                                                    ?.color
                                                                    ?.withValues(
                                                                      alpha:
                                                                          0.7,
                                                                    ) ??
                                                                Colors.black54),
                                                      fontSize: 10,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  ),
                                                ],
                                                Text(
                                                  _formatMessageTime(
                                                    msg['created_at'],
                                                  ),
                                                  style: TextStyle(
                                                    color: isMe
                                                        ? Colors.white70
                                                        : (theme
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.color
                                                                  ?.withValues(
                                                                    alpha: 0.7,
                                                                  ) ??
                                                              Colors.black54),
                                                    fontSize: 10,
                                                  ),
                                                ),
                                                if (isMe && !isDeleted) ...[
                                                  const SizedBox(width: 4),
                                                  _buildStatusIcon(msg),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              if (!_isSearching) ...[
                if (_replyingTo != null || _editingMessage != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: Border(
                        top: BorderSide(
                          color: Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _editingMessage != null ? Icons.edit : Icons.reply,
                          color: Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _editingMessage != null
                                    ? "Editing message"
                                    : "Replying to ${_replyingTo!['sender']['first_name']}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              _buildReplyPreviewWidget(
                                _editingMessage != null
                                    ? _editingMessage!['content']
                                    : _replyingTo!['content'],
                                Colors.grey,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            setState(() {
                              _replyingTo = null;
                              if (_editingMessage != null) {
                                _editingMessage = null;
                                _messageController.clear();
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                if (_isParticipantBlocked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    color: Colors.red.withValues(alpha: 0.1),
                    width: double.infinity,
                    child: const Text(
                      "You have been blocked from sending messages to this chat.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Column(
                        children: [
                          if (_selectedAttachment != null)
                            Container(
                              margin: const EdgeInsets.only(
                                bottom: 12,
                                left: 8,
                                right: 8,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    [
                                          'jpg',
                                          'jpeg',
                                          'png',
                                          'gif',
                                          'webp',
                                        ].contains(
                                          _selectedAttachment!.extension
                                              ?.toLowerCase(),
                                        )
                                        ? Icons.image
                                        : Icons.insert_drive_file,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _selectedAttachment!.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => setState(
                                      () => _selectedAttachment = null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          color: Colors.blueGrey,
                                        ),
                                        onPressed: () {
                                          HapticFeedback.selectionClick();
                                          _showAttachmentOptions();
                                        },
                                      ),
                                      Expanded(
                                        child: TextField(
                                          controller: _messageController,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          onChanged: _onTyping,
                                          keyboardType: TextInputType.multiline,
                                          minLines: 1,
                                          maxLines: 5,
                                          style: const TextStyle(fontSize: 16),
                                          decoration: const InputDecoration(
                                            hintText: "Message...",
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 14,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder:
                                    (
                                      Widget child,
                                      Animation<double> animation,
                                    ) {
                                      return ScaleTransition(
                                        scale: animation,
                                        child: child,
                                      );
                                    },
                                child:
                                    (_messageController.text
                                            .trim()
                                            .isNotEmpty ||
                                        _selectedAttachment != null)
                                    ? Padding(
                                        key: const ValueKey('send_btn'),
                                        padding: const EdgeInsets.only(
                                          bottom: 2.0,
                                        ),
                                        child: _isUploadingAttachment
                                            ? const Padding(
                                                padding: EdgeInsets.all(12.0),
                                                child: SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2.5,
                                                      ),
                                                ),
                                              )
                                            : CircleAvatar(
                                                backgroundColor:
                                                    theme.colorScheme.primary,
                                                radius: 24,
                                                child: IconButton(
                                                  icon: Icon(
                                                    _editingMessage != null
                                                        ? Icons.check
                                                        : Icons.send_rounded,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                  onPressed: _sendMessage,
                                                ),
                                              ),
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('empty_btn'),
                                      ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
          if (_showScrollToBottom && !_isSearching)
            Positioned(
              bottom: 110,
              right: 16,
              child: FloatingActionButton.small(
                onPressed: () {
                  _scrollController.animateTo(
                    0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                backgroundColor: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.85,
                ),
                child: const Icon(Icons.arrow_downward, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }
}

class ExpandableMessageText extends StatefulWidget {
  final String text;
  final bool isMe;
  final bool isDeleted;

  const ExpandableMessageText({
    super.key,
    required this.text,
    required this.isMe,
    this.isDeleted = false,
  });

  @override
  State<ExpandableMessageText> createState() => _ExpandableMessageTextState();
}

class _ExpandableMessageTextState extends State<ExpandableMessageText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 16, color: Colors.redAccent),
          SizedBox(width: 6),
          Text(
            widget.text,
            style: TextStyle(
              color: Colors.grey,
              fontSize: 15,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    final attachmentRegex = RegExp(
      r'^\[ATTACHMENT\|([^\|]+)\|([^\|]+)\|([^\]]+)\]\n?(.*)',
      dotAll: true,
    );
    final match = attachmentRegex.firstMatch(widget.text);

    Widget attachmentWidget = const SizedBox.shrink();
    String displayText = widget.text;

    if (match != null) {
      final ext = match.group(1)!.toLowerCase();
      final name = match.group(2)!;
      final url = match.group(3)!;
      displayText = match.group(4)!;

      final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
      final isVideo = ['mp4', 'mov', 'avi', 'mkv'].contains(ext);

      attachmentWidget = GestureDetector(
        onTap: () async {
          if (isImage) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  body: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.network(
                        url,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        },
                        errorBuilder: (c, e, s) => const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              color: Colors.white54,
                              size: 64,
                            ),
                            SizedBox(height: 16),
                            Text(
                              "Failed to load image",
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          } else {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: widget.isMe
                ? Colors.black.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.05),
          ),
          clipBehavior: Clip.antiAlias,
          child: isImage
              ? Container(
                  height: 200, // Fixed height constraint
                  width: double.infinity,
                  color: widget.isMe
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.2),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder:
                        (
                          BuildContext context,
                          Widget child,
                          ImageChunkEvent? loadingProgress,
                        ) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                  : null,
                              color: widget.isMe
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          );
                        },
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 48,
                      ),
                    ),
                  ),
                )
              : ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  leading: Icon(
                    isVideo ? Icons.video_file : Icons.insert_drive_file,
                    color: widget.isMe ? Colors.white : Colors.blueAccent,
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isMe
                          ? Colors.white
                          : Theme.of(context).textTheme.bodyMedium?.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: widget.isMe ? Colors.white70 : Colors.grey,
                  ),
                ),
        ),
      );
    }

    final lines = widget.text.split('\n').length;
    final isLong = widget.text.length > 250 || lines > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        attachmentWidget,
        if (displayText.isNotEmpty)
          LinkifiedText(
            text: displayText,
            isMe: widget.isMe,
            maxLines: (isLong && !_isExpanded) ? 5 : null,
            overflow: (isLong && !_isExpanded) ? TextOverflow.ellipsis : null,
          ),
        if (isLong && displayText.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
              child: Text(
                _isExpanded ? "Read Less" : "Read More...",
                style: TextStyle(
                  color: widget.isMe
                      ? Colors.white.withValues(alpha: 0.8)
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class LinkifiedText extends StatelessWidget {
  final String text;
  final bool isMe;
  final int? maxLines;
  final TextOverflow? overflow;

  const LinkifiedText({
    super.key,
    required this.text,
    required this.isMe,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final RegExp urlRegex = RegExp(
      r'(https?:\/\/[^\s]+)',
      caseSensitive: false,
    );
    final matches = urlRegex.allMatches(text);

    final defaultStyle = TextStyle(
      color: isMe
          ? Colors.white
          : Theme.of(context).textTheme.bodyMedium?.color,
      fontSize: 15,
    );

    if (matches.isEmpty) {
      return Text(
        text,
        style: defaultStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    List<TextSpan> spans = [];
    int lastMatchEnd = 0;

    for (var match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }

      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            color: isMe ? Colors.blue.shade100 : Colors.blue.shade700,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    }

    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(style: defaultStyle, children: spans),
    );
  }
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              final phase = index * 0.2;
              final offset = math.sin((t - phase) * 2 * math.pi) * 3;
              final opacity =
                  (math.sin((t - phase) * 2 * math.pi) + 1) / 2 * 0.7 + 0.3;

              return Transform.translate(
                offset: Offset(0, offset < 0 ? offset : 0),
                child: Opacity(
                  opacity: opacity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: CircleAvatar(
                      radius: 3.5,
                      backgroundColor: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

class ChatDetailsScreen extends StatefulWidget {
  final String conversationId;
  final String chatTitle;
  final bool isGroup;

  const ChatDetailsScreen({
    super.key,
    required this.conversationId,
    required this.chatTitle,
    required this.isGroup,
  });

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  bool _isLoading = true;
  bool _isMuted = false;
  List<dynamic> _participants = [];
  IconData _groupIcon = Icons.group;

  final List<IconData> _availableIcons = [
    Icons.group,
    Icons.school,
    Icons.work,
    Icons.science,
    Icons.sports_esports,
    Icons.sports_basketball,
    Icons.library_books,
    Icons.campaign,
    Icons.emoji_events,
    Icons.local_cafe,
    Icons.music_note,
    Icons.palette,
  ];

  @override
  void initState() {
    super.initState();
    _fetchDetails();
    _loadSavedIcon();
  }

  Future<void> _loadSavedIcon() async {
    final iconCode = await SecureStorageService().getGroupIcon(
      widget.conversationId,
    );
    if (iconCode != null && mounted) {
      setState(() {
        _groupIcon = IconData(iconCode, fontFamily: 'MaterialIcons');
      });
    }
  }

  Future<void> _fetchDetails() async {
    try {
      final auth = context.read<CampusSquareAuth>();
      final apiClient = ApiClient(baseUrl: auth.baseUrl);
      final response = await apiClient.authenticatedRequest(
        context,
        "/api/chat/conversations",
        method: "GET",
      );

      if (response.statusCode == 200 && mounted) {
        final convs = jsonDecode(response.body) as List<dynamic>;
        final currentConv = convs
            .where((c) => c['id'] == widget.conversationId)
            .firstOrNull;

        if (currentConv != null) {
          setState(() {
            _participants = currentConv['participants'] ?? [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _blockUser(String userId, bool block) async {
    try {
      final auth = context.read<CampusSquareAuth>();
      final apiClient = ApiClient(baseUrl: auth.baseUrl);

      final response = await apiClient.authenticatedRequest(
        context,
        "/api/chat/conversations/${widget.conversationId}/participants/$userId/block",
        method: "PATCH",
        body: jsonEncode({"is_blocked": block}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          final index = _participants.indexWhere(
            (p) => p['user']['id'] == userId,
          );
          if (index != -1) {
            _participants[index]['is_blocked'] = block;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              block ? 'User blocked from chat.' : 'User unblocked.',
            ),
            backgroundColor: block ? Colors.red : Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update block status. Server error.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update block status.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showIconPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose Group Icon',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: _availableIcons.length,
                  itemBuilder: (context, index) {
                    final icon = _availableIcons[index];
                    return InkWell(
                      onTap: () async {
                        setState(() => _groupIcon = icon);
                        await SecureStorageService().saveGroupIcon(
                          widget.conversationId,
                          icon.codePoint,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Group icon updated locally."),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        child: Icon(
                          icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = context.read<CampusSquareAuth>().user;
    final userRole = currentUser?['role'] ?? 'STUDENT';
    final isStaff = userRole == 'ADMIN' || userRole == 'COMMUNITY_HEAD';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              title: Text(
                widget.chatTitle,
                style: TextStyle(
                  color: theme.textTheme.titleLarge?.color,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: theme.scaffoldBackgroundColor,
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              background: Container(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                child: Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: theme.colorScheme.primary.withValues(
                          alpha: 0.15,
                        ),
                        child: widget.isGroup
                            ? Icon(
                                _groupIcon,
                                size: 50,
                                color: theme.colorScheme.primary,
                              )
                            : Text(
                                widget.chatTitle[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 40,
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      if (widget.isGroup)
                        GestureDetector(
                          onTap: _showIconPicker,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primary,
                            child: const Icon(
                              Icons.camera_alt,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_off_outlined),
                  title: const Text('Mute Notifications'),
                  subtitle: const Text('Do not disturb for this chat'),
                  value: _isMuted,
                  onChanged: (val) => setState(() => _isMuted = val),
                  activeThumbColor: theme.colorScheme.primary,
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Media, Links & Documents'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatMediaScreen(
                          conversationId: widget.conversationId,
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    'Participants (${_participants.length})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final participant = _participants[index];
                final user = participant['user'];
                final bool isBlocked = participant['is_blocked'] == true;
                final String role = user['role'] ?? 'STUDENT';
                final bool isParticipantStaff =
                    role == 'ADMIN' || role == 'COMMUNITY_HEAD';

                final bool canBlock =
                    isStaff &&
                    !isParticipantStaff &&
                    user['id'] != currentUser?['id'];

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isBlocked
                        ? Colors.red.withValues(alpha: 0.1)
                        : theme.colorScheme.primary.withValues(alpha: 0.1),
                    child: Text(
                      user['first_name'][0].toUpperCase(),
                      style: TextStyle(
                        color: isBlocked
                            ? Colors.red
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    "${user['first_name']} ${user['last_name']}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: isBlocked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      if (isParticipantStaff)
                        Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: Chip(
                            label: const Text(
                              'Admin',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                              ),
                            ),
                            backgroundColor: Colors.blue.shade400,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      if (isBlocked)
                        const Text(
                          "Blocked",
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        )
                      else
                        Text(
                          role,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  trailing: canBlock
                      ? PopupMenuButton<String>(
                          onSelected: (val) {
                            if (val == 'block') _blockUser(user['id'], true);
                            if (val == 'unblock') _blockUser(user['id'], false);
                          },
                          itemBuilder: (context) => [
                            if (!isBlocked)
                              const PopupMenuItem(
                                value: 'block',
                                child: Text(
                                  'Block from Chat',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            if (isBlocked)
                              const PopupMenuItem(
                                value: 'unblock',
                                child: Text(
                                  'Unblock User',
                                  style: TextStyle(color: Colors.green),
                                ),
                              ),
                          ],
                        )
                      : null,
                );
              }, childCount: _participants.length),
            ),
        ],
      ),
    );
  }
}

class ChatMediaScreen extends StatefulWidget {
  final String conversationId;
  const ChatMediaScreen({super.key, required this.conversationId});

  @override
  State<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends State<ChatMediaScreen> {
  bool _isLoading = true;
  List<dynamic> _mediaItems = [];

  @override
  void initState() {
    super.initState();
    _fetchMedia();
  }

  Future<void> _fetchMedia() async {
    try {
      final auth = context.read<CampusSquareAuth>();
      final apiClient = ApiClient(baseUrl: auth.baseUrl);
      final response = await apiClient.authenticatedRequest(
        context,
        "/api/chat/conversations/${widget.conversationId}/messages",
        method: "GET",
      );

      if (response.statusCode == 200 && mounted) {
        final msgs = jsonDecode(response.body) as List<dynamic>;
        final media = msgs
            .where(
              (m) =>
                  m['content'].toString().contains('[ATTACHMENT|') &&
                  m['is_deleted'] != true,
            )
            .toList();

        setState(() {
          _mediaItems = media;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media, Links & Docs')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _mediaItems.isEmpty
          ? const Center(
              child: Text(
                'No media found in this chat.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _mediaItems.length,
              itemBuilder: (context, index) {
                final msg = _mediaItems[index];
                final content = msg['content'] as String;

                final regex = RegExp(
                  r'^\[ATTACHMENT\|([^\|]+)\|([^\|]+)\|([^\]]+)\]',
                  dotAll: true,
                );
                final match = regex.firstMatch(content);
                if (match == null) return const SizedBox.shrink();

                final ext = match.group(1)!.toLowerCase();
                final name = match.group(2)!;
                final url = match.group(3)!;

                final isImage = [
                  'jpg',
                  'jpeg',
                  'png',
                  'gif',
                  'webp',
                ].contains(ext);

                return GestureDetector(
                  onTap: () async {
                    if (isImage) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            backgroundColor: Colors.black,
                            appBar: AppBar(
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              foregroundColor: Colors.white,
                            ),
                            body: Center(
                              child: InteractiveViewer(
                                child: Image.network(
                                  url,
                                  loadingBuilder:
                                      (
                                        BuildContext context,
                                        Widget child,
                                        ImageChunkEvent? loadingProgress,
                                      ) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return Center(
                                          child: CircularProgressIndicator(
                                            value:
                                                loadingProgress
                                                        .expectedTotalBytes !=
                                                    null
                                                ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                : null,
                                            color: Colors.white,
                                          ),
                                        );
                                      },
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.broken_image,
                                            color: Colors.white54,
                                            size: 64,
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            "Failed to load image",
                                            style: TextStyle(
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ],
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    } else {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: isImage
                        ? Image.network(
                            url,
                            fit: BoxFit.cover,
                            loadingBuilder:
                                (
                                  BuildContext context,
                                  Widget child,
                                  ImageChunkEvent? loadingProgress,
                                ) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value:
                                          loadingProgress.expectedTotalBytes !=
                                              null
                                          ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                          : null,
                                    ),
                                  );
                                },
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                  ),
                                ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.insert_drive_file,
                                size: 32,
                                color: Colors.blueGrey,
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                ),
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
    );
  }
}

class _ForwardSheet extends StatefulWidget {
  final List<dynamic> conversations;
  final List<String> selectedMessageIds;
  final List<dynamic> messages;
  final ApiClient apiClient;
  final String currentUserId;

  const _ForwardSheet({
    required this.conversations,
    required this.selectedMessageIds,
    required this.messages,
    required this.apiClient,
    required this.currentUserId,
  });

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  bool _isForwarding = false;

  void _forwardTo(BuildContext context, String targetConvId) async {
    setState(() => _isForwarding = true);
    try {
      final msgsToForward = widget.messages
          .where(
            (m) => widget.selectedMessageIds.contains(m['id'] ?? m['local_id']),
          )
          .toList()
          .reversed
          .toList();

      for (var msg in msgsToForward) {
        await widget.apiClient.authenticatedRequest(
          context,
          "/api/chat/conversations/$targetConvId/messages",
          method: "POST",
          body: jsonEncode({"content": msg['content']}),
        );
      }

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Messages forwarded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to forward some messages'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Forward to...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              if (_isForwarding)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const Divider(height: 32),
          Expanded(
            child: ListView.builder(
              itemCount: widget.conversations.length,
              itemBuilder: (context, index) {
                final conv = widget.conversations[index];

                String title = 'Group Chat';
                if (conv['type'] == 'DEPARTMENT' || conv['type'] == 'GROUP') {
                  title = conv['name'] ?? 'Group Chat';
                } else if (conv['type'] == 'DM') {
                  final participants = conv['participants'] as List<dynamic>;
                  final other = participants.firstWhere(
                    (p) => p['user']['id'] != widget.currentUserId,
                    orElse: () => participants.first,
                  );
                  title =
                      '${other['user']['first_name']} ${other['user']['last_name']}';
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    child: Text(
                      title[0].toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: _isForwarding
                      ? null
                      : () => _forwardTo(context, conv['id']),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
