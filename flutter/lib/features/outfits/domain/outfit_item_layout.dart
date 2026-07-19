final class OutfitItemLayout {
  const OutfitItemLayout({
    required this.itemId,
    required this.zone,
    required this.offsetX,
    required this.offsetY,
  });

  factory OutfitItemLayout.fromJson(Map<String, dynamic> json) =>
      OutfitItemLayout(
        itemId: json['item_id'] as String,
        zone: json['zone'] as String,
        offsetX: (json['offset_x'] as num).toDouble(),
        offsetY: (json['offset_y'] as num).toDouble(),
      );

  final String itemId;
  final String zone;
  final double offsetX;
  final double offsetY;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'zone': zone,
    'offset_x': offsetX,
    'offset_y': offsetY,
  };
}
