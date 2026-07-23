import '../../../core/network/api_client.dart';
import '../../outfits/data/outfit_repository.dart';
import '../../outfits/domain/outfit_preview.dart';
import '../../outfits/domain/outfit_item_layout.dart';
import '../../wardrobe/data/wardrobe_repository.dart';
import '../../wardrobe/domain/clothing_item_draft.dart';

/// Keeps Creative Space deliberately thin: it composes the existing wardrobe
/// and outfit repositories instead of introducing a second API surface.
final class CreativeRepository {
  CreativeRepository({WardrobeRepository? wardrobe, OutfitRepository? outfits})
    : _wardrobe = wardrobe ?? WardrobeRepository(ApiClient()),
      _outfits = outfits ?? OutfitRepository(ApiClient());

  final WardrobeRepository _wardrobe;
  final OutfitRepository _outfits;

  Future<List<ClothingItemDraft>> loadWardrobe() =>
      _wardrobe.list();

  Future<void> saveOutfit({
    
    required List<ClothingItemDraft> items,
    required String name,
    required List<OutfitItemLayout> itemLayout,
    String? occasion,
    String? outfitId,
    required String idempotencyKey,
  }) {
    final ids = <String>{};
    final distinctItems = <ClothingItemDraft>[];
    for (final item in items) {
      if (ids.add(item.id)) distinctItems.add(item);
    }
    final preview = OutfitPreview(
      name: name,
      occasion: occasion,
      rationale: 'Created in Studio',
      itemIds: distinctItems.map((item) => item.id).toList(),
      items: distinctItems,
    );
    if (outfitId != null) {
      return _outfits.update(
        
        outfitId: outfitId,
        name: name,
        occasion: occasion,
        itemIds: preview.itemIds,
        itemLayout: itemLayout,
      );
    }
    return _outfits.save(
      
      idempotencyKey: idempotencyKey,
      preview: preview,
      itemLayout: itemLayout,
    );
  }
}


