import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A lightweight, app-wide refresh signal for active wardrobe data.
///
/// Screens keep their own request/loading state, while every successful
/// wardrobe mutation increments this value so mounted consumers reload.
final wardrobeRevisionProvider =
    NotifierProvider<WardrobeRevisionNotifier, int>(
      WardrobeRevisionNotifier.new,
    );

final class WardrobeRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void notifyChanged() => state++;
}
