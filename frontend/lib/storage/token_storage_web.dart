/// Web token storage: memory only, by design.
///
/// Rationale: keeping the bearer token out of `localStorage` and cookies
/// means a page reload signs the user out, but the token cannot be exfiltrated
/// through persistent-storage XSS vectors. The app documents this trade-off
/// in the README. This file is only compiled for the web build.
library;

export 'token_storage_stub.dart';

import 'token_storage_stub.dart';

class _WebMemoryTokenStorage implements TokenStorage {
  static String? _token;

  @override
  Future<void> save(String token) async => _token = token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> delete() async => _token = null;
}

TokenStorage buildTokenStorage() => _WebMemoryTokenStorage();
