import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';

/// Shown to an authenticated-but-not-VERIFIED technician on /home. The
/// session's `status` drives the copy: PENDING/KYC_SUBMITTED reads as "under
/// review", SUSPENDED/DEACTIVATED reads as a hard block with a support
/// pointer. Either way a logout button is offered — there's nothing else to
/// do here until the backend flips the status.
class VerificationPendingScreen extends ConsumerWidget {
  const VerificationPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).value;
    final status = session is SessionAuthenticated ? session.status : 'PENDING';

    final suspended = status == 'SUSPENDED' || status == 'DEACTIVATED';
    final title = suspended ? 'Account suspended' : 'Verification pending';
    final body = suspended
        ? 'Your account is suspended. Please contact support.'
        : "Your account is under review. We'll notify you once you're verified.";

    return Scaffold(
      key: const Key('verificationPendingScreen'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  suspended ? Icons.block : Icons.hourglass_top,
                  size: 48,
                  color: FixCareColors.primary,
                ),
                const SizedBox(height: 20),
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(
                  body,
                  key: const Key('verificationStatusText'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14.5, color: FixCareColors.textMuted, height: 1.5),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  key: const Key('logoutBtn'),
                  onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
