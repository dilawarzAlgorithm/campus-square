import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_square/core/network/api_client.dart';
import 'package:campus_square/features/auth/controllers/auth_provider.dart';
import 'package:campus_square/features/bazaar/screens/product_detail_screen.dart';
import 'package:campus_square/features/bazaar/screens/sell_item_screen.dart';

class BazaarScreen extends StatefulWidget {
  const BazaarScreen({super.key});

  @override
  State<BazaarScreen> createState() => _BazaarScreenState();
}

class _BazaarScreenState extends State<BazaarScreen> {
  late final ApiClient _apiClient;
  bool _isLoading = true;
  List<dynamic> _products = [];
  String? _selectedCategory;

  final Map<String, String> _categories = {
    "Textbooks": "TEXTBOOK",
    "Electronics": "ELECTRONICS",
    "Furniture": "FURNITURE",
    "Clothing": "CLOTHING",
    "Stationery": "STATIONERY",
    "Other": "OTHER",
  };

  @override
  void initState() {
    super.initState();
    final auth = context.read<CampusSquareAuth>();
    _apiClient = ApiClient(baseUrl: auth.baseUrl);
    _loadCacheThenFetch();
  }

  Future<void> _loadCacheThenFetch() async {
    String endpoint = "/api/bazaar/products";
    if (_selectedCategory != null) {
      endpoint += "?category=$_selectedCategory";
    }

    final cachedString = await _apiClient.getCachedData(endpoint);
    if (cachedString != null && mounted) {
      setState(() {
        _products = jsonDecode(cachedString);
        _isLoading = false;
      });
    }

    _fetchProducts(endpoint);
  }

  Future<void> _fetchProducts(String endpoint) async {
    try {
      final response = await _apiClient.authenticatedRequest(
        context,
        endpoint,
        method: "GET",
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _products = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching bazaar products: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSavedItemCard(Map<String, dynamic> product, ThemeData theme) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ProductDetailScreen(product: product, apiClient: _apiClient),
          ),
        );
        if (result == true) {
          _loadCacheThenFetch();
        }
      },
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 100,
              height: double.infinity,
              child: product['image_url'] != null
                  ? CachedNetworkImage(
                      imageUrl: product['image_url'],
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      product['title'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹${product['price'].toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: double.infinity,
              width: 4,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product, ThemeData theme) {
    final conditionFormat = product['condition'].toString().replaceAll(
      '_',
      ' ',
    );

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ProductDetailScreen(product: product, apiClient: _apiClient),
          ),
        );
        if (result == true) {
          _loadCacheThenFetch();
        }
      },
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (product['image_url'] != null)
                    CachedNetworkImage(
                      imageUrl: product['image_url'],
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  else
                    Container(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        size: 48,
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        conditionFormat,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['title'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${product['price'].toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savedProducts = _products
        .where((p) => p['is_saved'] == true)
        .toList();
    final otherProducts = _products
        .where((p) => p['is_saved'] != true)
        .toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'bazaar_fab',
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SellItemScreen(apiClient: _apiClient),
            ),
          );
          if (result == true) {
            setState(() => _isLoading = true);
            _loadCacheThenFetch();
          }
        },
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.sell_outlined),
        label: const Text('Sell Item'),
      ),
      body: Column(
        children: [
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(
                bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              ),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: const Text('All Items'),
                    selected: _selectedCategory == null,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = null;
                          _isLoading = true;
                        });
                        _loadCacheThenFetch();
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
                        setState(() {
                          _selectedCategory = selected ? entry.value : null;
                          _isLoading = true;
                        });
                        _loadCacheThenFetch();
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
                : _products.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No items found.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadCacheThenFetch,
                    child: CustomScrollView(
                      slivers: [
                        if (savedProducts.isNotEmpty) ...[
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bookmark,
                                    color: Colors.blueGrey,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Saved Favorites',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 100,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: savedProducts.length,
                                itemBuilder: (context, index) {
                                  return _buildSavedItemCard(
                                    savedProducts[index],
                                    theme,
                                  );
                                },
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(top: 24, bottom: 8),
                              child: Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                            ),
                          ),
                        ],
                        if (otherProducts.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                savedProducts.isNotEmpty ? 16 : 24,
                                16,
                                16,
                              ),
                              child: Text(
                                savedProducts.isNotEmpty
                                    ? 'More Items'
                                    : 'Available Items',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    childAspectRatio: 0.75,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                return _buildProductCard(
                                  otherProducts[index],
                                  theme,
                                );
                              }, childCount: otherProducts.length),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 80)),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
