import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/data/technician_profile_dto.dart';
import 'submitted_summary.dart';

const reviewPollInterval = Duration(seconds: 30);

/// KYC_SUBMITTED: waiting for ops. Re-checks the profile every 30 s while in the foreground (a chain of
/// one-shot timers — the next check is armed only after the current one finishes), pauses in the
/// background, checks right away on resume, and on pull-to-refresh / "Check status". When ops decides,
/// the home gate swaps this screen out (which disposes the timer).
class UnderReviewScreen extends ConsumerStatefulWidget {
  const UnderReviewScreen({super.key});

  @override
  ConsumerState<UnderReviewScreen> createState() => _UnderReviewScreenState();
}

class _UnderReviewScreenState extends ConsumerState<UnderReviewScreen> {
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  bool _paused = false;
  bool _checking = false;
  bool _manualBusy = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _pause, onPause: _pause, onResume: _resume);
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_paused || !mounted) return;
    _timer = Timer(reviewPollInterval, () => unawaited(_tick()));
  }

  Future<void> _tick() async {
    await _check();
    _arm();
  }

  void _pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    unawaited(_tick());
  }

  /// One check at a time; null when one was already running.
  Future<Result<TechnicianProfileDto>?> _check() async {
    if (_checking || !mounted) return null;
    _checking = true;
    try {
      return await ref.read(authControllerProvider.notifier).refreshProfile();
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'fixcare onboarding',
        context: ErrorDescription('re-checking the verification status'),
      ));
      return null;
    } finally {
      _checking = false;
    }
  }

  Future<void> _manualCheck() async {
    setState(() => _manualBusy = true);
    try {
      final r = await _check();
      if (!mounted || r == null) return;
      final msg = switch (r) {
        Ok(value: final p) when p.status == 'KYC_SUBMITTED' => "Still under review. We'll update this screen when FixCare decides.",
        Ok() => null,
        Failure(message: final m) => m,
      };
      if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _manualBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(authControllerProvider).value;
    final profile = s is SessionAuthenticated ? s.profile : null;
    return Scaffold(
      key: const Key('underReviewScreen'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _manualCheck,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.hourglass_top, size: 48, color: FixCareColors.primary),
              const SizedBox(height: 20),
              Text('Verification pending', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              const Text(
                'Your details are with FixCare for verification',
                key: Key('verificationStatusText'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: FixCareColors.textMuted, height: 1.5),
              ),
              if (profile != null) SubmittedSummary(profile: profile),
              FilledButton(
                key: const Key('checkStatusBtn'),
                onPressed: _manualBusy ? null : _manualCheck,
                child: const Text('Check status'),
              ),
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
