import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/user_stats.dart';
import '../../../auth/presentation/auth_controller.dart';

import '../../../wardrobe/presentation/wardrobe_change_notifier.dart';

final profileStatsProvider =
    NotifierProvider<ProfileStatsNotifier, AsyncValue<UserStats>>(
      ProfileStatsNotifier.new,
    );

class ProfileStatsNotifier extends Notifier<AsyncValue<UserStats>> {
  late AuthRepository _authRepository;

  @override
  AsyncValue<UserStats> build() {
    _authRepository = ref.read(authRepositoryProvider);
    ref.listen(wardrobeRevisionProvider, (prev, next) {
      load();
    });
    ref.listen(outfitRevisionProvider, (prev, next) {
      load();
    });
    // Trigger initial load.
    Future.microtask(() => load());
    return const AsyncValue.loading();
  }

  Future<void> load() async {
    try {
      final stats = await _authRepository.stats();
      state = AsyncValue.data(stats);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void incrementItems() {
    state.whenData((current) {
      state = AsyncValue.data(
        current.copyWith(totalItems: current.totalItems + 1),
      );
    });
  }

  void decrementItems() {
    state.whenData((current) {
      state = AsyncValue.data(
        current.copyWith(totalItems: (current.totalItems - 1).clamp(0, 99999)),
      );
    });
  }

  void incrementOutfits() {
    state.whenData((current) {
      state = AsyncValue.data(
        current.copyWith(savedOutfits: current.savedOutfits + 1),
      );
    });
  }

  void decrementOutfits() {
    state.whenData((current) {
      state = AsyncValue.data(
        current.copyWith(savedOutfits: (current.savedOutfits - 1).clamp(0, 99999)),
      );
    });
  }
}
