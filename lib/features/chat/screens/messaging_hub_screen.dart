import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/chat/screens/chat_screen.dart';

class MessagingHubScreen extends StatefulWidget {
  const MessagingHubScreen({super.key});

  @override
  State<MessagingHubScreen> createState() => _MessagingHubScreenState();
}

class _MessagingHubScreenState extends State<MessagingHubScreen> {
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<dynamic> _conversations = [];
  String? _currentUserId;

  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _currentUserId = auth.user?['id'];
    _apiClient = ApiClient(baseUrl: auth.baseUrl);

    _fetchConversations();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchConversations(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
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
        }
      }
    } catch (e) {
      debugPrint("Error fetching conversations: $e");
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  String _getChatTitle(Map<String, dynamic> conversation) {
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
                      child: Text(
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
                    subtitle: lastMsg != null
                        ? Text(
                            lastMsg['content'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread ? Colors.black87 : Colors.grey,
                              fontWeight: hasUnread
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          )
                        : const Text(
                            "Started a conversation",
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                    trailing: hasUnread
                        ? Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            conversationId: conv['id'],
                            chatTitle: title,
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
