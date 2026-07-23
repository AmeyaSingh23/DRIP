import 'package:flutter/material.dart';

class WardrobeSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;

  const WardrobeSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  State<WardrobeSearchBar> createState() => _WardrobeSearchBarState();
}

class _WardrobeSearchBarState extends State<WardrobeSearchBar> {
  bool _isExpanded = false;

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (!_isExpanded) {
        widget.controller.clear();
        widget.onChanged();
        widget.focusNode.unfocus();
      } else {
        widget.focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassColor = isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.5);
    final borderColor = isDark ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.8);

    return TapRegion(
      onTapOutside: (_) {
        if (_isExpanded) _toggle();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: _isExpanded ? 240 : 48,
        height: 40,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: _isExpanded ? glassColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: _isExpanded ? Border.all(color: borderColor, width: 1.5) : null,
          boxShadow: _isExpanded
              ? [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    blurRadius: 8,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: _isExpanded ? 240 : 48,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _isExpanded ? () => widget.focusNode.requestFocus() : _toggle,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (_isExpanded) ...[
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      onChanged: (_) => widget.onChanged(),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.only(bottom: 2), // vertically center text
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        if (widget.controller.text.isNotEmpty) {
                          widget.controller.clear();
                          widget.onChanged();
                        } else {
                          _toggle();
                        }
                      },
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}


