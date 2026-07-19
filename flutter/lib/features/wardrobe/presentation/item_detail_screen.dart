import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../data/wardrobe_repository.dart';
import '../domain/clothing_item_draft.dart';
import '../domain/clothing_item_usage.dart';
import 'wardrobe_item_editor_dialog.dart';
import 'wardrobe_change_notifier.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({
    required this.itemId,
    required this.token,
    super.key,
  });

  final String itemId;
  final String token;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  final _repository = WardrobeRepository(ApiClient());
  ClothingItemDraft? _item;
  ClothingItemUsage? _usage;
  String? _error;
  bool _loading = true;
  bool _mutating = false;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final requestEpoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.get(itemId: widget.itemId, token: widget.token),
        _repository.usage(itemId: widget.itemId, token: widget.token),
      ]);
      if (mounted && requestEpoch == _loadEpoch) {
        setState(() {
          _item = results[0] as ClothingItemDraft;
          _usage = results[1] as ClothingItemUsage;
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

  String _messageFor(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return 'Could not load this wardrobe item.';
  }

  Future<void> _edit() async {
    if (_mutating) return;
    final item = _item;
    if (item == null) return;
    final values = await showDialog<ItemEditValues>(
      context: context,
      builder:
          (context) =>
              WardrobeItemEditorDialog(item: item, title: 'Edit wardrobe item'),
    );
    if (values == null || !mounted) return;
    setState(() => _mutating = true);
    try {
      await _repository.update(
        draft: item,
        token: widget.token,
        itemName: values.itemName,
        category: values.category,
        customCategory: values.customCategory,
        color: values.color,
      );
      ref.read(wardrobeRevisionProvider.notifier).notifyChanged();
      await _load();
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _delete({required bool permanent}) async {
    if (_mutating) return;
    final item = _item;
    if (item == null) return;
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
                  : 'This hides the item while preserving saved outfit and calendar history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style:
                    permanent
                        ? FilledButton.styleFrom(backgroundColor: Colors.red)
                        : null,
                onPressed: () => Navigator.pop(context, true),
                child: Text(permanent ? 'Erase permanently' : 'Remove'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _mutating = true);
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
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  String _formattedDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)} ${date.year}';

  String _monthName(int month) =>
      const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][month - 1];

  String _slotLabel(String slot) => switch (slot) {
    'morning_college' => 'Morning / college',
    'afternoon' => 'Afternoon',
    'evening' => 'Evening',
    'night' => 'Night',
    _ => slot,
  };

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final usage = _usage;
    return PopScope(
      canPop: !_mutating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _mutating && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your changes are still being saved.'),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(item?.itemName ?? 'Wardrobe item'),
          automaticallyImplyLeading: !_mutating,
          actions: [
            if (item != null)
              IconButton(
                tooltip: 'Edit item',
                onPressed: _mutating ? null : _edit,
                icon: const Icon(Icons.edit_outlined),
              ),
            if (item != null)
              PopupMenuButton<bool>(
                enabled: !_mutating,
                onSelected: (permanent) => _delete(permanent: permanent),
                itemBuilder:
                    (context) => const [
                      PopupMenuItem(
                        value: false,
                        child: Text('Remove from wardrobe'),
                      ),
                      PopupMenuItem(
                        value: true,
                        child: Text('Permanently erase'),
                      ),
                    ],
              ),
          ],
        ),
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                  child: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: Text(_error!),
                  ),
                )
                : item == null || usage == null
                ? const SizedBox.shrink()
                : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Container(
                        height: 330,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAF8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: CachedWardrobeImage(url: item.cloudinaryUrl),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        item.itemName ?? 'Unnamed item',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        'Category',
                        item.customCategory ?? item.category,
                      ),
                      if (item.color != null) _InfoRow('Color', item.color!),
                      if (item.pattern != null)
                        _InfoRow('Pattern', item.pattern!),
                      if (item.fabric != null) _InfoRow('Fabric', item.fabric!),
                      if (item.createdAt != null)
                        _InfoRow('Added', _formattedDate(item.createdAt!)),
                      const SizedBox(height: 14),
                      if (item.tags.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ...item.tags.map((tag) => Chip(label: Text(tag))),
                          ],
                        ),
                      const SizedBox(height: 28),
                      Text(
                        'Used in ${usage.outfitCount} saved outfit${usage.outfitCount == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (usage.outfits.isEmpty)
                        const Text('This item is not in a saved outfit yet.')
                      else
                        ...usage.outfits.map(
                          (outfit) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.checkroom_outlined),
                            title: Text(outfit.name ?? 'Untitled outfit'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap:
                                () => context.push(
                                  '/outfits/${outfit.id}',
                                  extra: widget.token,
                                ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        'Calendar history',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (usage.calendarHistory.isEmpty)
                        const Text('This item has not been scheduled yet.')
                      else
                        ...usage.calendarHistory.map(
                          (entry) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.calendar_today_outlined),
                            title: Text(_formattedDate(entry.date)),
                            subtitle: Text(
                              '${_slotLabel(entry.slot)} · ${entry.outfitName ?? 'Untitled outfit'}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
