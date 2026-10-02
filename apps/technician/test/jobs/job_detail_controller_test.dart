import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
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

// The backend's job-scoped 404/403 (technician-jobs.service.ts) — a vanish keys on the CODE, never the message.
const _jobNotFound = Failure<TechnicianJobDetailDto>(FailureKind.notFound, 'Job not found', code: 'JOB_NOT_FOUND');
const _jobNotAssigned =
    Failure<TechnicianJobDetailDto>(FailureKind.forbidden, 'This job is not assigned to you', code: 'JOB_NOT_ASSIGNED');

/// Captures FlutterError.reportError calls for the duration of a test (and restores the handler).
List<FlutterErrorDetails> _captureReportedErrors() {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reported.add;
  addTearDown(() => FlutterError.onError = previous);
  return reported;
}

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

/// job(id) throws (a non-Failure error escaping the repository) while `throwing` is set; otherwise Ok.
class _ThrowingRepo extends TechnicianJobRepository {
  _ThrowingRepo() : super(Dio());
  bool throwing = false;
  int jobCalls = 0;
  String state = 'EN_ROUTE';
  @override
  Future<Result<List<TechnicianJobDto>>> mine() async => throw StateError(_mineForbidden);
  @override
  Future<Result<TechnicianJobDetailDto>> job(String id) async {
    jobCalls++;
    if (throwing) throw StateError('boom');
    return _d(state);
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
      final repo = _FakeRepo()..nextJobResult = _jobNotFound;
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
        ..nextJobResult = _jobNotAssigned;
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
      repo.nextJobResult = _jobNotAssigned;
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
      repo.nextJobResult = _jobNotFound;
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

  test('after a vanish, a successful refetch() of an UNCHANGED job clears the error (AsyncData) and re-arms polling', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      final seen = <AsyncValue<TechnicianJobDetailDto>>[];
      container.listen(jobDetailProvider('b1'), (_, next) => seen.add(next));
      async.flushMicrotasks();
      repo.nextJobResult = _jobNotFound;
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).error, isA<JobVanishedException>());
      final notificationsAfterVanish = seen.length;

      container.read(jobDetailProvider('b1').notifier).refetch(); // same job content as before the vanish
      async.flushMicrotasks();
      final recovered = container.read(jobDetailProvider('b1'));
      expect(recovered, isA<AsyncData<TechnicianJobDetailDto>>(), reason: 'a stale AsyncError must not linger');
      expect(recovered.hasError, isFalse);
      expect(recovered.value?.job.id, 'b1');
      expect(seen.length, notificationsAfterVanish + 1, reason: 'listeners (the screen) are told it recovered');
      expect(seen.last, isA<AsyncData<TechnicianJobDetailDto>>());

