import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/catalog_repository.dart';
import '../data/technician_job_repository.dart';
import 'job_detail_controller.dart';

/// What the customer will see at DIAGNOSED — mirrors the backend quote (computeEstimate): labor +
/// Σ(snapshot ceiling price × qty) − visit fee (credited once quoted), floored at 0. Integer paise; only
/// `rupees()` formats. Shared by the diagnosis form preview and the read-only DIAGNOSED card.
int estimatePaise(TechnicianJobDto job, List<JobPartLineDto> parts) {
  final partsTotal = parts.fold<int>(0, (sum, p) => sum + p.ceilingPricePaise * p.qty);
  final total = job.laborPaise + partsTotal - job.visitFeePaise;
  return total < 0 ? 0 : total;
}

/// Parts catalog for a job's category (the backend returns that category + generic parts). `null` (an
/// older backend without categoryId) → unfiltered. autoDispose: re-fetched each time the form opens.
final partsCatalogProvider =
    FutureProvider.autoDispose.family<Result<List<PartCatalogDto>>, String?>((ref, categoryId) {
  return ref.read(catalogRepositoryProvider).parts(categoryId: categoryId);
});

/// The parts section of the diagnosis form (ARRIVED). The cart shown is ALWAYS the backend's
/// (`detail.parts`): every add/remove goes to the backend and then refetches the job — whatever the
/// outcome — so an app restart, a lost response, or a locked cart can never show a stale or duplicated
/// cart. Catalog prices only (Golden Rule 4): the technician picks a part and a qty, never a price.
class PartsSection extends ConsumerStatefulWidget {
  const PartsSection({super.key, required this.detail, required this.onBusyChanged});

  final TechnicianJobDetailDto detail;

  /// Whether any cart edit is in flight — the form blocks "Submit diagnosis" until the cart settles, so the
  /// estimate sent is exactly the one on screen.
  final ValueChanged<bool> onBusyChanged;

  @override
  ConsumerState<PartsSection> createState() => _PartsSectionState();
}

class _PartsSectionState extends ConsumerState<PartsSection> {
  final _filterController = TextEditingController();
  String _filter = '';
  final Map<String, int> _qty = {}; // selected qty per catalog part (1..99, default 1) — UI-only until Add
  final Set<String> _busyPartIds = {};
  final Set<String> _busyLineIds = {};

  @override
  void initState() {
    super.initState();
    _filterController.addListener(_onFilterChanged);
  }

  void _onFilterChanged() => setState(() => _filter = _filterController.text.trim().toLowerCase());

  @override
  void dispose() {
    _filterController.removeListener(_onFilterChanged);
    _filterController.dispose();
    super.dispose();
  }

  String get _jobId => widget.detail.job.id;
  int _qtyFor(String partId) => _qty[partId] ?? 1;
  void _incQty(String partId) => setState(() => _qty[partId] = (_qtyFor(partId) + 1).clamp(1, 99));
  void _decQty(String partId) => setState(() => _qty[partId] = (_qtyFor(partId) - 1).clamp(1, 99));

  void _reportBusy() => widget.onBusyChanged(_busyPartIds.isNotEmpty || _busyLineIds.isNotEmpty);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addPart(PartCatalogDto part) async {
    if (_busyPartIds.contains(part.id)) return;
    final repo = ref.read(technicianJobRepositoryProvider);
    final detail = ref.read(jobDetailProvider(_jobId).notifier);
    setState(() => _busyPartIds.add(part.id));
    _reportBusy();
    try {
      final result = await repo.addPart(_jobId, partsCatalogId: part.id, qty: _qtyFor(part.id));
      if (result case Failure(message: final m)) _snack(m);
    } catch (_) {
      _snack('Something went wrong.');
    } finally {
      // Refetch on EVERY outcome: a timed-out add the backend applied shows up; a 409 locked / 403
      // not-assigned moves the screen on. The cart on screen is always the server's.
      if (mounted) await detail.refetch();
      if (mounted) {
        setState(() => _busyPartIds.remove(part.id));
        _reportBusy();
      }
    }
  }

