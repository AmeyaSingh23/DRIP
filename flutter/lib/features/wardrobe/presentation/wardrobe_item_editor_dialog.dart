import 'dart:ui';
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

  void _showCategoryPicker() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]!.withOpacity(0.85)
                : Colors.white.withOpacity(0.85),
            child: SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: _categories.map((c) => ListTile(
                  title: Text(c, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
                  onTap: () {
                    setState(() {
                      _category = c;
                      _showCustomCategoryError = false;
                    });
                    Navigator.pop(context);
                  },
                )).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _solidField({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: child,
      ),
    );
  }

  Widget _charCounter(TextEditingController controller, int max) {
    return Align(
      alignment: Alignment.centerRight,
      child: ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, child) => Padding(
          padding: const EdgeInsets.only(top: 4, right: 4),
          child: Text(
            '${value.text.length}/$max',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final solidSurface = Theme.of(context).colorScheme.surface;
    final primaryColor = Theme.of(context).colorScheme.primary;

    InputDecoration fieldDecoration(String hint, {bool isDropdown = false}) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
        filled: true,
        fillColor: Colors.transparent,
        counterText: "",
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
        ),
        suffixIcon: isDropdown ? Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.onSurface) : null,
      );
    }
    
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]!.withOpacity(0.50)
                : Colors.white.withOpacity(0.50),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _fieldLabel('Name'),
                        _solidField(
                          child: TextField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            maxLength: 120,
                            decoration: fieldDecoration('Enter item name'),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                        _charCounter(_name, 120),
                        const SizedBox(height: 10),
                        _fieldLabel('Category'),
                        _solidField(
                          child: InkWell(
                            onTap: _showCategoryPicker,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: fieldDecoration('Select a category', isDropdown: true),
                              isEmpty: _category.isEmpty,
                              child: Text(_category, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16)),
                            ),
                          ),
                        ),
                        if (_category == 'Custom') ...[
                          const SizedBox(height: 14),
                          _fieldLabel('Custom Category'),
                          _solidField(
                            child: TextField(
                              controller: _customCategory,
                              textCapitalization: TextCapitalization.words,
                              maxLength: 100,
                              decoration: fieldDecoration('Enter custom category').copyWith(
                                errorText:
                                    _showCustomCategoryError
                                        ? 'Enter a custom category name.'
                                        : null,
                              ),
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                            ),
                          ),
                          _charCounter(_customCategory, 100),
                        ],
                        const SizedBox(height: 10),
                        _fieldLabel('Color'),
                        _solidField(
                          child: TextField(
                            controller: _color,
                            maxLength: 50,
                            decoration: fieldDecoration('Enter color'),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                        _charCounter(_color, 50),
                      ],
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
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.onSurface,
                        foregroundColor: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onPrimary,
                      ),
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
