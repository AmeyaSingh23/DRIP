import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/auth_controller.dart';
import '../../data/outfit_repository.dart';
import '../../domain/saved_outfit.dart';
import '../../../wardrobe/presentation/wardrobe_change_notifier.dart';

final outfitRepositoryProvider = Provider<OutfitRepository>(
  (ref) => OutfitRepository(ref.watch(apiClientProvider)),
);

class OutfitsState {
  final List<SavedOutfit> outfits;
  final bool loading;
  final String? error;

  OutfitsState({
    required this.outfits,
    required this.loading,
    this.error,
  });

  factory OutfitsState.initial() {
    return OutfitsState(
      outfits: const [],
      loading: false,
    );
  }

  OutfitsState copyWith({
    List<SavedOutfit>? outfits,
    bool? loading,
    String? error,
  }) {
    return OutfitsState(
      outfits: outfits ?? this.outfits,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}


final outfitsProvider =
    NotifierProvider<OutfitsNotifier, OutfitsState>(
      OutfitsNotifier.new,
    );

class OutfitsNotifier extends Notifier<OutfitsState> {
  late final OutfitRepository _repository;

  @override
  OutfitsState build() {
    _repository = ref.watch(outfitRepositoryProvider);
    ref.listen(outfitRevisionProvider, (prev, next) {
      load(refresh: true);
    });
    return OutfitsState.initial();
  }

  Future<void> load({bool refresh = false}) async {
    if (state.loading) return;

    state = state.copyWith(loading: state.outfits.isEmpty || refresh, error: null);

    try {
      final outfits = await _repository.list();
      state = state.copyWith(
        outfits: outfits,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );
    }
  }

  void addOptimistically(SavedOutfit newOutfit) {
    state = state.copyWith(
      outfits: [newOutfit, ...state.outfits],
    );
  }

  Future<void> archiveOptimistically(SavedOutfit outfit) async {
    final originalOutfits = [...state.outfits];

    state = state.copyWith(
      outfits: state.outfits.where((o) => o.id != outfit.id).toList(),
    );

    try {
      await _repository.archive(outfitId: outfit.id);
    } catch (e) {
      state = state.copyWith(
        outfits: originalOutfits,
        error: "Failed to archive outfit: ${e.toString()}",
      );
      rethrow;
    }
  }
}