  Future<void> _removeLine(JobPartLineDto line) async {
    if (_busyLineIds.contains(line.id)) return;
    final repo = ref.read(technicianJobRepositoryProvider);
    final detail = ref.read(jobDetailProvider(_jobId).notifier);
    setState(() => _busyLineIds.add(line.id));
    _reportBusy();
    try {
      final result = await repo.removePart(_jobId, line.id);
      if (result case Failure(message: final m)) _snack(m);
    } catch (_) {
      _snack('Something went wrong.');
    } finally {
      if (mounted) await detail.refetch();
      if (mounted) {
        setState(() => _busyLineIds.remove(line.id));
        _reportBusy();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final partsAsync = ref.watch(partsCatalogProvider(detail.job.service.categoryId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Parts', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          key: const Key('partsFilter'),
          controller: _filterController,
          decoration: const InputDecoration(labelText: 'Filter parts'),
        ),
        const SizedBox(height: 12),
        _buildPartsList(partsAsync),
        if (detail.parts.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('In this estimate', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final line in detail.parts) _buildCartLine(line),
        ],
        const SizedBox(height: 16),
        Text(
          'Customer will see: ${rupees(estimatePaise(detail.job, detail.parts))}',
          key: const Key('customerWillSee'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text('(labor + parts − visit fee)', style: TextStyle(fontSize: 12, color: FixCareColors.textMuted)),
      ],
    );
  }

  Widget _buildPartsList(AsyncValue<Result<List<PartCatalogDto>>> async) {
    return switch (async) {
      AsyncData(value: Ok(value: final parts)) => _partsColumn(parts),
      AsyncData(value: Failure(message: final m)) => _partsError(m),
      AsyncError() => _partsError('Something went wrong.'),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  /// A load failure must be recoverable in place — the technician is at the customer's door.
  Widget _partsError(String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('partsRetry'),
            onPressed: () => ref.invalidate(partsCatalogProvider(widget.detail.job.service.categoryId)),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  Widget _partsColumn(List<PartCatalogDto> parts) {
    final filtered = _filter.isEmpty ? parts : parts.where((p) => p.name.toLowerCase().contains(_filter)).toList();
    // Low-end devices: a plain Column of rows (no nested scrollable inside the screen's ListView).
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final p in filtered) _buildPartRow(p)]);
  }

  Widget _buildPartRow(PartCatalogDto part) {
    final qty = _qtyFor(part.id);
    final busy = _busyPartIds.contains(part.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(part.name),
                Text(rupees(part.ceilingPricePaise), style: const TextStyle(fontSize: 12, color: FixCareColors.textMuted)),
              ],
            ),
          ),
          IconButton(key: Key('qtyMinus_${part.id}'), icon: const Icon(Icons.remove), onPressed: busy ? null : () => _decQty(part.id)),
          Text('$qty'),
          IconButton(key: Key('qtyPlus_${part.id}'), icon: const Icon(Icons.add), onPressed: busy ? null : () => _incQty(part.id)),
          FilledButton(
            key: Key('addPartBtn_${part.id}'),
            onPressed: busy ? null : () => _addPart(part),
            child: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildCartLine(JobPartLineDto line) {
    final busy = _busyLineIds.contains(line.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        key: Key('cartLine_${line.id}'),
        children: [
          Expanded(child: Text('${line.name} × ${line.qty} · ${rupees(line.ceilingPricePaise * line.qty)}')),
          IconButton(
            key: Key('removePartBtn_${line.id}'),
            icon: const Icon(Icons.delete_outline),
            onPressed: busy ? null : () => _removeLine(line),
          ),
        ],
      ),
    );
  }
}

/// DIAGNOSED: the estimate has been sent and the cart is frozen (the backend rejects any change). Read-only
/// — the customer approves or declines in their app; the job poll moves this screen on.
class EstimateSentCard extends StatelessWidget {
  const EstimateSentCard({super.key, required this.detail});

  final TechnicianJobDetailDto detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('waitingApprovalCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estimate sent — waiting for the customer to approve or decline',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (detail.parts.isEmpty)
              const Text('Labor only — no parts.', key: Key('estimateLaborOnly'))
            else
              for (final p in detail.parts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('${p.name} × ${p.qty} · ${rupees(p.ceilingPricePaise * p.qty)}', key: Key('estimateLine_${p.id}')),
                ),
            const SizedBox(height: 12),
            Text(
              'Total: ${rupees(estimatePaise(detail.job, detail.parts))}',
              key: const Key('estimateTotal'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
