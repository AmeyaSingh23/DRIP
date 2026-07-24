import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/auth_controller.dart';
import '../../data/wardrobe_repository.dart';
import '../../domain/clothing_item_draft.dart';
import '../wardrobe_change_notifier.dart';

final wardrobeRepositoryProvider = Provider<WardrobeRepository>(
  (ref) => WardrobeRepository(ref.watch(apiClientProvider)),
);

class WardrobeState {
  final List<ClothingItemDraft> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final int offset;
  final String category;
  final String search;
  final bool hasLoaded;
  final String? error;

  WardrobeState({
    required this.items,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.offset,
    required this.category,
    required this.search,
    required this.hasLoaded,
    this.error,
  });

  factory WardrobeState.initial() {
    return WardrobeState(
      items: const [],
      loading: true,
      loadingMore: false,
      hasMore: true,
      offset: 0,
      category: 'All',
      search: '',
      hasLoaded: false,
    );
  }

  WardrobeState copyWith({
    List<ClothingItemDraft>? items,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    int? offset,
    String? category,
    String? search,
    bool? hasLoaded,
    String? error,
  }) {
    return WardrobeState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      category: category ?? this.category,
      search: search ?? this.search,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      error: error,
    );
  }
}

final wardrobeItemsProvider =
    NotifierProvider<WardrobeItemsNotifier, WardrobeState>(
      WardrobeItemsNotifier.new,
    );

class WardrobeItemsNotifier extends Notifier<WardrobeState> {
  late WardrobeRepository _repository;

  @override
  WardrobeState build() {
    _repository = ref.read(wardrobeRepositoryProvider);
    ref.listen(wardrobeRevisionProvider, (prev, next) {
      load(refresh: true);
    });
    return WardrobeState.initial();
  }

  Future<void> load({bool refresh = false}) async {
    final current = state;
    int offset = refresh ? 0 : current.offset;
    bool hasMore = refresh ? true : current.hasMore;

    if (!hasMore || ((current.loading || current.loadingMore) && !refresh)) return;

    state = state.copyWith(
      loading: (refresh || !current.hasLoaded) && current.items.isEmpty,
      loadingMore: !refresh && current.items.isNotEmpty,
      error: null,
    );

    try {
      final items = await _repository.list(
        category: state.category,
        search: state.search,
        limit: 30,
        offset: offset,
      );

      final newItems = refresh ? items : [...state.items, ...items];
      state = state.copyWith(
        items: newItems,
        offset: offset + items.length,
        hasMore: items.length == 30,
        loading: false,
        loadingMore: false,
        hasLoaded: true,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: e.toString(),
      );
    }
  }

  void updateCategory(String category) {
    if (state.category == category) return;
    state = state.copyWith(category: category, items: const [], offset: 0, hasMore: true);
    load(refresh: true);
  }

  void updateSearch(String search) {
    if (state.search == search) return;
    state = state.copyWith(search: search, items: const [], offset: 0, hasMore: true);
    load(refresh: true);
  }

  // Prepend a newly added item instantly to the cached list
  void addOptimistically(ClothingItemDraft newItem) {
    state = state.copyWith(
      items: [newItem, ...state.items],
    );
  }

  // Optimistic Archive/Delete support
  Future<void> archiveOptimistically(ClothingItemDraft item) async {
    final originalItems = [...state.items];
    
    // Optimistically remove from state
    state = state.copyWith(
      items: state.items.where((i) => i.id != item.id).toList(),
    );

    try {
      await _repository.archive(itemId: item.id);
    } catch (e) {
      // Revert on failure
      state = state.copyWith(
        items: originalItems,
        error: "Failed to archive item: ${e.toString()}",
      );
      rethrow;
    }
  }

  Future<void> deleteOptimistically(ClothingItemDraft item) async {
    final originalItems = [...state.items];
    
    // Optimistically remove from state
    state = state.copyWith(
      items: state.items.where((i) => i.id != item.id).toList(),
    );

    try {
      await _repository.permanentlyErase(itemId: item.id);
    } catch (e) {
      // Revert on failure
      state = state.copyWith(
        items: originalItems,
        error: "Failed to delete item: ${e.toString()}",
      );
      rethrow;
    }
  }
}
