import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/timetable/screens/subject_detail_screen.dart';

class SubjectsDashboardScreen extends StatefulWidget {
  const SubjectsDashboardScreen({super.key});

  @override
  State<SubjectsDashboardScreen> createState() =>
      _SubjectsDashboardScreenState();
}

class _SubjectsDashboardScreenState extends State<SubjectsDashboardScreen> {
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<dynamic> _subjects = [];

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchSubjects();
  }

  Future<void> _fetchSubjects() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/timetable/subjects",
        method: "GET",
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _subjects = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSubject(String subjectId) async {
    final bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Delete Subject?"),
            content: const Text(
              "Are you sure you want to delete this subject? All associated timetable events and attendance records will be permanently removed.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Delete"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() => _isLoading = true);
    if (!mounted) return;
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/timetable/subjects/$subjectId",
        method: "DELETE",
      );
      if (response.statusCode == 200 && mounted) {
        _fetchSubjects();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subject deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete subject.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddOrEditSubjectDialog({Map<String, dynamic>? existingSubject}) {
    final nameCtrl = TextEditingController(text: existingSubject?['name']);
    final codeCtrl = TextEditingController(text: existingSubject?['code']);
    final policyCtrl = TextEditingController(
      text: existingSubject?['attendance_policy']?.toString() ?? "75.0",
    );

    DateTime? startDate = existingSubject != null
        ? DateTime.parse(existingSubject['start_date'])
        : DateTime.now();
    DateTime? endDate = existingSubject != null
        ? DateTime.parse(existingSubject['end_date'])
        : DateTime.now().add(const Duration(days: 120));
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              existingSubject == null ? 'Add Subject' : 'Edit Subject',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Subject Name (e.g. Mathematics)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: "Code (Optional)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: policyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Required Attendance Policy %",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      startDate != null && endDate != null
                          ? "${startDate!.toLocal().toString().split(' ')[0]} to ${endDate!.toLocal().toString().split(' ')[0]}"
                          : "Select Semester Dates",
                    ),
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: startDate != null && endDate != null
                            ? DateTimeRange(start: startDate!, end: endDate!)
                            : null,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          startDate = picked.start;
                          endDate = picked.end;
                        });
                      }
                    },
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
                        if (nameCtrl.text.isEmpty ||
                            startDate == null ||
                            endDate == null) {
                          return;
                        }
                        setDialogState(() => isSaving = true);
                        try {
                          final isUpdate = existingSubject != null;
                          final endpoint = isUpdate
                              ? "/api/timetable/subjects/${existingSubject['id']}"
                              : "/api/timetable/subjects";
                          final method = isUpdate ? "PATCH" : "POST";

                          final response = await _apiClient
                              .authenticatedRequest(
                                context,
                                endpoint,
                                method: method,
                                body: jsonEncode({
                                  "name": nameCtrl.text.trim(),
                                  "code": codeCtrl.text.trim().isEmpty
                                      ? null
                                      : codeCtrl.text.trim(),
                                  "attendance_policy":
                                      double.tryParse(policyCtrl.text) ?? 75.0,
                                  "start_date": startDate!
                                      .toIso8601String()
                                      .split('T')[0],
                                  "end_date": endDate!.toIso8601String().split(
                                    'T',
                                  )[0],
                                }),
                              );
                          if (!context.mounted) return;
                          if (response.statusCode == 200 && mounted) {
                            Navigator.pop(ctx);
                            _fetchSubjects();
                          } else {
                            setDialogState(() => isSaving = false);
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
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Subjects Dashboard')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_sub_fab',
        onPressed: () => _showAddOrEditSubjectDialog(),
        icon: const Icon(Icons.add),
        label: const Text("Add Subject"),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subjects.isEmpty
          ? const Center(
              child: Text(
                "No subjects added. Click Add Subject to start.",
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _subjects.length,
              itemBuilder: (context, index) {
                final sub = _subjects[index];
                final double targetPct = sub['attendance_policy'] ?? 75.0;
                final int attended = sub['attended'] ?? 0;
                final int missed = sub['missed'] ?? 0;
                final int totalClasses = attended + missed;
                final double currentPct = totalClasses == 0
                    ? 100.0
                    : (attended / totalClasses) * 100;
                final bool isLow = currentPct < targetPct;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onTap: () async {
                      final res = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SubjectDetailScreen(subject: sub),
                        ),
                      );
                      if (res == true) _fetchSubjects();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sub['name'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    if (sub['code'] != null &&
                                        sub['code'].toString().isNotEmpty)
                                      Text(
                                        sub['code'],
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Chip(
                                label: Text(
                                  "Policy: ${targetPct.toStringAsFixed(0)}%",
                                ),
                                backgroundColor: theme
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.5),
                                side: BorderSide.none,
                                visualDensity: VisualDensity.compact,
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: Colors.blueGrey,
                                ),
                                onSelected: (val) {
                                  if (val == 'edit') {
                                    _showAddOrEditSubjectDialog(
                                      existingSubject: sub,
                                    );
                                  } else if (val == 'delete') {
                                    _deleteSubject(sub['id']);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit Subject'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Delete Subject',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildStatCol(
                                "Attended",
                                attended.toString(),
                                Colors.green,
                              ),
                              _buildStatCol(
                                "Missed",
                                missed.toString(),
                                Colors.red,
                              ),
                              _buildStatCol(
                                "Cancelled",
                                sub['cancelled'].toString(),
                                Colors.grey,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Current: ${currentPct.toStringAsFixed(1)}%",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isLow ? Colors.red : Colors.green,
                                ),
                              ),
                              Text(
                                "Can Miss: ${sub['can_miss']}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: currentPct / 100,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isLow ? Colors.red : Colors.green,
                            ),
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatCol(String label, String val, Color color) {
    return Column(
      children: [
        Text(
          val,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
