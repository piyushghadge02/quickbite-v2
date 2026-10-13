/// Order history (customer) and admin overview (read-only) state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import 'providers.dart';

// --- customer order history ------------------------------------------------

class OrdersListState {
  final List<OrderListItem> items;
  final String? statusFilter;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final bool hasMore;

  const OrdersListState({
    this.items = const [],
    this.statusFilter,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.hasMore = true,
  });

  OrdersListState copyWith({
    List<OrderListItem>? items,
    String? Function()? statusFilter,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool? hasMore,
  }) =>
      OrdersListState(
        items: items ?? this.items,
        statusFilter:
            statusFilter != null ? statusFilter() : this.statusFilter,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        errorMessage: errorMessage,
        hasMore: hasMore ?? this.hasMore,
      );
}

class OrdersListNotifier extends Notifier<OrdersListState> {
  static const _pageSize = 20;
  int _page = 1;

  @override
  OrdersListState build() {
    Future.microtask(() => refresh());
    return const OrdersListState(isLoading: true);
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> refresh() => _load(reset: true);

  Future<void> setStatusFilter(String? status) async {
    state = state.copyWith(statusFilter: () => status);
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      _page = 1;
      state = state.copyWith(isLoading: true, errorMessage: null);
    } else {
      if (state.isLoadingMore || !state.hasMore) return;
      state = state.copyWith(isLoadingMore: true);
    }
    try {
      final page = await _api.orders(
        status: state.statusFilter,
        page: _page,
        pageSize: _pageSize,
      );
      _page += 1;
      state = state.copyWith(
        items: reset ? page.items : [...state.items, ...page.items],
        isLoading: false,
        isLoadingMore: false,
        hasMore: page.hasMore,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        errorMessage: e.message,
      );
    }
  }

  Future<void> loadMore() => _load(reset: false);
}

// --- admin overview (read-only) --------------------------------------------

class AdminOrdersState extends OrdersListState {
  const AdminOrdersState({
    super.items,
    super.statusFilter,
    super.isLoading,
    super.isLoadingMore,
    super.errorMessage,
    super.hasMore,
  });

  @override
  AdminOrdersState copyWith({
    List<OrderListItem>? items,
    String? Function()? statusFilter,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool? hasMore,
  }) =>
      AdminOrdersState(
        items: items ?? this.items,
        statusFilter:
            statusFilter != null ? statusFilter() : this.statusFilter,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        errorMessage: errorMessage,
        hasMore: hasMore ?? this.hasMore,
      );
}

class AdminOrdersNotifier extends Notifier<AdminOrdersState> {
  static const _pageSize = 20;
  int _page = 1;

  @override
  AdminOrdersState build() {
    Future.microtask(() => refresh());
    return const AdminOrdersState(isLoading: true);
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> refresh() => _load(reset: true);

  Future<void> setStatusFilter(String? status) async {
    state = state.copyWith(statusFilter: () => status);
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      _page = 1;
      state = state.copyWith(isLoading: true, errorMessage: null);
    } else {
      if (state.isLoadingMore || !state.hasMore) return;
      state = state.copyWith(isLoadingMore: true);
    }
    try {
      final page = await _api.adminOrders(
        status: state.statusFilter,
        page: _page,
        pageSize: _pageSize,
      );
      _page += 1;
      state = state.copyWith(
        items: reset ? page.items : [...state.items, ...page.items],
        isLoading: false,
        isLoadingMore: false,
        hasMore: page.hasMore,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        errorMessage: e.message,
      );
    }
  }

  Future<void> loadMore() => _load(reset: false);
}

class AdminSummaryState {
  final AdminSummary? summary;
  final bool isLoading;
  final String? errorMessage;

  const AdminSummaryState({this.summary, this.isLoading = false, this.errorMessage});
}

class AdminSummaryNotifier extends Notifier<AdminSummaryState> {
  @override
  AdminSummaryState build() {
    Future.microtask(refresh);
    return const AdminSummaryState(isLoading: true);
  }

  Future<void> refresh() async {
    state = const AdminSummaryState(isLoading: true);
    try {
      final summary = await ref.read(apiClientProvider).adminSummary();
      state = AdminSummaryState(summary: summary);
    } on ApiException catch (e) {
      state = AdminSummaryState(errorMessage: e.message);
    }
  }
}
