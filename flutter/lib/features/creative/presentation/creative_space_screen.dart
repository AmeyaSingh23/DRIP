import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../wardrobe/domain/clothing_item_draft.dart';
import '../data/creative_repository.dart';
import '../../outfits/domain/outfit_item_layout.dart';

final class CreativeRouteArgs {
  const CreativeRouteArgs({
    required this.token,
    this.initialItems,
    this.initialName,
    this.initialOccasion,
    this.initialLayout,
    this.editingOutfitId,
    this.startCollapsed,
  });

  final String token;
  final List<ClothingItemDraft>? initialItems;
  final String? initialName;
  final String? initialOccasion;
  final List<OutfitItemLayout>? initialLayout;
  final String? editingOutfitId;
  final bool? startCollapsed;
}

enum _CanvasZone { accessories, shoes, bottoms, tops, outerwear }

class CreativeSpaceScreen extends StatefulWidget {
  const CreativeSpaceScreen({
    required this.token,
    this.initialItems,
    this.initialName,
    this.initialOccasion,
    this.initialLayout,
    this.editingOutfitId,
    this.startCollapsed,
    super.key,
  });

  final String token;
  final List<ClothingItemDraft>? initialItems;
  final String? initialName;
  final String? initialOccasion;
  final List<OutfitItemLayout>? initialLayout;
  final String? editingOutfitId;
  final bool? startCollapsed;

  @override
  State<CreativeSpaceScreen> createState() => _CreativeSpaceScreenState();
}

class _CreativeSpaceScreenState extends State<CreativeSpaceScreen> {
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
  final Map<_CanvasZone, ClothingItemDraft> _placed = {};
  final Map<_CanvasZone, Offset> _itemOffsets = {};
  List<ClothingItemDraft> _items = const [];
  String _selectedCategory = 'All';
  String _outfitName = 'Styled outfit';
  String? _occasion;
  String? _saveIdempotencyKey;
  _CanvasZone? _selectedZone;
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
  Rect get _accessoriesRect => Rect.fromCenter(
    center: const Offset(2000, 1940),
    width: 300,
    height: 620,
  );
  Rect get _shoesRect =>
      Rect.fromCenter(center: const Offset(2000, 2290), width: 190, height: 95);
  Rect get _bottomsRect => Rect.fromCenter(
    center: const Offset(2000, 2040),
    width: 220,
    height: 265,
  );
  Rect get _topsRect => Rect.fromCenter(
    center: const Offset(2000, 1775),
    width: 220,
    height: 265,
  );
  Rect get _outerwearRect => Rect.fromCenter(
    center: const Offset(2000, 1770),
    width: 255,
    height: 290,
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
      final zone = _zoneFromLayout(layout.zone);
      if (item == null || zone == null) continue;
      _placed[zone] = item;
      _itemOffsets[zone] = Offset(layout.offsetX, layout.offsetY);
      restoredIds.add(item.id);
    }
    for (final item in initialItems) {
      if (!restoredIds.contains(item.id)) _autoPlace(item);
    }
    _loadWardrobe();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _loadWardrobe() async {
    final epoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repository.loadWardrobe(token: widget.token);
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _items = items;
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

  _CanvasZone _zoneFor(ClothingItemDraft item) {
    if (item.category == 'Tops' || item.category == 'Uniform') {
      return _CanvasZone.tops;
    }
    if (item.category == 'Outerwear') return _CanvasZone.outerwear;
    if (item.category == 'Bottoms' || item.category == 'Dresses') {
      return _CanvasZone.bottoms;
    }
    if (item.category == 'Shoes') return _CanvasZone.shoes;
    return _CanvasZone.accessories;
  }

  bool _canDropOn(ClothingItemDraft item, _CanvasZone zone) {
    if (item.category == 'Dresses') {
      return zone == _CanvasZone.tops || zone == _CanvasZone.bottoms;
    }
    return _zoneFor(item) == zone;
  }

  Rect _zoneRect(_CanvasZone zone) => switch (zone) {
    _CanvasZone.accessories => _accessoriesRect,
    _CanvasZone.shoes => _shoesRect,
    _CanvasZone.bottoms => _bottomsRect,
    _CanvasZone.tops => _topsRect,
    _CanvasZone.outerwear => _outerwearRect,
  };

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
    if (item.category == 'Dresses') {
      _placed[_CanvasZone.tops] = item;
      _placed[_CanvasZone.bottoms] = item;
      _itemOffsets[_CanvasZone.tops] = Offset.zero;
      _itemOffsets[_CanvasZone.bottoms] = Offset.zero;
      return;
    }
    final zone = _zoneFor(item);
    _placed[zone] = item;
    _itemOffsets[zone] = Offset.zero;
  }

