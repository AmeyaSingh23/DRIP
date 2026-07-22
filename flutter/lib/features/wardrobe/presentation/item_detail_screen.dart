import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../../../core/widgets/hanger_loading_indicator.dart';
import '../data/wardrobe_repository.dart';
import '../domain/clothing_item_draft.dart';
import '../domain/clothing_item_usage.dart';
import 'widgets/wardrobe_hanger_refresh.dart';
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
      if (_item == null) _loading = true;
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

  Future<void> _archive() async {
    if (_mutating) return;
    final item = _item;
    if (item == null) return;
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
                        'This hides the item while preserving saved outfit and calendar history.',
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
    setState(() => _mutating = true);
    try {
      await _repository.archive(itemId: item.id, token: widget.token);
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
                          _archive();
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
        backgroundColor: Colors.transparent,
        body:
            _loading
                ? const Center(child: HangerLoadingIndicator())
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
                : CustomScrollView(
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
                        item.itemName ?? 'Wardrobe item',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      automaticallyImplyLeading: !_mutating,
                      actions: [
                        IconButton(
                          tooltip: 'Edit item',
                          onPressed: _mutating ? null : _edit,
                          icon: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        IconButton(
                          tooltip: 'More options',
                          onPressed: _mutating ? null : () => _showActions(item),
                          icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ],
                    ),
                    WardrobeHangerRefreshControl(onRefresh: _load),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            height: 330,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.black.withOpacity(0.3) 
                                  : Colors.white.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white.withOpacity(0.1) 
                                    : Colors.white.withOpacity(0.5),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: CachedWardrobeImage(url: item.cloudinaryUrl),
                            ),
                          ),
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
                    ]),
                  ),
                ),
              ],
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
