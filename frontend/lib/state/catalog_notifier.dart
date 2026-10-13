/// Catalog state: restaurant list and per-restaurant menus (both paginated).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import 'providers.dart';

/// Shared list state: items accumulated across pages, plus loading/error.
class CatalogListState {
  final List<Restaurant> items;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final bool hasMore;

  const CatalogListState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.hasMore = true,
  });

  CatalogListState copyWith({
    List<Restaurant>? items,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool? hasMore,
  }) =>
      CatalogListState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        errorMessage: errorMessage,
        hasMore: hasMore ?? this.hasMore,
      );
}

class RestaurantListNotifier extends Notifier<CatalogListState> {
  static const _pageSize = 20;
  int _page = 1;

  @override
  CatalogListState build() {
    Future.microtask(() => refresh());
    return const CatalogListState(isLoading: true);
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> refresh() async {
    _page = 1;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final page = await _api.restaurants(page: 1, pageSize: _pageSize);
      state = state.copyWith(
        items: page.items,
        isLoading: false,
        hasMore: page.hasMore,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _api.restaurants(page: _page + 1, pageSize: _pageSize);
      _page += 1;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        isLoadingMore: false,
        hasMore: page.hasMore,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingMore: false, errorMessage: e.message);
    }
  }
}

// --- menu ------------------------------------------------------------------

class MenuState {
  final Restaurant? restaurant;
  final List<MenuItem> items;
  final bool isLoading;
  final String? errorMessage;
  final bool hasMore;
  final bool isLoadingMore;

  const MenuState({
    this.restaurant,
    this.items = const [],
    this.isLoading = false,
    this.errorMessage,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  MenuState copyWith({
    Restaurant? restaurant,
    List<MenuItem>? items,
    bool? isLoading,
    String? errorMessage,
    bool? hasMore,
    bool? isLoadingMore,
  }) =>
      MenuState(
        restaurant: restaurant ?? this.restaurant,
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

class MenuNotifier extends FamilyNotifier<MenuState, String> {
  static const _pageSize = 50;
  int _page = 1;

  @override
  MenuState build(String restaurantId) {
    Future.microtask(() => refresh());
    return const MenuState(isLoading: true);
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> refresh() async {
    final restaurantId = arg;
    _page = 1;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final page = await _api.menu(restaurantId, page: 1, pageSize: _pageSize);
      state = state.copyWith(
        items: page.items,
        isLoading: false,
        hasMore: page.hasMore,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page =
          await _api.menu(arg, page: _page + 1, pageSize: _pageSize);
      _page += 1;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        isLoadingMore: false,
        hasMore: page.hasMore,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingMore: false, errorMessage: e.message);
    }
  }
}
