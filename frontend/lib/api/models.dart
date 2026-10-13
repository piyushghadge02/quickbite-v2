/// Typed request/response models for the QuickBite v2 `/api/v1` contract.
///
/// Conventions:
/// * Money is an integer number of minor units (paise) — never a double.
/// * Timestamps are tz-aware ISO-8601 strings; parsed to [DateTime].
/// * All `fromJson` constructors are defensive: missing optional keys fall
///   back to documented defaults instead of throwing.
library;

int _asInt(Object? v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? fallback);

String _asString(Object? v, [String fallback = '']) =>
    v is String ? v : (v == null ? fallback : '$v');

DateTime _asDateTime(Object? v) =>
    v is String ? DateTime.parse(v) : DateTime.now().toUtc();

/// Generic paginated envelope `{items, page, page_size, total}`.
class PagedResult<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  const PagedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  factory PagedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final raw = (json['items'] as List?) ?? const [];
    return PagedResult(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(itemFromJson)
          .toList(growable: false),
      page: _asInt(json['page'], 1),
      pageSize: _asInt(json['page_size'], 20),
      total: _asInt(json['total']),
    );
  }

  bool get hasMore => items.length < total;
}

// --- auth ---------------------------------------------------------------

class User {
  final String id;
  final String email;
  final String name;
  final String role;
  final DateTime? createdAt;

  const User({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.createdAt,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: _asString(json['id']),
        email: _asString(json['email']),
        name: _asString(json['name']),
        role: _asString(json['role'], 'customer'),
        createdAt:
            json['created_at'] is String ? DateTime.parse(json['created_at']) : null,
      );
}

class LoginResponse {
  final String accessToken;
  final String tokenType;
  final DateTime expiresAt;
  final String role;
  final User user;

