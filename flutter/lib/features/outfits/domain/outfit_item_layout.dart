final class OutfitItemLayout {
  const OutfitItemLayout({
    required this.itemId,
    required this.zone,
    required this.offsetX,
    required this.offsetY,
    this.scale = 1,
  });

  factory OutfitItemLayout.fromJson(Map<String, dynamic> json) =>
      OutfitItemLayout(
        itemId: json['item_id'] as String,
        zone: json['zone'] as String,
        offsetX: (json['offset_x'] as num).toDouble(),
        offsetY: (json['offset_y'] as num).toDouble(),
        scale: (json['scale'] as num?)?.toDouble() ?? 1,
      );

  final String itemId;
  final String zone;
  final double offsetX;
  final double offsetY;
  final double scale;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'zone': zone,
    'offset_x': offsetX,
    'offset_y': offsetY,
    'scale': scale,
  };
}
