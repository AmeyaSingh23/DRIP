import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../domain/clothing_item_draft.dart';
import '../domain/clothing_tag_result.dart';
import '../domain/clothing_item_usage.dart';

final class WardrobeRepository {
  WardrobeRepository(this._client);

  final ApiClient _client;

  Future<Uint8List> removeBackground({
    required File image,
    
  }) async {
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        image.path,
        filename: 'garment.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    });
    final response = await _client.dio.post<List<int>>(
      '/api/v1/items/cutout',
      data: form,
      options: Options(
        
        responseType: ResponseType.bytes,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Background removal returned an empty image.');
    }
    return Uint8List.fromList(bytes);
  }

  Future<ClothingTagResult> tag({
    required File taggingImage,
    
  }) async {
    final form = FormData.fromMap({
      'tagging_image': await MultipartFile.fromFile(
        taggingImage.path,
        filename: 'tagging.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    });
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/items/tag',
      data: form,
      options: Options(
        
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    return ClothingTagResult.fromJson(response.data!);
  }

  Future<ClothingItemDraft> manualUpload({
    required File cutout,
    
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
      
    );
    return ClothingItemDraft.fromJson(response.data!);
  }

  Future<List<ClothingItemDraft>> list({
    
    String? category,
    String? search,
    bool archived = false,
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await _client.dio.get<List<dynamic>>(
      '/api/v1/items',
      queryParameters: {
        if (category != null && category != 'All') 'category': category,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (archived) 'archived': true,
        'limit': limit,
        'offset': offset,
      },
      
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ClothingItemDraft.fromJson)
        .toList();
  }

  Future<ClothingItemDraft> get({
    required String itemId,
    
  }) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/items/$itemId',
      
    );
    return ClothingItemDraft.fromJson(response.data!);
  }

  Future<ClothingItemUsage> usage({
    required String itemId,
    int offset = 0,
    int limit = 5,
    
  }) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/items/$itemId/usage',
      queryParameters: {'offset': offset, 'limit': limit},
      
    );
    return ClothingItemUsage.fromJson(response.data!);
  }

  Future<void> archive({required String itemId, }) =>
      _client.dio.delete<void>(
        '/api/v1/items/$itemId',
        
      );

  Future<void> permanentlyErase({
    required String itemId,
    
  }) => _client.dio.delete<void>(
    '/api/v1/items/$itemId/permanent',
    
  );

  Future<ClothingItemDraft> restore({
    required String itemId,
    
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/items/$itemId/restore',
      
    );
    return ClothingItemDraft.fromJson(response.data!);
  }
}


