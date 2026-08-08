import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class ManageInstitutionsScreen extends StatefulWidget {
  const ManageInstitutionsScreen({super.key});

  @override
  State<ManageInstitutionsScreen> createState() =>
      _ManageInstitutionsScreenState();
}

class _ManageInstitutionsScreenState extends State<ManageInstitutionsScreen> {
  late final ApiClient _apiClient;
  List<dynamic> _institutions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchInstitutions();
  }

  Future<void> _fetchInstitutions() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/admin/institutions",
        method: "GET",
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _institutions = jsonDecode(response.body);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching institutions: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddInstitutionDialog() {
    final nameController = TextEditingController();
    final shortNameController = TextEditingController();
    final domainController = TextEditingController();
    final headEmailController = TextEditingController();
    final headFirstNameController = TextEditingController();
    final headLastNameController = TextEditingController();
    final headPasswordController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Provision New Campus'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Institution Details",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name (e.g. Stanford University)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: shortNameController,
                    decoration: const InputDecoration(
                      labelText: 'Short Name (e.g. Stanford)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: domainController,
                    decoration: const InputDecoration(
                      labelText: 'Domain (e.g. stanford.edu)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    "Initial Community Head Details",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: headEmailController,
                    decoration: const InputDecoration(
                      labelText: 'Head Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: headFirstNameController,
                          decoration: const InputDecoration(
                            labelText: 'First Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: headLastNameController,
                          decoration: const InputDecoration(
                            labelText: 'Last Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: headPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Initial Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (nameController.text.isEmpty ||
                            domainController.text.isEmpty ||
                            headEmailController.text.isEmpty ||
                            headPasswordController.text.isEmpty) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please fill all required fields'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);
                        try {
                          final response = await _apiClient
                              .authenticatedRequest(
                                context,
                                "/api/admin/institutions",
                                method: "POST",
                                body: jsonEncode({
                                  "name": nameController.text.trim(),
                                  "short_name": shortNameController.text.trim(),
                                  "domain": domainController.text
                                      .trim()
                                      .toLowerCase(),
                                  "head_email": headEmailController.text.trim(),
                                  "head_first_name": headFirstNameController
                                      .text
                                      .trim(),
                                  "head_last_name": headLastNameController.text
                                      .trim(),
                                  "head_password": headPasswordController.text,
                                }),
                              );

                          if (!context.mounted) return;

                          if (response.statusCode == 201) {
                            Navigator.pop(ctx);
                            _fetchInstitutions();
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Institution created successfully!',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            throw Exception(
                              jsonDecode(response.body)['detail'] ??
                                  'Failed to create',
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceAll("Exception: ", ""),
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          setDialogState(() => isSubmitting = false);
                        }
                      },
                child: isSubmitting
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

  void _showEditStorageLimitDialog(Map<String, dynamic> inst) {
    final currentLimitMb = (inst['default_storage_limit'] / (1024 * 1024))
        .round()
        .toString();
    final controller = TextEditingController(text: currentLimitMb);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Set Default Storage Limit"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Set the default storage limit (in MB) for all students in ${inst['short_name']}.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Limit in MB',
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
              final val = int.tryParse(controller.text.trim());
              if (val == null) return;

              try {
                final response = await _apiClient.authenticatedRequest(
                  context,
                  "/api/admin/institutions/${inst['id']}/storage-limit",
                  method: "PATCH",
                  body: jsonEncode({"default_storage_limit_mb": val}),
                );
                if (!mounted) return;
                if (response.statusCode == 200) {
                  _fetchInstitutions();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Storage limit updated'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              } catch (e) {
                // Ignore silent failure
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Institutions')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'institute_fab',
        onPressed: _showAddInstitutionDialog,
        icon: const Icon(Icons.add_business),
        label: const Text("New Campus"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _institutions.isEmpty
          ? const Center(child: Text("No institutions registered yet."))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _institutions.length,
              itemBuilder: (context, index) {
                final inst = _institutions[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      child: Text(inst['short_name'][0]),
                    ),
                    title: Text(
                      inst['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('@${inst['domain']}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'storage') _showEditStorageLimitDialog(inst);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'storage',
                          child: Text('Edit Default Storage Limit'),
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
