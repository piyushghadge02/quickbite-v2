/// Sign-in screen with three explicit states:
/// * loading — button shows a spinner and is disabled (no double submit);
/// * invalid credentials (401 → INVALID_CREDENTIALS);
/// * network error (timeout / unreachable) with a "Try again" action.
/// Any other API error gets a generic banner.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth_notifier.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    ref.read(authProvider.notifier).signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isLoading = auth.phase == AuthPhase.signingIn;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ResponsiveCenter(
              maxWidth: 440,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Semantics(
                      header: true,
                      child: const _BrandHeader(),
                    ),
                    const SizedBox(height: 32),
                    if (auth.phase == AuthPhase.error)
                      _ErrorBanner(
                        failure: auth.failure,
                        message: auth.failureMessage ??
                            'Something went wrong. Please try again.',
                        onRetry: auth.failure == AuthFailure.network
                            ? _submit
                            : null,
                      ),
                    Semantics(
                      label: 'Email address',
                      textField: true,
                      child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return 'Enter your email.';
                          if (!value.contains('@')) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      label: 'Password',
                      textField: true,
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => (v ?? '').isEmpty
                            ? 'Enter your password.'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      button: true,
                      label: isLoading ? 'Signing in' : 'Sign in',
                      child: FilledButton(
                        onPressed: isLoading ? null : _submit,
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _DemoAccountsNote(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            color: AppColors.orange,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.restaurant_menu,
            size: 44,
            color: Colors.white,
            semanticLabel: 'QuickBite logo',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'QuickBite',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hot food, tracked live.',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 15),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final AuthFailure? failure;
  final String message;
  final VoidCallback? onRetry;

  const _ErrorBanner({
    required this.failure,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isNetwork = failure == AuthFailure.network;
    final title = switch (failure) {
      AuthFailure.invalidCredentials => 'Incorrect email or password',
      AuthFailure.network => 'Connection problem',
      _ => 'Couldn\'t sign you in',
    };
    return Semantics(
      label: 'Sign-in error: $title. $message',
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isNetwork ? Icons.cloud_off_outlined : Icons.error_outline,
              color: AppColors.danger,
              semanticLabel: isNetwork ? 'Offline' : 'Error',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7F1D1D),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                        color: Color(0xFF7F1D1D), height: 1.35),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoAccountsNote extends StatelessWidget {
  const _DemoAccountsNote();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Demo accounts',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            SelectableText('Customer: aarav@quickbite.test / customer123'),
            SelectableText('Customer: diya@quickbite.test / customer123'),
            SelectableText('Admin: admin@quickbite.test / admin123'),
          ],
        ),
      ),
    );
  }
}
