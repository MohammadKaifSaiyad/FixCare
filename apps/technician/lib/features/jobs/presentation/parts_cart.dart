import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/format.dart';
import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/catalog_repository.dart';
import '../data/technician_job_repository.dart';

part 'parts_cart.g.dart';

/// One line the technician has added to the (not-yet-submitted) parts cart
/// for this job — a catalog part plus a quantity, keyed by the id the backend
/// returned from `addPart` (needed to `removePart` later).
@immutable
class CartLine {
  const CartLine({required this.lineId, required this.part, required this.qty});

  final String lineId;
  final PartCatalogDto part;
  final int qty;
}

/// Session-scoped cart state per job (keepAlive: survives leaving and
/// re-opening the job detail screen within the same app session — NOT an app
/// restart; the job DTO carries no parts array to rehydrate from, so a
/// restart losing the in-progress cart is a deferred follow-up). Backend
/// `addPart`/`removePart` are the source of truth; this just mirrors what
/// succeeded there so the UI can render the cart + estimate.
@Riverpod(keepAlive: true)
class JobCart extends _$JobCart {
  @override
  List<CartLine> build(String bookingId) => const [];

  void add(CartLine line) => state = [...state, line];

  void remove(String lineId) => state = state.where((l) => l.lineId != lineId).toList();
}

/// Pure, integer-paise estimate: labor + parts (ceiling price × qty) − visit
/// fee (already collected/locked at arrival), floored at 0. Never negative —
/// a customer never sees a negative "estimate".
int indicativeEstimatePaise(TechnicianJobDto job, List<CartLine> lines) {
  final partsTotal = lines.fold<int>(0, (sum, l) => sum + l.part.ceilingPricePaise * l.qty);
  final estimate = job.laborPaise + partsTotal - job.visitFeePaise;
  return estimate < 0 ? 0 : estimate;
}

final _partsProvider = FutureProvider.autoDispose<Result<List<PartCatalogDto>>>((ref) {
  return ref.read(catalogRepositoryProvider).parts();
});

/// DIAGNOSED: the cart is open (the backend only accepts addPart/removePart
/// while the booking is DIAGNOSED — it locks the moment the customer
/// approves or declines the estimate).
class PartsCartCard extends ConsumerStatefulWidget {
  const PartsCartCard({super.key, required this.job});

  final TechnicianJobDto job;

  @override
  ConsumerState<PartsCartCard> createState() => _PartsCartCardState();
}

class _PartsCartCardState extends ConsumerState<PartsCartCard> {
  final _filterController = TextEditingController();
  String _filter = '';

  // Selected qty per part (1..99, default 1) — UI-only until Add is tapped.
  final Map<String, int> _qty = {};

  // Per-action busy sets: only the button for the in-flight part/line is
  // disabled, and a repeat tap on it is a no-op (ignored double-tap).
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

  int _qtyFor(String partId) => _qty[partId] ?? 1;

  void _incQty(String partId) => setState(() => _qty[partId] = (_qtyFor(partId) + 1).clamp(1, 99));
  void _decQty(String partId) => setState(() => _qty[partId] = (_qtyFor(partId) - 1).clamp(1, 99));

  Future<void> _addPart(PartCatalogDto part) async {
    if (_busyPartIds.contains(part.id)) return;
    setState(() => _busyPartIds.add(part.id));
    try {
      final qty = _qtyFor(part.id);
      final result =
          await ref.read(technicianJobRepositoryProvider).addPart(widget.job.id, partsCatalogId: part.id, qty: qty);
      if (!mounted) return;
      switch (result) {
        case Ok(value: final lineId):
          ref.read(jobCartProvider(widget.job.id).notifier).add(CartLine(lineId: lineId, part: part, qty: qty));
        case Failure(message: final m):
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong.')));
      }
    } finally {
      if (mounted) setState(() => _busyPartIds.remove(part.id));
    }
  }

  Future<void> _removeLine(CartLine line) async {
    if (_busyLineIds.contains(line.lineId)) return;
    setState(() => _busyLineIds.add(line.lineId));
    try {
      final result = await ref.read(technicianJobRepositoryProvider).removePart(widget.job.id, line.lineId);
      if (!mounted) return;
      switch (result) {
        case Ok():
          ref.read(jobCartProvider(widget.job.id).notifier).remove(line.lineId);
        case Failure(message: final m):
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong.')));
      }
    } finally {
      if (mounted) setState(() => _busyLineIds.remove(line.lineId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final lines = ref.watch(jobCartProvider(job.id));
    final partsAsync = ref.watch(_partsProvider);

    return Card(
      key: const Key('waitingApprovalCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Waiting for the customer to approve the estimate. Add the parts this repair '
              'needs now — the cart locks once the customer decides.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('partsFilter'),
              controller: _filterController,
              decoration: const InputDecoration(labelText: 'Filter parts'),
            ),
            const SizedBox(height: 12),
            _buildPartsList(partsAsync),
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('In cart', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final line in lines) _buildCartLine(line),
            ],
            const SizedBox(height: 16),
            Text(
              'Indicative estimate: ${rupees(indicativeEstimatePaise(job, lines))}',
              key: const Key('indicativeEstimate'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              '(labor + parts − visit fee; the customer sees the final amount)',
              style: TextStyle(fontSize: 12, color: FixCareColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartsList(AsyncValue<Result<List<PartCatalogDto>>> async) {
    return switch (async) {
      AsyncData(value: Ok(value: final parts)) => _partsColumn(parts),
      AsyncData(value: Failure(message: final m)) => Text(m),
      AsyncError() => const Text('Something went wrong.'),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _partsColumn(List<PartCatalogDto> parts) {
    final filtered =
        _filter.isEmpty ? parts : parts.where((p) => p.name.toLowerCase().contains(_filter)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // Low-end devices: a plain Column of rows (no nested ListView/scrollable
      // inside the screen's outer ListView).
      children: [for (final p in filtered) _buildPartRow(p)],
    );
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
                Text(
                  rupees(part.ceilingPricePaise),
                  style: const TextStyle(fontSize: 12, color: FixCareColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('qtyMinus_${part.id}'),
            icon: const Icon(Icons.remove),
            onPressed: busy ? null : () => _decQty(part.id),
          ),
          Text('$qty'),
          IconButton(
            key: Key('qtyPlus_${part.id}'),
            icon: const Icon(Icons.add),
            onPressed: busy ? null : () => _incQty(part.id),
          ),
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

  Widget _buildCartLine(CartLine line) {
    final busy = _busyLineIds.contains(line.lineId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        key: Key('cartLine_${line.lineId}'),
        children: [
          Expanded(
            child: Text('${line.part.name} × ${line.qty} · ${rupees(line.part.ceilingPricePaise * line.qty)}'),
          ),
          IconButton(
            key: Key('removePartBtn_${line.lineId}'),
            icon: const Icon(Icons.delete_outline),
            onPressed: busy ? null : () => _removeLine(line),
          ),
        ],
      ),
    );
  }
}
