import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../wardrobe/domain/clothing_item_draft.dart';
import '../data/creative_repository.dart';

final class CreativeRouteArgs {
  const CreativeRouteArgs({
    required this.token,
    this.initialItems,
    this.startCollapsed,
  });

  final String token;
  final List<ClothingItemDraft>? initialItems;
  final bool? startCollapsed;
}

enum _CanvasZone { accessories, shoes, bottoms, tops, outerwear }

class CreativeSpaceScreen extends StatefulWidget {
  const CreativeSpaceScreen({
    required this.token,
    this.initialItems,
    this.startCollapsed,
    super.key,
  });

  final String token;
  final List<ClothingItemDraft>? initialItems;
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
  static const _canvasSize = Size(680, 960);
  static const _dummyRect = Rect.fromLTWH(160, 95, 360, 710);
  static const _accessoriesRect = Rect.fromLTWH(85, 105, 510, 690);
  static const _shoesRect = Rect.fromLTWH(190, 748, 300, 135);
  static const _bottomsRect = Rect.fromLTWH(168, 448, 344, 330);
  static const _topsRect = Rect.fromLTWH(180, 210, 320, 300);
  static const _outerwearRect = Rect.fromLTWH(145, 185, 390, 350);

  final _repository = CreativeRepository();
  final _transform = TransformationController();
  final Map<_CanvasZone, ClothingItemDraft> _placed = {};
  List<ClothingItemDraft> _items = const [];
  String _selectedCategory = 'All';
  bool _sidebarCollapsed = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _sidebarCollapsed = widget.startCollapsed ?? widget.initialItems != null;
    for (final item in widget.initialItems ?? const <ClothingItemDraft>[]) {
      _autoPlace(item);
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

  _CanvasZone _zoneFor(ClothingItemDraft item) => switch (item.category) {
    'Tops' || 'Uniform' => _CanvasZone.tops,
    'Outerwear' => _CanvasZone.outerwear,
    'Bottoms' || 'Dresses' => _CanvasZone.bottoms,
    'Shoes' => _CanvasZone.shoes,
    _ => _CanvasZone.accessories,
  };

  bool _canDropOn(ClothingItemDraft item, _CanvasZone zone) {
    if (item.category == 'Dresses') {
      return zone == _CanvasZone.tops || zone == _CanvasZone.bottoms;
    }
    return _zoneFor(item) == zone;
  }

  void _autoPlace(ClothingItemDraft item) {
    if (item.category == 'Dresses') {
      _placed[_CanvasZone.tops] = item;
      _placed[_CanvasZone.bottoms] = item;
      return;
    }
    _placed[_zoneFor(item)] = item;
  }

  void _place(ClothingItemDraft item, _CanvasZone zone) {
    setState(() {
      if (item.category == 'Dresses') {
        _autoPlace(item);
      } else {
        _placed[zone] = item;
      }
    });
  }

  void _remove(_CanvasZone zone) {
    final item = _placed[zone];
    setState(() {
      if (item == null) {
        _placed.remove(zone);
      } else {
        _placed.removeWhere((_, placed) => placed.id == item.id);
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

  Future<void> _save() async {
    final items = _placedItems;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item before saving.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _repository.saveOutfit(
        token: widget.token,
        items: items,
        idempotencyKey: const Uuid().v4(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Outfit saved to your wardrobe history.'),
          ),
        );
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

  void _clearAll() => setState(_placed.clear);

  void _resetCanvasView() => _transform.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Studio'),
      actions: [
        IconButton(
          tooltip: 'Reset canvas view',
          onPressed: _resetCanvasView,
          icon: const Icon(Icons.zoom_out_map),
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
                      label: Text(_saving ? 'Saving...' : 'Save as outfit'),
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
    width: _sidebarCollapsed ? 36 : 200,
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
                Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: Text(
                          'Wardrobe',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Hide wardrobe',
                      onPressed: () => setState(() => _sidebarCollapsed = true),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ],
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
                Expanded(child: _itemGrid()),
              ],
            ),
  );

  Widget _itemGrid() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(onPressed: _loadWardrobe, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final items = _filteredItems;
    if (items.isEmpty) return const Center(child: Text('No items'));
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: .72,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _draggableItem(items[index]),
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
        child: SizedBox(width: 96, height: 128, child: thumbnail),
      ),
      childWhenDragging: Opacity(opacity: .35, child: thumbnail),
      child: thumbnail,
    );
  }

  Widget _canvas() => Container(
    color: const Color(0xFFFAFAF8),
    padding: const EdgeInsets.all(16),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: InteractiveViewer(
        transformationController: _transform,
        alignment: Alignment.center,
        minScale: .35,
        maxScale: 3.2,
        boundaryMargin: const EdgeInsets.all(500),
        constrained: false,
        child: SizedBox(
          width: _canvasSize.width,
          height: _canvasSize.height,
          child: _canvasStack(),
        ),
      ),
    ),
  );

  Widget _canvasStack() => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(child: CustomPaint(painter: _GridPainter())),
      // This target sits behind the mannequin. It catches blank-canvas drops
      // and assigns them based on category without blocking body-zone drops.
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
        child: const IgnorePointer(
          child: Image(
            image: AssetImage('assets/images/female_dummy.png'),
            fit: BoxFit.contain,
          ),
        ),
      ),
      _placedOnly(_CanvasZone.accessories, _accessoriesRect),
      _dropZone(_CanvasZone.shoes, _shoesRect),
      _dropZone(_CanvasZone.bottoms, _bottomsRect),
      _dropZone(_CanvasZone.tops, _topsRect),
      _dropZone(_CanvasZone.outerwear, _outerwearRect),
    ],
  );

  Widget _placedOnly(_CanvasZone zone, Rect rect) =>
      Positioned.fromRect(rect: rect, child: _placedItem(zone));

  Widget _dropZone(_CanvasZone zone, Rect rect) => Positioned.fromRect(
    rect: rect,
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
            child: _placedItem(zone),
          ),
    ),
  );

  Widget _placedItem(_CanvasZone zone) {
    final item = _placed[zone];
    if (item == null) return const SizedBox.expand();
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: Image.network(
            item.cloudinaryUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _remove(zone),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 32.0;
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
