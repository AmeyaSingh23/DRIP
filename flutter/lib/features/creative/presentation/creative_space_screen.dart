import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../../../core/widgets/hanger_loading_indicator.dart';
import '../../wardrobe/presentation/widgets/wardrobe_hanger_refresh.dart';
import '../../wardrobe/domain/clothing_item_draft.dart';
import '../../wardrobe/presentation/wardrobe_change_notifier.dart';
import '../../wardrobe/presentation/providers/wardrobe_provider.dart';
import '../data/creative_repository.dart';
import '../../outfits/domain/outfit_item_layout.dart';
import '../../profile/presentation/providers/profile_stats_provider.dart';

final class CreativeRouteArgs {
  const CreativeRouteArgs({
    
    this.initialItems,
    this.initialName,
    this.initialOccasion,
    this.initialLayout,
    this.editingOutfitId,
    this.startCollapsed,
  });
  final List<ClothingItemDraft>? initialItems;
  final String? initialName;
  final String? initialOccasion;
  final List<OutfitItemLayout>? initialLayout;
  final String? editingOutfitId;
  final bool? startCollapsed;
}

enum _CanvasZone { accessories, shoes, bottoms, tops, outerwear }

class CreativeSpaceScreen extends ConsumerStatefulWidget {
  const CreativeSpaceScreen({
    
    this.initialItems,
    this.initialName,
    this.initialOccasion,
    this.initialLayout,
    this.editingOutfitId,
    this.startCollapsed,
    super.key,
  });
  final List<ClothingItemDraft>? initialItems;
  final String? initialName;
  final String? initialOccasion;
  final List<OutfitItemLayout>? initialLayout;
  final String? editingOutfitId;
  final bool? startCollapsed;

  @override
  ConsumerState<CreativeSpaceScreen> createState() => _CreativeSpaceScreenState();
}

class _CreativeSpaceScreenState extends ConsumerState<CreativeSpaceScreen> {
  static const _baseCategories = [
    'All',
    'Tops',
    'Bottoms',
    'Outerwear',
    'Shoes',
    'Dresses',
    'Accessories',
    'Uniform',
  ];
  static const _planeSize = Size(4000, 4000);

  final _repository = CreativeRepository();
  final _transform = TransformationController();
  final _canvasKey = GlobalKey();
  final Map<String, ClothingItemDraft> _placed = {};
  final Map<String, Offset> _itemOffsets = {};
  final Map<String, double> _itemScales = {};
  List<ClothingItemDraft> _items = const [];
  String _selectedCategory = 'All';
  String _outfitName = 'Styled outfit';
  String? _occasion;
  String? _saveIdempotencyKey;
  String? _selectedItemId;
  Offset _longPressStartOffset = Offset.zero;
  bool _sidebarCollapsed = false;
  bool _loading = true;
  bool _saving = false;
  bool _initialViewApplied = false;
  Size? _viewportSize;
  String? _error;
  int _loadEpoch = 0;

  Rect get _dummyRect => Rect.fromCenter(
    center: const Offset(2000, 1950),
    width: 360,
    height: 760,
  );

