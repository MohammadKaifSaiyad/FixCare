import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/result.dart';
import '../data/technician_job_repository.dart';
import 'job_action.dart';
import 'job_detail_controller.dart';
import 'location_service.dart';

/// The job-detail screen: renders the job and a state-driven phase-action
/// card (via [jobActionFor]). Wires every card except the two photo phases
/// (diagnose = Task 7 placeholder, completeRepair = Task 8 placeholder).
class JobDetailScreen extends ConsumerStatefulWidget {
  const JobDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  // Shared busy flag: only one action card is ever visible at a time (the
  // phase-action card chosen by jobActionFor), so a single screen-level flag
  // is enough to disable its button(s) and block a double-tap.
  bool _busy = false;

  // Arrive-card-only state: the arrival code survives poll rebuilds while the
  // job is still EN_ROUTE (the state doesn't change on arrive — the poll
  // flips it to ARRIVED once the customer confirms).
  String? _arrivalCode;
  String? _arriveError;

  Future<void> _refetch() => ref.read(jobDetailProvider(widget.bookingId).notifier).refetch();

  /// enRoute/startRepair/partsNeeded/partsAcquired: a Failure surfaces as a
  /// SnackBar (verbatim message) and either way we refetch — this self-heals
  /// a stale card if the backend rejected the action because state moved on.
  /// `_busy` is always reset in `finally` — the repo's `_guard` only catches
  /// `DioException`, so a non-Dio throw (e.g. a malformed-response TypeError)
  /// must not strand the button disabled forever; it's surfaced as a generic
  /// SnackBar rather than swallowed.
  Future<void> _runOneTap(Future<Result<void>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      if (result case Failure(message: final m)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      }
      await _refetch();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// `_busy` is reset in `finally` for the same reason as [_runOneTap]: an
  /// unexpected throw (from the location read or the repo call) must not
  /// strand the technician on a permanently-disabled arrive button.
  Future<void> _onArrive() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _arriveError = null;
    });
    try {
      final loc = await ref.read(locationServiceProvider).current();
      if (!mounted) return;
      if (loc == null) {
        setState(() {
          _arriveError = "Couldn't get your location. Make sure location is on and try again.";
        });
        return;
      }
      final result =
          await ref.read(technicianJobRepositoryProvider).arrive(widget.bookingId, lat: loc.lat, lng: loc.lng);
      if (!mounted) return;
      switch (result) {
        case Ok(value: final v):
          setState(() {
            _arrivalCode = v.arrivalCode;
            _arriveError = null;
          });
        case Failure(message: final m):
          setState(() => _arriveError = m);
      }
    } catch (_) {
      if (mounted) setState(() => _arriveError = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Result<void>> _submitCompletion(String code) async {
    final result = await ref.read(technicianJobRepositoryProvider).confirmCompletion(widget.bookingId, code);
    if (!mounted) return result;
    if (result case Ok()) await _refetch();
    return result;
  }

  Future<Result<CashResultDto>> _submitCash(String code) async {
    final result = await ref.read(technicianJobRepositoryProvider).confirmCash(widget.bookingId, code);
    if (!mounted) return result;
    if (result case Ok()) await _refetch();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(jobDetailProvider(widget.bookingId));

    return Scaffold(
      key: const Key('jobDetailScreen'),
      appBar: AppBar(title: Text(async.value?.bookingNumber ?? 'Job')),
      body: SafeArea(
        child: switch (async) {
          AsyncData(value: final job) => _buildBody(job),
          AsyncError() => _buildError(),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Couldn't load this job."),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('jobDetailRetry'),
            onPressed: () => ref.invalidate(jobDetailProvider(widget.bookingId)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(TechnicianJobDto job) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _JobInfoCard(job: job),
        const SizedBox(height: 16),
        _buildActionCard(job),
      ],
    );
  }

  Widget _buildActionCard(TechnicianJobDto job) {
    switch (jobActionFor(job)) {
      case JobAction.enRoute:
        return _OneTapCard(
          buttonKey: const Key('enRouteBtn'),
          label: "I'm on my way",
          busy: _busy,
          onPressed: () => _runOneTap(() => ref.read(technicianJobRepositoryProvider).enRoute(widget.bookingId)),
        );
      case JobAction.arrive:
        return _ArriveCard(
          busy: _busy,
          arrivalCode: _arrivalCode,
          error: _arriveError,
          onPressed: _onArrive,
        );
      case JobAction.waitingConfirm:
        return const _ReadOnlyCard(text: 'Waiting for the customer.');
      case JobAction.diagnose:
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('diagnosis form — task 7', key: Key('diagnosePlaceholder')),
          ),
        );
      case JobAction.waitingApproval:
        return const _ReadOnlyCard(
          key: Key('waitingApprovalCard'),
          text: 'Waiting for the customer to approve the estimate.',
        );
      case JobAction.startRepair:
        return _StartRepairCard(
          busy: _busy,
          showPartsNeeded: job.state == 'CUSTOMER_APPROVED',
          onStartRepair: () =>
              _runOneTap(() => ref.read(technicianJobRepositoryProvider).startRepair(widget.bookingId)),
          onPartsNeeded: () =>
              _runOneTap(() => ref.read(technicianJobRepositoryProvider).partsNeeded(widget.bookingId)),
        );
      case JobAction.partsNeeded:
        return const _ReadOnlyCard(text: 'Parts requested — waiting for pickup.');
      case JobAction.partsAcquired:
        return _OneTapCard(
          buttonKey: const Key('partsAcquiredBtn'),
          label: 'Parts acquired',
          busy: _busy,
          onPressed: () =>
              _runOneTap(() => ref.read(technicianJobRepositoryProvider).partsAcquired(widget.bookingId)),
        );
      case JobAction.completeRepair:
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('repair photos — task 8', key: Key('repairPlaceholder')),
          ),
        );
      case JobAction.confirmCompletion:
        return _CodeEntryCard<void>(
          key: const ValueKey('completionCodeCard'),
          fieldKey: const Key('completionCodeField'),
          buttonKey: const Key('confirmCompletionBtn'),
          buttonLabel: 'Confirm completion',
          onSubmit: _submitCompletion,
        );
      case JobAction.confirmCash:
        return _CodeEntryCard<CashResultDto>(
          key: const ValueKey('cashCodeCard'),
          fieldKey: const Key('cashCodeField'),
          buttonKey: const Key('confirmCashBtn'),
          buttonLabel: 'Confirm cash received',
          onSubmit: _submitCash,
        );
      case JobAction.terminal:
        return _TerminalCard(state: job.state);
    }
  }
}

