import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';

/// SUSPENDED (or DEACTIVATED): blocked from jobs. Shows ops' reason; "Check again" / pull-to-refresh
/// re-checks so a reinstated technician gets back in (no timer — reinstatement is rare).
class SuspendedScreen extends ConsumerStatefulWidget {
  const SuspendedScreen({super.key});

  @override
  ConsumerState<SuspendedScreen> createState() => _SuspendedScreenState();
}

class _SuspendedScreenState extends ConsumerState<SuspendedScreen> {
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      final msg = switch (r) {
        Ok(value: final p) when p.status != 'VERIFIED' => 'Your account is still suspended.',
        Ok() => null,
        Failure(message: final m) => m,
      };
      if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'fixcare onboarding',
        context: ErrorDescription('re-checking a suspended account'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(authControllerProvider).value;
    final reason = s is SessionAuthenticated ? s.profile.reviewNote : null;
    return Scaffold(
      key: const Key('suspendedScreen'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _check,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.block, size: 48, color: FixCareColors.primary),
              const SizedBox(height: 20),
              Text('Account suspended', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              if (reason case final r? when r.trim().isNotEmpty)
                Container(
                  key: const Key('suspensionReason'),
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: FixCareColors.errorFill,
                    border: Border.all(color: FixCareColors.errorBorder),
                    borderRadius: BorderRadius.circular(FixCareRadii.card),
                  ),
                  child: Text(r, style: const TextStyle(color: FixCareColors.errorText, height: 1.4)),
                ),
              const SizedBox(height: 16),
              const Text(
                'Contact FixCare support',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: FixCareColors.textMuted),
              ),
              const SizedBox(height: 28),
              FilledButton(key: const Key('checkAgainBtn'), onPressed: _busy ? null : _check, child: const Text('Check again')),
              const SizedBox(height: 8),
              OutlinedButton(key: const Key('earningsBtn'), onPressed: () => context.push('/earnings'), child: const Text('Earnings')),
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
    );
  }
}
