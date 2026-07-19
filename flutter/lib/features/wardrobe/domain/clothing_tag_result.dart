final class ClothingTagResult {
  const ClothingTagResult({
    required this.category,
    required this.confidence,
    required this.isWornOnPerson,
    this.customCategory,
    this.color,
    this.pattern,
    this.fabric,
    this.itemName,
    this.tags = const [],
  });

  factory ClothingTagResult.fromJson(Map<String, dynamic> json) =>
      ClothingTagResult(
        category: json['category'] as String? ?? 'Custom',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        isWornOnPerson: json['is_worn_on_person'] as bool? ?? false,
        customCategory: json['custom_category'] as String?,
        color: json['color'] as String?,
        pattern: json['pattern'] as String?,
        fabric: json['fabric'] as String?,
        itemName: json['item_name'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
      );

  final String category;
  final double confidence;
  final bool isWornOnPerson;
  final String? customCategory;
  final String? color;
  final String? pattern;
  final String? fabric;
  final String? itemName;
  final List<String> tags;
}
