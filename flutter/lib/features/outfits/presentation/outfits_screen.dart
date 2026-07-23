import 'dart:ui';

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
  const OutfitsScreen({ super.key});
  @override
  State<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends State<OutfitsScreen> {
  final _repository = OutfitRepository(ApiClient());
  List<SavedOutfit> _outfits = const [];
  String? _error;
  bool _loading = true;
  String? _deletingId;
  String? _schedulingId; // tracks outfit being scheduled
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
      final outfits = await _repository.list();
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
                'Archive ${outfit.name ?? 'this outfit'}? It stays linked to existing calendar entries.',
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
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = outfit.id);
    try {
      await _repository.archive( outfitId: outfit.id);
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

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? actionButton,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey[900]!.withOpacity(0.40)
                      : Colors.white.withOpacity(0.40),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.12)
                        : Colors.white.withOpacity(0.50),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      ),
                      child: Icon(
                        icon,
                        size: 36,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                    ),
                    if (actionButton != null) ...[
                      const SizedBox(height: 24),
                      actionButton,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverAppBar(
          title: const Text('Outfits'),
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
            IconButton(
              onPressed: () async {
                await context.push('/outfits/generate', );
                if (mounted) await _load();
              },
              tooltip: 'Create an outfit',
              icon: const Icon(Icons.auto_awesome_outlined),
            ),
          ],
        ),
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
          _buildEmptyState(
            icon: Icons.dry_cleaning_outlined,
            title: 'No Saved Outfits Yet',
            subtitle: 'Let our AI Stylist create a perfect outfit for you.',
            actionButton: FilledButton.icon(
              onPressed: () async {
                await context.push('/outfits/generate', );
                if (mounted) await _load();
              },
              style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate Outfit'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final outfit = _outfits[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Material(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black.withOpacity(0.3)
                              : Colors.white.withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white.withOpacity(0.1)
                                  : Colors.white.withOpacity(0.5),
                            ),
                          ),
                          child: InkWell(
                            onLongPress:
                                _deletingId == null ? () => _delete(outfit) : null,
                            onTap: () async {
                              await context.push<bool>(
                                '/outfits/${outfit.id}',
                                
                              );
                              if (mounted) await _load();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              outfit.name ?? 'Untitled outfit',
                                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (outfit.occasion != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                outfit.occasion!,
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    height: 120,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: outfit.items.length,
                                      separatorBuilder:
                                          (_, _) => const SizedBox(width: 12),
                                      itemBuilder:
                                          (context, itemIndex) => AspectRatio(
                                            aspectRatio: 1,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: BackdropFilter(
                                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).brightness == Brightness.dark 
                                                        ? Colors.black.withOpacity(0.3) 
                                                        : Colors.white.withOpacity(0.4),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: Theme.of(context).brightness == Brightness.dark 
                                                          ? Colors.white.withOpacity(0.1) 
                                                          : Colors.white.withOpacity(0.5),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  padding: const EdgeInsets.all(8),
                                                  child: CachedWardrobeImage(
                                                    url:
                                                        outfit
                                                            .items[itemIndex]
                                                            .cloudinaryUrl,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          ),
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


