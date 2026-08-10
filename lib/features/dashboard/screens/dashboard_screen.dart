import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_square/core/theme/theme_provider.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/core/services/notification_service.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/vault/screens/vault_screen.dart';
import 'package:campus_square/features/profile/screens/profile_screen.dart';
import 'package:campus_square/features/square/screens/square_screen.dart';
import 'package:campus_square/features/bazaar/screens/bazaar_screen.dart';
import 'package:campus_square/features/chat/screens/messaging_hub_screen.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _currentIndex = 0;
  Timer? _unreadTimer;
  int _unreadCount = 0;

  bool _showBanner = false;
  Map<String, dynamic> _bannerData = {};

  final List<Widget> _screens = [
    const SquareScreen(),
    const BazaarScreen(),
    const AcademicVaultScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _fetchUnreadCount();
    _checkAppCampaign();
    _unreadTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchUnreadCount(),
    );
  }

  Future<void> _checkAppCampaign() async {
    try {
      final auth = context.read<CampusSquareAuth>();
      final apiClient = ApiClient(baseUrl: auth.baseUrl);

      final response = await apiClient.authenticatedRequest(
        context,
        "/api/utils/app-campaign",
        method: "GET",
      );

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);

        if (data.containsKey('primary_color_hex')) {
          context.read<ThemeProvider>().updatePrimaryColor(
            data['primary_color_hex'],
          );
        }

        if (data['show_banner'] == true) {
          setState(() {
            _showBanner = true;
            _bannerData = data;
          });
        } else {
          setState(() => _showBanner = false);
        }

        if (data['show_popup'] == true) {
          final String versionId = data['version_id'];
          final prefs = await SharedPreferences.getInstance();

          bool hasSeen = prefs.getBool('seen_campaign_$versionId') ?? false;

          if (!hasSeen) {
            await prefs.setBool('seen_campaign_$versionId', true);

            if (mounted) {
              context.read<NotificationProvider>().addSystemNotification(
                data['popup_title'] ?? "Announcement",
                data['popup_message'] ?? "Check out the latest updates.",
              );

              _showAnnouncementDialog(data);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Campaign check error: $e");
    }
  }

  void _showAnnouncementDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data['lottie_url'] != null)
              Lottie.network(
                data['lottie_url'],
                height: 180,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.stars_rounded,
                  size: 60,
                  color: Colors.amber,
                ),
              )
            else
              const Icon(Icons.stars_rounded, size: 60, color: Colors.amber),

            const SizedBox(height: 16),
            Text(
              data['popup_title'] ?? "New Update",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              data['popup_message'] ?? "",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Dismiss"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (data['target_route'] == '/square') {
                setState(() => _currentIndex = 0);
              } else if (data['target_route'] == '/bazaar') {
                setState(() => _currentIndex = 1);
              } else if (data['target_route'] == '/vault') {
                setState(() => _currentIndex = 2);
              }
            },
            child: const Text("Check it out"),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bannerData['banner_title'] ?? 'Announcement',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _bannerData['banner_message'] ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _showBanner = false),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final auth = context.read<CampusSquareAuth>();
      final apiClient = ApiClient(baseUrl: auth.baseUrl);
      final response = await apiClient.authenticatedRequest(
        context,
        "/api/chat/unread-count",
        method: "GET",
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _unreadCount = jsonDecode(response.body)['unread_count'] ?? 0;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Campus Square',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: ApiClient.isOfflineNotifier,
            builder: (context, isOffline, child) {
              if (isOffline) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Tooltip(
                    message: "You are offline. Showing cached data.",
                    child: Icon(
                      Icons.wifi_off,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: Badge(
              isLabelVisible:
                  context.watch<NotificationProvider>().unreadCount > 0,
              label: Text(
                context.watch<NotificationProvider>().unreadCount.toString(),
              ),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            onPressed: () {
              context.read<NotificationProvider>().markAllAsRead();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) => const NotificationHistorySheet(),
              );
            },
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _unreadCount > 0,
              label: Text(_unreadCount.toString()),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MessagingHubScreen()),
              ).then((_) => _fetchUnreadCount());
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_showBanner) _buildDynamicBanner(),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: _screens),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Square',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_bag_outlined),
            activeIcon: Icon(Icons.shopping_bag),
            label: 'Bazaar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_outlined),
            activeIcon: Icon(Icons.folder),
            label: 'Vault',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
