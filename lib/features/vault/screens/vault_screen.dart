import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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
  Set<String> _savedResourceIds = {};

  String? _selectedDeptId;

  String? _filterType;
  int? _filterSemester;
  String _sortBy = "upvotes"; // "upvotes" or "newest"

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

      if (!mounted) return;

      final savedResponse = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/saved-resource-ids",
        method: "GET",
      );
      if (savedResponse.statusCode == 200) {
        final List<dynamic> savedIds = jsonDecode(savedResponse.body);
        _savedResourceIds = savedIds.map((e) => e.toString()).toSet();
      }

      await _fetchResources();
    } catch (e) {
      debugPrint("Vault fetch error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchResources() async {
    List<String> queryParams = [];

    if (_selectedDeptId != null) {
      queryParams.add("department_id=$_selectedDeptId");
    }
    if (_filterSemester != null) queryParams.add("semester=$_filterSemester");
    if (_filterType != null) queryParams.add("resource_type=$_filterType");
    queryParams.add("sort_by=$_sortBy");

    String query = queryParams.isNotEmpty ? "?${queryParams.join('&')}" : "";

    try {
      final resResponse = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/resources$query",
        method: "GET",
      );

      if (resResponse.statusCode == 200) {
        if (mounted) {
          setState(() {
            _resources = jsonDecode(resResponse.body);
          });
        }
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
        if (mounted) {
          context.read<CampusSquareAuth>().refreshProfile();
        }
      }
    } catch (e) {
      debugPrint("Voting error: $e");
    }
  }

  Future<void> _toggleSaveResource(String resourceId) async {
    final isSaved = _savedResourceIds.contains(resourceId);
    setState(() {
      if (isSaved) {
        _savedResourceIds.remove(resourceId);
      } else {
        _savedResourceIds.add(resourceId);
      }
    });

    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/resources/$resourceId/save",
        method: "POST",
      );

      if (response.statusCode != 200) {
        setState(() {
          if (isSaved) {
            _savedResourceIds.add(resourceId);
          } else {
            _savedResourceIds.remove(resourceId);
          }
        });
      }
    } catch (e) {
      debugPrint("Toggle save error: $e");
      setState(() {
        if (isSaved) {
          _savedResourceIds.add(resourceId);
        } else {
          _savedResourceIds.remove(resourceId);
        }
      });
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

  void _handlePreview(Map<String, dynamic> item) {
    final String urlString = item["file_url"] ?? "";
    final String lowerUrl = urlString.toLowerCase();

    if (lowerUrl.endsWith(".png") ||
        lowerUrl.endsWith(".jpg") ||
        lowerUrl.endsWith(".jpeg") ||
        lowerUrl.endsWith(".gif")) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            item["title"],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    urlString,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) =>
                        const Text("Failed to load image preview."),
                  ),
                ),
              ),
              if (item["description"] != null) ...[
                const SizedBox(height: 12),
                Text(item["description"], style: const TextStyle(fontSize: 14)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openResource(urlString, inAppPreview: false);
              },
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open Externally'),
            ),
          ],
        ),
      );
    } else {
      _openResource(urlString, inAppPreview: true);
    }
  }

  Future<void> _openResource(
    String urlString, {
    bool inAppPreview = false,
  }) async {
    Uri url = Uri.parse(urlString);
    LaunchMode mode = LaunchMode.externalApplication;

    if (inAppPreview) {
      mode = LaunchMode.inAppBrowserView;
    }

    try {
      bool launched = await launchUrl(url, mode: mode);

      if (!launched) {
        launched = await launchUrl(url, mode: LaunchMode.platformDefault);
        if (!launched) {
          throw Exception("Could not launch $urlString");
        }
      }
    } catch (e) {
      debugPrint("Error opening file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Unable to open this file. Please check your browser.",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Sort & Filter',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Sort By',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'upvotes',
                          label: Text('Top Voted'),
                          icon: Icon(Icons.thumb_up_alt_outlined),
                        ),
                        ButtonSegment(
                          value: 'newest',
                          label: Text('Newest'),
                          icon: Icon(Icons.access_time),
                        ),
                      ],
                      selected: {_sortBy},
                      onSelectionChanged: (Set<String> newSelection) {
                        setModalState(() => _sortBy = newSelection.first);
                      },
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            initialValue: _filterSemester,
                            decoration: const InputDecoration(
                              labelText: 'Semester',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('All Semesters'),
                              ),
                              ..._semesters.map(
                                (sem) => DropdownMenuItem(
                                  value: sem,
                                  child: Text('Sem $sem'),
                                ),
                              ),
                            ],
                            onChanged: (val) =>
                                setModalState(() => _filterSemester = val),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _filterType,
                            decoration: const InputDecoration(
                              labelText: 'Type',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('All Types'),
                              ),
                              ..._resourceTypes.map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ),
                              ),
                            ],
                            onChanged: (val) =>
                                setModalState(() => _filterType = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setModalState(() {
                                _filterSemester = null;
                                _filterType = null;
                                _sortBy = 'upvotes';
                              });
                            },
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() => _isLoading = true);
                              _fetchResources().then(
                                (_) => setState(() => _isLoading = false),
                              );
                            },
                            child: const Text('Apply Filters'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
    final userRole = currentUser?['role'] ?? 'STUDENT';
    final currentUserId = currentUser?['id'];

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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                              _isLoading = true;
                            });
                            _fetchResources().then(
                              (_) => setState(() => _isLoading = false),
                            );
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

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.cardColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_resources.length} Resources Found',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
                TextButton.icon(
                  onPressed: _showFilterSheet,
                  icon: const Icon(Icons.filter_list, size: 18),
                  label: const Text("Sort & Filter"),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _resources.isEmpty
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
                          'No learning documents match your criteria.',
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchResources,
                    child: ListView.builder(
                      itemCount: _resources.length,
                      padding: const EdgeInsets.all(16),
                      itemBuilder: (context, index) {
                        final item = _resources[index];
                        final isOwner = item['uploader_id'] == currentUserId;
                        final isStaff =
                            userRole == 'COMMUNITY_HEAD' || userRole == 'ADMIN';
                        final canDelete = isOwner || isStaff;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 1,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _handlePreview(item),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item["title"],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (item["description"] != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            item["description"],
                                            style: const TextStyle(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Chip(
                                              label: Text(
                                                item["resource_type"],
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Sem ${item["semester"]}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GestureDetector(
                                            onTap: () => _voteResource(
                                              item["id"],
                                              "UPVOTE",
                                            ),
                                            child: Icon(
                                              Icons.keyboard_arrow_up,
                                              color: theme.colorScheme.primary,
                                              size: 28,
                                            ),
                                          ),
                                          Text(
                                            '${item["upvote_count"] - item["downvote_count"]}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => _voteResource(
                                              item["id"],
                                              "DOWNVOTE",
                                            ),
                                            child: const Icon(
                                              Icons.keyboard_arrow_down,
                                              color: Colors.red,
                                              size: 28,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: Icon(
                                          _savedResourceIds.contains(item["id"])
                                              ? Icons.bookmark
                                              : Icons.bookmark_border,
                                          color:
                                              _savedResourceIds.contains(
                                                item["id"],
                                              )
                                              ? theme.colorScheme.primary
                                              : Colors.grey,
                                        ),
                                        tooltip: "Save Resource",
                                        onPressed: () =>
                                            _toggleSaveResource(item["id"]),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.open_in_new),
                                        color: Colors.blueGrey,
                                        tooltip: "Open Externally",
                                        onPressed: () => _openResource(
                                          item["file_url"],
                                          inAppPreview: false,
                                        ),
                                      ),
                                      if (canDelete)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          color: Colors.grey,
                                          onPressed: () =>
                                              _confirmDeleteResource(
                                                item["id"],
                                              ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
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
        context.read<CampusSquareAuth>().refreshProfile();
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
