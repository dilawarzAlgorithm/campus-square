import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'],
        title: json['title'],
        body: json['body'],
        timestamp: DateTime.parse(json['timestamp']),
        isRead: json['isRead'],
      );
}

class NotificationProvider extends ChangeNotifier {
  List<AppNotification> _notifications = [];
  String? _currentUserId;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> setUserId(String? userId) async {
    if (_currentUserId != userId) {
      _currentUserId = userId;
      _notifications.clear();

      if (userId != null) {
        await _loadHistory();
      }
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    await FirebaseMessaging.instance.subscribeToTopic('all_users');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final senderId = message.data['sender_id'];
      if (senderId != null &&
          _currentUserId != null &&
          senderId == _currentUserId) {
        return;
      }

      if (message.notification != null) {
        _addNotification(
          message.notification!.title ?? 'New Notification',
          message.notification!.body ?? '',
        );
      }
    });
  }

  void _addNotification(String title, String body) {
    _notifications.insert(
      0,
      AppNotification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        timestamp: DateTime.now(),
      ),
    );
    _saveHistory();
    notifyListeners();
  }

  Future<void> markAllAsRead() async {
    for (var n in _notifications) {
      n.isRead = true;
    }
    _saveHistory();
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    if (_currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('notification_history_$_currentUserId');

    if (data != null) {
      _notifications = data
          .map((e) => AppNotification.fromJson(jsonDecode(e)))
          .toList();
      notifyListeners();
    }
  }

  Future<void> _saveHistory() async {
    if (_currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final data = _notifications
        .take(50) // latest 50
        .map((e) => jsonEncode(e.toJson()))
        .toList();
    await prefs.setStringList('notification_history_$_currentUserId', data);
  }

  Future<void> clearHistory() async {
    if (_currentUserId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('notification_history_$_currentUserId');
    }
    _notifications.clear();
    notifyListeners();
  }
}

class NotificationHistorySheet extends StatelessWidget {
  const NotificationHistorySheet({super.key});

  String _formatTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: provider.notifications.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "You're all caught up!",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: provider.notifications.length,
                    itemBuilder: (context, index) {
                      final notif = provider.notifications[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.notifications,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          notif.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(notif.body),
                        ),
                        trailing: Text(
                          _formatTime(notif.timestamp),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
