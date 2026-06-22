import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class AcademicVaultScreen extends StatefulWidget {
  const AcademicVaultScreen({super.key});

  @override
  State<AcademicVaultScreen> createState() => _AcademicVaultScreenState();
}

class _AcademicVaultScreenState extends State<AcademicVaultScreen> {
  late final ApiClient _apiClient;
  List<dynamic> _departments = [];
  List<dynamic> _resources = [];
  bool _isLoading = true;
  String? _selectedDeptId;

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    try {
      final deptResponse = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/departments",
        method: "GET",
      );

      if (deptResponse.statusCode == 200) {
        final decoded = jsonDecode(deptResponse.body);
        _departments = decoded;
        if (_departments.isNotEmpty) {
          _selectedDeptId = _departments.first["id"];
        }
      }

      await _fetchResources();
    } catch (e) {
      debugPrint("Vault fetch error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchResources() async {
    String query = "";
    if (_selectedDeptId != null) {
      query = "?department_id=$_selectedDeptId";
    }

    try {
      final resResponse = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/resources$query",
        method: "GET",
      );

      if (resResponse.statusCode == 200) {
        setState(() {
          _resources = jsonDecode(resResponse.body);
        });
      }
    } catch (e) {
      debugPrint("Error fetching resources: $e");
    }
  }

  Future<void> _voteResource(String resourceId, String voteType) async {
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/resources/$resourceId/vote",
        method: "POST",
        body: jsonEncode({"vote_type": voteType}),
      );

      if (response.statusCode == 200) {
        _fetchResources();
      }
    } catch (e) {
      debugPrint("Voting error: $e");
    }
  }

  void _showAddDepartmentDialog() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Department'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Department Name (e.g. Computer Science)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Short Code (e.g. CSE)',
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
              if (nameController.text.isEmpty || codeController.text.isEmpty) {
                return;
              }
              Navigator.pop(ctx);
              setState(() => _isLoading = true);

              try {
                final response = await _apiClient.authenticatedRequest(
                  context,
                  "/api/vault/departments",
                  method: "POST",
                  body: jsonEncode({
                    "name": nameController.text.trim(),
                    "code": codeController.text.trim().toUpperCase(),
                  }),
                );

                if (response.statusCode == 201) {
                  _fetchInitialData();
                }
              } catch (_) {}
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: theme.cardColor,
            child: Row(
              children: [
                const Text(
                  'Department: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _departments.isEmpty
                      ? const Text('No Departments Created yet.')
                      : DropdownButton<String>(
                          value: _selectedDeptId,
                          isExpanded: true,
                          underline: const SizedBox(),
                          items: _departments.map<DropdownMenuItem<String>>((
                            dept,
                          ) {
                            return DropdownMenuItem<String>(
                              value: dept["id"],
                              child: Text("[${dept['code']}] ${dept['name']}"),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedDeptId = val;
                            });
                            _fetchResources();
                          },
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _showAddDepartmentDialog,
                  tooltip: 'Create Department',
                ),
              ],
            ),
          ),

          Expanded(
            child: _resources.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No learning documents uploaded to this department.',
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _resources.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final item = _resources[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        child: ListTile(
                          title: Text(
                            item["title"],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                item["description"] ??
                                    "No description provided.",
                              ),
                              const SizedBox(height: 4),
                              Chip(
                                label: Text(
                                  item["resource_type"],
                                  style: const TextStyle(fontSize: 10),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_upward),
                                color: theme.colorScheme.primary,
                                onPressed: () =>
                                    _voteResource(item["id"], "UPVOTE"),
                              ),
                              Text(
                                '${item["upvote_count"] - item["downvote_count"]}',
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward),
                                color: Colors.red,
                                onPressed: () =>
                                    _voteResource(item["id"], "DOWNVOTE"),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
