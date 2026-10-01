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

Result<TechnicianJobDetailDto> _d(String state, {String id = 'b1', List<JobPartLineDto> parts = const []}) =>
    Ok(TechnicianJobDetailDto(job: _j(state, id: id), parts: parts));

const _mineForbidden = 'the job-detail controller must not call mine()';

/// A scripted repo: job(id) returns results[callIndex], clamping at the last entry.
class _ScriptedRepo extends TechnicianJobRepository {
  _ScriptedRepo(this.results) : super(Dio());
  final List<Result<TechnicianJobDetailDto>> results;
  int calls = 0;
  final List<String> ids = [];
  @override
  Future<Result<List<TechnicianJobDto>>> mine() async => throw StateError(_mineForbidden);
  @override
  Future<Result<TechnicianJobDetailDto>> job(String id) async {
    ids.add(id);
    final r = results[calls < results.length ? calls : results.length - 1];
    calls++;
    return r;
  }
}

/// A repo whose every job(id) call stays in flight until the test completes it
/// (pending[i] is the i-th call) — for overlap / ordering tests.
class _GatedRepo extends TechnicianJobRepository {
  _GatedRepo() : super(Dio());
  final List<Completer<Result<TechnicianJobDetailDto>>> pending = [];
  int get calls => pending.length;
  @override
  Future<Result<List<TechnicianJobDto>>> mine() async => throw StateError(_mineForbidden);
  @override
  Future<Result<TechnicianJobDetailDto>> job(String id) {
    final c = Completer<Result<TechnicianJobDetailDto>>();
    pending.add(c);
    return c.future;
  }
}

/// A mutable repo: serves `current` + `parts` from job(id); a test can set a one-shot `nextJobResult`
/// (cleared after use) to script a single failure.
class _FakeRepo extends TechnicianJobRepository {
  _FakeRepo() : super(Dio());
  TechnicianJobDto current = _j('EN_ROUTE');
  final List<JobPartLineDto> parts = [];
  Result<TechnicianJobDetailDto>? nextJobResult;
  int jobCalls = 0;

  @override
  Future<Result<List<TechnicianJobDto>>> mine() async => throw StateError(_mineForbidden);

  @override
  Future<Result<TechnicianJobDetailDto>> job(String id) async {
    jobCalls++;
    final scripted = nextJobResult;
    nextJobResult = null;
    // List.of: a snapshot, so a later parts.add() is a genuine change between polls.
    return scripted ?? Ok(TechnicianJobDetailDto(job: current, parts: List.of(parts)));
  }
}

