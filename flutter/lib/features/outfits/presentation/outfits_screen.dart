import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../../../core/widgets/hanger_loading_indicator.dart';
import '../../wardrobe/presentation/widgets/wardrobe_hanger_refresh.dart';
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
      if (_outfits.isEmpty) _loading = true;
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
            title: const Text('Archive outfit?'),
            content: Text(
              'Archive ${outfit.name ?? 'this outfit'}? It stays linked to existing calendar entries.',
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
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = outfit.id);
    try {
      await _repository.archive(token: widget.token, outfitId: outfit.id);
      await _load();
    } on DioException catch (error) {
      if (mounted) {
        final data = error.response?.data;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data is Map && data['detail'] is String
                  ? data['detail'] as String
                  : 'Could not archive outfit. Please try again.',
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
    body: CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        WardrobeHangerRefreshControl(onRefresh: _load),
        if (_loading)
          const SliverFillRemaining(child: Center(child: HangerLoadingIndicator()))
        else if (_error != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              children: [
                const SizedBox(height: 140),
                Center(child: Text(_error!)),
              ],
            ),
          )
        else if (_outfits.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              children: const [
                SizedBox(height: 140),
                Center(
                  child: Text('No saved outfits yet. Create one with ✨.'),
                ),
              ],
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
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
                childCount: _outfits.length,
              ),
            ),
          ),
      ],
    ),
  );
}