  const LoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
    required this.role,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
        accessToken: _asString(json['access_token']),
        tokenType: _asString(json['token_type'], 'bearer'),
        expiresAt: _asDateTime(json['expires_at']),
        role: _asString(json['role'], 'customer'),
        user: User.fromJson((json['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

// --- catalog ------------------------------------------------------------

class Restaurant {
  final String id;
  final String name;
  final String address;
  final bool isActive;
  final String? imageUrl;
  final String? cuisine;
  final String? description;
  final double? rating;
  final int? deliveryTimeMinutes;

  const Restaurant({
    required this.id,
    required this.name,
    required this.address,
    required this.isActive,
    this.imageUrl,
    this.cuisine,
    this.description,
    this.rating,
    this.deliveryTimeMinutes,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) => Restaurant(
        id: _asString(json['id']),
        name: _asString(json['name'], 'Unnamed restaurant'),
        address: _asString(json['address']),
        isActive: json['is_active'] != false,
        imageUrl: json['image_url'] as String?,
        cuisine: json['cuisine'] as String?,
        description: json['description'] as String?,
        rating: json['rating'] is num ? (json['rating'] as num).toDouble() : null,
        deliveryTimeMinutes: _asInt(json['delivery_time_minutes']),
      );
}

class MenuItem {
  final String id;
  final String restaurantId;
  final String name;
  final int priceMinor;
  final String currency;
  final bool isAvailable;

  const MenuItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.priceMinor,
    required this.currency,
    required this.isAvailable,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: _asString(json['id']),
        restaurantId: _asString(json['restaurant_id']),
        name: _asString(json['name'], 'Unnamed item'),
        priceMinor: _asInt(json['price_minor']),
        currency: _asString(json['currency'], 'INR'),
        isAvailable: json['is_available'] != false,
      );
}

// --- checkout -----------------------------------------------------------

class CheckoutItemInput {
  final String menuItemId;
  final int quantity;

  const CheckoutItemInput({required this.menuItemId, required this.quantity});

  Map<String, dynamic> toJson() =>
      {'menu_item_id': menuItemId, 'quantity': quantity};
}

class CheckoutRequest {
  final String restaurantId;
  final String deliveryAddress;
  final List<CheckoutItemInput> items;

  const CheckoutRequest({
    required this.restaurantId,
    required this.deliveryAddress,
    required this.items,
  });

  /// Canonical JSON used both for the wire body and for the persisted
  /// idempotency record, so "same payload" comparisons are stable.
  Map<String, dynamic> toJson() {
    final sorted = [...items]
      ..sort((a, b) => a.menuItemId.compareTo(b.menuItemId));
    return {
      'restaurant_id': restaurantId,
      'delivery_address': deliveryAddress.trim(),
      'items': sorted.map((i) => i.toJson()).toList(),
    };
  }
}

class CheckoutAccepted {
  final String orderId;
  final String status;
  final String currency;
  final int totalAmountMinor;
  final int version;
  final String message;

  const CheckoutAccepted({
    required this.orderId,
    required this.status,
    required this.currency,
    required this.totalAmountMinor,
    required this.version,
    required this.message,
  });

  factory CheckoutAccepted.fromJson(Map<String, dynamic> json) =>
      CheckoutAccepted(
        orderId: _asString(json['order_id']),
        status: _asString(json['status'], 'PENDING'),
        currency: _asString(json['currency'], 'INR'),
        totalAmountMinor: _asInt(json['total_amount_minor']),
        version: _asInt(json['version'], 1),
        message: _asString(json['message']),
      );
}

// --- orders -------------------------------------------------------------

class OrderListItem {
  final String id;
  final String restaurantId;
  final String currency;
  final int totalMinor;
  final String status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OrderListItem({
    required this.id,
    required this.restaurantId,
    required this.currency,
    required this.totalMinor,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrderListItem.fromJson(Map<String, dynamic> json) => OrderListItem(
        id: _asString(json['id']),
        restaurantId: _asString(json['restaurant_id']),
        currency: _asString(json['currency'], 'INR'),
        totalMinor: _asInt(json['total_minor']),
        status: _asString(json['status'], 'PENDING'),
        version: _asInt(json['version'], 1),
        createdAt: _asDateTime(json['created_at']),
        updatedAt: _asDateTime(json['updated_at']),
      );
}

class OrderLineItem {
  final String menuItemId;
  final String itemName;
  final int quantity;
  final int unitPriceMinor;

  const OrderLineItem({
    required this.menuItemId,
    required this.itemName,
    required this.quantity,
    required this.unitPriceMinor,
  });

  factory OrderLineItem.fromJson(Map<String, dynamic> json) => OrderLineItem(
        menuItemId: _asString(json['menu_item_id']),
        itemName: _asString(json['item_name']),
        quantity: _asInt(json['quantity'], 1),
        unitPriceMinor: _asInt(json['unit_price_minor']),
      );
}

class OrderDetail {
  final String id;
  final String customerId;
  final String restaurantId;
  final String deliveryAddress;
  final String currency;
  final int totalMinor;
  final String status;
  final int version;
  final String? failureCode;
  final String? driverId;
  final String? driverName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<OrderLineItem> items;

  const OrderDetail({
    required this.id,
    required this.customerId,
    required this.restaurantId,
    required this.deliveryAddress,
    required this.currency,
    required this.totalMinor,
    required this.status,
    required this.version,
    this.failureCode,
    this.driverId,
    this.driverName,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  factory OrderDetail.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return OrderDetail(
      id: _asString(json['id']),
      customerId: _asString(json['customer_id']),
      restaurantId: _asString(json['restaurant_id']),
      deliveryAddress: _asString(json['delivery_address']),
      currency: _asString(json['currency'], 'INR'),
      totalMinor: _asInt(json['total_minor']),
      status: _asString(json['status'], 'PENDING'),
      version: _asInt(json['version'], 1),
      failureCode: json['failure_code'] as String?,
      driverId: json['driver_id'] as String?,
      driverName: json['driver_name'] as String?,
      createdAt: _asDateTime(json['created_at']),
      updatedAt: _asDateTime(json['updated_at']),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(OrderLineItem.fromJson)
          .toList(growable: false),
    );
  }
}

class HistoryEntry {
  final String? fromStatus;
  final String toStatus;
  final int version;
  final String? note;
  final DateTime createdAt;

  const HistoryEntry({
    this.fromStatus,
    required this.toStatus,
    required this.version,
    this.note,
    required this.createdAt,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        fromStatus: json['from_status'] as String?,
        toStatus: _asString(json['to_status']),
        version: _asInt(json['version']),
        note: json['note'] as String?,
        createdAt: _asDateTime(json['created_at']),
      );
}

class AppNotification {
  final int id;
  final String eventId;
  final String eventType;
  final String orderId;
  final String title;
  final String body;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.eventId,
    required this.eventType,
    required this.orderId,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: _asInt(json['id']),
        eventId: _asString(json['event_id']),
        eventType: _asString(json['event_type']),
        orderId: _asString(json['order_id']),
        title: _asString(json['title']),
        body: _asString(json['body']),
        createdAt: _asDateTime(json['created_at']),
      );
}

// --- admin --------------------------------------------------------------

class AdminSummary {
  final Map<String, int> ordersByStatus;
  final int outboxPending;
  final int outboxScheduled;
  final int retriesScheduled;
  final int quarantineTotal;

  const AdminSummary({
    required this.ordersByStatus,
    required this.outboxPending,
    required this.outboxScheduled,
    required this.retriesScheduled,
    required this.quarantineTotal,
  });

  factory AdminSummary.fromJson(Map<String, dynamic> json) {
    final raw = (json['orders_by_status'] as Map?) ?? const {};
    return AdminSummary(
      ordersByStatus: raw.map(
        (k, v) => MapEntry('$k', _asInt(v)),
      ),
      outboxPending: _asInt(json['outbox_pending']),
      outboxScheduled: _asInt(json['outbox_scheduled']),
      retriesScheduled: _asInt(json['retries_scheduled']),
      quarantineTotal: _asInt(json['quarantine_total']),
    );
  }
}
