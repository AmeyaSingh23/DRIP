import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../data/wardrobe_repository.dart';
import '../domain/clothing_item_draft.dart';
import 'wardrobe_change_notifier.dart';
import 'upload_screen.dart';
import 'widgets/wardrobe_search_bar.dart';
import 'widgets/wardrobe_filter_tabs.dart';
import 'widgets/wardrobe_hanger_refresh.dart';

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
      if (_items.isEmpty) _loading = true;
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

  Future<void> _archive(ClothingItemDraft item) async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[900]!.withOpacity(0.50)
                      : Colors.white.withOpacity(0.50),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Archive item?',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'This hides the item from your wardrobe while preserving saved outfit and calendar history.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.onSurface,
                            ),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.onSurface,
                              foregroundColor: Theme.of(context).brightness == Brightness.dark
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onPrimary,
                            ),
                            child: const Text('Archive'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await _repository.archive(itemId: item.id, token: widget.token);
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      elevation: 0,
      builder:
          (sheetContext) => ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[900]!.withOpacity(0.50)
                    : Colors.white.withOpacity(0.50),
                child: SafeArea(
                  child: Wrap(
                    children: [
                      ListTile(
                        leading: Icon(Icons.remove_circle_outline, color: Theme.of(context).colorScheme.onSurface),
                        title: Text('Archive item', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                        subtitle: Text('Preserves saved outfit and calendar history', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _archive(item);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(wardrobeRevisionProvider, (_, _) => _load());
    final items = _filteredItems;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.black.withOpacity(0.2) 
                      : Colors.white.withOpacity(0.3),
                ),
              ),
            ),
            title: Text(
              'Wardrobe',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              WardrobeSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: () => setState(() {}),
              ),
              IconButton(
                onPressed: _deleting
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
                icon: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60.0),
              child: WardrobeFilterTabs(
                categories: _categories,
                selectedCategory: _selectedCategory,
                onSelected: (category) {
                  _searchFocusNode.unfocus();
                  setState(() => _selectedCategory = category);
                },
              ),
            ),
          ),
        ],
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            WardrobeHangerRefreshControl(onRefresh: _load),
          if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(_error!)),
            )
          else if (_loading)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const ShimmerSkeleton(
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: 16,
                  ),
                  childCount: 6, // Show 6 skeleton placeholders
                ),
              ),
            )
          else if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No wardrobe items here yet. Add your first item.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.black.withOpacity(0.3) 
                                  : Colors.white.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white.withOpacity(0.1) 
                                    : Colors.white.withOpacity(0.5),
                                width: 1,
                              ),
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
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.itemName ?? item.category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    [
                                      item.color,
                                      item.pattern,
                                    ].whereType<String>().join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                        ),
                      ),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
