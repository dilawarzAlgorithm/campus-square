import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/profile/screens/staff_profile_screen.dart';
import 'package:campus_square/features/admin/screens/manage_institutions_screen.dart';
import 'package:campus_square/features/admin/screens/manage_users_global_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const _AdminPanelTab(),
    const StaffProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Campus Square (Global)',
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
            icon: Icon(Icons.admin_panel_settings_outlined),
            activeIcon: Icon(Icons.admin_panel_settings),
            label: 'Infrastructure',
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

class _AdminPanelTab extends StatefulWidget {
  const _AdminPanelTab();

  @override
  State<_AdminPanelTab> createState() => _AdminPanelTabState();
}

class _AdminPanelTabState extends State<_AdminPanelTab> {
  Map<String, dynamic>? _metrics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMetrics();
  }

  Future<void> _fetchMetrics() async {
    try {
      final auth = context.read<CampusSquareAuth>();
      final client = ApiClient(baseUrl: auth.baseUrl);
      final response = await client.authenticatedRequest(
        context,
        "/api/admin/metrics",
        method: "GET",
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _metrics = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.public, size: 48, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Global Infrastructure',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage all registered institutions and platform-wide settings.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_metrics != null)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildMetricCard(
                context,
                'Institutions',
                _metrics!['total_institutions'].toString(),
                Icons.business,
              ),
              _buildMetricCard(
                context,
                'Total Users',
                _metrics!['total_users'].toString(),
                Icons.people,
              ),
              _buildMetricCard(
                context,
                'Comm. Heads',
                _metrics!['total_heads'].toString(),
                Icons.shield,
              ),
              _buildMetricCard(
                context,
                'Resources',
                _metrics!['total_resources'].toString(),
                Icons.folder,
              ),
            ],
          ),
        const SizedBox(height: 24),
        _buildAdminCard(
          context,
          'Global Broadcast',
          Icons.campaign,
          'Send an urgent push notification to every user.',
          () => _showBroadcastDialog(context),
        ),
        _buildAdminCard(
          context,
          'Manage Institutions',
          Icons.business,
          'Provision, edit, or block campuses.',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ManageInstitutionsScreen()),
          ),
        ),
        _buildAdminCard(
          context,
          'Global User Directory',
          Icons.people,
          'Search and moderate all users platform-wide.',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ManageUsersGlobalScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.blueGrey, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Text(
              title,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminCard(
    BuildContext context,
    String title,
    IconData icon,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _showBroadcastDialog(BuildContext context) {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.campaign, color: Colors.red),
                SizedBox(width: 8),
                Text('Global Broadcast'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This will send a push notification to EVERY user registered on Campus Square, overriding their mute settings. Use with extreme caution.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Broadcast Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Message Body',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (titleController.text.trim().isEmpty ||
                            bodyController.text.trim().isEmpty) {
                          return;
                        }

                        setDialogState(() => isSubmitting = true);

                        try {
                          final auth = context.read<CampusSquareAuth>();
                          final client = ApiClient(baseUrl: auth.baseUrl);
                          final response = await client.authenticatedRequest(
                            context,
                            "/api/notifications/broadcast",
                            method: "POST",
                            body: jsonEncode({
                              "title": titleController.text.trim(),
                              "body": bodyController.text.trim(),
                            }),
                          );

                          if (context.mounted) {
                            Navigator.pop(ctx);
                            if (response.statusCode == 200) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Broadcast sent successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to send broadcast.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Send Broadcast'),
              ),
            ],
          );
        },
      ),
    );
  }
}
