import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../models/profile.dart';
import 'auth_scaffold.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  UserRole _role = UserRole.salesman;
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
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
      await ref.read(authControllerProvider.notifier).signUp(
            name: _nameController.text.trim(),
            mobile: _mobileController.text.trim(),
            email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
            password: _passwordController.text,
            role: _role,
          );
      // A successful sign-up redirects away from this screen immediately
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
      title: 'Create your account',
      subtitle: 'One account per person — the owner decides what it can do.',
      icon: Icons.person_add_alt_1,
      footer: AuthFooterLink(
        prompt: 'Already have an account?',
        action: 'Sign in',
        onPressed: () => context.go('/login'),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              AuthErrorBanner(message: _error!),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nameController,
              decoration: authField('Full name'),
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: authField('Mobile number'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!RegExp(r'^[0-9+][0-9\- ]{6,}$').hasMatch(v.trim())) return 'Enter a valid mobile number';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: authField('Email (optional)'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: authField(
                'Password',
                helper: 'At least 6 characters',
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
              validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
            ),
            const SizedBox(height: 20),
            const Text(
              'I am a',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AuthPalette.ink),
            ),
            const SizedBox(height: 8),
            // Two choices deserve two buttons, not a dropdown that hides one.
            Row(
              children: [
                Expanded(
                  child: _RoleOption(
                    icon: Icons.storefront,
                    label: 'Salesman',
                    caption: 'Books orders',
                    selected: _role == UserRole.salesman,
                    onTap: () => setState(() => _role = UserRole.salesman),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _RoleOption(
                    icon: Icons.local_shipping,
                    label: 'Delivery Man',
                    caption: 'Runs the van',
                    selected: _role == UserRole.deliveryman,
                    onTap: () => setState(() => _role = UserRole.deliveryman),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AuthPalette.indigo.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: AuthPalette.indigo),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'An owner must approve your account before you can sign in.',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: AuthPalette.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            AuthSubmitButton(
              label: 'Create account',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two roles, as a pressable card. Selected state is carried by
/// fill, border and a tick — not colour alone.
class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.icon,
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AuthPalette.indigo.withValues(alpha: 0.10) : Colors.white,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? AuthPalette.indigo : const Color(0xFFD9D6E6),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: selected ? AuthPalette.indigo : AuthPalette.inkSoft),
                  const Spacer(),
                  if (selected) const Icon(Icons.check_circle, size: 16, color: AuthPalette.indigo),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AuthPalette.indigo : AuthPalette.ink,
                ),
              ),
              Text(
                caption,
                style: const TextStyle(fontSize: 11.5, color: AuthPalette.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
