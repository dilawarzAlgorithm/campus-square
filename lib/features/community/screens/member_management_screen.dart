import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  late final ApiClient _apiClient;
  List<dynamic> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/community/members",
        method: "GET",
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _members = jsonDecode(response.body);
          });
        }
      } else {
        _showError("Failed to load members.");
      }
    } catch (e) {
      _showError("Network error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleBlock(String userId, bool blockStatus) async {
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/community/members/$userId/block",
        method: "PATCH",
        body: jsonEncode({"is_blocked": blockStatus}),
      );

      if (response.statusCode == 200) {
        _fetchMembers();
        _showSuccess(blockStatus ? "User blocked" : "User unblocked");
      } else {
        _showError(
          jsonDecode(response.body)['detail'] ?? "Block action failed",
        );
      }
    } catch (e) {
      _showError("Action error: $e");
    }
  }

  Future<void> _updateRollNumber(String userId, String rollNumber) async {
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/community/members/$userId/roll-number",
        method: "PATCH",
        body: jsonEncode({"roll_number": rollNumber}),
      );

      if (response.statusCode == 200) {
        _fetchMembers();
        _showSuccess("Roll number updated successfully");
      } else {
        _showError(jsonDecode(response.body)['detail'] ?? "Update failed");
      }
    } catch (e) {
      _showError("Update error: $e");
    }
  }

  void _showEditRollNumberDialog(Map<String, dynamic> user) {
    final controller = TextEditingController(text: user['roll_number'] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Edit Roll Number"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Roll Number / Student ID',
            hintText: 'e.g. 26BCS098',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateRollNumber(user['id'], controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showStorageLimitDialog(Map<String, dynamic> user) {
    final currentLimit = user['storage_limit'];
    final currentLimitMb = currentLimit != null
        ? (currentLimit / (1024 * 1024)).round().toString()
        : '';
    final controller = TextEditingController(text: currentLimitMb);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Set Storage Limit"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Set a custom storage limit for ${user['first_name']}. Leave blank to reset to the institution default.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Limit in MB',
                hintText: 'e.g. 100',
                border: OutlineInputBorder(),
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
              final val = controller.text.trim();
              final int? mbLimit = val.isNotEmpty ? int.tryParse(val) : null;

              try {
                final response = await _apiClient.authenticatedRequest(
                  context,
                  "/api/community/members/${user['id']}/storage-limit",
                  method: "PATCH",
                  body: jsonEncode({"storage_limit_mb": mbLimit}),
                );
                if (response.statusCode == 200) {
                  _fetchMembers();
                  _showSuccess("Storage limit updated successfully");
                } else {
                  _showError(
                    jsonDecode(response.body)['detail'] ?? "Update failed",
                  );
                }
              } catch (e) {
                _showError("Update error: $e");
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAutoAssignDialog() {
    bool extractFromEmail = true;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Auto-Assign Roll Numbers'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Extract roll numbers automatically from student emails? (e.g. 26BCS098@mit.edu -> 26BCS098). This will apply to existing students missing a roll number and all future registrations.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text(
                    'Enable Auto-Extraction',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  value: extractFromEmail,
                  onChanged: (val) =>
                      setDialogState(() => extractFromEmail = val),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        try {
                          final response = await _apiClient
                              .authenticatedRequest(
                                context,
                                "/api/community/settings/auto-roll-numbers",
                                method: "POST",
                                body: jsonEncode({
                                  "extract_roll_from_email": extractFromEmail,
                                }),
                              );
                          if (!context.mounted) return;
                          Navigator.pop(ctx);
                          if (response.statusCode == 200) {
                            _showSuccess(jsonDecode(response.body)['message']);
                            _fetchMembers();
                          } else {
                            _showError("Failed to update settings");
                          }
                        } catch (e) {
                          if (context.mounted) Navigator.pop(ctx);
                          _showError("Error: $e");
                        }
                      },
                icon: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Apply Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Member Directory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: "Auto-Assign Roll Numbers",
            onPressed: _showAutoAssignDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _members.isEmpty
          ? const Center(child: Text("No members found."))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _members.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final user = _members[index];
                final bool isBlocked = user['is_blocked'] ?? false;
                final String role = user['role'] ?? 'STUDENT';
                final bool isHead = role == 'COMMUNITY_HEAD';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isBlocked
                        ? Colors.red.shade100
                        : theme.colorScheme.primary.withValues(alpha: 0.1),
                    child: Text(
                      user['first_name'][0].toUpperCase(),
                      style: TextStyle(
                        color: isBlocked
                            ? Colors.red
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    "${user['first_name']} ${user['last_name']}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: isBlocked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user['email'], style: const TextStyle(fontSize: 12)),
                      if (user['roll_number'] != null)
                        Text(
                          "Roll No: ${user['roll_number']}",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              role,
                              style: TextStyle(
                                fontSize: 10,
                                color: role == 'CAPTAIN'
                                    ? Colors.orange.shade800
                                    : Colors.blueGrey,
                              ),
                            ),
                            backgroundColor: role == 'CAPTAIN'
                                ? Colors.orange.shade50
                                : Colors.grey.shade100,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          if (isBlocked) ...[
                            const SizedBox(width: 8),
                            const Chip(
                              label: Text(
                                "BLOCKED",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                ),
                              ),
                              backgroundColor: Colors.white,
                              side: BorderSide(color: Colors.red),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  trailing: isHead
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'block') {
                              _toggleBlock(user['id'], true);
                            }
                            if (value == 'unblock') {
                              _toggleBlock(user['id'], false);
                            }
                            if (value == 'edit_roll') {
                              _showEditRollNumberDialog(user);
                            }
                            if (value == 'edit_storage') {
                              _showStorageLimitDialog(user);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit_roll',
                              child: Text('Edit Roll Number'),
                            ),
                            const PopupMenuItem(
                              value: 'edit_storage',
                              child: Text('Edit Storage Quota'),
                            ),
                            const PopupMenuDivider(),
                            if (!isBlocked)
                              const PopupMenuItem(
                                value: 'block',
                                child: Text(
                                  'Block User',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            if (isBlocked)
                              const PopupMenuItem(
                                value: 'unblock',
                                child: Text(
                                  'Unblock User',
                                  style: TextStyle(color: Colors.green),
                                ),
                              ),
                          ],
                        ),
                );
              },
            ),
    );
  }
}
