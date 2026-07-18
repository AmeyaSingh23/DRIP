import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../domain/clothing_item_draft.dart';
import '../domain/clothing_item_usage.dart';

final class WardrobeRepository {
  WardrobeRepository(this._client);

  final ApiClient _client;

  Future<ClothingItemDraft> upload({
    required File cutout,
    required File taggingImage,
    required String token,
    required String idempotencyKey,
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
        headers: {
          'Authorization': 'Bearer $token',
          'Idempotency-Key': idempotencyKey,
        },
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    return ClothingItemDraft.fromJson(response.data!);
  }

  Future<ClothingItemDraft> manualUpload({
    required File cutout,
    required String token,
    required String itemName,
    required String category,
    required String color,
    required String idempotencyKey,
    String? customCategory,
  }) async {
    final form = FormData.fromMap({
      'cutout': await MultipartFile.fromFile(
        cutout.path,
        filename: 'cutout.png',
        contentType: MediaType('image', 'png'),
      ),
      'item_name': itemName,
      'category': category,
      'color': color,
      if (customCategory != null) 'custom_category': customCategory,
    });
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/items/manual',
      data: form,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Idempotency-Key': idempotencyKey,
        },
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    return ClothingItemDraft.fromJson(response.data!);
  }

  Future<ClothingItemDraft> update({
    required ClothingItemDraft draft,
    required String token,
    String? itemName,
    String? category,
    String? customCategory,
    String? color,
  }) async {
    final response = await _client.dio.patch<Map<String, dynamic>>(
      '/api/v1/items/${draft.id}',
      data: {
        'item_name': itemName,
        'category': category,
        'custom_category': customCategory,
        'color': color,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return ClothingItemDraft.fromJson(response.data!);
  }

  Future<List<ClothingItemDraft>> list({
    required String token,
    String? category,
    String? search,
  }) async {
    final response = await _client.dio.get<List<dynamic>>(
      '/api/v1/items',
      queryParameters: {
        if (category != null && category != 'All') 'category': category,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ClothingItemDraft.fromJson)
        .toList();
  }

  Future<ClothingItemDraft> get({
    required String itemId,
    required String token,
  }) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/items/$itemId',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return ClothingItemDraft.fromJson(response.data!);
  }

  Future<ClothingItemUsage> usage({
    required String itemId,
    required String token,
  }) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/items/$itemId/usage',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return ClothingItemUsage.fromJson(response.data!);
  }

  Future<void> softDelete({required String itemId, required String token}) =>
      _client.dio.delete<void>(
        '/api/v1/items/$itemId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

  Future<void> permanentlyErase({
    required String itemId,
    required String token,
  }) => _client.dio.delete<void>(
    '/api/v1/items/$itemId/permanent',
    options: Options(headers: {'Authorization': 'Bearer $token'}),
  );
}
