import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class FullProfileScreen extends StatelessWidget {
  const FullProfileScreen({super.key});

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0, left: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.blueGrey),
        title: Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        subtitle: Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ),
    );
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

  void _showEditPreferencesDialog(BuildContext context, CampusSquareAuth auth) {
    final profilePrefs = auth.user?['profile'] as Map<String, dynamic>?;
    final dietaryController = TextEditingController(
      text: profilePrefs?['dietary_preference'] ?? '',
    );
    final sleepController = TextEditingController(
      text: profilePrefs?['sleep_schedule'] ?? '',
    );
    final studyController = TextEditingController(
      text: profilePrefs?['study_habits'] ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Preferences'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dietaryController,
              decoration: const InputDecoration(
                labelText: 'Dietary Preference',
                hintText: 'e.g. Vegetarian, Non-Veg, Vegan',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sleepController,
              decoration: const InputDecoration(
                labelText: 'Sleep Schedule',
                hintText: 'e.g. Early Bird, Night Owl',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: studyController,
              decoration: const InputDecoration(
                labelText: 'Study Habits',
                hintText: 'e.g. Quiet Room, Music, Group Study',
              ),
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
              Navigator.pop(ctx);
              bool success = await auth.updatePreferences(
                dietaryController.text.trim(),
                sleepController.text.trim(),
                studyController.text.trim(),
              );

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? "Preferences updated!"
                        : "Failed to update preferences",
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

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Personal Information')),
        body: const Center(child: Text('Profile data not available.')),
      );
    }

    final profilePrefs = user['profile'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(title: const Text('Personal Information')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionHeader(
            context,
            "Identity & Contact",
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showEditNameDialog(context, auth),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          _buildInfoTile(
            context,
            'First Name',
            user['first_name'] ?? 'N/A',
            Icons.person_outline,
          ),
          _buildInfoTile(
            context,
            'Last Name',
            user['last_name'] ?? 'N/A',
            Icons.person_outline,
          ),
          _buildInfoTile(
            context,
            'Email Address',
            user['email'] ?? 'N/A',
            Icons.email_outlined,
          ),
          _buildInfoTile(
            context,
            'Platform Role',
            user['role'] ?? 'STUDENT',
            Icons.admin_panel_settings_outlined,
          ),
          _buildSectionHeader(context, "Academics"),
          _buildInfoTile(
            context,
            'Institution',
            user['institution_name'] ?? 'Not Assigned',
            Icons.account_balance_outlined,
          ),
          _buildInfoTile(
            context,
            'Department',
            user['department_name'] ?? 'Not Assigned',
            Icons.domain_outlined,
          ),
          _buildInfoTile(
            context,
            'Roll Number',
            user['roll_number'] ?? 'Not Assigned',
            Icons.badge_outlined,
          ),
          _buildSectionHeader(
            context,
            "Preferences & Habits",
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showEditPreferencesDialog(context, auth),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          _buildInfoTile(
            context,
            'Dietary Preference',
            profilePrefs?['dietary_preference'] ?? 'Not specified',
            Icons.restaurant_outlined,
          ),
          _buildInfoTile(
            context,
            'Sleep Schedule',
            profilePrefs?['sleep_schedule'] ?? 'Not specified',
            Icons.nights_stay_outlined,
          ),
          _buildInfoTile(
            context,
            'Study Habits',
            profilePrefs?['study_habits'] ?? 'Not specified',
            Icons.menu_book_outlined,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
