class ClothingItemDraft {
  const ClothingItemDraft({
    required this.id,
    required this.cloudinaryUrl,
    required this.category,
    this.customCategory,
    this.color,
    this.pattern,
    this.fabric,
    this.isUniform = false,
    this.itemName,
    this.tags = const [],
    this.aiConfidence = 0,
    this.userVerified = false,
    this.createdAt,
    this.archivedAt,
  });

  factory ClothingItemDraft.fromJson(Map<String, dynamic> json) =>
      ClothingItemDraft(
        id: json['id'] as String,
        cloudinaryUrl: json['cloudinary_url'] as String,
        category: json['category'] as String? ?? 'Custom',
        customCategory: json['custom_category'] as String?,
        color: json['color'] as String?,
        pattern: json['pattern'] as String?,
        fabric: json['fabric'] as String?,
        isUniform: json['is_uniform'] as bool? ?? false,
        itemName: json['item_name'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
        aiConfidence:
            (json['ai_confidence'] as num?)?.toDouble() ??
            (json['confidence'] as num?)?.toDouble() ??
            0,
        userVerified: json['user_verified'] as bool? ?? false,
        createdAt:
            json['created_at'] is String
                ? DateTime.tryParse(json['created_at'] as String)
                : null,
        archivedAt:
            json['archived_at'] is String
                ? DateTime.tryParse(json['archived_at'] as String)
                : null,
      );

  final String id;
  final String cloudinaryUrl;
  final String category;
  final String? customCategory;
  final String? color;
  final String? pattern;
  final String? fabric;
  final bool isUniform;
  final String? itemName;
  final List<String> tags;
  final double aiConfidence;
  final bool userVerified;
  final DateTime? createdAt;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'cloudinary_url': cloudinaryUrl,
    'category': category,
    'custom_category': customCategory,
    'color': color,
    'pattern': pattern,
    'fabric': fabric,
    'is_uniform': isUniform,
    'item_name': itemName,
    'tags': tags,
    'ai_confidence': aiConfidence,
    'user_verified': userVerified,
    'created_at': createdAt?.toIso8601String(),
    'archived_at': archivedAt?.toIso8601String(),
  };
}


