import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:provider/provider.dart';

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
    _unreadTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchUnreadCount(),
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

      body: IndexedStack(index: _currentIndex, children: _screens),

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