      final calls = repo.jobCalls;
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(repo.jobCalls, calls + 1, reason: 'polling resumed');
    });
  });

  test('a transient 403 blip then resume() (job unchanged) recovers to AsyncData', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = _jobNotAssigned;
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).error, isA<JobVanishedException>());

      container.read(jobDetailProvider('b1').notifier).pause();
      container.read(jobDetailProvider('b1').notifier).resume();
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')), isA<AsyncData<TechnicianJobDetailDto>>());
      expect(container.read(jobDetailProvider('b1')).hasError, isFalse);
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

  test('refetch() reports the outcome: true on Ok (changed or unchanged), false on a Failure', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      final results = <bool>[];
      c.read(jobDetailProvider('b1').notifier).refetch().then(results.add); // unchanged job → still confirmed
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.network, 'Network error. Check your connection.');
      c.read(jobDetailProvider('b1').notifier).refetch().then(results.add);
      async.flushMicrotasks();
      repo.current = _j('ARRIVED');
      c.read(jobDetailProvider('b1').notifier).refetch().then(results.add); // changed → applied
      async.flushMicrotasks();
      expect(results, [true, false, true]);
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'ARRIVED');
    });
  });

  test('refetch() whose response is dropped because a NEWER success was already applied reports true (superseded, not failed)', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.pending[0].complete(_d('ARRIVED'));
      async.flushMicrotasks();
      final results = <bool>[];
      c.read(jobDetailProvider('b1').notifier).refetch().then(results.add); // #2 (older)
      c.read(jobDetailProvider('b1').notifier).refetch().then(results.add); // #3 (newer)
      async.flushMicrotasks();
      repo.pending[2].complete(_d('DIAGNOSED'));
      async.flushMicrotasks();
      repo.pending[1].complete(_d('ARRIVED')); // lands late → dropped, but a newer success is on screen
      async.flushMicrotasks();
      expect(results, [true, true]);
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'DIAGNOSED');
      c.read(jobDetailProvider('b1').notifier).pause();
    });
  });

  test('a refetch issued, a newer poll lands first (Ok), the refetch response dropped → refetch() returns true', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.pending[0].complete(_d('ARRIVED'));
      async.flushMicrotasks();
      final results = <bool>[];
      final notifier = c.read(jobDetailProvider('b1').notifier);
      notifier.refetch().then(results.add); // #2 — the refetch after a cart edit
      async.flushMicrotasks();
      // The poll timer was re-armed by the first load; a poll (#3) goes out while the refetch is in flight.
      async.elapse(jobPollInterval);
      expect(repo.calls, 3);
      repo.pending[2].complete(_d('ARRIVED')); // the newer poll lands first (Ok)
      async.flushMicrotasks();
      repo.pending[1].complete(_d('ARRIVED')); // the refetch's response lands late → dropped
      async.flushMicrotasks();
      expect(results, [true]);
      notifier.pause();
    });
  });

  test('a refetch that fails AFTER a newer success was applied still reports true; with no newer success it reports false', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.pending[0].complete(_d('ARRIVED'));
      async.flushMicrotasks();
      final results = <bool>[];
      final notifier = c.read(jobDetailProvider('b1').notifier);
      notifier.refetch().then(results.add); // #2
      notifier.refetch().then(results.add); // #3
      async.flushMicrotasks();
      repo.pending[2].complete(_d('ARRIVED')); // #3 Ok
      async.flushMicrotasks();
      repo.pending[1].complete(const Failure(FailureKind.network, 'blip')); // #2 fails, but #3 (newer) succeeded
      async.flushMicrotasks();
      expect(results, [true, true]);

      notifier.refetch().then(results.add); // #4 fails with nothing newer
      async.flushMicrotasks();
      repo.pending[3].complete(const Failure(FailureKind.network, 'blip'));
      async.flushMicrotasks();
      expect(results, [true, true, false]);
      notifier.pause();
    });
  });

  test('a job() that THROWS keeps the last good state, keeps polling, and refetch() reports false', () {
    fakeAsync((async) {
      final repo = _ThrowingRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'EN_ROUTE');

      final reported = _captureReportedErrors();
      repo.throwing = true;
      async.elapse(jobPollInterval); // a poll whose fetch throws
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'EN_ROUTE', reason: 'keep last good');
      // Never swallowed silently: the throw (exception + stack only) reaches FlutterError.reportError.
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      expect(reported.single.library, 'fixcare jobs');
      expect(reported.single.stack, isNotNull);
      expect(c.read(jobDetailProvider('b1')).hasError, isFalse);
      final results = <bool>[];
      c.read(jobDetailProvider('b1').notifier).refetch().then(results.add);
      async.flushMicrotasks();
      expect(results, [false]);

      repo.throwing = false;
      repo.state = 'ARRIVED';
      final calls = repo.jobCalls;
      async.elapse(jobPollInterval);
      expect(repo.jobCalls, calls + 1, reason: 'the poll chain survived the throw');
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'ARRIVED');
    });
  });

  test('a vanish keys on the code only: a 403 with the old "not assigned" MESSAGE but no job code is an access error, not a vanish', () {
    fakeAsync((async) {
      final repo = _FakeRepo()
        ..nextJobResult = const Failure(FailureKind.forbidden, 'This job is not assigned to you', code: 'FORBIDDEN');
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).error, isA<JobAccessException>());
      expect(c.read(jobDetailProvider('b1')).error, isNot(isA<JobVanishedException>()));
    });
  });

  test('a 404 WITHOUT a job code (route-not-found on an older backend) during polling is transient: keep last good, keep polling', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.notFound, 'Route GET:/technician/jobs/b1 not found');
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      final s = c.read(jobDetailProvider('b1'));
      expect(s.hasError, isFalse);
      expect(s.value?.job.id, 'b1');
      final calls = repo.jobCalls;
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(repo.jobCalls, calls + 1, reason: 'still polling');
    });
  });

  test('a 404 WITHOUT a job code on first load → a plain Exception (generic error + Retry), not a vanish', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([const Failure(FailureKind.notFound, 'Route GET:/technician/jobs/b1 not found')]);
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {}, fireImmediately: true);
      async.flushMicrotasks();
      final s = c.read(jobDetailProvider('b1'));
      expect(s.hasError, isTrue);
      expect(s.error, isA<Exception>());
      expect(s.error, isNot(isA<JobVanishedException>()));
      expect(s.error, isNot(isA<JobAccessException>()));
      c.read(jobDetailProvider('b1').notifier).pause();
    });
  });

  test('jobFetchOkSeq is set to the request seq of every successful fetch — applied OR unchanged', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      final okSeqs = <int>[];
      c.listen<int>(jobFetchOkSeqProvider('b1'), (_, next) => okSeqs.add(next));
      async.flushMicrotasks();
      final notifier = c.read(jobDetailProvider('b1').notifier);

      notifier.refetch(); // unchanged job → skipped, but still a success
      final unchangedSeq = notifier.lastIssuedSeq;
      async.flushMicrotasks();
      expect(c.read(jobFetchOkSeqProvider('b1')), unchangedSeq);

      repo.current = _j('ARRIVED');
      notifier.refetch(); // changed → applied
      final appliedSeq = notifier.lastIssuedSeq;
      async.flushMicrotasks();
      expect(appliedSeq, greaterThan(unchangedSeq));
      expect(c.read(jobFetchOkSeqProvider('b1')), appliedSeq);

      repo.nextJobResult = const Failure(FailureKind.network, 'blip');
      notifier.refetch(); // a failure does not move it
      async.flushMicrotasks();
      expect(c.read(jobFetchOkSeqProvider('b1')), appliedSeq);
      expect(okSeqs, containsAllInOrder([unchangedSeq, appliedSeq]));
      notifier.pause();
    });
  });

  test('lastIssuedSeq is the seq the latest refetch() went out with (fixed at issue time)', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.pending[0].complete(_d('ARRIVED'));
      async.flushMicrotasks();
      final notifier = c.read(jobDetailProvider('b1').notifier);
      notifier.refetch();
      final first = notifier.lastIssuedSeq;
      async.elapse(jobPollInterval); // a poll goes out — it does not move lastIssuedSeq
      expect(notifier.lastIssuedSeq, first);
      notifier.refetch();
      expect(notifier.lastIssuedSeq, greaterThan(first));
      for (final p in repo.pending.skip(1)) {
        p.complete(_d('ARRIVED'));
      }
      async.flushMicrotasks();
      notifier.pause();
    });
  });

  test('403 other than "not assigned" (e.g. suspended) → AsyncError(JobAccessException) with the backend message; polling stops', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.forbidden, 'Verified technician required');
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      final s = c.read(jobDetailProvider('b1'));
      expect(s.error, isA<JobAccessException>());
      expect(s.error, isNot(isA<JobVanishedException>()));
      expect(s.error.toString(), 'Verified technician required');
      final calls = repo.jobCalls;
      async.elapse(const Duration(seconds: 30));
      expect(repo.jobCalls, calls, reason: 'polling stopped');
    });
  });

  test('403 "Verified technician required" on first load → AsyncError(JobAccessException), not retried', () {
    fakeAsync((async) {
      final repo = _FakeRepo()..nextJobResult = const Failure(FailureKind.forbidden, 'Verified technician required');
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).error, isA<JobAccessException>());
      expect(c.read(jobDetailProvider('b1')).error.toString(), 'Verified technician required');
      async.elapse(const Duration(seconds: 30));
      expect(repo.jobCalls, 1);
    });
  });

  test('a refetch that lands before the first load keeps the newer response (first load never regresses it)', () {
    fakeAsync((async) {
      final repo = _GatedRepo();
      final c = _container(repo);
      c.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      expect(repo.calls, 1); // first load in flight
      c.read(jobDetailProvider('b1').notifier).resume(); // e.g. foregrounded mid-load
      async.flushMicrotasks();
      expect(repo.calls, 2);
      repo.pending[1].complete(_d('DIAGNOSED')); // the newer one lands first
      async.flushMicrotasks();
      repo.pending[0].complete(_d('ARRIVED')); // the first load lands late
      async.flushMicrotasks();
      expect(c.read(jobDetailProvider('b1')).value?.job.state, 'DIAGNOSED');
      c.read(jobDetailProvider('b1').notifier).pause();
    });
  });
}
