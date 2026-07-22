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
    required this.token,
    super.key,
  });

  final String outfitId;
  final String token;

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
        token: widget.token,
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
          (context) => AlertDialog(
            title: const Text('Archive outfit?'),
            content: const Text(
              'This hides the outfit from saved outfits while preserving calendar history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Archive'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await _repository.archive(token: widget.token, outfitId: widget.outfitId);
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
        token: widget.token,
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
      await _repository.restore(token: widget.token, outfitId: widget.outfitId);
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
        appBar: AppBar(
          title: Text(outfit?.name ?? 'Outfit'),
          automaticallyImplyLeading: !_deleting,
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
                                token: widget.token,
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
        body:
            _error != null
                ? Center(child: Text(_error!))
                : outfit == null
                ? const Center(child: HangerLoadingIndicator())
                : ListView(
                  padding: const EdgeInsets.all(16),
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
                    ...outfit.items.map(
                      (item) => Card(
                        child: ListTile(
                          onTap:
                              () => context.push(
                                '/wardrobe/items/${item.id}',
                                extra: widget.token,
                              ),
                          leading: SizedBox(
                            width: 56,
                            height: 56,
                            child: CachedWardrobeImage(url: item.cloudinaryUrl),
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit outfit details'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Outfit name'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _occasion,
          maxLength: 50,
          decoration: const InputDecoration(labelText: 'Occasion (optional)'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
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
        child: const Text('Save'),
      ),
    ],
  );
}
