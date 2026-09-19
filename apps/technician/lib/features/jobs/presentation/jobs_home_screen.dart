import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/result.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/technician_job_repository.dart';
import 'available_jobs_controller.dart';
import 'my_jobs_controller.dart';

/// Tracks which job cards currently have an in-flight accept, so a second tap
/// on the same card is a no-op while its request is outstanding.
class _BusyJobIds extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void add(String id) => state = {...state, id};
  void remove(String id) => state = {...state}..remove(id);
}

final _busyJobIdsProvider = NotifierProvider<_BusyJobIds, Set<String>>(_BusyJobIds.new);

class JobsHomeScreen extends ConsumerWidget {
  const JobsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(availableJobsControllerProvider);
    final mine = ref.watch(myJobsControllerProvider);

    return Scaffold(
      key: const Key('jobsHomeScreen'),
      appBar: AppBar(
        title: const Text('Jobs'),
        actions: [
          IconButton(
            key: const Key('logoutBtn'),
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _AvailableSection(async: available),
            const SizedBox(height: 24),
            const Text('My jobs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _MyJobsSection(async: mine),
          ],
        ),
      ),
    );
  }
}

class _AvailableSection extends ConsumerWidget {
  const _AvailableSection({required this.async});
  final AsyncValue<List<TechnicianJobDto>> async;

  Future<void> _onRefresh(WidgetRef ref) =>
      ref.read(availableJobsControllerProvider.notifier).refresh();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (async) {
      AsyncData(value: final jobs) when jobs.isEmpty => RefreshIndicator(
          onRefresh: () => _onRefresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            shrinkWrap: true,
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No jobs available right now', key: Key('noJobsEmpty')),
                ),
              ),
            ],
          ),
        ),
      AsyncData(value: final jobs) => RefreshIndicator(
          onRefresh: () => _onRefresh(ref),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: jobs.length,
            itemBuilder: (context, i) => _AvailableJobCard(job: jobs[i]),
          ),
        ),
      AsyncError(error: final e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('$e'),
        ),
      _ => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
    };
  }
}

class _AvailableJobCard extends ConsumerWidget {
  const _AvailableJobCard({required this.job});
  final TechnicianJobDto job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(_busyJobIdsProvider).contains(job.id);

    Future<void> onAccept() async {
      if (ref.read(_busyJobIdsProvider).contains(job.id)) return;
      ref.read(_busyJobIdsProvider.notifier).add(job.id);
      final r = await ref.read(availableJobsControllerProvider.notifier).accept(job.id);
      ref.read(_busyJobIdsProvider.notifier).remove(job.id);
      if (r is Failure<TechnicianJobDto> && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message)));
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.service.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 4),
            Text('Visit fee ${rupees(job.visitFeePaise)} · Labor ${rupees(job.laborPaise)}'),
            const SizedBox(height: 4),
            Text(job.zone.name),
            const SizedBox(height: 4),
            Text(_addressLine(job.address)),
            const SizedBox(height: 4),
            Text('Scheduled: ${job.scheduledSlot}'),
            const SizedBox(height: 4),
            Text(job.customer.maskedPhone),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: Key('acceptJob_${job.id}'),
                onPressed: busy ? null : onAccept,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Accept'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyJobsSection extends ConsumerWidget {
  const _MyJobsSection({required this.async});
  final AsyncValue<List<TechnicianJobDto>> async;

  Future<void> _onRefresh(WidgetRef ref) => ref.read(myJobsControllerProvider.notifier).refresh();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (async) {
      AsyncData(value: final jobs) when jobs.isEmpty => RefreshIndicator(
          onRefresh: () => _onRefresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            shrinkWrap: true,
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No accepted jobs yet')),
              ),
            ],
          ),
        ),
      AsyncData(value: final jobs) => RefreshIndicator(
          onRefresh: () => _onRefresh(ref),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: jobs.length,
            itemBuilder: (context, i) => _MyJobCard(job: jobs[i]),
          ),
        ),
      AsyncError(error: final e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('$e'),
        ),
      _ => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
    };
  }
}

class _MyJobCard extends StatelessWidget {
  const _MyJobCard({required this.job});
  final TechnicianJobDto job;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.service.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 4),
            Text('Visit fee ${rupees(job.visitFeePaise)} · Labor ${rupees(job.laborPaise)}'),
            const SizedBox(height: 4),
            Text(job.zone.name),
            const SizedBox(height: 4),
            Text(_addressLine(job.address)),
            const SizedBox(height: 4),
            Text('Scheduled: ${job.scheduledSlot}'),
            const SizedBox(height: 4),
            Text(job.customer.maskedPhone),
            const SizedBox(height: 4),
            Text('State: ${job.state}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

String _addressLine(JobAddressDto a) {
  final parts = [a.line1, if (a.landmark != null && a.landmark!.isNotEmpty) a.landmark, a.pincode];
  return parts.join(', ');
}
