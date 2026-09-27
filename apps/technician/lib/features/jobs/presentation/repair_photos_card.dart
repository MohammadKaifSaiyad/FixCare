import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/technician_job_repository.dart';
import 'job_action.dart';
import 'job_detail_controller.dart';
import 'photo_capture.dart';

/// REPAIR_IN_PROGRESS: the three mandatory repair photos (old part removed, new
/// part packaging, new part installed) + "Complete repair".
///
/// The button stays disabled until all three have evidence (uploaded this
/// session or already on the server). This is the app-side half of the
/// completion gate (Golden Rule 1): the backend re-checks the three photos
/// on complete-repair and 422s otherwise, and that message is shown
/// verbatim inline.
class RepairPhotosCard extends ConsumerStatefulWidget {
  const RepairPhotosCard({super.key, required this.job});

  final TechnicianJobDto job;

  @override
  ConsumerState<RepairPhotosCard> createState() => _RepairPhotosCardState();
}

class _RepairPhotosCardState extends ConsumerState<RepairPhotosCard> {
  bool _busy = false;
  String? _error;

  Future<void> _complete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(technicianJobRepositoryProvider).completeRepair(widget.job.id);
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
    // One list drives both the slots and the gate, so they cannot disagree.
    final kinds = requiredPhotoKinds('REPAIR_IN_PROGRESS');

    return Card(
      key: const Key('repairPhotosCard'),
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
            if (_error case final err?) ...[
              const SizedBox(height: 8),
              Text(err, key: const Key('completeRepairError'), style: const TextStyle(color: FixCareColors.errorText)),
            ],
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: queue,
              builder: (context, _) {
                final ready = photosReady(queue, job, kinds);
                final enabled = ready && !_busy;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: const Key('completeRepairBtn'),
                        onPressed: enabled ? _complete : null,
                        child: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Complete repair'),
                      ),
                    ),
                    if (!ready) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Take all 3 photos to complete the repair.',
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
}
