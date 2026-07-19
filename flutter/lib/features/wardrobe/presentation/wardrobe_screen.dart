import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../data/wardrobe_repository.dart';
import '../domain/clothing_item_draft.dart';
import 'wardrobe_change_notifier.dart';
import 'upload_screen.dart';

class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({required this.email, required this.token, super.key});

  final String email;
  final String token;

  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
  static const _baseCategories = [
    'All',
    'Tops',
    'Bottoms',
    'Outerwear',
    'Shoes',
    'Dresses',
    'Accessories',
    'Uniform',
  ];

  final _repository = WardrobeRepository(ApiClient());
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<ClothingItemDraft> _items = const [];
  String _selectedCategory = 'All';
  bool _loading = true;
  bool _deleting = false;
  String? _error;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final requestEpoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repository.list(token: widget.token);
      if (mounted && requestEpoch == _loadEpoch) {
        setState(() {
          _items = items;
          // Custom tabs only exist while at least one active item uses them.
          // A deletion may remove the current tab, so return to a stable view.
          if (!_categories.contains(_selectedCategory)) {
            _selectedCategory = 'All';
          }
        });
      }
    } on DioException catch (error) {
      if (mounted && requestEpoch == _loadEpoch) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted && requestEpoch == _loadEpoch) {
        setState(() => _loading = false);
      }
    }
  }

  List<String> get _categories {
    final custom = <String>{};
    for (final item in _items) {
      final value = item.customCategory?.trim();
      if (item.category == 'Custom' && value != null && value.isNotEmpty) {
        custom.add(value);
      }
    }
    final sortedCustom = custom.toList()..sort();
    return [..._baseCategories, ...sortedCustom];
  }

  List<ClothingItemDraft> get _filteredItems {
    final search = _searchController.text.trim().toLowerCase();
    return _items.where((item) {
      final inCategory =
          _selectedCategory == 'All' ||
          item.category == _selectedCategory ||
          (item.category == 'Custom' &&
              item.customCategory == _selectedCategory);
      if (!inCategory) return false;
      if (search.isEmpty) return true;
      final terms =
          [
            item.itemName,
            item.category,
            item.customCategory,
            item.color,
            item.pattern,
            item.fabric,
            ...item.tags,
          ].whereType<String>().join(' ').toLowerCase();
      return terms.contains(search);
    }).toList();
  }

  String _messageFor(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return 'Could not update your wardrobe. Please try again.';
  }

  Future<void> _delete(
    ClothingItemDraft item, {
    required bool permanent,
  }) async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              permanent ? 'Permanently erase item?' : 'Remove from wardrobe?',
            ),
            content: Text(
              permanent
                  ? 'This removes the image from Cloudinary and cannot be undone.'
                  : 'This hides the item from your wardrobe while preserving saved outfit history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style:
                    permanent
                        ? FilledButton.styleFrom(backgroundColor: Colors.red)
                        : null,
                child: Text(permanent ? 'Erase permanently' : 'Remove'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      if (permanent) {
        await _repository.permanentlyErase(
          itemId: item.id,
          token: widget.token,
        );
      } else {
        await _repository.softDelete(itemId: item.id, token: widget.token);
      }
      ref.read(wardrobeRevisionProvider.notifier).notifyChanged();
      await _load();
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _showActions(ClothingItemDraft item) {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: const Text('Remove from wardrobe'),
                  subtitle: const Text('Preserves saved outfit history'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _delete(item, permanent: false);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Permanently erase',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _delete(item, permanent: true);
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(wardrobeRevisionProvider, (_, _) => _load());
    final items = _filteredItems;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wardrobe'),
        actions: [
          IconButton(
            onPressed:
                _deleting
                    ? null
                    : () async {
                      _searchFocusNode.unfocus();
                      await context.push(
                        '/wardrobe/upload',
                        extra: UploadRouteArgs(
                          token: widget.token,
                          email: widget.email,
                        ),
                      );
                      if (mounted) await _load();
                    },
            tooltip: 'Add wardrobe item',
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (_) => setState(() {}),
                onTapOutside: (_) => _searchFocusNode.unfocus(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search wardrobe',
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  return ChoiceChip(
                    label: Text(category),
                    selected: _selectedCategory == category,
                    onSelected: (_) {
                      _searchFocusNode.unfocus();
                      setState(() => _selectedCategory = category);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(child: Text(_error!))
                      : items.isEmpty
                      ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text(
                              'No wardrobe items here yet. Add your first item.',
                            ),
                          ),
                        ],
                      )
                      : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.72,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return InkWell(
                            onTap: () async {
                              _searchFocusNode.unfocus();
                              final changed = await context.push<bool>(
                                '/wardrobe/items/${item.id}',
                                extra: widget.token,
                              );
                              if (changed == true) await _load();
                            },
                            onLongPress:
                                _deleting
                                    ? null
                                    : () {
                                      _searchFocusNode.unfocus();
                                      _showActions(item);
                                    },
                            borderRadius: BorderRadius.circular(16),
                            child: Ink(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAFAF8),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: CachedWardrobeImage(
                                        url: item.cloudinaryUrl,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.itemName ?? item.category,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          [
                                            item.color,
                                            item.pattern,
                                          ].whereType<String>().join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
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
          ],
        ),
      ),
    );
  }
}
