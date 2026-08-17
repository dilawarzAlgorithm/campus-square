import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/hubs/screens/create_hub_screen.dart';
import 'package:campus_square/features/hubs/screens/hub_dashboard_screen.dart';

class HubsScreen extends StatefulWidget {
  const HubsScreen({super.key});

  @override
  State<HubsScreen> createState() => _HubsScreenState();
}

class _HubsScreenState extends State<HubsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<dynamic> _clubs = [];
  List<dynamic> _studyGroups = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _fetchHubs();
  }

  Future<void> _fetchHubs() async {
    setState(() => _isLoading = true);
    try {
      final resClubs = await _apiClient.authenticatedRequest(
        context,
        "/api/hubs?type=CLUB",
        method: "GET",
      );
      if (!mounted) return;
      final resStudy = await _apiClient.authenticatedRequest(
        context,
        "/api/hubs?type=STUDY_GROUP",
        method: "GET",
      );

      if (mounted) {
        setState(() {
          if (resClubs.statusCode == 200) {
            _clubs = jsonDecode(resClubs.body);
            _clubs.sort(
              (a, b) =>
                  (b['is_saved'] ? 1 : 0).compareTo(a['is_saved'] ? 1 : 0),
            );
          }
          if (resStudy.statusCode == 200) {
            _studyGroups = jsonDecode(resStudy.body);
            _studyGroups.sort(
              (a, b) =>
                  (b['is_saved'] ? 1 : 0).compareTo(a['is_saved'] ? 1 : 0),
            );
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching hubs: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinHub(String hubId) async {
    try {
      final res = await _apiClient.authenticatedRequest(
        context,
        "/api/hubs/$hubId/join",
        method: "POST",
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(jsonDecode(res.body)['message']),
            backgroundColor: Colors.green,
          ),
        );
        _fetchHubs();
      }
    } catch (e) {
      //pass
    }
  }

  Future<void> _toggleSave(String hubId) async {
    try {
      await _apiClient.authenticatedRequest(
        context,
        "/api/hubs/$hubId/save",
        method: "POST",
      );
      _fetchHubs();
    } catch (e) {
      //pass
    }
  }

  Widget _buildHubList(List<dynamic> hubs) {
    if (hubs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchHubs,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.5,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hub_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text(
                  'No groups found.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchHubs,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: hubs.length,
        itemBuilder: (context, index) {
          final hub = hubs[index];
          final bool isMember = hub['is_member'] == true;
          final bool isPending = hub['is_pending'] == true;
          final bool isSaved = hub['is_saved'] == true;

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    backgroundImage: hub['avatar_url'] != null
                        ? CachedNetworkImageProvider(hub['avatar_url'])
                        : null,
                    child: hub['avatar_url'] == null
                        ? Icon(
                            Icons.groups,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                hub['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSaved)
                              const Padding(
                                padding: EdgeInsets.only(left: 4.0),
                                child: Icon(
                                  Icons.star,
                                  size: 14,
                                  color: Colors.amber,
                                ),
                              ),
                          ],
                        ),
                        if (hub['description'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              hub['description'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              hub['privacy'] == 'PUBLIC'
                                  ? Icons.public
                                  : Icons.lock,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "${hub['member_count']} members",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      isMember
                          ? ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                elevation: 0,
                              ),
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => HubDashboardScreen(
                                      hubId: hub['id'],
                                      hubName: hub['name'],
                                      isHubAdmin: hub['is_admin'] == true,
                                    ),
                                  ),
                                );

                                if (result == true) {
                                  _fetchHubs();
                                }
                              },
                              child: const Text("Open"),
                            )
                          : OutlinedButton(
                              onPressed: isPending
                                  ? null
                                  : () => _joinHub(hub['id']),
                              child: Text(isPending ? "Pending" : "Join"),
                            ),
                      IconButton(
                        icon: Icon(
                          isSaved ? Icons.star : Icons.star_border,
                          color: isSaved ? Colors.amber : Colors.grey,
                          size: 20,
                        ),
                        onPressed: () => _toggleSave(hub['id']),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Theme.of(context).cardColor,
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(text: "Clubs & Orgs"),
                Tab(text: "Study Groups"),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildHubList(_clubs),
                          _buildHubList(_studyGroups),
                        ],
                      ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton(
                    heroTag: 'hub_fab',
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CreateHubScreen(apiClient: _apiClient),
                        ),
                      );
                      if (result == true) _fetchHubs();
                    },
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