  @override
  void initState() {
    super.initState();
    _sidebarCollapsed = widget.startCollapsed ?? widget.initialItems != null;
    _outfitName =
        widget.initialName?.trim().isNotEmpty == true
            ? widget.initialName!.trim()
            : _outfitName;
    _occasion = widget.initialOccasion;
    final initialItems = widget.initialItems ?? const <ClothingItemDraft>[];
    final itemById = {for (final item in initialItems) item.id: item};
    final restoredIds = <String>{};
    for (final layout in widget.initialLayout ?? const <OutfitItemLayout>[]) {
      final item = itemById[layout.itemId];
      if (item == null) continue;
      _placed[item.id] = item;
      _itemOffsets[item.id] = Offset(layout.offsetX, layout.offsetY);
      _itemScales[item.id] = layout.scale;
      restoredIds.add(item.id);
    }
    for (final item in initialItems) {
      if (!restoredIds.contains(item.id)) _autoPlace(item);
    }
    Future.microtask(() {
      if (mounted) _loadWardrobe();
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _loadWardrobe() async {
    final epoch = ++_loadEpoch;
    setState(() {
      if (_items.isEmpty) _loading = true;
      _error = null;
    });
    try {
      var items = ref.read(wardrobeItemsProvider).items;
      if (items.isEmpty) {
        await ref.read(wardrobeItemsProvider.notifier).load();
        items = ref.read(wardrobeItemsProvider).items;
      }
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _items = items;
        final activeIds = items.map((item) => item.id).toSet();
        final missingIds = _placed.keys
            .where((id) => !activeIds.contains(id))
            .toList();
        for (final id in missingIds) {
          _placed.remove(id);
          _itemOffsets.remove(id);
          _itemScales.remove(id);
        }
        if (_selectedItemId != null && !_placed.containsKey(_selectedItemId)) {
          _selectedItemId = null;
        }
        if (!_categories.contains(_selectedCategory)) _selectedCategory = 'All';
      });
    } on DioException catch (error) {
      if (mounted && epoch == _loadEpoch) {
        setState(
          () => _error = _messageFor(error, 'Could not load wardrobe items.'),
        );
      }
    } finally {
      if (mounted && epoch == _loadEpoch) setState(() => _loading = false);
    }
  }

  List<String> get _categories {
    final custom =
        _items
            .where((item) => item.category == 'Custom')
            .map((item) => item.customCategory?.trim())
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return [..._baseCategories, ...custom];
  }

  List<ClothingItemDraft> get _filteredItems =>
      _items.where((item) {
        if (_selectedCategory == 'All') return true;
        return item.category == _selectedCategory ||
            (item.category == 'Custom' &&
                item.customCategory == _selectedCategory);
      }).toList();

  String _messageFor(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map && data['detail'] is String
        ? data['detail'] as String
        : fallback;
  }

  String _itemText(ClothingItemDraft item) =>
      [
        item.category,
        item.customCategory,
        item.itemName,
        ...item.tags,
      ].whereType<String>().join(' ').toLowerCase();

  _CanvasZone _zoneFor(ClothingItemDraft item) {
    final text = _itemText(item);
    if (item.category == 'Dresses' ||
        text.contains('dress') ||
        text.contains('gown') ||
        text.contains('jumpsuit')) {
      return _CanvasZone.tops;
    }
    if (item.category == 'Tops' ||
        item.category == 'Uniform' ||
        text.contains('shirt') ||
        text.contains('tee') ||
        text.contains('blouse') ||
        text.contains('polo') ||
        text.contains('sweater') ||
        text.contains('hoodie') ||
        text.contains('tank') ||
        text.contains('camisole') ||
        text.contains('bra')) {
      return _CanvasZone.tops;
    }
    if (item.category == 'Outerwear' ||
        text.contains('jacket') ||
        text.contains('coat') ||
        text.contains('blazer') ||
        text.contains('cardigan')) {
      return _CanvasZone.outerwear;
    }
    if (item.category == 'Bottoms' ||
        text.contains('short') ||
        text.contains('brief') ||
        text.contains('boxer') ||
        text.contains('jean') ||
        text.contains('trouser') ||
        text.contains('pants') ||
        text.contains('legging') ||
        text.contains('skirt')) {
      return _CanvasZone.bottoms;
    }
    if (item.category == 'Shoes' ||
        text.contains('shoe') ||
        text.contains('sneaker') ||
        text.contains('sandal') ||
        text.contains('boot') ||
        text.contains('heel')) {
      return _CanvasZone.shoes;
    }
    return _CanvasZone.accessories;
  }

  Rect _zoneRect(_CanvasZone zone, [ClothingItemDraft? item]) {
    final text = item == null ? '' : _itemText(item);
    // These are just sensible starting bounds.  The saved per-item scale is
    // deliberately the authority, so we do not maintain a brittle list of
    // special cases for every garment name.
    if (item?.category == 'Dresses' ||
        text.contains('dress') ||
        text.contains('gown') ||
        text.contains('jumpsuit')) {
      return Rect.fromCenter(
        center: const Offset(2000, 1950),
        width: 250,
        height: 500,
      );
    }
    if (item?.category == 'Uniform') {
      return Rect.fromCenter(
        center: const Offset(2000, 1930),
        width: 255,
        height: 500,
      );
    }
    return switch (zone) {
      _CanvasZone.tops => Rect.fromCenter(
        center: const Offset(2000, 1780),
        width: 235,
        height: 265,
      ),
      _CanvasZone.outerwear => Rect.fromCenter(
        center: const Offset(2000, 1800),
        width: 255,
        height: 300,
      ),
      _CanvasZone.bottoms => Rect.fromCenter(
        center: const Offset(2000, 2060),
        width: 230,
        height: 285,
      ),
      _CanvasZone.shoes => Rect.fromCenter(
        center: const Offset(2000, 2290),
        width: 230,
        height: 120,
      ),
      _CanvasZone.accessories => Rect.fromCenter(
        center: const Offset(2000, 1760),
        width: 145,
        height: 145,
      ),
    };
  }

  _CanvasZone? _zoneFromLayout(String value) => switch (value) {
    'accessories' => _CanvasZone.accessories,
    'shoes' => _CanvasZone.shoes,
    'bottoms' => _CanvasZone.bottoms,
    'tops' => _CanvasZone.tops,
    'outerwear' => _CanvasZone.outerwear,
    _ => null,
  };

  String _layoutZone(_CanvasZone zone) => switch (zone) {
    _CanvasZone.accessories => 'accessories',
    _CanvasZone.shoes => 'shoes',
    _CanvasZone.bottoms => 'bottoms',
    _CanvasZone.tops => 'tops',
    _CanvasZone.outerwear => 'outerwear',
  };

  void _autoPlace(ClothingItemDraft item) {
    _placed[item.id] = item;
    _itemOffsets[item.id] = Offset.zero;
    _itemScales[item.id] = 1;
  }

  // ignore: unused_element
  void _place(ClothingItemDraft item) {
    setState(() {
      _saveIdempotencyKey = null;
      _placed[item.id] = item;
      _itemOffsets[item.id] = Offset.zero;
      _itemScales[item.id] = 1;
    });
  }

  void _placeAt(DragTargetDetails<ClothingItemDraft> details) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final item = details.data;
    final zone = _zoneFor(item);
    final scenePoint = box?.globalToLocal(details.offset);
    final rect = _zoneRect(zone, item);
    setState(() {
      _saveIdempotencyKey = null;
      _placed[item.id] = item;
      _itemOffsets[item.id] =
          scenePoint == null ? Offset.zero : scenePoint - rect.center;
      _itemScales[item.id] = 1;
    });
  }