  void _place(ClothingItemDraft item, _CanvasZone zone) {
    setState(() {
      _saveIdempotencyKey = null;
      if (item.category == 'Dresses') {
        _autoPlace(item);
      } else {
        _placed[zone] = item;
        _itemOffsets[zone] = Offset.zero;
      }
    });
  }

  void _startMove(_CanvasZone zone) {
    setState(() {
      _selectedZone = zone;
      _longPressStartOffset = _itemOffsets[zone] ?? Offset.zero;
    });
  }

  void _moveItem(_CanvasZone zone, LongPressMoveUpdateDetails details) {
    final scale = _transform.value.getMaxScaleOnAxis();
    setState(() {
      _saveIdempotencyKey = null;
      _selectedZone = zone;
      _itemOffsets[zone] =
          _longPressStartOffset + details.offsetFromOrigin / scale;
    });
  }

  void _nudge(Offset delta) {
    final zone = _selectedZone;
    if (zone == null || !_placed.containsKey(zone)) return;
    setState(() {
      _saveIdempotencyKey = null;
      _itemOffsets[zone] = (_itemOffsets[zone] ?? Offset.zero) + delta;
    });
  }

  void _deselectIfOutside(PointerDownEvent event) {
    final zone = _selectedZone;
    if (zone == null) return;
    final scenePoint = _transform.toScene(event.localPosition);
    final itemBounds = _zoneRect(zone).shift(_itemOffsets[zone] ?? Offset.zero);
    if (!itemBounds.contains(scenePoint)) {
      setState(() => _selectedZone = null);
    }
  }

  void _remove(_CanvasZone zone) {
    final item = _placed[zone];
    setState(() {
      _saveIdempotencyKey = null;
      if (item == null) {
        _placed.remove(zone);
        _itemOffsets.remove(zone);
      } else {
        final matching =
            _placed.entries
                .where((entry) => entry.value.id == item.id)
                .map((entry) => entry.key)
                .toList();
        for (final matchingZone in matching) {
          _placed.remove(matchingZone);
          _itemOffsets.remove(matchingZone);
        }
        if (matching.contains(_selectedZone)) _selectedZone = null;
      }
    });
  }

  List<ClothingItemDraft> get _placedItems {
    final seen = <String>{};
    return _CanvasZone.values
        .map((zone) => _placed[zone])
        .whereType<ClothingItemDraft>()
        .where((item) => seen.add(item.id))
        .toList();
  }

