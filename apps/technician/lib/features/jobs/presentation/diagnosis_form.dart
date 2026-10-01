import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/catalog_repository.dart';
import '../data/technician_job_repository.dart';
import 'job_action.dart';
import 'job_detail_controller.dart';
import 'parts_cart.dart';
import 'photo_capture.dart';

/// The job category's issues (null = an older backend without categoryId → unfiltered). The backend still
/// re-validates the issue's category on diagnose (422 surfaced inline).
final _issuesProvider =
    FutureProvider.autoDispose.family<Result<List<DiagnosedIssueDto>>, String?>((ref, categoryId) {
  return ref.read(catalogRepositoryProvider).issues(categoryId: categoryId);
});

/// ARRIVED: the complete estimate — the two evidence photos, the diagnosed issue, and the parts cart. "Submit diagnosis" sends it to the customer and freezes the cart (backend-enforced).
class DiagnosisForm extends ConsumerStatefulWidget {
  const DiagnosisForm({super.key, required this.detail});

  final TechnicianJobDetailDto detail;

  @override
  ConsumerState<DiagnosisForm> createState() => _DiagnosisFormState();
}

class _DiagnosisFormState extends ConsumerState<DiagnosisForm> {
  String? _issueId;
  bool _busy = false;
  bool _cartBusy = false;
  String? _error;

  Future<void> _confirmAndSubmit() async {
    final issueId = _issueId;
    if (issueId == null || _busy || _cartBusy) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send estimate?'),
        content: const Text("Send this estimate to the customer? You won't be able to change parts after this."),
        actions: [
          TextButton(key: const Key('cancelSendEstimateBtn'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not yet')),
          FilledButton(key: const Key('confirmSendEstimateBtn'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Send estimate')),
        ],
      ),
    );
    if (send != true || !mounted) return;
    await _submit(issueId);
  }

  Future<void> _submit(String issueId) async {
    final jobId = widget.detail.job.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(technicianJobRepositoryProvider).diagnose(jobId, issueId);
      if (!mounted) return;
      switch (result) {
        case Ok():
          await ref.read(jobDetailProvider(jobId).notifier).refetch();
        case Failure(message: final m):
          setState(() => _error = m);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.detail.job;
    final queue = ref.read(photoUploadQueueProvider);
    final issuesAsync = ref.watch(_issuesProvider(job.service.categoryId));
    // One list drives both the slots and the gate, so they cannot disagree.
    final kinds = requiredPhotoKinds('ARRIVED');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, kind) in kinds.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              PhotoSlot(
                bookingId: job.id,
                kind: kind,
                label: photoSlotLabels[kind] ?? 'Photo',
                serverHasPhoto: job.photos.any((p) => p.kind == kind),
              ),
            ],
            const SizedBox(height: 16),
            _buildIssuePicker(issuesAsync),
            const SizedBox(height: 20),
            PartsSection(
              detail: widget.detail,
              onBusyChanged: (busy) {
                if (mounted && busy != _cartBusy) setState(() => _cartBusy = busy);
              },
            ),
            if (_error case final err?) ...[
              const SizedBox(height: 8),
              Text(err, key: const Key('diagnosisError'), style: const TextStyle(color: FixCareColors.errorText)),
            ],
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: queue,
              builder: (context, _) {
                final ready = photosReady(queue, job, kinds);
                final enabled = ready && _issueId != null && !_busy && !_cartBusy;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: const Key('submitDiagnosisBtn'),
                        onPressed: enabled ? _confirmAndSubmit : null,
                        child: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Submit diagnosis'),
                      ),
                    ),
                    if (!enabled) ...[
                      const SizedBox(height: 4),
                      Text(
                        _cartBusy ? 'Updating the parts…' : 'Take both photos and pick the issue to continue.',
                        style: TextStyle(fontSize: 12, color: FixCareColors.textMuted),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssuePicker(AsyncValue<Result<List<DiagnosedIssueDto>>> async) {
    return switch (async) {
      AsyncData(value: Ok(value: final issues)) => DropdownButtonFormField<String>(
          key: const Key('issuePicker'),
          initialValue: _issueId,
          decoration: const InputDecoration(labelText: 'Issue'),
          items: [for (final i in issues) DropdownMenuItem(value: i.id, child: Text(i.name))],
          onChanged: (v) => setState(() => _issueId = v),
        ),
      AsyncData(value: Failure(message: final m)) => _issuesError(m),
      AsyncError() => _issuesError('Something went wrong.'),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _issuesError(String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('issuesRetry'),
            onPressed: () => ref.invalidate(_issuesProvider(widget.detail.job.service.categoryId)),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
