import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../jobs/presentation/jobs_home_screen.dart';
import 'onboarding_screen.dart';
import 'suspended_screen.dart';
import 'under_review_screen.dart';

/// `/home`: picks the screen from the technician's status, and WATCHES the session so a status change
/// made by ops (verified, sent back, suspended, reinstated) swaps the screen without a re-login.
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(authControllerProvider).value;
    if (s is! SessionAuthenticated) return const SizedBox.shrink(); // the router redirects away
    if (!s.hydrated) return const _ProfileLoadError();
    return switch (s.status) {
      'VERIFIED' => const JobsHomeScreen(),
      'PENDING' => const OnboardingScreen(),
      'KYC_SUBMITTED' => const UnderReviewScreen(),
      // SUSPENDED, DEACTIVATED, or a status this build doesn't know: blocked — never the jobs screen.
      _ => const SuspendedScreen(),
    };
  }
}

/// Signed in, but the profile fetch failed (network). Never show a blank onboarding form for an
/// unknown status — offer a retry instead.
class _ProfileLoadError extends ConsumerStatefulWidget {
  const _ProfileLoadError();

  @override
  ConsumerState<_ProfileLoadError> createState() => _ProfileLoadErrorState();
}

class _ProfileLoadErrorState extends ConsumerState<_ProfileLoadError> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      if (r case Failure(:final message)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'fixcare onboarding',
        context: ErrorDescription('retrying the profile load'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('profileLoadError'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: FixCareColors.primary),
                const SizedBox(height: 20),
                Text("Couldn't load your profile", textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                FilledButton(key: const Key('retryProfileBtn'), onPressed: _busy ? null : _retry, child: const Text('Retry')),
                const SizedBox(height: 8),
                TextButton(
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
