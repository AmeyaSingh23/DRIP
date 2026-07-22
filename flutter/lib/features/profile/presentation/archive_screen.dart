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

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({required this.token, super.key});
  final String token;

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
        _wardrobe.list(token: widget.token, archived: true),
        _outfits.list(token: widget.token, archived: true),
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
    try {
      await _wardrobe.restore(itemId: item.id, token: widget.token);
      ref.read(wardrobeRevisionProvider.notifier).notifyChanged();
      await _load();
    } on DioException catch (error) { _show(_message(error)); }
  }

  Future<void> _restoreOutfit(SavedOutfit outfit) async {
    try {
      await _outfits.restore(token: widget.token, outfitId: outfit.id);
      ref.read(outfitRevisionProvider.notifier).notifyChanged();
      await _load();
    } on DioException catch (error) { _show(_message(error)); }
  }

  Future<void> _deleteItem(ClothingItemDraft item) async {
    final confirmed = await _confirm('Delete item forever?', 'This permanently deletes the item. It cannot be undone.');
    if (confirmed != true) return;
    try {
      await _wardrobe.permanentlyErase(itemId: item.id, token: widget.token);
      ref.read(wardrobeRevisionProvider.notifier).notifyChanged();
      await _load();
    } on DioException catch (error) { _show(_message(error)); }
  }

  Future<void> _deleteOutfit(SavedOutfit outfit) async {
    final confirmed = await _confirm('Delete outfit forever?', 'This permanently deletes the outfit. It cannot be undone.');
    if (confirmed != true) return;
    try {
      await _outfits.permanentlyDelete(token: widget.token, outfitId: outfit.id);
      ref.read(outfitRevisionProvider.notifier).notifyChanged();
      await _load();
    } on DioException catch (error) { _show(_message(error)); }
  }

  Future<bool?> _confirm(String title, String content) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title), content: Text(content), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Delete forever')),
      ],
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
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: NestedScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('Archive'),
            pinned: true,
            floating: true,
            backgroundColor: Colors.transparent,
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
    ),
  );

  Widget _itemsTab() => CustomScrollView(
    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    slivers: [
      WardrobeHangerRefreshControl(onRefresh: _load),
      if (_items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false, 
          child: Column(children: const [SizedBox(height: 140), Center(child: Text('No archived items.'))])
        )
      else
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _items[index];
                return _buildGlassCard(
                  onTap: () => context.push('/wardrobe/items/${item.id}', extra: widget.token),
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
        SliverFillRemaining(
          hasScrollBody: false, 
          child: Column(children: const [SizedBox(height: 140), Center(child: Text('No archived outfits.'))])
        )
      else
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final outfit = _outfitsList[index];
                return _buildGlassCard(
                  onTap: () => context.push('/outfits/${outfit.id}', extra: widget.token),
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
