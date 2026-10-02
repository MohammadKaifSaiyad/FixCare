import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/catalog_repository.dart';
import '../data/technician_job_repository.dart';
import 'job_detail_controller.dart';

/// One estimate line — `<name> × <qty> · <line total>` from the DTO's own [JobPartLineDto.lineTotalPaise].
/// The single line widget for the cart, the confirm dialog and the read-only sent card, so the three can
/// never disagree.
class PartLineText extends StatelessWidget {
  const PartLineText(this.line, {super.key});

  final JobPartLineDto line;

  @override
  Widget build(BuildContext context) => Text('${line.name} × ${line.qty} · ${rupees(line.lineTotalPaise)}');
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
/// cart. If that refetch fails, the cart on screen is marked unconfirmed (Submit stays blocked) until a
/// fetch ISSUED AFTER it succeeds (tracked by fetch sequence, so an unchanged poll clears it and an older
/// in-flight one does not). Catalog prices only (Golden Rule 4): the technician picks a part and a qty,
/// never a price; the "Customer will see" amount is the backend's own quote.
class PartsSection extends ConsumerStatefulWidget {
  const PartsSection({super.key, required this.detail, required this.onBusyChanged, this.enabled = true});

  final TechnicianJobDetailDto detail;

  /// Whether the cart is unsettled — an edit in flight, or the cart on screen not yet confirmed by the
  /// server. The form blocks "Submit diagnosis" while true, so the estimate sent is the one on screen.
  final ValueChanged<bool> onBusyChanged;

  /// False while the estimate is being sent (confirm dialog open / diagnose in flight): every cart control
  /// is disabled, so nothing can change between "Send estimate" and the backend freezing the cart.
  final bool enabled;

  @override
  ConsumerState<PartsSection> createState() => _PartsSectionState();
}

/// With an empty filter the catalog list shows at most this many rows (low-end devices: a plain Column,
/// no lazy list inside the screen's ListView) — typing narrows to every match.
const _unfilteredPartRows = 8;

class _PartsSectionState extends ConsumerState<PartsSection> {
  final _filterController = TextEditingController();
  String _filter = '';
  final Set<String> _busyPartIds = {};
  final Set<String> _busyLineIds = {};
  // The last refetch after a cart edit failed: what the server holds may differ from the screen. Cleared
  // when a fetch with a seq GREATER than [_unconfirmedSeq] (the failed refetch's) comes back Ok.
  bool _cartUnconfirmed = false;
  int _unconfirmedSeq = 0;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _filterController.addListener(_onFilterChanged);
  }

  // The controller also notifies on cursor/selection moves — rebuild only when the filter text changed.
  void _onFilterChanged() {
    final next = _filterController.text.trim().toLowerCase();
    if (next == _filter) return;
    setState(() => _filter = next);
  }

  @override
  void dispose() {
    _filterController.removeListener(_onFilterChanged);
    _filterController.dispose();
    super.dispose();
  }

  String get _jobId => widget.detail.job.id;

  void _reportBusy() => widget.onBusyChanged(
      _busyPartIds.isNotEmpty || _busyLineIds.isNotEmpty || _cartUnconfirmed || _retrying);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Refetch the job so the cart on screen is the server's; a failed (or throwing) refetch leaves it
  /// unconfirmed — unless a fetch issued after it already succeeded. Never throws.
  Future<void> _confirmCart(JobDetail detail) async {
    if (!mounted) return;
    var ok = false;
    final pending = detail.refetch();
    // Read synchronously: the seq this refetch went out with (a poll issued meanwhile is newer).
    final issuedSeq = detail.lastIssuedSeq;
    try {
      ok = await pending;
    } catch (e, st) {
      reportJobsError(e, st, 'while confirming the parts cart');
      ok = false;
    }
    if (!mounted) return;
    // A newer fetch may have succeeded between the refetch failing and this line running.
    final confirmed = ok || ref.read(jobFetchOkSeqProvider(_jobId)) > issuedSeq;
    setState(() {
      _cartUnconfirmed = !confirmed;
      if (!confirmed) _unconfirmedSeq = issuedSeq;
    });
  }

