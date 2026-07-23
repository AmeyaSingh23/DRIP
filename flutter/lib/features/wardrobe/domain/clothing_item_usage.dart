class ClothingItemUsage {
  const ClothingItemUsage({
    required this.outfitCount,
    this.outfits = const [],
    this.calendarHistory = const [],
  });

  factory ClothingItemUsage.fromJson(Map<String, dynamic> json) =>
      ClothingItemUsage(
        outfitCount: json['outfit_count'] as int? ?? 0,
        outfits:
            (json['outfits'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(OutfitUsage.fromJson)
                .toList(),
        calendarHistory:
            (json['calendar_history'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(CalendarUsage.fromJson)
                .toList(),
      );

  final int outfitCount;
  final List<OutfitUsage> outfits;
  final List<CalendarUsage> calendarHistory;
}

class OutfitUsage {
  const OutfitUsage({required this.id, this.name});

  factory OutfitUsage.fromJson(Map<String, dynamic> json) => OutfitUsage(
    id: json['outfit_id'] as String,
    name: json['outfit_name'] as String?,
  );

  final String id;
  final String? name;
}

class CalendarUsage {
  const CalendarUsage({
    required this.date,
    required this.slot,
    required this.outfitId,
    this.outfitName,
  });

  factory CalendarUsage.fromJson(Map<String, dynamic> json) => CalendarUsage(
    date: DateTime.parse(json['entry_date'] as String),
    slot: json['slot'] as String,
    outfitId: json['outfit_id'] as String,
    outfitName: json['outfit_name'] as String?,
  );

  final DateTime date;
  final String slot;
  final String outfitId;
  final String? outfitName;
}


