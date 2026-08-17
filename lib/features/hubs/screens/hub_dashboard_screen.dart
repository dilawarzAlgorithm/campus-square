import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/chat/screens/chat_screen.dart';

class HubDashboardScreen extends StatefulWidget {
  final String hubId;
  final String hubName;
  final bool isHubAdmin;

  const HubDashboardScreen({
    super.key,
    required this.hubId,
    required this.hubName,
    required this.isHubAdmin,
  });

  @override
  State<HubDashboardScreen> createState() => _HubDashboardScreenState();
}

class _HubDashboardScreenState extends State<HubDashboardScreen> {
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<dynamic> _teams = [];

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchTeams();
  }

  Future<void> _fetchTeams() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/hubs?type=TEAM&parent_id=${widget.hubId}",
        method: "GET",
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _teams = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching teams: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinTeam(String teamId) async {
    try {
      final res = await _apiClient.authenticatedRequest(
        context,
        "/api/hubs/$teamId/join",
        method: "POST",
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(jsonDecode(res.body)['message']),
            backgroundColor: Colors.green,
          ),
        );
        _fetchTeams();
      }
    } catch (e) {
      //pass
    }
  }

  void _confirmDeleteHub() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Hub?'),
        content: const Text(
          'Are you sure you want to delete this hub? This action is permanent and will remove all teams, messages, media, and members inside it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteHub();
            },
            child: const Text('Delete Hub'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteHub() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/hubs/${widget.hubId}",
        method: "DELETE",
      );
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hub deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Delete Hub Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCreateTeamDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String privacy = 'PUBLIC';
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Create Team / Channel'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Team Name (e.g. Core Team, Tech)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: "Description",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: privacy,
                    decoration: const InputDecoration(
                      labelText: "Privacy",
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'PUBLIC',
                        child: Text("Public (Open to all)"),
                      ),
                      DropdownMenuItem(
                        value: 'PRIVATE',
                        child: Text("Private (Request/Invite)"),
                      ),
                    ],
                    onChanged: (val) => setDialogState(() => privacy = val!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty) return;
                        setDialogState(() => isSaving = true);
                        try {
                          final res = await _apiClient.authenticatedRequest(
                            context,
                            "/api/hubs",
                            method: "POST",
                            body: jsonEncode({
                              "name": nameCtrl.text.trim(),
                              "description": descCtrl.text.trim(),
                              "type": "TEAM",
                              "privacy": privacy,
                              "parent_id": widget.hubId,
                            }),
                          );
                          if (!context.mounted) return;
                          if (res.statusCode == 200 && mounted) {
                            Navigator.pop(ctx);
                            _fetchTeams();
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAssignLeadDialog() async {
    if (_teams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please create a Team first before assigning leads."),
        ),
      );
      return;
    }

    try {
      final res = await _apiClient.authenticatedRequest(
        context,
        "/api/chat/conversations",
        method: "GET",
      );

      if (res.statusCode != 200 || !mounted) return;

      final convs = jsonDecode(res.body) as List<dynamic>;
      final clubConv = convs.where((c) => c['id'] == widget.hubId).firstOrNull;

      if (clubConv == null) return;

      final participants = (clubConv['participants'] as List<dynamic>)
          .where((p) => p['is_approved'] == true)
          .toList();

      if (participants.isEmpty) return;

      String selectedUserId = participants.first['user']['id'];
      String selectedTeamId = _teams.first['id'];
      bool isSaving = false;

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Assign Team Lead'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Select Member:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUserId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: participants.map<DropdownMenuItem<String>>((p) {
                      final u = p['user'];
                      return DropdownMenuItem(
                        value: u['id'] as String,
                        child: Text("${u['first_name']} ${u['last_name']}"),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setDialogState(() => selectedUserId = val!),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Assign as Lead for Team:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTeamId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _teams.map<DropdownMenuItem<String>>((team) {
                      return DropdownMenuItem(
                        value: team['id'] as String,
                        child: Text(team['name'] as String),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setDialogState(() => selectedTeamId = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            final assignRes = await _apiClient.authenticatedRequest(
                              context,
                              "/api/hubs/$selectedTeamId/members/$selectedUserId/make-lead",
                              method: "PATCH",
                            );
                            if (!context.mounted) return;
                            if (assignRes.statusCode == 200 && mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Team Lead assigned successfully!",
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              _fetchTeams();
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Assign Lead'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      debugPrint("Error fetching members for lead assignment: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStaff = [
      'ADMIN',
      'COMMUNITY_HEAD',
    ].contains(context.read<CampusSquareAuth>().user?['role']);
    final canManageTeams = widget.isHubAdmin || isStaff;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.hubName),
        actions: [
          if (canManageTeams) ...[
            IconButton(
              icon: const Icon(Icons.delete_forever),
              color: Colors.redAccent,
              tooltip: "Delete Hub",
              onPressed: _confirmDeleteHub,
            ),
            IconButton(
              icon: const Icon(Icons.person),
              tooltip: "Assign Team Lead",
              onPressed: _showAssignLeadDialog,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: "Create Team",
              onPressed: _showCreateTeamDialog,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    "MAIN",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.1,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  title: const Text(
                    "General Chat",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text("Main discussion area for all members"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          conversationId: widget.hubId,
                          chatTitle: widget.hubName,
                          isGroup: true,
                        ),
                      ),
                    );
                    if (!context.mounted) return;
                    if (result == true && mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "TEAMS & CHANNELS",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      if (canManageTeams)
                        InkWell(
                          onTap: _showCreateTeamDialog,
                          child: Row(
                            children: [
                              Icon(
                                Icons.add,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                "Add Team",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (_teams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "No teams created yet.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ..._teams.map((team) {
                    final bool isMember = team['is_member'] == true;
                    final bool isPending = team['is_pending'] == true;
                    final bool isPrivate = team['privacy'] == 'PRIVATE';

                    return ListTile(
                      leading: Icon(
                        isPrivate ? Icons.lock_outline : Icons.tag,
                        color: Colors.blueGrey,
                      ),
                      title: Text(
                        team['name'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: team['description'] != null
                          ? Text(team['description'])
                          : null,
                      trailing: isMember
                          ? ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor: theme.colorScheme.primary,
                                elevation: 0,
                              ),
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      conversationId: team['id'],
                                      chatTitle: team['name'],
                                      isGroup: true,
                                    ),
                                  ),
                                );

                                if (result == true) {
                                  _fetchTeams();
                                }
                              },
                              child: const Text("Open"),
                            )
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: isPending
                                  ? null
                                  : () => _joinTeam(team['id']),
                              child: Text(isPending ? "Pending" : "Join"),
                            ),
                    );
                  }),
              ],
            ),
    );
  }
}
