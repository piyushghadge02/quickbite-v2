/// Typed errors for the QuickBite v2 error envelope
/// `{code, message, details, request_id}` plus transport failures.
library;

/// Base error for every API failure surfaced to the UI.
class ApiException implements Exception {
  final String code;
  final String message;
  final Object? details;
  final String? requestId;
  final int? statusCode;

  const ApiException({
    required this.code,
    required this.message,
    this.details,
    this.requestId,
    this.statusCode,
  });

  /// Build from the backend's error envelope JSON.
  factory ApiException.fromEnvelope(
    Map<String, dynamic> envelope, {
    required int statusCode,
  }) {
    String detailText(Object? details) {
      if (details == null) return '';
      if (details is String) return details;
      if (details is List) {
        return details
            .whereType<Map>()
            .map((e) {
              final loc = (e['loc'] as List?)?.join('.') ?? '';
              final msg = e['msg'] ?? e['message'] ?? '';
              return loc.isEmpty ? '$msg' : '$loc: $msg';
            })
            .join('\n');
      }
      return '$details';
    }

    final rawMessage = '${envelope['message'] ?? 'Request failed'}';
    final detailStr = detailText(envelope['details']);
    final message =
        detailStr.isEmpty ? rawMessage : '$rawMessage\n$detailStr';

    return ApiException(
      code: '${envelope['code'] ?? 'UNKNOWN'}',
      message: message,
      details: envelope['details'],
      requestId: envelope['request_id'] as String?,
      statusCode: statusCode,
    );
  }

  @override
  String toString() => 'ApiException($code): $message';
}

/// The device could not reach the API at all (DNS, refused, timeout).
class NetworkException extends ApiException {
  const NetworkException({required super.message, super.requestId})
      : super(code: 'NETWORK_ERROR', statusCode: null);
}

/// HTTP 401 — missing, invalid, or expired token.
class UnauthorizedException extends ApiException {
  const UnauthorizedException({required super.message, super.requestId})
      : super(code: 'UNAUTHORIZED', statusCode: 401);
}

/// HTTP 403 — authenticated but not allowed (e.g. non-admin on /admin/*).
class ForbiddenException extends ApiException {
  const ForbiddenException({required super.message, super.requestId})
      : super(code: 'FORBIDDEN', statusCode: 403);
}

/// HTTP 404 — resource not found (or not owned by this user).
class NotFoundException extends ApiException {
  const NotFoundException({required super.message, super.requestId})
      : super(code: 'NOT_FOUND', statusCode: 404);
}

/// HTTP 409 — idempotency-key conflict (same key, different payload).
class ConflictException extends ApiException {
  const ConflictException({required super.message, super.requestId})
      : super(code: 'CONFLICT', statusCode: 409);
}

/// HTTP 422 — request validation failed.
class ValidationException extends ApiException {
  const ValidationException({
    required super.message,
    super.details,
    super.requestId,
  }) : super(code: 'VALIDATION_ERROR', statusCode: 422);
}