  /// Any fetch issued after the failed refetch came back Ok — even one that changed nothing on screen.
  void _onFetchOk(int? _, int okSeq) {
    if (!_cartUnconfirmed || okSeq <= _unconfirmedSeq) return;
    setState(() => _cartUnconfirmed = false);
    _reportBusy();
  }

  Future<void> _addPart(PartCatalogDto part, int qty) async {
    if (!widget.enabled || _busyPartIds.contains(part.id)) return;
    final repo = ref.read(technicianJobRepositoryProvider);
    final detail = ref.read(jobDetailProvider(_jobId).notifier);
    setState(() => _busyPartIds.add(part.id));
    _reportBusy();
    try {
      try {
        final result = await repo.addPart(_jobId, partsCatalogId: part.id, qty: qty);
        if (result case Failure(message: final m)) _snack(m);
      } catch (e, st) {
        reportJobsError(e, st, 'while adding a part to the estimate');
        _snack('Something went wrong.');
      }
      // Refetch on EVERY outcome: a timed-out add the backend applied shows up; a 409 locked / 403
      // not-assigned moves the screen on. The cart on screen is always the server's.
      await _confirmCart(detail);
    } finally {
      if (mounted) {
        setState(() => _busyPartIds.remove(part.id));
        _reportBusy();
      }
    }
  }

  Future<void> _removeLine(JobPartLineDto line) async {
    if (!widget.enabled || _busyLineIds.contains(line.id)) return;
    final repo = ref.read(technicianJobRepositoryProvider);
    final detail = ref.read(jobDetailProvider(_jobId).notifier);
    setState(() => _busyLineIds.add(line.id));
    _reportBusy();
    try {
      try {
        final result = await repo.removePart(_jobId, line.id);
        if (result case Failure(message: final m)) _snack(m);
      } catch (e, st) {
        reportJobsError(e, st, 'while removing a part from the estimate');
        _snack('Something went wrong.');
      }
      await _confirmCart(detail);
    } finally {
      if (mounted) {
        setState(() => _busyLineIds.remove(line.id));
        _reportBusy();
      }
    }
  }

