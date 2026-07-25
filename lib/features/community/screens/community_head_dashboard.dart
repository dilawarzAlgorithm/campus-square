import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:provider/provider.dart';

import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/core/services/notification_service.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/vault/screens/vault_screen.dart';
import 'package:campus_square/features/profile/screens/staff_profile_screen.dart';
import 'package:campus_square/features/square/screens/square_screen.dart';
import 'package:campus_square/features/community/screens/member_management_screen.dart';
import 'package:campus_square/features/chat/screens/messaging_hub_screen.dart';

class CommunityHeadDashboardScreen extends StatefulWidget {
  const CommunityHeadDashboardScreen({super.key});

  @override
  State<CommunityHeadDashboardScreen> createState() =>
      _CommunityHeadDashboardScreenState();
}

class _CommunityHeadDashboardScreenState
    extends State<CommunityHeadDashboardScreen> {
  int _currentIndex = 0;
  int _unreadCount = 0;
  Timer? _unreadTimer;

  final List<Widget> _screens = [
    const SquareScreen(),
    const Center(child: Text('Bazaar: Marketplace (Moderation Mode)')),
    const AcademicVaultScreen(),
    const _CommunityPanelTab(),
    const StaffProfileScreen(),
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
      body: _screens[_currentIndex],
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
            icon: Icon(Icons.shield_outlined),
            activeIcon: Icon(Icons.shield),
            label: 'Manage',
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

class _CommunityPanelTab extends StatelessWidget {
  const _CommunityPanelTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield, size: 48, color: Colors.teal),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Institution Hub',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your campus students, captains, and moderate content.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.teal.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildHeadCard(
          context,
          'Member Directory',
          Icons.list_alt,
          'View and manage all students in your institution.',
        ),
        _buildHeadCard(
          context,
          'Assign Captains',
          Icons.star,
          'Promote reliable students to assist with moderation.',
        ),
      ],
    );
  }

  Widget _buildHeadCard(
    BuildContext context,
    String title,
    IconData icon,
    String subtitle,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.teal.shade100,
          child: Icon(icon, color: Colors.teal),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          if (title == 'Member Directory' || title == 'Assign Captains') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MemberManagementScreen(),
              ),
            );
          }
        },
      ),
    );
  }
}
