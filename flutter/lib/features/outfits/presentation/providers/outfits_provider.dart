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
  final bool hasLoaded;
  final String? error;

  OutfitsState({
    required this.outfits,
    required this.loading,
    required this.hasLoaded,
    this.error,
  });

  factory OutfitsState.initial() {
    return OutfitsState(
      outfits: const [],
      loading: true,
      hasLoaded: false,
    );
  }

  OutfitsState copyWith({
    List<SavedOutfit>? outfits,
    bool? loading,
    bool? hasLoaded,
    String? error,
  }) {
    return OutfitsState(
      outfits: outfits ?? this.outfits,
      loading: loading ?? this.loading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      error: error,
    );
  }
}


final outfitsProvider =
    NotifierProvider<OutfitsNotifier, OutfitsState>(
      OutfitsNotifier.new,
    );

class OutfitsNotifier extends Notifier<OutfitsState> {
  late OutfitRepository _repository;
  bool _requestInFlight = false;
  bool _refreshPending = false;

  @override
  OutfitsState build() {
    _repository = ref.read(outfitRepositoryProvider);
    ref.listen(outfitRevisionProvider, (prev, next) {
      load(refresh: true);
    });
    return OutfitsState.initial();
  }

  Future<void> load({bool refresh = false}) async {
    if (_requestInFlight) {
      if (refresh) _refreshPending = true;
      return;
    }
    if (!refresh && state.hasLoaded && !state.loading) return;

    _requestInFlight = true;

    state = state.copyWith(loading: state.outfits.isEmpty || refresh, error: null);

    try {
      final outfits = await _repository.list();
      state = state.copyWith(
        outfits: outfits,
        loading: false,
        hasLoaded: true,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );
    } finally {
      _requestInFlight = false;
      if (_refreshPending) {
        _refreshPending = false;
        await load(refresh: true);
      }
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
