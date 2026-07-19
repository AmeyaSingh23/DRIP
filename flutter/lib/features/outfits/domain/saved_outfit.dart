import '../../wardrobe/domain/clothing_item_draft.dart';
import 'outfit_item_layout.dart';

class SavedOutfit {
  const SavedOutfit({
    required this.id,
    required this.items,
    required this.isAiGenerated,
    required this.itemLayout,
    this.name,
    this.occasion,
  });

  factory SavedOutfit.fromJson(Map<String, dynamic> json) => SavedOutfit(
    id: json['id'] as String,
    name: json['name'] as String?,
    occasion: json['occasion'] as String?,
    isAiGenerated: json['is_ai_generated'] as bool? ?? false,
    itemLayout:
        (json['item_layout'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OutfitItemLayout.fromJson)
            .toList(),
    items:
        (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClothingItemDraft.fromJson)
            .toList(),
  );

  final String id;
  final String? name;
  final String? occasion;
  final bool isAiGenerated;
  final List<OutfitItemLayout> itemLayout;
  final List<ClothingItemDraft> items;
}
