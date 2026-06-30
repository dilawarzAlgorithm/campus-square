import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class CommunityHeadDashboardScreen extends StatelessWidget {
  const CommunityHeadDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Community Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<CampusSquareAuth>().logout(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
      ),
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
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal.shade100,
          child: Icon(icon, color: Colors.teal),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // TODO: Navigate to specific management screens
        },
      ),
    );
  }
}
