import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../../../core/widgets/hanger_loading_indicator.dart';
import '../../outfits/data/outfit_repository.dart';
import '../../outfits/domain/saved_outfit.dart';
import '../../wardrobe/data/wardrobe_repository.dart';
import '../../wardrobe/domain/clothing_item_draft.dart';
import '../../wardrobe/presentation/widgets/wardrobe_hanger_refresh.dart';
import '../../wardrobe/presentation/wardrobe_change_notifier.dart';
import 'providers/profile_stats_provider.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({ super.key});
  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  final _wardrobe = WardrobeRepository(ApiClient());
  final _outfits = OutfitRepository(ApiClient());
  List<ClothingItemDraft> _items = const [];
  List<SavedOutfit> _outfitsList = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_items.isEmpty && _outfitsList.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _wardrobe.list( archived: true),
        _outfits.list( archived: true),
      ]);
      if (mounted) {
        setState(() {
          _items = results[0] as List<ClothingItemDraft>;
          _outfitsList = results[1] as List<SavedOutfit>;
        });
      }
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(DioException error) {
    final data = error.response?.data;
    return data is Map && data['detail'] is String
        ? data['detail'] as String
        : 'Could not load Archive.';
  }

  Future<void> _restoreItem(ClothingItemDraft item) async {
    final original = [..._items];
    setState(() {
      _items = _items.where((i) => i.id != item.id).toList();
    });
    ref.read(profileStatsProvider.notifier).incrementItems();

    try {
      await _wardrobe.restore(itemId: item.id);
      if (mounted) {
        ref.read(wardrobeRevisionProvider.notifier).notifyChanged();
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() => _items = original);
        ref.read(profileStatsProvider.notifier).decrementItems();
        _show(_message(error));
      }
    }
  }

  Future<void> _restoreOutfit(SavedOutfit outfit) async {
    final original = [..._outfitsList];
    setState(() {
      _outfitsList = _outfitsList.where((o) => o.id != outfit.id).toList();
    });
    ref.read(profileStatsProvider.notifier).incrementOutfits();

    try {
      await _outfits.restore(outfitId: outfit.id);
      if (mounted) {
        ref.read(outfitRevisionProvider.notifier).notifyChanged();
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() => _outfitsList = original);
        ref.read(profileStatsProvider.notifier).decrementOutfits();
        _show(_message(error));
      }
    }
  }

  Future<void> _deleteItem(ClothingItemDraft item) async {
    final confirmed = await _confirm(
      'Delete item forever?',
      'This permanently deletes the item. It cannot be undone.',
    );
    if (confirmed != true) return;
    final original = [..._items];
    setState(() {
      _items = _items.where((i) => i.id != item.id).toList();
    });

    try {
      await _wardrobe.permanentlyErase(itemId: item.id);
      if (mounted) {
        ref.read(wardrobeRevisionProvider.notifier).notifyChanged();
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() => _items = original);
        _show(_message(error));
      }
    }
  }

  Future<void> _deleteOutfit(SavedOutfit outfit) async {
    final confirmed = await _confirm(
      'Delete outfit forever?',
      'This permanently deletes the outfit. It cannot be undone.',
    );
    if (confirmed != true) return;
    final original = [..._outfitsList];
    setState(() {
      _outfitsList = _outfitsList.where((o) => o.id != outfit.id).toList();
    });

    try {
      await _outfits.permanentlyDelete(outfitId: outfit.id);
      if (mounted) {
        ref.read(outfitRevisionProvider.notifier).notifyChanged();
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() => _outfitsList = original);
        _show(_message(error));
      }
    }
  }

  Future<bool?> _confirm(String title, String content) => showDialog<bool>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]!.withOpacity(0.60)
                : Colors.white.withOpacity(0.60),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  content,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
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
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete forever'),
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

  void _show(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showItemActions(ClothingItemDraft item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      elevation: 0,
      builder: (sheetContext) => ClipRRect(
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
                    leading: const Icon(Icons.restore),
                    title: const Text('Restore'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _restoreItem(item);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Delete forever', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _deleteItem(item);
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

  void _showOutfitActions(SavedOutfit outfit) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      elevation: 0,
      builder: (sheetContext) => ClipRRect(
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
                    leading: const Icon(Icons.restore),
                    title: const Text('Restore'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _restoreOutfit(outfit);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Delete forever', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _deleteOutfit(outfit);
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
                    Container(
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.white.withOpacity(0.5),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Material(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.2)
                  : Colors.white.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: child,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF2A1B22) : const Color(0xFFFFF5F7),
        body: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: isDark ? 0.35 : 0.25,
                child: Image.asset(
                  isDark
                      ? 'assets/images/dark_leopard_texture.png'
                      : 'assets/images/leopard_texture.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            NestedScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  title: const Text('Archive'),
                  pinned: true,
                  floating: true,
                  backgroundColor: Colors.transparent,
                  flexibleSpace: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black.withOpacity(0.2)
                            : Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ),
                  bottom: TabBar(
                    dividerColor: Colors.transparent,
                    indicatorColor: Theme.of(context).colorScheme.onSurface,
                    labelColor: Theme.of(context).colorScheme.onSurface,
                    unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
                    tabs: const [Tab(text: 'Items'), Tab(text: 'Outfits')],
                  ),
                ),
              ],
              body: _loading
                  ? const Center(child: HangerLoadingIndicator())
                  : _error != null
                      ? Center(child: FilledButton(onPressed: _load, child: const Text('Try again')))
                      : TabBarView(children: [_itemsTab(), _outfitsTab()]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemsTab() => CustomScrollView(
    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    slivers: [
      WardrobeHangerRefreshControl(onRefresh: _load),
      if (_items.isEmpty)
        _buildEmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No Archived Items',
          subtitle: 'Items you archive from your wardrobe will appear here for safe keeping.',
        )
      else
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _items[index];
                return _buildGlassCard(
                  onTap: () => context.push('/wardrobe/items/${item.id}', ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 64, 
                          height: 72, 
                          child: CachedWardrobeImage(url: item.cloudinaryUrl),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.itemName ?? item.category,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.category,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                        onPressed: () => _showItemActions(item),
                      ),
                    ],
                  ),
                );
              },
              childCount: _items.length,
            ),
          ),
        ),
    ],
  );

  Widget _outfitsTab() => CustomScrollView(
    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    slivers: [
      WardrobeHangerRefreshControl(onRefresh: _load),
      if (_outfitsList.isEmpty)
        _buildEmptyState(
          icon: Icons.dry_cleaning_outlined,
          title: 'No Archived Outfits',
          subtitle: 'Outfits you archive will be kept here until restored or deleted.',
        )
      else
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final outfit = _outfitsList[index];
                return _buildGlassCard(
                  onTap: () => context.push('/outfits/${outfit.id}', ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.dry_cleaning_outlined, size: 28, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              outfit.name ?? 'Untitled outfit',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${outfit.items.length} items',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                        onPressed: () => _showOutfitActions(outfit),
                      ),
                    ],
                  ),
                );
              },
              childCount: _outfitsList.length,
            ),
          ),
        ),
    ],
  );
}


