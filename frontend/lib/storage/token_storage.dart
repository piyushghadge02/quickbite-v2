/// Platform token storage behind a conditional import.
///
/// * Web (`dart.library.html`) → in-memory only. The token never touches
///   `localStorage`/cookies, so it does not survive a page reload and is not
///   readable by injected scripts through storage APIs. Documented trade-off:
///   users must sign in again after a reload.
/// * Mobile (`dart.library.io`) → `flutter_secure_storage` (Keychain /
///   Keystore), so the token is encrypted at rest and survives restarts.
///
/// Web never imports `flutter_secure_storage`: it is referenced only from
/// `token_storage_mobile.dart`, which the web build does not compile.
library;

/// The [TokenStorage] interface is re-exported so importers of this library
/// see it; the conditional import below only selects which
/// `buildTokenStorage()` implementation is linked per platform.
export 'token_storage_stub.dart';

import 'token_storage_stub.dart'
    if (dart.library.html) 'token_storage_web.dart'
    if (dart.library.io) 'token_storage_mobile.dart';

/// Factory exposed to the rest of the app; the conditional import above
/// decides which implementation is actually constructed.
TokenStorage createTokenStorage() => buildTokenStorage();
