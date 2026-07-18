import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/outfit_preview.dart';

final class OutfitRepository {
  OutfitRepository(this._client);

  final ApiClient _client;

  Future<OutfitPreview> generate({
    required String token,
    String? occasion,
    String? styleNotes,
    String? weatherSummary,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/outfits/generate',
      data: {
        if (occasion != null && occasion.trim().isNotEmpty)
          'occasion': occasion.trim(),
        if (styleNotes != null && styleNotes.trim().isNotEmpty)
          'style_notes': styleNotes.trim(),
        if (weatherSummary != null && weatherSummary.trim().isNotEmpty)
          'weather_summary': weatherSummary.trim(),
      },
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    return OutfitPreview.fromJson(response.data!);
  }

  Future<void> save({required String token, required OutfitPreview preview}) =>
      _client.dio.post<void>(
        '/api/v1/outfits',
        data: {
          'name': preview.name,
          'occasion': preview.occasion,
          'item_ids': preview.itemIds,
          'is_ai_generated': true,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
}
