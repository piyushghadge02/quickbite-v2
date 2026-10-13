/// Mobile token storage: encrypted at rest via flutter_secure_storage.
///
/// Only compiled when `dart.library.io` is available (Android/iOS). The web
/// build never imports this file, and therefore never links the
/// `flutter_secure_storage` plugin.
library;

export 'token_storage_stub.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_storage_stub.dart';

class _MobileSecureTokenStorage implements TokenStorage {
  static const _key = 'quickbite_access_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<void> save(String token) => _storage.write(key: _key, value: token);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

TokenStorage buildTokenStorage() => _MobileSecureTokenStorage();
