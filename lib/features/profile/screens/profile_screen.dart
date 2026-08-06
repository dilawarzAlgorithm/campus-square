import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/vault/screens/saved_vault_screen.dart';
import 'package:campus_square/features/profile/screens/full_profile_screen.dart';
import 'package:campus_square/features/settings/screens/notification_settings_screen.dart';
import 'package:campus_square/features/timetable/screens/timetable_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  IconData _getKarmaIcon(int level) {
    switch (level) {
      case 4:
        return Icons.diamond_rounded; // Campus Legend
      case 3:
        return Icons.local_library_rounded; // Scholar
      case 2:
        return Icons.verified_user_rounded; // Contributor
      case 1:
      default:
        return Icons.eco_rounded; // Novice
    }
  }

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

    final karma = user?["karma"] ?? 0;
    final karmaTier = user?["karma_tier"] as Map<String, dynamic>?;
    final int level = karmaTier?["level"] ?? 1;
    final String title = karmaTier?["title"] ?? "Novice";
    final double progress = (karmaTier?["progress_percentage"] ?? 0.0)
        .toDouble();
    final String nextTierText =
        karmaTier != null && karmaTier["points_to_next"] != null
        ? '${karmaTier["points_to_next"]} pts to ${karmaTier["next_tier_title"]}'
        : 'Max Level Reached!';

    final int storageUsed = user?["storage_used"] ?? 0;
    final int storageLimit =
        user?["effective_storage_limit"] ?? 52428800; // default 50 MB
    final double usedMb = storageUsed / (1024 * 1024);
    final double limitMb = storageLimit / (1024 * 1024);
    final double storageProgress = (storageLimit > 0)
        ? (storageUsed / storageLimit).clamp(0.0, 1.0)
        : 0.0;

    return RefreshIndicator(
      onRefresh: () => auth.refreshProfile(),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const SizedBox(height: 16),
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.person,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 45),
              Text(
                '${user?["first_name"] ?? "First"} ${user?["last_name"] ?? "Last"}',
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
              user?["email"] ?? "email@university.edu",
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    user?["role"] ?? "Student",
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF10B981)],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Campus Karma',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getKarmaIcon(level),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  '$karma pts',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white.withValues(alpha: 0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Level $level',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      nextTierText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Text(
              'STORAGE USAGE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Cloud Storage',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${usedMb.toStringAsFixed(1)} MB / ${limitMb.toStringAsFixed(0)} MB',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: storageProgress,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        storageProgress > 0.9
                            ? Colors.red
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (storageProgress > 0.9)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        'You are running out of storage. Delete old files to free up space.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Text(
              'ACCOUNT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('My Bazaar Listings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.bookmark_border),
                  title: const Text('Saved Vault Items'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SavedVaultScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('My Timetable & Attendance'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TimetableScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Personal Information'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FullProfileScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const NotificationSettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
