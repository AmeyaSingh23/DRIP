import '../../wardrobe/domain/clothing_item_draft.dart';

class OutfitPreview {
  const OutfitPreview({
    required this.name,
    required this.rationale,
    required this.itemIds,
    required this.items,
    this.occasion,
  });

  factory OutfitPreview.fromJson(Map<String, dynamic> json) => OutfitPreview(
    name: json['name'] as String,
    occasion: json['occasion'] as String?,
    rationale: json['rationale'] as String,
    itemIds: (json['item_ids'] as List<dynamic>).cast<String>(),
    items:
        (json['items'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(ClothingItemDraft.fromJson)
            .toList(),
  );

  final String name;
  final String? occasion;
  final String rationale;
  final List<String> itemIds;
  final List<ClothingItemDraft> items;
}
