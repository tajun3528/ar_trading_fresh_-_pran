import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import 'auth_scaffold.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signIn(
            identifier: _identifierController.text,
            password: _passwordController.text,
          );
      // A successful sign-in redirects away from this screen immediately
      // (router listens to authControllerProvider), so the widget — and its
      // `ref` — may already be disposed by the time this resumes.
      if (!mounted) return;
      final state = ref.read(authControllerProvider);
      if (state.hasError) {
        setState(() => _error = state.error.toString());
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'AR-Trading',
      subtitle: 'Distribution, from the order book to the bank.',
      icon: Icons.local_shipping,
      footer: AuthFooterLink(
        prompt: 'No account yet?',
        action: 'Create one',
        onPressed: () => context.go('/signup'),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sign in',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AuthPalette.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Use the mobile number your account was set up with.',
              style: TextStyle(fontSize: 13, height: 1.4, color: AuthPalette.inkSoft),
            ),
            const SizedBox(height: 22),
            if (_error != null) ...[
              AuthErrorBanner(message: _error!),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _identifierController,
              decoration: authField('Mobile number or email'),
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: authField(
                'Password',
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 19,
                    color: AuthPalette.inkSoft,
                  ),
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              obscureText: _obscure,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            AuthSubmitButton(
              label: 'Sign in',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