  List<OutfitItemLayout> get _itemLayout =>
      _CanvasZone.values
          .map((zone) {
            final item = _placed[zone];
            if (item == null) return null;
            final offset = _itemOffsets[zone] ?? Offset.zero;
            return OutfitItemLayout(
              itemId: item.id,
              zone: _layoutZone(zone),
              offsetX: offset.dx,
              offsetY: offset.dy,
            );
          })
          .whereType<OutfitItemLayout>()
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
        token: widget.token,
        items: items,
        name: _outfitName,
        itemLayout: _itemLayout,
        occasion: _occasion,
        outfitId: widget.editingOutfitId,
        idempotencyKey: _saveIdempotencyKey ??= const Uuid().v4(),
      );
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
      _selectedZone = null;
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
    const scale = 1.0;
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Studio'),
      actions: [
        IconButton(
          tooltip: 'Focus mannequin',
          onPressed: _focusMannequin,
          icon: const Icon(Icons.center_focus_strong),
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
                const VerticalDivider(width: 1),
                Expanded(child: _canvas()),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
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
                    onPressed: _saving || _placed.isEmpty ? null : _clearAll,
                    icon: const Icon(Icons.layers_clear_outlined),
                    label: const Text('Clear all'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _sidebar() => AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeInOut,
    width: _sidebarCollapsed ? 36 : 116,
    color: Theme.of(context).colorScheme.surface,
    child:
        _sidebarCollapsed
            ? Align(
              alignment: Alignment.topCenter,
              child: IconButton(
                tooltip: 'Show wardrobe',
                onPressed: () => setState(() => _sidebarCollapsed = false),
                icon: const Icon(Icons.chevron_right),
              ),
            )
            : Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Hide wardrobe',
                    onPressed: () => setState(() => _sidebarCollapsed = true),
                    icon: const Icon(Icons.chevron_left),
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
                      return ChoiceChip(
                        label: Text(category),
                        selected: category == _selectedCategory,
                        onSelected:
                            (_) => setState(() => _selectedCategory = category),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: _itemList()),
              ],
            ),
  );

  Widget _itemList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: TextButton(
            onPressed: _loadWardrobe,
            child: const Text('Retry'),
          ),
        ),
      );
    }
    final items = _filteredItems;
    if (items.isEmpty) return const Center(child: Text('No items'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder:
          (context, index) =>
              SizedBox(height: 126, child: _draggableItem(items[index])),
    );
  }

  Widget _draggableItem(ClothingItemDraft item) {
    final thumbnail = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(
              child: Image.network(
                item.cloudinaryUrl,
                fit: BoxFit.contain,
                errorBuilder:
                    (_, _, _) => const Icon(Icons.image_not_supported),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.itemName ?? item.category,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
    return Draggable<ClothingItemDraft>(
      data: item,
      feedback: Opacity(
        opacity: .72,
        child: SizedBox(width: 96, height: 126, child: thumbnail),
      ),
      childWhenDragging: Opacity(opacity: .35, child: thumbnail),
      child: thumbnail,
    );
  }

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      _scheduleInitialView(Size(constraints.maxWidth, constraints.maxHeight));
      return Container(
        color: const Color(0xFFFAFAF8),
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
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
              if (_selectedZone != null && _placed.containsKey(_selectedZone))
                Positioned(right: 12, bottom: 12, child: _nudgeControls()),
            ],
          ),
        ),
      );
    },
  );

  Widget _canvasStack() => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(child: CustomPaint(painter: _GridPainter())),
      Positioned.fill(
        child: DragTarget<ClothingItemDraft>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails:
              (details) => _place(details.data, _zoneFor(details.data)),
          builder:
              (_, candidates, _) => DecoratedBox(
                decoration: BoxDecoration(
                  border:
                      candidates.isEmpty
                          ? null
                          : Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                ),
              ),
        ),
      ),
      Positioned.fromRect(
        rect: _dummyRect,
        child: IgnorePointer(child: _croppedDummy()),
      ),
      _dropZone(_CanvasZone.shoes),
      _dropZone(_CanvasZone.bottoms),
      _dropZone(_CanvasZone.tops),
      _dropZone(_CanvasZone.outerwear),
      _placedLayer(_CanvasZone.accessories),
      _placedLayer(_CanvasZone.shoes),
      _placedLayer(_CanvasZone.bottoms),
      _placedLayer(_CanvasZone.tops),
      _placedLayer(_CanvasZone.outerwear),
      ..._CanvasZone.values.where(_placed.containsKey).map(_removeButton),
    ],
  );

  Widget _placedLayer(_CanvasZone zone) =>
      Positioned.fromRect(rect: _zoneRect(zone), child: _placedItem(zone));

  Widget _dropZone(_CanvasZone zone) => Positioned.fromRect(
    rect: _zoneRect(zone),
    child: DragTarget<ClothingItemDraft>(
      onWillAcceptWithDetails: (details) => _canDropOn(details.data, zone),
      onAcceptWithDetails: (details) => _place(details.data, zone),
      builder:
          (context, candidates, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border:
                  candidates.isEmpty
                      ? null
                      : Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 4,
                      ),
              boxShadow:
                  candidates.isEmpty
                      ? null
                      : [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .25),
                          blurRadius: 18,
                          spreadRadius: 3,
                        ),
                      ],
            ),
            child: const SizedBox.expand(),
          ),
    ),
  );

  Widget _placedItem(_CanvasZone zone) {
    final item = _placed[zone];
    if (item == null) return const SizedBox.expand();
    return Transform.translate(
      offset: _itemOffsets[zone] ?? Offset.zero,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _startMove(zone),
        onLongPressMoveUpdate: (details) => _moveItem(zone, details),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border:
                _selectedZone == zone
                    ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    )
                    : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Image.network(
              item.cloudinaryUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported),
            ),
          ),
        ),
      ),
    );
  }

  Widget _removeButton(_CanvasZone zone) {
    final rect = _zoneRect(zone);
    final offset = _itemOffsets[zone] ?? Offset.zero;
    return Positioned(
      left: rect.right + offset.dx - 20,
      top: rect.top + offset.dy - 12,
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _remove(zone),
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: Icon(Icons.close, size: 17, color: Colors.white),
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

  Widget _nudgeControls() => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
    elevation: 4,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Move', style: TextStyle(fontSize: 11)),
          IconButton(
            tooltip: 'Move up',
            onPressed: () => _nudge(const Offset(0, -8)),
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Move left',
                onPressed: () => _nudge(const Offset(-8, 0)),
                icon: const Icon(Icons.keyboard_arrow_left),
              ),
              IconButton(
                tooltip: 'Move right',
                onPressed: () => _nudge(const Offset(8, 0)),
                icon: const Icon(Icons.keyboard_arrow_right),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Move down',
            onPressed: () => _nudge(const Offset(0, 8)),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 40.0;
    final paint =
        Paint()
          ..color = const Color(0xFFDDD9E5)
          ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
  }

  @override
  void dispose() {
    _name.dispose();
    _occasion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save outfit'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Outfit name'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _occasion,
          maxLength: 50,
          decoration: const InputDecoration(
            labelText: 'Occasion (optional)',
            hintText: 'College, dinner, date night...',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
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
  );
}
