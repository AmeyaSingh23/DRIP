import '../../../core/network/api_client.dart';
import '../../outfits/data/outfit_repository.dart';
import '../../outfits/domain/outfit_preview.dart';
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

  Future<List<ClothingItemDraft>> loadWardrobe({required String token}) =>
      _wardrobe.list(token: token);

  Future<void> saveOutfit({
    required String token,
    required List<ClothingItemDraft> items,
    required String name,
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
        token: token,
        outfitId: outfitId,
        name: name,
        occasion: occasion,
        itemIds: preview.itemIds,
      );
    }
    return _outfits.save(
      token: token,
      idempotencyKey: idempotencyKey,
      preview: preview,
    );
  }
}