ProviderContainer _container(TechnicianJobRepository repo) {
  final c = ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('first load fetches the single job by id via job(id) (never mine())', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([_d('EN_ROUTE')]);
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(repo.calls, 1);
      expect(repo.ids, ['b1']);
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'EN_ROUTE');
      expect(c.read(jobDetailProvider('b1')).value?.parts, isEmpty);
    });
  });

  test('polls every 5s while active; stops once terminal', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        _d('EN_ROUTE'),
        _d('ARRIVED'),
        _d('PAYMENT_RECEIVED'),
        _d('PAYMENT_RECEIVED'),
      ]);
      final c = _container(repo);
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
        _d('EN_ROUTE'),
        const Failure(FailureKind.network, 'blip'),
        _d('ARRIVED'),
      ]);
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5)); // tick -> Failure
      final afterBlip = c.read(jobDetailProvider('b1'));
      expect(afterBlip.value?.job.state, 'EN_ROUTE', reason: 'last-good retained on a poll failure');
      expect(afterBlip.hasError, isFalse);
      async.elapse(const Duration(seconds: 5)); // tick -> ARRIVED
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'ARRIVED');
    });
  });

  test('first-load Failure surfaces as AsyncError', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([const Failure(FailureKind.network, 'offline')]);
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).hasError, isTrue);
      expect(c.read(jobDetailProvider('b1')).error, isNot(isA<JobVanishedException>()),
          reason: 'a network failure is retryable, not "no longer assigned"');
    });
  });

  test('refetch() reloads immediately without flashing AsyncLoading and re-arms polling', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        _d('ARRIVED'),
        _d('DIAGNOSED'), // simulated result of a diagnose action, pulled by refetch()
        _d('CUSTOMER_APPROVED'),
      ]);
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'ARRIVED');

      final states = <bool>[];
      c.listen(jobDetailProvider('b1'), (_, next) => states.add(next.isLoading), fireImmediately: false);
      c.read(jobDetailProvider('b1').notifier).refetch();
      async.flushMicrotasks();
      expect(states, isNot(contains(true)), reason: 'refetch must never flash AsyncLoading');
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'DIAGNOSED');

      // polling continues after refetch's re-arm
      async.elapse(const Duration(seconds: 5));
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'CUSTOMER_APPROVED');
    });
  });

  test('no second fetch starts while a poll is in flight; the next tick is armed only after it completes', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(repo.calls, 1);
      repo.pending[0].complete(_d('EN_ROUTE'));
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 5)); // tick -> poll #2 starts, stays in flight
      expect(repo.calls, 2);
      async.elapse(const Duration(seconds: 30)); // slow network: no overlapping ticks
      expect(repo.calls, 2);

      repo.pending[1].complete(_d('ARRIVED'));
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'ARRIVED');
      expect(repo.calls, 2, reason: 're-armed, not fired immediately');
      async.elapse(const Duration(seconds: 5));
      expect(repo.calls, 3);
      repo.pending[2].complete(_d('ARRIVED'));
      async.flushMicrotasks();
    });
  });

  test('a stale response landing after a newer one is dropped (poll vs refetch)', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      repo.pending[0].complete(_d('ARRIVED'));
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 5)); // poll #2 in flight (will carry the OLD state)
      expect(repo.calls, 2);
      c.read(jobDetailProvider('b1').notifier).refetch(); // #3, issued after the action
      async.flushMicrotasks();
      expect(repo.calls, 3);

      repo.pending[2].complete(_d('DIAGNOSED')); // newer lands first
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'DIAGNOSED');

      repo.pending[1].complete(_d('ARRIVED')); // older lands late
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'DIAGNOSED', reason: 'the stale poll must not regress the card');

      // Exactly one timer chain survives.
      async.elapse(const Duration(seconds: 5));
      expect(repo.calls, 4);
      repo.pending[3].complete(_d('DIAGNOSED'));
      async.flushMicrotasks();
    });
  });

  test('pause() stops polling; resume() fetches once immediately and re-arms', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        _d('EN_ROUTE'),
        _d('ARRIVED'),
        _d('DIAGNOSED'),
      ]);
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(repo.calls, 1);

      c.read(jobDetailProvider('b1').notifier).pause();
      async.elapse(const Duration(minutes: 2));
      expect(repo.calls, 1, reason: 'no polling while backgrounded');

      c.read(jobDetailProvider('b1').notifier).resume();
      async.flushMicrotasks();
      expect(repo.calls, 2);
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'ARRIVED');

      async.elapse(const Duration(seconds: 5));
      expect(repo.calls, 3, reason: 'polling re-armed after resume');
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'DIAGNOSED');
    });
  });

  test('pause() while a poll is in flight: the completing poll does not re-arm', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      repo.pending[0].complete(_d('EN_ROUTE'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      expect(repo.calls, 2);

      c.read(jobDetailProvider('b1').notifier).pause();
      repo.pending[1].complete(_d('EN_ROUTE'));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));

      expect(repo.calls, 2);
    });
  });

  test('a poll differing only in photo urls does not notify listeners (state is not reassigned)', () {
    fakeAsync((async) {
      TechnicianJobDto withPhotoUrl(String url) => TechnicianJobDto.fromJson({
            'id': 'b1', 'bookingNumber': 'FC-1', 'state': 'REPAIR_IN_PROGRESS',
            'scheduledSlot': '2026-09-20T09:00:00.000Z',
            'service': {'name': 'Svc', 'requiredSkill': 'FAN'}, 'zone': {'name': 'Padra'},
            'visitFeePaise': 9900, 'laborPaise': 20000,
            'address': {'line1': 'x', 'line2': null, 'landmark': null, 'pincode': '391440'},
            'customer': {'maskedPhone': '••••••8384'},
            'photos': [
              {'kind': 'REPAIR_OLD_PART', 'capturedAt': '2026-09-20T09:00:00.000Z', 'url': url},
            ],
          });
      final repo = _ScriptedRepo([
        Ok(TechnicianJobDetailDto(job: withPhotoUrl('https://r2.example.com/a?sig=1'))),
        Ok(TechnicianJobDetailDto(job: withPhotoUrl('https://r2.example.com/a?sig=2'))), // fresh signed url, nothing else changed
      ]);
      final c = _container(repo);
      var notifications = 0;
      c.listen(jobDetailProvider('b1'), (_, next) => notifications++, fireImmediately: true);
      async.flushMicrotasks();
      final afterFirstLoad = notifications;

      async.elapse(const Duration(seconds: 5)); // poll #2: only the photo url differs
      expect(repo.calls, 2, reason: 'the poll still happens');
      expect(notifications, afterFirstLoad, reason: 'a photo-url-only diff must not notify listeners');
    });
  });

  test('404 on first load → AsyncError(JobVanishedException) and nothing is polled', () {
    fakeAsync((async) {
      final repo = _FakeRepo()..nextJobResult = const Failure(FailureKind.notFound, 'Job not found');
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).error, isA<JobVanishedException>());
      expect(container.read(jobDetailProvider('b1')).error.toString(), 'This job is no longer assigned to you.');
      async.elapse(const Duration(seconds: 30));
      expect(repo.jobCalls, 1);
    });
  });

  test('403 on first load → AsyncError(JobVanishedException) and nothing is polled', () {
    fakeAsync((async) {
      final repo = _FakeRepo()
        ..nextJobResult = const Failure(FailureKind.forbidden, 'This job is not assigned to you');
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).error, isA<JobVanishedException>());
      async.elapse(const Duration(seconds: 30));
      expect(repo.jobCalls, 1);
    });
  });

  test('403 during polling → AsyncError(JobVanishedException) and polling stops', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.forbidden, 'This job is not assigned to you');
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).error, isA<JobVanishedException>());
      final calls = repo.jobCalls;
      async.elapse(const Duration(seconds: 30));
      expect(repo.jobCalls, calls);
    });
  });

  test('404 during polling → AsyncError(JobVanishedException) and polling stops', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.notFound, 'Job not found');
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).error, isA<JobVanishedException>());
      final calls = repo.jobCalls;
      async.elapse(const Duration(seconds: 30));
      expect(repo.jobCalls, calls);
    });
  });

  test('a transient failure (network) during polling keeps the last good data and keeps polling', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.network, 'Network error. Check your connection.');
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).value?.job.id, 'b1');
      expect(container.read(jobDetailProvider('b1')).hasError, isFalse);
      final calls = repo.jobCalls;
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(repo.jobCalls, calls + 1);
    });
  });

  test('a 5xx (server) failure during polling is transient too: keeps the last good data, keeps polling', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.server, 'Unexpected response from the server.');
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).value?.job.id, 'b1');
      final calls = repo.jobCalls;
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(repo.jobCalls, calls + 1);
    });
  });

  test('a parts change between polls DOES notify (unlike a photo-url-only change)', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      var notifications = 0;
      container.listen(jobDetailProvider('b1'), (_, _) => notifications++);
      async.flushMicrotasks();
      final before = notifications;
      repo.parts.add(const JobPartLineDto(
          id: 'l1', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 1, ceilingPricePaise: 15000));
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(notifications, before + 1);
      expect(container.read(jobDetailProvider('b1')).value!.parts.single.id, 'l1');
    });
  });

  test('an unchanged poll (same job, same parts) does not notify listeners', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      var notifications = 0;
      container.listen(jobDetailProvider('b1'), (_, _) => notifications++);
      async.flushMicrotasks();
      final before = notifications;
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(repo.jobCalls, 2, reason: 'the poll still happens');
      expect(notifications, before);
    });
  });

  test('after a vanish, a successful refetch() recovers the job and re-arms polling', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.notFound, 'Job not found');
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).error, isA<JobVanishedException>());

      container.read(jobDetailProvider('b1').notifier).refetch();
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).value?.job.id, 'b1');
      final calls = repo.jobCalls;
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(repo.jobCalls, calls + 1, reason: 'polling resumed');
    });
  });

  test('resume() on a terminal job fetches once and does not re-arm', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        _d('PAYMENT_RECEIVED'),
      ]);
      final c = _container(repo);
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
