import 'package:flutter/material.dart';

import '../domain/clothing_item_draft.dart';

class ItemEditValues {
  const ItemEditValues({
    required this.itemName,
    required this.category,
    required this.color,
    this.customCategory,
  });

  final String itemName;
  final String category;
  final String color;
  final String? customCategory;
}

class WardrobeItemEditorDialog extends StatefulWidget {
  const WardrobeItemEditorDialog({
    required this.item,
    required this.title,
    super.key,
  });

  final ClothingItemDraft item;
  final String title;

  @override
  State<WardrobeItemEditorDialog> createState() =>
      _WardrobeItemEditorDialogState();
}

class _WardrobeItemEditorDialogState extends State<WardrobeItemEditorDialog> {
  static const _categories = [
    'Tops',
    'Bottoms',
    'Outerwear',
    'Shoes',
    'Dresses',
    'Accessories',
    'Uniform',
    'Custom',
  ];

  late final TextEditingController _name;
  late final TextEditingController _color;
  late final TextEditingController _customCategory;
  late String _category;
  bool _showCustomCategoryError = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.itemName ?? '');
    _color = TextEditingController(text: widget.item.color ?? '');
    _customCategory = TextEditingController(
      text:
          widget.item.category == 'Custom'
              ? widget.item.customCategory ?? ''
              : '',
    );
    _category =
        _categories.contains(widget.item.category)
            ? widget.item.category
            : 'Custom';
  }

  @override
  void dispose() {
    _name.dispose();
    _color.dispose();
    _customCategory.dispose();
    super.dispose();
  }

  void _save() {
    if (_category == 'Custom' && _customCategory.text.trim().isEmpty) {
      setState(() => _showCustomCategoryError = true);
      return;
    }
    Navigator.pop(
      context,
      ItemEditValues(
        itemName: _name.text.trim(),
        category: _category,
        customCategory:
            _category == 'Custom' ? _customCategory.text.trim() : null,
        color: _color.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey(_category),
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items:
                _categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _category = value;
                  _showCustomCategoryError = false;
                });
              }
            },
          ),
          const SizedBox(height: 14),
          Visibility(
            visible: _category == 'Custom',
            maintainState: true,
            child: TextField(
              controller: _customCategory,
              textCapitalization: TextCapitalization.words,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: 'Custom category',
                hintText: 'For example: Activewear',
                errorText:
                    _showCustomCategoryError
                        ? 'Enter a custom category name.'
                        : null,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _color,
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
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
