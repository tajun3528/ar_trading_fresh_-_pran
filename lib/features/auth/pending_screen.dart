import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/viz/status_palette.dart';
import '../../models/profile.dart';
import 'auth_scaffold.dart';

class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).valueOrNull;
    final isInactive = profile?.status == UserStatus.inactive;
    final level = isInactive ? StatusLevel.critical : StatusLevel.warning;

    return AuthScaffold(
      title: isInactive ? 'Account deactivated' : 'Waiting for approval',
      subtitle: isInactive
          ? 'This account can no longer sign in.'
          : 'Your account is made — it just needs letting in.',
      icon: isInactive ? Icons.block : Icons.hourglass_top,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: level.color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: level.color.withValues(alpha: 0.30)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(isInactive ? Icons.block : Icons.schedule, size: 17, color: level.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isInactive
                        ? 'Your account has been deactivated. Please contact the business owner.'
                        : 'The business owner approves each new account and sets what it can do. '
                            'Ask them to open Users and activate yours.',
                    style: const TextStyle(fontSize: 12.5, height: 1.4, color: AuthPalette.inkSoft),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!isInactive) ...[
            AuthSubmitButton(
              label: 'Check again',
              busy: false,
              onPressed: () => ref.read(authControllerProvider.notifier).refresh(),
            ),
            const SizedBox(height: 10),
          ],
          TextButton(
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            style: TextButton.styleFrom(
              foregroundColor: AuthPalette.inkSoft,
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('Sign out', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
