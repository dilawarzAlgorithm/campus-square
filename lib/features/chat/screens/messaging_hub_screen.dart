import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/core/services/secure_storage_service.dart';
import 'package:campus_square/features/chat/screens/chat_screen.dart';

class MessagingHubScreen extends StatefulWidget {
  const MessagingHubScreen({super.key});

  @override
  State<MessagingHubScreen> createState() => _MessagingHubScreenState();
}

class _MessagingHubScreenState extends State<MessagingHubScreen>
    with WidgetsBindingObserver {
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<dynamic> _conversations = [];
  String? _currentUserId;

  WebSocketChannel? _hubChannel;
  StreamSubscription? _hubSubscription;
  final Map<String, bool> _typingStatus = {};
  final Map<String, String> _drafts = {};
  final Map<String, IconData> _groupIcons = {};

  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final auth = context.read<CampusSquareAuth>();
    _currentUserId = auth.user?['id'];
    _apiClient = ApiClient(baseUrl: auth.baseUrl);

    _fetchConversations();
    _connectHubWebSocket();

    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchConversations(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pollingTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    _hubSubscription?.cancel();
    _hubChannel?.sink.close();
    super.dispose();
  }

  Future<void> _connectHubWebSocket() async {
    final storage = SecureStorageService();
    final token = await storage.getAccessToken();
    if (token == null) return;

    if (!mounted) return;
    final auth = context.read<CampusSquareAuth>();
    String wsBaseUrl = auth.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');

    final wsUrl = Uri.parse('$wsBaseUrl/api/chat/ws/hub?token=$token');

    try {
      _hubChannel = WebSocketChannel.connect(wsUrl);
      _hubSubscription = _hubChannel!.stream.listen(
        (data) {
          if (!mounted) return;

          final payload = jsonDecode(data);
          final type = payload['type'];

          setState(() {
            if (type == 'typing_status' || type == 'hub_typing_status') {
              _typingStatus[payload['conversation_id']] =
                  payload['is_typing'] == true;
            } else if (type == 'new_message' || type == 'hub_new_message') {
              final msg = payload['message'];
              final convId = msg['conversation_id'];

              final idx = _conversations.indexWhere((c) => c['id'] == convId);
              if (idx != -1) {
                final conv = _conversations.removeAt(idx);
                conv['last_message'] = msg;
                if (msg['sender']['id'] != _currentUserId) {
                  conv['unread_count'] = (conv['unread_count'] ?? 0) + 1;
                }
                _conversations.insert(0, conv);
              }
              _typingStatus[convId] = false;
            } else if (type == 'user_presence') {
              final presenceUserId = payload['user_id'];
              for (var conv in _conversations) {
                if (conv['type'] == 'DM') {
                  final participants = conv['participants'] as List<dynamic>;
                  for (var p in participants) {
                    if (p['user']['id'] == presenceUserId) {
                      p['user']['is_online'] = payload['is_online'];
                      p['user']['last_seen'] = payload['last_seen'];
                    }
                  }
                }
              }
            }
          });
        },
        onError: (_) {},
        onDone: () {},
      );
    } catch (e) {
      debugPrint("Hub WS connection error: $e");
    }
  }

  Future<void> _fetchConversations({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/chat/conversations",
        method: "GET",
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _conversations = jsonDecode(response.body);
            _isLoading = false;
          });
          await _loadDrafts();
        }
      }
    } catch (e) {
      debugPrint("Error fetching conversations: $e");
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDrafts() async {
    final storage = SecureStorageService();
    Map<String, String> drafts = {};
    Map<String, IconData> icons = {};
    for (var conv in _conversations) {
      final draft = await storage.getDraftMessage(conv['id']);
      if (draft != null && draft.isNotEmpty) {
        drafts[conv['id']] = draft;
      }
      if (conv['type'] == 'GROUP' || conv['type'] == 'DEPARTMENT') {
        final iconCode = await storage.getGroupIcon(conv['id']);
        if (iconCode != null) {
          icons[conv['id']] = IconData(iconCode, fontFamily: 'MaterialIcons');
        }
      }
    }
    if (mounted) {
      setState(() {
        _drafts.clear();
        _drafts.addAll(drafts);
        _groupIcons.clear();
        _groupIcons.addAll(icons);
      });
    }
  }

  String _getChatTitle(Map<String, dynamic> conversation) {
    if (conversation['type'] == 'DEPARTMENT' ||
        conversation['type'] == 'GROUP') {
      return conversation['name'] ?? 'Group Chat';
    }

    if (conversation['type'] == 'DM') {
      final participants = conversation['participants'] as List<dynamic>;
      final other = participants.firstWhere(
        (p) => p['user']['id'] != _currentUserId,
        orElse: () => participants.first,
      );
      return '${other['user']['first_name']} ${other['user']['last_name']}';
    }
    return 'Group Chat';
  }

  String _formatHubTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final msgDate = DateTime(date.year, date.month, date.day);

      if (msgDate == today) {
        final hour = date.hour > 12
            ? date.hour - 12
            : (date.hour == 0 ? 12 : date.hour);
        final period = date.hour >= 12 ? 'PM' : 'AM';
        final minute = date.minute.toString().padLeft(2, '0');
        return '$hour:$minute $period';
      }
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
      return "${date.day} ${months[date.month - 1]}";
    } catch (_) {
      return '';
    }
  }

  Widget _buildMessageStatusIcon(Map<String, dynamic> msg) {
    if (msg['status'] == 'sending') {
      return const Padding(
        padding: EdgeInsets.only(right: 4.0),
        child: Icon(Icons.access_time, size: 14, color: Colors.grey),
      );
    } else if (msg['status'] == 'failed') {
      return const Padding(
        padding: EdgeInsets.only(right: 4.0),
        child: Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
      );
    }

    bool isRead = msg['is_read'] == true;
    bool isDelivered = msg['is_delivered'] == true || isRead;

    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: Icon(
        isRead ? Icons.done_all : (isDelivered ? Icons.done_all : Icons.check),
        color: isRead ? Colors.blue : Colors.grey,
        size: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No messages yet.',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _fetchConversations(silent: false),
              child: ListView.separated(
                itemCount: _conversations.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final conv = _conversations[index];
                  final title = _getChatTitle(conv);
                  final lastMsg = conv['last_message'];
                  final unreadCount = conv['unread_count'] ?? 0;
                  final hasUnread = unreadCount > 0;
                  final isTyping = _typingStatus[conv['id']] == true;
                  final draftText = _drafts[conv['id']];

                  String displayText = "";
                  IconData? attachmentIcon;

                  if (lastMsg != null) {
                    displayText = lastMsg['content'];
                    if (displayText.contains('[ATTACHMENT|')) {
                      final startIndex = displayText.indexOf('[ATTACHMENT|');
                      final closeIndex = displayText.indexOf(']', startIndex);

                      if (closeIndex != -1) {
                        final attachmentData = displayText
                            .substring(startIndex + 12, closeIndex)
                            .split('|');
                        if (attachmentData.length >= 3) {
                          final ext = attachmentData[0].toLowerCase();
                          final isImage = [
                            'jpg',
                            'jpeg',
                            'png',
                            'gif',
                            'webp',
                          ].contains(ext);

                          attachmentIcon = isImage
                              ? Icons.image
                              : Icons.attach_file;

                          final textPart = displayText
                              .replaceRange(startIndex, closeIndex + 1, '')
                              .trim();

                          if (textPart.isNotEmpty) {
                            displayText = textPart;
                          } else {
                            displayText = isImage ? 'Photo' : 'Document';
                          }
                        }
                      }
                    }

                    final isGroup =
                        conv['type'] == 'GROUP' || conv['type'] == 'DEPARTMENT';
                    if (isGroup && lastMsg['sender']['id'] != _currentUserId) {
                      final senderName = lastMsg['sender']['first_name'];
                      displayText = "$senderName: $displayText";
                    }
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.1,
                      ),
                      child:
                          (conv['type'] == 'GROUP' ||
                                  conv['type'] == 'DEPARTMENT') &&
                              _groupIcons.containsKey(conv['id'])
                          ? Icon(
                              _groupIcons[conv['id']],
                              color: theme.colorScheme.primary,
                              size: 24,
                            )
                          : Text(
                              title[0].toUpperCase(),
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                    ),
                    title: Text(
                      title,
                      style: TextStyle(
                        fontWeight: hasUnread
                            ? FontWeight.w900
                            : FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (lastMsg != null)
                          Row(
                            children: [
                              if (lastMsg['sender']['id'] == _currentUserId)
                                _buildMessageStatusIcon(lastMsg),
                              if (attachmentIcon != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4.0),
                                  child: Icon(
                                    attachmentIcon,
                                    size: 16,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  displayText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: hasUnread
                                        ? Colors.black87
                                        : Colors.grey,
                                    fontWeight: hasUnread
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          const Text(
                            "Started a conversation",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        if (isTyping)
                          const Padding(
                            padding: EdgeInsets.only(top: 2.0),
                            child: Text(
                              "Typing...",
                              style: TextStyle(
                                color: Colors.green,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else if (draftText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Row(
                              children: [
                                const Text(
                                  "Draft: ",
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    draftText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontStyle: FontStyle.italic,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (lastMsg != null)
                          Text(
                            _formatHubTime(lastMsg['created_at']),
                            style: TextStyle(
                              color: hasUnread
                                  ? theme.colorScheme.primary
                                  : Colors.grey,
                              fontSize: 12,
                              fontWeight: hasUnread
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        if (hasUnread) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    onTap: () {
                      final isGroup =
                          conv['type'] == 'GROUP' ||
                          conv['type'] == 'DEPARTMENT';
                      bool initialOnline = false;
                      String? initialLastSeen;

                      if (!isGroup) {
                        final participants =
                            conv['participants'] as List<dynamic>;
                        final other = participants.firstWhere(
                          (p) => p['user']['id'] != _currentUserId,
                          orElse: () => participants.first,
                        );
                        initialOnline = other['user']['is_online'] == true;
                        initialLastSeen = other['user']['last_seen'];
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            conversationId: conv['id'],
                            chatTitle: title,
                            isGroup: isGroup,
                            initialOnline: initialOnline,
                            initialLastSeen: initialLastSeen,
                          ),
                        ),
                      ).then((_) => _fetchConversations(silent: true));
                    },
                  );
                },
              ),
            ),
    );
  }
}
