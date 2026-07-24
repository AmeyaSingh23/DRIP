import 'dart:async';
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
import 'providers/wardrobe_provider.dart';
import '../../profile/presentation/providers/profile_stats_provider.dart';

class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({required this.email,  super.key});

  final String email;
  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> with SingleTickerProviderStateMixin {
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

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;
  late final AnimationController _emptyIconController;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _emptyIconController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    Future.microtask(() {
      ref.read(wardrobeItemsProvider.notifier).load(refresh: true);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(wardrobeItemsProvider.notifier).load();
    }
  }

  @override
  void dispose() {
    _emptyIconController.dispose();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<String> _categories(List<ClothingItemDraft> items) {
    final custom = <String>{};
    for (final item in items) {
      final value = item.customCategory?.trim();
      if (item.category == 'Custom' && value != null && value.isNotEmpty) {
        custom.add(value);
      }
    }
    final sortedCustom = custom.toList()..sort();
    return [..._baseCategories, ...sortedCustom];
  }

  String _messageFor(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return 'Could not update your wardrobe. Please try again.';
  }

  Future<void> _archive(ClothingItemDraft item) async {
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
    try {
      ref.read(profileStatsProvider.notifier).decrementItems();
      await ref.read(wardrobeItemsProvider.notifier).archiveOptimistically(item);
    } catch (error) {
      if (mounted) {
        ref.read(profileStatsProvider.notifier).incrementItems(); // revert counter
        final errorMsg = error is DioException ? _messageFor(error) : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
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

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey[900]!.withOpacity(0.40)
                      : Colors.white.withOpacity(0.40),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.12)
                        : Colors.white.withOpacity(0.50),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.95, end: 1.05).animate(
                        CurvedAnimation(
                          parent: _emptyIconController,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Theme.of(context).colorScheme.primary.withOpacity(0.15),
                        ),
                        child: Icon(
                          icon,
                          size: 36,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        context.push(
                          '/wardrobe/upload',
                          extra: UploadRouteArgs(email: widget.email),
                        );
                      },
                      style: FilledButton.styleFrom(
                        foregroundColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add your first item'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wardrobeState = ref.watch(wardrobeItemsProvider);
    final items = wardrobeState.items;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
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
                onChanged: () {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                    ref.read(wardrobeItemsProvider.notifier).updateSearch(_searchController.text);
                  });
                },
              ),
              IconButton(
                onPressed: () async {
                  _searchFocusNode.unfocus();
                  await context.push(
                    '/wardrobe/upload',
                    extra: UploadRouteArgs(
                      email: widget.email,
                    ),
                  );
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
                categories: _categories(items),
                selectedCategory: wardrobeState.category,
                onSelected: (category) {
                  _searchFocusNode.unfocus();
                  ref.read(wardrobeItemsProvider.notifier).updateCategory(category);
                },
              ),
            ),
          ),
          WardrobeHangerRefreshControl(onRefresh: () => ref.read(wardrobeItemsProvider.notifier).load(refresh: true)),
          if (wardrobeState.error != null && items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(wardrobeState.error!)),
            )
          else if (wardrobeState.loading)
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
                  childCount: 6,
                ),
              ),
            )
          else if (items.isEmpty)
            _buildEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No wardrobe items here yet.',
              subtitle: 'Add your first item.',
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
                        await context.push<bool>(
                          '/wardrobe/items/${item.id}',
                        );
                      },
                      onLongPress: () {
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
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.white.withOpacity(0.15)
                                              : Colors.white.withOpacity(0.6),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.08),
                                            blurRadius: 6,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: CachedWardrobeImage(
                                          url: item.cloudinaryUrl,
                                        ),
                                      ),
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
          if (wardrobeState.loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
