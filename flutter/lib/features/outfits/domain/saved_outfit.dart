import '../../wardrobe/domain/clothing_item_draft.dart';

class SavedOutfit {
  const SavedOutfit({
    required this.id,
    required this.items,
    required this.isAiGenerated,
    this.name,
    this.occasion,
  });

  factory SavedOutfit.fromJson(Map<String, dynamic> json) => SavedOutfit(
    id: json['id'] as String,
    name: json['name'] as String?,
    occasion: json['occasion'] as String?,
    isAiGenerated: json['is_ai_generated'] as bool? ?? false,
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
  final List<ClothingItemDraft> items;
}
