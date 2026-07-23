import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../../../core/widgets/hanger_loading_indicator.dart';
import '../../creative/presentation/creative_space_screen.dart';
import '../../wardrobe/presentation/wardrobe_change_notifier.dart';
import '../data/outfit_repository.dart';
import '../domain/saved_outfit.dart';

class OutfitDetailScreen extends ConsumerStatefulWidget {
  const OutfitDetailScreen({
    required this.outfitId,
    
    super.key,
  });

  final String outfitId;
  @override
  ConsumerState<OutfitDetailScreen> createState() => _OutfitDetailScreenState();
}

class _OutfitDetailScreenState extends ConsumerState<OutfitDetailScreen> {
  final _repository = OutfitRepository(ApiClient());
  SavedOutfit? _outfit;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final outfit = await _repository.get(
        
        outfitId: widget.outfitId,
      );
      if (mounted) setState(() => _outfit = outfit);
    } on DioException catch (error) {
      if (mounted) {
        setState(
          () =>
              _error =
                  error.response?.data is Map
                      ? (error.response!.data['detail'] as String? ??
                          'Could not load outfit.')
                      : 'Could not load outfit.',
        );
      }
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AlertDialog(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[900]!.withOpacity(0.50)
                  : Colors.white.withOpacity(0.50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.white.withOpacity(0.5),
                  width: 1,
                ),
              ),
              title: Text('Archive outfit?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              content: Text(
                'This hides the outfit from saved outfits while preserving calendar history.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  child: const Text('Cancel'),
                ),
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
          ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await _repository.archive( outfitId: widget.outfitId);
      ref.read(outfitRevisionProvider.notifier).notifyChanged();
      if (mounted) context.pop(true);
    } on DioException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not archive outfit. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _editDetails() async {
    if (_deleting || _outfit == null) return;
    final outfit = _outfit!;
    final details = await showDialog<_OutfitDetails>(
      context: context,
      builder:
          (_) => _OutfitDetailsDialog(
            initialName: outfit.name,
            initialOccasion: outfit.occasion,
          ),
    );
    if (details == null || !mounted) return;
    setState(() => _deleting = true);
    try {
      final updated = await _repository.update(
        
        outfitId: outfit.id,
        name: details.name,
        occasion: details.occasion,
      );
      if (mounted) setState(() => _outfit = updated);
    } on DioException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update outfit details.')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _restoreOutfit() async {
    if (_deleting || _outfit == null) return;
    setState(() => _deleting = true);
    try {
      await _repository.restore( outfitId: widget.outfitId);
      ref.read(outfitRevisionProvider.notifier).notifyChanged();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Outfit restored successfully.')),
        );
      }
    } on DioException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not restore outfit. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outfit = _outfit;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: !_deleting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _deleting && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('The outfit is still being deleted.')),
          );
        }
      },
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
            CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverAppBar(
                  title: Text(outfit?.name ?? 'Outfit'),
              automaticallyImplyLeading: !_deleting,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[900]!.withOpacity(0.50)
                        : Colors.white.withOpacity(0.50),
                  ),
                ),
              ),
              actions: [
                if (outfit != null)
                  IconButton(
                    onPressed: _deleting
                        ? null
                        : (outfit.isArchived
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Restore this outfit before editing details.')),
                                );
                              }
                            : _editDetails),
                    icon: Icon(
                      Icons.edit_note_outlined,
                      color: outfit.isArchived ? Theme.of(context).colorScheme.onSurface.withOpacity(0.3) : null,
                    ),
                    tooltip: outfit.isArchived ? 'Restore outfit to edit details' : 'Edit outfit details',
                  ),
                if (outfit != null)
                  IconButton(
                    onPressed: _deleting
                        ? null
                        : (outfit.isArchived
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Restore this outfit before styling on canvas.')),
                                );
                              }
                            : () async {
                                await context.push(
                                  '/creative',
                                  extra: CreativeRouteArgs(
                                    
                                    initialItems: outfit.items,
                                    initialName: outfit.name,
                                    initialOccasion: outfit.occasion,
                                    initialLayout: outfit.itemLayout,
                                    editingOutfitId: outfit.id,
                                    startCollapsed: true,
                                  ),
                                );
                                if (mounted) await _load();
                              }),
                    icon: Icon(
                      Icons.palette_outlined,
                      color: outfit.isArchived ? Theme.of(context).colorScheme.onSurface.withOpacity(0.3) : null,
                    ),
                    tooltip: outfit.isArchived ? 'Restore outfit to style on canvas' : 'Style on canvas',
                  ),
                if (outfit != null)
                  IconButton(
                    onPressed: _deleting
                        ? null
                        : (outfit.isArchived ? _restoreOutfit : _delete),
                    icon: Icon(outfit.isArchived ? Icons.restore : Icons.archive_outlined),
                    tooltip: outfit.isArchived ? 'Restore outfit' : 'Archive outfit',
                  ),
              ],
            ),
            if (_error != null)
              SliverFillRemaining(child: Center(child: Text(_error!)))
            else if (outfit == null)
              const SliverFillRemaining(child: Center(child: HangerLoadingIndicator()))
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == 0) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    if (outfit.isArchived)
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
                    if (outfit.occasion != null)
                      Chip(label: Text(outfit.occasion!)),
                    const SizedBox(height: 8),
                    Text(
                      '${outfit.items.length} wardrobe items',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                            const SizedBox(height: 10),
                          ],
                        );
                      }
                      
                      final item = outfit.items[index - 1];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.black.withOpacity(0.3)
                                    : Colors.white.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white.withOpacity(0.1)
                                      : Colors.white.withOpacity(0.5),
                                ),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: ListTile(
                                onTap:
                                    () => context.push(
                                      '/wardrobe/items/${item.id}',
                                      
                                    ),
                                leading: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).brightness == Brightness.dark 
                                              ? Colors.black.withOpacity(0.3) 
                                              : Colors.white.withOpacity(0.4),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Theme.of(context).brightness == Brightness.dark 
                                                ? Colors.white.withOpacity(0.1) 
                                                : Colors.white.withOpacity(0.5),
                                            width: 1,
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: CachedWardrobeImage(url: item.cloudinaryUrl),
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(item.itemName ?? item.category),
                                subtitle: Text(
                                  [
                                    item.color,
                                    item.pattern,
                                  ].whereType<String>().join(' · '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    },
                    childCount: outfit.items.length + 1,
                  ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutfitDetails {
  const _OutfitDetails({required this.name, this.occasion});
  final String? name;
  final String? occasion;
}

class _OutfitDetailsDialog extends StatefulWidget {
  const _OutfitDetailsDialog({this.initialName, this.initialOccasion});
  final String? initialName;
  final String? initialOccasion;

  @override
  State<_OutfitDetailsDialog> createState() => _OutfitDetailsDialogState();
}

class _OutfitDetailsDialogState extends State<_OutfitDetailsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _occasion;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _occasion = TextEditingController(text: widget.initialOccasion ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _occasion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
    child: AlertDialog(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey[900]!.withOpacity(0.50)
          : Colors.white.withOpacity(0.50),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.1)
              : Colors.white.withOpacity(0.5),
          width: 1,
        ),
      ),
      title: Text('Edit outfit details', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Outfit Name', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _name,
                  builder: (context, value, _) => Text(
                    '${value.text.length}/120',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              maxLength: 120,
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.white.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Occasion (optional)', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _occasion,
                  builder: (context, value, _) => Text(
                    '${value.text.length}/50',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _occasion,
              maxLength: 50,
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.white.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.pop(
                context,
                _OutfitDetails(
                  name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                  occasion:
                      _occasion.text.trim().isEmpty
                          ? null
                          : _occasion.text.trim(),
                ),
              ),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.onSurface,
            foregroundColor: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onPrimary,
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}