class _JobInfoCard extends StatelessWidget {
  const _JobInfoCard({required this.job});
  final TechnicianJobDto job;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.service.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 4),
            Text(job.zone.name),
            const SizedBox(height: 4),
            Text(_addressLine(job.address)),
            const SizedBox(height: 4),
            Text('Scheduled: ${job.scheduledSlot}'),
            const SizedBox(height: 4),
            Text(job.customer.maskedPhone),
            const SizedBox(height: 8),
            Text('Visit fee ${rupees(job.visitFeePaise)} · Labor ${rupees(job.laborPaise)}'),
          ],
        ),
      ),
    );
  }
}

String _addressLine(JobAddressDto a) {
  final parts = [
    a.line1,
    if (a.line2 != null && a.line2!.isNotEmpty) a.line2,
    if (a.landmark != null && a.landmark!.isNotEmpty) a.landmark,
    a.pincode,
  ];
  return parts.join(', ');
}

class _ReadOnlyCard extends StatelessWidget {
  const _ReadOnlyCard({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}

class _OneTapCard extends StatelessWidget {
  const _OneTapCard({
    required this.buttonKey,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: buttonKey,
            onPressed: busy ? null : onPressed,
            child: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(label),
          ),
        ),
      ),
    );
  }
}

class _ArriveCard extends StatelessWidget {
  const _ArriveCard({
    required this.busy,
    required this.arrivalCode,
    required this.error,
    required this.onPressed,
  });

  final bool busy;
  final String? arrivalCode;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final code = arrivalCode;
    final err = error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (code != null) ...[
              Text(code, key: const Key('arrivalCode'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Read this code to your customer. Waiting for them to confirm…'),
              const SizedBox(height: 12),
            ],
            if (err != null) ...[
              Text(err, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('arriveBtn'),
                onPressed: busy ? null : onPressed,
                child: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(code != null ? 'Get a new code' : "I've arrived"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartRepairCard extends StatelessWidget {
  const _StartRepairCard({
    required this.busy,
    required this.showPartsNeeded,
    required this.onStartRepair,
    required this.onPartsNeeded,
  });

  final bool busy;
  final bool showPartsNeeded;
  final VoidCallback onStartRepair;
  final VoidCallback onPartsNeeded;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (showPartsNeeded)
              OutlinedButton(
                key: const Key('partsNeededBtn'),
                onPressed: busy ? null : onPartsNeeded,
                child: const Text('Need parts'),
              ),
            FilledButton(
              key: const Key('startRepairBtn'),
              onPressed: busy ? null : onStartRepair,
              child: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Start repair'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 6-char code entry card, reused for both the completion and cash
/// confirmations. `T` is the repository call's success payload type (void for
/// completion, [CashResultDto] for cash) — only whether the Result is Ok or
/// Failure matters here, so it's generic rather than duplicated.
class _CodeEntryCard<T> extends StatefulWidget {
  const _CodeEntryCard({
    super.key,
    required this.fieldKey,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onSubmit,
  });

  final Key fieldKey;
  final Key buttonKey;
  final String buttonLabel;
  final Future<Result<T>> Function(String code) onSubmit;

  @override
  State<_CodeEntryCard<T>> createState() => _CodeEntryCardState<T>();
}

class _CodeEntryCardState<T> extends State<_CodeEntryCard<T>> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit => _controller.text.trim().length == 6 && !_busy;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final code = _controller.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSubmit(code);
      if (!mounted) return;
      if (result case Failure(message: final m)) {
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: widget.fieldKey,
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: InputDecoration(labelText: 'Enter code', errorText: _error),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: widget.buttonKey,
                onPressed: _canSubmit ? _submit : null,
                child: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      'PAYMENT_RECEIVED' || 'CLOSED' => 'Paid',
      'CANCELLED_BY_CUSTOMER' || 'CANCELLED_BY_TECHNICIAN' => 'Cancelled',
      _ => 'Closed',
    };
    return Card(
      key: const Key('terminalSummary'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('$label — $state'),
      ),
    );
  }
}
