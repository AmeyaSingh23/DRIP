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
    
    super.key,
  });

  final String itemId;
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
        _repository.get(itemId: widget.itemId, ),
        _repository.usage(itemId: widget.itemId, ),
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
      await _repository.archive(itemId: item.id, );
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

  Future<void> _restoreItem() async {
    final item = _item;
    if (_mutating || item == null) return;
    setState(() => _mutating = true);
    try {
      await _repository.restore(itemId: item.id, );
      ref.read(wardrobeRevisionProvider.notifier).notifyChanged();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item restored successfully.')),
        );
      }
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error))),
        );
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
                      if (item.isArchived)
                        ListTile(
                          leading: Icon(Icons.restore, color: Theme.of(context).colorScheme.onSurface),
                          title: Text('Restore item', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                          subtitle: Text('Restores item back to active wardrobe', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _restoreItem();
                          },
                        )
                      else
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

  Widget _buildEmptyUsageTile(IconData icon, String message) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.2)
                : Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
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
                          tooltip: item.isArchived ? 'Restore item to edit' : 'Edit item',
                          onPressed: _mutating
                              ? null
                              : (item.isArchived
                                  ? () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Restore this item before editing it.'),
                                        ),
                                      );
                                    }
                                  : _edit),
                          icon: Icon(
                            Icons.edit_outlined,
                            color: item.isArchived
                                ? Theme.of(context).colorScheme.onSurface.withOpacity(0.3)
                                : Theme.of(context).colorScheme.onSurface,
                          ),
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
                      if (item.isArchived)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                                  color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white.withOpacity(0.1) 
                                      : Colors.black.withOpacity(0.05),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.archive_outlined, size: 16, color: Theme.of(context).colorScheme.onSurface),
                                    const SizedBox(width: 8),
                                    Text('Archived', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        item.itemName ?? 'Unnamed item',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        'Category',
                        item.customCategory ?? item.category,
                        Icons.category_outlined,
                      ),
                      if (item.color != null) _InfoRow('Color', item.color!, Icons.color_lens_outlined),
                      if (item.pattern != null)
                        _InfoRow('Pattern', item.pattern!, Icons.texture_outlined),
                      if (item.fabric != null) _InfoRow('Fabric', item.fabric!, Icons.checkroom_outlined),
                      if (item.createdAt != null)
                        _InfoRow('Added', _formattedDate(item.createdAt!), Icons.event_outlined),
                      const SizedBox(height: 14),
                      if (item.tags.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ...item.tags.map((tag) => Chip(
                              label: Text(tag),
                              backgroundColor: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.white.withOpacity(0.1) 
                                  : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              side: BorderSide(
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white.withOpacity(0.2) 
                                    : Theme.of(context).colorScheme.primary.withOpacity(0.3),
                              ),
                              labelStyle: TextStyle(
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            )),
                          ],
                        ),
                      const SizedBox(height: 28),
                      Text(
                        'Used in ${usage.outfitCount} saved outfit${usage.outfitCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (usage.outfits.isEmpty)
                        _buildEmptyUsageTile(Icons.checkroom_outlined, 'This item is not in a saved outfit yet.')
                      else
                        ...usage.outfits.map(
                          (outfit) => _GlassListTile(
                            icon: Icons.checkroom_outlined,
                            title: outfit.name ?? 'Untitled outfit',
                            trailingIcon: Icons.chevron_right,
                            onTap: () => context.push(
                              '/outfits/${outfit.id}',
                              
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        'Calendar history',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (usage.calendarHistory.isEmpty)
                        _buildEmptyUsageTile(Icons.calendar_today_outlined, 'This item has not been scheduled yet.')
                      else
                        ...usage.calendarHistory.map(
                          (entry) => _GlassListTile(
                            icon: Icons.calendar_today_outlined,
                            title: _formattedDate(entry.date),
                            subtitle: '${_slotLabel(entry.slot)} · ${entry.outfitName ?? 'Untitled outfit'}',
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

class _GlassListTile extends StatelessWidget {
  const _GlassListTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingIcon,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title, 
                            style: TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.w600, 
                              color: Theme.of(context).colorScheme.onSurface
                            )
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!, 
                              style: TextStyle(
                                fontSize: 13, 
                                fontWeight: FontWeight.w600, 
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                letterSpacing: 0.5,
                              )
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 16),
                      Icon(trailingIcon, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.black.withOpacity(0.2) 
                : Colors.white.withOpacity(0.4),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white.withOpacity(0.1) 
                  : Colors.white.withOpacity(0.5),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label, 
                      style: TextStyle(
                        fontSize: 13, 
                        fontWeight: FontWeight.w600, 
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        letterSpacing: 0.5,
                      )
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value, 
                      style: TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.w600, 
                        color: Theme.of(context).colorScheme.onSurface
                      )
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
}


