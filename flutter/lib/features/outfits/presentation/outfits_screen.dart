import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../data/outfit_repository.dart';
import '../domain/saved_outfit.dart';

class OutfitsScreen extends StatefulWidget {
  const OutfitsScreen({required this.token, super.key});

  final String token;

  @override
  State<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends State<OutfitsScreen> {
  final _repository = OutfitRepository(ApiClient());
  List<SavedOutfit> _outfits = const [];
  String? _error;
  bool _loading = true;
  String? _deletingId;
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
      final outfits = await _repository.list(token: widget.token);
      if (mounted && requestEpoch == _loadEpoch) {
        setState(() => _outfits = outfits);
      }
    } on DioException catch (error) {
      if (mounted && requestEpoch == _loadEpoch) {
        final data = error.response?.data;
        setState(
          () =>
              _error =
                  data is Map && data['detail'] is String
                      ? data['detail'] as String
                      : 'Could not load saved outfits.',
        );
      }
    } finally {
      if (mounted && requestEpoch == _loadEpoch) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _delete(SavedOutfit outfit) async {
    if (_deletingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete outfit?'),
            content: Text(
              'Delete ${outfit.name ?? 'this outfit'}? Your wardrobe items stay untouched.',
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
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = outfit.id);
    try {
      await _repository.delete(token: widget.token, outfitId: outfit.id);
      await _load();
    } on DioException catch (error) {
      if (mounted) {
        final data = error.response?.data;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data is Map && data['detail'] is String
                  ? data['detail'] as String
                  : 'Could not delete outfit. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Outfits'),
      actions: [
        IconButton(
          onPressed: () async {
            await context.push('/outfits/generate', extra: widget.token);
            if (mounted) await _load();
          },
          tooltip: 'Create an outfit',
          icon: const Icon(Icons.auto_awesome_outlined),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ListView(
                children: [
                  const SizedBox(height: 140),
                  Center(child: Text(_error!)),
                ],
              )
              : _outfits.isEmpty
              ? ListView(
                children: const [
                  SizedBox(height: 140),
                  Center(
                    child: Text('No saved outfits yet. Create one with ✨.'),
                  ),
                ],
              )
              : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                itemCount: _outfits.length,
                itemBuilder: (context, index) {
                  final outfit = _outfits[index];
                  return InkWell(
                    onLongPress:
                        _deletingId == null ? () => _delete(outfit) : null,
                    onTap: () async {
                      await context.push<bool>(
                        '/outfits/${outfit.id}',
                        extra: widget.token,
                      );
                      if (mounted) await _load();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              outfit.name ?? 'Untitled outfit',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (outfit.occasion != null)
                              Text(
                                outfit.occasion!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 150,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: outfit.items.length,
                                separatorBuilder:
                                    (_, _) => const SizedBox(width: 8),
                                itemBuilder:
                                    (context, itemIndex) => AspectRatio(
                                      aspectRatio: .75,
                                      child: CachedWardrobeImage(
                                        url:
                                            outfit
                                                .items[itemIndex]
                                                .cloudinaryUrl,
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
    ),
  );
}