  void _startMove(String itemId) {
    setState(() {
      _selectedItemId = itemId;
      _longPressStartOffset = _itemOffsets[itemId] ?? Offset.zero;
    });
  }

  void _moveItem(String itemId, LongPressMoveUpdateDetails details) {
    final scale = _transform.value.getMaxScaleOnAxis();
    setState(() {
      _saveIdempotencyKey = null;
      _selectedItemId = itemId;
      _itemOffsets[itemId] =
          _longPressStartOffset + details.offsetFromOrigin / scale;
    });
  }

  void _nudge(Offset delta) {
    final itemId = _selectedItemId;
    if (itemId == null || !_placed.containsKey(itemId)) return;
    setState(() {
      _saveIdempotencyKey = null;
      _itemOffsets[itemId] = (_itemOffsets[itemId] ?? Offset.zero) + delta;
    });
  }

  void _resizeSelected(double factor) {
    final itemId = _selectedItemId;
    if (itemId == null || !_placed.containsKey(itemId)) return;
    setState(() {
      _saveIdempotencyKey = null;
      _itemScales[itemId] =
          ((_itemScales[itemId] ?? 1) * factor).clamp(.4, 2.4).toDouble();
    });
  }

  void _deselectIfOutside(PointerDownEvent event) {
    final itemId = _selectedItemId;
    if (itemId == null) return;
    final item = _placed[itemId];
    if (item == null) return;
    final scenePoint = _transform.toScene(event.localPosition);
    final baseRect = _zoneRect(_zoneFor(item), item);
    final scale = _itemScales[itemId] ?? 1;
    final itemBounds = Rect.fromCenter(
      center: baseRect.center + (_itemOffsets[itemId] ?? Offset.zero),
      width: baseRect.width * scale,
      height: baseRect.height * scale,
    );
    if (!itemBounds.contains(scenePoint)) {
      setState(() => _selectedItemId = null);
    }
  }

  void _remove(String itemId) {
    setState(() {
      _saveIdempotencyKey = null;
      _placed.remove(itemId);
      _itemOffsets.remove(itemId);
      _itemScales.remove(itemId);
      if (_selectedItemId == itemId) _selectedItemId = null;
    });
  }

