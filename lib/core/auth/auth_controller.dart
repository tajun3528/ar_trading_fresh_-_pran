import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/profile.dart';
import '../insforge/insforge_exception.dart';
import '../providers.dart';

/// Holds the signed-in user's profile (role + status), or null when signed
/// out. The router redirects off this: no profile -> /login, pending/inactive
/// -> /pending, active -> the role's home shell.
class AuthController extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final client = ref.watch(insforgeClientProvider);
    await client.restoreSession();
    final user = await client.getCurrentUser();
    if (user == null) return null;
    return _fetchProfile(user['id'] as String);
  }

  Future<Profile?> _fetchProfile(String userId) async {
    final client = ref.read(insforgeClientProvider);
    final row = await client.from('profiles').select().eq('user_id', userId).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  static String _sanitizeMobile(String mobile) => mobile.replaceAll(RegExp('[^0-9]'), '');

  Future<void> signIn({required String identifier, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(insforgeClientProvider);
      final resolvedEmail = await client.resolveLoginEmail(identifier.trim());
      final email = resolvedEmail ?? identifier.trim();
      await client.signIn(email: email, password: password);
      final user = await client.getCurrentUser();
      if (user == null) {
        throw InsforgeException('Sign in failed. Please try again.');
      }
      return _fetchProfile(user['id'] as String);
    });
  }

  Future<void> signUp({
    required String name,
    required String mobile,
    String? email,
    required String password,
    required UserRole role,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(insforgeClientProvider);
      final hasRealEmail = email != null && email.trim().isNotEmpty;
      final authEmail = hasRealEmail ? email.trim() : '${_sanitizeMobile(mobile)}@artrading.local';

      await client.signUp(email: authEmail, password: password, name: name);
      await client.rpc('complete_profile', {
        'p_name': name,
        'p_mobile': mobile.trim(),
        'p_role': role.name,
        'p_email': hasRealEmail ? email.trim() : null,
      });

      final user = await client.getCurrentUser();
      if (user == null) {
        throw InsforgeException('Sign up failed. Please try again.');
      }
      return _fetchProfile(user['id'] as String);
    });
  }

  Future<void> signOut() async {
    final client = ref.read(insforgeClientProvider);
    await client.signOut();
    state = const AsyncData(null);
  }

  /// Re-reads the current user's profile — call after any self-service
  /// profile update so the UI reflects it immediately.
  Future<void> refresh() async {
    final client = ref.read(insforgeClientProvider);
    final user = await client.getCurrentUser();
    if (user == null) {
      state = const AsyncData(null);
      return;
    }
    state = await AsyncValue.guard(() => _fetchProfile(user['id'] as String));
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, Profile?>(AuthController.new);
