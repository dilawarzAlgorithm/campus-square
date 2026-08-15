import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class CreateHubScreen extends StatefulWidget {
  final ApiClient apiClient;
  const CreateHubScreen({super.key, required this.apiClient});

  @override
  State<CreateHubScreen> createState() => _CreateHubScreenState();
}

class _CreateHubScreenState extends State<CreateHubScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _type = 'STUDY_GROUP';
  String _privacy = 'PUBLIC';
  bool _isSaving = false;

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please provide both a Hub Name and a Description."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final res = await widget.apiClient.authenticatedRequest(
        context,
        "/api/hubs",
        method: "POST",
        body: jsonEncode({
          "name": _nameCtrl.text.trim(),
          "description": _descCtrl.text.trim(),
          "type": _type,
          "privacy": _privacy,
        }),
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Hub created successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        final err = jsonDecode(res.body);
        throw Exception(err['detail'] ?? "Failed to create Hub.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.read<CampusSquareAuth>().user?['role'] ?? 'STUDENT';
    final isStaff = role == 'ADMIN' || role == 'COMMUNITY_HEAD';

    return Scaffold(
      appBar: AppBar(title: const Text("Create Hub")),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: "Hub Name *",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Description / Rules *",
              helperText: "A brief description is required.",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (isStaff)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: "Hub Type",
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'CLUB',
                    child: Text("Official Club or Organization"),
                  ),
                  DropdownMenuItem(
                    value: 'STUDY_GROUP',
                    child: Text("Student Study Group"),
                  ),
                ],
                onChanged: (val) => setState(() => _type = val!),
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: _privacy,
            decoration: const InputDecoration(
              labelText: "Privacy",
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'PUBLIC',
                child: Text("Public (Anyone can join instantly)"),
              ),
              DropdownMenuItem(
                value: 'PRIVATE',
                child: Text("Private (Admins must approve requests)"),
              ),
            ],
            onChanged: (val) => setState(() => _privacy = val!),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: _isSaving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    "Create Hub",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ],
      ),
    );
  }
}
