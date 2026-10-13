/// Common interface + stub for platforms without a dedicated implementation.
library;

/// Persists the auth token. Implementations must never log the token.
abstract class TokenStorage {
  Future<void> save(String token);
  Future<String?> read();
  Future<void> delete();
}

/// Fallback: in-memory. Used if neither the web nor the mobile file applies.
class _InMemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<void> save(String token) async => _token = token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> delete() async => _token = null;
}

TokenStorage buildTokenStorage() => _InMemoryTokenStorage();
