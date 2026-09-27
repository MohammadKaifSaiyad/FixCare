import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/catalog_repository.dart';
import '../data/technician_job_repository.dart';
import 'job_action.dart';
import 'job_detail_controller.dart';
import 'photo_capture.dart';

/// The two evidence photos + issue picker + submit, at ARRIVED. Consumes the
/// Task 7a photo queue ([photosReady], [PhotoSlot]) and the catalog's issue
/// list. The backend re-validates the issue against the job's category on
/// submit (the job DTO carries no categoryId) and 422s with a message this
/// widget surfaces verbatim inline.
final _issuesProvider =
    FutureProvider.autoDispose<Result<List<DiagnosedIssueDto>>>((ref) {
  return ref.read(catalogRepositoryProvider).issues();
});

class DiagnosisForm extends ConsumerStatefulWidget {
  const DiagnosisForm({super.key, required this.job});

  final TechnicianJobDto job;

  @override
  ConsumerState<DiagnosisForm> createState() => _DiagnosisFormState();
}

class _DiagnosisFormState extends ConsumerState<DiagnosisForm> {
  String? _issueId;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final issueId = _issueId;
    if (issueId == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(technicianJobRepositoryProvider).diagnose(widget.job.id, issueId);
      if (!mounted) return;
      switch (result) {
        case Ok():
          await ref.read(jobDetailProvider(widget.job.id).notifier).refetch();
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
    final job = widget.job;
    final queue = ref.read(photoUploadQueueProvider);
    final issuesAsync = ref.watch(_issuesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhotoSlot(
              bookingId: job.id,
              kind: 'DIAGNOSIS_OVERVIEW',
              label: 'Overview photo',
              serverHasPhoto: job.photos.any((p) => p.kind == 'DIAGNOSIS_OVERVIEW'),
            ),
            const SizedBox(height: 12),
            PhotoSlot(
              bookingId: job.id,
              kind: 'DIAGNOSIS_CLOSEUP',
              label: 'Close-up of the fault',
              serverHasPhoto: job.photos.any((p) => p.kind == 'DIAGNOSIS_CLOSEUP'),
            ),
            const SizedBox(height: 16),
            _buildIssuePicker(issuesAsync),
            if (_error case final err?) ...[
              const SizedBox(height: 8),
              Text(err, key: const Key('diagnosisError'), style: const TextStyle(color: FixCareColors.errorText)),
            ],
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: queue,
              builder: (context, _) {
                final ready = photosReady(queue, job, requiredPhotoKinds('ARRIVED'));
                final enabled = ready && _issueId != null && !_busy;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: const Key('submitDiagnosisBtn'),
                        onPressed: enabled ? _submit : null,
                        child: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Submit diagnosis'),
                      ),
                    ),
                    if (!enabled) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Take both photos and pick the issue to continue.',
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
            onPressed: () => ref.invalidate(_issuesProvider),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
