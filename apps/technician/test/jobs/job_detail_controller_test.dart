import 'dart:async';

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

/// A repo whose every mine() call stays in flight until the test completes it
/// (pending[i] is the i-th call) — for overlap / ordering tests.
class _GatedRepo extends TechnicianJobRepository {
  _GatedRepo() : super(Dio());
  final List<Completer<Result<List<TechnicianJobDto>>>> pending = [];
  int get calls => pending.length;
  @override
  Future<Result<List<TechnicianJobDto>>> mine() {
    final c = Completer<Result<List<TechnicianJobDto>>>();
    pending.add(c);
    return c.future;
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

  test('no second fetch starts while a poll is in flight; the next tick is armed only after it completes', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(repo.calls, 1);
      repo.pending[0].complete(Ok([_j('EN_ROUTE')]));
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 5)); // tick -> poll #2 starts, stays in flight
      expect(repo.calls, 2);
      async.elapse(const Duration(seconds: 30)); // slow network: no overlapping ticks
      expect(repo.calls, 2);

      repo.pending[1].complete(Ok([_j('ARRIVED')]));
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.state, 'ARRIVED');
      expect(repo.calls, 2, reason: 're-armed, not fired immediately');
      async.elapse(const Duration(seconds: 5));
      expect(repo.calls, 3);
      repo.pending[2].complete(Ok([_j('ARRIVED')]));
      async.flushMicrotasks();
    });
  });

  test('a stale response landing after a newer one is dropped (poll vs refetch)', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      repo.pending[0].complete(Ok([_j('ARRIVED')]));
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 5)); // poll #2 in flight (will carry the OLD state)
      expect(repo.calls, 2);
      c.read(jobDetailProvider('b1').notifier).refetch(); // #3, issued after the action
      async.flushMicrotasks();
      expect(repo.calls, 3);

      repo.pending[2].complete(Ok([_j('DIAGNOSED')])); // newer lands first
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.state, 'DIAGNOSED');

      repo.pending[1].complete(Ok([_j('ARRIVED')])); // older lands late
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.state, 'DIAGNOSED', reason: 'the stale poll must not regress the card');

      // Exactly one timer chain survives.
      async.elapse(const Duration(seconds: 5));
      expect(repo.calls, 4);
      repo.pending[3].complete(Ok([_j('DIAGNOSED')]));
      async.flushMicrotasks();
    });
  });

  test('pause() stops polling; resume() fetches once immediately and re-arms', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok([_j('EN_ROUTE')]),
        Ok([_j('ARRIVED')]),
        Ok([_j('DIAGNOSED')]),
      ]);
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(repo.calls, 1);

      c.read(jobDetailProvider('b1').notifier).pause();
      async.elapse(const Duration(minutes: 2));
      expect(repo.calls, 1, reason: 'no polling while backgrounded');

      c.read(jobDetailProvider('b1').notifier).resume();
      async.flushMicrotasks();
      expect(repo.calls, 2);
      expect(c.read(jobDetailProvider('b1')).value?.state, 'ARRIVED');

      async.elapse(const Duration(seconds: 5));
      expect(repo.calls, 3, reason: 'polling re-armed after resume');
      expect(c.read(jobDetailProvider('b1')).value?.state, 'DIAGNOSED');
    });
  });

  test('pause() while a poll is in flight: the completing poll does not re-arm', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      repo.pending[0].complete(Ok([_j('EN_ROUTE')]));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      expect(repo.calls, 2);

      c.read(jobDetailProvider('b1').notifier).pause();
      repo.pending[1].complete(Ok([_j('EN_ROUTE')]));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));

      expect(repo.calls, 2);
    });
  });

  test('resume() on a terminal job fetches once and does not re-arm', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok([_j('PAYMENT_RECEIVED')]),
      ]);
      final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      c.read(jobDetailProvider('b1').notifier).pause();
      c.read(jobDetailProvider('b1').notifier).resume();
      async.flushMicrotasks();
      expect(repo.calls, 2);
      async.elapse(const Duration(minutes: 1));
      expect(repo.calls, 2);
    });
  });
}
