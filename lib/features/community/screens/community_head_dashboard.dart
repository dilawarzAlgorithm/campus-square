import 'package:flutter/material.dart';
import 'package:campus_square/features/vault/screens/vault_screen.dart';
import 'package:campus_square/features/dashboard/screens/dashboard_screen.dart';

class CommunityHeadDashboardScreen extends StatefulWidget {
  const CommunityHeadDashboardScreen({super.key});

  @override
  State<CommunityHeadDashboardScreen> createState() =>
      _CommunityHeadDashboardScreenState();
}

class _CommunityHeadDashboardScreenState
    extends State<CommunityHeadDashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const Center(child: Text('Square: Community Notices')),
    const Center(child: Text('Bazaar: Marketplace')),
    const AcademicVaultScreen(),
    const _CommunityPanelTab(),
    const ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Campus Square',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
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
                      'Community Hub',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your students, captains, and moderate content.',
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
          'Member List',
          Icons.list_alt,
          'View and manage community members.',
        ),
        _buildHeadCard(
          context,
          'Promote Captains',
          Icons.star,
          'Assign captain roles to active students.',
        ),
        _buildHeadCard(
          context,
          'Content Moderation',
          Icons.gavel,
          'Delete flagged messages and posts.',
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
          // TODO: Navigate to specific management screens
        },
      ),
    );
  }
}
