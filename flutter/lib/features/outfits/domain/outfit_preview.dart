import '../../wardrobe/domain/clothing_item_draft.dart';
import 'outfit_weather.dart';

class OutfitPreview {
  const OutfitPreview({
    required this.name,
    required this.rationale,
    required this.itemIds,
    required this.items,
    this.occasion,
    this.weatherStatus = 'not_requested',
    this.weatherContext,
    this.isQuickPick = false,
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
    weatherStatus: json['weather_status'] as String? ?? 'not_requested',
    weatherContext: json['weather_context'] is Map<String, dynamic>
        ? OutfitWeatherContext.fromJson(
            json['weather_context'] as Map<String, dynamic>,
          )
        : null,
    isQuickPick: json['is_quick_pick'] as bool? ?? false,
  );

  final String name;
  final String? occasion;
  final String rationale;
  final List<String> itemIds;
  final List<ClothingItemDraft> items;
  final String weatherStatus;
  final OutfitWeatherContext? weatherContext;
  final bool isQuickPick;
}
