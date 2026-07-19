import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../creative/presentation/creative_space_screen.dart';
import '../data/outfit_repository.dart';
import '../domain/saved_outfit.dart';

class OutfitDetailScreen extends StatefulWidget {
  const OutfitDetailScreen({
    required this.outfitId,
    required this.token,
    super.key,
  });

  final String outfitId;
  final String token;

  @override
  State<OutfitDetailScreen> createState() => _OutfitDetailScreenState();
}

class _OutfitDetailScreenState extends State<OutfitDetailScreen> {
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
            title: const Text('Delete outfit?'),
            content: const Text(
              'This removes only the saved outfit. Your wardrobe items stay untouched.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await _repository.delete(token: widget.token, outfitId: widget.outfitId);
      if (mounted) context.pop(true);
    } on DioException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete outfit. Please try again.'),
          ),
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
                onPressed:
                    _deleting
                        ? null
                        : () => context.push(
                          '/creative',
                          extra: CreativeRouteArgs(
                            token: widget.token,
                            initialItems: outfit.items,
                            startCollapsed: true,
                          ),
                        ),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Style on canvas',
              ),
            if (outfit != null)
              IconButton(
                onPressed: _deleting ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete outfit',
              ),
          ],
        ),
        body:
            _error != null
                ? Center(child: Text(_error!))
                : outfit == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
                            child: Image.network(
                              item.cloudinaryUrl,
                              fit: BoxFit.contain,
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
                  ],
                ),
      ),
    );
  }
}
