final class UserStats {
  const UserStats({required this.totalItems, required this.savedOutfits});

  final int totalItems;
  final int savedOutfits;

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalItems: json['total_items'] as int,
      savedOutfits: json['saved_outfits'] as int,
    );
  }

  UserStats copyWith({
    int? totalItems,
    int? savedOutfits,
  }) {
    return UserStats(
      totalItems: totalItems ?? this.totalItems,
      savedOutfits: savedOutfits ?? this.savedOutfits,
    );
  }
}
