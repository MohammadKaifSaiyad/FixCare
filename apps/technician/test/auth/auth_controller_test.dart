import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/data/auth_repository.dart';
import 'package:fixcare_technician/features/auth/domain/session.dart';
import 'package:fixcare_technician/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_repository.dart';

class _FakeProfileRepo extends TechnicianProfileRepository {
  _FakeProfileRepo(this._result) : super(Dio());
  final Result<TechnicianProfileDto> _result;
  @override
  Future<Result<TechnicianProfileDto>> getProfile() async => _result;
}

class _FailingAuthRepo extends AuthRepository {
  _FailingAuthRepo() : super(Dio());
  @override
  Future<Result<VerifyResponse>> verifyOtp(String phone, String otp) async =>
      const Failure(FailureKind.unauthorized, 'Invalid or expired OTP', code: 'UNAUTHORIZED');
}

/// Returns queued results in order (the last one repeats); [gate], when set, holds every call until completed.
class _SeqProfileRepo extends TechnicianProfileRepository {
  _SeqProfileRepo(this._results) : super(Dio());
  final List<Result<TechnicianProfileDto>> _results;
  int calls = 0;
  Completer<void>? gate;
  @override
  Future<Result<TechnicianProfileDto>> getProfile() async {
    final r = _results[calls < _results.length ? calls : _results.length - 1];
    calls++;
    if (gate case final g?) await g.future;
    return r;
  }
}

/// Logout / verify succeed; the profile repo (see [_GatedProfileRepo]) decides the rest.
class _OkAuthRepo extends AuthRepository {
  _OkAuthRepo() : super(Dio());
  @override
  Future<Result<void>> logout(String refreshToken) async => const Ok(null);
  @override
  Future<Result<VerifyResponse>> verifyOtp(String phone, String otp) async =>
      const Ok(VerifyResponse(accessToken: 'a2', refreshToken: 'r2', user: UserDto(id: 'u2', role: 'TECHNICIAN', status: 'ACTIVE')));
}

/// Call N (0-based) is held until [gate] completes; every call returns its queued result.
class _GatedProfileRepo extends TechnicianProfileRepository {
  _GatedProfileRepo(this._results, {required this.gateCall}) : super(Dio());
  final List<Result<TechnicianProfileDto>> _results;
  final int gateCall;
  final gate = Completer<void>();
  int calls = 0;
  @override
  Future<Result<TechnicianProfileDto>> getProfile() async {
    final i = calls++;
    final r = _results[i < _results.length ? i : _results.length - 1];
    if (i == gateCall) await gate.future;
    return r;
  }
}

