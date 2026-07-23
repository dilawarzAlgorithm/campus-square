import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/core/services/secure_storage_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String chatTitle;
  final String? initialText;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.chatTitle,
    this.initialText,
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

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  String? _currentUserId;

  Map<String, dynamic>? _replyingTo;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _messageController.text = widget.initialText!;
    }
    final auth = context.read<CampusSquareAuth>();
    _currentUserId = auth.user?['id'];
    _apiClient = ApiClient(baseUrl: auth.baseUrl);

    _initializeChat();
  }

  Future<void> _initializeChat() async {
    await _fetchMessageHistory();
    await _connectWebSocket();
  }

  Future<void> _fetchMessageHistory() async {
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/chat/conversations/${widget.conversationId}/messages",
        method: "GET",
      );

      if (response.statusCode == 200) {
        if (mounted && !_isDisposing) {
          setState(() {
            _messages = jsonDecode(response.body);
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

      _markMessagesAsRead();

      _wsSubscription = _channel!.stream.listen(
        (data) {
          final payload = jsonDecode(data);
          final type = payload['type'];

          if (type == 'new_message') {
            final msg = payload['message'];
            if (mounted && !_isDisposing) {
              setState(() {
                _messages.insert(0, msg);
              });

              if (msg['sender']['id'] != _currentUserId) {
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
          } else if (type == 'typing_status') {
            if (payload['user_id'] != _currentUserId &&
                mounted &&
                !_isDisposing) {
              setState(() => _isOtherTyping = payload['is_typing']);
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
                  _messages[idx]['content'] = "🚫 This message was deleted";
                }
              });
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
    if (_channel == null || !_isConnected || _isDisposing) return;

    _channel!.sink.add(jsonEncode({"type": "typing", "is_typing": true}));

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (!_isDisposing) {
        _channel!.sink.add(jsonEncode({"type": "typing", "is_typing": false}));
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No Internet Connection. Message not sent.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final payload = {
      "type": "message",
      "content": text,
      "reply_to_id": _replyingTo?['id'],
    };

    _channel!.sink.add(jsonEncode(payload));
    _messageController.clear();
    setState(() => _replyingTo = null);
  }

  void _deleteMessageAPI(String msgId) async {
    try {
      await _apiClient.authenticatedRequest(
        context,
        "/api/chat/messages/$msgId",
        method: "DELETE",
      );
    } catch (_) {}
  }

  void _showMessageOptions(Map<String, dynamic> msg) {
    if (msg['is_deleted'] == true) return;
    final isMe = msg['sender']['id'] == _currentUserId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _replyingTo = msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Text'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: msg['content']));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete Message',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessageAPI(msg['id']);
                },
              ),
          ],
        ),
      ),
    );
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

  @override
  void dispose() {
    _isDisposing = true;
    _wsSubscription?.cancel();
    _channel?.sink.close();
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.chatTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (_isOtherTyping)
              const Text(
                "typing...",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        actions: [
          if (!_isConnected && !_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Icon(Icons.wifi_off, color: Colors.red, size: 20),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isConnected && !_isLoading)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg['sender']['id'] == _currentUserId;
                      final isDeleted = msg['is_deleted'] == true;
                      final replyTo = msg['reply_to'];

                      final currentMsgDate = DateTime.parse(
                        msg['created_at'],
                      ).toLocal();

                      bool isFirstOfDay = false;
                      if (index == _messages.length - 1) {
                        isFirstOfDay = true;
                      } else {
                        final previousMsgDate = DateTime.parse(
                          _messages[index + 1]['created_at'],
                        ).toLocal();
                        if (!_isSameDay(currentMsgDate, previousMsgDate)) {
                          isFirstOfDay = true;
                        }
                      }

                      bool isGroupedWithOlder = false;
                      if (!isFirstOfDay && index < _messages.length - 1) {
                        isGroupedWithOlder =
                            msg['sender']['id'] ==
                            _messages[index + 1]['sender']['id'];
                      }

                      if (replyTo != null) {
                        isGroupedWithOlder = false;
                      }

                      bool isGroupedWithNewer = false;
                      if (index > 0) {
                        final newerMsgDate = DateTime.parse(
                          _messages[index - 1]['created_at'],
                        ).toLocal();
                        if (_isSameDay(currentMsgDate, newerMsgDate)) {
                          isGroupedWithNewer =
                              msg['sender']['id'] ==
                              _messages[index - 1]['sender']['id'];
                        }
                        if (_messages[index - 1]['reply_to'] != null) {
                          isGroupedWithNewer = false;
                        }
                      }

                      final double bottomMargin = isGroupedWithNewer
                          ? 2.0
                          : 12.0;

                      return Column(
                        children: [
                          if (isFirstOfDay)
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 16),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
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

                          Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () => _showMessageOptions(msg),
                              child: Container(
                                margin: EdgeInsets.only(bottom: bottomMargin),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
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
                                          ? (isGroupedWithOlder ? 4 : 16)
                                          : 16,
                                    ),
                                    topRight: Radius.circular(
                                      isMe ? (isGroupedWithOlder ? 4 : 16) : 16,
                                    ),
                                    bottomLeft: Radius.circular(!isMe ? 4 : 16),
                                    bottomRight: Radius.circular(isMe ? 4 : 16),
                                  ),
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (replyTo != null && !isDeleted) ...[
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        margin: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border(
                                            left: BorderSide(
                                              color: isMe
                                                  ? Colors.white
                                                  : theme.colorScheme.primary,
                                              width: 3,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              replyTo['sender']['first_name'],
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isMe
                                                    ? Colors.white70
                                                    : theme.colorScheme.primary,
                                              ),
                                            ),
                                            Text(
                                              replyTo['content'],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isMe
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ],
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
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                    ],

                                    ExpandableMessageText(
                                      text: msg['content'],
                                      isMe: isMe,
                                      isDeleted: isDeleted,
                                    ),

                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatMessageTime(msg['created_at']),
                                          style: TextStyle(
                                            color: isMe
                                                ? Colors.white70
                                                : Colors.black54,
                                            fontSize: 10,
                                          ),
                                        ),
                                        if (isMe && !isDeleted) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            msg['is_read'] == true
                                                ? Icons.done_all
                                                : Icons.check,
                                            color: msg['is_read'] == true
                                                ? Colors.blue.shade200
                                                : Colors.white70,
                                            size: 14,
                                          ),
                                        ],
                                      ],
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

          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  const Icon(Icons.reply, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Replying to ${_replyingTo!['sender']['first_name']}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _replyingTo!['content'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: _onTyping,
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: "Message...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2.0),
                    child: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary,
                      radius: 22,
                      child: IconButton(
                        icon: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ),
                ],
              ),
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
      return Text(
        widget.text,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 15,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final lines = widget.text.split('\n').length;
    final isLong = widget.text.length > 250 || lines > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: (isLong && !_isExpanded) ? 5 : null,
          overflow: (isLong && !_isExpanded) ? TextOverflow.ellipsis : null,
          style: TextStyle(
            color: widget.isMe ? Colors.white : Colors.black87,
            fontSize: 15,
          ),
        ),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
              child: Text(
                _isExpanded ? "Read Less" : "Read More...",
                style: TextStyle(
                  color: widget.isMe
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.blue.shade700,
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
