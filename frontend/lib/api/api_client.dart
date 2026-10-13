/// Centralized HTTP client for the QuickBite v2 `/api/v1` contract.
///
/// All API access in the app goes through [ApiClient]; widgets and notifiers
/// never touch `package:http` directly. The client owns:
/// * base URL joining, JSON encode/decode, default timeouts;
/// * the `Authorization: Bearer <token>` header (token set by the auth
///   notifier after sign-in and cleared on sign-out);
/// * mapping of the `{code,message,details,request_id}` error envelope and
///   transport failures into the typed [ApiException] hierarchy.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'models.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _http;

  /// Called on HTTP 401 so the auth layer can sign the user out.
  final void Function()? onUnauthorized;

  String? _authToken;

  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.onUnauthorized,
  }) : _http = httpClient ?? http.Client();

  void setAuthToken(String? token) => _authToken = token;

  void close() => _http.close();

  // --- low-level ---------------------------------------------------------

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(
        queryParameters: query == null || query.isEmpty ? null : query,
      );

  Map<String, String> _headers({String? idempotencyKey}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      };

  dynamic _decode(http.Response res) {
    if (res.body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(res.body);
    } on FormatException {
      throw ApiException(
        code: 'BAD_RESPONSE',
        message: 'The server returned a response the app could not read.',
        statusCode: res.statusCode,
      );
    }
  }

  Never _throwForStatus(http.Response res) {
    final body = _decode(res);
    final envelope =
        body is Map<String, dynamic> ? body : <String, dynamic>{'message': 'Request failed'};
    final ex = ApiException.fromEnvelope(envelope, statusCode: res.statusCode);
    switch (res.statusCode) {
      case 401:
        onUnauthorized?.call();
        throw UnauthorizedException(message: ex.message, requestId: ex.requestId);
      case 403:
        throw ForbiddenException(message: ex.message, requestId: ex.requestId);
      case 404:
        throw NotFoundException(message: ex.message, requestId: ex.requestId);
      case 409:
        throw ConflictException(message: ex.message, requestId: ex.requestId);
      case 422:
        throw ValidationException(
            message: ex.message, details: ex.details, requestId: ex.requestId);
      default:
        throw ex;
    }
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    late final http.Response res;
    try {
      res = await call().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const NetworkException(
          message: 'The request timed out. Check your connection and retry.');
    } on SocketException {
      throw const NetworkException(
          message: 'Could not reach the QuickBite server. Check your connection.');
    } on http.ClientException catch (e) {
      throw NetworkException(message: 'Network error: ${e.message}');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    _throwForStatus(res); // Never returns — it always throws.
  }

  Future<Map<String, dynamic>> _getJson(String path,
      {Map<String, String>? query}) async {
    final res = await _send(() => _http.get(_uri(path, query), headers: _headers()));
    final body = _decode(res);
    if (body is! Map<String, dynamic>) {
      throw const ApiException(code: 'BAD_RESPONSE', message: 'Unexpected response shape.');
    }
    return body;
  }

  Future<(http.Response, Map<String, dynamic>)> _postRaw(
    String path,
    Map<String, dynamic> json, {
    String? idempotencyKey,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    late http.Response res;
    try {
      res = await _http
          .post(_uri(path),
              headers: _headers(idempotencyKey: idempotencyKey),
              body: jsonEncode(json))
          .timeout(timeout);
    } on TimeoutException {
      throw const NetworkException(
          message: 'The request timed out. Your order may still have been '
              'accepted — use “Retry safely”.');
    } on SocketException {
      throw const NetworkException(
          message: 'Could not reach the QuickBite server. Your order may still '
              'have been accepted — use “Retry safely”.');
    } on http.ClientException catch (e) {
      throw NetworkException(message: 'Network error: ${e.message}');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = _decode(res);
      if (body is! Map<String, dynamic>) {
        throw const ApiException(
            code: 'BAD_RESPONSE', message: 'Unexpected response shape.');
      }
      return (res, body);
    }
    _throwForStatus(res);
  }

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> json,
          {String? idempotencyKey}) async =>
      (await _postRaw(path, json, idempotencyKey: idempotencyKey)).$2;

  // --- auth --------------------------------------------------------------

  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final body = await _postJson('/api/v1/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    return LoginResponse.fromJson(body);
  }

  Future<User> me() async => User.fromJson(await _getJson('/api/v1/me'));

  // --- catalog -----------------------------------------------------------

  Future<PagedResult<Restaurant>> restaurants({int page = 1, int pageSize = 20}) async {
    final body = await _getJson('/api/v1/restaurants', query: {
      'page': '$page',
      'page_size': '$pageSize',
    });
    return PagedResult.fromJson(body, Restaurant.fromJson);
  }

  Future<PagedResult<MenuItem>> menu(String restaurantId,
      {int page = 1, int pageSize = 50}) async {
    final body = await _getJson('/api/v1/restaurants/$restaurantId/menu', query: {
      'page': '$page',
      'page_size': '$pageSize',
    });
    return PagedResult.fromJson(body, MenuItem.fromJson);
  }

  // --- orders ------------------------------------------------------------

  /// Creates an order. Expects HTTP 202 with a `Location` header.
  /// The caller MUST supply a fresh-or-reused `Idempotency-Key`.
  Future<CheckoutAccepted> createOrder(
    CheckoutRequest request, {
    required String idempotencyKey,
  }) async {
    final (res, body) = await _postRaw(
      '/api/v1/orders',
      request.toJson(),
      idempotencyKey: idempotencyKey,
    );
    if (res.statusCode != 202) {
      throw const ApiException(
          code: 'UNEXPECTED_STATUS',
          message: 'The server did not accept the order as expected.');
    }
    return CheckoutAccepted.fromJson(body);
  }

  Future<PagedResult<OrderListItem>> orders({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final body = await _getJson('/api/v1/orders', query: {
      if (status != null && status.isNotEmpty) 'status': status,
      'page': '$page',
      'page_size': '$pageSize',
    });
    return PagedResult.fromJson(body, OrderListItem.fromJson);
  }

  Future<OrderDetail> order(String orderId) async =>
      OrderDetail.fromJson(await _getJson('/api/v1/orders/$orderId'));

  Future<List<HistoryEntry>> orderHistory(String orderId) async {
    final res = await _send(
        () => _http.get(_uri('/api/v1/orders/$orderId/history'), headers: _headers()));
    final body = _decode(res);
    if (body is! List) {
      throw const ApiException(code: 'BAD_RESPONSE', message: 'Unexpected response shape.');
    }
    return body
        .whereType<Map<String, dynamic>>()
        .map(HistoryEntry.fromJson)
        .toList(growable: false);
  }

  Future<PagedResult<AppNotification>> orderNotifications(String orderId,
      {int page = 1, int pageSize = 20}) async {
    final body = await _getJson('/api/v1/orders/$orderId/notifications', query: {
      'page': '$page',
      'page_size': '$pageSize',
    });
    return PagedResult.fromJson(body, AppNotification.fromJson);
  }

  // --- admin (read-only overview) ----------------------------------------

  Future<PagedResult<OrderListItem>> adminOrders({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final body = await _getJson('/api/v1/admin/orders', query: {
      if (status != null && status.isNotEmpty) 'status': status,
      'page': '$page',
      'page_size': '$pageSize',
    });
    return PagedResult.fromJson(body, OrderListItem.fromJson);
  }

  Future<AdminSummary> adminSummary() async =>
      AdminSummary.fromJson(await _getJson('/api/v1/admin/summary'));
}
