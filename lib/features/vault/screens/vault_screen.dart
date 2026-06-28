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
  List<String> _resourceTypes = [];
  List<int> _semesters = [];
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

      if (!mounted) return;

      final enumResponse = await _apiClient.authenticatedRequest(
        context,
        "/api/utils/get-enums",
        method: "GET",
      );

      if (deptResponse.statusCode == 200) {
        final decoded = jsonDecode(deptResponse.body);
        _departments = decoded;
        if (_departments.isNotEmpty) {
          _selectedDeptId = _departments.first["id"];
        }
      }

      if (enumResponse.statusCode == 200) {
        final decodedEnums = jsonDecode(enumResponse.body);

        final resTypeMap = decodedEnums["ResourceType"]["values"] as Map;
        _resourceTypes = resTypeMap.values.map((e) => e.toString()).toList();

        final semMap = decodedEnums["Semester"]["values"] as Map;
        _semesters = semMap.values.map((e) => int.parse(e.toString())).toList();
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

  Future<void> _uploadResource({
    required String title,
    required String description,
    required String fileUrl,
    required String resourceType,
    required int semester,
    required String departmentId,
  }) async {
    setState(() => _isLoading = true);
    try {
      final payload = {
        "title": title,
        "description": description.isNotEmpty ? description : null,
        "file_url": fileUrl,
        "resource_type": resourceType,
        "semester": semester,
        "department_id": departmentId,
      };

      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/resources",
        method: "POST",
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resource uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        if (_selectedDeptId == departmentId) {
          _fetchResources();
        }
      } else {
        final error = jsonDecode(response.body);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error['detail'] ?? 'Upload failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("Upload error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteResource(String resourceId) async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/resources/$resourceId",
        method: "DELETE",
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resource deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchResources();
      } else {
        final error = jsonDecode(response.body);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error['detail'] ?? 'Failed to delete resource.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("Delete error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _confirmDeleteResource(String resourceId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Resource'),
        content: const Text(
          'Are you sure you want to delete this resource? This action cannot be undone.',
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
            onPressed: () {
              Navigator.pop(ctx);
              _deleteResource(resourceId);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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

  void _showUploadResourceDialog() {
    if (_departments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please create a department first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final titleController = TextEditingController();
    final descController = TextEditingController();
    final fileUrlController = TextEditingController();

    final List<String> resourceTypes = _resourceTypes.isNotEmpty
        ? _resourceTypes
        : ['PYQ', 'NOTE', 'SYLLABUS', 'OTHER'];

    final List<int> semesters = _semesters.isNotEmpty
        ? _semesters
        : [1, 2, 3, 4, 5, 6, 7, 8];

    String selectedType = resourceTypes.first;
    int selectedSemester = semesters.first;
    String selectedDeptId = _selectedDeptId ?? _departments.first['id'];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Upload Resource'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedDeptId,
                      decoration: const InputDecoration(
                        labelText: 'Target Department',
                        border: OutlineInputBorder(),
                      ),
                      items: _departments.map<DropdownMenuItem<String>>((dept) {
                        return DropdownMenuItem<String>(
                          value: dept['id'],
                          child: Text("[${dept['code']}] ${dept['name']}"),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setStateDialog(() => selectedDeptId = val!),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'e.g., Data Structures Midsem 2024',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: fileUrlController,
                      decoration: const InputDecoration(
                        labelText: 'File URL / Cloud Drive Link',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Resource Type',
                        border: OutlineInputBorder(),
                      ),
                      items: resourceTypes.map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (val) =>
                          setStateDialog(() => selectedType = val!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: selectedSemester,
                      decoration: const InputDecoration(
                        labelText: 'Semester',
                        border: OutlineInputBorder(),
                      ),
                      items: semesters.map((sem) {
                        return DropdownMenuItem(
                          value: sem,
                          child: Text('Semester $sem'),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setStateDialog(() => selectedSemester = val!),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty ||
                        fileUrlController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Title and File URL are required.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx);

                    _uploadResource(
                      title: titleController.text.trim(),
                      description: descController.text.trim(),
                      fileUrl: fileUrlController.text.trim(),
                      resourceType: selectedType,
                      semester: selectedSemester,
                      departmentId: selectedDeptId,
                    );
                  },
                  child: const Text('Upload'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = context.read<CampusSquareAuth>().user;
    final currentUserId = currentUser?['id'];

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showUploadResourceDialog,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text("Upload"),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
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
                              if (item["uploader_id"] == currentUserId)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  color: Colors.grey,
                                  onPressed: () =>
                                      _confirmDeleteResource(item["id"]),
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
