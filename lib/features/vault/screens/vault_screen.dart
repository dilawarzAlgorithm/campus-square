import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

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
      if (mounted) setState(() => _isLoading = false);
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
      if (mounted) setState(() => _isLoading = false);
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
              } catch (_) {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _navigateToUploadScreen() async {
    if (_departments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please create a department first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UploadResourceScreen(
          apiClient: _apiClient,
          departments: _departments,
          resourceTypes: _resourceTypes,
          semesters: _semesters,
          initialDeptId: _selectedDeptId ?? _departments.first['id'],
        ),
      ),
    );

    if (result == true) {
      _fetchResources();
    }
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
        onPressed: _navigateToUploadScreen,
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

class UploadResourceScreen extends StatefulWidget {
  final ApiClient apiClient;
  final List<dynamic> departments;
  final List<String> resourceTypes;
  final List<int> semesters;
  final String initialDeptId;

  const UploadResourceScreen({
    super.key,
    required this.apiClient,
    required this.departments,
    required this.resourceTypes,
    required this.semesters,
    required this.initialDeptId,
  });

  @override
  State<UploadResourceScreen> createState() => _UploadResourceScreenState();
}

class _UploadResourceScreenState extends State<UploadResourceScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  PlatformFile? _selectedFile;
  bool _isPickingFile = false;
  bool _isUploading = false;

  late String _selectedType;
  late int _selectedSemester;
  late String _selectedDeptId;

  @override
  void initState() {
    super.initState();
    _selectedDeptId = widget.initialDeptId;
    _selectedType = widget.resourceTypes.isNotEmpty
        ? widget.resourceTypes.first
        : 'NOTE';
    _selectedSemester = widget.semesters.isNotEmpty
        ? widget.semesters.first
        : 1;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _isPickingFile = true);
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null) {
        setState(() => _selectedFile = result.files.first);
      }
    } catch (e) {
      debugPrint("File picker error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingFile = false);
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty ||
        _selectedFile == null ||
        _selectedFile!.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title and a valid file are required.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      final uploadResponse = await widget.apiClient
          .authenticatedMultipartRequest(
            context,
            "/api/vault/upload-file",
            filePath: _selectedFile!.path!,
            fileField: "file",
          );

      if (uploadResponse.statusCode != 200) {
        throw Exception("Failed to upload file to cloud storage.");
      }

      final uploadData = jsonDecode(uploadResponse.body);
      final fileUrl = uploadData['file_url'];

      final payload = {
        "title": _titleController.text.trim(),
        "description": _descController.text.trim().isNotEmpty
            ? _descController.text.trim()
            : null,
        "file_url": fileUrl,
        "resource_type": _selectedType,
        "semester": _selectedSemester,
        "department_id": _selectedDeptId,
      };

      if (!mounted) return;
      final response = await widget.apiClient.authenticatedRequest(
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
        Navigator.pop(context, true);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Upload failed');
      }
    } catch (e) {
      debugPrint("Upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<int> defaultSemesters = [1, 2, 3, 4, 5, 6, 7, 8];
    final List<String> defaultTypes = ['PYQ', 'NOTE', 'SYLLABUS', 'OTHER'];

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Resource')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedDeptId,
              decoration: const InputDecoration(
                labelText: 'Target Department',
                border: OutlineInputBorder(),
              ),
              items: widget.departments.map<DropdownMenuItem<String>>((dept) {
                return DropdownMenuItem<String>(
                  value: dept['id'],
                  child: Text("[${dept['code']}] ${dept['name']}"),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedDeptId = val!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g., Data Structures Midsem 2024',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            OutlinedButton.icon(
              icon: _isPickingFile
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file),
              label: Text(
                _selectedFile != null
                    ? _selectedFile!.name
                    : (_isPickingFile
                          ? 'Opening File Explorer...'
                          : 'Select PDF / Document'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(20),
                alignment: Alignment.centerLeft,
                side: BorderSide(
                  color: _selectedFile != null ? Colors.green : Colors.grey,
                ),
              ),
              onPressed: _isPickingFile || _isUploading ? null : _pickFile,
            ),

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Resource Type',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        (widget.resourceTypes.isNotEmpty
                                ? widget.resourceTypes
                                : defaultTypes)
                            .map((type) {
                              return DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              );
                            })
                            .toList(),
                    onChanged: (val) => setState(() => _selectedType = val!),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedSemester,
                    decoration: const InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        (widget.semesters.isNotEmpty
                                ? widget.semesters
                                : defaultSemesters)
                            .map((sem) {
                              return DropdownMenuItem(
                                value: sem,
                                child: Text('Sem $sem'),
                              );
                            })
                            .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedSemester = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _isUploading ? null : _submit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Upload File',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
