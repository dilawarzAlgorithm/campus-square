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
        _fetchSavedResources();
      }
    } catch (e) {
      debugPrint("Error unsaving resource: $e");
    }
  }

  void _handlePreview(Map<String, dynamic> item) {
    final String urlString = item["file_url"] ?? "";
    final String lowerUrl = urlString.toLowerCase();
    final bool isImage =
        lowerUrl.endsWith(".png") ||
        lowerUrl.endsWith(".jpg") ||
        lowerUrl.endsWith(".jpeg") ||
        lowerUrl.endsWith(".gif") ||
        lowerUrl.endsWith(".webp");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Resource Details"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item["title"],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Row(
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
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              if (item["description"] != null) ...[
                const SizedBox(height: 12),
                const Text(
                  "Description:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(item["description"], style: const TextStyle(fontSize: 14)),
              ],
              if (isImage) ...[
                const SizedBox(height: 16),
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
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openResource(urlString, inAppPreview: !isImage);
            },
            icon: Icon(
              isImage ? Icons.open_in_new : Icons.picture_as_pdf,
              size: 16,
            ),
            label: Text(isImage ? 'Open Externally' : 'View Document'),
          ),
        ],
      ),
    );
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item["title"],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                if (item["description"] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item["description"],
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
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
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.open_in_new,
                                  color: Colors.blueGrey,
                                ),
                                tooltip: "Open Externally",
                                onPressed: () => _openResource(
                                  item["file_url"],
                                  inAppPreview: false,
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.bookmark,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                tooltip: "Remove from Saved",
                                onPressed: () => _unsaveResource(item["id"]),
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
    );
  }
}
