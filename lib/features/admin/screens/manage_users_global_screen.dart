import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class ManageUsersGlobalScreen extends StatefulWidget {
  const ManageUsersGlobalScreen({super.key});

  @override
  State<ManageUsersGlobalScreen> createState() =>
      _ManageUsersGlobalScreenState();
}

class _ManageUsersGlobalScreenState extends State<ManageUsersGlobalScreen> {
  late final ApiClient _apiClient;
  List<dynamic> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/admin/users",
        method: "GET",
      );
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _users = jsonDecode(response.body);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching users: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleBlockStatus(String userId, bool isBlocked) async {
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/admin/users/$userId/block",
        method: "PATCH",
        body: jsonEncode({"is_blocked": isBlocked}),
      );
      if (!mounted) return;

      if (response.statusCode == 200) {
        _fetchUsers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update status'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error updating block status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Global User Directory')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
          ? const Center(child: Text("No users found."))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                final isBlocked = user['is_blocked'] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isBlocked
                          ? Colors.red.shade100
                          : Colors.blue.shade100,
                      child: Icon(
                        Icons.person,
                        color: isBlocked ? Colors.red : Colors.blue,
                      ),
                    ),
                    title: Text(
                      "${user['first_name']} ${user['last_name']}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration: isBlocked
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: Text("${user['email']}\nRole: ${user['role']}"),
                    isThreeLine: true,
                    trailing: user['role'] == 'ADMIN'
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (val) {
                              if (val == 'block') {
                                _toggleBlockStatus(user['id'], true);
                              } else if (val == 'unblock') {
                                _toggleBlockStatus(user['id'], false);
                              }
                            },
                            itemBuilder: (context) => [
                              if (!isBlocked)
                                const PopupMenuItem(
                                  value: 'block',
                                  child: Text(
                                    'Block Globally',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              if (isBlocked)
                                const PopupMenuItem(
                                  value: 'unblock',
                                  child: Text(
                                    'Unblock',
                                    style: TextStyle(color: Colors.green),
                                  ),
                                ),
                            ],
                          ),
                  ),
                );
              },
            ),
    );
  }
}
