import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/token_store.dart';
import '../../profile/data/technician_profile_repository.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

part 'auth_controller.g.dart';

/// Owns the session lifecycle: boot from storage, OTP verify, logout, and the
/// interceptor's session-lost signal. The auth interceptor is the ONLY place a
/// token refresh happens; this controller only reacts to the outcome.
///
/// keepAlive: this is app-wide session state that must live for the whole app
/// session. It is read from several places (the router bridge, the dio
/// interceptor's onAuthLost, screens) at different times; an auto-dispose
/// controller would risk being torn down and re-booting the session between
/// uses. Keep the lifetime explicit rather than relying on an incidental
/// long-lived listener.
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  @override
  Future<Session> build() async {
    final access = await ref.read(tokenStoreProvider).readAccess();
    if (access == null) return const SessionUnauthenticated();
    return _hydrate();
  }

  /// Token present → fetch the real profile. 401 = stale token → clear + logout.
  /// network/other = stay logged in but unhydrated (option a): don't eject the
  /// user on a transient blip. The verification gate keys on profile.status
  /// (TechnicianStatus), so an unhydrated technician must NEVER be treated as
  /// VERIFIED — fall back to a PENDING placeholder, not the real (unknown) status.
  Future<Session> _hydrate() async {
    final r = await ref.read(technicianProfileRepositoryProvider).getProfile();
    switch (r) {
      case Ok(value: final profile):
        return SessionAuthenticated(profile, hydrated: true);
      case Failure(kind: FailureKind.unauthorized):
        await ref.read(tokenStoreProvider).clear();
        return const SessionUnauthenticated();
      case Failure():
        return const SessionAuthenticated(
          TechnicianProfileDto(id: '', role: 'TECHNICIAN', name: '', skills: [], status: 'PENDING'),
          hydrated: false,
        );
    }
  }

  Future<Result<SendOtpResponse>> requestOtp(String phone) =>
      ref.read(authRepositoryProvider).sendOtp(phone);

  Future<Result<void>> submitOtp(String phone, String code) async {
    final r = await ref.read(authRepositoryProvider).verifyOtp(phone, code);
    if (r is Ok<VerifyResponse>) {
      _newSession();
      final store = ref.read(tokenStoreProvider);
      await store.save(access: r.value.accessToken, refresh: r.value.refreshToken);
      await store.savePhone(phone);
      // verify's user has no name/skills — fetch the real profile so the
      // verification gate (isVerified) works off the real TechnicianStatus.
      state = AsyncData(await _hydrate());
      return const Ok(null);
    }
    final f = r as Failure<VerifyResponse>;
    return Failure(f.kind, f.message, code: f.code);
  }

  Future<void> logout() async {
    final refresh = await ref.read(tokenStoreProvider).readRefresh();
    if (refresh != null) {
      // Best-effort server-side revoke; local clear happens regardless.
      await ref.read(authRepositoryProvider).logout(refresh);
    }
    _newSession();
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(SessionUnauthenticated());
  }

  /// Called by the auth interceptor when a refresh fails: drop to
  /// unauthenticated so the router pushes the phone screen.
  void onAuthLost() {
    _newSession();
    state = const AsyncData(SessionUnauthenticated());
  }

  /// Bumped whenever the session changes (login, logout, auth lost). A profile request that started under an
  /// older epoch must not touch state or tokens when it lands — it belongs to a session that no longer exists.
  int _epoch = 0;
  Future<Result<TechnicianProfileDto>>? _refreshing;

  /// Invalidates any in-flight refresh and stops a new session from joining it.
  void _newSession() {
    _epoch++;
    _refreshing = null;
  }

  /// Re-reads the profile so status changes made by ops (verified, sent back, suspended, reinstated) reach
  /// the home gate without a re-login. Concurrent callers share one request. A transient failure keeps the
  /// current session (never eject on a blip); 401 signs out.
  Future<Result<TechnicianProfileDto>> refreshProfile() {
    final existing = _refreshing;
    if (existing != null) return existing;
    final f = _refresh();
    _refreshing = f;
    // Clear only our own entry — a new session may already have started a different refresh.
    void clear() {
      if (identical(_refreshing, f)) _refreshing = null;
    }
    f.then((_) => clear(), onError: (Object _) => clear());
    return f;
  }

  /// Feeds a profile the app already has (e.g. the submit response) straight into the session — no extra fetch.
  /// Applies only to the live session of the SAME technician: signed out, or a different id (a logout/login landed
  /// while the caller's request was in flight), is ignored.
  void applyProfile(TechnicianProfileDto profile) {
    if (!ref.mounted || state.hasError) return;
    final now = state.value;
    if (now is! SessionAuthenticated || now.profile.id != profile.id) return;
    if (now.hydrated && now.profile == profile) return;
    state = AsyncData(SessionAuthenticated(profile, hydrated: true));
  }

  Future<Result<TechnicianProfileDto>> _refresh() async {
    // Never the stale value of an error state (Riverpod 3 keeps the previous value on AsyncError).
    final before = state.hasError ? null : state.value;
    if (before is! SessionAuthenticated) return const Failure(FailureKind.unauthorized, 'Not signed in.');
    final epoch = _epoch;
    final r = await ref.read(technicianProfileRepositoryProvider).getProfile();
    if (!ref.mounted || epoch != _epoch) return r;
    // A logout / session loss that landed while the request was in flight wins — never resurrect a session.
    final now = state.hasError ? null : state.value;
    if (now is! SessionAuthenticated) return r;
    switch (r) {
      case Ok(value: final profile):
        if (!(now.hydrated && now.profile == profile)) state = AsyncData(SessionAuthenticated(profile, hydrated: true));
      case Failure(kind: FailureKind.unauthorized):
        await ref.read(tokenStoreProvider).clear();
        if (ref.mounted && epoch == _epoch) state = const AsyncData(SessionUnauthenticated());
      case Failure():
        break;
    }
    return r;
  }
}
