/// QuickBite v2 Flutter client — entry point.
///
/// Wiring done here and nowhere else:
/// * `SharedPreferences` is awaited before `runApp` and injected via
///   `sharedPreferencesProvider` override (tests override it with
///   `SharedPreferences.setMockInitialValues`).
/// * Named routes: `/` (auth gate), `/cart`. Everything else is pushed
///   imperatively with `MaterialPageRoute` because the screens carry typed
///   arguments (Restaurant, CheckoutAccepted, orderId).
///
/// Keyboard navigation on web works out of the box: every control is a real
/// Material button/field in the tab order, the email field has `autofocus`,
/// and dialogs trap focus.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state/auth_notifier.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';
import 'screens/admin_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/restaurant_list_screen.dart';
import 'screens/sign_in_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(buildApp(prefs: prefs));
}

/// Builds the root widget with an explicit [SharedPreferences] instance so
/// integration tests can inject a cleared store.
Widget buildApp({required SharedPreferences prefs}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: const QuickBiteApp(),
  );
}

class QuickBiteApp extends StatelessWidget {
  const QuickBiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickBite',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AuthGate(),
      routes: {
        '/cart': (_) => const CartScreen(),
      },
    );
  }
}

/// Routes to sign-in / customer home / admin overview based on auth state.
/// Shows a branded splash while a saved mobile token is being validated.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return switch (auth.phase) {
      AuthPhase.restoring => const _Splash(),
      AuthPhase.signedIn when auth.user?.isAdmin == true =>
        const AdminOverviewScreen(),
      AuthPhase.signedIn => const RestaurantListScreen(),
      _ => const SignInScreen(),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu,
                size: 64, color: AppColors.orange),
            SizedBox(height: 16),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