TechnicianProfileDto _p(String status) => TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: const ['AC'], status: status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backing = <String, String>{};

  void mockStorage() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write': backing[call.arguments['key'] as String] = call.arguments['value'] as String; return null;
          case 'read': return backing[call.arguments['key'] as String];
          case 'delete': backing.remove(call.arguments['key'] as String); return null;
          case 'deleteAll': backing.clear(); return null;
          case 'readAll': return Map<String, String>.from(backing);
          case 'containsKey': return backing.containsKey(call.arguments['key'] as String);
        }
        return null;
      },
    );
  }

  setUp(() { backing.clear(); mockStorage(); });

  Future<Session> boot(Result<TechnicianProfileDto> profileResult) async {
    final container = ProviderContainer(overrides: [
      technicianProfileRepositoryProvider.overrideWithValue(_FakeProfileRepo(profileResult)),
    ]);
    addTearDown(container.dispose);
    return container.read(authControllerProvider.future);
  }

  test('no token -> Unauthenticated', () async {
    final s = await boot(const Ok(TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: ['FAN'], status: 'VERIFIED')));
    expect(s, isA<SessionUnauthenticated>());
  });

  test('token + VERIFIED profile -> Authenticated with isVerified true', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Ok(TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: ['FAN'], status: 'VERIFIED')));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, true);
    expect(a.isVerified, true);
  });

  test('token + PENDING profile -> Authenticated with isVerified false', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Ok(TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: '', skills: [], status: 'PENDING')));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, true);
    expect(a.isVerified, false);
  });

  test('token + 401 -> tokens cleared, Unauthenticated', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Failure(FailureKind.unauthorized, 'stale'));
    expect(s, isA<SessionUnauthenticated>());
    expect(backing['fixcare.access'], isNull);
  });

  test('token + network fail -> Authenticated NOT hydrated, PENDING fallback (isVerified false)', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Failure(FailureKind.network, 'offline'));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, false);
    expect(a.isVerified, false);
    expect(a.status, 'PENDING');
    expect(backing['fixcare.access'], 'a'); // not cleared
  });

  test('submitOtp Failure keeps the backend code (never dropped when re-wrapped)', () async {
    final container = ProviderContainer(overrides: [
      technicianProfileRepositoryProvider.overrideWithValue(_FakeProfileRepo(const Failure(FailureKind.unauthorized, 'x'))),
      authRepositoryProvider.overrideWithValue(_FailingAuthRepo()),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final r = await container.read(authControllerProvider.notifier).submitOtp('9999999999', '123456') as Failure;
    expect(r.kind, FailureKind.unauthorized);
    expect(r.message, 'Invalid or expired OTP');
    expect(r.code, 'UNAUTHORIZED');
  });

  Future<(ProviderContainer, _SeqProfileRepo)> booted(List<Result<TechnicianProfileDto>> results) async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final repo = _SeqProfileRepo(results);
    final container = ProviderContainer(overrides: [technicianProfileRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    return (container, repo);
  }

  Session? sessionOf(ProviderContainer c) => c.read(authControllerProvider).value;

  test('refreshProfile: a status change updates the session', () async {
    final (c, _) = await booted([Ok(_p('KYC_SUBMITTED')), Ok(_p('VERIFIED'))]);
    final r = await c.read(authControllerProvider.notifier).refreshProfile();
    expect(r, isA<Ok<TechnicianProfileDto>>());
    expect((sessionOf(c)! as SessionAuthenticated).status, 'VERIFIED');
  });

  test('refreshProfile: an unchanged profile does not re-emit the session', () async {
    final (c, _) = await booted([Ok(_p('KYC_SUBMITTED'))]);
    var emits = 0;
    c.listen(authControllerProvider, (_, _) => emits++);
    await c.read(authControllerProvider.notifier).refreshProfile();
    expect(emits, 0);
  });

  test('refreshProfile: a network failure keeps the current session', () async {
    final (c, _) = await booted([Ok(_p('KYC_SUBMITTED')), const Failure(FailureKind.network, 'down')]);
    final r = await c.read(authControllerProvider.notifier).refreshProfile();
    expect((r as Failure).kind, FailureKind.network);
    expect((sessionOf(c)! as SessionAuthenticated).status, 'KYC_SUBMITTED');
  });

  test('refreshProfile: 401 clears tokens and signs out', () async {
    final (c, _) = await booted([Ok(_p('VERIFIED')), const Failure(FailureKind.unauthorized, 'stale')]);
    await c.read(authControllerProvider.notifier).refreshProfile();
    expect(sessionOf(c), isA<SessionUnauthenticated>());
    expect(backing['fixcare.access'], isNull);
  });

  test('refreshProfile: an unhydrated session becomes hydrated', () async {
    final (c, _) = await booted([const Failure(FailureKind.network, 'down'), Ok(_p('PENDING'))]);
    expect((sessionOf(c)! as SessionAuthenticated).hydrated, false);
    await c.read(authControllerProvider.notifier).refreshProfile();
    expect((sessionOf(c)! as SessionAuthenticated).hydrated, true);
  });

  test('applyProfile: applies the given profile when the session has the same id (no extra fetch)', () async {
    final (c, repo) = await booted([Ok(_p('PENDING'))]);
    c.read(authControllerProvider.notifier).applyProfile(_p('KYC_SUBMITTED'));
    final a = sessionOf(c)! as SessionAuthenticated;
    expect(a.status, 'KYC_SUBMITTED');
    expect(a.hydrated, true);
    expect(repo.calls, 1); // only the boot fetch
  });

  test('applyProfile: ignored when signed out', () async {
    final c = ProviderContainer(overrides: [technicianProfileRepositoryProvider.overrideWithValue(_SeqProfileRepo([Ok(_p('PENDING'))]))]);
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future); // no token stored → unauthenticated
    c.read(authControllerProvider.notifier).applyProfile(_p('KYC_SUBMITTED'));
    expect(sessionOf(c), isA<SessionUnauthenticated>());
  });

  test('applyProfile: ignored after logout and for a different technician id', () async {
    final (c, _) = await booted([Ok(_p('PENDING'))]);
    final n = c.read(authControllerProvider.notifier);
    n.applyProfile(const TechnicianProfileDto(id: 'someone-else', role: 'TECHNICIAN', name: 'X', skills: [], status: 'VERIFIED'));
    expect((sessionOf(c)! as SessionAuthenticated).status, 'PENDING');
    n.onAuthLost();
    n.applyProfile(_p('KYC_SUBMITTED'));
    expect(sessionOf(c), isA<SessionUnauthenticated>());
  });

  test('refreshProfile: concurrent calls share one request', () async {
    final (c, repo) = await booted([Ok(_p('KYC_SUBMITTED')), Ok(_p('VERIFIED'))]);
    final n = c.read(authControllerProvider.notifier);
    await Future.wait([n.refreshProfile(), n.refreshProfile(), n.refreshProfile()]);
    expect(repo.calls, 2); // 1 boot + 1 shared refresh
  });

  test('refreshProfile: a logout while the request is in flight is not undone', () async {
    final (c, repo) = await booted([Ok(_p('KYC_SUBMITTED')), Ok(_p('VERIFIED'))]);
    repo.gate = Completer<void>();
    final pending = c.read(authControllerProvider.notifier).refreshProfile();
    c.read(authControllerProvider.notifier).onAuthLost();
    repo.gate!.complete();
    await pending;
    expect(sessionOf(c), isA<SessionUnauthenticated>());
  });

  Future<(ProviderContainer, _GatedProfileRepo)> bootedGated(List<Result<TechnicianProfileDto>> results) async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final repo = _GatedProfileRepo(results, gateCall: 1);
    final c = ProviderContainer(overrides: [
      technicianProfileRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(_OkAuthRepo()),
    ]);
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    return (c, repo);
  }

  test('refreshProfile: a profile fetched for a previous session is NOT applied to the next login', () async {
    // call 0 = boot, 1 = the gated (old session) refresh, 2 = hydrate after the new login
    final (c, repo) = await bootedGated([Ok(_p('KYC_SUBMITTED')), Ok(_p('VERIFIED')), Ok(_p('PENDING'))]);
    final n = c.read(authControllerProvider.notifier);
    final pending = n.refreshProfile();
    await n.logout();
    await n.submitOtp('9999999999', '123456'); // a new session, hydrated as PENDING
    expect((sessionOf(c)! as SessionAuthenticated).status, 'PENDING');
    repo.gate.complete();
    await pending;
    expect((sessionOf(c)! as SessionAuthenticated).status, 'PENDING'); // the old VERIFIED profile was dropped
  });

  test('refreshProfile: a 401 for a previous session does not clear the new session\'s tokens', () async {
    final (c, repo) = await bootedGated([Ok(_p('KYC_SUBMITTED')), const Failure(FailureKind.unauthorized, 'stale'), Ok(_p('PENDING'))]);
    final n = c.read(authControllerProvider.notifier);
    final pending = n.refreshProfile();
    await n.logout();
    await n.submitOtp('9999999999', '123456');
    repo.gate.complete();
    await pending;
    expect(sessionOf(c), isA<SessionAuthenticated>());
    expect(backing['fixcare.access'], 'a2');
  });

  test('refreshProfile when signed out makes no request', () async {
    final repo = _SeqProfileRepo([Ok(_p('VERIFIED'))]);
    final c = ProviderContainer(overrides: [technicianProfileRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    final r = await c.read(authControllerProvider.notifier).refreshProfile();
    expect((r as Failure).kind, FailureKind.unauthorized);
    expect(repo.calls, 0);
  });
}