  List<ClothingItemDraft> get _placedItems => _placed.values.toList();

  List<OutfitItemLayout> get _itemLayout =>
      _placed.values
          .map((item) {
            final offset = _itemOffsets[item.id] ?? Offset.zero;
            return OutfitItemLayout(
              itemId: item.id,
              zone: _layoutZone(_zoneFor(item)),
              offsetX: offset.dx,
              offsetY: offset.dy,
              scale: _itemScales[item.id] ?? 1,
            );
          })
          .toList();

  Future<void> _save() async {
    final items = _placedItems;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item before saving.')),
      );
      return;
    }
    final details = await showDialog<_OutfitDetails>(
      context: context,
      builder:
          (_) => _OutfitDetailsDialog(
            initialName: _outfitName,
            initialOccasion: _occasion,
          ),
    );
    if (details == null || !mounted) return;
    setState(() {
      _outfitName = details.name;
      _occasion = details.occasion;
      _saving = true;
    });
    try {
      await _repository.saveOutfit(
        
        items: items,
        name: _outfitName,
        itemLayout: _itemLayout,
        occasion: _occasion,
        outfitId: widget.editingOutfitId,
        idempotencyKey: _saveIdempotencyKey ??= const Uuid().v4(),
      );
      ref.read(profileStatsProvider.notifier).incrementOutfits();
      ref.read(outfitRevisionProvider.notifier).notifyChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.editingOutfitId == null
                  ? 'Outfit saved to your wardrobe history.'
                  : 'Outfit changes saved.',
            ),
          ),
        );
        _saveIdempotencyKey = null;
      }
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error, 'Could not save outfit.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearAll() {
    setState(() {
      _saveIdempotencyKey = null;
      _placed.clear();
      _itemOffsets.clear();
      _itemScales.clear();
      _selectedItemId = null;
    });
  }

  void _scheduleInitialView(Size size) {
    if (_initialViewApplied || size.isEmpty) return;
    _viewportSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_initialViewApplied) {
        _focusMannequin();
        _initialViewApplied = true;
      }
    });
  }

  void _focusMannequin() {
    final size = _viewportSize;
    if (size == null) return;
    // Leave comfortable head-and-feet margins on phone screens rather than
    // fitting the mannequin edge-to-edge.
    const scale = .72;
    final center = size.center(Offset.zero);
    final sceneCenter = _dummyRect.center;
    final matrix = Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      center.dx - sceneCenter.dx * scale,
      center.dy - sceneCenter.dy * scale,
      0,
    );
    _transform.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(wardrobeRevisionProvider, (_, _) => _loadWardrobe());
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Studio'),
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
        actions: [
          IconButton(
            tooltip: 'Focus mannequin',
            onPressed: _focusMannequin,
            icon: Icon(Icons.center_focus_strong, color: Theme.of(context).colorScheme.onSurface),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  _sidebar(),
                  Expanded(child: _canvas()),
                ],
              ),
            ),
            ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.black.withOpacity(0.2) 
                      : Colors.white.withOpacity(0.3),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            foregroundColor: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white 
                                : const Color(0xFF5C0024),
                          ),
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: Text(
                            _saving
                                ? 'Saving...'
                                : widget.editingOutfitId == null
                                ? 'Save as outfit'
                                : 'Save changes',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.onSurface,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        onPressed: _saving || _placed.isEmpty ? null : _clearAll,
                        icon: const Icon(Icons.layers_clear_outlined),
                        label: const Text('Clear all'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: _sidebarCollapsed ? 48 : 116,
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.25) : Colors.white.withOpacity(0.40),
            border: Border(
              right: BorderSide(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.4),
              ),
            ),
          ),
          child: _sidebarCollapsed
              ? Align(
                  alignment: Alignment.topCenter,
                  child: IconButton(
                    tooltip: 'Show wardrobe',
                    onPressed: () => setState(() => _sidebarCollapsed = false),
                    icon: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface),
                  ),
                )
              : Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Hide wardrobe',
                        onPressed: () => setState(() => _sidebarCollapsed = true),
                        icon: Icon(Icons.chevron_left, color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _categories.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          final isSelected = category == _selectedCategory;
                          return ChoiceChip(
                            label: Text(
                              category,
                              style: TextStyle(
                                color: isSelected
                                    ? (isDark ? Colors.white : const Color(0xFF5C0024))
                                    : Theme.of(context).colorScheme.onSurface,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: Theme.of(context).colorScheme.primary,
                            checkmarkColor: isDark ? Colors.white : const Color(0xFF5C0024),
                            onSelected: (_) => setState(() => _selectedCategory = category),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: CustomScrollView(
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        slivers: [
                          WardrobeHangerRefreshControl(onRefresh: _loadWardrobe),
                          _itemList(),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _itemList() {
    if (_loading) return const SliverFillRemaining(child: Center(child: HangerLoadingIndicator()));
    if (_error != null) {
      return SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton(
              onPressed: _loadWardrobe,
              child: const Text('Retry'),
            ),
          ),
        ),
      );
    }
    final items = _filteredItems;
    if (items.isEmpty) return const SliverFillRemaining(child: Center(child: Text('No items')));
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index.isOdd) return const SizedBox(height: 8);
            final itemIndex = index ~/ 2;
            return SizedBox(height: 126, child: _draggableItem(items[itemIndex]));
          },
          childCount: items.isEmpty ? 0 : items.length * 2 - 1,
        ),
      ),
    );
  }

  Widget _draggableItem(ClothingItemDraft item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnCanvas = _placed.values.any((placed) => placed.id == item.id);
    final thumbnail = Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(child: CachedWardrobeImage(url: item.cloudinaryUrl)),
            const SizedBox(height: 4),
            Text(
              item.itemName ?? item.category,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ],
        ),
      ),
    );
    return LongPressDraggable<ClothingItemDraft>(
      data: item,
      maxSimultaneousDrags: isOnCanvas ? 0 : 1,
      delay: const Duration(milliseconds: 250),
      feedback: Opacity(
        opacity: .72,
        child: SizedBox(width: 96, height: 126, child: thumbnail),
      ),
      childWhenDragging: Opacity(opacity: .35, child: thumbnail),
      child: Opacity(opacity: isOnCanvas ? .42 : 1, child: thumbnail),
    );
  }

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      _scheduleInitialView(Size(constraints.maxWidth, constraints.maxHeight));
      return Container(
        color: Colors.transparent,
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: DragTarget<ClothingItemDraft>(
                  onWillAcceptWithDetails:
                      (details) =>
                          !_placed.values.any(
                            (item) => item.id == details.data.id,
                          ),
                  onAcceptWithDetails: _placeAt,
                  builder:
                      (context, candidates, _) => Listener(
                        onPointerDown: _deselectIfOutside,
                        child: InteractiveViewer(
                          transformationController: _transform,
                          minScale: .28,
                          maxScale: 3.5,
                          boundaryMargin: const EdgeInsets.all(900),
                          constrained: false,
                          child: SizedBox(
                            width: _planeSize.width,
                            height: _planeSize.height,
                            child: _canvasStack(),
                          ),
                        ),
                      ),
                ),
              ),
              if (_selectedItemId != null && _placed.containsKey(_selectedItemId))
                Positioned(right: 12, bottom: 12, child: _nudgeControls()),
            ],
          ),
        ),
      );
    },
  );

  Widget _canvasStack() => Stack(
    key: _canvasKey,
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _GridPainter(
            lineColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
          ),
        ),
      ),
      Positioned.fromRect(
        rect: _dummyRect,
        child: IgnorePointer(child: _croppedDummy()),
      ),
      ..._placedLayerItems(_CanvasZone.accessories),
      ..._placedLayerItems(_CanvasZone.shoes),
      ..._placedLayerItems(_CanvasZone.bottoms),
      ..._placedLayerItems(_CanvasZone.tops),
      ..._placedLayerItems(_CanvasZone.outerwear),
      ..._placed.keys.map(_removeButton),
    ],
  );

  Iterable<Widget> _placedLayerItems(_CanvasZone zone) =>
      _placed.values.where((item) => _zoneFor(item) == zone).map(_placedItem);

  Widget _placedItem(ClothingItemDraft item) {
    final zone = _zoneFor(item);
    return Positioned.fromRect(
      rect: _zoneRect(zone, item),
      child: Transform.translate(
        offset: _itemOffsets[item.id] ?? Offset.zero,
        child: Transform.scale(
          alignment: Alignment.center,
          scale: _itemScales[item.id] ?? 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => _startMove(item.id),
            onLongPressMoveUpdate: (details) => _moveItem(item.id, details),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border:
                    _selectedItemId == item.id
                        ? Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFFFFB6C1)
                                : const Color(0xFFC2185B),
                            width: 2.5,
                          )
                        : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: CachedWardrobeImage(url: item.cloudinaryUrl),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _removeButton(String itemId) {
    final item = _placed[itemId]!;
    final rect = _zoneRect(_zoneFor(item), item);
    final offset = _itemOffsets[itemId] ?? Offset.zero;
    final scale = _itemScales[itemId] ?? 1;
    return Positioned(
      left: rect.center.dx + offset.dx + (rect.width * scale) / 2 - 32,
      top: rect.center.dy + offset.dy - (rect.height * scale) / 2 - 24,
      child: GestureDetector(
        onTap: () => _remove(itemId),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  // The supplied PNG has a 1408x768 transparent canvas around a narrow,
  // centred figure. Crop that canvas at render time so the mannequin's visible
  // body fills its logical body rectangle without altering the user asset.
  Widget _croppedDummy() => LayoutBuilder(
    builder:
        (context, constraints) => ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            maxHeight: constraints.maxHeight / .875,
            child: Image.asset(
              'assets/images/female_dummy.png',
              height: constraints.maxHeight / .875,
              fit: BoxFit.fitHeight,
            ),
          ),
        ),
  );

  Widget _nudgeControls() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = Theme.of(context).colorScheme.onSurface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Adjust', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: iconColor)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Make smaller',
                      onPressed: () => _resizeSelected(.9),
                      icon: Icon(Icons.remove_circle_outline, color: iconColor),
                    ),
                    IconButton(
                      tooltip: 'Make larger',
                      onPressed: () => _resizeSelected(1.1),
                      icon: Icon(Icons.add_circle_outline, color: iconColor),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: () => _nudge(const Offset(0, -8)),
                  icon: Icon(Icons.keyboard_arrow_up, color: iconColor),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Move left',
                      onPressed: () => _nudge(const Offset(-8, 0)),
                      icon: Icon(Icons.keyboard_arrow_left, color: iconColor),
                    ),
                    IconButton(
                      tooltip: 'Move right',
                      onPressed: () => _nudge(const Offset(8, 0)),
                      icon: Icon(Icons.keyboard_arrow_right, color: iconColor),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: () => _nudge(const Offset(0, 8)),
                  icon: Icon(Icons.keyboard_arrow_down, color: iconColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color lineColor;
  _GridPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 40.0;
    final paint =
        Paint()
          ..color = lineColor
          ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => oldDelegate.lineColor != lineColor;
}

class _OutfitDetails {
  const _OutfitDetails({required this.name, this.occasion});

  final String name;
  final String? occasion;
}

class _OutfitDetailsDialog extends StatefulWidget {
  const _OutfitDetailsDialog({required this.initialName, this.initialOccasion});

  final String initialName;
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
    _name = TextEditingController(text: widget.initialName);
    _occasion = TextEditingController(text: widget.initialOccasion ?? '');
    _name.addListener(() => setState(() {}));
    _occasion.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _occasion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceFill = isDark ? Colors.grey[850]! : Colors.grey[100]!;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: isDark ? Colors.grey[900]!.withOpacity(0.60) : Colors.white.withOpacity(0.60),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Save outfit',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Outfit name',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    maxLength: 120,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: surfaceFill,
                      hintText: 'e.g. Summer Casual Outfit',
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_name.text.length}/120',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Occasion (optional)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _occasion,
                    maxLength: 50,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: surfaceFill,
                      hintText: 'College, dinner, date night...',
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_occasion.text.length}/50',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.onSurface,
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : const Color(0xFF5C0024),
                        ),
                        onPressed: () {
                          final name = _name.text.trim();
                          if (name.isEmpty) return;
                          final occasion = _occasion.text.trim();
                          Navigator.pop(
                            context,
                            _OutfitDetails(
                              name: name,
                              occasion: occasion.isEmpty ? null : occasion,
                            ),
                          );
                        },
                        child: const Text('Save'),
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
  }
}


