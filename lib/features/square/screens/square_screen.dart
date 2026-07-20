import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/chat/screens/chat_screen.dart';

class SquareScreen extends StatefulWidget {
  const SquareScreen({super.key});

  @override
  State<SquareScreen> createState() => _SquareScreenState();
}

class _SquareScreenState extends State<SquareScreen> {
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<dynamic> _posts = [];

  String? _selectedCategory;

  final Map<String, String> _categories = {
    "📢 Notices": "NOTICE",
    "🎉 Events": "EVENT",
    "🔍 Lost & Found": "LOST_FOUND",
    "🚗 Ride Pool": "RIDE_POOL",
    "🛋️ Roommate": "ROOMMATE",
  };

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchPosts();
  }

  Future<void> _fetchPosts() async {
    setState(() => _isLoading = true);

    String endpoint = "/api/square/notices";
    if (_selectedCategory != null) {
      endpoint += "?category=$_selectedCategory";
    }

    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        endpoint,
        method: "GET",
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _posts = jsonDecode(response.body);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching square posts: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        "/api/square/notices/$postId",
        method: "DELETE",
      );

      if (response.statusCode == 200) {
        _fetchPosts();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post deleted.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error deleting post: $e");
    }
  }

  Future<void> _openResource(String urlString) async {
    Uri url = Uri.parse(urlString);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Error opening file: $e");
    }
  }

  String _formatShortTime(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) return '${difference.inDays}d';
      if (difference.inHours > 0) return '${difference.inHours}h';
      if (difference.inMinutes > 0) return '${difference.inMinutes}m';
      return 'now';
    } catch (_) {
      return '';
    }
  }

  List<Map<String, dynamic>> _flattenComments(
    List<dynamic> comments, {
    int depth = 0,
  }) {
    List<Map<String, dynamic>> result = [];
    for (var comment in comments) {
      result.add({'comment': comment, 'depth': depth});
      if (comment['replies'] != null &&
          (comment['replies'] as List).isNotEmpty) {
        result.addAll(_flattenComments(comment['replies'], depth: depth + 1));
      }
    }
    return result;
  }

  void _showCommentsSheet(Map<String, dynamic> post) {
    final commentController = TextEditingController();
    final FocusNode commentFocusNode = FocusNode();
    bool isSubmitting = false;
    bool isInputEmpty = true;

    String? replyingToId;
    String? replyingToName;

    final ScrollController listScrollController = ScrollController();

    final currentUser = context.read<CampusSquareAuth>().user;
    final currentUserId = currentUser?['id'];
    final userRole = currentUser?['role'] ?? 'STUDENT';
    final isStaff = userRole == 'ADMIN' || userRole == 'COMMUNITY_HEAD';
    final theme = Theme.of(context);

    List<dynamic> mutableComments = List.from(
      (post['comments'] as List<dynamic>? ?? []).where(
        (c) => c['parent_id'] == null,
      ),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final flatComments = _flattenComments(mutableComments);

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.9,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            "${flatComments.length} Comments",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    Expanded(
                      child: flatComments.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "💬",
                                    style: TextStyle(fontSize: 48),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    "No comments yet",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Start the conversation.",
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: listScrollController,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              itemCount: flatComments.length,
                              itemBuilder: (context, index) {
                                final item = flatComments[index];
                                final c = item['comment'];
                                final depth = item['depth'] as int;

                                final isStaffComment =
                                    c['author']['role'] == 'ADMIN' ||
                                    c['author']['role'] == 'COMMUNITY_HEAD';
                                final isCommentOwner =
                                    c['author']['id'] == currentUserId;
                                final canDeleteComment =
                                    isCommentOwner || isStaff;

                                return InkWell(
                                  onLongPress: () {
                                    _showCommentActions(
                                      context,
                                      c,
                                      setModalState,
                                      post['id'],
                                    );
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: 16.0 + (depth * 32.0),
                                      right: 16.0,
                                      top: depth == 0 ? 12.0 : 6.0,
                                      bottom: depth == 0 ? 12.0 : 6.0,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: depth == 0 ? 18 : 14,
                                          backgroundColor: theme
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.1),
                                          child: Text(
                                            c['author']['first_name'][0]
                                                .toUpperCase(),
                                            style: TextStyle(
                                              fontSize: depth == 0 ? 14 : 12,
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      "${c['author']['first_name']} ${c['author']['last_name']}",
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (isStaffComment)
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                        left: 4,
                                                      ),
                                                      child: Icon(
                                                        Icons.verified,
                                                        color: Colors.blue,
                                                        size: 14,
                                                      ),
                                                    ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    _formatShortTime(
                                                      c['created_at'],
                                                    ),
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade500,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                c['text'],
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  height: 1.3,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  InkWell(
                                                    onTap: () {
                                                      setModalState(() {
                                                        replyingToId = c['id'];
                                                        replyingToName =
                                                            "${c['author']['first_name']} ${c['author']['last_name']}";
                                                      });
                                                      commentFocusNode
                                                          .requestFocus();
                                                    },
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.reply_rounded,
                                                          size: 14,
                                                          color: Colors
                                                              .grey
                                                              .shade600,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          "Reply",
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .grey
                                                                .shade600,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (canDeleteComment) ...[
                                                    const SizedBox(width: 16),
                                                    InkWell(
                                                      onTap: () =>
                                                          _confirmDeleteComment(
                                                            context,
                                                            c,
                                                            setModalState,
                                                            post['id'],
                                                          ),
                                                      child: Text(
                                                        "Delete",
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .red
                                                              .shade300,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    if (replyingToId != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              "Replying to ",
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              replyingToName ?? "",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () => setModalState(() {
                                replyingToId = null;
                                replyingToName = null;
                              }),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),

                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: commentController,
                                focusNode: commentFocusNode,
                                minLines: 1,
                                maxLines: 4,
                                onChanged: (val) => setModalState(
                                  () => isInputEmpty = val.trim().isEmpty,
                                ),
                                decoration: InputDecoration(
                                  hintText: replyingToId != null
                                      ? 'Write a reply...'
                                      : 'Write a comment...',
                                  filled: true,
                                  fillColor: Colors.grey.shade100,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : InkWell(
                                      onTap: isInputEmpty
                                          ? null
                                          : () async {
                                              setModalState(
                                                () => isSubmitting = true,
                                              );
                                              try {
                                                final response = await _apiClient
                                                    .authenticatedRequest(
                                                      context,
                                                      "/api/square/notices/${post['id']}/comments",
                                                      method: "POST",
                                                      body: jsonEncode({
                                                        "text":
                                                            commentController
                                                                .text
                                                                .trim(),
                                                        "parent_id":
                                                            replyingToId,
                                                      }),
                                                    );
                                                if (response.statusCode ==
                                                    201) {
                                                  await _fetchPosts();
                                                  final updatedPost = _posts
                                                      .firstWhere(
                                                        (p) =>
                                                            p['id'] ==
                                                            post['id'],
                                                        orElse: () => post,
                                                      );

                                                  final bool wasReply =
                                                      replyingToId != null;

                                                  setModalState(() {
                                                    mutableComments = List.from(
                                                      (updatedPost['comments']
                                                                  as List<
                                                                    dynamic
                                                                  >? ??
                                                              [])
                                                          .where(
                                                            (c) =>
                                                                c['parent_id'] ==
                                                                null,
                                                          ),
                                                    );
                                                    replyingToId = null;
                                                    replyingToName = null;
                                                    commentController.clear();
                                                    isInputEmpty = true;
                                                  });

                                                  if (!wasReply) {
                                                    Future.delayed(
                                                      const Duration(
                                                        milliseconds: 100,
                                                      ),
                                                      () {
                                                        if (listScrollController
                                                            .hasClients) {
                                                          listScrollController
                                                              .animateTo(
                                                                0.0,
                                                                duration:
                                                                    const Duration(
                                                                      milliseconds:
                                                                          300,
                                                                    ),
                                                                curve: Curves
                                                                    .easeOut,
                                                              );
                                                        }
                                                      },
                                                    );
                                                  }
                                                }
                                              } catch (e) {
                                                debugPrint("Comment error: $e");
                                              } finally {
                                                setModalState(
                                                  () => isSubmitting = false,
                                                );
                                              }
                                            },
                                      borderRadius: BorderRadius.circular(20),
                                      child: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: isInputEmpty
                                            ? Colors.grey.shade300
                                            : theme.colorScheme.primary,
                                        child: const Icon(
                                          Icons.arrow_upward,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
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

  void _showCommentActions(
    BuildContext context,
    dynamic c,
    StateSetter setModalState,
    String postId,
  ) {
    final currentUser = context.read<CampusSquareAuth>().user;
    final userRole = currentUser?['role'] ?? 'STUDENT';
    final isStaff = userRole == 'ADMIN' || userRole == 'COMMUNITY_HEAD';
    final canDelete = c['author']['id'] == currentUser?['id'] || isStaff;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (actCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: c['text']));
                  Navigator.pop(actCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Comment copied to clipboard'),
                    ),
                  );
                },
              ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete Comment',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(actCtx);
                    _confirmDeleteComment(context, c, setModalState, postId);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteComment(
    BuildContext context,
    dynamic c,
    StateSetter setModalState,
    String postId,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text(
          'Are you sure you want to delete this comment? This will also remove any replies attached to it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                final response = await _apiClient.authenticatedRequest(
                  context,
                  "/api/square/comments/${c['id']}",
                  method: "DELETE",
                );

                if (response.statusCode == 200) {
                  await _fetchPosts();
                  final updatedPost = _posts.firstWhere(
                    (p) => p['id'] == postId,
                  );
                  setModalState(() {});
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _showCommentsSheet(updatedPost);
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to delete comment'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                debugPrint("Delete comment error: $e");
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCreatePostSheet() {
    final userRole =
        context.read<CampusSquareAuth>().user?['role'] ?? 'STUDENT';
    final isStaff = userRole == 'ADMIN' || userRole == 'COMMUNITY_HEAD';

    final availableCategories = isStaff
        ? _categories.values.toList()
        : ["LOST_FOUND", "RIDE_POOL", "ROOMMATE"];

    String selectedType = availableCategories.first;
    bool isUrgent = false;
    int urgentHours = 48;
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    PlatformFile? selectedFile;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Create Post',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: availableCategories.map((type) {
                        final uiLabel = _categories.entries
                            .firstWhere((e) => e.value == type)
                            .key;
                        return DropdownMenuItem(
                          value: type,
                          child: Text(uiLabel),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setModalState(() => selectedType = val!),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: bodyController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Details',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        selectedFile != null
                            ? selectedFile!.name
                            : 'Attach Image or PDF',
                      ),
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.any,
                        );
                        if (result != null) {
                          setModalState(
                            () => selectedFile = result.files.first,
                          );
                        }
                      },
                    ),

                    if (isStaff &&
                        (selectedType == 'NOTICE' ||
                            selectedType == 'EVENT')) ...[
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text(
                          'Mark as Urgent',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        value: isUrgent,
                        activeThumbColor: Colors.red,
                        onChanged: (val) => setModalState(() => isUrgent = val),
                      ),
                      if (isUrgent)
                        DropdownButtonFormField<int>(
                          initialValue: urgentHours,
                          decoration: const InputDecoration(
                            labelText: 'Urgent Duration',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 24,
                              child: Text('24 Hours'),
                            ),
                            DropdownMenuItem(
                              value: 48,
                              child: Text('48 Hours'),
                            ),
                            DropdownMenuItem(value: 168, child: Text('1 Week')),
                          ],
                          onChanged: (val) =>
                              setModalState(() => urgentHours = val!),
                        ),
                    ],

                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              if (titleController.text.trim().isEmpty ||
                                  bodyController.text.trim().isEmpty) {
                                return;
                              }

                              setModalState(() => isSubmitting = true);
                              try {
                                String? urgentUntilStr;
                                if (isUrgent) {
                                  urgentUntilStr = DateTime.now()
                                      .add(Duration(hours: urgentHours))
                                      .toUtc()
                                      .toIso8601String();
                                }

                                String? imageUrl;
                                String? fileUrl;

                                if (selectedFile != null &&
                                    selectedFile!.path != null) {
                                  final uploadRes = await _apiClient
                                      .authenticatedMultipartRequest(
                                        context,
                                        "/api/vault/upload-file",
                                        filePath: selectedFile!.path!,
                                        fileField: "file",
                                      );
                                  if (uploadRes.statusCode == 200) {
                                    final url = jsonDecode(
                                      uploadRes.body,
                                    )['file_url'];
                                    final ext =
                                        selectedFile!.extension
                                            ?.toLowerCase() ??
                                        '';
                                    if ([
                                      'png',
                                      'jpg',
                                      'jpeg',
                                      'gif',
                                      'webp',
                                    ].contains(ext)) {
                                      imageUrl = url;
                                    } else {
                                      fileUrl = url;
                                    }
                                  } else {
                                    throw Exception(
                                      "Failed to upload attachment",
                                    );
                                  }
                                }

                                if (!context.mounted) return;

                                final response = await _apiClient
                                    .authenticatedRequest(
                                      context,
                                      "/api/square/notices",
                                      method: "POST",
                                      body: jsonEncode({
                                        "title": titleController.text.trim(),
                                        "body": bodyController.text.trim(),
                                        "category": selectedType,
                                        "urgent_until": urgentUntilStr,
                                        "image_url": imageUrl,
                                        "file_url": fileUrl,
                                      }),
                                    );

                                if (!context.mounted) return;

                                if (response.statusCode == 201) {
                                  Navigator.pop(ctx);
                                  _fetchPosts();
                                } else if (response.statusCode == 422) {
                                  final errorData = jsonDecode(response.body);
                                  if (errorData['detail'] is List) {
                                    final List errors = errorData['detail'];
                                    String errorMsg = errors
                                        .map(
                                          (e) =>
                                              "${e['loc'].last}: ${e['msg']}",
                                        )
                                        .join("\n");
                                    throw Exception(errorMsg);
                                  }
                                  throw Exception("Validation Error");
                                } else {
                                  final errorData = jsonDecode(response.body);
                                  throw Exception(
                                    errorData['detail'] ?? "Failed to post",
                                  );
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.toString().replaceAll(
                                        "Exception: ",
                                        "",
                                      ),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                setModalState(() => isSubmitting = false);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Publish',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) return '${difference.inDays}d ago';
      if (difference.inHours > 0) return '${difference.inHours}h ago';
      if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = context.read<CampusSquareAuth>().user;
    final currentUserId = currentUser?['id'];
    final userRole = currentUser?['role'] ?? 'STUDENT';
    final isStaff = userRole == 'ADMIN' || userRole == 'COMMUNITY_HEAD';

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePostSheet,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _selectedCategory == null,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = null);
                        _fetchPosts();
                      }
                    },
                  ),
                ),
                ..._categories.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(entry.key),
                      selected: _selectedCategory == entry.value,
                      onSelected: (selected) {
                        setState(
                          () =>
                              _selectedCategory = selected ? entry.value : null,
                        );
                        _fetchPosts();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _posts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.feed_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No posts found in this category.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchPosts,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _posts.length,
                      itemBuilder: (context, index) {
                        final post = _posts[index];
                        final author = post['author'];
                        bool isUrgent = false;
                        if (post['urgent_until'] != null) {
                          final expireDate = DateTime.parse(
                            post['urgent_until'],
                          ).toLocal();
                          isUrgent = DateTime.now().isBefore(expireDate);
                        }

                        final isOwner = author['id'] == currentUserId;
                        final canDelete = isOwner || isStaff;
                        final isPeerPost = [
                          "LOST_FOUND",
                          "RIDE_POOL",
                          "ROOMMATE",
                        ].contains(post['category']);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: isUrgent ? 4 : 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: isUrgent
                                ? const BorderSide(color: Colors.red, width: 2)
                                : BorderSide.none,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: theme.colorScheme.primary
                                          .withValues(alpha: 0.1),
                                      child: Text(
                                        author['first_name'][0].toUpperCase(),
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  '${author['first_name']} ${author['last_name']}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (author['role'] == 'ADMIN' ||
                                                  author['role'] ==
                                                      'COMMUNITY_HEAD') ...[
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.verified,
                                                  color: Colors.blue,
                                                  size: 16,
                                                ),
                                              ],
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              Text(
                                                author['role'] ==
                                                        'COMMUNITY_HEAD'
                                                    ? 'Staff'
                                                    : author['role'],
                                                style: TextStyle(
                                                  color:
                                                      author['role'] ==
                                                          'STUDENT'
                                                      ? Colors.grey
                                                      : Colors.green.shade700,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const Text(
                                                ' • ',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              Text(
                                                _formatTime(post['created_at']),
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (canDelete)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                          color: Colors.grey,
                                        ),
                                        onPressed: () =>
                                            _deletePost(post['id']),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                if (isUrgent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          size: 16,
                                          color: Colors.red.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'URGENT NOTICE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Text(
                                  post['title'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  post['body'],
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.4,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (post['image_url'] != null) ...[
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      post['image_url'],
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ],
                                if (post['file_url'] != null) ...[
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.picture_as_pdf,
                                      color: Colors.red,
                                    ),
                                    label: const Text('Open Attachment'),
                                    onPressed: () =>
                                        _openResource(post['file_url']),
                                  ),
                                ],
                                const SizedBox(height: 16),

                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (isPeerPost)
                                      ElevatedButton.icon(
                                        icon: const Icon(
                                          Icons.chat_bubble_outline,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'Message ${author['first_name']}',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: theme
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.1),
                                          foregroundColor:
                                              theme.colorScheme.primary,
                                          elevation: 0,
                                        ),
                                        onPressed: () async {
                                          try {
                                            final response = await _apiClient
                                                .authenticatedRequest(
                                                  context,
                                                  "/api/chat/dm/${author['id']}",
                                                  method: "POST",
                                                );

                                            if (!context.mounted) return;

                                            if (response.statusCode == 200) {
                                              final conv = jsonDecode(
                                                response.body,
                                              );
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => ChatScreen(
                                                    conversationId: conv['id'],
                                                    chatTitle:
                                                        '${author['first_name']} ${author['last_name']}',
                                                  ),
                                                ),
                                              );
                                            } else {
                                              final error = jsonDecode(
                                                response.body,
                                              );
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    error['detail'] ??
                                                        "Could not start chat",
                                                  ),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            debugPrint("Chat error: $e");
                                          }
                                        },
                                      )
                                    else
                                      TextButton.icon(
                                        icon: const Icon(
                                          Icons.comment_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'Comments (${post['comments']?.length ?? 0})',
                                        ),
                                        onPressed: () =>
                                            _showCommentsSheet(post),
                                      ),

                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _categories.entries
                                            .firstWhere(
                                              (e) =>
                                                  e.value == post['category'],
                                              orElse: () =>
                                                  const MapEntry("", ""),
                                            )
                                            .key,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.blueGrey,
                                          fontWeight: FontWeight.w500,
                                        ),
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
                  ),
          ),
        ],
      ),
    );
  }
}
