import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../../outfits/data/outfit_repository.dart';
import '../../outfits/domain/saved_outfit.dart';
import '../../wardrobe/data/wardrobe_repository.dart';
import '../../wardrobe/domain/clothing_item_draft.dart';
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
      _loading = true;
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
      await _load();
    } on DioException catch (error) { _show(_message(error)); }
  }

  Future<void> _deleteItem(ClothingItemDraft item) async {
    final confirmed = await _confirm('Delete item forever?', 'This permanently deletes the item. It cannot be undone.');
    if (confirmed != true) return;
    try {
      await _wardrobe.permanentlyErase(itemId: item.id, token: widget.token);
      await _load();
    } on DioException catch (error) { _show(_message(error)); }
  }

  Future<void> _deleteOutfit(SavedOutfit outfit) async {
    final confirmed = await _confirm('Delete outfit forever?', 'This permanently deletes the outfit. It cannot be undone.');
    if (confirmed != true) return;
    try {
      await _outfits.permanentlyDelete(token: widget.token, outfitId: outfit.id);
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

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(title: const Text('Archive'), bottom: const TabBar(tabs: [Tab(text: 'Items'), Tab(text: 'Outfits')])),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: FilledButton(onPressed: _load, child: const Text('Try again')))
          : TabBarView(children: [_itemsTab(), _outfitsTab()]),
    ),
  );

  Widget _itemsTab() => RefreshIndicator(
    onRefresh: _load,
    child: _items.isEmpty ? ListView(children: const [SizedBox(height: 140), Center(child: Text('No archived items.'))]) : ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: ListTile(
            onTap: () => context.push('/wardrobe/items/${item.id}', extra: widget.token),
            leading: SizedBox(width: 56, height: 64, child: CachedWardrobeImage(url: item.cloudinaryUrl)),
            title: Text(item.itemName ?? item.category),
            subtitle: Text(item.category),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(onPressed: () => _restoreItem(item), child: const Text('Restore')),
              PopupMenuButton<String>(onSelected: (_) => _deleteItem(item), itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete forever'))]),
            ]),
          ),
        );
      },
    ),
  );

  Widget _outfitsTab() => RefreshIndicator(
    onRefresh: _load,
    child: _outfitsList.isEmpty ? ListView(children: const [SizedBox(height: 140), Center(child: Text('No archived outfits.'))]) : ListView.builder(
      itemCount: _outfitsList.length,
      itemBuilder: (context, index) {
        final outfit = _outfitsList[index];
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/outfits/${outfit.id}', extra: widget.token),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(outfit.name ?? 'Untitled outfit', style: Theme.of(context).textTheme.titleMedium)),
                  FilledButton(onPressed: () => _restoreOutfit(outfit), child: const Text('Restore')),
                  PopupMenuButton<String>(onSelected: (_) => _deleteOutfit(outfit), itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete forever'))]),
                ]),
                if (outfit.occasion != null) Text(outfit.occasion!, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: outfit.items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, itemIndex) => AspectRatio(
                      aspectRatio: .75,
                      child: CachedWardrobeImage(url: outfit.items[itemIndex].cloudinaryUrl),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    ),
  );
}
