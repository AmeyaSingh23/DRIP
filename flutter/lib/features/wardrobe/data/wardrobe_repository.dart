import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../domain/clothing_item_draft.dart';

final class WardrobeRepository {
  WardrobeRepository(this._client);

  final ApiClient _client;

  Future<ClothingItemDraft> upload({
    required File cutout,
    required File taggingImage,
    required String token,
  }) async {
    final form = FormData.fromMap({
      'cutout': await MultipartFile.fromFile(
        cutout.path,
        filename: 'cutout.png',
        contentType: MediaType('image', 'png'),
      ),
      'tagging_image': await MultipartFile.fromFile(
        taggingImage.path,
        filename: 'tagging.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    });
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/items/upload',
      data: form,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    return ClothingItemDraft.fromJson(response.data!);
  }

  Future<ClothingItemDraft> update({
    required ClothingItemDraft draft,
    required String token,
    String? itemName,
    String? category,
    String? color,
  }) async {
    final response = await _client.dio.patch<Map<String, dynamic>>(
      '/api/v1/items/${draft.id}',
      data: {'item_name': itemName, 'category': category, 'color': color},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return ClothingItemDraft.fromJson(response.data!);
  }
}
