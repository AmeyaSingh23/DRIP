import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/outfit_preview.dart';
import '../domain/outfit_item_layout.dart';
import '../domain/outfit_weather.dart';
import '../domain/saved_outfit.dart';

final class OutfitRepository {
  OutfitRepository(this._client);

  final ApiClient _client;

  Future<OutfitPreview> generate({
    required String token,
    String? occasion,
    String? styleNotes,
    OutfitLocation? location,
    DateTime? wearAt,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/outfits/generate',
      data: {
        if (occasion != null && occasion.trim().isNotEmpty)
          'occasion': occasion.trim(),
        if (styleNotes != null && styleNotes.trim().isNotEmpty)
          'style_notes': styleNotes.trim(),
        if (location != null) 'location': location.toJson(),
        if (wearAt != null) 'wear_at': wearAt.toIso8601String(),
      },
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    return OutfitPreview.fromJson(response.data!);
  }

  Future<List<OutfitLocation>> searchLocations({
    required String token,
    required String query,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.dio.get<List<dynamic>>(
      '/api/v1/outfits/locations',
      queryParameters: {'query': query},
      cancelToken: cancelToken,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        receiveTimeout: const Duration(seconds: 3),
      ),
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(OutfitLocation.fromJson)
        .toList();
  }

  Future<WeatherContextResult> weatherContext({
    required String token,
    required OutfitLocation location,
    required DateTime wearAt,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/outfits/weather-context',
      data: {'location': location.toJson(), 'wear_at': wearAt.toIso8601String()},
      cancelToken: cancelToken,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 6),
      ),
    );
    return WeatherContextResult.fromJson(response.data!);
  }

  Future<void> save({
    required String token,
    required OutfitPreview preview,
    required List<OutfitItemLayout> itemLayout,
    required String idempotencyKey,
  }) => _client.dio.post<void>(
    '/api/v1/outfits',
    data: {
      'name': preview.name,
      'occasion': preview.occasion,
      'item_ids': preview.itemIds,
      'item_layout': itemLayout.map((entry) => entry.toJson()).toList(),
      'is_ai_generated': true,
    },
    options: Options(
      headers: {
        'Authorization': 'Bearer $token',
        'Idempotency-Key': idempotencyKey,
      },
    ),
  );

  Future<List<SavedOutfit>> list({required String token}) async {
    final response = await _client.dio.get<List<dynamic>>(
      '/api/v1/outfits',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SavedOutfit.fromJson)
        .toList();
  }

  Future<SavedOutfit> get({
    required String token,
    required String outfitId,
  }) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/outfits/$outfitId',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return SavedOutfit.fromJson(response.data!);
  }

  Future<SavedOutfit> update({
    required String token,
    required String outfitId,
    String? name,
    String? occasion,
    List<String>? itemIds,
    List<OutfitItemLayout>? itemLayout,
  }) async {
    final response = await _client.dio.patch<Map<String, dynamic>>(
      '/api/v1/outfits/$outfitId',
      data: {
        'name': name,
        'occasion': occasion,
        if (itemIds != null) 'item_ids': itemIds,
        if (itemLayout != null)
          'item_layout': itemLayout.map((entry) => entry.toJson()).toList(),
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return SavedOutfit.fromJson(response.data!);
  }

  Future<void> delete({required String token, required String outfitId}) =>
      _client.dio.delete<void>(
        '/api/v1/outfits/$outfitId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
}
