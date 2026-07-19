import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

final _wardrobeCache = CacheManager(
  Config(
    'la-maison-de-miniso-wardrobe-thumbnails',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 180,
  ),
);

class CachedWardrobeImage extends StatelessWidget {
  const CachedWardrobeImage({
    required this.url,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    super.key,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  String get _thumbnailUrl {
    const marker = '/upload/';
    final index = url.indexOf(marker);
    if (index < 0) return url;
    return '${url.substring(0, index + marker.length)}f_auto,q_auto,w_640/${url.substring(index + marker.length)}';
  }

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    imageUrl: _thumbnailUrl,
    cacheManager: _wardrobeCache,
    fit: fit,
    width: width,
    height: height,
    fadeInDuration: const Duration(milliseconds: 120),
    placeholder: (_, _) => const Center(child: CircularProgressIndicator()),
    errorWidget: (_, _, _) => const Icon(Icons.image_not_supported),
  );
}