  Future<void> _retryConfirm() async {
    if (!widget.enabled || _retrying) return;
    final detail = ref.read(jobDetailProvider(_jobId).notifier);
    setState(() => _retrying = true);
    _reportBusy();
    try {
      await _confirmCart(detail);
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
        _reportBusy();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    ref.listen<int>(jobFetchOkSeqProvider(_jobId), _onFetchOk);
    final partsAsync = ref.watch(partsCatalogProvider(detail.job.service.categoryId));
    final quote = detail.customerQuote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Parts', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          key: const Key('partsFilter'),
          controller: _filterController,
          enabled: widget.enabled,
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
        if (_cartUnconfirmed) ...[
          const SizedBox(height: 12),
          Row(
            key: const Key('cartUnconfirmedNotice'),
            children: [
              const Expanded(
                child: Text("Couldn't confirm the latest parts.", style: TextStyle(color: FixCareColors.errorText)),
              ),
              TextButton(
                key: const Key('cartUnconfirmedRetry'),
                onPressed: widget.enabled && !_retrying ? _retryConfirm : null,
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
        // The backend's own quote (computeEstimate) — no quote (an older backend) hides the amount rather
        // than re-deriving a money figure on the device.
        if (quote != null) ...[
          const SizedBox(height: 16),
          Text(
            'Customer will see: ${rupees(quote.totalPayablePaise)}',
            key: const Key('customerWillSee'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text('(labor + parts − visit fee)', style: TextStyle(fontSize: 12, color: FixCareColors.textMuted)),
        ],
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
            onPressed: widget.enabled
                ? () => ref.invalidate(partsCatalogProvider(widget.detail.job.service.categoryId))
                : null,
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  Widget _partsColumn(List<PartCatalogDto> parts) {
    final matches = _filter.isEmpty ? parts : parts.where((p) => p.name.toLowerCase().contains(_filter)).toList();
    if (matches.isEmpty) {
      return const Text('No matching parts', key: Key('partsEmpty'), style: TextStyle(color: FixCareColors.textMuted));
    }
    final shown = _filter.isEmpty && matches.length > _unfilteredPartRows ? matches.take(_unfilteredPartRows).toList() : matches;
    final hidden = matches.length - shown.length;
    // One line per part (backend-enforced): a part already in the estimate offers no second Add.
    final inEstimate = {for (final l in widget.detail.parts) l.partsCatalogId};
    // Low-end devices: a plain Column of rows (no nested scrollable inside the screen's ListView).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in shown)
          _PartRow(
            key: ValueKey(p.id),
            part: p,
            busy: _busyPartIds.contains(p.id),
            enabled: widget.enabled,
            inEstimate: inEstimate.contains(p.id),
            onAdd: (qty) => _addPart(p, qty),
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Type to find more parts ($hidden more)',
              key: const Key('partsMoreHint'),
              style: const TextStyle(fontSize: 12, color: FixCareColors.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _buildCartLine(JobPartLineDto line) {
    final busy = _busyLineIds.contains(line.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        key: Key('cartLine_${line.id}'),
        children: [
          Expanded(child: PartLineText(line)),
          IconButton(
            key: Key('removePartBtn_${line.id}'),
            tooltip: 'Remove part',
            icon: const Icon(Icons.delete_outline),
            onPressed: busy || !widget.enabled ? null : () => _removeLine(line),
          ),
        ],
      ),
    );
  }
}

/// One catalog part with its own qty stepper — a qty tap rebuilds only this row. `busy` (an add of this
/// part in flight) comes from the section. `inEstimate`: the part already has a line in the cart — the row
/// shows "In estimate" instead of Add and its stepper is disabled (remove the line to change the qty).
class _PartRow extends StatefulWidget {
  const _PartRow({
    super.key,
    required this.part,
    required this.busy,
    required this.enabled,
    required this.inEstimate,
    required this.onAdd,
  });

  final PartCatalogDto part;
  final bool busy;
  final bool enabled;
  final bool inEstimate;
  final ValueChanged<int> onAdd;

  @override
  State<_PartRow> createState() => _PartRowState();
}

class _PartRowState extends State<_PartRow> {
  int _qty = 1; // 1..99 (the backend's per-line cap) — UI-only until Add

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    final active = widget.enabled && !widget.busy && !widget.inEstimate;
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
          IconButton(
            key: Key('qtyMinus_${part.id}'),
            tooltip: 'Fewer',
            icon: const Icon(Icons.remove),
            onPressed: active ? () => setState(() => _qty = (_qty - 1).clamp(1, 99)) : null,
          ),
          Text('$_qty'),
          IconButton(
            key: Key('qtyPlus_${part.id}'),
            tooltip: 'More',
            icon: const Icon(Icons.add),
            onPressed: active ? () => setState(() => _qty = (_qty + 1).clamp(1, 99)) : null,
          ),
          if (widget.inEstimate)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('In estimate',
                  key: Key('inEstimate_${part.id}'), style: const TextStyle(color: FixCareColors.textMuted)),
            )
          else
            FilledButton(
              key: Key('addPartBtn_${part.id}'),
              onPressed: active ? () => widget.onAdd(_qty) : null,
              child: widget.busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add'),
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
    final quote = detail.customerQuote;
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
                  child: PartLineText(p, key: Key('estimateLine_${p.id}')),
                ),
            // The backend's quote — hidden (never recomputed) when an older backend sends none.
            if (quote != null) ...[
              const SizedBox(height: 12),
              Text(
                'Total: ${rupees(quote.totalPayablePaise)}',
                key: const Key('estimateTotal'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
