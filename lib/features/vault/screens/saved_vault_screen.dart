import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';

class SavedVaultScreen extends StatefulWidget {
  const SavedVaultScreen({super.key});

  @override
  State<SavedVaultScreen> createState() => _SavedVaultScreenState();
}

class _SavedVaultScreenState extends State<SavedVaultScreen> {
  late final ApiClient _apiClient;
  List<dynamic> _savedResources = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchSavedResources();
  }

  Future<void> _fetchSavedResources() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/saved-resources",
        method: "GET",
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _savedResources = jsonDecode(response.body);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching saved resources: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unsaveResource(String resourceId) async {
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/vault/resources/$resourceId/save",
        method: "POST",
      );
      if (response.statusCode == 200) {
        _fetchSavedResources(); // Refresh the list
      }
    } catch (e) {
      debugPrint("Error unsaving resource: $e");
    }
  }

  void _openResource(String urlString) async {
    Uri url = Uri.parse(urlString);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Error opening file: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Vault Items')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedResources.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'You have not saved any academic resources yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _savedResources.length,
              itemBuilder: (context, index) {
                final item = _savedResources[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(
                      item["title"],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          Chip(
                            label: Text(
                              item["resource_type"],
                              style: const TextStyle(fontSize: 10),
                            ),
                            visualDensity: VisualDensity.compact,
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
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.open_in_new,
                            color: Colors.blueGrey,
                          ),
                          onPressed: () => _openResource(item["file_url"]),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.bookmark,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () => _unsaveResource(item["id"]),
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
