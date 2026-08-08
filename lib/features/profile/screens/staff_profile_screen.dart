import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class StaffProfileScreen extends StatelessWidget {
  const StaffProfileScreen({super.key});

  void _showEditNameDialog(BuildContext context, CampusSquareAuth auth) {
    final firstController = TextEditingController(
      text: auth.user?["first_name"],
    );
    final lastController = TextEditingController(text: auth.user?["last_name"]);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstController,
              decoration: const InputDecoration(labelText: 'First Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastController,
              decoration: const InputDecoration(labelText: 'Last Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (firstController.text.trim().isEmpty ||
                  lastController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx);
              bool success = await auth.updateName(
                firstController.text.trim(),
                lastController.text.trim(),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success ? "Name updated!" : "Failed to update name",
                  ),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<CampusSquareAuth>();
    final user = auth.user;
    final theme = Theme.of(context);
    final role = user?["role"] ?? "STAFF";

    final isGlobalAdmin = role == 'ADMIN';

    return RefreshIndicator(
      onRefresh: () => auth.refreshProfile(),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const SizedBox(height: 16),
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.secondary.withValues(
                alpha: 0.1,
              ),
              child: Icon(
                isGlobalAdmin ? Icons.admin_panel_settings : Icons.shield,
                size: 48,
                color: theme.colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 45),
              Text(
                '${user?["first_name"] ?? "Staff"} ${user?["last_name"] ?? "Member"}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: Colors.grey,
                ),
                onPressed: () => _showEditNameDialog(context, auth),
              ),
            ],
          ),
          Center(
            child: Text(
              user?["email"] ?? "admin@system.local",
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified, color: Colors.teal, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    isGlobalAdmin ? "Global Administrator" : "Community Head",
                    style: TextStyle(
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 48),

          ElevatedButton.icon(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.red.shade200),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
