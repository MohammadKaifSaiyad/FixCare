import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../jobs/data/catalog_repository.dart';
import '../../profile/data/technician_profile_repository.dart';
import 'skills.dart';

const kSubmitConfirmBody = "Submit your details? You won't be able to change them while FixCare reviews your profile.";

/// A PENDING technician (new, or sent back by ops): name + skills + service zones, then "Submit for
/// verification". Ops verifies in person — no documents are collected here.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _skills = <String>{};
  final _zoneIds = <String>{};
  String? _reviewNote;
  List<ZoneRefDto>? _zones; // null while loading
  String? _zonesError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(authControllerProvider).value;
    if (s is SessionAuthenticated) {
      _name.text = s.profile.name;
      _skills.addAll(s.profile.skills.where((c) => kSkills.any((k) => k.$1 == c)));
      _zoneIds.addAll(s.profile.zones.map((z) => z.id));
      _reviewNote = s.profile.reviewNote;
    }
    _name.addListener(_onNameChanged);
    unawaited(_fetchZones());
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  Future<void> _fetchZones() async {
    Result<List<ZoneRefDto>> r;
    try {
      r = await ref.read(catalogRepositoryProvider).zones();
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'fixcare onboarding',
        context: ErrorDescription('loading service zones'),
      ));
      r = const Failure(FailureKind.unknown, "Couldn't load service zones.");
    }
    if (!mounted) return;
    setState(() {
      switch (r) {
        case Ok(value: final zones):
          _zones = zones;
        case Failure(message: final m):
          _zonesError = m;
      }
    });
  }

  void _retryZones() {
    setState(() {
      _zones = null;
      _zonesError = null;
    });
    unawaited(_fetchZones());
  }

  /// Only zones still offered are sent: a prefilled zone ops has since deactivated would 422 forever.
  List<String> get _selectedZoneIds => [for (final z in _zones ?? const <ZoneRefDto>[]) if (_zoneIds.contains(z.id)) z.id];

  bool get _valid => _name.text.trim().isNotEmpty && _skills.isNotEmpty && _selectedZoneIds.isNotEmpty;

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit for verification'),
        content: const Text(kSubmitConfirmBody),
        actions: [
          TextButton(key: const Key('cancelSubmitBtn'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('confirmSubmitBtn'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(technicianProfileRepositoryProvider);
      final saved = await repo.updateProfile(
        name: _name.text.trim(),
        skills: [for (final (code, _) in kSkills) if (_skills.contains(code)) code],
        zoneIds: _selectedZoneIds,
      );
      if (!mounted) return;
      if (saved case Failure(:final message, :final code)) {
        _snack(message);
        // Already submitted (an earlier tap whose response was lost): re-check so the gate shows "under review".
        if (code == 'PROFILE_LOCKED') await ref.read(authControllerProvider.notifier).refreshProfile();
        return;
      }
      final sent = await repo.submit();
      if (!mounted) return;
      if (sent case Failure(:final message, :final code)) {
        _snack(message);
        // Already submitted / no longer editable: re-check so the gate moves on instead of looping on this form.
        if (code == 'INVALID_TECHNICIAN_TRANSITION') await ref.read(authControllerProvider.notifier).refreshProfile();
        return;
      }
      // KYC_SUBMITTED → the home gate swaps this screen for "Verification pending".
      final refreshed = await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      if (refreshed is Failure) _snack("Submitted. Couldn't refresh — pull down or reopen the app.");
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'fixcare onboarding',
        context: ErrorDescription('submitting the onboarding form'),
      ));
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('onboardingScreen'),
      appBar: AppBar(
        title: const Text('Your details'),
        actions: [
          TextButton(
            key: const Key('logoutBtn'),
            onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).logout(),
            child: const Text('Log out'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (_reviewNote case final note? when note.trim().isNotEmpty) _SentBackBanner(note: note),
            const Text(
              'Tell FixCare about your work. Our team will verify you in person.',
              style: TextStyle(fontSize: 14.5, color: FixCareColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('nameField'),
              controller: _name,
              enabled: !_busy,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 8),
            const _SectionTitle('Skills'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (code, label) in kSkills)
                  FilterChip(
                    key: Key('skill_$code'),
                    label: Text(label),
                    selected: _skills.contains(code),
                    onSelected: _busy ? null : (on) => setState(() => on ? _skills.add(code) : _skills.remove(code)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Service zones'),
            _zonesSection(),
            const SizedBox(height: 28),
            FilledButton(
              key: const Key('submitForVerificationBtn'),
              onPressed: _valid && !_busy ? _submit : null,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit for verification'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zonesSection() {
    if (_zonesError case final err?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(err, key: const Key('zonesError'), style: const TextStyle(color: FixCareColors.errorText)),
          TextButton(key: const Key('zonesRetryBtn'), onPressed: _retryZones, child: const Text('Retry')),
        ],
      );
    }
    final zones = _zones;
    if (zones == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(key: Key('zonesLoading'))),
      );
    }
    if (zones.isEmpty) {
      return const Text('No service zones are open yet. Please check back later.', key: Key('zonesEmpty'));
    }
    return Column(
      children: [
        for (final z in zones)
          CheckboxListTile(
            key: Key('zone_${z.id}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(z.name),
            value: _zoneIds.contains(z.id),
            onChanged: _busy ? null : (on) => setState(() => on == true ? _zoneIds.add(z.id) : _zoneIds.remove(z.id)),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
      );
}

class _SentBackBanner extends StatelessWidget {
  const _SentBackBanner({required this.note});
  final String note;
  @override
  Widget build(BuildContext context) => Container(
        key: const Key('sentBackBanner'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FixCareColors.errorFill,
          border: Border.all(color: FixCareColors.errorBorder),
          borderRadius: BorderRadius.circular(FixCareRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FixCare sent your profile back', style: TextStyle(fontWeight: FontWeight.w600, color: FixCareColors.errorText)),
            const SizedBox(height: 6),
            Text(note, style: const TextStyle(color: FixCareColors.errorText, height: 1.4)),
            const SizedBox(height: 6),
            const Text('Please fix and resubmit.', style: TextStyle(color: FixCareColors.errorText)),
          ],
        ),
      );
}
