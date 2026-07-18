import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/wardrobe_repository.dart';
import '../domain/clothing_item_draft.dart';

class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({required this.email, required this.token, super.key});

  final String email;
  final String token;

  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
  static const _baseCategories = [
    'All',
    'Tops',
    'Bottoms',
    'Outerwear',
    'Shoes',
    'Dresses',
    'Accessories',
    'Uniform',
    'Custom',
  ];

  final _repository = WardrobeRepository(ApiClient());
  final _searchController = TextEditingController();
  List<ClothingItemDraft> _items = const [];
  String _selectedCategory = 'All';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repository.list(token: widget.token);
      if (mounted) {
        setState(() {
          _items = items;
          // Custom tabs only exist while at least one active item uses them.
          // A deletion may remove the current tab, so return to a stable view.
          if (!_categories.contains(_selectedCategory)) {
            _selectedCategory = 'All';
          }
        });
      }
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _categories {
    final custom =
        _items
            .where(
              (item) =>
                  item.category == 'Custom' && item.customCategory != null,
            )
            .map((item) => item.customCategory!)
            .toSet()
            .toList()
          ..sort();
    return [..._baseCategories, ...custom];
  }

  List<ClothingItemDraft> get _filteredItems {
    final search = _searchController.text.trim().toLowerCase();
    return _items.where((item) {
      final inCategory =
          _selectedCategory == 'All' ||
          item.category == _selectedCategory ||
          (item.category == 'Custom' &&
              item.customCategory == _selectedCategory);
      if (!inCategory) return false;
      if (search.isEmpty) return true;
      final terms =
          [
            item.itemName,
            item.category,
            item.customCategory,
            item.color,
            item.pattern,
            item.fabric,
            ...item.tags,
          ].whereType<String>().join(' ').toLowerCase();
      return terms.contains(search);
    }).toList();
  }

  String _messageFor(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return 'Could not update your wardrobe. Please try again.';
  }

  Future<void> _edit(ClothingItemDraft item) async {
    final name = TextEditingController(text: item.itemName ?? '');
    final color = TextEditingController(text: item.color ?? '');
    final customCategory = TextEditingController(
      text: item.category == 'Custom' ? item.customCategory ?? '' : '',
    );
    final categories = _baseCategories.sublist(1);
    var category =
        categories.contains(item.category) ? item.category : 'Custom';
    var showCustomCategoryError = false;
    final values = await showDialog<List<String>>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Edit wardrobe item'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          key: const ValueKey('item-name'),
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items:
                              categories
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                category = value;
                                showCustomCategoryError = false;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        Visibility(
                          visible: category == 'Custom',
                          child: TextField(
                            key: const ValueKey('custom-category'),
                            controller: customCategory,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 100,
                            decoration: InputDecoration(
                              labelText: 'Custom category',
                              hintText: 'For example: Activewear',
                              errorText:
                                  showCustomCategoryError
                                      ? 'Enter a custom category name.'
                                      : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('item-color'),
                          controller: color,
                          decoration: const InputDecoration(labelText: 'Color'),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (category == 'Custom' &&
                            customCategory.text.trim().isEmpty) {
                          setDialogState(() => showCustomCategoryError = true);
                          return;
                        }
                        Navigator.pop(context, [
                          name.text.trim(),
                          category,
                          category == 'Custom'
                              ? customCategory.text.trim()
                              : '',
                          color.text.trim(),
                        ]);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
    name.dispose();
    color.dispose();
    customCategory.dispose();
    if (values == null) return;
    try {
      await _repository.update(
        draft: item,
        token: widget.token,
        itemName: values[0],
        category: values[1],
        customCategory: values[2].isEmpty ? null : values[2],
        color: values[3],
      );
      await _load();
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    }
  }

  Future<void> _delete(
    ClothingItemDraft item, {
    required bool permanent,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              permanent ? 'Permanently erase item?' : 'Remove from wardrobe?',
            ),
            content: Text(
              permanent
                  ? 'This removes the image from Cloudinary and cannot be undone.'
                  : 'This hides the item from your wardrobe while preserving saved outfit history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style:
                    permanent
                        ? FilledButton.styleFrom(backgroundColor: Colors.red)
                        : null,
                child: Text(permanent ? 'Erase permanently' : 'Remove'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      if (permanent) {
        await _repository.permanentlyErase(
          itemId: item.id,
          token: widget.token,
        );
      } else {
        await _repository.softDelete(itemId: item.id, token: widget.token);
      }
      await _load();
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    }
  }

  void _showActions(ClothingItemDraft item) {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit item'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _edit(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: const Text('Remove from wardrobe'),
                  subtitle: const Text('Preserves saved outfit history'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _delete(item, permanent: false);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Permanently erase',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _delete(item, permanent: true);
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wardrobe'),
        actions: [
          IconButton(
            onPressed: () async {
              await context.push('/wardrobe/upload', extra: widget.token);
              _load();
            },
            tooltip: 'Add wardrobe item',
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search wardrobe',
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  return ChoiceChip(
                    label: Text(category),
                    selected: _selectedCategory == category,
                    onSelected:
                        (_) => setState(() => _selectedCategory = category),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(child: Text(_error!))
                      : items.isEmpty
                      ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text(
                              'No wardrobe items here yet. Add your first item.',
                            ),
                          ),
                        ],
                      )
                      : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.72,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return InkWell(
                            onTap: () => _edit(item),
                            onLongPress: () => _showActions(item),
                            borderRadius: BorderRadius.circular(16),
                            child: Ink(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAFAF8),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Image.network(
                                        item.cloudinaryUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (_, _, _) => const Icon(
                                              Icons.image_not_supported,
                                            ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.itemName ?? item.category,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          [
                                            item.color,
                                            item.pattern,
                                          ].whereType<String>().join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
