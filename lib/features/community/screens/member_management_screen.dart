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

  Future<void> _updateRole(String userId, String newRole) async {
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/community/members/$userId/role",
        method: "PATCH",
        body: jsonEncode({"role": newRole}),
      );
      if (response.statusCode == 200) {
        _fetchMembers();
        _showSuccess("User role updated to $newRole");
      } else {
        _showError(jsonDecode(response.body)['detail'] ?? "Update failed");
      }
    } catch (e) {
      _showError("Update error: $e");
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Member Directory')),
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
                            if (value == 'promote') {
                              _updateRole(user['id'], 'CAPTAIN');
                            }
                            if (value == 'demote') {
                              _updateRole(user['id'], 'STUDENT');
                            }
                          },
                          itemBuilder: (context) => [
                            if (role == 'STUDENT')
                              const PopupMenuItem(
                                value: 'promote',
                                child: Text('Promote to Captain'),
                              ),
                            if (role == 'CAPTAIN')
                              const PopupMenuItem(
                                value: 'demote',
                                child: Text('Demote to Student'),
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
