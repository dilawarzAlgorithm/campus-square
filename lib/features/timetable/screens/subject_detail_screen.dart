import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class SubjectDetailScreen extends StatefulWidget {
  final Map<String, dynamic> subject;
  const SubjectDetailScreen({super.key, required this.subject});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<dynamic> _records = [];

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiClient.authenticatedRequest(
        context,
        "/api/timetable/attendance/subject/${widget.subject['id']}",
        method: "GET",
      );
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _records = jsonDecode(res.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRecord(String recordId) async {
    try {
      final res = await _apiClient.authenticatedRequest(
        context,
        "/api/timetable/attendance/$recordId",
        method: "DELETE",
      );
      if (res.statusCode == 200) {
        _fetchHistory();
      }
    } catch (_) {}
  }

  Future<void> _updateRecord(String eventId, String date, String status) async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiClient.authenticatedRequest(
        context,
        "/api/timetable/attendance",
        method: "POST",
        body: jsonEncode({"event_id": eventId, "date": date, "status": status}),
      );
      if (res.statusCode == 200) {
        _fetchHistory();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.subject['name']} History")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? const Center(
              child: Text(
                "No attendance records found.",
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final r = _records[index];
                Color statusColor = Colors.grey;
                if (r['status'] == 'ATTENDED') statusColor = Colors.green;
                if (r['status'] == 'MISSED') statusColor = Colors.red;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      r['event_title'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text("${r['date']} • ${r['event_type']}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          r['status'],
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.edit_calendar,
                            color: Colors.blueGrey,
                          ),
                          tooltip: "Change Attendance",
                          onSelected: (val) {
                            if (val == 'DELETE') {
                              _deleteRecord(r['id']);
                            } else {
                              _updateRecord(r['event_id'], r['date'], val);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'ATTENDED',
                              child: Text('Mark Attended'),
                            ),
                            const PopupMenuItem(
                              value: 'MISSED',
                              child: Text('Mark Missed'),
                            ),
                            const PopupMenuItem(
                              value: 'CANCELLED',
                              child: Text('Mark Cancelled'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'DELETE',
                              child: Text(
                                'Delete Record',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
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
