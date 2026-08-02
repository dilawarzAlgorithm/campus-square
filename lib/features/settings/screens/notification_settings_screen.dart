import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/core/theme/theme_provider.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  bool _allNotifications = true;
  bool _messageHub = true;
  bool _allNotices = true;
  bool _importantNotices = true;
  bool _resources = true;
  bool _isLoading = true;
  String _instId = '';

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _instId = auth.user?['institution_id'] ?? '';
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _allNotifications = prefs.getBool('fcm_all_notifications') ?? true;
      _messageHub = prefs.getBool('fcm_message_hub') ?? true;
      _allNotices = prefs.getBool('fcm_all_notices') ?? true;
      _importantNotices = prefs.getBool('fcm_important_notices') ?? true;
      _resources = prefs.getBool('fcm_resources') ?? true;
      _isLoading = false;
    });

    _syncAllTopics();
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _handleTopic(String topic, bool subscribe) async {
    if (subscribe && _allNotifications) {
      await _fcm.subscribeToTopic(topic);
      debugPrint('Subscribed to $topic');
    } else {
      await _fcm.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from $topic');
    }
  }

  Future<void> _syncAllTopics() async {
    if (_instId.isEmpty) return;
    await _handleTopic('${_instId}_all_notices', _allNotices);
    await _handleTopic('${_instId}_important_notices', _importantNotices);
    await _handleTopic('${_instId}_resources', _resources);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final themeProvider = context.watch<ThemeProvider>();
    final isCurrentlyDark =
        themeProvider.themeMode == ThemeMode.dark ||
        (themeProvider.themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'APPEARANCE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text(
              'Dark Mode',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Toggle dark theme on or off'),
            secondary: const Icon(Icons.dark_mode_outlined),
            value: isCurrentlyDark,
            onChanged: (bool value) {
              themeProvider.toggleTheme(value);
            },
          ),
          const SizedBox(height: 16),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text(
              'NOTIFICATIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blueGrey),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Customize the push notifications you receive. Ensure notifications are enabled in your device settings.",
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text(
              'All Notifications',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Enable or disable all notifications'),
            value: _allNotifications,
            onChanged: (bool value) async {
              setState(() {
                _allNotifications = value;
                if (!value) {
                  _messageHub = false;
                  _allNotices = false;
                  _importantNotices = false;
                  _resources = false;
                } else {
                  _messageHub = true;
                  _allNotices = true;
                  _importantNotices = true;
                  _resources = true;
                }
              });
              await _savePreference('fcm_all_notifications', _allNotifications);
              await _savePreference('fcm_message_hub', _messageHub);
              await _savePreference('fcm_all_notices', _allNotices);
              await _savePreference('fcm_important_notices', _importantNotices);
              await _savePreference('fcm_resources', _resources);

              _syncAllTopics();

              if (context.mounted) {
                context.read<CampusSquareAuth>().updateFCMTokenStatus(
                  value ? _messageHub : false,
                );
              }
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Message Hub'),
            subtitle: const Text('New messages and mentions'),
            value: _messageHub,
            onChanged: _allNotifications
                ? (bool value) async {
                    setState(() => _messageHub = value);
                    await _savePreference('fcm_message_hub', value);

                    if (context.mounted) {
                      context.read<CampusSquareAuth>().updateFCMTokenStatus(
                        value,
                      );
                    }
                  }
                : null,
          ),
          SwitchListTile(
            title: const Text('All Notices'),
            subtitle: const Text('General campus announcements'),
            value: _allNotices,
            onChanged: _allNotifications
                ? (bool value) async {
                    setState(() => _allNotices = value);
                    await _savePreference('fcm_all_notices', value);
                    if (_instId.isNotEmpty) {
                      _handleTopic('${_instId}_all_notices', value);
                    }
                  }
                : null,
          ),
          SwitchListTile(
            title: const Text('Important Notices'),
            subtitle: const Text('Urgent alerts and critical updates'),
            value: _importantNotices,
            onChanged: _allNotifications
                ? (bool value) async {
                    setState(() => _importantNotices = value);
                    await _savePreference('fcm_important_notices', value);
                    if (_instId.isNotEmpty) {
                      _handleTopic('${_instId}_important_notices', value);
                    }
                  }
                : null,
          ),
          SwitchListTile(
            title: const Text('Resources'),
            subtitle: const Text('New study materials and resources'),
            value: _resources,
            onChanged: _allNotifications
                ? (bool value) async {
                    setState(() => _resources = value);
                    await _savePreference('fcm_resources', value);
                    if (_instId.isNotEmpty) {
                      _handleTopic('${_instId}_resources', value);
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
