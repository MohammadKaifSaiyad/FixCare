import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_detail_controller.dart';

TechnicianJobDto _j(String state, {String id = 'b1'}) => TechnicianJobDto.fromJson({
  'id': id, 'bookingNumber': 'FC-1', 'state': state, 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Svc', 'requiredSkill': 'FAN'}, 'zone': {'name': 'Padra'},
  'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'x', 'line2': null, 'landmark': null, 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
});

/// A scripted repo: mine() returns results[callIndex], clamping at the last entry.
class _ScriptedRepo extends TechnicianJobRepository {
  _ScriptedRepo(this.results) : super(Dio());
  final List<Result<List<TechnicianJobDto>>> results;
  int calls = 0;
  @override
  Future<Result<List<TechnicianJobDto>>> mine() async {
    final r = results[calls < results.length ? calls : results.length - 1];
    calls++;
    return r;
  }
}

void main() {
  test('first load finds the job by id in mine()', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok([_j('EN_ROUTE'), _j('ACCEPTED', id: 'other')]),
      ]);
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(repo.calls, 1);
      expect(c.read(jobDetailProvider('b1')).value?.state, 'EN_ROUTE');
    });
  });

  test('polls every 5s while active; stops once terminal', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok([_j('EN_ROUTE')]),
        Ok([_j('ARRIVED')]),
        Ok([_j('PAYMENT_RECEIVED')]),
        Ok([_j('PAYMENT_RECEIVED')]),
      ]);
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks(); // first load
      expect(repo.calls, 1);
      async.elapse(const Duration(seconds: 5)); // tick -> ARRIVED
      expect(repo.calls, 2);
      async.elapse(const Duration(seconds: 5)); // tick -> PAYMENT_RECEIVED (terminal, timer cancels)
      expect(repo.calls, 3);
      async.elapse(const Duration(seconds: 15)); // no more polls after terminal
      expect(repo.calls, 3);
    });
  });

  test('a poll Failure keeps the last good job (keep-last-good)', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok([_j('EN_ROUTE')]),
        const Failure(FailureKind.network, 'blip'),
        Ok([_j('ARRIVED')]),
      ]);
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5)); // tick -> Failure
      final afterBlip = c.read(jobDetailProvider('b1'));
      expect(afterBlip.value?.state, 'EN_ROUTE', reason: 'last-good retained on a poll failure');
      expect(afterBlip.hasError, isFalse);
      async.elapse(const Duration(seconds: 5)); // tick -> ARRIVED
      expect(c.read(jobDetailProvider('b1')).value?.state, 'ARRIVED');
    });
  });

  test('a poll where the job disappears from mine() keeps the last good job', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok([_j('EN_ROUTE')]),
        Ok([_j('ACCEPTED', id: 'other')]), // b1 no longer present
        Ok([_j('ARRIVED')]),
      ]);
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5)); // tick -> not found
      expect(c.read(jobDetailProvider('b1')).value?.state, 'EN_ROUTE');
      async.elapse(const Duration(seconds: 5)); // tick -> ARRIVED
      expect(c.read(jobDetailProvider('b1')).value?.state, 'ARRIVED');
    });
  });

  test('first-load Failure surfaces as AsyncError', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([const Failure(FailureKind.network, 'offline')]);
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).hasError, isTrue);
    });
  });

  test('first-load not-found (job absent from mine()) surfaces as AsyncError', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok([_j('ACCEPTED', id: 'other')]),
      ]);
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).hasError, isTrue);
    });
  });

  test('refetch() reloads immediately without flashing AsyncLoading and re-arms polling', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok([_j('ARRIVED')]),
        Ok([_j('DIAGNOSED')]), // simulated result of a diagnose action, pulled by refetch()
        Ok([_j('CUSTOMER_APPROVED')]),
      ]);
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.state, 'ARRIVED');

      final states = <bool>[];
      c.listen(jobDetailProvider('b1'), (_, next) => states.add(next.isLoading), fireImmediately: false);
      c.read(jobDetailProvider('b1').notifier).refetch();
      async.flushMicrotasks();
      expect(states, isNot(contains(true)), reason: 'refetch must never flash AsyncLoading');
      expect(c.read(jobDetailProvider('b1')).value?.state, 'DIAGNOSED');

      // polling continues after refetch's re-arm
      async.elapse(const Duration(seconds: 5));
      expect(c.read(jobDetailProvider('b1')).value?.state, 'CUSTOMER_APPROVED');
    });
  });
}
